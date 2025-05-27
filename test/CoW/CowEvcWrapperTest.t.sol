// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {GPv2Signing} from "cow/mixins/GPv2Signing.sol";
import {GPv2Order} from "cow/libraries/GPv2Order.sol";
import {GPv2Trade, IERC20} from "cow/libraries/GPv2Trade.sol";

import {IEVC} from "ethereum-vault-connector/interfaces/IEthereumVaultConnector.sol";
import {EVaultTestBase} from "lib/euler-vault-kit/test/unit/evault/EVaultTestBase.t.sol";

import {CowEvcWrapper} from "../../src/CoW/CowEvcWrapper.sol";
import {AllowListAuthentication} from "../../src/CoW/vendor/AllowListAuthentication.sol";
import {CowSettlement, GPv2Trade} from "../../src/CoW/vendor/CowSettlement.sol";

import {console} from "forge-std/Test.sol";

import {CowBaseTest} from "./helpers/CowBaseTest.sol";

contract CowEvcWrapperTest is CowBaseTest {
    function test_batchWithSettle_Empty() external {
        vm.skip(bytes(FORK_RPC_URL).length == 0);

        (
            address[] memory tokens,
            uint256[] memory clearingPrices,
            GPv2Trade.Data[] memory trades,
            CowSettlement.InteractionData[][3] memory interactions
        ) = getEmptySettlement();

        IEVC.BatchItem[] memory preSettlementItems = new IEVC.BatchItem[](0);
        IEVC.BatchItem[] memory postSettlementItems = new IEVC.BatchItem[](0);

        vm.prank(solver);
        wrapper.batchWithSettle(preSettlementItems, postSettlementItems, tokens, clearingPrices, trades, interactions);
    }

    function test_batchWithSettle_NonSolver() external {
        vm.skip(bytes(FORK_RPC_URL).length == 0);
        address nonSolver = makeAddr("nonSolver");
        vm.startPrank(nonSolver);

        (
            address[] memory tokens,
            uint256[] memory clearingPrices,
            GPv2Trade.Data[] memory trades,
            CowSettlement.InteractionData[][3] memory interactions
        ) = getEmptySettlement();

        IEVC.BatchItem[] memory preSettlementItems = new IEVC.BatchItem[](0);
        IEVC.BatchItem[] memory postSettlementItems = new IEVC.BatchItem[](0);

        vm.expectRevert("Not a valid solver");
        wrapper.batchWithSettle(preSettlementItems, postSettlementItems, tokens, clearingPrices, trades, interactions);
    }

    function test_batchWithSettle_WithCoWOrder() external {
        vm.skip(bytes(FORK_RPC_URL).length == 0);
        uint256 daiBalanceInMilkSwapBefore = IERC20(DAI).balanceOf(address(milkSwap));

        // Setup user with WETH
        deal(WETH, user, 1e18);
        vm.startPrank(user);

        // Create order parameters
        uint256 sellAmount = 1e18; // 1 WETH
        uint256 buyAmount = 1000e18; //  1000 DAI

        // Get settlement, that sells WETH for DAI
        (
            bytes memory orderUid,
            ,
            address[] memory tokens,
            uint256[] memory clearingPrices,
            GPv2Trade.Data[] memory trades,
            CowSettlement.InteractionData[][3] memory interactions
        ) = getSwapSettlement(user, sellAmount, buyAmount);

        // User, pre-approve the order
        console.logBytes(orderUid);
        cowSettlement.setPreSignature(orderUid, true);

        // Execute the settlement through the wrapper
        vm.stopPrank();
        vm.startPrank(solver);

        IEVC.BatchItem[] memory preSettlementItems = new IEVC.BatchItem[](0);
        IEVC.BatchItem[] memory postSettlementItems = new IEVC.BatchItem[](0);
        wrapper.batchWithSettle(preSettlementItems, postSettlementItems, tokens, clearingPrices, trades, interactions);

        // Verify the swap was executed
        assertEq(IERC20(DAI).balanceOf(user), buyAmount, "User should receive DAI");
        assertEq(IERC20(WETH).balanceOf(address(milkSwap)), sellAmount, "MilkSwap should receive WETH");

        uint256 daiBalanceInMilkSwapAfter = IERC20(DAI).balanceOf(address(milkSwap));
        assertEq(daiBalanceInMilkSwapAfter, daiBalanceInMilkSwapBefore - buyAmount, "MilkSwap should have less DAI");
    }
}
