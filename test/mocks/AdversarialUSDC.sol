// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract AdversarialUSDC {
    enum Behavior {
        Normal,
        ReturnFalse,
        RevertCall,
        Reenter
    }

    mapping(address account => uint256) public balanceOf;
    mapping(address owner => mapping(address spender => uint256)) public allowance;

    Behavior public behavior;
    address public callbackTarget;
    bytes public callbackData;
    bool public callbackSucceeded;
    bytes4 public callbackRevertSelector;

    error ForcedRevert();

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function configure(Behavior newBehavior, address target, bytes calldata data) external {
        behavior = newBehavior;
        callbackTarget = target;
        callbackData = data;
        callbackSucceeded = false;
        callbackRevertSelector = bytes4(0);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (!_beforeTransfer()) return false;
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (!_beforeTransfer()) return false;

        uint256 approved = allowance[from][msg.sender];
        require(approved >= amount, "allowance");
        allowance[from][msg.sender] = approved - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _beforeTransfer() internal returns (bool) {
        if (behavior == Behavior.ReturnFalse) return false;
        if (behavior == Behavior.RevertCall) revert ForcedRevert();
        if (behavior == Behavior.Reenter) {
            (bool succeeded, bytes memory ret) = callbackTarget.call(callbackData);
            callbackSucceeded = succeeded;
            if (ret.length >= 4) {
                bytes4 selector;
                assembly ("memory-safe") {
                    selector := mload(add(ret, 0x20))
                }
                callbackRevertSelector = selector;
            }
        }
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}
