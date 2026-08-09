// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {MerchantFacet} from "../src/facets/MerchantFacet.sol";

/// @notice Enables a registered merchant using the configured underwriter key.
contract EnableMerchant is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address revline = vm.envAddress("REVLINE_ADDRESS");
        address merchant = vm.envAddress("MERCHANT_ADDRESS");

        require(revline != address(0) && revline.code.length != 0, "Revline unavailable");
        require(merchant != address(0), "merchant is zero");

        vm.startBroadcast(privateKey);
        MerchantFacet(revline).setCreditEnabled(merchant, true);
        vm.stopBroadcast();

        console2.log("Credit enabled for merchant", merchant);
    }
}
