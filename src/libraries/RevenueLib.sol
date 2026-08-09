// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {RevlineStorage} from "../RevlineStorage.sol";
import {CreditMath} from "./CreditMath.sol";

library RevenueLib {
    function currentDay() internal view returns (uint32) {
        return uint32(block.timestamp / 1 days);
    }

    function record(address merchant, uint256 gross) internal {
        RevlineStorage.Layout storage $ = RevlineStorage.layout();
        uint32 day = currentDay();
        $.revenueByDay[merchant][day] += gross;
        $.merchants[merchant].lifetimeRevenue += gross;
    }

    function trailing30d(address merchant) internal view returns (uint256 total) {
        RevlineStorage.Layout storage $ = RevlineStorage.layout();
        uint32 day = currentDay();

        for (uint256 i; i < CreditMath.REVENUE_WINDOW_DAYS; ++i) {
            if (uint256(day) < i) break;
            total += $.revenueByDay[merchant][day - uint32(i)];
        }
    }
}
