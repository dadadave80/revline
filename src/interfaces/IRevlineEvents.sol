// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IRevlineEvents {
    event MerchantRegistered(address indexed merchant, address indexed payout, string name);

    event PayoutUpdated(address indexed merchant, address indexed oldPayout, address indexed newPayout);

    event CreditEligibilityUpdated(address indexed merchant, bool enabled, address indexed underwriter);

    event InvoiceCreated(
        uint256 indexed invoiceId, address indexed merchant, uint256 amount, uint64 expiresAt, string memo
    );

    event InvoiceCancelled(uint256 indexed invoiceId, address indexed merchant);

    event InvoicePaid(
        uint256 indexed invoiceId,
        address indexed merchant,
        address indexed payer,
        uint256 grossAmount,
        uint256 merchantNet,
        uint256 repayment
    );

    event AdvanceDrawn(
        uint256 indexed advanceId,
        address indexed merchant,
        uint256 principal,
        uint256 fee,
        uint256 totalOwed,
        uint256 repaymentRateBps
    );

    event RepaymentApplied(
        uint256 indexed advanceId,
        uint256 indexed invoiceId,
        uint256 amount,
        uint256 principalApplied,
        uint256 feeApplied,
        uint256 remainingOwed
    );

    event AdvanceRepaid(uint256 indexed advanceId, address indexed merchant, uint256 totalRepaid, uint64 repaidAt);
}
