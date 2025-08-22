// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Test} from "forge-std/Test.sol";
import {PIV, IPIV} from "../src/PIV.sol";
import {Router, IRouter} from "../src/Router.sol";
import {IAaveV3PoolMinimal} from "../src/extensions/IAaveV3PoolMinimal.sol";
import {console} from "forge-std/console.sol";

contract FrokPiv is Test {
    address constant AAVE_V3_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2; // Aave V3 Pool on Ethereum Mainnet
    address constant AAVE_V3_ADDRESS_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    IAaveV3PoolMinimal aavePool = IAaveV3PoolMinimal(AAVE_V3_POOL);

    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address aWeth;

    PIV piv;
    Router router;

    address borrower = vm.addr(1);
    address trader = vm.addr(2);
    uint256 interestRate = 2; // Float interest rate mode
    uint256 debtAmount = 1000e6;
    uint256 collateralAmount = 1 ether;

    function setUp() public {
        vm.createSelectFork(MAINNET_RPC_URL);

        // Create the router
        router = new Router(AAVE_V3_POOL, AAVE_V3_ADDRESS_PROVIDER);
        //create the vault
        vm.prank(borrower);
        piv = PIV(router.deployPIV());
        aWeth = piv.atokenAddress(weth);

        // Ensure the user has Collateral tokens
        deal(weth, borrower, collateralAmount);

        // Initialize the loan in aave
        vm.startPrank(borrower);
        IERC20(weth).approve(address(aavePool), collateralAmount); // Approve WETH for supply
        aavePool.supply(weth, collateralAmount, borrower, 0); // Supply collateralAmount WETH as collateral
        aavePool.borrow(usdc, debtAmount, interestRate, 0, borrower); // Borrow 1000 USDC

        assertEq(IERC20(usdc).balanceOf(borrower), debtAmount, "User should have 1000 USDC");
        assertEq(IERC20(aWeth).balanceOf(borrower), collateralAmount, "User should have 1 aWETH");

        // migrate the vault to PI
        IERC20(aWeth).approve(address(piv), collateralAmount);
        piv.migrateFromAave(IERC20(aWeth), collateralAmount, IERC20(usdc), debtAmount, interestRate);
        assertEq(IERC20(aWeth).balanceOf(borrower), 0, "User should have 0 aWETH after migration");
        assertEq(
            IERC20(aWeth).balanceOf(address(piv)),
            collateralAmount,
            "PIV should have collateralAmount aWETH after migration"
        );

        vm.stopPrank();
    }

    function testPlaceOrder() public {
        vm.startPrank(borrower);

        // Define order parameters
        uint256 orderCollateralAmount = 0.5 ether; // Half of the available collateral
        uint256 orderPrice = 2000e18; // Price: 1 WETH = 2000 USDC (in 18 decimals)

        // Check initial state
        uint256 initialTotalOrders = piv.totalOrders();
        uint256 expectedOrderId = initialTotalOrders + 1;

        // Check that PIV has sufficient collateral balance
        uint256 pivCollateralBalance = IERC20(aWeth).balanceOf(address(piv));
        assertGe(pivCollateralBalance, orderCollateralAmount, "PIV should have sufficient collateral");

        // Expect the OrderPlaced event to be emitted
        vm.expectEmit(true, true, true, true);
        emit IPIV.OrderPlaced(
            borrower,
            expectedOrderId,
            weth, // collateralToken
            usdc, // debtToken
            orderCollateralAmount,
            orderPrice,
            interestRate
        );

        // Place the order
        uint256 orderId = piv.placeOrder(
            weth, // collateralToken
            orderCollateralAmount,
            usdc, // debtToken
            orderPrice,
            interestRate
        );

        // Verify the returned order ID
        assertEq(orderId, expectedOrderId, "Order ID should match expected value");

        // Verify total orders increased
        assertEq(piv.totalOrders(), initialTotalOrders + 1, "Total orders should increase by 1");

        // Verify the order was stored correctly
        (
            address storedCollateralToken,
            address storedDebtToken,
            uint256 storedCollateralAmount,
            uint256 storedRemainingCollateral,
            uint256 storedPrice,
            uint256 storedInterestRateMode
        ) = piv.orderMapping(orderId);

        assertEq(storedCollateralToken, weth, "Stored collateral token should match");
        assertEq(storedDebtToken, usdc, "Stored debt token should match");
        assertEq(storedCollateralAmount, orderCollateralAmount, "Stored collateral amount should match");
        assertEq(storedRemainingCollateral, orderCollateralAmount, "Remaining collateral should equal initial amount");
        assertEq(storedPrice, orderPrice, "Stored price should match");
        assertEq(storedInterestRateMode, interestRate, "Stored interest rate mode should match");

        vm.stopPrank();
    }

    function testPlaceOrderRevertInvalidCollateral() public {
        vm.startPrank(borrower);

        // Test with zero collateral amount
        vm.expectRevert("Invalid collateral or price");
        piv.placeOrder(
            weth,
            0, // Invalid: zero collateral
            usdc,
            2000e18,
            interestRate
        );

        vm.stopPrank();
    }

    function testPlaceOrderRevertInvalidPrice() public {
        vm.startPrank(borrower);

        // Test with zero price
        vm.expectRevert("Invalid collateral or price");
        piv.placeOrder(
            weth,
            0.5 ether,
            usdc,
            0, // Invalid: zero price
            interestRate
        );

        vm.stopPrank();
    }

    function testPlaceOrderRevertInsufficientBalance() public {
        vm.startPrank(borrower);

        uint256 pivBalance = IERC20(aWeth).balanceOf(address(piv));
        uint256 excessiveAmount = pivBalance + 1 ether;

        // Test with amount exceeding available balance
        vm.expectRevert("Insufficient collateral balance");
        piv.placeOrder(weth, excessiveAmount, usdc, 2000e18, interestRate);

        vm.stopPrank();
    }

    function testPlaceOrderOnlyOwner() public {
        // Test that only owner can place orders
        vm.startPrank(trader); // Different address, not the owner

        vm.expectRevert(); // Should revert with Ownable: caller is not the owner
        piv.placeOrder(weth, 0.5 ether, usdc, 2000e18, interestRate);

        vm.stopPrank();
    }

    function testUpdateOrder() public {
        vm.startPrank(borrower);

        // First, place an order to update
        uint256 orderCollateralAmount = 0.5 ether;
        uint256 originalPrice = 2000e18;
        uint256 orderId = piv.placeOrder(weth, orderCollateralAmount, usdc, originalPrice, interestRate);

        // Define new price for update
        uint256 newPrice = 2500e18; // Updated price: 1 WETH = 2500 USDC

        // Expect the OrderUpdated event to be emitted
        vm.expectEmit(true, true, true, true);
        emit IPIV.OrderUpdated(orderId, newPrice);

        // Update the order
        piv.updateOrder(orderId, newPrice);

        // Verify the order was updated correctly
        (
            address storedCollateralToken,
            address storedDebtToken,
            uint256 storedCollateralAmount,
            uint256 storedRemainingCollateral,
            uint256 storedPrice,
            uint256 storedInterestRateMode
        ) = piv.orderMapping(orderId);

        // Check that only the price was updated, other fields remain the same
        assertEq(storedCollateralToken, weth, "Collateral token should remain unchanged");
        assertEq(storedDebtToken, usdc, "Debt token should remain unchanged");
        assertEq(storedCollateralAmount, orderCollateralAmount, "Collateral amount should remain unchanged");
        assertEq(storedRemainingCollateral, orderCollateralAmount, "Remaining collateral should remain unchanged");
        assertEq(storedPrice, newPrice, "Price should be updated to new value");
        assertEq(storedInterestRateMode, interestRate, "Interest rate mode should remain unchanged");

        vm.stopPrank();
    }

    function testUpdateOrderRevertNonexistentOrder() public {
        vm.startPrank(borrower);

        uint256 nonexistentOrderId = 999;
        uint256 newPrice = 2500e18;

        // Attempt to update a non-existent order
        vm.expectRevert("Order does not exist");
        piv.updateOrder(nonexistentOrderId, newPrice);

        vm.stopPrank();
    }

    function testUpdateOrderRevertInvalidPrice() public {
        vm.startPrank(borrower);

        // First, place an order to update
        uint256 orderId = piv.placeOrder(weth, 0.5 ether, usdc, 2000e18, interestRate);

        // Attempt to update with invalid price (zero)
        vm.expectRevert("Invalid price");
        piv.updateOrder(orderId, 0);

        vm.stopPrank();
    }

    function testUpdateOrderOnlyOwner() public {
        vm.startPrank(borrower);

        // Place an order as owner
        uint256 orderId = piv.placeOrder(weth, 0.5 ether, usdc, 2000e18, interestRate);

        vm.stopPrank();

        // Try to update order as non-owner
        vm.startPrank(trader);
        vm.expectRevert(); // Should revert with Ownable: caller is not the owner
        piv.updateOrder(orderId, 2500e18);
        vm.stopPrank();
    }

    function testCancelOrder() public {
        vm.startPrank(borrower);

        // First, place an order to cancel
        uint256 orderCollateralAmount = 0.5 ether;
        uint256 orderPrice = 2000e18;
        uint256 orderId = piv.placeOrder(weth, orderCollateralAmount, usdc, orderPrice, interestRate);

        // Verify the order exists before cancellation
        (address storedCollateralToken,, uint256 storedCollateralAmount,, uint256 storedPrice,) =
            piv.orderMapping(orderId);

        assertEq(storedCollateralToken, weth, "Order should exist before cancellation");
        assertEq(storedCollateralAmount, orderCollateralAmount, "Order data should be correct");
        assertEq(storedPrice, orderPrice, "Order price should be correct");

        // Expect the OrderCancelled event to be emitted
        vm.expectEmit(true, true, true, true);
        emit IPIV.OrderCancelled(orderId);

        // Cancel the order
        piv.cancelOrder(orderId);

        // Verify the order was deleted (all fields should be zero/empty)
        (
            address cancelledCollateralToken,
            address cancelledDebtToken,
            uint256 cancelledCollateralAmount,
            uint256 cancelledRemainingCollateral,
            uint256 cancelledPrice,
            uint256 cancelledInterestRateMode
        ) = piv.orderMapping(orderId);

        assertEq(cancelledCollateralToken, address(0), "Collateral token should be zero after cancellation");
        assertEq(cancelledDebtToken, address(0), "Debt token should be zero after cancellation");
        assertEq(cancelledCollateralAmount, 0, "Collateral amount should be zero after cancellation");
        assertEq(cancelledRemainingCollateral, 0, "Remaining collateral should be zero after cancellation");
        assertEq(cancelledPrice, 0, "Price should be zero after cancellation");
        assertEq(cancelledInterestRateMode, 0, "Interest rate mode should be zero after cancellation");

        vm.stopPrank();
    }

    function testCancelOrderOnlyOwner() public {
        vm.startPrank(borrower);

        // Place an order as owner
        uint256 orderId = piv.placeOrder(weth, 0.5 ether, usdc, 2000e18, interestRate);

        vm.stopPrank();

        // Try to cancel order as non-owner
        vm.startPrank(trader);
        vm.expectRevert(); // Should revert with Ownable: caller is not the owner
        piv.cancelOrder(orderId);
        vm.stopPrank();
    }

    function testCancelNonexistentOrder() public {
        vm.startPrank(borrower);

        uint256 nonexistentOrderId = 999;

        // Cancelling a non-existent order should not revert (just deletes empty mapping)
        // Expect the OrderCancelled event to be emitted even for non-existent orders
        vm.expectEmit(true, true, true, true);
        emit IPIV.OrderCancelled(nonexistentOrderId);

        piv.cancelOrder(nonexistentOrderId);

        vm.stopPrank();
    }

    function testPreviewSwap() public {
        vm.startPrank(borrower);

        // Place multiple orders with different prices
        uint256 orderCollateralAmount1 = 0.3 ether;
        uint256 orderPrice1 = 2000e18; // 1 WETH = 2000 USDC
        uint256 orderId1 = piv.placeOrder(weth, orderCollateralAmount1, usdc, orderPrice1, interestRate);

        uint256 orderCollateralAmount2 = 0.4 ether;
        uint256 orderPrice2 = 2100e18; // 1 WETH = 2100 USDC
        uint256 orderId2 = piv.placeOrder(weth, orderCollateralAmount2, usdc, orderPrice2, interestRate);

        // Preview swap for partial amount of first order
        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = orderId1;
        uint256 tradingAmount = 200e6;

        (uint256 collateralOutput, uint256 debtInput) = piv.previewSwap(orderIds, tradingAmount);

        // Calculate expected debt input using helper function
        uint256 expectedCollateralOutput = _calculateCollateralOutput(weth, tradingAmount, usdc, orderPrice1);
        assertEq(debtInput, tradingAmount, "Debt input should match expected calculation");
        assertEq(
            collateralOutput, expectedCollateralOutput, "Collateral output should equal expected collateral output"
        );

        // Preview swap across multiple orders
        uint256[] memory multipleOrderIds = new uint256[](2);
        multipleOrderIds[0] = orderId1;
        multipleOrderIds[1] = orderId2;
        uint256 largeTradingAmount = 1020e6; // Exceeds first order
        uint256 expectedLargeCollateralOutput = 0.5 ether; // 0.3 + 0.2 ETH

        (uint256 multiCollateralOutput, uint256 multiDebtInput) = piv.previewSwap(multipleOrderIds, largeTradingAmount);

        // Expected: first order fully filled (0.3 ETH 600 USDC) + partial second order (0.2 ETH 420 USDC)
        assertEq(
            multiCollateralOutput,
            expectedLargeCollateralOutput,
            "Multi-order collateral output should equal trading amount"
        );
        assertEq(multiDebtInput, largeTradingAmount, "Multi-order debt input should be sum of both orders");
        vm.stopPrank();
    }

    function testSwapSingleOrder() public {
        vm.startPrank(borrower);

        // Place an order
        uint256 orderCollateralAmount = 0.5 ether;
        uint256 orderPrice = 2000e18; // 1 WETH = 2000 USDC
        uint256 orderId = piv.placeOrder(weth, orderCollateralAmount, usdc, orderPrice, interestRate);

        vm.stopPrank();

        // Setup trader with 400 USDC
        uint256 tradingAmount = 400e6;
        uint256 expectedCollateralOutput = _calculateCollateralOutput(weth, tradingAmount, usdc, orderPrice);
        deal(usdc, trader, tradingAmount);

        vm.startPrank(trader);
        IERC20(usdc).approve(address(piv), tradingAmount);

        // Get initial balances
        uint256 traderUSDCBefore = IERC20(usdc).balanceOf(trader);
        uint256 traderWETHBefore = IERC20(weth).balanceOf(trader);

        // Execute swap
        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = orderId;

        vm.expectEmit(true, true, true, true);
        emit IPIV.OrderTraded(orderId, expectedCollateralOutput);

        (uint256 totalCollateralOutput, uint256 totalDebtInput) = piv.swap(orderIds, tradingAmount, trader);

        // Verify swap results
        assertEq(
            totalCollateralOutput, expectedCollateralOutput, "Collateral output should match expected collateral output"
        );
        assertEq(totalDebtInput, tradingAmount, "Debt input should match tradingAmount");

        // Verify balances changed correctly
        assertEq(
            IERC20(usdc).balanceOf(trader), traderUSDCBefore - tradingAmount, "Trader USDC balance should decrease"
        );
        assertEq(
            IERC20(weth).balanceOf(trader),
            traderWETHBefore + expectedCollateralOutput,
            "Trader WETH balance should increase"
        );

        // Verify order remaining collateral updated
        (,,, uint256 remainingCollateral,,) = piv.orderMapping(orderId);
        assertEq(
            remainingCollateral,
            orderCollateralAmount - expectedCollateralOutput,
            "Remaining collateral should be updated"
        );

        vm.stopPrank();
    }

    function testSwapMultipleOrders() public {
        vm.startPrank(borrower);

        // Place multiple orders
        uint256 orderCollateralAmount1 = 0.3 ether;
        uint256 orderPrice1 = 2000e18; // 1 WETH = 2000 USDC
        uint256 orderId1 = piv.placeOrder(weth, orderCollateralAmount1, usdc, orderPrice1, interestRate);

        uint256 orderCollateralAmount2 = 0.4 ether;
        uint256 orderPrice2 = 2100e18; // 1 WETH = 2100 USDC
        uint256 orderId2 = piv.placeOrder(weth, orderCollateralAmount2, usdc, orderPrice2, interestRate);

        vm.stopPrank();

        // Setup trader with enough USDC for both orders
        uint256 tradingAmount = 1020e6; // 600 USDC for first order + 420 USDC for second order
        uint256 totalOutputCollateral = 0.5 ether; // 0.3 + 0.2 ETH

        deal(usdc, trader, tradingAmount);

        vm.startPrank(trader);
        IERC20(usdc).approve(address(piv), tradingAmount);

        // Execute swap across multiple orders
        uint256[] memory orderIds = new uint256[](2);
        orderIds[0] = orderId1;
        orderIds[1] = orderId2;

        // Expect events for both orders
        vm.expectEmit(true, true, true, true);
        emit IPIV.OrderTraded(orderId1, orderCollateralAmount1);
        vm.expectEmit(true, true, true, true);
        emit IPIV.OrderTraded(orderId2, totalOutputCollateral - orderCollateralAmount1);

        (uint256 totalCollateralOutput, uint256 totalDebtInput) = piv.swap(orderIds, tradingAmount, trader);

        // Verify results
        assertEq(
            totalCollateralOutput,
            totalOutputCollateral,
            "Total collateral output should match expected collateral output"
        );
        assertEq(totalDebtInput, tradingAmount, "Total debt input should match required USDC");

        // Verify first order is completely filled
        (,,, uint256 remainingCollateral1,,) = piv.orderMapping(orderId1);
        assertEq(remainingCollateral1, 0, "First order should be completely filled");

        // Verify second order is partially filled
        (,,, uint256 remainingCollateral2,,) = piv.orderMapping(orderId2);
        assertEq(
            remainingCollateral2,
            orderCollateralAmount2 - (totalOutputCollateral - orderCollateralAmount1),
            "Second order should be partially filled"
        );

        vm.stopPrank();
    }

    function testSwapInsufficientCollateral() public {
        vm.startPrank(borrower);

        // Place a small order
        uint256 orderCollateralAmount = 0.1 ether;
        uint256 orderPrice = 2000e18; // 1 WETH = 2000 USDC
        uint256 orderId = piv.placeOrder(weth, orderCollateralAmount, usdc, orderPrice, interestRate);

        vm.stopPrank();

        // Try to swap more than available
        uint256 excessiveTradingAmount = 0.2 ether;
        uint256 requiredUSDC = _calculateDebtAmount(weth, excessiveTradingAmount, usdc, orderPrice);
        deal(usdc, trader, requiredUSDC);

        vm.startPrank(trader);
        IERC20(usdc).approve(address(piv), requiredUSDC);

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = orderId;

        (uint256 totalCollateralOutput, uint256 totalDebtInput) = piv.swap(orderIds, excessiveTradingAmount, trader);
        assertEq(totalCollateralOutput, orderCollateralAmount, "Should only fill available collateral");
        assertEq(
            totalDebtInput,
            _calculateDebtAmount(weth, orderCollateralAmount, usdc, orderPrice),
            "Should only charge for available collateral"
        );
        vm.stopPrank();
    }

    function testSwapInsufficientUSDCBalance() public {
        vm.startPrank(borrower);

        // Place an order
        uint256 orderCollateralAmount = 0.5 ether;
        uint256 orderPrice = 2000e18; // 1 WETH = 2000 USDC
        uint256 orderId = piv.placeOrder(weth, orderCollateralAmount, usdc, orderPrice, interestRate);

        vm.stopPrank();

        // Give trader insufficient USDC
        uint256 tradingAmount = 0.2 ether;
        uint256 requiredUSDC = _calculateDebtAmount(weth, tradingAmount, usdc, orderPrice);
        uint256 insufficientUSDC = requiredUSDC / 2;
        deal(usdc, trader, insufficientUSDC);

        vm.startPrank(trader);
        IERC20(usdc).approve(address(piv), insufficientUSDC);

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = orderId;

        vm.expectRevert(); // Should revert due to insufficient balance
        piv.swap(orderIds, tradingAmount, trader);

        vm.stopPrank();
    }

    function testRouterSwap() public {
        vm.startPrank(borrower);

        // Place an order
        uint256 orderCollateralAmount = 0.5 ether;
        uint256 orderPrice = 2000e18; // 1 WETH = 2000 USDC
        uint256 orderId = piv.placeOrder(weth, orderCollateralAmount, usdc, orderPrice, interestRate);

        vm.stopPrank();

        // Setup trader for router swap
        uint256 tradingAmount = 400e6; // 400 USDC worth of WETH
        uint256 expectedCollateralOutput = _calculateCollateralOutput(weth, tradingAmount, usdc, orderPrice);
        deal(usdc, trader, tradingAmount);

        vm.startPrank(trader);
        IERC20(usdc).approve(address(router), tradingAmount);

        // Prepare swap data for router
        IRouter.OrderData[] memory orderDatas = new IRouter.OrderData[](1);
        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = orderId;
        orderDatas[0] = IRouter.OrderData({pivAddress: address(piv), orderIds: orderIds});

        IRouter.SwapData memory swapData = IRouter.SwapData({
            tokenIn: usdc,
            tokenOut: weth,
            amountIn: tradingAmount,
            minAmountOut: expectedCollateralOutput,
            orderDatas: orderDatas
        });

        // Get initial balances
        uint256 traderUSDCBefore = IERC20(usdc).balanceOf(trader);
        uint256 traderWETHBefore = IERC20(weth).balanceOf(trader);

        // Expect SwapExecuted event
        vm.expectEmit(true, true, true, true);
        emit IRouter.SwapExecuted(usdc, weth, trader, tradingAmount, expectedCollateralOutput);

        // Execute router swap
        (uint256 netAmountOut,) = router.swap(swapData);

        // Verify results
        assertEq(netAmountOut, expectedCollateralOutput, "Net amount out should match trading amount");
        assertEq(IERC20(usdc).balanceOf(trader), traderUSDCBefore - tradingAmount, "Trader USDC should decrease");
        assertEq(
            IERC20(weth).balanceOf(trader), traderWETHBefore + expectedCollateralOutput, "Trader WETH should increase"
        );

        vm.stopPrank();
    }

    function testSwapInsufficientOutputInRouter() public {
        vm.startPrank(borrower);

        // Place an order
        uint256 orderCollateralAmount = 0.5 ether;
        uint256 orderPrice = 2000e18; // 1 WETH = 2000 USDC
        uint256 orderId = piv.placeOrder(weth, orderCollateralAmount, usdc, orderPrice, interestRate);

        vm.stopPrank();

        // Setup trader for router swap
        uint256 tradingAmount = 600e6; // 600 USDC worth of WETH
        uint256 expectedCollateralOutput = _calculateCollateralOutput(weth, tradingAmount, usdc, orderPrice);
        deal(usdc, trader, tradingAmount);

        vm.startPrank(trader);
        IERC20(usdc).approve(address(router), tradingAmount);

        // Prepare swap data with too high minimum output requirement
        IRouter.OrderData[] memory orderDatas = new IRouter.OrderData[](1);
        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = orderId;
        orderDatas[0] = IRouter.OrderData({pivAddress: address(piv), orderIds: orderIds});

        IRouter.SwapData memory swapData = IRouter.SwapData({
            tokenIn: usdc,
            tokenOut: weth,
            amountIn: tradingAmount,
            minAmountOut: expectedCollateralOutput + 0.1 ether, // Too high minimum
            orderDatas: orderDatas
        });

        // Should revert due to insufficient output
        vm.expectRevert("Insufficient output amount");
        router.swap(swapData);

        vm.stopPrank();
    }

    function testCalculateDebtAmount() public view {
        // Test with WETH as collateral and USDC as debt
        uint256 collateralAmount1 = 1 ether; // 1 WETH
        uint256 price = 2000e18; // 1 WETH = 2000 USDC

        uint256 requiredDebtAmount = _calculateDebtAmount(weth, collateralAmount1, usdc, price);
        assertEq(requiredDebtAmount, 2000e6, "Should calculate correct debt amount for 1 WETH at $2000");

        uint256 collateralOutput = _calculateCollateralOutput(weth, requiredDebtAmount, usdc, price);
        assertEq(collateralOutput, collateralAmount1, "Should calculate correct collateral output for 1 WETH at $2000");

        // Test with different price
        price = 2500e18; // 1 WETH = 2500 USDC
        requiredDebtAmount = _calculateDebtAmount(weth, collateralAmount1, usdc, price);
        assertEq(requiredDebtAmount, 2500e6, "Should calculate correct debt amount for 1 WETH at $2500");

        uint256 collateralOutput2 = _calculateCollateralOutput(weth, requiredDebtAmount, usdc, price);
        assertEq(collateralOutput2, collateralAmount1, "Should calculate correct collateral output for 1 WETH at $2500");
    }

    function _calculateCollateralOutput(address collateralToken, uint256 debtAmount_, address debtToken, uint256 price)
        internal
        view
        returns (uint256 collateralOutputAmount)
    {
        // price = collateral price * 1e18 / debt price
        uint256 collateralUnits = 10 ** IERC20Metadata(collateralToken).decimals();
        uint256 debtUnits = 10 ** IERC20Metadata(debtToken).decimals();

        collateralOutputAmount = (debtAmount_ * 1e18 * collateralUnits) / (price * debtUnits);
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
}
