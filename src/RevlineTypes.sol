// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library RevlineTypes {
    enum InvoiceStatus {
        None,
        Open,
        Paid,
        Cancelled
    }

    enum AdvanceStatus {
        None,
        Active,
        Repaid
    }

    struct Merchant {
        bool registered;
        bool creditEnabled;
        address payout;
        uint64 registeredAt;
        uint256 activeAdvanceId;
        uint256 lifetimeRevenue;
        uint256 totalBorrowed;
        uint256 totalRepaid;
        string name;
    }

    struct Invoice {
        address merchant;
        address payer;
        uint256 amount;
        uint64 createdAt;
        uint64 expiresAt; // 0 = no expiry
        uint64 paidAt;
        InvoiceStatus status;
        string memo;
    }

    struct Advance {
        address merchant;
        uint256 principal;
        uint256 principalOutstanding;
        uint256 fee;
        uint256 totalOwed;
        uint256 repaid;
        uint64 drawnAt;
        uint64 repaidAt;
        AdvanceStatus status;
    }

    struct CreditQuote {
        uint256 trailingRevenue;
        uint256 creditLimit;
        uint256 drawableNow;
        bool registered;
        bool creditEnabled;
        bool hasActiveAdvance;
    }

    struct PoolStats {
        uint256 liquidUSDC;
        uint256 outstandingPrincipal;
        uint256 totalAdvanced;
        uint256 totalRepaid;
        uint256 totalFeesEarned;
        uint256 managedAssets;
    }
}
