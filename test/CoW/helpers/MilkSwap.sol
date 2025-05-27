// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IERC20} from "cow/libraries/GPv2Trade.sol";

contract MilkSwap {
    mapping(address => uint256) public prices; // Price expressed in atoms of the quote per unit of the base token
    address public quoteToken;

    constructor(address _quoteToken) {
        quoteToken = _quoteToken;
    }

    function setPrice(address token, uint256 price) external {
        prices[token] = price;
    }

    function getAmountOut(address tokenIn, uint256 amountIn) external view returns (uint256 amountOut) {
        uint256 price = prices[tokenIn];
        require(price > 0, "tokenIn is not supported");

        return (amountIn * price);
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn) external {
        require(tokenOut == quoteToken, "tokenOut must be the quote token");

        uint256 amountOut = this.getAmountOut(tokenIn, amountIn);

        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).transfer(msg.sender, amountOut);
    }
}
