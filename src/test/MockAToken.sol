// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockAToken is ERC20 {
    address public pool;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function setPool(address _pool) external {
        pool = _pool;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == pool, "MockAToken: only pool");
        _mint(to, amount);
    }

    function burnFrom(address from, uint256 amount) external {
        require(msg.sender == pool, "MockAToken: only pool");
        _burn(from, amount);
    }
}
