// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {IDiamondCut} from "@diamond/interfaces/IDiamondCut.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IPausable} from "@lattice/interfaces/security/IPausable.sol";
import {RevlineRoles} from "../src/RevlineRoles.sol";
import {RevlineTestBase} from "./helpers/RevlineTestBase.t.sol";

contract UpgradeProbe {
    function value() external pure returns (uint256) {
        return 42;
    }
}

contract RevlineSecurityTest is RevlineTestBase {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

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
        IPausable pausable = IPausable(address(diamond));

        vm.prank(admin);
        pausable.pause();
        assertTrue(pausable.paused());

        vm.prank(admin);
        pausable.unpause();
        assertFalse(pausable.paused());
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
}
