// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";
import {ReentrancyGuard} from "@lattice/security/ReentrancyGuard.sol";
import {RevlineStorage} from "../RevlineStorage.sol";
import {RevlineTypes} from "../RevlineTypes.sol";
import {IRevlineErrors} from "../interfaces/IRevlineErrors.sol";
import {IRevlineEvents} from "../interfaces/IRevlineEvents.sol";
import {CreditMath} from "../libraries/CreditMath.sol";
import {RevenueLib} from "../libraries/RevenueLib.sol";
import {USDCTransferLib} from "../libraries/USDCTransferLib.sol";

contract CreditFacet is ReentrancyGuard, IRevlineEvents {
    function creditTerms()
        external
        pure
        returns (
            uint256 revenueWindowDays,
            uint256 advanceRateBps,
            uint256 repaymentRateBps,
            uint256 feeBps,
            uint256 minTrailingRevenue,
            uint256 maxAdvance
        )
    {
        return (
            CreditMath.REVENUE_WINDOW_DAYS,
            CreditMath.ADVANCE_RATE_BPS,
            CreditMath.REPAYMENT_RATE_BPS,
            CreditMath.FEE_BPS,
            CreditMath.MIN_TRAILING_REVENUE,
            CreditMath.MAX_ADVANCE
        );
    }

    function creditQuote(address merchantAddress) external view returns (RevlineTypes.CreditQuote memory quote) {
        RevlineStorage.Layout storage $ = RevlineStorage.layout();
        RevlineTypes.Merchant storage merchant = $.merchants[merchantAddress];

        quote.trailingRevenue = RevenueLib.trailing30d(merchantAddress);
        quote.creditLimit = CreditMath.creditLimit(quote.trailingRevenue);
        quote.registered = merchant.registered;
        quote.creditEnabled = merchant.creditEnabled;
        quote.hasActiveAdvance = merchant.activeAdvanceId != 0;

        if (
            quote.trailingRevenue >= CreditMath.MIN_TRAILING_REVENUE && quote.registered && quote.creditEnabled
                && !quote.hasActiveAdvance
        ) {
            quote.drawableNow = CreditMath.min(quote.creditLimit, IERC20($.usdc).balanceOf(address(this)));
        }
    }

    function drawAdvance(uint256 principal) external nonReentrant returns (uint256 advanceId) {
        PausableLib.checkNotPaused();

        RevlineStorage.Layout storage $ = RevlineStorage.layout();
        RevlineTypes.Merchant storage merchant = $.merchants[msg.sender];
        if (!merchant.registered) revert IRevlineErrors.NotRegistered(msg.sender);
        if (!merchant.creditEnabled) revert IRevlineErrors.CreditNotEnabled(msg.sender);
        if (merchant.activeAdvanceId != 0) {
            revert IRevlineErrors.ActiveAdvanceExists(msg.sender, merchant.activeAdvanceId);
        }

        uint256 trailingRevenue = RevenueLib.trailing30d(msg.sender);
        if (trailingRevenue < CreditMath.MIN_TRAILING_REVENUE) {
            revert IRevlineErrors.InsufficientRevenue(trailingRevenue, CreditMath.MIN_TRAILING_REVENUE);
        }
        if (principal == 0) revert IRevlineErrors.InvalidAmount();

        uint256 creditLimit = CreditMath.creditLimit(trailingRevenue);
        if (principal > creditLimit) revert IRevlineErrors.AdvanceTooLarge(principal, creditLimit);

        uint256 liquid = IERC20($.usdc).balanceOf(address(this));
        if (principal > liquid) revert IRevlineErrors.InsufficientLiquidity(principal, liquid);

        uint256 fee = CreditMath.feeFor(principal);
        uint256 totalOwed = principal + fee;
        advanceId = ++$.advanceNonce;
        $.advances[advanceId] = RevlineTypes.Advance({
            merchant: msg.sender,
            principal: principal,
            principalOutstanding: principal,
            fee: fee,
            totalOwed: totalOwed,
            repaid: 0,
            drawnAt: uint64(block.timestamp),
            repaidAt: 0,
            status: RevlineTypes.AdvanceStatus.Active
        });
        $.merchantAdvances[msg.sender].push(advanceId);

        merchant.activeAdvanceId = advanceId;
        merchant.totalBorrowed += principal;
        $.totalAdvanced += principal;
        $.totalPrincipalOutstanding += principal;

        USDCTransferLib.safeTransfer($.usdc, merchant.payout, principal);
        emit AdvanceDrawn(advanceId, msg.sender, principal, fee, totalOwed, CreditMath.REPAYMENT_RATE_BPS);
    }

    function getAdvance(uint256 advanceId) external view returns (RevlineTypes.Advance memory) {
        return RevlineStorage.layout().advances[advanceId];
    }

    function getMerchantAdvanceIds(address merchant) external view returns (uint256[] memory) {
        return RevlineStorage.layout().merchantAdvances[merchant];
    }

    function poolStats() external view returns (RevlineTypes.PoolStats memory stats) {
        RevlineStorage.Layout storage $ = RevlineStorage.layout();
        uint256 liquid = IERC20($.usdc).balanceOf(address(this));

        stats = RevlineTypes.PoolStats({
            liquidUSDC: liquid,
            outstandingPrincipal: $.totalPrincipalOutstanding,
            totalAdvanced: $.totalAdvanced,
            totalRepaid: $.totalRepaid,
            totalFeesEarned: $.totalFeesEarned,
            managedAssets: liquid + $.totalPrincipalOutstanding
        });
    }
}
