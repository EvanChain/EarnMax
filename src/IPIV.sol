// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SwapUnit} from "./interfaces/IERC20SwapAdapter.sol";

struct Order {
    uint256 price; // The price at which the order is placed (collateral/debt decimal is 18)
    uint256 deadline; // The timestamp after which the order is no longer valid
}

struct Position {
    address collateralToken;
    uint256 collateralAmount;
    address debtToken;
    int256 debtAmount;
    uint256 principal; // principal amount to do leverage
    uint256 interestRateMode; // 1 for stable, 2 for variable
    uint256 expectProfit; // The expect total profit, expectProfit = total collateral as debt token
    uint256 deadline; // The dealine of the take time
}

interface IPIV {
    /// @notice Emitted when a loan is migrated from Aave to PIV
    /// @param from The address of the user who migrated the loan
    /// @param positionId The id of the position that was migrated
    /// @param position The Position struct containing details of the migrated loan
    event LoanMigrated(address indexed from, uint256 indexed positionId, Position position);

    event LoanCreated(uint256 indexed positionId, Position position);

    event PositionUpdated(uint256 indexed positionId, uint256 expectProfit, uint256 deadline);

    event PositionTakeProfit(uint256 indexed positionId, uint256 debtAmount, uint256 collateralAmount);

    error SwapUnitsIsEmpty();

    error SwapFailed(address adapter, bytes result);

    /// @notice Get the aToken address for a given asset
    /// @param asset The address of the asset for which to retrieve the aToken address
    /// @return The address of the aToken representing the asset
    function aTokenAddress(address asset) external view returns (address);

    function createPosition(Position memory position, bool useAaveBalance, SwapUnit[] memory swapUnits)
        external
        returns (uint256 positionId);

    function migrateFromAave(Position memory position) external returns (uint256 positionId);

    function updateExpectProfit(uint256 positionId, uint256 expectProfit, uint256 deadline) external;

    function takePosition(uint256 positionId, uint256 inputAmount, address receiver)
        external
        returns (uint256 debtInput, uint256 collateralOutput);

    function previewTakePosition(uint256 positionId, uint256 inputAmount)
        external
        view
        returns (uint256 debtInput, uint256 collateralOutput);
}
