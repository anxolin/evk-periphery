// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import {GPv2Trade} from "cow/libraries/GPv2Trade.sol";
import {AllowListAuthentication} from "./AllowListAuthentication.sol";

interface CowSettlement {
    struct InteractionData {
        address to;
        uint256 value;
        bytes callData;
    }

    function settle(
        address[] memory tokens,
        uint256[] memory clearingPrices,
        GPv2Trade.Data[] memory trades,
        InteractionData[][3] memory interactions
    ) external;

    function setPreSignature(bytes calldata orderUid, bool signed) external;

    function domainSeparator() external view returns (bytes32);

    function vaultRelayer() external view returns (address);

    function authenticator() external view returns (AllowListAuthentication);
}
