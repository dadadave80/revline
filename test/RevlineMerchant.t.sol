// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPausable} from "@lattice/interfaces/security/IPausable.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {MerchantFacet} from "../src/facets/MerchantFacet.sol";
import {RevlineRoles} from "../src/RevlineRoles.sol";
import {RevlineTypes} from "../src/RevlineTypes.sol";
import {IRevlineErrors} from "../src/interfaces/IRevlineErrors.sol";
import {IRevlineEvents} from "../src/interfaces/IRevlineEvents.sol";
import {RevlineTestBase} from "./helpers/RevlineTestBase.t.sol";

contract RevlineMerchantTest is RevlineTestBase {
    MerchantFacet internal merchantFacet;

    function setUp() public override {
        super.setUp();
        merchantFacet = MerchantFacet(address(diamond));
    }

    function test_registerMerchant() public {
        vm.expectEmit(true, true, false, true, address(diamond));
        emit IRevlineEvents.MerchantRegistered(merchant, merchant, "Acme");

        vm.prank(merchant);
        merchantFacet.registerMerchant("Acme");

        RevlineTypes.Merchant memory registered = merchantFacet.getMerchant(merchant);
        assertTrue(registered.registered);
        assertEq(registered.payout, merchant);
        assertEq(registered.registeredAt, uint64(block.timestamp));
        assertEq(registered.name, "Acme");
        assertEq(merchantFacet.trailingRevenue(merchant), 0);
    }

    function test_registerMerchantRejectsDuplicate() public {
        _registerMerchant();

        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.AlreadyRegistered.selector, merchant));
        merchantFacet.registerMerchant("Acme II");
    }

    function test_registerMerchantRejectsEmptyName() public {
        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.InvalidNameLength.selector, 0));
        merchantFacet.registerMerchant("");
    }

    function test_registerMerchantRejectsNameLongerThan64Bytes() public {
        string memory name = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.InvalidNameLength.selector, bytes(name).length));
        merchantFacet.registerMerchant(name);
    }

    function test_registeredPayoutDefaultsToCaller() public {
        _registerMerchant();
        assertEq(merchantFacet.getMerchant(merchant).payout, merchant);
    }

    function test_setPayoutAddress() public {
        _registerMerchant();
        address newPayout = makeAddr("newPayout");

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IRevlineEvents.PayoutUpdated(merchant, merchant, newPayout);

        vm.prank(merchant);
        merchantFacet.setPayoutAddress(newPayout);

        assertEq(merchantFacet.getMerchant(merchant).payout, newPayout);
    }

    function test_setPayoutAddressRejectsZeroAddress() public {
        _registerMerchant();

        vm.prank(merchant);
        vm.expectRevert(IRevlineErrors.ZeroAddress.selector);
        merchantFacet.setPayoutAddress(address(0));
    }

    function test_setPayoutAddressRejectsDiamond() public {
        _registerMerchant();

        vm.prank(merchant);
        vm.expectRevert(IRevlineErrors.ZeroAddress.selector);
        merchantFacet.setPayoutAddress(address(diamond));
    }

    function test_setPayoutAddressRejectsUnregisteredMerchant() public {
        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.NotRegistered.selector, merchant));
        merchantFacet.setPayoutAddress(makeAddr("payout"));
    }

    function test_nonUnderwriterCannotSetCreditEnabled() public {
        _registerMerchant();

        vm.prank(customer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, customer, RevlineRoles.UNDERWRITER_ROLE
            )
        );
        merchantFacet.setCreditEnabled(merchant, true);
    }

    function test_underwriterCanEnableAndDisableCredit() public {
        _registerMerchant();

        vm.expectEmit(true, false, true, true, address(diamond));
        emit IRevlineEvents.CreditEligibilityUpdated(merchant, true, admin);
        vm.prank(admin);
        merchantFacet.setCreditEnabled(merchant, true);
        assertTrue(merchantFacet.getMerchant(merchant).creditEnabled);

        vm.expectEmit(true, false, true, true, address(diamond));
        emit IRevlineEvents.CreditEligibilityUpdated(merchant, false, admin);
        vm.prank(admin);
        merchantFacet.setCreditEnabled(merchant, false);
        assertFalse(merchantFacet.getMerchant(merchant).creditEnabled);
    }

    function test_underwriterCannotEnableUnregisteredMerchant() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.NotRegistered.selector, merchant));
        merchantFacet.setCreditEnabled(merchant, true);
    }

    function test_merchantMutationsRevertWhilePaused() public {
        vm.prank(admin);
        pausable.pause();

        vm.prank(merchant);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        merchantFacet.registerMerchant("Acme");

        vm.prank(admin);
        pausable.unpause();
        _registerMerchant();

        vm.prank(admin);
        pausable.pause();

        vm.prank(merchant);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        merchantFacet.setPayoutAddress(makeAddr("payout"));
    }

    function test_setCreditEnabledWorksWhilePaused() public {
        _registerMerchant();

        vm.prank(admin);
        pausable.pause();

        vm.prank(admin);
        merchantFacet.setCreditEnabled(merchant, true);

        assertTrue(merchantFacet.getMerchant(merchant).creditEnabled);
    }

    function _registerMerchant() internal {
        vm.prank(merchant);
        merchantFacet.registerMerchant("Acme");
    }
}
