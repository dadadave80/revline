// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";
import {ReentrancyGuard} from "@lattice/security/ReentrancyGuard.sol";
import {RevlineStorage} from "../RevlineStorage.sol";
import {RevlineTypes} from "../RevlineTypes.sol";
import {IRevlineErrors} from "../interfaces/IRevlineErrors.sol";
import {IRevlineEvents} from "../interfaces/IRevlineEvents.sol";
import {RevenueLib} from "../libraries/RevenueLib.sol";
import {USDCTransferLib} from "../libraries/USDCTransferLib.sol";

contract InvoiceFacet is ReentrancyGuard, IRevlineEvents {
    function createInvoice(uint256 amount, uint64 expiresAt, string calldata memo)
        external
        returns (uint256 invoiceId)
    {
        PausableLib.checkNotPaused();

        RevlineStorage.Layout storage $ = RevlineStorage.layout();
        if (!$.merchants[msg.sender].registered) revert IRevlineErrors.NotRegistered(msg.sender);
        if (amount == 0) revert IRevlineErrors.InvalidAmount();

        uint256 memoLength = bytes(memo).length;
        if (memoLength > 120) revert IRevlineErrors.InvalidMemoLength(memoLength);
        if (expiresAt != 0 && expiresAt <= block.timestamp) revert IRevlineErrors.InvalidExpiry(expiresAt);

        invoiceId = ++$.invoiceNonce;
        $.invoices[invoiceId] = RevlineTypes.Invoice({
            merchant: msg.sender,
            payer: address(0),
            amount: amount,
            createdAt: uint64(block.timestamp),
            expiresAt: expiresAt,
            paidAt: 0,
            status: RevlineTypes.InvoiceStatus.Open,
            memo: memo
        });
        $.merchantInvoices[msg.sender].push(invoiceId);

        emit InvoiceCreated(invoiceId, msg.sender, amount, expiresAt, memo);
    }

    function cancelInvoice(uint256 invoiceId) external {
        PausableLib.checkNotPaused();

        RevlineTypes.Invoice storage invoice = RevlineStorage.layout().invoices[invoiceId];
        if (invoice.status == RevlineTypes.InvoiceStatus.None) revert IRevlineErrors.InvoiceNotFound(invoiceId);
        if (invoice.status != RevlineTypes.InvoiceStatus.Open) revert IRevlineErrors.InvoiceNotOpen(invoiceId);
        if (invoice.merchant != msg.sender) revert IRevlineErrors.NotInvoiceMerchant(invoiceId, msg.sender);

        invoice.status = RevlineTypes.InvoiceStatus.Cancelled;
        emit InvoiceCancelled(invoiceId, msg.sender);
    }

    function payInvoice(uint256 invoiceId) external nonReentrant {
        PausableLib.checkNotPaused();

        RevlineStorage.Layout storage $ = RevlineStorage.layout();
        RevlineTypes.Invoice storage invoice = $.invoices[invoiceId];
        if (invoice.status == RevlineTypes.InvoiceStatus.None) revert IRevlineErrors.InvoiceNotFound(invoiceId);
        if (invoice.status != RevlineTypes.InvoiceStatus.Open) revert IRevlineErrors.InvoiceNotOpen(invoiceId);
        if (invoice.expiresAt != 0 && invoice.expiresAt <= block.timestamp) {
            revert IRevlineErrors.InvoiceExpired(invoiceId);
        }
        if (invoice.merchant == msg.sender) revert IRevlineErrors.MerchantCannotPayOwnInvoice(invoiceId);

        USDCTransferLib.safeTransferFrom($.usdc, msg.sender, address(this), invoice.amount);

        invoice.status = RevlineTypes.InvoiceStatus.Paid;
        invoice.payer = msg.sender;
        invoice.paidAt = uint64(block.timestamp);
        RevenueLib.record(invoice.merchant, invoice.amount);

        address payout = $.merchants[invoice.merchant].payout;
        USDCTransferLib.safeTransfer($.usdc, payout, invoice.amount);

        emit InvoicePaid(invoiceId, invoice.merchant, msg.sender, invoice.amount, invoice.amount, 0);
    }

    function getInvoice(uint256 invoiceId) external view returns (RevlineTypes.Invoice memory) {
        return RevlineStorage.layout().invoices[invoiceId];
    }

    function getMerchantInvoiceIds(address merchant) external view returns (uint256[] memory) {
        return RevlineStorage.layout().merchantInvoices[merchant];
    }
}
