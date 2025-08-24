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

    function test_takePosition_allowsWhenDeadlineInFuture() public {
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

        // update expectProfit and deadline in the future so position is takeable
        uint256 expectProfit = 500e6; // expected profit in debt token units
        uint256 deadline = block.timestamp + 1 hours; // future deadline
        vm.prank(user);
        piv.updateExpectProfit(1, expectProfit, deadline);

        // choose an input amount less than expectProfit
        uint256 input = 200e6;
        (uint256 debtInput, uint256 collateralOutput) = piv.previewTakePosition(1, input);

        // preview should return non-zero values (deadline in future should allow taking)
        assertEq(debtInput, input);
        uint256 expectedCollateralOut = (debtInput * collateralAmount) / expectProfit;
        assertEq(collateralOutput, expectedCollateralOut);

        // prepare a taker with enough debt token (USDC) and approve the PIV contract
        address taker = vm.addr(10);
        address receiver = vm.addr(11);
        usdc.mint(taker, debtInput);
        vm.prank(taker);
        usdc.approve(address(piv), debtInput);

        // ensure the PIV contract holds the collateral token to be transferred
        weth.mint(address(this), collateralOutput);
        weth.transfer(address(piv), collateralOutput);

        uint256 takerBefore = usdc.balanceOf(taker);
        uint256 receiverBefore = weth.balanceOf(receiver);

        // taker takes the position
        vm.prank(taker);
        (uint256 actualDebtInput, uint256 actualCollateralOutput) = piv.takePosition(1, input, receiver);

        // verify returned values and transfers
        assertEq(actualDebtInput, debtInput);
        assertEq(actualCollateralOutput, collateralOutput);
        assertEq(usdc.balanceOf(taker), takerBefore - debtInput);
        assertEq(weth.balanceOf(receiver), receiverBefore + collateralOutput);

        // verify position updated in storage
        (,,, int256 debtAmountAfter,,,,) = piv.positionMapping(1);
        assertEq(debtAmountAfter, int256(debtAmount) - int256(debtInput));
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
        units[0] = SwapUnit({
            adapter: address(adapter),
            tokenIn: address(usdc),
            tokenOut: address(weth),
            swapData: abi.encode(collateralAmount)
        });

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

    function test_closePosition_closesPositionAndEmitsEvent() public {
        // First create a position using the migrate flow
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
        uint256 posId = piv.migrateFromAave(position);

        // verify position was created
        assertEq(posId, 1);
        assertEq(piv.totalPositions(), 1);

        // Get the actual debt amount after migration (includes premium from migration)
        (,,, int256 actualDebtAmount,,,,) = piv.positionMapping(1);
        uint256 actualDebt = uint256(actualDebtAmount);

        // deploy a mock swap adapter for closing
        MockSwapAdapter adapter = new MockSwapAdapter();

        // ensure the pool has enough debt token for flash loan repayment
        usdc.mint(address(pool), actualDebt * 2);
        vm.prank(address(pool));
        usdc.approve(address(piv), actualDebt * 2);

        // calculate expected profit for closing (need to account for closing premium too)
        uint256 closingPremium = (uint256(pool.FLASHLOAN_PREMIUM_TOTAL()) * actualDebt) / 10000;
        uint256 swapOutput = actualDebt + closingPremium + 100e6; // enough to cover repayment + some profit
        uint256 expectedProfit = swapOutput - (actualDebt + closingPremium);

        // construct swap units to convert collateralToken -> debtToken
        SwapUnit[] memory units = new SwapUnit[](1);
        units[0] = SwapUnit({
            adapter: address(adapter),
            tokenIn: address(weth),
            tokenOut: address(usdc),
            swapData: abi.encode(swapOutput) // mock adapter will return this amount
        });

        // verify initial position state
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

        assertTrue(debtAmount0 > 0, "Position should have debt before closing");
        assertTrue(collateralAmount0 > 0, "Position should have collateral before closing");

        // expect the LoanClosed event with the calculated profit
        vm.expectEmit(true, true, false, false);
        emit IPIV.LoanClosed(1, expectedProfit);

        // close position as the owner (user)
        vm.prank(user);
        piv.closePosition(1, units);

        // verify position is marked as closed
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

        assertEq(debtAmount1, -int256(expectedProfit), "Debt amount should be negative profit after closing");
        assertEq(collateralAmount1, 0, "Collateral amount should be zero after closing");
        assertEq(expectProfit1, 0, "Expect profit should be zero after closing");
        assertEq(deadline1, 0, "Deadline should be zero after closing");

        // verify PIV no longer holds the aToken
        assertEq(aWeth.balanceOf(address(piv)), 0, "PIV should not hold aTokens after closing");
    }

    function test_closePosition_revertsIfPositionAlreadyClosed() public {
        // First create a position using the migrate flow
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
        uint256 posId = piv.migrateFromAave(position);

        // Get the actual debt amount after migration
        (,,, int256 actualDebtAmount,,,,) = piv.positionMapping(1);
        uint256 actualDebt = uint256(actualDebtAmount);

        // close the position first
        MockSwapAdapter adapter = new MockSwapAdapter();
        usdc.mint(address(pool), actualDebt * 2);
        vm.prank(address(pool));
        usdc.approve(address(piv), actualDebt * 2);

        // calculate required amount for successful close
        uint256 premium = (uint256(pool.FLASHLOAN_PREMIUM_TOTAL()) * actualDebt) / 10000;
        uint256 swapOutput = actualDebt + premium + 100e6; // enough to cover repayment

        SwapUnit[] memory units = new SwapUnit[](1);
        units[0] = SwapUnit({
            adapter: address(adapter),
            tokenIn: address(weth),
            tokenOut: address(usdc),
            swapData: abi.encode(swapOutput)
        });

        vm.prank(user);
        piv.closePosition(1, units);

        // try to close again - should revert
        vm.prank(user);
        vm.expectRevert("Position already closed");
        piv.closePosition(1, units);
    }

    function test_closePosition_revertsIfNotOwner() public {
        // First create a position using the migrate flow
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
        uint256 posId = piv.migrateFromAave(position);

        // deploy a mock swap adapter
        MockSwapAdapter adapter = new MockSwapAdapter();
        SwapUnit[] memory units = new SwapUnit[](1);
        units[0] = SwapUnit({
            adapter: address(adapter),
            tokenIn: address(weth),
            tokenOut: address(usdc),
            swapData: abi.encode(debtAmount)
        });

        // try to close as non-owner - should revert
        address nonOwner = vm.addr(999);
        vm.prank(nonOwner);
        vm.expectRevert();
        piv.closePosition(1, units);
    }

    function test_closePosition_revertsIfInsufficientDebtTokenAfterSwap() public {
        // First create a position using the migrate flow
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
        uint256 posId = piv.migrateFromAave(position);

        // deploy a mock swap adapter that returns insufficient amount
        MockSwapAdapter adapter = new MockSwapAdapter();
        usdc.mint(address(pool), debtAmount * 2);
        vm.prank(address(pool));
        usdc.approve(address(piv), debtAmount * 2);

        SwapUnit[] memory units = new SwapUnit[](1);
        units[0] = SwapUnit({
            adapter: address(adapter),
            tokenIn: address(weth),
            tokenOut: address(usdc),
            swapData: abi.encode(debtAmount / 2) // insufficient amount
        });

        // expect revert due to insufficient debt token after swap
        vm.prank(user);
        vm.expectRevert("Insufficient debt token after swap");
        piv.closePosition(1, units);
    }

    function test_closePosition_worksWithCreatedPosition() public {
        // Create a new position using createPosition instead of migrate
        MockSwapAdapter adapter = new MockSwapAdapter();

        // prepare a new position
        Position memory position;
        position.collateralToken = address(weth);
        position.collateralAmount = collateralAmount;
        position.debtToken = address(usdc);
        position.debtAmount = int256(500e6);
        position.principal = 0;
        position.interestRateMode = interestRateMode;
        position.expectProfit = 0;
        position.deadline = 0;

        uint256 loanAmt = uint256(position.debtAmount);

        // ensure the pool has enough of the debt token
        usdc.mint(address(pool), loanAmt * 3);
        vm.prank(address(pool));
        usdc.approve(address(piv), loanAmt * 3);

        // construct swap units for creation
        SwapUnit[] memory createUnits = new SwapUnit[](1);
        createUnits[0] = SwapUnit({
            adapter: address(adapter),
            tokenIn: address(usdc),
            tokenOut: address(weth),
            swapData: abi.encode(collateralAmount)
        });

        // create position
        vm.prank(user);
        uint256 posId = piv.createPosition(position, false, createUnits);

        // verify position was created
        assertEq(posId, 1);
        assertEq(piv.totalPositions(), 1);

        // get the actual debt amount after creation (includes premium)
        (,,, int256 actualDebtAmount,,,,) = piv.positionMapping(1);
        uint256 actualDebt = uint256(actualDebtAmount);

        // calculate required amount for closing
        uint256 premium = (uint256(pool.FLASHLOAN_PREMIUM_TOTAL()) * actualDebt) / 10000;
        uint256 swapOutput = actualDebt + premium + 100e6; // enough to cover loan + premium + profit
        uint256 expectedProfit = swapOutput - (actualDebt + premium);

        // construct swap units for closing (reverse direction)
        SwapUnit[] memory closeUnits = new SwapUnit[](1);
        closeUnits[0] = SwapUnit({
            adapter: address(adapter),
            tokenIn: address(weth),
            tokenOut: address(usdc),
            swapData: abi.encode(swapOutput)
        });

        // close the position
        vm.prank(user);
        piv.closePosition(1, closeUnits);

        // verify position is closed
        (, uint256 collateralAmount1,, int256 debtAmount1,,, uint256 expectProfit1, uint256 deadline1) =
            piv.positionMapping(1);

        assertEq(debtAmount1, -int256(expectedProfit), "Debt amount should be negative profit after closing");
        assertEq(collateralAmount1, 0, "Collateral amount should be zero after closing");
        assertEq(expectProfit1, 0, "Expect profit should be zero after closing");
        assertEq(deadline1, 0, "Deadline should be zero after closing");
    }

    function test_closePosition_revertsWithEmptySwapUnits() public {
        // First create a position
        Position memory position;
        position.collateralToken = address(weth);
        position.collateralAmount = collateralAmount;
        position.debtToken = address(usdc);
        position.debtAmount = int256(debtAmount);
        position.principal = 0;
        position.interestRateMode = interestRateMode;
        position.expectProfit = 0;
        position.deadline = 0;

        vm.prank(user);
        uint256 posId = piv.migrateFromAave(position);

        // ensure pool has enough debt tokens
        usdc.mint(address(pool), debtAmount * 2);
        vm.prank(address(pool));
        usdc.approve(address(piv), debtAmount * 2);

        // try to close with empty swap units
        SwapUnit[] memory emptyUnits = new SwapUnit[](0);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IPIV.SwapUnitsIsEmpty.selector));
        piv.closePosition(1, emptyUnits);
    }
}
