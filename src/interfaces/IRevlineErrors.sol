// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IRevlineErrors {
    error ZeroAddress();
    error AlreadyRegistered(address merchant);
    error NotRegistered(address merchant);
    error InvalidNameLength(uint256 length);
    error InvalidMemoLength(uint256 length);
    error InvalidAmount();
    error InvalidExpiry(uint64 expiresAt);
    error InvoiceNotFound(uint256 invoiceId);
    error InvoiceNotOpen(uint256 invoiceId);
    error InvoiceExpired(uint256 invoiceId);
    error NotInvoiceMerchant(uint256 invoiceId, address caller);
    error MerchantCannotPayOwnInvoice(uint256 invoiceId);
    error CreditNotEnabled(address merchant);
    error ActiveAdvanceExists(address merchant, uint256 advanceId);
    error InsufficientRevenue(uint256 trailingRevenue, uint256 required);
    error AdvanceTooLarge(uint256 requested, uint256 maximum);
    error InsufficientLiquidity(uint256 requested, uint256 available);
}
