// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";
import {RevlineRoles} from "./RevlineRoles.sol";
import {RevlineStorage} from "./RevlineStorage.sol";
import {IRevlineErrors} from "./interfaces/IRevlineErrors.sol";

contract RevlineInit {
    function init(address admin, address usdc) external {
        if (admin == address(0) || usdc == address(0)) {
            revert IRevlineErrors.ZeroAddress();
        }

        RevlineStorage.Layout storage $ = RevlineStorage.layout();
        require($.usdc == address(0), "Revline: already initialized");

        AccessControlLib.__AccessControl_init(admin);
        AccessControlLib._grantRole(RevlineRoles.UNDERWRITER_ROLE, admin);
        PausableLib.__Pausable_init();

        $.usdc = usdc;
    }
}
