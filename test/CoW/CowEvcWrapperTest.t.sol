// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {GPv2Signing} from "cow/mixins/GPv2Signing.sol";
import {GPv2Order} from "cow/libraries/GPv2Order.sol";
import {GPv2Trade, IERC20} from "cow/libraries/GPv2Trade.sol";

import {IEVC} from "ethereum-vault-connector/interfaces/IEthereumVaultConnector.sol";
import {IEVault, IERC4626, IBorrowing} from "evk/EVault/IEVault.sol";

import {EVaultTestBase} from "lib/euler-vault-kit/test/unit/evault/EVaultTestBase.t.sol";

import {CowEvcWrapper} from "../../src/CoW/CowEvcWrapper.sol";
import {AllowListAuthentication} from "../../src/CoW/vendor/AllowListAuthentication.sol";
import {CowSettlement, GPv2Trade} from "../../src/CoW/vendor/CowSettlement.sol";

import {console} from "forge-std/Test.sol";

import {CowBaseTest} from "./helpers/CowBaseTest.sol";

import {SignerECDSA} from "evc-test/unit/EthereumVaultConnector/Permit.t.sol";
import {SwapVerifier} from "../../src/Swaps/SwapVerifier.sol";

contract CowEvcWrapperTest is CowBaseTest {
    // Euler vaults


    SignerECDSA internal signerECDSA;

    function setUp() public override {
        super.setUp();
        signerECDSA = new SignerECDSA(evc);
    }

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
        uint256 susdsBalanceInMilkSwapBefore = IERC20(SUSDS).balanceOf(address(milkSwap));

        // Setup user with WETH
        deal(WETH, user, 1e18);
        vm.startPrank(user);

        // Create order parameters
        uint256 sellAmount = 1e18; // 1 WETH
        uint256 buyAmount = 1000e18; //  1000 SUSDS

        // Get settlement, that sells WETH for SUSDS
        (
            bytes memory orderUid,
            ,
            address[] memory tokens,
            uint256[] memory clearingPrices,
            GPv2Trade.Data[] memory trades,
            CowSettlement.InteractionData[][3] memory interactions
        ) = getSwapSettlement(user, user, sellAmount, buyAmount);

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
        assertEq(IERC20(SUSDS).balanceOf(user), buyAmount, "User should receive SUSDS");
        assertEq(IERC20(WETH).balanceOf(address(milkSwap)), sellAmount, "MilkSwap should receive WETH");

        uint256 susdsBalanceInMilkSwapAfter = IERC20(SUSDS).balanceOf(address(milkSwap));
        assertEq(susdsBalanceInMilkSwapAfter, susdsBalanceInMilkSwapBefore - buyAmount, "MilkSwap should have less SUSDS");
    }

    function test_leverage_WithCoWOrder() external {
        vm.skip(bytes(FORK_RPC_URL).length == 0);

        // sUSDS is not currently a collateral for WETH borrow, fix it
        vm.startPrank(IEVault(eWETH).governorAdmin());
        IEVault(eWETH).setLTV(eSUSDS, 0.9e4, 0.9e4, 0);

        uint256 SUSDS_MARGIN = 2000e18;
        // Setup user with SUSDS
        deal(SUSDS, user, SUSDS_MARGIN);

        vm.startPrank(user);

        // Create order parameters
        uint256 sellAmount = 1e18; // 1 WETH
        uint256 buyAmount = 1000e18; //  1000 SUSDS

        // Get settlement, that sells WETH for SUSDS
        // NOTE the receiver is the SUSDS vault, because we'll skim the output for the user in post-settlement
        (
            bytes memory orderUid,
            ,
            address[] memory tokens,
            uint256[] memory clearingPrices,
            GPv2Trade.Data[] memory trades,
            CowSettlement.InteractionData[][3] memory interactions
        ) = getSwapSettlement(user, eSUSDS, sellAmount, buyAmount);

        // User, pre-approve the order
        console.logBytes(orderUid);
        cowSettlement.setPreSignature(orderUid, true);


        signerECDSA.setPrivateKey(privateKey);

        // User approves SUSDS vault for deposit
        IERC20(SUSDS).approve(eSUSDS, type(uint).max);

        // Construct a batch with deposit of margin collateral and a borrow
        // TODO user approved CoW vault relayer on WETH, therefore the borrow to user's wallet
        // provides WETH to swap. It should be possible to do it without approval by setting borrow recipient
        // to some trusted contract. EVC wrapper? The next batch item could be approving the relayer.
        // How would an order be signed then?
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](4);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeCall(IEVC.enableCollateral, (user, eSUSDS))
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeCall(IEVC.enableController, (user, eWETH))
        });
        items[2] = IEVC.BatchItem({
            onBehalfOfAccount: user,
            targetContract: eSUSDS,
            value: 0,
            data: abi.encodeCall(IERC4626.deposit, (SUSDS_MARGIN, user))
        });
        items[3] = IEVC.BatchItem({
            onBehalfOfAccount: user,
            targetContract: eWETH,
            value: 0,
            data: abi.encodeCall(IBorrowing.borrow, (sellAmount, user))
        });

        // User signs the batch
        bytes memory batchData = abi.encodeCall(IEVC.batch, items);
        bytes memory batchSignature = signerECDSA.signPermit(user, address(wrapper), 0, 0, block.timestamp, 0, batchData);

        vm.stopPrank();

        // pre-settlement will include nested batch signed and executed through `EVC.permit`
        IEVC.BatchItem[] memory preSettlementItems = new IEVC.BatchItem[](1);
        preSettlementItems[0] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeCall(IEVC.permit, (user, address(wrapper), 0, 0, block.timestamp, 0, batchData, batchSignature))
        });


        // post-settlement will check slippage and skim the free cash on the destination vault for the user
        IEVC.BatchItem[] memory postSettlementItems = new IEVC.BatchItem[](1);
        postSettlementItems[0] = IEVC.BatchItem({
            onBehalfOfAccount: address(wrapper),
            targetContract: swapVerifier,
            value: 0,
            data: abi.encodeCall(SwapVerifier.verifyAmountMinAndSkim, (eSUSDS, user, buyAmount, block.timestamp))
        });


        // Execute the settlement through the wrapper
        vm.stopPrank();
        vm.startPrank(solver);

        wrapper.batchWithSettle(preSettlementItems, postSettlementItems, tokens, clearingPrices, trades, interactions);


        // Verify the position was created
        assertApproxEqAbs(
            IEVault(eSUSDS).convertToAssets(IERC20(eSUSDS).balanceOf(user)),
            IEVault(eSUSDS).convertToShares(buyAmount) + SUSDS_MARGIN, 5e18,
            "User should receive eSUSDS"
        );
        assertEq(IEVault(eWETH).debtOf(user), sellAmount, "User should receive eWETH debt");

        // uint256 susdsBalanceInMilkSwapAfter = IERC20(SUSDS).balanceOf(address(milkSwap));
        // assertEq(susdsBalanceInMilkSwapAfter, susdsBalanceInMilkSwapBefore - buyAmount, "MilkSwap should have less SUSDS");
    }
}
