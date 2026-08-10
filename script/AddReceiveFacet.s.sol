// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {IDiamondCut} from "@diamond/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {Receive} from "@lattice/Receive.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract AddReceiveFacet is Script {
    bytes4 internal constant ZERO_SELECTOR = bytes4(0);

    error ZeroAddress();
    error TargetHasNoCode(address target);
    error ReceiveAlreadyInstalled(address existingFacet);
    error ReceiveInstallFailed(address expectedFacet, address actualFacet);

    function buildCut(address receiveFacet) public pure returns (FacetCut[] memory cuts) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = ZERO_SELECTOR;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: receiveFacet, action: FacetCutAction.Add, functionSelectors: selectors});
    }

    function run() external returns (address receiveFacet) {
        address target = vm.envAddress("REVLINE_ADDRESS");
        if (target == address(0)) revert ZeroAddress();
        if (target.code.length == 0) revert TargetHasNoCode(target);

        address existing = IDiamondLoupe(target).facetAddress(ZERO_SELECTOR);
        if (existing != address(0)) revert ReceiveAlreadyInstalled(existing);

        vm.startBroadcast();
        receiveFacet = address(new Receive());
        IDiamondCut(target).diamondCut(buildCut(receiveFacet), address(0), "");
        vm.stopBroadcast();

        address actual = IDiamondLoupe(target).facetAddress(ZERO_SELECTOR);
        if (actual != receiveFacet) revert ReceiveInstallFailed(receiveFacet, actual);

        console2.log("Revline Diamond", target);
        console2.log("Receive implementation", receiveFacet);
        console2.log("Receive selector", uint256(uint32(ZERO_SELECTOR)));
        console2.log("Native receive installed");
    }
}
