// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20SwapAdapter} from "../interfaces/IERC20SwapAdapter.sol";
import {OnlyProxyCall} from "../utils/OnlyProxyCall.sol";

abstract contract ERC20SwapAdapter is IERC20SwapAdapter, OnlyProxyCall {
    using SafeERC20 for IERC20;

    /// @notice Error for less than min token out
    /// @dev Revert when the actual output token amount is less than the expected minimum
    error LessThanMinTokenOut(uint256 actual, uint256 expected);
    /// @notice Error for exceeding max token in
    /// @dev Revert when the actual required input token amount exceeds the expected maximum
    error ExceedMaxTokenIn(uint256 actual, uint256 expected);

    /**
     * @inheritdoc IERC20SwapAdapter
     */
    function swap(address recipient, address tokenIn, address tokenOut, uint256 tokenInAmt, bytes memory swapData)
        external
        override
        onlyProxy
        returns (uint256)
    {
        return _swap(recipient, IERC20(tokenIn), IERC20(tokenOut), tokenInAmt, swapData);
    }

    function _swap(address recipient, IERC20 tokenIn, IERC20 tokenOut, uint256 tokenInAmt, bytes memory swapData)
        internal
        virtual
        returns (uint256 tokenOutAmt)
    {}
}
