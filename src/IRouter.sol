// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRouter {
    struct OrderData {
        address pivAddress; // The address of the PIV contract
        uint256[] orderIds; // The IDs of the orders to be traded
    }

    struct SwapData {
        address tokenIn; // The address of the token being sold (debt token)
        address tokenOut; // The address of the token being bought (collateral Token)
        uint256 amountIn; // The amount of the token being sold (debt token)
        uint256 minAmountOut; // The minimum amount of the token being bought (collateral Token)
        OrderData[] orderDatas; // The IDs of the orders to be traded
    }

    /// @notice Emitted when a swap is executed
    /// @param tokenIn The address of the token being sold (debt token)
    /// @param tokenOut The address of the token being bought (collateral Token)
    /// @param amountIn The amount of the token being sold (debt token)
    /// @param finalAmountOut The final amount of the token being bought (collateral Token)

    event SwapExecuted(
        address indexed tokenIn, address indexed tokenOut, address caller, uint256 amountIn, uint256 finalAmountOut
    );
    /// @notice Emitted when a PIV contract is deployed
    /// @param owner The address of the owner who deployed the PIV contract
    /// @param pivAddress The address of the deployed PIV contract
    event PIVDeployed(address owner, address pivAddress);

    /// @notice Deploy a new PIV contract
    /// @return pivAddress The address of the newly deployed PIV contract
    /// @dev This function creates a new PIV contract and returns its address.
    function deployPIV() external returns (address pivAddress);

    /// @notice Trade an order in the PIV system
    /// @param swapData The data required for the swap, including token addresses, amounts, and order datas
    /// @return netAmountOut The total amount of the token being bought (collateral Token) after the swap
    /// @return totalInputAmount The total amount of the token being sold (debt token) used in the swap
    function swap(SwapData calldata swapData) external returns (uint256 netAmountOut, uint256 totalInputAmount);
}
