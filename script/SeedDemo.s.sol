// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {CreditFacet} from "../src/facets/CreditFacet.sol";
import {InvoiceFacet} from "../src/facets/InvoiceFacet.sol";
import {MerchantFacet} from "../src/facets/MerchantFacet.sol";

/// @notice Seeds the recorded demo state with real Revline calls and real Arc USDC transfers.
/// @dev Requires an unused merchant wallet and a customer wallet funded with at least 500 USDC.
contract SeedDemo is Script {
    address internal constant ARC_USDC = 0x3600000000000000000000000000000000000000;
    uint256 internal constant POOL_FUNDING = 1_000e6;
    uint256 internal constant INVOICE_ONE = 150e6;
    uint256 internal constant INVOICE_TWO = 175e6;
    uint256 internal constant INVOICE_THREE = 175e6;

    function run() external {
        uint256 underwriterKey = vm.envUint("PRIVATE_KEY");
        uint256 merchantKey = vm.envUint("MERCHANT_PRIVATE_KEY");
        uint256 customerKey = vm.envUint("CUSTOMER_PRIVATE_KEY");
        address revline = vm.envAddress("REVLINE_ADDRESS");
        address merchant = vm.addr(merchantKey);
        address customer = vm.addr(customerKey);

        require(revline != address(0) && revline.code.length != 0, "Revline unavailable");
        require(ARC_USDC.code.length != 0, "Arc USDC unavailable");
        require(merchant != customer, "merchant is customer");
        require(!MerchantFacet(revline).getMerchant(merchant).registered, "merchant already registered");
        require(!CreditFacet(revline).creditQuote(merchant).hasActiveAdvance, "merchant has active advance");

        vm.startBroadcast(underwriterKey);
        require(IERC20(ARC_USDC).transfer(revline, POOL_FUNDING), "pool funding failed");
        vm.stopBroadcast();

        vm.startBroadcast(merchantKey);
        MerchantFacet(revline).registerMerchant("Revline Demo Merchant");
        uint256 invoiceOne = InvoiceFacet(revline).createInvoice(INVOICE_ONE, 0, "Demo invoice 1");
        uint256 invoiceTwo = InvoiceFacet(revline).createInvoice(INVOICE_TWO, 0, "Demo invoice 2");
        uint256 invoiceThree = InvoiceFacet(revline).createInvoice(INVOICE_THREE, 0, "Demo invoice 3");
        vm.stopBroadcast();

        vm.startBroadcast(underwriterKey);
        MerchantFacet(revline).setCreditEnabled(merchant, true);
        vm.stopBroadcast();

        vm.startBroadcast(customerKey);
        require(IERC20(ARC_USDC).approve(revline, INVOICE_ONE + INVOICE_TWO + INVOICE_THREE), "approval failed");
        InvoiceFacet(revline).payInvoice(invoiceOne);
        InvoiceFacet(revline).payInvoice(invoiceTwo);
        InvoiceFacet(revline).payInvoice(invoiceThree);
        vm.stopBroadcast();

        console2.log("Demo merchant", merchant);
        console2.log("Demo customer", customer);
        console2.log("Routed revenue", INVOICE_ONE + INVOICE_TWO + INVOICE_THREE);
        console2.log("Pool funding", POOL_FUNDING);
    }
}
