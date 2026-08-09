// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPausable} from "@lattice/interfaces/security/IPausable.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {DeployRevline} from "../script/DeployRevline.s.sol";
import {MerchantFacet} from "../src/facets/MerchantFacet.sol";
import {CreditFacet} from "../src/facets/CreditFacet.sol";
import {InvoiceFacet} from "../src/facets/InvoiceFacet.sol";
import {RevlineTypes} from "../src/RevlineTypes.sol";
import {IRevlineErrors} from "../src/interfaces/IRevlineErrors.sol";
import {IRevlineEvents} from "../src/interfaces/IRevlineEvents.sol";
import {RevlineTestBase} from "./helpers/RevlineTestBase.t.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

contract RevlineCreditTest is RevlineTestBase {
    CreditFacet internal creditFacet;
    InvoiceFacet internal invoiceFacet;
    MerchantFacet internal merchantFacet;

    function setUp() public override {
        super.setUp();
        vm.warp(100 days + 1 hours);
        _bindFacets();
    }

    function test_creditTermsAreFixedV1Values() public view {
        (
            uint256 revenueWindowDays,
            uint256 advanceRateBps,
            uint256 repaymentRateBps,
            uint256 feeBps,
            uint256 minTrailingRevenue,
            uint256 maxAdvance
        ) = creditFacet.creditTerms();

        assertEq(revenueWindowDays, 30);
        assertEq(advanceRateBps, 2_000);
        assertEq(repaymentRateBps, 2_000);
        assertEq(feeBps, 500);
        assertEq(minTrailingRevenue, 100e6);
        assertEq(maxAdvance, 1_000e6);
    }

    function test_quoteAtZeroRevenueHasZeroCredit() public {
        _registerAndEnable();
        RevlineTypes.CreditQuote memory quote = creditFacet.creditQuote(merchant);

        assertEq(quote.trailingRevenue, 0);
        assertEq(quote.creditLimit, 0);
        assertEq(quote.drawableNow, 0);
        assertTrue(quote.registered);
        assertTrue(quote.creditEnabled);
        assertFalse(quote.hasActiveAdvance);
    }

    function test_quoteUnregisteredMerchantHasNoDrawableCredit() public view {
        RevlineTypes.CreditQuote memory quote = creditFacet.creditQuote(merchant);

        assertFalse(quote.registered);
        assertFalse(quote.creditEnabled);
        assertFalse(quote.hasActiveAdvance);
        assertEq(quote.drawableNow, 0);
    }

    function test_quoteAt99UsdcFailsMinimumButStillReportsLimit() public {
        _prepareMerchant(99e6, true);
        RevlineTypes.CreditQuote memory quote = creditFacet.creditQuote(merchant);

        assertEq(quote.trailingRevenue, 99e6);
        assertEq(quote.creditLimit, 19_800_000);
        assertEq(quote.drawableNow, 0);
    }

    function test_quoteAt100UsdcAllows20Usdc() public {
        _prepareMerchant(100e6, true);
        RevlineTypes.CreditQuote memory quote = creditFacet.creditQuote(merchant);

        assertEq(quote.trailingRevenue, 100e6);
        assertEq(quote.creditLimit, 20e6);
        assertEq(quote.drawableNow, 20e6);
    }

    function test_quoteAt500UsdcAllows100Usdc() public {
        _prepareMerchant(500e6, true);
        RevlineTypes.CreditQuote memory quote = creditFacet.creditQuote(merchant);

        assertEq(quote.creditLimit, 100e6);
        assertEq(quote.drawableNow, 100e6);
    }

    function test_quoteAt10000UsdcCapsAt1000Usdc() public {
        _prepareMerchant(10_000e6, true);
        RevlineTypes.CreditQuote memory quote = creditFacet.creditQuote(merchant);

        assertEq(quote.creditLimit, 1_000e6);
        assertEq(quote.drawableNow, 1_000e6);
    }

    function test_quoteDisabledMerchantHasNoDrawableCredit() public {
        _prepareMerchant(500e6, false);
        RevlineTypes.CreditQuote memory quote = creditFacet.creditQuote(merchant);

        assertEq(quote.creditLimit, 100e6);
        assertEq(quote.drawableNow, 0);
        assertFalse(quote.creditEnabled);
    }

    function test_quoteActiveAdvanceHasNoDrawableCredit() public {
        _prepareMerchant(500e6, true);
        vm.prank(merchant);
        creditFacet.drawAdvance(100e6);

        RevlineTypes.CreditQuote memory quote = creditFacet.creditQuote(merchant);
        assertEq(quote.creditLimit, 100e6);
        assertEq(quote.drawableNow, 0);
        assertTrue(quote.hasActiveAdvance);
    }

    function test_quoteDrawableIsCappedByLiquidUsdc() public {
        _redeployWithLiquidity(12e6);
        _prepareMerchant(500e6, true);

        RevlineTypes.CreditQuote memory quote = creditFacet.creditQuote(merchant);
        assertEq(quote.creditLimit, 100e6);
        assertEq(quote.drawableNow, 12e6);
    }

    function test_drawRejectsZeroPrincipal() public {
        _prepareMerchant(500e6, true);

        vm.prank(merchant);
        vm.expectRevert(IRevlineErrors.InvalidAmount.selector);
        creditFacet.drawAdvance(0);
    }

    function test_drawRejectsUnregisteredMerchant() public {
        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.NotRegistered.selector, merchant));
        creditFacet.drawAdvance(1);
    }

    function test_drawRejectsDisabledMerchant() public {
        _prepareMerchant(500e6, false);

        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.CreditNotEnabled.selector, merchant));
        creditFacet.drawAdvance(100e6);
    }

    function test_drawRejectsInsufficientRevenue() public {
        _prepareMerchant(99e6, true);

        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.InsufficientRevenue.selector, 99e6, 100e6));
        creditFacet.drawAdvance(1e6);
    }

    function test_drawRejectsAboveCreditLimit() public {
        _prepareMerchant(500e6, true);

        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.AdvanceTooLarge.selector, 100e6 + 1, 100e6));
        creditFacet.drawAdvance(100e6 + 1);
    }

    function test_drawRejectsInsufficientPoolLiquidity() public {
        _redeployWithLiquidity(12e6);
        _prepareMerchant(500e6, true);

        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.InsufficientLiquidity.selector, 13e6, 12e6));
        creditFacet.drawAdvance(13e6);
    }

    function test_drawCreatesAdvanceAndPreservesManagedAssets() public {
        _prepareMerchant(500e6, true);
        uint256 merchantBalanceBefore = usdc.balanceOf(merchant);
        RevlineTypes.PoolStats memory beforeStats = creditFacet.poolStats();

        vm.expectEmit(true, true, false, true, address(diamond));
        emit IRevlineEvents.AdvanceDrawn(1, merchant, 100e6, 5e6, 105e6, 2_000);
        vm.prank(merchant);
        uint256 advanceId = creditFacet.drawAdvance(100e6);

        RevlineTypes.Advance memory advance = creditFacet.getAdvance(advanceId);
        RevlineTypes.Merchant memory merchantState = merchantFacet.getMerchant(merchant);
        RevlineTypes.PoolStats memory afterStats = creditFacet.poolStats();
        uint256[] memory ids = creditFacet.getMerchantAdvanceIds(merchant);

        assertEq(advanceId, 1);
        assertEq(advance.merchant, merchant);
        assertEq(advance.principal, 100e6);
        assertEq(advance.principalOutstanding, 100e6);
        assertEq(advance.fee, 5e6);
        assertEq(advance.totalOwed, 105e6);
        assertEq(advance.repaid, 0);
        assertEq(advance.drawnAt, uint64(block.timestamp));
        assertEq(advance.repaidAt, 0);
        assertEq(uint256(advance.status), uint256(RevlineTypes.AdvanceStatus.Active));
        assertEq(merchantState.activeAdvanceId, 1);
        assertEq(merchantState.totalBorrowed, 100e6);
        assertEq(usdc.balanceOf(merchant), merchantBalanceBefore + 100e6);
        assertEq(afterStats.liquidUSDC, beforeStats.liquidUSDC - 100e6);
        assertEq(afterStats.outstandingPrincipal, 100e6);
        assertEq(afterStats.totalAdvanced, 100e6);
        assertEq(afterStats.totalRepaid, 0);
        assertEq(afterStats.totalFeesEarned, 0);
        assertEq(afterStats.managedAssets, beforeStats.managedAssets);
        assertEq(ids.length, 1);
        assertEq(ids[0], 1);
    }

    function test_drawRejectsSecondActiveAdvance() public {
        _prepareMerchant(500e6, true);
        vm.prank(merchant);
        creditFacet.drawAdvance(50e6);

        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.ActiveAdvanceExists.selector, merchant, 1));
        creditFacet.drawAdvance(50e6);
    }

    function test_drawRevertsWhilePaused() public {
        _prepareMerchant(500e6, true);
        vm.prank(admin);
        pausable.pause();

        vm.prank(merchant);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        creditFacet.drawAdvance(100e6);
    }

    function test_paymentRepaysPrincipalFirstAndPreservesManagedAssets() public {
        _drawHundredUsdcAdvance();
        RevlineTypes.PoolStats memory beforeStats = creditFacet.poolStats();
        uint256 merchantBalanceBefore = usdc.balanceOf(merchant);

        vm.prank(merchant);
        uint256 invoiceId = invoiceFacet.createInvoice(50e6, 0, "Repayment 1");
        vm.prank(customer);
        usdc.approve(address(diamond), 50e6);

        vm.expectEmit(true, true, false, true, address(diamond));
        emit IRevlineEvents.RepaymentApplied(1, invoiceId, 10e6, 10e6, 0, 95e6);
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IRevlineEvents.InvoicePaid(invoiceId, merchant, customer, 50e6, 40e6, 10e6);
        vm.prank(customer);
        invoiceFacet.payInvoice(invoiceId);

        RevlineTypes.Advance memory advance = creditFacet.getAdvance(1);
        RevlineTypes.PoolStats memory afterStats = creditFacet.poolStats();
        assertEq(usdc.balanceOf(merchant), merchantBalanceBefore + 40e6);
        assertEq(advance.principalOutstanding, 90e6);
        assertEq(advance.repaid, 10e6);
        assertEq(afterStats.outstandingPrincipal, 90e6);
        assertEq(afterStats.totalRepaid, 10e6);
        assertEq(afterStats.totalFeesEarned, 0);
        assertEq(afterStats.managedAssets, beforeStats.managedAssets);
        assertEq(merchantFacet.getMerchant(merchant).lifetimeRevenue, 550e6);
        assertEq(merchantFacet.getMerchant(merchant).totalRepaid, 10e6);
    }

    function test_tenPaymentsRepayPrincipalButDoNotRealizeFee() public {
        _drawHundredUsdcAdvance();
        uint256 managedAssetsAfterDraw = creditFacet.poolStats().managedAssets;

        for (uint256 i; i < 10; ++i) {
            _payNewInvoice(50e6);
        }

        RevlineTypes.Advance memory advance = creditFacet.getAdvance(1);
        RevlineTypes.PoolStats memory stats = creditFacet.poolStats();
        assertEq(advance.principalOutstanding, 0);
        assertEq(advance.repaid, 100e6);
        assertEq(uint256(advance.status), uint256(RevlineTypes.AdvanceStatus.Active));
        assertEq(advance.totalOwed - advance.repaid, 5e6);
        assertEq(stats.outstandingPrincipal, 0);
        assertEq(stats.totalRepaid, 100e6);
        assertEq(stats.totalFeesEarned, 0);
        assertEq(stats.managedAssets, managedAssetsAfterDraw);
        assertEq(merchantFacet.getMerchant(merchant).activeAdvanceId, 1);
    }

    function test_finalPaymentCapsRepaymentRealizesFeeAndClosesAdvance() public {
        _drawHundredUsdcAdvance();
        uint256 managedAssetsAfterDraw = creditFacet.poolStats().managedAssets;
        for (uint256 i; i < 10; ++i) {
            _payNewInvoice(50e6);
        }

        vm.prank(merchant);
        uint256 invoiceId = invoiceFacet.createInvoice(50e6, 0, "Final repayment");
        vm.prank(customer);
        usdc.approve(address(diamond), 50e6);
        uint256 merchantBalanceBefore = usdc.balanceOf(merchant);

        vm.expectEmit(true, true, false, true, address(diamond));
        emit IRevlineEvents.RepaymentApplied(1, invoiceId, 5e6, 0, 5e6, 0);
        vm.expectEmit(true, true, false, true, address(diamond));
        emit IRevlineEvents.AdvanceRepaid(1, merchant, 105e6, uint64(block.timestamp));
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IRevlineEvents.InvoicePaid(invoiceId, merchant, customer, 50e6, 45e6, 5e6);
        vm.prank(customer);
        invoiceFacet.payInvoice(invoiceId);

        RevlineTypes.Advance memory advance = creditFacet.getAdvance(1);
        RevlineTypes.PoolStats memory stats = creditFacet.poolStats();
        assertEq(usdc.balanceOf(merchant), merchantBalanceBefore + 45e6);
        assertEq(advance.repaid, 105e6);
        assertEq(advance.repaidAt, uint64(block.timestamp));
        assertEq(uint256(advance.status), uint256(RevlineTypes.AdvanceStatus.Repaid));
        assertEq(stats.totalRepaid, 105e6);
        assertEq(stats.totalFeesEarned, 5e6);
        assertEq(stats.managedAssets, managedAssetsAfterDraw + 5e6);
        assertEq(merchantFacet.getMerchant(merchant).activeAdvanceId, 0);
    }

    function test_reborrowBlockedUntilFeePaidThenAllowed() public {
        _drawHundredUsdcAdvance();
        for (uint256 i; i < 10; ++i) {
            _payNewInvoice(50e6);
        }

        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.ActiveAdvanceExists.selector, merchant, 1));
        creditFacet.drawAdvance(100e6);

        _payNewInvoice(50e6);

        vm.prank(merchant);
        uint256 secondAdvanceId = creditFacet.drawAdvance(100e6);
        assertEq(secondAdvanceId, 2);
        assertEq(merchantFacet.getMerchant(merchant).activeAdvanceId, 2);
    }

    function _bindFacets() internal {
        creditFacet = CreditFacet(address(diamond));
        invoiceFacet = InvoiceFacet(address(diamond));
        merchantFacet = MerchantFacet(address(diamond));
    }

    function _redeployWithLiquidity(uint256 liquidity) internal {
        usdc = new MockUSDC();
        diamond = new DeployRevline().deploy(address(usdc), admin);
        usdc.mint(customer, LARGE_BALANCE);
        usdc.mint(address(diamond), liquidity);
        _bindFacets();
    }

    function _registerAndEnable() internal {
        vm.prank(merchant);
        merchantFacet.registerMerchant("Acme");
        vm.prank(admin);
        merchantFacet.setCreditEnabled(merchant, true);
    }

    function _prepareMerchant(uint256 revenue, bool enabled) internal {
        vm.prank(merchant);
        merchantFacet.registerMerchant("Acme");

        if (enabled) {
            vm.prank(admin);
            merchantFacet.setCreditEnabled(merchant, true);
        }

        vm.prank(merchant);
        uint256 invoiceId = invoiceFacet.createInvoice(revenue, 0, "Revenue");
        vm.prank(customer);
        usdc.approve(address(diamond), revenue);
        vm.prank(customer);
        invoiceFacet.payInvoice(invoiceId);
    }

    function _drawHundredUsdcAdvance() internal {
        _prepareMerchant(500e6, true);
        vm.prank(merchant);
        creditFacet.drawAdvance(100e6);
    }

    function _payNewInvoice(uint256 amount) internal returns (uint256 invoiceId) {
        vm.prank(merchant);
        invoiceId = invoiceFacet.createInvoice(amount, 0, "Revenue repayment");
        vm.prank(customer);
        usdc.approve(address(diamond), amount);
        vm.prank(customer);
        invoiceFacet.payInvoice(invoiceId);
    }
}
