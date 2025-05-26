// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IEVC} from "ethereum-vault-connector/interfaces/IEthereumVaultConnector.sol";
import {EVaultTestBase} from "lib/euler-vault-kit/test/unit/evault/EVaultTestBase.t.sol";
import {IEVault, IERC4626, IERC20} from "lib/euler-vault-kit/src/EVault/IEVault.sol";

import {CowSettlement} from "../../src/CoW/vendor/CowSettlement.sol";
import {CowEvcWrapper} from "../../src/CoW/CowEvcWrapper.sol";
import {AllowListAuthentication} from "../../src/CoW/vendor/AllowListAuthentication.sol";

import "forge-std/Test.sol";

contract CowEvcWrapperTest is EVaultTestBase {
    uint256 mainnetFork;
    uint256 BLOCK_NUMBER = 22546006;
    string FORK_RPC_URL = vm.envOr("FORK_RPC_URL", string(""));

    address constant solver = 0x7E2eF26AdccB02e57258784957922AEEFEe807e5; // quasilabs
    address constant allowListManager = 0xA03be496e67Ec29bC62F01a428683D7F9c204930;

    CowSettlement constant cowSettlement = CowSettlement(0x9008D19f58AAbD9eD0D60971565AA8510560ab41);

    CowEvcWrapper public wrapper;
    address user;

    function setUp() public virtual override {
        super.setUp();

        if (bytes(FORK_RPC_URL).length != 0) {
            mainnetFork = vm.createSelectFork(FORK_RPC_URL);
            vm.rollFork(BLOCK_NUMBER);
        }

        user = makeAddr("user");
        wrapper = new CowEvcWrapper(address(evc), address(cowSettlement));

        // Add wrapper as solver
        AllowListAuthentication allowList = cowSettlement.authenticator();
        console.log("cowSettlement", address(cowSettlement));
        console.log("allowListAddress", address(allowList));
        address manager = allowList.manager();
        // vm.deal(address(manager), 1e18);
        vm.startPrank(manager);
        allowList.addSolver(address(wrapper));
        vm.stopPrank();
    }

    function getEmptySettlement()
        public
        pure
        returns (
            address[] memory tokens,
            uint256[] memory clearingPrices,
            CowSettlement.TradeData[] memory trades,
            CowSettlement.InteractionData[][3] memory interactions
        )
    {
        return (
            new address[](0),
            new uint256[](0),
            new CowSettlement.TradeData[](0),
            [
                new CowSettlement.InteractionData[](0),
                new CowSettlement.InteractionData[](0),
                new CowSettlement.InteractionData[](0)
            ]
        );
    }

    function test_batchWithSettle_Empty() external {
        vm.skip(bytes(FORK_RPC_URL).length == 0);
        vm.startPrank(solver);

        (
            address[] memory tokens,
            uint256[] memory clearingPrices,
            CowSettlement.TradeData[] memory trades,
            CowSettlement.InteractionData[][3] memory interactions
        ) = getEmptySettlement();

        IEVC.BatchItem[] memory preSettlementItems = new IEVC.BatchItem[](0);
        IEVC.BatchItem[] memory postSettlementItems = new IEVC.BatchItem[](0);

        wrapper.batchWithSettle(preSettlementItems, postSettlementItems, tokens, clearingPrices, trades, interactions);
    }

    function test_batchWithSettle_NonSolver() external {
        vm.skip(bytes(FORK_RPC_URL).length == 0);
        address nonSolver = makeAddr("nonSolver");
        vm.startPrank(nonSolver);

        (
            address[] memory tokens,
            uint256[] memory clearingPrices,
            CowSettlement.TradeData[] memory trades,
            CowSettlement.InteractionData[][3] memory interactions
        ) = getEmptySettlement();

        IEVC.BatchItem[] memory preSettlementItems = new IEVC.BatchItem[](0);
        IEVC.BatchItem[] memory postSettlementItems = new IEVC.BatchItem[](0);

        vm.expectRevert("Not a valid solver");
        wrapper.batchWithSettle(preSettlementItems, postSettlementItems, tokens, clearingPrices, trades, interactions);
    }
}

contract SimpleStorage {
    uint256 public value;

    function setValue(uint256 newValue) external {
        value = newValue;
    }
}
