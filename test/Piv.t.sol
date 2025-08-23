// filepath: /Users/evan/Documents/10-UnlockX/EarnMax/test/Piv.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {PIV} from "../src/PIV.sol";
import {IPIV, Position} from "../src/IPIV.sol";
import {MockAavePool} from "../src/test/MockAavePool.sol";
import {MockAToken} from "../src/test/MockAToken.sol";
import {MockERC20} from "../src/test/MockERC20.sol";

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

        // deploy PIV owned by this test contract
        piv = new PIV(address(pool), address(0), address(this));

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

        // call migrateFromAave as owner
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

        piv.migrateFromAave(position);

        // update expectProfit and deadline so position is takeable
        uint256 expectProfit = 500e6; // e.g. expected profit in debt token units
        uint256 deadline = block.timestamp; // allow taking now
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
}
