// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDiamondCut} from "@diamond/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IPausable} from "@lattice/interfaces/security/IPausable.sol";
import {Test} from "forge-std/Test.sol";
import {DeployRevline} from "../../script/DeployRevline.s.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";

abstract contract RevlineTestBase is Test {
    uint256 internal constant LARGE_BALANCE = 1_000_000e6;

    MockUSDC internal usdc;
    Lattice internal diamond;
    IAccessControl internal accessControl;
    IPausable internal pausable;
    IDiamondCut internal diamondCut;
    IDiamondLoupe internal loupe;

    address internal admin;
    address internal merchant;
    address internal customer;

    function setUp() public virtual {
        admin = makeAddr("admin");
        merchant = makeAddr("merchant");
        customer = makeAddr("customer");

        usdc = new MockUSDC();
        diamond = new DeployRevline().deploy(address(usdc), admin);

        accessControl = IAccessControl(address(diamond));
        pausable = IPausable(address(diamond));
        diamondCut = IDiamondCut(address(diamond));
        loupe = IDiamondLoupe(address(diamond));

        usdc.mint(admin, LARGE_BALANCE);
        usdc.mint(customer, LARGE_BALANCE);
        usdc.mint(address(diamond), LARGE_BALANCE);
    }

    function _approveCustomer(uint256 amount) internal {
        vm.prank(customer);
        usdc.approve(address(diamond), amount);
    }
}
