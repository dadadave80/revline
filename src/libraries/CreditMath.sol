// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library CreditMath {
    uint256 internal constant BPS = 10_000;
    uint256 internal constant REVENUE_WINDOW_DAYS = 30;
    uint256 internal constant ADVANCE_RATE_BPS = 2_000;
    uint256 internal constant REPAYMENT_RATE_BPS = 2_000;
    uint256 internal constant FEE_BPS = 500;
    uint256 internal constant MIN_TRAILING_REVENUE = 100e6;
    uint256 internal constant MAX_ADVANCE = 1_000e6;

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function creditLimit(uint256 trailingRevenue) internal pure returns (uint256) {
        return min(trailingRevenue * ADVANCE_RATE_BPS / BPS, MAX_ADVANCE);
    }

    function feeFor(uint256 principal) internal pure returns (uint256) {
        return principal * FEE_BPS / BPS;
    }

    function repaymentFor(uint256 gross, uint256 remainingOwed) internal pure returns (uint256) {
        uint256 candidate = gross * REPAYMENT_RATE_BPS / BPS;
        return min(candidate, remainingOwed);
    }
}
