// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPIV, PIV} from "./PIV.sol";
import {IRouter} from "./IRouter.sol";
import {console} from "forge-std/console.sol";

contract Router is IRouter {
    using SafeERC20 for IERC20;

    address public immutable POOL;
    address public immutable ADDRESSES_PROVIDER;

    constructor(address aavePool, address aaveAddressProvider) {
        POOL = aavePool;
        ADDRESSES_PROVIDER = aaveAddressProvider;
    }

    function deployPIV() external override returns (address pivAddress) {
        PIV piv = new PIV(POOL, ADDRESSES_PROVIDER, msg.sender);
        pivAddress = address(piv);
        emit PIVDeployed(msg.sender, pivAddress);
    }

    /// @notice Trade an order in the PIV system
    /// @param swapData The data required for the swap, including token addresses, amounts, and order datas
    function swap(SwapData calldata swapData)
        external
        override
        returns (uint256 netAmountOut, uint256 totalInputAmount)
    {
        IERC20 tokenIn = IERC20(swapData.tokenIn);
        tokenIn.safeTransferFrom(msg.sender, address(this), swapData.amountIn);
        uint256 remainningAmount = swapData.amountIn;
        for (uint256 i = 0; i < swapData.orderDatas.length; i++) {
            OrderData memory orderData = swapData.orderDatas[i];
            IPIV piv = IPIV(orderData.pivAddress);
            (uint256 output, uint256 input) = piv.previewSwap(orderData.orderIds, remainningAmount);
            if (input != 0 && output != 0) {
                // Transfer the input amount to the PIV contract
                tokenIn.safeIncreaseAllowance(address(piv), input);
                // Execute the swap in the PIV contract
                (output, input) = piv.swap(orderData.orderIds, input, msg.sender);
                remainningAmount -= input;
                netAmountOut += output;
                totalInputAmount += input;
            }
            if (remainningAmount == 0) {
                break; // No more amount to swap
            }
        }
        console.log("Net amount out:", netAmountOut);
        require(netAmountOut >= swapData.minAmountOut, "Insufficient output amount");

        if (remainningAmount != 0) {
            // If the remaining amount is not zero, refund the difference
            tokenIn.safeTransfer(msg.sender, remainningAmount);
        }

        // This is a placeholder implementation
        emit SwapExecuted(swapData.tokenIn, swapData.tokenOut, msg.sender, totalInputAmount, netAmountOut);
        return (netAmountOut, totalInputAmount);
    }
}
