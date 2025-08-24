// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../src/test/MockERC20.sol";
import "../src/test/MockAToken.sol";
import "../src/test/MockAavePool.sol";
import "../src/test/MockSwapAdapter.sol";
import "../src/test/Faucet.sol";
import "../src/Router.sol";
import "../src/PIV.sol";

contract DeployScript is Script {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    string rpcUrl = vm.envString("RPC_URL");

    function run() external {
        vm.rpcUrl(rpcUrl);
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer:", deployer);
        // start broadcasting transactions using the private key provided to forge
        vm.startBroadcast(deployerPrivateKey);

        address aaveAddressProvider = address(0);
        address pool = 0x64d10E4F2C4D35a0fBBE6C10b9c3fa908A78C047;

        Router router = new Router(address(pool), aaveAddressProvider);
        console.log("Router deployed at:", address(router));

        vm.stopBroadcast();
    }
}
