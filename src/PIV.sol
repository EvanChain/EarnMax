// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.29;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IAaveV3PoolMinimal} from "./extensions/IAaveV3PoolMinimal.sol";
import {IAaveV3FlashLoanReceiver} from "./extensions/IAaveV3FlashLoanReceiver.sol";
import {IPIV, Position, Order} from "./IPIV.sol";
import {IERC20SwapAdapter, SwapUnit} from "./interfaces/IERC20SwapAdapter.sol";
import {console} from "forge-std/console.sol";

contract PIV is IAaveV3FlashLoanReceiver, Ownable, EIP712, IPIV, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    enum FlashLoanOperation {
        MigrateFromAave,
        NewLoan,
        ClosePosition
    }

    /// @notice aave V3 Pool address
    address public immutable POOL;
    address public immutable ADDRESSES_PROVIDER;

    uint256 public totalPositions;
    mapping(uint256 => Position) public positionMapping;

    constructor(address aavePool, address aaveAddressProvider, address admin) Ownable(admin) EIP712("PIV", "1") {
        POOL = aavePool;
        ADDRESSES_PROVIDER = aaveAddressProvider;
    }

    // aave flash loan callback function
    function executeOperation(address asset, uint256 amount, uint256 premium, address, bytes calldata data)
        external
        override
        returns (bool)
    {
        require(msg.sender == POOL, "Invalid caller");
        (FlashLoanOperation operation, bytes memory params) = abi.decode(data, (FlashLoanOperation, bytes));
        if (operation == FlashLoanOperation.MigrateFromAave) {
            _migrateFromAave(params, asset, amount, premium);
        } else if (operation == FlashLoanOperation.NewLoan) {
            _newLoan(params, asset, amount, premium);
        } else if (operation == FlashLoanOperation.ClosePosition) {
            _closePosition(params, asset, amount, premium);
        }
        IERC20(asset).safeIncreaseAllowance(POOL, amount + premium);
        return true;
    }

    // Create a position in PIV
    function _newLoan(bytes memory params, address asset, uint256 amount, uint256 premium) internal {
        (Position memory position, SwapUnit[] memory swapUnits) = abi.decode(params, (Position, SwapUnit[]));
        // swap debt token to collateral token
        uint256 collateralAmount = _doSwap(amount + position.principal, swapUnits);
        require(collateralAmount >= position.collateralAmount, "Insufficient collateral after swap");
        // deposit collateral to aave
        IERC20(position.collateralToken).safeIncreaseAllowance(POOL, collateralAmount);
        IAaveV3PoolMinimal(POOL).supply(position.collateralToken, collateralAmount, address(this), 0);
        // borrow debt from aave
        IAaveV3PoolMinimal(POOL).borrow(asset, amount + premium, position.interestRateMode, 0, address(this));
        uint256 positionId = ++totalPositions;

        position.debtAmount = int256(amount + premium);
        positionMapping[positionId] = position;
        emit IPIV.LoanCreated(positionId, position);
    }

    function createPosition(Position memory position, bool useAaveBalance, SwapUnit[] memory swapUnits)
        external
        onlyOwner
        returns (uint256 positionId)
    {
        if (useAaveBalance) {
            IAaveV3PoolMinimal(POOL).withdraw(address(position.debtToken), position.principal, address(this));
        } else {
            IERC20(position.debtToken).safeTransferFrom(msg.sender, address(this), position.principal);
        }
        bytes memory params = abi.encode(position, swapUnits);
        params = abi.encode(FlashLoanOperation.NewLoan, params);
        IAaveV3PoolMinimal(POOL).flashLoanSimple(
            address(this), address(position.debtToken), uint256(position.debtAmount), params, 0
        );
        positionId = totalPositions;
    }

    // Migrate positions from Aave V3 to PIV
    function _migrateFromAave(bytes memory params, address asset, uint256 amount, uint256 premium) internal {
        (address user, Position memory position) = abi.decode(params, (address, Position));
        //repay old debt
        IERC20(asset).safeIncreaseAllowance(POOL, amount);
        IAaveV3PoolMinimal(POOL).repay(asset, amount, position.interestRateMode, user);
        //transfer aToken from user to this contract
        IERC20(aTokenAddress(address(position.collateralToken))).safeTransferFrom(
            user, address(this), position.collateralAmount
        );
        //borrow new debt
        position.debtAmount = int256(amount + premium);
        IAaveV3PoolMinimal(POOL).borrow(
            asset, uint256(position.debtAmount), position.interestRateMode, 0, address(this)
        );
        uint256 positionId = ++totalPositions;
        positionMapping[positionId] = position;
        emit IPIV.LoanMigrated(user, positionId, position);
    }

    // interestMode 1 for Stable, 2 for Variable
    function migrateFromAave(Position memory position) external onlyOwner returns (uint256 positionId) {
        bytes memory params = abi.encode(msg.sender, position);
        params = abi.encode(FlashLoanOperation.MigrateFromAave, params);
        IAaveV3PoolMinimal(POOL).flashLoanSimple(
            address(this), address(position.debtToken), uint256(position.debtAmount), params, 0
        );
        positionId = totalPositions;
    }

    function closePosition(uint256 positionId, SwapUnit[] memory swapUnits) external onlyOwner {
        Position memory position = positionMapping[positionId];
        require(position.debtAmount > 0, "Position already closed");

        bytes memory params = abi.encode(positionId, position, swapUnits);
        params = abi.encode(FlashLoanOperation.ClosePosition, params);
        IAaveV3PoolMinimal(POOL).flashLoanSimple(
            address(this), address(position.debtToken), uint256(position.debtAmount), params, 0
        );
    }

    function _closePosition(bytes memory params, address asset, uint256 amount, uint256 premium) internal {
        (uint256 positionId, Position memory position, SwapUnit[] memory swapUnits) =
            abi.decode(params, (uint256, Position, SwapUnit[]));
        //repay debt
        IERC20(asset).safeIncreaseAllowance(POOL, amount);
        IAaveV3PoolMinimal(POOL).repay(asset, amount, position.interestRateMode, address(this));
        //withdraw collateral from aave
        IAaveV3PoolMinimal(POOL).withdraw(address(position.collateralToken), position.collateralAmount, address(this));
        //swap collateral to debt token
        uint256 debtAmount = _doSwap(position.collateralAmount, swapUnits);
        require(debtAmount >= amount + premium, "Insufficient debt token after swap");
        //calculate profit before marking position as closed
        uint256 profit = debtAmount - (amount + premium);
        //mark position as closed
        position.debtAmount = -int256(profit);
        position.collateralAmount = 0;
        position.expectProfit = 0;
        position.deadline = 0;
        positionMapping[positionId] = position;
        emit IPIV.LoanClosed(positionId, profit);
    }

    function aTokenAddress(address asset) public view returns (address) {
        return IAaveV3PoolMinimal(POOL).getReserveData(asset).aTokenAddress;
    }

    function updateExpectProfit(uint256 positionId, uint256 expectProfit, uint256 deadline) external onlyOwner {
        Position memory position = positionMapping[positionId];
        position.expectProfit = expectProfit;
        position.deadline = deadline;
        // persist updated fields back to storage
        positionMapping[positionId] = position;
        emit PositionUpdated(positionId, expectProfit, deadline);
    }

    function takePosition(uint256 positionId, uint256 inputAmount, address receiver)
        external
        nonReentrant
        returns (uint256 debtInput, uint256 collateralOutput)
    {
        Position memory position = positionMapping[positionId];
        (debtInput, collateralOutput) = _calculateTakeResult(position, inputAmount);
        if (debtInput != 0) {
            IERC20(position.debtToken).safeTransferFrom(msg.sender, address(this), debtInput);
            IERC20(position.collateralToken).safeTransfer(receiver, collateralOutput);
            position.debtAmount -= int256(debtInput);
            position.expectProfit -= debtInput;
            position.collateralAmount -= collateralOutput;
            positionMapping[positionId] = position;
            emit PositionTakeProfit(positionId, debtInput, collateralOutput);
        }
    }

    function previewTakePosition(uint256 positionId, uint256 inputAmount)
        external
        view
        returns (uint256 debtInput, uint256 collateralOutput)
    {
        Position memory position = positionMapping[positionId];
        return _calculateTakeResult(position, inputAmount);
    }

    function _calculateTakeResult(Position memory position, uint256 inputAmount)
        internal
        view
        returns (uint256 debtInput, uint256 collateralOutput)
    {
        // If there's no expected profit, nobody can take.
        // If a deadline is set (non-zero) and it has already passed, taking is disallowed.
        if (position.expectProfit == 0 || (position.deadline != 0 && block.timestamp > position.deadline)) {
            return (0, 0);
        }
        debtInput = inputAmount > position.expectProfit ? position.expectProfit : inputAmount;
        // the price is show in type how many debt token -> how many collateral token
        collateralOutput = debtInput.mulDiv(position.collateralAmount, position.expectProfit);
    }

    function withdrawAssets(address token, uint256 amount, address recipient) external onlyOwner {
        require(amount > 0, "Amount must be greater than zero");
        IERC20(token).safeTransfer(recipient, amount);
    }

    function getBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function executeTransaction(address payable target, uint256 value, bytes calldata data)
        external
        onlyOwner
        returns (bytes memory)
    {
        (bool success, bytes memory result) = target.call{value: value}(data);
        require(success, "Transaction failed");
        return result;
    }

    function _doSwap(uint256 inputAmt, SwapUnit[] memory units) internal returns (uint256 outputAmt) {
        if (units.length == 0) {
            revert IPIV.SwapUnitsIsEmpty();
        }
        for (uint256 i = 0; i < units.length; ++i) {
            bytes memory dataToSwap = abi.encodeCall(
                IERC20SwapAdapter.swap,
                (address(this), units[i].tokenIn, units[i].tokenOut, inputAmt, units[i].swapData)
            );

            (bool success, bytes memory returnData) = units[i].adapter.delegatecall(dataToSwap);
            if (!success) {
                revert IPIV.SwapFailed(units[i].adapter, returnData);
            }
            inputAmt = abi.decode(returnData, (uint256));
        }
        outputAmt = inputAmt;
    }
}
