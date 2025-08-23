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
        // Deploy a simple faucet and mock tokens for testing
        Faucet faucet = new Faucet();
        console.log("Faucet deployed at:", address(faucet));
        IERC20 usdc = faucet.mockUSDC();
        IERC20 weth = faucet.mockETH();
        IERC20 pt_susde = faucet.mockPtSusde();
        console.log("Mock USDC deployed at:", address(usdc));
        console.log("Mock WETH deployed at:", address(weth));
        console.log("Mock pt_susde deployed at:", address(pt_susde));

        MockSwapAdapter swapAdapter = new MockSwapAdapter();
        console.log("Mock Swap Adapter deployed at:", address(swapAdapter));

        // Deploy aToken mock and Aave-like pool
        MockAToken aUSDC = new MockAToken("aUSDC", "aUSDC");
        console.log("aUSDC deployed at:", address(aUSDC));

        MockAToken aWETH = new MockAToken("aWETH", "aWETH");
        console.log("aWETH deployed at:", address(aWETH));

        MockAToken aPtSusde = new MockAToken("aPtSusde", "aPtSusde");
        console.log("aPtSusde deployed at:", address(aPtSusde));

        MockAavePool pool = new MockAavePool();
        console.log("Mock Aave Pool deployed at:", address(pool));
        // Initialize reserve on the mock pool linking the asset and its aToken
        pool.initReserve(address(usdc), address(aUSDC), address(0), address(0), address(0));
        pool.initReserve(address(weth), address(aWETH), address(0), address(0), address(0));
        pool.initReserve(address(pt_susde), address(aPtSusde), address(0), address(0), address(0));

        // Deploy protocol contracts. We don't have a separate address provider in tests,
        // so pass address(0) for the addresses provider.
        address aaveAddressProvider = address(0);

        Router router = new Router(address(pool), aaveAddressProvider);
        console.log("Router deployed at:", address(router));
        PIV piv = new PIV(address(pool), aaveAddressProvider, deployer);
        console.log("PIV deployed at:", address(piv));

        vm.stopBroadcast();

        // write to deployments file
        string memory deploymentsFile =
            string.concat(vm.projectRoot(), "/deployments/", vm.toString(block.chainid), ".txt");

        console.log("Writing deployments to:", deploymentsFile);
        vm.writeFile(deploymentsFile, "");
        vm.writeLine(deploymentsFile, string.concat("Faucet=", vm.toString(address(faucet))));
        vm.writeLine(deploymentsFile, string.concat("MockUSDC=", vm.toString(address(usdc))));
        vm.writeLine(deploymentsFile, string.concat("MockWETH=", vm.toString(address(weth))));
        vm.writeLine(deploymentsFile, string.concat("MockPtSusde=", vm.toString(address(pt_susde))));
        vm.writeLine(deploymentsFile, string.concat("MockSwapAdapter=", vm.toString(address(swapAdapter))));
        vm.writeLine(deploymentsFile, string.concat("MockAUSDC=", vm.toString(address(aUSDC))));
        vm.writeLine(deploymentsFile, string.concat("MockAWETH=", vm.toString(address(aWETH))));
        vm.writeLine(deploymentsFile, string.concat("MockAPtSusde=", vm.toString(address(aPtSusde))));
        vm.writeLine(deploymentsFile, string.concat("MockAavePool=", vm.toString(address(pool))));
        vm.writeLine(deploymentsFile, string.concat("Router=", vm.toString(address(router))));
        vm.writeLine(deploymentsFile, string.concat("PIV=", vm.toString(address(piv))));
    }
}
