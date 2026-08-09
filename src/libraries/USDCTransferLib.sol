// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";

library USDCTransferLib {
    error USDCTransferFailed(address token);

    function safeTransfer(address token, address to, uint256 amount) internal {
        if (amount == 0) return;

        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));

        if (!ok || (ret.length == 0 ? token.code.length == 0 : !abi.decode(ret, (bool)))) {
            revert USDCTransferFailed(token);
        }
    }

    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount));

        if (!ok || (ret.length == 0 ? token.code.length == 0 : !abi.decode(ret, (bool)))) {
            revert USDCTransferFailed(token);
        }
    }
}
