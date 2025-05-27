// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IEVC} from "ethereum-vault-connector/interfaces/IEthereumVaultConnector.sol";
import {CowSettlement, GPv2Trade} from "./vendor/CowSettlement.sol";

/// @title CowEvcWrapper
/// @notice A wrapper around the EVC that allows for settlement operations
contract CowEvcWrapper {
    IEVC public immutable evc;
    CowSettlement public immutable settlement;

    constructor(address _evc, address _settlement) {
        evc = IEVC(_evc);
        settlement = CowSettlement(_settlement);
    }

    /// @notice Executes a batch of EVC operations with a settlement in between
    /// @param preSettlementItems Items to execute before settlement
    /// @param postSettlementItems Items to execute after settlement
    /// @param tokens Tokens involved in settlement
    /// @param clearingPrices Clearing prices for settlement
    /// @param trades Trade data for settlement
    /// @param interactions Interaction data for settlement
    function batchWithSettle(
        IEVC.BatchItem[] calldata preSettlementItems,
        IEVC.BatchItem[] calldata postSettlementItems,
        address[] calldata tokens,
        uint256[] calldata clearingPrices,
        GPv2Trade.Data[] calldata trades,
        CowSettlement.InteractionData[][3] calldata interactions
    ) external payable {
        // Revert if not a valid solver
        if (!settlement.authenticator().isSolver(msg.sender)) {
            revert("Not a valid solver");
        }

        // Create a single batch with all items
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](preSettlementItems.length + postSettlementItems.length + 1);

        // Copy pre-settlement items
        for (uint256 i = 0; i < preSettlementItems.length; i++) {
            items[i] = preSettlementItems[i];
        }

        // Add settlement call to wrapper
        items[preSettlementItems.length] = IEVC.BatchItem({
            onBehalfOfAccount: msg.sender,
            targetContract: address(this),
            value: 0,
            data: abi.encodeCall(this.settle, (tokens, clearingPrices, trades, interactions))
        });

        // Copy post-settlement items
        for (uint256 i = 0; i < postSettlementItems.length; i++) {
            items[preSettlementItems.length + 1 + i] = postSettlementItems[i];
        }

        // Execute all items in a single batch
        evc.batch(items);
    }

    /// @notice Executes a batch of EVC operations
    /// @param tokens Tokens involved in settlement
    /// @param clearingPrices Clearing prices for settlement
    /// @param trades Trade data for settlement
    /// @param interactions Interaction data for settlement
    function settle(
        address[] calldata tokens,
        uint256[] calldata clearingPrices,
        GPv2Trade.Data[] calldata trades,
        CowSettlement.InteractionData[][3] calldata interactions
    ) external payable {
        // TODO: This is unsecure, only for demostration purposes (it should use transient data and avoid re-entrancies)
        settlement.settle(tokens, clearingPrices, trades, interactions);
    }
}
