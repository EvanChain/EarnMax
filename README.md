# EarnMax

EarnMax is a leverage and decentralized-exchange (DEX) protocol that enables users to amplify yield by combining Aave V3 borrowing with tradable position tokens. Users can borrow assets (for example, USDC at ~6% from Aave) and deploy them into higher-yielding position tokens (for example, pt-sUSDe at ~14%). By leveraging within the protocol and operating up to allowable LTV limits, the nominal APY can be substantially increased — for example, at a 90% LTV the effective APY could reach roughly 81% in this illustrative scenario. These numbers are examples for illustration only and depend on prevailing borrow rates, token yields, fees, and risk parameters.

A decentralized protocol for trading debt positions and collateral from Aave V3, built with Foundry. EarnMax enables users to migrate their Aave positions into a tradeable format and create orders for swapping collateral and debt tokens.

## Features

- **Aave V3 Integration**: Seamlessly migrate positions from Aave V3 using flash loans
- **Position Trading**: Create tradeable orders for your collateral and debt positions
- **Router System**: Efficient order matching and execution across multiple PIV contracts
- **Flash Loan Support**: Gas-efficient position migration using Aave V3 flash loans
- **Flexible Order Management**: Place, update, and cancel orders with dynamic pricing

## Architecture

- **Router.sol**: Main entry point for deploying PIV contracts and executing swaps
- **PIV.sol**: Position-in-Vault contract that manages individual user positions and orders
- **IPIV.sol**: Interface defining the PIV contract functionality
- **IRouter.sol**: Interface for the router contract

## Smart Contracts

### Router Contract
- Deploys new PIV contracts for users
- Executes multi-order swaps across different PIV contracts
- Handles token transfers and minimum output validation

### PIV Contract
- Leverage positions
- Manages Aave V3 position migration via flash loans
- Handles order placement, updates, and cancellation
- Executes swaps between collateral and debt tokens
- Integrates with Aave V3 Pool for lending operations

## Getting Started

### Prerequisites
- Foundry installed (https://getfoundry.sh/)
- Node with access to an Ethereum-compatible network that has Aave V3 deployed (or use local anvil)

### Installation

```shell
# Clone the repository
git clone <repository-url>
cd EarnMax

# Install/update dependencies defined in foundry.toml
forge update

# Build contracts
forge build
```

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Deploy

Run the deploy script using forge. Add --broadcast to send transactions to the network.

```shell
forge script script/Deploy.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast
```