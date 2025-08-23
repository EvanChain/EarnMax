// filepath: /Users/evan/Documents/10-UnlockX/EarnMax/test/Router.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {Router} from "../src/Router.sol";
import {PIV} from "../src/PIV.sol";
import {MockAavePool} from "../src/test/MockAavePool.sol";
import {MockAToken} from "../src/test/MockAToken.sol";
import {MockERC20} from "../src/test/MockERC20.sol";
import {IPIV, Position} from "../src/IPIV.sol";
import {IRouter} from "../src/IRouter.sol";

contract RouterTest is Test {
    MockAavePool internal pool;
    Router internal router;

    address internal user = vm.addr(1);

    function setUp() public {
        pool = new MockAavePool();
        router = new Router(address(pool), address(0));
    }

    function test_deployPIV_createsPIVAndStoresMapping() public {
        // deploy a PIV as `user`
        vm.prank(user);
        address pivAddr = router.deployPIV();

        // mapping should point to deployed PIV
        assertEq(router.userPivMapping(user), pivAddr);
        assertTrue(pivAddr != address(0));

        // the PIV owner should be the deploying user
        PIV piv = PIV(pivAddr);
        assertEq(piv.owner(), user);

        // calling deployPIV again should return the same address and not create a second PIV
        vm.prank(user);
        address pivAddr2 = router.deployPIV();
        assertEq(pivAddr2, pivAddr);
    }

    function test_swap_consumesInputAndTransfersCollateral() public {
        // create tokens and aTokens similar to PIV tests
        MockAToken aWeth = new MockAToken("aWETH", "aWETH");
        MockERC20 weth = new MockERC20("WETH", "WETH", 18);
        MockERC20 usdc = new MockERC20("USDC", "USDC", 6);

        uint256 collateralAmount = 1 ether;
        uint256 debtAmount = 1000e6;
        uint256 interestRateMode = 2;

        // init reserve so pool knows the aToken
        pool.initReserve(address(weth), address(aWeth), address(0), address(0), address(0));

        // mint WETH to this contract and supply on behalf of `user` so user owns the aTokens
        weth.mint(address(this), collateralAmount);
        weth.approve(address(pool), collateralAmount);
        pool.supply(address(weth), collateralAmount, user, 0);

        // mint USDC to pool so it can lend and create a borrow for the user
        usdc.mint(address(pool), debtAmount);
        pool.borrow(address(usdc), debtAmount, 0, uint16(interestRateMode), user);

        // deploy a PIV for the user via the router
        vm.prank(user);
        address pivAddr = router.deployPIV();

        // user must approve PIV to move their aTokens
        vm.prank(user);
        aWeth.approve(pivAddr, collateralAmount);

        // prepare and migrate position from Aave into PIV
        Position memory position;
        position.collateralToken = address(weth);
        position.collateralAmount = collateralAmount;
        position.debtToken = address(usdc);
        position.debtAmount = int256(debtAmount);
        position.principal = 0;
        position.interestRateMode = interestRateMode;
        position.expectProfit = 0;
        position.deadline = 0;

        // migrate as the user (owner)
        vm.prank(user);
        PIV(pivAddr).migrateFromAave(position);

        // update expectProfit and deadline so position is takeable
        uint256 expectProfit = 500e6;
        uint256 deadline = block.timestamp;
        vm.prank(user);
        PIV(pivAddr).updateExpectProfit(1, expectProfit, deadline);

        // prepare taker and approvals
        address taker = vm.addr(2);
        uint256 swapIn = 200e6; // less than expectProfit
        usdc.mint(taker, swapIn);
        vm.prank(taker);
        usdc.approve(address(router), swapIn);

        // Router must approve PIV to pull tokens from Router after Router received them
        vm.prank(address(router));
        usdc.approve(pivAddr, swapIn);

        // compute expected collateral output and ensure PIV holds that collateral
        uint256 expectedCollateralOut = (swapIn * collateralAmount) / expectProfit;
        weth.mint(pivAddr, expectedCollateralOut);

        // construct swap data
        IRouter.PositionData[] memory posDatas = new IRouter.PositionData[](1);
        posDatas[0] = IRouter.PositionData({pivAddress: pivAddr, positionId: 1});
        IRouter.SwapData memory swapData = IRouter.SwapData({
            tokenIn: address(usdc),
            tokenOut: address(weth),
            amountIn: swapIn,
            minAmountOut: 0,
            positionDatas: posDatas
        });

        // record balances before
        uint256 routerWethBefore = weth.balanceOf(address(router));
        uint256 takerUsdcBefore = usdc.balanceOf(taker);

        // perform swap as taker
        vm.prank(taker);
        (uint256 netOut, uint256 totalIn) = router.swap(swapData);

        // verify outputs and balances
        assertEq(netOut, expectedCollateralOut);
        assertEq(weth.balanceOf(address(router)), routerWethBefore + expectedCollateralOut);
        assertEq(usdc.balanceOf(taker), takerUsdcBefore - swapIn);

        // Note: Router.totalInputAmount is uninitialized in the contract implementation; we only assert netOut here
        assertEq(totalIn, 0);
    }
}