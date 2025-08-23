// filepath: /Users/evan/Documents/10-UnlockX/EarnMax/test/Piv.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {PIV} from "../src/PIV.sol";
import {IPIV, Position} from "../src/IPIV.sol";
import {MockAavePool} from "../src/test/MockAavePool.sol";
import {MockAToken} from "../src/test/MockAToken.sol";
import {MockERC20} from "../src/test/MockERC20.sol";
import {MockSwapAdapter} from "../src/test/MockSwapAdapter.sol";
import {SwapUnit} from "../src/interfaces/IERC20SwapAdapter.sol";

contract PIVTest is Test {
    MockAavePool internal pool;
    MockAToken internal aWeth;
    MockERC20 internal weth;
    MockERC20 internal usdc;
    PIV internal piv;

    address internal user = vm.addr(1);
    uint256 internal collateralAmount = 1 ether;
    uint256 internal debtAmount = 1000e6;
    uint256 internal interestRateMode = 2; // variable

    function setUp() public {
        // deploy mocks
        pool = new MockAavePool();
        aWeth = new MockAToken("aWETH", "aWETH");
        weth = new MockERC20("WETH", "WETH", 18);
        usdc = new MockERC20("USDC", "USDC", 6);

        // init reserve so pool knows the aToken
        pool.initReserve(address(weth), address(aWeth), address(0), address(0), address(0));

        // mint WETH to this contract and supply on behalf of `user` so user owns the aTokens
        weth.mint(address(this), collateralAmount);
        weth.approve(address(pool), collateralAmount);
        pool.supply(address(weth), collateralAmount, user, 0);

        // mint USDC to pool so it can lend
        usdc.mint(address(pool), debtAmount);

        // create a prior borrow for the user on the pool
        pool.borrow(address(usdc), debtAmount, 0, uint16(interestRateMode), user);

        // deploy PIV owned by the user (matches real flow where user deploys their PIV)
        piv = new PIV(address(pool), address(0), user);

        // user must approve PIV to move their aTokens (the pool minted them to `user`)
        vm.prank(user);
        aWeth.approve(address(piv), collateralAmount);
    }

    function test_migrateFromAave_reducesUserDebt_and_transfersAToken() public {
        // prepare position struct: collateralToken is the underlying (weth), collateralAmount is aToken amount
        Position memory position;
        position.collateralToken = address(weth);
        position.collateralAmount = collateralAmount;
        position.debtToken = address(usdc);
        position.debtAmount = int256(debtAmount);
        position.principal = 0;
        position.interestRateMode = interestRateMode;
        position.expectProfit = 0;
        position.deadline = 0;

        uint256 beforeDebt = pool.userDebt(user, address(usdc));

        // call migrateFromAave as the user (PIV owner)
        vm.prank(user);
        uint256 posId = piv.migrateFromAave(position);

        // totalPositions should have incremented
        assertEq(posId, 1);
        assertEq(piv.totalPositions(), 1);

        // user debt should be reduced (repaid)
        uint256 afterDebt = pool.userDebt(user, address(usdc));
        assertEq(afterDebt, beforeDebt - debtAmount);

        // PIV should hold the user's aToken balance equal to collateralAmount
        address aTokenAddr = pool.getReserveData(address(weth)).aTokenAddress;
        assertEq(aTokenAddr, address(aWeth));
        assertEq(aWeth.balanceOf(address(piv)), collateralAmount);
    }

    function test_previewTakePosition_computesExpectedAmounts() public {
        // reuse migrate flow to create a position
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
        piv.migrateFromAave(position);

        // update expectProfit and deadline so position is takeable (owner-only)
        uint256 expectProfit = 500e6; // e.g. expected profit in debt token units
        uint256 deadline = block.timestamp; // allow taking now
        vm.prank(user);
        piv.updateExpectProfit(1, expectProfit, deadline);

        // choose an input amount less than expectProfit
        uint256 input = 200e6;
        (uint256 debtInput, uint256 collateralOutput) = piv.previewTakePosition(1, input);

        // debtInput should equal input (since input < expectProfit)
        assertEq(debtInput, input);
        // collateralOutput = debtInput * collateralAmount / expectProfit
        uint256 expectedCollateralOut = (debtInput * collateralAmount) / expectProfit;
        assertEq(collateralOutput, expectedCollateralOut);
    }

    function test_takePosition_transfersAndUpdatesPosition() public {
        // reuse migrate flow to create a position
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
        piv.migrateFromAave(position);

        // update expectProfit and deadline so position is takeable (owner-only)
        uint256 expectProfit = 500e6; // e.g. expected profit in debt token units
        uint256 deadline = block.timestamp; // allow taking now
        vm.prank(user);
        piv.updateExpectProfit(1, expectProfit, deadline);

        // choose an input amount less than expectProfit
        uint256 input = 200e6;

        // compute preview amounts
        (uint256 debtInput, uint256 collateralOutput) = piv.previewTakePosition(1, input);
        assertEq(debtInput, input);
        uint256 expectedCollateralOut = (debtInput * collateralAmount) / expectProfit;
        assertEq(collateralOutput, expectedCollateralOut);

        // prepare a taker with enough debt token (USDC) and approve the PIV contract
        address taker = vm.addr(2);
        address receiver = vm.addr(3);
        usdc.mint(taker, debtInput);
        vm.prank(taker);
        usdc.approve(address(piv), debtInput);

        // ensure the PIV contract holds the collateral token to be transferred
        // mint underlying collateral to this test contract and transfer to PIV
        weth.mint(address(this), collateralOutput);
        weth.transfer(address(piv), collateralOutput);

        // record balances before
        uint256 takerBefore = usdc.balanceOf(taker);
        uint256 receiverBefore = weth.balanceOf(receiver);
        (
            address collateralToken0,
            uint256 collateralAmount0,
            address debtToken0,
            int256 debtAmount0,
            uint256 principal0,
            uint256 interestRateMode0,
            uint256 expectProfit0,
            uint256 deadline0
        ) = piv.positionMapping(1);
        Position memory beforePos = Position(
            collateralToken0,
            collateralAmount0,
            debtToken0,
            debtAmount0,
            principal0,
            interestRateMode0,
            expectProfit0,
            deadline0
        );

        // taker takes the position
        vm.prank(taker);
        (uint256 actualDebtInput, uint256 actualCollateralOutput) = piv.takePosition(1, input, receiver);

        // verify returned values
        assertEq(actualDebtInput, debtInput);
        assertEq(actualCollateralOutput, collateralOutput);

        // verify transfers: taker paid debtInput, receiver got collateralOutput
        assertEq(usdc.balanceOf(taker), takerBefore - debtInput);
        assertEq(weth.balanceOf(receiver), receiverBefore + collateralOutput);

        // verify position updated in storage
        (
            address collateralToken1,
            uint256 collateralAmount1,
            address debtToken1,
            int256 debtAmount1,
            uint256 principal1,
            uint256 interestRateMode1,
            uint256 expectProfit1,
            uint256 deadline1
        ) = piv.positionMapping(1);
        Position memory afterPos = Position(
            collateralToken1,
            collateralAmount1,
            debtToken1,
            debtAmount1,
            principal1,
            interestRateMode1,
            expectProfit1,
            deadline1
        );
        assertEq(afterPos.debtAmount, beforePos.debtAmount - int256(debtInput));
        assertEq(afterPos.expectProfit, beforePos.expectProfit - debtInput);
        assertEq(afterPos.collateralAmount, beforePos.collateralAmount - collateralOutput);
    }

    function test_createPosition_createsPositionAndSuppliesToAave() public {
        // deploy a mock swap adapter
        MockSwapAdapter adapter = new MockSwapAdapter();

        // prepare a new position
        Position memory position;
        position.collateralToken = address(weth);
        position.collateralAmount = collateralAmount; // expect to receive this much collateral
        position.debtToken = address(usdc);
        position.debtAmount = int256(500e6); // flashloan amount
        position.principal = 0;
        position.interestRateMode = interestRateMode;
        position.expectProfit = 0;
        position.deadline = 0;

        uint256 loanAmt = uint256(position.debtAmount);

        // ensure the pool has enough of the debt token and approve PIV to pull tokenIn during swap
        usdc.mint(address(pool), loanAmt);
        vm.prank(address(pool));
        usdc.approve(address(piv), loanAmt * 2);

        // construct swap units to convert debtToken -> collateralToken
        SwapUnit[] memory units = new SwapUnit[](1);
        units[0] = SwapUnit({adapter: address(adapter), tokenIn: address(usdc), tokenOut: address(weth), swapData: abi.encode(collateralAmount)});

        // call createPosition as the owner (user)
        vm.prank(user);
        uint256 posId = piv.createPosition(position, false, units);

        // position id and totalPositions should increment
        assertEq(posId, 1);
        assertEq(piv.totalPositions(), 1);

        // verify PIV holds the aToken minted by the pool equal to the collateral supplied
        address aTokenAddr = pool.getReserveData(address(weth)).aTokenAddress;
        assertEq(aTokenAddr, address(aWeth));
        assertEq(aWeth.balanceOf(address(piv)), collateralAmount);

        // compute expected debt (amount + premium)
        uint256 premium = (uint256(pool.FLASHLOAN_PREMIUM_TOTAL()) * loanAmt) / 10000;
        uint256 expectedDebt = loanAmt + premium;

        // verify stored position debt equals amount + premium
        (
            address collateralToken0,
            uint256 collateralAmount0,
            address debtToken0,
            int256 debtAmount0,
            uint256 principal0,
            uint256 interestRateMode0,
            uint256 expectProfit0,
            uint256 deadline0
        ) = piv.positionMapping(1);

        assertEq(uint256(debtAmount0), expectedDebt);

        // verify the pool recorded the borrow on behalf of PIV
        assertEq(pool.userDebt(address(piv), address(usdc)), expectedDebt);
    }
}
