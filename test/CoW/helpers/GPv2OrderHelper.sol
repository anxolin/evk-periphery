// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {GPv2Signing} from "cow/mixins/GPv2Signing.sol";
import {GPv2Order} from "cow/libraries/GPv2Order.sol";
import {GPv2Trade, IERC20} from "cow/libraries/GPv2Trade.sol";

import {console} from "forge-std/Test.sol";

contract GPv2OrderHelper {
    using GPv2Order for bytes;

    function extractOrderUidParams(bytes calldata orderUid)
        external
        pure
        returns (bytes32 orderDigest, address owner, uint32 validTo)
    {
        return orderUid.extractOrderUidParams();
    }

    function extractOrder(GPv2Trade.Data calldata trade, IERC20[] calldata tokens)
        external
        pure
        returns (GPv2Order.Data memory extractedOrder, GPv2Signing.Scheme scheme)
    {
        GPv2Order.Data memory order;
        scheme = GPv2Trade.extractOrder(trade, tokens, order);
        return (order, scheme);
    }
}
