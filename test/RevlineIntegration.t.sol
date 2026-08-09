// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DeployRevline} from "../script/DeployRevline.s.sol";
import {CreditFacet} from "../src/facets/CreditFacet.sol";
import {InvoiceFacet} from "../src/facets/InvoiceFacet.sol";
import {MerchantFacet} from "../src/facets/MerchantFacet.sol";
import {RevlineTypes} from "../src/RevlineTypes.sol";
import {RevlineTestBase} from "./helpers/RevlineTestBase.t.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

contract RevlineIntegrationTest is RevlineTestBase {
    CreditFacet internal creditFacet;
    InvoiceFacet internal invoiceFacet;
    MerchantFacet internal merchantFacet;

    function setUp() public override {
        super.setUp();
        usdc = new MockUSDC();
        diamond = new DeployRevline().deploy(address(usdc), admin);
        usdc.mint(customer, LARGE_BALANCE);
        usdc.mint(address(diamond), 1_000e6);

        creditFacet = CreditFacet(address(diamond));
        invoiceFacet = InvoiceFacet(address(diamond));
        merchantFacet = MerchantFacet(address(diamond));
    }

    function test_canonicalRevenueAdvanceAndRepaymentScenario() public {
        vm.prank(merchant);
        merchantFacet.registerMerchant("Acme");
        vm.prank(admin);
        merchantFacet.setCreditEnabled(merchant, true);

        _payInvoice(200e6);
        _payInvoice(150e6);
        _payInvoice(150e6);

        RevlineTypes.CreditQuote memory quote = creditFacet.creditQuote(merchant);
        assertEq(usdc.balanceOf(address(diamond)), 1_000e6);
        assertEq(quote.trailingRevenue, 500e6);
        assertEq(quote.creditLimit, 100e6);
        assertEq(quote.drawableNow, 100e6);

        vm.prank(merchant);
        uint256 advanceId = creditFacet.drawAdvance(100e6);
        RevlineTypes.Advance memory drawnAdvance = creditFacet.getAdvance(advanceId);
        assertEq(drawnAdvance.principal, 100e6);
        assertEq(drawnAdvance.fee, 5e6);
        assertEq(drawnAdvance.totalOwed, 105e6);
        assertEq(usdc.balanceOf(address(diamond)), 900e6);

        uint256 merchantBalanceBefore = usdc.balanceOf(merchant);
        _payInvoice(50e6);

        RevlineTypes.Advance memory repaidAdvance = creditFacet.getAdvance(advanceId);
        RevlineTypes.PoolStats memory stats = creditFacet.poolStats();
        assertEq(usdc.balanceOf(merchant), merchantBalanceBefore + 40e6);
        assertEq(repaidAdvance.repaid, 10e6);
        assertEq(repaidAdvance.principalOutstanding, 90e6);
        assertEq(stats.liquidUSDC, 910e6);
        assertEq(stats.outstandingPrincipal, 90e6);
        assertEq(stats.totalRepaid, 10e6);
        assertEq(stats.totalFeesEarned, 0);
        assertEq(stats.managedAssets, 1_000e6);
        assertEq(merchantFacet.getMerchant(merchant).lifetimeRevenue, 550e6);
    }

    function _payInvoice(uint256 amount) internal {
        vm.prank(merchant);
        uint256 invoiceId = invoiceFacet.createInvoice(amount, 0, "Revenue");
        vm.prank(customer);
        usdc.approve(address(diamond), amount);
        vm.prank(customer);
        invoiceFacet.payInvoice(invoiceId);
    }
}
