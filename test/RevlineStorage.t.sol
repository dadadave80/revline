// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {RevlineStorage} from "../src/RevlineStorage.sol";

contract RevlineStorageTest is Test {
    function test_storageSlotIsERC7201Aligned() public pure {
        bytes32 slot = RevlineStorage.storageSlot();
        assertEq(uint256(slot) & 0xff, 0);
    }

    function test_storageSlotMatchesFormula() public pure {
        bytes32 namespace = keccak256("revline.storage.Core.v1");
        bytes32 expected = keccak256(abi.encode(uint256(namespace) - 1)) & ~bytes32(uint256(0xff));

        assertEq(RevlineStorage.storageSlot(), expected);
    }
}
