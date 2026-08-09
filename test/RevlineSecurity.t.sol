// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {IDiamondCut} from "@diamond/interfaces/IDiamondCut.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IPausable} from "@lattice/interfaces/security/IPausable.sol";
import {IReentrancyGuard} from "@lattice/interfaces/security/IReentrancyGuard.sol";
import {DeployRevline} from "../script/DeployRevline.s.sol";
import {RevlineRoles} from "../src/RevlineRoles.sol";
import {RevlineTypes} from "../src/RevlineTypes.sol";
import {CreditFacet} from "../src/facets/CreditFacet.sol";
import {InvoiceFacet} from "../src/facets/InvoiceFacet.sol";
import {MerchantFacet} from "../src/facets/MerchantFacet.sol";
import {IRevlineErrors} from "../src/interfaces/IRevlineErrors.sol";
import {CreditMath} from "../src/libraries/CreditMath.sol";
import {USDCTransferLib} from "../src/libraries/USDCTransferLib.sol";
import {RevlineTestBase} from "./helpers/RevlineTestBase.t.sol";
import {AdversarialUSDC} from "./mocks/AdversarialUSDC.sol";

contract UpgradeProbe {
    function value() external pure returns (uint256) {
        return 42;
    }
}

contract RevlineSecurityTest is RevlineTestBase {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    uint256 internal constant INVOICE_AMOUNT = 500e6;

    CreditFacet internal creditFacet;
    InvoiceFacet internal invoiceFacet;
    MerchantFacet internal merchantFacet;

    function setUp() public override {
        super.setUp();
        vm.warp(100 days + 1 hours);
        _bindFacets();
    }

    function test_deploySucceeds() public view {
        assertTrue(address(diamond).code.length > 0);
    }

    function test_adminHasDefaultAdminRole() public view {
        assertTrue(IAccessControl(address(diamond)).hasRole(DEFAULT_ADMIN_ROLE, admin));
    }

    function test_adminHasUnderwriterRole() public view {
        assertTrue(IAccessControl(address(diamond)).hasRole(RevlineRoles.UNDERWRITER_ROLE, admin));
    }

    function test_nonAdminCannotDiamondCut() public {
        FacetCut[] memory cuts = new FacetCut[](0);

        vm.prank(customer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, customer, DEFAULT_ADMIN_ROLE
            )
        );
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
    }

    function test_adminCanDiamondCut() public {
        UpgradeProbe probe = new UpgradeProbe();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = UpgradeProbe.value.selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(probe), action: FacetCutAction.Add, functionSelectors: selectors});

        vm.prank(admin);
        diamondCut.diamondCut(cuts, address(0), "");

        assertEq(UpgradeProbe(address(diamond)).value(), 42);
        assertEq(loupe.facetAddress(UpgradeProbe.value.selector), address(probe));
    }

    function test_adminCanPauseAndUnpause() public {
        vm.prank(admin);
        pausable.pause();
        assertTrue(pausable.paused());

        vm.prank(admin);
        pausable.unpause();
        assertFalse(pausable.paused());
    }

    function test_pauseMatrixBlocksMutationsButAllowsUnderwritingAndViews() public {
        uint256 invoiceId = _prepareEligibleMerchant();
        address otherMerchant = makeAddr("otherMerchant");

        vm.prank(admin);
        pausable.pause();

        vm.prank(otherMerchant);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        merchantFacet.registerMerchant("Other");

        vm.prank(merchant);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        merchantFacet.setPayoutAddress(otherMerchant);

        vm.prank(merchant);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        invoiceFacet.createInvoice(1e6, 0, "paused");

        vm.prank(merchant);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        invoiceFacet.cancelInvoice(invoiceId);

        vm.prank(customer);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        invoiceFacet.payInvoice(invoiceId);

        vm.prank(merchant);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        creditFacet.drawAdvance(100e6);

        vm.prank(admin);
        merchantFacet.setCreditEnabled(merchant, false);

        assertTrue(pausable.paused());
        assertFalse(merchantFacet.getMerchant(merchant).creditEnabled);
        assertEq(merchantFacet.trailingRevenue(merchant), INVOICE_AMOUNT);
        assertEq(invoiceFacet.getInvoice(invoiceId).merchant, merchant);
        assertEq(invoiceFacet.getMerchantInvoiceIds(merchant).length, 2);
        assertEq(creditFacet.creditQuote(merchant).creditLimit, 100e6);
        assertEq(creditFacet.getMerchantAdvanceIds(merchant).length, 0);
        assertEq(creditFacet.poolStats().managedAssets, LARGE_BALANCE);
    }

    function test_nonAdminCannotPauseOrUnpause() public {
        vm.prank(customer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, customer, DEFAULT_ADMIN_ROLE
            )
        );
        pausable.pause();

        vm.prank(admin);
        pausable.pause();

        vm.prank(customer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, customer, DEFAULT_ADMIN_ROLE
            )
        );
        pausable.unpause();
    }

    function test_nonUnderwriterCannotSetCreditEnabled() public {
        vm.prank(merchant);
        merchantFacet.registerMerchant("Acme");

        vm.prank(customer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, customer, RevlineRoles.UNDERWRITER_ROLE
            )
        );
        merchantFacet.setCreditEnabled(merchant, true);
    }

    function test_customerCannotCancelMerchantInvoice() public {
        vm.prank(merchant);
        merchantFacet.registerMerchant("Acme");
        vm.prank(merchant);
        uint256 invoiceId = invoiceFacet.createInvoice(1e6, 0, "auth");

        vm.prank(customer);
        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.NotInvoiceMerchant.selector, invoiceId, customer));
        invoiceFacet.cancelInvoice(invoiceId);
    }

    function test_transferFromCallbackCannotReenterPayInvoice() public {
        AdversarialUSDC token = _deployWithAdversarialToken();
        uint256 invoiceId = _createAdversarialInvoice(token, 50e6);
        token.configure(
            AdversarialUSDC.Behavior.Reenter, address(diamond), abi.encodeCall(InvoiceFacet.payInvoice, (invoiceId))
        );

        vm.prank(customer);
        invoiceFacet.payInvoice(invoiceId);

        assertFalse(token.callbackSucceeded());
        assertEq(token.callbackRevertSelector(), IReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        assertEq(uint256(invoiceFacet.getInvoice(invoiceId).status), uint256(RevlineTypes.InvoiceStatus.Paid));
    }

    function test_transferCallbackCannotReenterDrawAdvance() public {
        AdversarialUSDC token = _deployWithAdversarialToken();
        _prepareAdversarialEligibleMerchant(token);
        token.configure(
            AdversarialUSDC.Behavior.Reenter, address(diamond), abi.encodeCall(CreditFacet.drawAdvance, (1e6))
        );

        vm.prank(merchant);
        uint256 advanceId = creditFacet.drawAdvance(100e6);

        assertFalse(token.callbackSucceeded());
        assertEq(token.callbackRevertSelector(), IReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        assertEq(creditFacet.getAdvance(advanceId).principal, 100e6);
    }

    function test_transferFromRejectsExternalCallFailure() public {
        AdversarialUSDC token = _deployWithAdversarialToken();
        uint256 invoiceId = _createAdversarialInvoice(token, 50e6);
        token.configure(AdversarialUSDC.Behavior.RevertCall, address(0), "");

        vm.prank(customer);
        vm.expectRevert(abi.encodeWithSelector(USDCTransferLib.USDCTransferFailed.selector, address(token)));
        invoiceFacet.payInvoice(invoiceId);
    }

    function test_transferFromRejectsExplicitFalseReturn() public {
        AdversarialUSDC token = _deployWithAdversarialToken();
        uint256 invoiceId = _createAdversarialInvoice(token, 50e6);
        token.configure(AdversarialUSDC.Behavior.ReturnFalse, address(0), "");

        vm.prank(customer);
        vm.expectRevert(abi.encodeWithSelector(USDCTransferLib.USDCTransferFailed.selector, address(token)));
        invoiceFacet.payInvoice(invoiceId);
    }

    function test_transferRejectsExternalCallFailureAndRollsBackDraw() public {
        _assertDrawTransferFailure(AdversarialUSDC.Behavior.RevertCall);
    }

    function test_transferRejectsExplicitFalseReturnAndRollsBackDraw() public {
        _assertDrawTransferFailure(AdversarialUSDC.Behavior.ReturnFalse);
    }

    function test_transferFromRejectsEmptyReturnFromAddressWithoutCode() public {
        address noCode = makeAddr("noCodeToken");
        diamond = new DeployRevline().deploy(noCode, admin);
        _bindFacets();
        vm.prank(merchant);
        merchantFacet.registerMerchant("Acme");
        vm.prank(merchant);
        uint256 invoiceId = invoiceFacet.createInvoice(50e6, 0, "no-code");

        vm.prank(customer);
        vm.expectRevert(abi.encodeWithSelector(USDCTransferLib.USDCTransferFailed.selector, noCode));
        invoiceFacet.payInvoice(invoiceId);
    }

    function testFuzz_creditLimitNeverExceedsCap(uint256 revenue) public pure {
        revenue %= type(uint256).max / CreditMath.ADVANCE_RATE_BPS + 1;
        assert(CreditMath.creditLimit(revenue) <= CreditMath.MAX_ADVANCE);
    }

    function testFuzz_repaymentNeverExceedsDebtOrGrossShare(uint256 gross, uint256 remainingOwed) public pure {
        gross %= type(uint256).max / CreditMath.REPAYMENT_RATE_BPS + 1;
        uint256 repayment = CreditMath.repaymentFor(gross, remainingOwed);

        assert(repayment <= remainingOwed);
        assert(repayment <= gross * CreditMath.REPAYMENT_RATE_BPS / CreditMath.BPS);
    }

    function test_mockUsdcTransferFromDecrementsFiniteAllowance() public {
        vm.prank(customer);
        usdc.approve(admin, 10e6);

        vm.prank(admin);
        assertTrue(usdc.transferFrom(customer, merchant, 4e6));

        assertEq(usdc.allowance(customer, admin), 6e6);
        assertEq(usdc.balanceOf(merchant), 4e6);
    }

    function test_mockUsdcTransferFromPreservesInfiniteAllowance() public {
        vm.prank(customer);
        usdc.approve(admin, type(uint256).max);

        vm.prank(admin);
        assertTrue(usdc.transferFrom(customer, merchant, 4e6));

        assertEq(usdc.allowance(customer, admin), type(uint256).max);
    }

    function _prepareEligibleMerchant() internal returns (uint256 openInvoiceId) {
        vm.prank(merchant);
        merchantFacet.registerMerchant("Acme");
        vm.prank(admin);
        merchantFacet.setCreditEnabled(merchant, true);
        vm.prank(merchant);
        uint256 revenueInvoiceId = invoiceFacet.createInvoice(INVOICE_AMOUNT, 0, "revenue");
        _approveCustomer(INVOICE_AMOUNT);
        vm.prank(customer);
        invoiceFacet.payInvoice(revenueInvoiceId);
        vm.prank(merchant);
        openInvoiceId = invoiceFacet.createInvoice(1e6, 0, "open");
        _approveCustomer(1e6);
    }

    function _deployWithAdversarialToken() internal returns (AdversarialUSDC token) {
        token = new AdversarialUSDC();
        diamond = new DeployRevline().deploy(address(token), admin);
        token.mint(customer, LARGE_BALANCE);
        token.mint(address(diamond), LARGE_BALANCE);
        _bindFacets();
    }

    function _createAdversarialInvoice(AdversarialUSDC token, uint256 amount) internal returns (uint256 invoiceId) {
        vm.prank(merchant);
        merchantFacet.registerMerchant("Acme");
        vm.prank(merchant);
        invoiceId = invoiceFacet.createInvoice(amount, 0, "attack");
        vm.prank(customer);
        token.approve(address(diamond), amount);
    }

    function _prepareAdversarialEligibleMerchant(AdversarialUSDC token) internal {
        uint256 invoiceId = _createAdversarialInvoice(token, INVOICE_AMOUNT);
        vm.prank(customer);
        invoiceFacet.payInvoice(invoiceId);
        vm.prank(admin);
        merchantFacet.setCreditEnabled(merchant, true);
    }

    function _assertDrawTransferFailure(AdversarialUSDC.Behavior behavior) internal {
        AdversarialUSDC token = _deployWithAdversarialToken();
        _prepareAdversarialEligibleMerchant(token);
        token.configure(behavior, address(0), "");

        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(USDCTransferLib.USDCTransferFailed.selector, address(token)));
        creditFacet.drawAdvance(100e6);

        assertEq(merchantFacet.getMerchant(merchant).activeAdvanceId, 0);
        assertEq(uint256(creditFacet.getAdvance(1).status), uint256(RevlineTypes.AdvanceStatus.None));
        assertEq(creditFacet.poolStats().outstandingPrincipal, 0);
        assertEq(creditFacet.poolStats().totalAdvanced, 0);
    }

    function _bindFacets() internal {
        creditFacet = CreditFacet(address(diamond));
        invoiceFacet = InvoiceFacet(address(diamond));
        merchantFacet = MerchantFacet(address(diamond));
    }
}
