// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IPausable} from "@lattice/interfaces/security/IPausable.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {IDiamondCut} from "@diamond/interfaces/IDiamondCut.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {Receive} from "@lattice/Receive.sol";
import {CreditFacet} from "../src/facets/CreditFacet.sol";
import {RevlineTypes} from "../src/RevlineTypes.sol";
import {RevlineTestBase} from "./helpers/RevlineTestBase.t.sol";

contract RevlineReceiveTest is RevlineTestBase {
    bytes4 internal constant ZERO_SELECTOR = bytes4(0);
    CreditFacet internal credit;

    function setUp() public override {
        super.setUp();
        credit = CreditFacet(address(diamond));
    }

    function test_plainNativeTransferSucceeds() public {
        vm.deal(customer, 1 ether);
        uint256 beforeBalance = address(diamond).balance;

        vm.prank(customer);
        (bool ok,) = address(diamond).call{value: 1 ether}("");

        assertTrue(ok);
        assertEq(address(diamond).balance, beforeBalance + 1 ether);
    }

    function test_receiveUsesZeroSelector() public view {
        address receiveFacet = IDiamondLoupe(address(diamond)).facetAddress(ZERO_SELECTOR);
        assertTrue(receiveFacet != address(0));
        assertTrue(receiveFacet.code.length > 0);
    }

    function test_nonEmptyZeroCalldataStillReverts() public {
        vm.deal(customer, 1 ether);
        uint256 beforeBalance = address(diamond).balance;

        vm.prank(customer);
        (bool ok,) = address(diamond).call{value: 1 ether}(hex"00");

        assertFalse(ok);
        assertEq(address(diamond).balance, beforeBalance);
    }

    function test_nativeTransferDoesNotChangeProtocolAccounting() public {
        RevlineTypes.PoolStats memory beforeStats = credit.poolStats();
        uint256 beforeERC20 = IERC20(address(usdc)).balanceOf(address(diamond));
        uint256 beforeNative = address(diamond).balance;

        vm.deal(customer, 1 ether);
        vm.prank(customer);
        (bool ok,) = address(diamond).call{value: 1 ether}("");

        assertTrue(ok);
        RevlineTypes.PoolStats memory afterStats = credit.poolStats();
        assertEq(address(diamond).balance, beforeNative + 1 ether);
        assertEq(IERC20(address(usdc)).balanceOf(address(diamond)), beforeERC20);
        assertEq(afterStats.liquidUSDC, beforeStats.liquidUSDC);
        assertEq(afterStats.outstandingPrincipal, beforeStats.outstandingPrincipal);
        assertEq(afterStats.totalAdvanced, beforeStats.totalAdvanced);
        assertEq(afterStats.totalRepaid, beforeStats.totalRepaid);
        assertEq(afterStats.totalFeesEarned, beforeStats.totalFeesEarned);
        assertEq(afterStats.managedAssets, beforeStats.managedAssets);
    }

    function test_directERC20FundingBehaviorIsUnchanged() public {
        RevlineTypes.PoolStats memory beforeStats = credit.poolStats();
        uint256 amount = 25e6;

        usdc.mint(customer, amount);
        vm.prank(customer);
        usdc.transfer(address(diamond), amount);

        RevlineTypes.PoolStats memory afterStats = credit.poolStats();
        assertEq(afterStats.liquidUSDC, beforeStats.liquidUSDC + amount);
        assertEq(afterStats.managedAssets, beforeStats.managedAssets + amount);
        assertEq(afterStats.totalAdvanced, beforeStats.totalAdvanced);
        assertEq(afterStats.totalRepaid, beforeStats.totalRepaid);
        assertEq(afterStats.totalFeesEarned, beforeStats.totalFeesEarned);
    }

    function test_receiveWorksWhilePaused() public {
        vm.prank(admin);
        IPausable(address(diamond)).pause();

        vm.deal(customer, 1 ether);
        vm.prank(customer);
        (bool ok,) = address(diamond).call{value: 1 ether}("");

        assertTrue(ok);
        assertTrue(IPausable(address(diamond)).paused());
    }

    function test_nonAdminCannotInstallAnotherReceiveFacet() public {
        Receive replacement = new Receive();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = ZERO_SELECTOR;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] =
            FacetCut({facetAddress: address(replacement), action: FacetCutAction.Add, functionSelectors: selectors});

        vm.prank(customer);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, customer, bytes32(0))
        );
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
    }
}
