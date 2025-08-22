// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPIV {
    struct Order {
        address collateralToken; // The address of the collateral token
        address debtToken; // The address of the debt token
        uint256 collateralAmount; // The amount of collateral provided in the order
        uint256 remainingCollateral; // The remaining collateral amount after trades
        uint256 price; // The price at which the order is placed (collateral/debt decimal is 18)
        uint256 interestRateMode; // The interest rate mode of the debt (1 for stable, 2 for variable)
    }

    /// @notice Emitted when a loan is migrated from Aave to PIV
    /// @param user The address of the user who migrated the loan
    /// @param collateralToken The address of the token representing the collateral asset
    /// @param debtToken The address of the debt token that was migrated
    /// @param collateralAmount The amount of collateral provided in the migration
    /// @param newDebtAmount The new amount of debt after migration
    /// @param interestRateMode The interest rate mode of the debt (1 for stable, 2 for variable)
    /// @dev This event is emitted when a user migrates their collateral and debt from Aave to PIV.
    event LoanMigrated(
        address indexed user,
        address indexed collateralToken,
        address indexed debtToken,
        uint256 collateralAmount,
        uint256 newDebtAmount,
        uint256 interestRateMode
    );

    /// @notice Emitted when an order is placed
    /// @param owner The address of the user who placed the order
    /// @param orderId The ID of the order
    /// @param collateralToken The address of the collateral token
    /// @param debtToken The address of the debt token
    /// @param collateralAmount The amount of collateral provided in the order
    /// @param price The swap rate at which the order is placed (debt/collateral decimal is 18)
    /// @param interestRateMode The interest rate mode of the debt (1 for stable, 2 for variable)
    event OrderPlaced(
        address indexed owner,
        uint256 indexed orderId,
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 price,
        uint256 interestRateMode
    );

    /// @notice Emitted when an order is updated
    /// @param orderId The ID of the order that was updated
    /// @param price The new price at which the order is placed (collateral/debt
    event OrderUpdated(uint256 indexed orderId, uint256 price);

    /// @notice Emitted when an order is cancelled
    /// @param orderId The ID of the order that was cancelled
    event OrderCancelled(uint256 indexed orderId);

    /// @notice Emitted when an order is traded
    /// @param orderId The ID of the order that was traded
    /// @param tradingAmount The amount of collateral that was traded in the order
    event OrderTraded(uint256 indexed orderId, uint256 tradingAmount);

    function totalOrders() external view returns (uint256);

    /// @notice Migrate from Aave to PIV
    /// @dev This function allows users to migrate their collateral and debt from Aave to PIV.
    /// @param collateralToken The address of the token representing the collateral asset
    /// @param collateralAmount The amount of aTokens to migrate as collateral
    /// @param debtToken The address of the debt token to migrate
    /// @param debtAmount The amount of debt to migrate
    /// @param interestRateMode The interest rate mode of the debt (1 for stable, 2 for variable)
    /// @return newDebtAmount The new amount of debt after migration
    function migrateFromAave(
        address collateralToken,
        uint256 collateralAmount,
        address debtToken,
        uint256 debtAmount,
        uint256 interestRateMode
    ) external returns (uint256 newDebtAmount);

    /// @notice Get the aToken address for a given asset
    /// @param asset The address of the asset for which to retrieve the aToken address
    /// @return The address of the aToken representing the asset
    function atokenAddress(address asset) external view returns (address);

    /// @notice Place an order in the PIV system
    /// @dev This function allows users to place an order with collateral and debt.
    /// @param collateralToken The address of the aToken representing the collateral asset
    /// @param collateralAmount The amount of aTokens to sell
    /// @param debtToken The address of the debt token you want to buy
    /// @param price The price between the collateral and debt token (collateral/debt decimal is 18)
    /// @param interestRateMode The interest rate mode of the debt (1 for stable, 2 for variable)
    /// @return orderId The ID of the created order
    function placeOrder(
        address collateralToken,
        uint256 collateralAmount,
        address debtToken,
        uint256 price,
        uint256 interestRateMode
    ) external returns (uint256 orderId);

    /// @notice Update an existing order in the PIV system
    /// @param orderId the ID of the order to update
    /// @param collateralAmount The new amount of collateral to sell
    /// @param price The new price between the collateral and debt token (collateral/debt decimal is 18)
    /// @dev This function allows users to update the amount and price of an existing order.
    function updateOrder(uint256 orderId, uint256 collateralAmount, uint256 price) external;

    /// @notice Cancel an existing order in the PIV system
    /// @param orderId The ID of the order to cancel
    function cancelOrder(uint256 orderId) external;

    /// @notice Preview a swap operation based on the provided order IDs and trading amount
    /// @param orderIds An array of order IDs to consider for the swap
    /// @param tradingAmount The amount of collateral to trade
    /// @return collateralOutput The total amount of collateral output received from the swap
    /// @return debtInput The total amount of debt input required for the swap
    function previewSwap(uint256[] calldata orderIds, uint256 tradingAmount)
        external
        view
        returns (uint256 collateralOutput, uint256 debtInput);

    /// @notice Execute a swap operation based on the provided order IDs and trading amount
    /// @param orderIds An array of order IDs to consider for the swap
    /// @param tradingAmount The amount of collateral to trade
    /// @param recipient The address to receive the collateral output
    /// @return totalCollateralOutput The total amount of collateral output received from the swap
    /// @return totalDebtInput The total amount of debt input required for the swap
    function swap(uint256[] calldata orderIds, uint256 tradingAmount, address recipient)
        external
        returns (uint256 totalCollateralOutput, uint256 totalDebtInput);
}
