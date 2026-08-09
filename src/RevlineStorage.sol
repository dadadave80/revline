// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {RevlineTypes} from "./RevlineTypes.sol";

library RevlineStorage {
    bytes32 internal constant NAMESPACE = keccak256("revline.storage.Core.v1");

    struct Layout {
        address usdc;

        uint256 invoiceNonce;
        uint256 advanceNonce;

        uint256 totalPrincipalOutstanding;
        uint256 totalAdvanced;
        uint256 totalRepaid;
        uint256 totalFeesEarned;

        mapping(address merchant => RevlineTypes.Merchant) merchants;
        mapping(uint256 invoiceId => RevlineTypes.Invoice) invoices;
        mapping(uint256 advanceId => RevlineTypes.Advance) advances;

        mapping(address merchant => mapping(uint32 dayIndex => uint256 amount)) revenueByDay;
        mapping(address merchant => uint256[] invoiceIds) merchantInvoices;
        mapping(address merchant => uint256[] advanceIds) merchantAdvances;
    }

    function layout() internal pure returns (Layout storage $) {
        bytes32 namespace = NAMESPACE;
        bytes32 slot = keccak256(abi.encode(uint256(namespace) - 1)) & ~bytes32(uint256(0xff));
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function storageSlot() internal pure returns (bytes32) {
        bytes32 namespace = NAMESPACE;
        return keccak256(abi.encode(uint256(namespace) - 1)) & ~bytes32(uint256(0xff));
    }
}
