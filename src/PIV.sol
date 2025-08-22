// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IAaveV3PoolMinimal} from "./extensions/IAaveV3PoolMinimal.sol";
import {IAaveV3FlashLoanReceiver} from "./extensions/IAaveV3FlashLoanReceiver.sol";
import {IPIV} from "./IPIV.sol";
import {console} from "forge-std/console.sol";

contract PIV is IAaveV3FlashLoanReceiver, Ownable {
    using SafeERC20 for IERC20;

    address public immutable POOL;
    address public immutable ADDRESSES_PROVIDER;

    uint256 public totalOrders;
    mapping(uint256 => IPIV.Order) public orderMapping;
    mapping(address => uint256) public collateralOnSold;

    constructor(address aavePool, address aaveAddressProvider, address admin) Ownable(admin) {
        POOL = aavePool;
        ADDRESSES_PROVIDER = aaveAddressProvider;
    }

    function executeOperation(address asset, uint256 amount, uint256 premium, address, bytes calldata params)
        external
        override
        returns (bool)
    {
        require(msg.sender == POOL, "Invalid caller");
        (address user, IERC20 collateralToken, uint256 aTokenAmount, uint256 interestMode) =
            abi.decode(params, (address, IERC20, uint256, uint256));
        //repay old debt
        IERC20(asset).safeIncreaseAllowance(POOL, amount);
        IAaveV3PoolMinimal(POOL).repay(asset, amount, interestMode, user);
        //transfer aToken from user to this contract
        IERC20(atokenAddress(address(collateralToken))).safeTransferFrom(user, address(this), aTokenAmount);
        //borrow new debt
        uint256 newDebtAmount = amount + premium;
        assembly {
            tstore(0, newDebtAmount)
        }
        IAaveV3PoolMinimal(POOL).borrow(asset, newDebtAmount, interestMode, 0, address(this));
        IERC20(asset).safeIncreaseAllowance(POOL, newDebtAmount);
        return true;
    }

    function atokenAddress(address asset) public view returns (address) {
        return IAaveV3PoolMinimal(POOL).getReserveData(asset).aTokenAddress;
    }

    // interestMode 1 for Stable, 2 for Variable
    function migrateFromAave(
        IERC20 collateralToken,
        uint256 collateralAmount,
        IERC20 debtToken,
        uint256 debtAmount,
        uint256 interestRateMode
    ) external onlyOwner returns (uint256 newDebtAmount) {
        bytes memory params = abi.encode(msg.sender, collateralToken, collateralAmount, interestRateMode);
        IAaveV3PoolMinimal(POOL).flashLoanSimple(address(this), address(debtToken), debtAmount, params, 0);
        assembly {
            newDebtAmount := tload(0)
        }
        emit IPIV.LoanMigrated(
            msg.sender, address(collateralToken), address(debtToken), collateralAmount, newDebtAmount, interestRateMode
        );
    }

    function placeOrder(
        address collateralToken,
        uint256 collateralAmount,
        address debtToken,
        uint256 price,
        uint256 interestRateMode
    ) external onlyOwner returns (uint256 orderId) {
        require(collateralAmount > 0 && price > 0, "Invalid collateral or price");
        address aToken = atokenAddress(collateralToken);
        uint256 cBalance = IERC20(aToken).balanceOf(address(this));
        require(cBalance >= collateralAmount + collateralOnSold[collateralToken], "Insufficient collateral balance");
        orderId = ++totalOrders;
        orderMapping[orderId] = IPIV.Order({
            collateralToken: collateralToken,
            debtToken: debtToken,
            collateralAmount: collateralAmount,
            remainingCollateral: collateralAmount,
            price: price,
            interestRateMode: interestRateMode
        });
        collateralOnSold[aToken] += collateralAmount;

        emit IPIV.OrderPlaced(
            msg.sender, orderId, collateralToken, debtToken, collateralAmount, price, interestRateMode
        );
    }

    function updateOrder(uint256 orderId, uint256 price) external onlyOwner {
        IPIV.Order memory order = orderMapping[orderId];
        require(order.price != 0, "Order does not exist");
        require(price > 0, "Invalid price");
        orderMapping[orderId].price = price;

        emit IPIV.OrderUpdated(orderId, price);
    }

    function cancelOrder(uint256 orderId) external onlyOwner {
        IPIV.Order storage order = orderMapping[orderId];
        collateralOnSold[atokenAddress(order.collateralToken)] -= order.collateralAmount;
        delete orderMapping[orderId];
        emit IPIV.OrderCancelled(orderId);
    }

    function previewSwap(uint256[] calldata orderIds, uint256 tradingAmount)
        public
        view
        returns (uint256 collateralOutput, uint256 debtInput)
    {
        for (uint256 i = 0; i < orderIds.length; i++) {
            IPIV.Order memory order = orderMapping[orderIds[i]];
            console.log("orderId", orderIds[i]);
            console.log("tradingAmount", tradingAmount);
            uint256 output =
                _calculateCollateralOutput(order.collateralToken, tradingAmount, order.debtToken, order.price);
            console.log("output", output);
            // Check if the order has enough remaining collateral
            if (order.remainingCollateral >= output) {
                collateralOutput += output;
                debtInput += tradingAmount;
                break;
            } else {
                collateralOutput += order.remainingCollateral; // Add the remaining collateral
                // Reduce the trading amount by the remaining collateral's debt equivalent
                uint256 requiredDebtAmt =
                    _calculateDebtAmount(order.collateralToken, order.remainingCollateral, order.debtToken, order.price);
                console.log("requiredDebtAmt", requiredDebtAmt);
                tradingAmount -= requiredDebtAmt; // Reduce the trading amount by the debt equivalent of the remaining collateral
                debtInput += requiredDebtAmt; // Add the required debt amount to the total debt input
            }
        }
        console.log("collateralOutput", collateralOutput);
        console.log("debtInput", debtInput);
    }

    function swap(uint256[] calldata orderIds, uint256 tradingAmount, address recipient)
        external
        returns (uint256 totalCollateralOutput, uint256 totalDebtInput)
    {
        (uint256 collateralOutput, uint256 debtInput) = previewSwap(orderIds, tradingAmount);
        (totalCollateralOutput, totalDebtInput) = (collateralOutput, debtInput);

        for (uint256 i = 0; i < orderIds.length; i++) {
            IPIV.Order storage order = orderMapping[orderIds[i]];
            if (collateralOutput >= order.remainingCollateral) {
                collateralOutput -= order.remainingCollateral; // Reduce the collateral output by the used amount
                emit IPIV.OrderTraded(orderIds[i], order.remainingCollateral);
                order.remainingCollateral = 0; // Use all remaining collateral
            } else {
                order.remainingCollateral -= collateralOutput; // Reduce the remaining collateral by the used amount
                emit IPIV.OrderTraded(orderIds[i], collateralOutput);
                break;
            }
        }

        IERC20 debtToken = IERC20(orderMapping[orderIds[0]].debtToken);
        IERC20 collateralToken = IERC20(orderMapping[orderIds[0]].collateralToken);
        debtToken.safeTransferFrom(msg.sender, address(this), totalDebtInput);
        debtToken.safeIncreaseAllowance(POOL, totalDebtInput);

        // Repay the debt
        // Note: This assumes the debt token is the same as the one used in the order
        IAaveV3PoolMinimal(POOL).repay(
            address(debtToken), totalDebtInput, orderMapping[orderIds[0]].interestRateMode, address(this)
        );
        // Transfer the trading amount to the caller
        address aToken = atokenAddress(address(collateralToken));
        collateralOnSold[aToken] -= totalCollateralOutput;
        IERC20(aToken).safeIncreaseAllowance(POOL, totalCollateralOutput);
        IAaveV3PoolMinimal(POOL).withdraw(address(collateralToken), totalCollateralOutput, recipient);
    }

    // function _swap(uint256 orderId, uint256 tradingAmount, address recipient) internal returns (uint256, uint256) {
    //     IPIV.Order storage order = orderMapping[orderId];
    //     if (tradingAmount > order.remainingCollateral) {
    //         tradingAmount = order.remainingCollateral; // Adjust to remaining collateral if more is requested
    //         order.remainingCollateral = 0; // All collateral used
    //     } else {
    //         order.remainingCollateral -= tradingAmount; // Reduce the remaining collateral
    //     }
    //     console.log("tradingAmount", tradingAmount);
    //     uint256 debtAmount = _calculateDebtAmount(order.collateralToken, tradingAmount, order.debtToken, order.price);
    //     console.log("debtAmount", debtAmount);
    //     IERC20(order.debtToken).safeTransferFrom(msg.sender, address(this), debtAmount);
    //     IERC20(order.debtToken).safeIncreaseAllowance(POOL, debtAmount);
    //     // Repay the debt
    //     // Note: This assumes the debt token is the same as the one used in the order
    //     IAaveV3PoolMinimal(POOL).repay(order.debtToken, debtAmount, order.interestRateMode, address(this));
    //     // Transfer the trading amount to the caller
    //     address aToken = atokenAddress(order.collateralToken);
    //     collateralOnSold[aToken] -= tradingAmount;
    //     IERC20(aToken).safeIncreaseAllowance(POOL, tradingAmount);
    //     IAaveV3PoolMinimal(POOL).withdraw(order.collateralToken, tradingAmount, recipient);
    //     emit IPIV.OrderTraded(orderId, tradingAmount);
    //     // Logic to handle the swap can be added here
    //     return (tradingAmount, debtAmount);
    // }

    function _calculateCollateralOutput(address collateralToken, uint256 debtAmount, address debtToken, uint256 price)
        internal
        view
        returns (uint256 collateralOutputAmount)
    {
        // price = collateral price * 1e18 / debt price
        uint256 collateralUnits = 10 ** IERC20Metadata(collateralToken).decimals();
        uint256 debtUnits = 10 ** IERC20Metadata(debtToken).decimals();

        collateralOutputAmount = (debtAmount * 1e18 * collateralUnits) / (price * debtUnits);
    }

    function _calculateDebtAmount(address collateralToken, uint256 collateralAmount_, address debtToken, uint256 price)
        internal
        view
        returns (uint256 requiredDebtAmount)
    {
        // price = debtToken * 1e18 / collateralToken
        uint256 collateralUnits = 10 ** IERC20Metadata(collateralToken).decimals();
        uint256 debtUnits = 10 ** IERC20Metadata(debtToken).decimals();
        uint256 denimonator = collateralUnits * 1 ether;
        requiredDebtAmount = (collateralAmount_ * price * debtUnits + denimonator - 1) / denimonator; // rounding up
    }

    function withdrawAssets(address token, uint256 amount, address recipient) external onlyOwner {
        require(amount > 0, "Amount must be greater than zero");
        IERC20(token).safeTransfer(recipient, amount);
    }

    function getBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
