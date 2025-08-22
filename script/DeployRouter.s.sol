// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {Router, PIV, IERC20} from "../src/Router.sol";

contract RouterScript is Script {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    string rpcUrl = vm.envString("RPC_URL");

    Router public router;

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        // eth-sepolia
        address aaveV3Pool = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
        address aaveV3AddressProvider = 0x012bAC54348C0E635dCAc9D5FB99f06F24136C9A;
        vm.label(aaveV3Pool, "Aave V3 Pool");
        vm.label(aaveV3AddressProvider, "Aave V3 Address Provider");
        // address anotherAddress = 0x4479B26363c0465EE05A45ED13B4fAeA3E8b009A;

        router = new Router(aaveV3Pool, aaveV3AddressProvider);
        console.log("Router deployed at:", address(router));
        vm.label(address(router), "Router");

        PIV piv = PIV(router.deployPIV());
        console.log("PIV deployed at:", address(piv));
        vm.label(address(piv), "PIV");

        address wbtc = 0x29f2D40B0605204364af54EC677bD022dA425d03;
        address usdc = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
        vm.label(wbtc, "WBTC");
        vm.label(usdc, "USDC");
        address awbtc = piv.atokenAddress(wbtc);
        uint256 wbtcAmount = 0.1e8; // 0.1 WBTC
        uint256 usdcAmount = 10e6; // 10 USDC
        IERC20(awbtc).approve(address(piv), type(uint256).max);
        piv.migrateFromAave(
            IERC20(wbtc),
            wbtcAmount,
            IERC20(usdc),
            usdcAmount,
            2 // interest rate mode
        );

        uint256 price = 110000e18; // 100,000 USDC per WBTC

        // place a swap order
        piv.placeOrder(
            wbtc,
            wbtcAmount/10,
            usdc,
            price,
            2 // interest rate mode
        );

        vm.stopBroadcast();
    }
}
