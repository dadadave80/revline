// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Lattice} from "@lattice/Lattice.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {Pausable} from "@lattice/security/Pausable.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {MultiInit} from "@diamond/initializers/MultiInit.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {IERC8153} from "@lattice/interfaces/external/ercs/IERC8153.sol";
import {Receive} from "@lattice/Receive.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {RevlineInit} from "../src/RevlineInit.sol";
import {CreditFacet} from "../src/facets/CreditFacet.sol";
import {InvoiceFacet} from "../src/facets/InvoiceFacet.sol";
import {MerchantFacet} from "../src/facets/MerchantFacet.sol";

contract DeployRevline is Script {
    address internal constant ARC_USDC = 0x3600000000000000000000000000000000000000;

    function _exportedSelectors(address facet) internal view returns (bytes4[] memory selectors) {
        (bool ok, bytes memory ret) = facet.staticcall(abi.encodeCall(IERC8153.exportSelectors, ()));
        require(ok, "exportSelectors reverted");

        bytes memory packed = abi.decode(ret, (bytes));
        require(packed.length != 0, "no selectors");
        require(packed.length % 4 == 0, "bad selector bytes");

        uint256 count = packed.length / 4;
        selectors = new bytes4[](count);

        for (uint256 i; i < count; ++i) {
            bytes4 sel;
            assembly ("memory-safe") {
                sel := mload(add(add(packed, 0x20), mul(i, 4)))
            }
            selectors[i] = sel;
        }
    }

    function _add(address facet) internal view returns (FacetCut memory) {
        return FacetCut({facetAddress: facet, action: FacetCutAction.Add, functionSelectors: _exportedSelectors(facet)});
    }

    function deploy(address usdc, address admin) public returns (Lattice diamond) {
        require(usdc != address(0), "USDC is zero");
        require(admin != address(0), "admin is zero");

        FacetCut[] memory cuts = new FacetCut[](9);
        cuts[0] = _add(address(new Receive()));
        cuts[1] = _add(address(new ERC165Facet()));
        cuts[2] = _add(address(new AccessControl()));
        cuts[3] = _add(address(new Pausable()));
        cuts[4] = _add(address(new DiamondLoupeFacet()));
        cuts[5] = _add(address(new AccessControlDiamondCut()));
        cuts[6] = FacetCut({
            facetAddress: address(new MerchantFacet()),
            action: FacetCutAction.Add,
            functionSelectors: _merchantSelectors()
        });
        cuts[7] = FacetCut({
            facetAddress: address(new InvoiceFacet()),
            action: FacetCutAction.Add,
            functionSelectors: _invoiceSelectors()
        });
        cuts[8] = FacetCut({
            facetAddress: address(new CreditFacet()), action: FacetCutAction.Add, functionSelectors: _creditSelectors()
        });

        address[] memory initAddresses = new address[](2);
        initAddresses[0] = address(new RevlineInit());
        initAddresses[1] = address(new DiamondIntrospectionInit());

        bytes[] memory initData = new bytes[](2);
        initData[0] = abi.encodeCall(RevlineInit.init, (admin, usdc));
        initData[1] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());

        MultiInit multiInit = new MultiInit();
        diamond = new Lattice();
        diamond.initialize(cuts, address(multiInit), abi.encodeCall(MultiInit.multiInit, (initAddresses, initData)));
    }

    function _merchantSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](5);
        s[0] = MerchantFacet.registerMerchant.selector;
        s[1] = MerchantFacet.setPayoutAddress.selector;
        s[2] = MerchantFacet.setCreditEnabled.selector;
        s[3] = MerchantFacet.getMerchant.selector;
        s[4] = MerchantFacet.trailingRevenue.selector;
    }

    function _invoiceSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](5);
        s[0] = InvoiceFacet.createInvoice.selector;
        s[1] = InvoiceFacet.cancelInvoice.selector;
        s[2] = InvoiceFacet.payInvoice.selector;
        s[3] = InvoiceFacet.getInvoice.selector;
        s[4] = InvoiceFacet.getMerchantInvoiceIds.selector;
    }

    function _creditSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](6);
        s[0] = CreditFacet.creditTerms.selector;
        s[1] = CreditFacet.creditQuote.selector;
        s[2] = CreditFacet.drawAdvance.selector;
        s[3] = CreditFacet.getAdvance.selector;
        s[4] = CreditFacet.getMerchantAdvanceIds.selector;
        s[5] = CreditFacet.poolStats.selector;
    }

    function run() external returns (Lattice diamond) {
        address admin = msg.sender;
        require(ARC_USDC.code.length != 0, "Arc USDC unavailable");

        vm.startBroadcast();
        diamond = deploy(ARC_USDC, admin);
        console2.log("Revline Diamond", address(diamond));
        console2.log("Arc USDC", ARC_USDC);
        console2.log("Admin / underwriter", admin);
        vm.stopBroadcast();
    }
}
