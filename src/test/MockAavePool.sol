// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAaveV3PoolMinimal} from "../extensions/IAaveV3PoolMinimal.sol";
import {MockAToken} from "./MockAToken.sol";
import {MockERC20} from "./MockERC20.sol";
import {IAaveV3FlashLoanReceiver} from "../extensions/IAaveV3FlashLoanReceiver.sol";

contract MockAavePool is IAaveV3PoolMinimal {
    using SafeERC20 for IERC20;

    uint128 public constant FLASHLOAN_PREMIUM_TOTAL = 9; // 0.09% (in bps)
    uint128 public constant FLASHLOAN_PREMIUM_TO_PROTOCOL_CONST = 0;

    struct ReserveDataInternal {
        address aTokenAddress;
    }

    mapping(address => ReserveDataInternal) internal reserves;
    // user -> asset -> debt
    mapping(address => mapping(address => uint256)) public userDebt;

    function initReserve(address asset, address aTokenAddress, address, address, address) external override {
        reserves[asset].aTokenAddress = aTokenAddress;
        // let the aToken know who is the pool
        MockAToken(aTokenAddress).setPool(address(this));
    }

    function getReserveData(address asset) external view override returns (ReserveData memory) {
        ReserveData memory rd;
        rd.aTokenAddress = reserves[asset].aTokenAddress;
        return rd;
    }

    function supply(address asset, uint256 amount, address onBehalfOf, uint16) external override {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        address aToken = reserves[asset].aTokenAddress;
        require(aToken != address(0), "Reserve not initialized");
        MockAToken(aToken).mint(onBehalfOf, amount);
    }

    function withdraw(address asset, uint256 amount, address to) external override returns (uint256) {
        address aToken = reserves[asset].aTokenAddress;
        require(aToken != address(0), "Reserve not initialized");
        // burn aTokens from msg.sender
        MockAToken(aToken).burnFrom(msg.sender, amount);
        MockERC20(asset).mint(to, amount);
        return amount;
    }

    function borrow(address asset, uint256 amount, uint256, uint16, address onBehalfOf) external override {
        // transfer underlying to the borrower
        MockERC20(asset).mint(onBehalfOf, amount);
        userDebt[onBehalfOf][asset] += amount;
    }

    function repay(address asset, uint256 amount, uint256, address onBehalfOf) external override returns (uint256) {
        // pull tokens from msg.sender (the caller should have approved the pool)
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        uint256 debt = userDebt[onBehalfOf][asset];
        uint256 repaid = amount > debt ? debt : amount;
        userDebt[onBehalfOf][asset] = debt - repaid;
        return repaid;
    }

    function flashLoanSimple(address receiverAddress, address asset, uint256 amount, bytes calldata params, uint16)
        external
        override
    {
        address receiver = receiverAddress;
        uint256 premium = (uint256(FLASHLOAN_PREMIUM_TOTAL) * amount) / 10000;
        // transfer the funds to the receiver
        MockERC20(asset).mint(receiver, amount);

        // call the receiver
        bool ok = IAaveV3FlashLoanReceiver(receiver).executeOperation(asset, amount, premium, msg.sender, params);
        require(ok, "Flash loan callback failed");

        // pull back amount + premium
        IERC20(asset).safeTransferFrom(receiver, address(this), amount + premium);
        // For simplicity, premium remains in the pool
    }

    function updateFlashloanPremiums(uint128, uint128) external override {}

    // The following functions are not used in the minimal mock but required by the interface. Provide stub implementations.
    function mintUnbacked(address, uint256, address, uint16) external override {}

    function backUnbacked(address, uint256, uint256) external override returns (uint256) {
        return 0;
    }

    function supplyWithPermit(address, uint256, address, uint16, uint256, uint8, bytes32, bytes32) external override {}

    function repayWithPermit(address, uint256, uint256, address, uint256, uint8, bytes32, bytes32)
        external
        override
        returns (uint256)
    {
        return 0;
    }

    function repayWithATokens(address, uint256, uint256) external override returns (uint256) {
        return 0;
    }

    function swapBorrowRateMode(address, uint256) external override {}
    function rebalanceStableBorrowRate(address, address) external override {}
    function setUserUseReserveAsCollateral(address, bool) external override {}
    function liquidationCall(address, address, address, uint256, bool) external override {}
    function flashLoan(
        address,
        address[] calldata,
        uint256[] calldata,
        uint256[] calldata,
        address,
        bytes calldata,
        uint16
    ) external override {}

    function getUserAccountData(address)
        external
        view
        override
        returns (uint256, uint256, uint256, uint256, uint256, uint256)
    {
        return (0, 0, 0, 0, 0, 0);
    }

    function dropReserve(address) external override {}
    function setReserveInterestRateStrategyAddress(address, address) external override {}
    function setConfiguration(address, ReserveConfigurationMap calldata) external override {}

    function getConfiguration(address) external view override returns (ReserveConfigurationMap memory) {
        return ReserveConfigurationMap({data: 0});
    }

    function getReserveNormalizedIncome(address) external view override returns (uint256) {
        return 0;
    }

    function getReserveNormalizedVariableDebt(address) external view override returns (uint256) {
        return 0;
    }

    function finalizeTransfer(address, address, address, uint256, uint256, uint256) external override {}

    function getReservesList() external view override returns (address[] memory) {
        address[] memory empty;
        return empty;
    }

    function getReserveAddressById(uint16) external view override returns (address) {
        return address(0);
    }

    function ADDRESSES_PROVIDER() external view override returns (address) {
        return address(0);
    }

    function updateBridgeProtocolFee(uint256) external override {}
    function setUserEMode(uint8) external override {}

    function getUserEMode(address) external view override returns (uint256) {
        return 0;
    }

    function resetIsolationModeTotalDebt(address) external override {}

    function MAX_STABLE_RATE_BORROW_SIZE_PERCENT() external view override returns (uint256) {
        return 0;
    }

    function BRIDGE_PROTOCOL_FEE() external view override returns (uint256) {
        return 0;
    }

    function FLASHLOAN_PREMIUM_TO_PROTOCOL() external view override returns (uint128) {
        return FLASHLOAN_PREMIUM_TO_PROTOCOL_CONST;
    }

    function MAX_NUMBER_RESERVES() external view override returns (uint16) {
        return 0;
    }

    function mintToTreasury(address[] calldata) external override {}
    function rescueTokens(address, address, uint256) external override {}
    function deposit(address, uint256, address, uint16) external override {}
}
