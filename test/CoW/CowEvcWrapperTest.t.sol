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

    address constant DAI = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    CowSettlement constant cowSettlement = CowSettlement(0x9008D19f58AAbD9eD0D60971565AA8510560ab41);

    CowEvcWrapper public wrapper;
    MilkSwap public milkSwap;
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
        address manager = allowList.manager();
        // vm.deal(address(manager), 1e18);
        vm.startPrank(manager);
        allowList.addSolver(address(wrapper));
        vm.stopPrank();

        // Setup some liquidity for MilkSwap
        milkSwap = new MilkSwap();
        deal(DAI, address(milkSwap), 1000e18); // Add DAI to MilkSwap

        // User has approved WETH for COW Protocol
        IERC20(WETH).approve(address(cowSettlement.vaultRelayer()), type(uint256).max);
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

contract MilkSwap {
    // Mock price for testing - 1:1 ratio
    uint256 constant PRICE = 1e18;

    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn)
        external
        pure
        returns (uint256 amountOut)
    {
        return (amountIn * PRICE) / 1e18;
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn) external {
        uint256 amountOut = getAmountOut(tokenIn, tokenOut, amountIn);
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).transfer(msg.sender, amountOut);
    }
}
