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
    // The piv mapping for user
    mapping(address => address) public userPivMapping;

    constructor(address aavePool, address aaveAddressProvider) {
        POOL = aavePool;
        ADDRESSES_PROVIDER = aaveAddressProvider;
    }

    function deployPIV() external override returns (address pivAddress) {
        if (userPivMapping[msg.sender] != address(0)) {
            return userPivMapping[msg.sender];
        }
        PIV piv = new PIV(POOL, ADDRESSES_PROVIDER, msg.sender);
        pivAddress = address(piv);
        userPivMapping[msg.sender] = pivAddress;
        emit PIVDeployed(msg.sender, pivAddress);
    }

    /// @notice Take position's collateral in the PIV system
    /// @param swapData The data required for the swap, including token addresses, amounts, and position datas
    function swap(SwapData calldata swapData)
        external
        override
        returns (uint256 netAmountOut, uint256 totalInputAmount)
    {
        IERC20 tokenIn = IERC20(swapData.tokenIn);
        tokenIn.safeTransferFrom(msg.sender, address(this), swapData.amountIn);
        uint256 remainningAmount = swapData.amountIn;
        for (uint256 i = 0; i < swapData.positionDatas.length; i++) {
            PositionData memory positionData = swapData.positionDatas[i];
            IPIV piv = IPIV(positionData.pivAddress);
            (uint256 input, uint256 output) = piv.previewTakePosition(positionData.positionId, remainningAmount);
            if (input != 0 && output != 0) {
                piv.takePosition(positionData.positionId, input, address(this));
                remainningAmount -= input;
                netAmountOut += output;
            }
            if (remainningAmount == 0) {
                break; // No more amount to swap
            }
        }
        console.log("Net amount out:", netAmountOut);

        require(remainningAmount == 0, "Insufficient liquidity");
        require(netAmountOut >= swapData.minAmountOut, "Insufficient output amount");

        // This is a placeholder implementation
        emit SwapExecuted(swapData.tokenIn, swapData.tokenOut, msg.sender, totalInputAmount, netAmountOut);
        return (netAmountOut, totalInputAmount);
    }
}
