<p align="center">
  <br>
  <a href="https://bp.fun" target="_blank">
    <img width="300" height="100" src="./assets/blueprint.png" alt="Blueprint Logo">
  </a>
  <br><br>
</p>

[![Twitter](https://img.shields.io/twitter/follow/bpdotfun?color=blue&style=flat-square)](https://twitter.com/bpdotfun)
[![LICENSE](https://img.shields.io/badge/license-Apache--2.0-blue?logo=apache)](./LICENSE)

# BP.FUN Contracts

This repository contains a suite of upgradeable smart contracts that power the Blueprint ecosystem. The contracts include:

- **Incentive** – A reward claim contract that uses EIP‑712 signatures to verify reward claims, enforce a daily reward cap, and trigger reward distribution via a factory.
- **BlueprintERC1155Factory** – A factory contract for deploying and managing ERC1155 NFT collections, enabling NFT drops with configurable fees and royalties.

---

## Table of Contents

- [Overview](#overview)
- [Smart Contract Details](#smart-contract-details)
  - [Incentive](#incentive)
  - [BlueprintERC1155Factory](#blueprinterc1155factory)
- [Setup and Installation](#setup-and-installation)
- [Deployment](#deployment)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Overview

Blueprint's smart contract suite enables reward claims and NFT collections management. The reward claim process is a fork of Layer3's [CUBE](https://github.com/layer3xyz/cubes) contract for reward distribution. The contracts are built with upgradeability (UUPS pattern) and leverage OpenZeppelin's upgradeable libraries for security and reliability.

---

## Smart Contract Details

### Incentive

- **Purpose:**  
  Processes reward claims by verifying EIP‑712–signed claim data and enforcing a 24-hour cooldown per quest.
- **Key Features:**
  - Verifies signature over a `IncentiveData` struct.
  - Emits events for quest initialization, transaction logging, and reward distribution.
  - Integrates with an escrow factory for reward distribution.
- **File:** [Incentive.sol](./src/Incentive.sol)

---

### BlueprintERC1155Factory

- **Purpose:**  
  Factory contract for deploying and managing BlueprintERC1155 collection clones with NFT drop functionality.
- **Key Features:**
  - Uses OpenZeppelin's Clones library for gas-efficient deployment.
  - Configurable fee structure for platform fees and creator royalties.
  - Admin controls for collection and drop management.
  - Supports creating and managing drops with start/end times.
  - Access control for admin and creator roles.
- **File:** [BlueprintERC1155Factory.sol](./src/nft/BlueprintERC1155Factory.sol)

---

## Setup and Installation

Ensure you have [Foundry](https://book.getfoundry.sh) installed and updated:

```bash
foundryup
```

## Install

```bash
make install
```

Build the contracts:

```bash
make build
```

---

## Deployment

The contracts are designed for upgradeability and can be deployed using Forge scripts.

```bash
make deploy_proxy ARGS="--network base_sepolia"
make deploy_escrow ARGS="--network base_sepolia"
```

### Verification

For proxy contracts, use this command after deployment (replace addresses with your values):

```bash
forge verify-contract $FACTORY_PROXY_ADDRESS \
  --chain-id 84532 \
  --etherscan-api-key $BASESCAN_API_KEY \
  --constructor-args $(cast abi-encode "constructor(address,bytes)" $FACTORY_IMPLEMENTATION_ADDRESS 0x$(cast sig "initialize(address)" | cut -c3-)$(cast abi-encode "x(address)" $TREASURY_ADDRESS | cut -c3-)) \
  --rpc-url $BASE_SEPOLIA_RPC \
  "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy" \
  --watch
```

Example initialization calldata generation:

```bash
echo "0x$(cast sig "initialize(address)" | cut -c3-)$(cast abi-encode "x(address)" $TREASURY_ADDRESS | cut -c3-)"
```

For local development with Anvil:

```bash
anvil
```

In a new terminal, run:

```bash
forge script script/Anvil.s.sol --rpc-url http://localhost:8545 --private-key <ANVIL_PRIVATE_KEY> --broadcast --via-ir
```

---

## Testing

Run the complete test suite with:

```bash
make test
```

Or directly with Forge:

```bash
forge install
forge test
```

---

## SDK

To generate the SDK ABIs, run the following commands:

```bash
jq '.abi' out/Incentive.sol/Incentive.json > sdk/abis/incentiveAbi.json
jq '.abi' out/Escrow.sol/Escrow.json > sdk/abis/escrowAbi.json
jq '.abi' out/Factory.sol/Factory.json > sdk/abis/factoryAbi.json
jq '.abi' out/BlueprintERC1155Factory.sol/BlueprintERC1155Factory.json > sdk/abis/blueprintERC1155FactoryAbi.json
jq '.abi' out/BlueprintERC1155.sol/BlueprintERC1155.json > sdk/abis/blueprintERC1155Abi.json
```

## Troubleshooting

- **Foundry Installation Issues:**  
  If you encounter "Permission Denied" errors during `forge install`, ensure your GitHub SSH keys are correctly added. Refer to [GitHub SSH documentation](https://docs.github.com/en/authentication/connecting-to-github-with-ssh).

- **Deployment Failures:**  
  Ensure that the correct flags and salt values are used (especially for CREATE2 deployments) and verify that your deployer address matches the expected CREATE2 proxy address if applicable.

---

## License

This repository is released under the [Apache 2.0 License](./LICENSE). Some files (such as tests and scripts) may be licensed under MIT.
