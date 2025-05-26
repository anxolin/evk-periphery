// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IEVC} from "ethereum-vault-connector/interfaces/IEthereumVaultConnector.sol";
import {CowSettlement} from "./vendor/CowSettlement.sol";

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
    /// @param preItems Items to execute before settlement
    /// @param tokens Tokens involved in settlement
    /// @param clearingPrices Clearing prices for settlement
    /// @param trades Trade data for settlement
    /// @param interactions Interaction data for settlement
    /// @param postItems Items to execute after settlement
    function batchWithSettle(
        IEVC.BatchItem[] calldata preItems,
        address[] calldata tokens,
        uint256[] calldata clearingPrices,
        CowSettlement.TradeData[] calldata trades,
        CowSettlement.InteractionData[][3] calldata interactions,
        IEVC.BatchItem[] calldata postItems
    ) external payable {
        // TODO: Revert if not a valid solver. The wrapper will be a solver itself, so we need to only allow solvers to
        // invoke

        // Execute pre-settlement items
        if (preItems.length > 0) {
            evc.batch(preItems);
        }

        // Execute settlement
        settlement.settle(tokens, clearingPrices, trades, interactions);

        // Execute post-settlement items
        if (postItems.length > 0) {
            evc.batch(postItems);
        }
    }

    /// @notice Executes a batch of EVC operations
    /// @param items Items to execute
    function batch(IEVC.BatchItem[] calldata items) external payable {
        evc.batch(items);
    }
}
