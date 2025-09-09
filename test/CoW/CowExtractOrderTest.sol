// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {GPv2Signing} from "cow/mixins/GPv2Signing.sol";
import {GPv2Order} from "cow/libraries/GPv2Order.sol";
import {GPv2Trade, IERC20} from "cow/libraries/GPv2Trade.sol";

import {EVaultTestBase} from "lib/euler-vault-kit/test/unit/evault/EVaultTestBase.t.sol";

import {CowEvcWrapper} from "../../src/CoW/CowEvcWrapper.sol";
import {AllowListAuthentication} from "../../src/CoW/vendor/AllowListAuthentication.sol";
import {CowSettlement} from "../../src/CoW/vendor/CowSettlement.sol";

import {CowBaseTest} from "./helpers/CowBaseTest.sol";

import {console} from "forge-std/Test.sol";

contract CowExtractOrderTest is CowBaseTest {
    // I just created this to debug issues with the pre-signing
    function test_orderUid_extraction() external {
        vm.skip(bytes(FORK_RPC_URL).length == 0);

        // Get order ID
        uint256 sellAmount = 1e18; // 1 WETH
        uint256 buyAmount = 1000e18; //  1000 DAI
        (bytes memory orderUid, GPv2Order.Data memory orderData,,,,) = getSwapSettlement(user, user, sellAmount, buyAmount);

        // Extract parameters from order UID using helper
        (bytes32 extractedOrderDigest, address extractedOwner, uint32 extractedValidTo) =
            helper.extractOrderUidParams(orderUid);

        // Verify the extracted parameters match the original values
        assertEq(
            extractedOrderDigest, GPv2Order.hash(orderData, cowSettlement.domainSeparator()), "Order digest mismatch"
        );
        assertEq(extractedOwner, user, "Owner mismatch");
        assertEq(extractedValidTo, orderData.validTo, "ValidTo mismatch");
    }

    // This test is to debug issues with the pre-signing. I want to reproduce what the settlement does to recover the
    // order from the trade data.
    function test_order_extraction_from_trade() external {
        vm.skip(bytes(FORK_RPC_URL).length == 0);

        // Create order parameters
        uint256 sellAmount = 1e18; // 1 WETH
        uint256 buyAmount = 1000e18; // 1000 DAI

        // Get settlement data
        (
            bytes memory orderUid,
            GPv2Order.Data memory originalOrder,
            address[] memory tokens,
            ,
            GPv2Trade.Data[] memory trades,
        ) = getSwapSettlement(user, user, sellAmount, buyAmount);

        // Convert tokens to IERC20 array
        IERC20[] memory erc20Tokens = new IERC20[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            erc20Tokens[i] = IERC20(tokens[i]);
        }

        // Extract order from trade using helper
        (GPv2Order.Data memory extractedOrder, GPv2Signing.Scheme scheme) = helper.extractOrder(trades[0], erc20Tokens);

        // Verify the extracted order matches the original order
        assertEq(address(extractedOrder.sellToken), address(originalOrder.sellToken), "Sell token mismatch");
        assertEq(address(extractedOrder.buyToken), address(originalOrder.buyToken), "Buy token mismatch");
        assertEq(extractedOrder.receiver, originalOrder.receiver, "Receiver mismatch");
        assertEq(extractedOrder.sellAmount, originalOrder.sellAmount, "Sell amount mismatch");
        assertEq(extractedOrder.buyAmount, originalOrder.buyAmount, "Buy amount mismatch");
        assertEq(extractedOrder.validTo, originalOrder.validTo, "ValidTo mismatch");
        assertEq(extractedOrder.appData, originalOrder.appData, "AppData mismatch");
        assertEq(extractedOrder.feeAmount, originalOrder.feeAmount, "Fee amount mismatch");
        assertEq(extractedOrder.kind, originalOrder.kind, "Kind mismatch");
        assertEq(extractedOrder.partiallyFillable, originalOrder.partiallyFillable, "Partially fillable mismatch");
        assertEq(extractedOrder.sellTokenBalance, originalOrder.sellTokenBalance, "Sell token balance mismatch");
        assertEq(extractedOrder.buyTokenBalance, originalOrder.buyTokenBalance, "Buy token balance mismatch");

        // Assert the scheme is 712
        require(scheme != GPv2Signing.Scheme.Eip712, "Signing scheme doesn't match");

        // Verify the orderUid matches the orderId generated from the extractedOrder
        assertEq(getOrderUid(user, extractedOrder), orderUid, "OrderUid mismatch");
    }
}
