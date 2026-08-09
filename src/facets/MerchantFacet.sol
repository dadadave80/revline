// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";
import {RevlineRoles} from "../RevlineRoles.sol";
import {RevlineStorage} from "../RevlineStorage.sol";
import {RevlineTypes} from "../RevlineTypes.sol";
import {IRevlineErrors} from "../interfaces/IRevlineErrors.sol";
import {IRevlineEvents} from "../interfaces/IRevlineEvents.sol";
import {RevenueLib} from "../libraries/RevenueLib.sol";

contract MerchantFacet is IRevlineEvents {
    function registerMerchant(string calldata name) external {
        PausableLib.checkNotPaused();

        RevlineStorage.Layout storage $ = RevlineStorage.layout();
        RevlineTypes.Merchant storage merchant = $.merchants[msg.sender];
        if (merchant.registered) revert IRevlineErrors.AlreadyRegistered(msg.sender);

        uint256 nameLength = bytes(name).length;
        if (nameLength == 0 || nameLength > 64) revert IRevlineErrors.InvalidNameLength(nameLength);

        merchant.registered = true;
        merchant.payout = msg.sender;
        merchant.registeredAt = uint64(block.timestamp);
        merchant.name = name;

        emit MerchantRegistered(msg.sender, msg.sender, name);
    }

    function setPayoutAddress(address newPayout) external {
        PausableLib.checkNotPaused();

        RevlineStorage.Layout storage $ = RevlineStorage.layout();
        RevlineTypes.Merchant storage merchant = $.merchants[msg.sender];
        if (!merchant.registered) revert IRevlineErrors.NotRegistered(msg.sender);
        if (newPayout == address(0) || newPayout == address(this)) revert IRevlineErrors.ZeroAddress();

        address oldPayout = merchant.payout;
        merchant.payout = newPayout;

        emit PayoutUpdated(msg.sender, oldPayout, newPayout);
    }

    function setCreditEnabled(address merchantAddress, bool enabled) external {
        AccessControlLib.checkRole(RevlineRoles.UNDERWRITER_ROLE);

        RevlineTypes.Merchant storage merchant = RevlineStorage.layout().merchants[merchantAddress];
        if (!merchant.registered) revert IRevlineErrors.NotRegistered(merchantAddress);

        merchant.creditEnabled = enabled;
        emit CreditEligibilityUpdated(merchantAddress, enabled, msg.sender);
    }

    function getMerchant(address merchant) external view returns (RevlineTypes.Merchant memory) {
        return RevlineStorage.layout().merchants[merchant];
    }

    function trailingRevenue(address merchant) external view returns (uint256) {
        return RevenueLib.trailing30d(merchant);
    }
}
