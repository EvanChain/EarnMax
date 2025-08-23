// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct SwapUnit {
    /// @notice Adapter's address
    address adapter;
    /// @notice Input token address
    address tokenIn;
    /// @notice Output token address
    address tokenOut;
    /// @notice Encoded swap data
    bytes swapData;
}

interface IERC20SwapAdapter {
    /// @notice Swap tokenIn to tokenOut
    /// @param recipient Address to receive the output tokens
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address
    /// @param tokenInAmt token input amount
    /// @param swapData Encoded swap data
    /// @return tokenOutAmt token output amount
    function swap(address recipient, address tokenIn, address tokenOut, uint256 tokenInAmt, bytes memory swapData)
        external
        returns (uint256 tokenOutAmt);
}
