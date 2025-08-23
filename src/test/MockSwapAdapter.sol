// filepath: /Users/evan/Documents/10-UnlockX/EarnMax/src/test/MockSwapAdapter.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20SwapAdapter} from "../interfaces/IERC20SwapAdapter.sol";
import {MockERC20} from "./MockERC20.sol";
/// @notice Simple mock swap adapter for tests
/// @dev swapData (optional) should be abi.encode(uint256 outAmount). If omitted, outAmount == tokenInAmt

contract MockSwapAdapter is IERC20SwapAdapter {
    /// @notice Swap tokenIn -> tokenOut for tests
    /// @dev Adapter pulls tokenIn from caller (transferFrom). Then transfers tokenOut from its own balance to recipient.
    /// swapData can contain an abi-encoded uint256 specifying the exact tokenOut amount to send.
    function swap(address recipient, address tokenIn, address tokenOut, uint256 tokenInAmt, bytes memory swapData)
        external
        override
        returns (uint256 tokenOutAmt)
    {
        // pull tokenIn from caller to this adapter for accounting (if non-zero)
        if (tokenInAmt > 0) {
            require(
                IERC20(tokenIn).transferFrom(msg.sender, address(this), tokenInAmt),
                "MockSwapAdapter: transferFrom failed"
            );
        }

        // decode desired output amount from swapData if provided
        if (swapData.length >= 32) {
            tokenOutAmt = abi.decode(swapData, (uint256));
        } else {
            tokenOutAmt = tokenInAmt;
        }

        // transfer tokenOut from this adapter to recipient
        if (tokenOutAmt > 0) {
            MockERC20(tokenOut).mint(recipient, tokenOutAmt);
        }

        return tokenOutAmt;
    }
}
