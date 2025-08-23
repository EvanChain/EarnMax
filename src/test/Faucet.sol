// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {MockERC20} from "./MockERC20.sol";

contract Faucet {
    MockERC20 public immutable mockUSDC;
    MockERC20 public immutable mockETH;
    MockERC20 public immutable mockPtSusde;

    constructor() {
        mockUSDC = new MockERC20("USDC", "USDC", 6);
        mockETH = new MockERC20("WETH", "WETH", 18);
        mockPtSusde = new MockERC20("PT-sUSDE", "PT-sUSDE", 18);
    }

    function faucet() public {
        mockUSDC.mint(msg.sender, 10000e6);
        mockETH.mint(msg.sender, 100 ether);
        mockPtSusde.mint(msg.sender, 10000 ether);
    }
}
