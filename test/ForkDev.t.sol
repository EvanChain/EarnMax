// filepath: /Users/evan/Documents/10-UnlockX/EarnMax/test/Piv.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {PIV, IERC20} from "../src/PIV.sol";
import {IPIV, Position} from "../src/IPIV.sol";
import {MockAavePool} from "../src/test/MockAavePool.sol";
import {MockAToken} from "../src/test/MockAToken.sol";
import {MockERC20} from "../src/test/MockERC20.sol";
import {MockSwapAdapter} from "../src/test/MockSwapAdapter.sol";
import {SwapUnit} from "../src/interfaces/IERC20SwapAdapter.sol";
import {Router, IRouter} from "../src/Router.sol";

contract ForkDevTest is Test {
    function setUp() public {
        // vm.createSelectFork(vm.envString("RPC_URL"));
    }

    // function testForkDev() public {
    //     address user = 0x4479B26363c0465EE05A45ED13B4fAeA3E8b009A;
    //     // Router router = Router(0x1aD5fc72C997A4BBc3cb5dD8028b0D884AF7E2cB);

    //     Router router = new Router(address(0), address(0));
    //     // {
    //     //     "tokenIn": "0x67f426aaD5b712DBacdA1b6A5Ef0e52C61c7e7Ca",
    //     //     "tokenOut": "0x09c2Be9B5c975580dafc72107d1E004287C734E5",
    //     //     "amountIn": "10000000",
    //     //     "minAmountOut": "0",
    //     //     "positionDatas": [
    //     //         {
    //     //             "pivAddress": "0xFC701a7f3a3133A0f8eD2E3461dA28cb66D80258",
    //     //             "positionId": 1
    //     //         }
    //     //     ]
    //     // }
    //     PIV piv = PIV(0xFC701a7f3a3133A0f8eD2E3461dA28cb66D80258);
    //     IRouter.SwapData memory swapData = IRouter.SwapData({
    //         tokenIn: 0x67f426aaD5b712DBacdA1b6A5Ef0e52C61c7e7Ca,
    //         tokenOut: 0x09c2Be9B5c975580dafc72107d1E004287C734E5,
    //         amountIn: 10000000,
    //         minAmountOut: 0,
    //         positionDatas: new IRouter.PositionData[](1)
    //     });
    //     swapData.positionDatas[0] = IRouter.PositionData({pivAddress: address(piv), positionId: 1});

    //     (
    //         address collateralToken,
    //         uint256 collateralAmount,
    //         address debtToken,
    //         int256 debtAmount,
    //         uint256 principal,
    //         uint256 interestRateMode, // 1 for stable, 2 for variable
    //         uint256 expectProfit, // The expect total profit, expectProfit = total collateral as debt token
    //         uint256 deadline // The dealine of the take time
    //     ) = piv.positionMapping(1);
    //     console.log("position.collateralAmount", collateralAmount);
    //     console.log("position.debtAmount", debtAmount);
    //     console.log("position.expectProfit", expectProfit);
    //     console.log("is expired", deadline < block.timestamp);

    //     (uint256 input, uint256 output) = piv.previewTakePosition(1, 1e7);
    //     console.log("preview input", input);
    //     console.log("preview output", output);

    //     vm.startPrank(user);
    //     IERC20(swapData.tokenIn).approve(address(router), swapData.amountIn);
    //     (uint256 netAmountOut, uint256 totalInputAmount) = router.swap(swapData);
    //     console.log("netAmountOut", netAmountOut);
    //     console.log("totalInputAmount", totalInputAmount);
    //     vm.stopPrank();
    // }
}
