// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPausable} from "@lattice/interfaces/security/IPausable.sol";
import {InvoiceFacet} from "../src/facets/InvoiceFacet.sol";
import {MerchantFacet} from "../src/facets/MerchantFacet.sol";
import {RevlineTypes} from "../src/RevlineTypes.sol";
import {IRevlineErrors} from "../src/interfaces/IRevlineErrors.sol";
import {IRevlineEvents} from "../src/interfaces/IRevlineEvents.sol";
import {RevlineTestBase} from "./helpers/RevlineTestBase.t.sol";

contract RevlineInvoiceTest is RevlineTestBase {
    uint256 internal constant INVOICE_AMOUNT = 50e6;

    InvoiceFacet internal invoiceFacet;
    MerchantFacet internal merchantFacet;

    function setUp() public override {
        super.setUp();
        vm.warp(100 days + 1 hours);
        invoiceFacet = InvoiceFacet(address(diamond));
        merchantFacet = MerchantFacet(address(diamond));
    }

    function test_onlyRegisteredMerchantCanCreateInvoice() public {
        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.NotRegistered.selector, merchant));
        invoiceFacet.createInvoice(INVOICE_AMOUNT, 0, "Invoice 1");
    }

    function test_createInvoiceRejectsZeroAmount() public {
        _registerMerchant();

        vm.prank(merchant);
        vm.expectRevert(IRevlineErrors.InvalidAmount.selector);
        invoiceFacet.createInvoice(0, 0, "Invoice 1");
    }

    function test_createInvoiceRejectsMemoLongerThan120Bytes() public {
        _registerMerchant();
        string memory memo =
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.InvalidMemoLength.selector, bytes(memo).length));
        invoiceFacet.createInvoice(INVOICE_AMOUNT, 0, memo);
    }

    function test_createInvoiceRejectsPastAndCurrentExpiry() public {
        _registerMerchant();

        vm.startPrank(merchant);
        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.InvalidExpiry.selector, uint64(block.timestamp - 1)));
        invoiceFacet.createInvoice(INVOICE_AMOUNT, uint64(block.timestamp - 1), "past");

        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.InvalidExpiry.selector, uint64(block.timestamp)));
        invoiceFacet.createInvoice(INVOICE_AMOUNT, uint64(block.timestamp), "current");
        vm.stopPrank();
    }

    function test_createNoExpiryInvoiceAndSequentialIds() public {
        _registerMerchant();

        vm.expectEmit(true, true, false, true, address(diamond));
        emit IRevlineEvents.InvoiceCreated(1, merchant, INVOICE_AMOUNT, 0, "first");
        vm.prank(merchant);
        uint256 firstId = invoiceFacet.createInvoice(INVOICE_AMOUNT, 0, "first");

        vm.prank(merchant);
        uint256 secondId = invoiceFacet.createInvoice(75e6, uint64(block.timestamp + 1 days), "second");

        assertEq(firstId, 1);
        assertEq(secondId, 2);

        RevlineTypes.Invoice memory invoice = invoiceFacet.getInvoice(firstId);
        assertEq(invoice.merchant, merchant);
        assertEq(invoice.payer, address(0));
        assertEq(invoice.amount, INVOICE_AMOUNT);
        assertEq(invoice.createdAt, uint64(block.timestamp));
        assertEq(invoice.expiresAt, 0);
        assertEq(invoice.paidAt, 0);
        assertEq(uint256(invoice.status), uint256(RevlineTypes.InvoiceStatus.Open));
        assertEq(invoice.memo, "first");

        uint256[] memory ids = invoiceFacet.getMerchantInvoiceIds(merchant);
        assertEq(ids.length, 2);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);
    }

    function test_merchantCanCancelInvoice() public {
        uint256 invoiceId = _createInvoice(0);

        vm.expectEmit(true, true, false, true, address(diamond));
        emit IRevlineEvents.InvoiceCancelled(invoiceId, merchant);
        vm.prank(merchant);
        invoiceFacet.cancelInvoice(invoiceId);

        assertEq(uint256(invoiceFacet.getInvoice(invoiceId).status), uint256(RevlineTypes.InvoiceStatus.Cancelled));
    }

    function test_nonMerchantCannotCancelInvoice() public {
        uint256 invoiceId = _createInvoice(0);

        vm.prank(customer);
        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.NotInvoiceMerchant.selector, invoiceId, customer));
        invoiceFacet.cancelInvoice(invoiceId);
    }

    function test_cancelledInvoiceCannotBePaid() public {
        uint256 invoiceId = _createInvoice(0);
        vm.prank(merchant);
        invoiceFacet.cancelInvoice(invoiceId);

        _approveCustomer(INVOICE_AMOUNT);
        vm.prank(customer);
        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.InvoiceNotOpen.selector, invoiceId));
        invoiceFacet.payInvoice(invoiceId);
    }

    function test_expiredInvoiceCannotBePaid() public {
        uint256 invoiceId = _createInvoice(uint64(block.timestamp + 1 days));
        vm.warp(block.timestamp + 1 days);

        _approveCustomer(INVOICE_AMOUNT);
        vm.prank(customer);
        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.InvoiceExpired.selector, invoiceId));
        invoiceFacet.payInvoice(invoiceId);
    }

    function test_paidInvoiceCannotBePaidTwice() public {
        uint256 invoiceId = _createInvoice(0);
        _payInvoice(invoiceId);

        _approveCustomer(INVOICE_AMOUNT);
        vm.prank(customer);
        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.InvoiceNotOpen.selector, invoiceId));
        invoiceFacet.payInvoice(invoiceId);
    }

    function test_merchantCannotPayOwnInvoice() public {
        uint256 invoiceId = _createInvoice(0);
        vm.prank(merchant);
        usdc.approve(address(diamond), INVOICE_AMOUNT);

        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.MerchantCannotPayOwnInvoice.selector, invoiceId));
        invoiceFacet.payInvoice(invoiceId);
    }

    function test_payInvoicePullsExactGrossAndRoutesFullAmountWithoutDebt() public {
        uint256 invoiceId = _createInvoice(0);
        uint256 customerBefore = usdc.balanceOf(customer);
        uint256 merchantBefore = usdc.balanceOf(merchant);
        uint256 diamondBefore = usdc.balanceOf(address(diamond));
        _approveCustomer(INVOICE_AMOUNT);

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IRevlineEvents.InvoicePaid(invoiceId, merchant, customer, INVOICE_AMOUNT, INVOICE_AMOUNT, 0);
        vm.prank(customer);
        invoiceFacet.payInvoice(invoiceId);

        assertEq(usdc.balanceOf(customer), customerBefore - INVOICE_AMOUNT);
        assertEq(usdc.balanceOf(merchant), merchantBefore + INVOICE_AMOUNT);
        assertEq(usdc.balanceOf(address(diamond)), diamondBefore);
        assertEq(usdc.allowance(customer, address(diamond)), 0);
    }

    function test_paidInvoiceRecordsPaymentAndGrossRevenue() public {
        uint256 invoiceId = _createInvoice(0);
        uint64 paidAt = uint64(block.timestamp);
        _payInvoice(invoiceId);

        RevlineTypes.Invoice memory invoice = invoiceFacet.getInvoice(invoiceId);
        assertEq(invoice.payer, customer);
        assertEq(invoice.paidAt, paidAt);
        assertEq(uint256(invoice.status), uint256(RevlineTypes.InvoiceStatus.Paid));
        assertEq(merchantFacet.getMerchant(merchant).lifetimeRevenue, INVOICE_AMOUNT);
        assertEq(merchantFacet.trailingRevenue(merchant), INVOICE_AMOUNT);
    }

    function test_directUsdcTransferDoesNotCreateRevenue() public {
        _registerMerchant();

        vm.prank(customer);
        assertTrue(usdc.transfer(address(diamond), INVOICE_AMOUNT));

        assertEq(merchantFacet.getMerchant(merchant).lifetimeRevenue, 0);
        assertEq(merchantFacet.trailingRevenue(merchant), 0);
    }

    function test_trailingRevenueIncludesPaymentThroughDay29AndExcludesOnDay30() public {
        uint256 invoiceId = _createInvoice(0);
        _payInvoice(invoiceId);

        vm.warp(block.timestamp + 29 days);
        assertEq(merchantFacet.trailingRevenue(merchant), INVOICE_AMOUNT);

        vm.warp(block.timestamp + 1 days);
        assertEq(merchantFacet.trailingRevenue(merchant), 0);
    }

    function test_trailingRevenueSumsPaymentsAcrossDays() public {
        uint256 firstId = _createInvoice(0);
        _payInvoice(firstId);

        vm.warp(block.timestamp + 10 days);
        vm.prank(merchant);
        uint256 secondId = invoiceFacet.createInvoice(75e6, 0, "second");
        _approveCustomer(75e6);
        vm.prank(customer);
        invoiceFacet.payInvoice(secondId);

        vm.warp(block.timestamp + 19 days);
        assertEq(merchantFacet.trailingRevenue(merchant), 125e6);

        vm.warp(block.timestamp + 1 days);
        assertEq(merchantFacet.trailingRevenue(merchant), 75e6);
    }

    function test_invoiceMutationsRevertWhilePaused() public {
        _registerMerchant();
        vm.prank(admin);
        pausable.pause();

        vm.prank(merchant);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        invoiceFacet.createInvoice(INVOICE_AMOUNT, 0, "paused");

        vm.prank(admin);
        pausable.unpause();
        vm.prank(merchant);
        uint256 invoiceId = invoiceFacet.createInvoice(INVOICE_AMOUNT, 0, "open");
        vm.prank(admin);
        pausable.pause();

        vm.prank(merchant);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        invoiceFacet.cancelInvoice(invoiceId);

        vm.prank(customer);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        invoiceFacet.payInvoice(invoiceId);
    }

    function test_missingInvoiceCannotCancelOrPay() public {
        vm.prank(merchant);
        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.InvoiceNotFound.selector, 1));
        invoiceFacet.cancelInvoice(1);

        vm.prank(customer);
        vm.expectRevert(abi.encodeWithSelector(IRevlineErrors.InvoiceNotFound.selector, 1));
        invoiceFacet.payInvoice(1);
    }

    function _registerMerchant() internal {
        vm.prank(merchant);
        merchantFacet.registerMerchant("Acme");
    }

    function _createInvoice(uint64 expiresAt) internal returns (uint256 invoiceId) {
        _registerMerchant();
        vm.prank(merchant);
        invoiceId = invoiceFacet.createInvoice(INVOICE_AMOUNT, expiresAt, "Invoice 1");
    }

    function _payInvoice(uint256 invoiceId) internal {
        _approveCustomer(INVOICE_AMOUNT);
        vm.prank(customer);
        invoiceFacet.payInvoice(invoiceId);
    }
}
