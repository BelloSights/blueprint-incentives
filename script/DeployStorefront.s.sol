// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {BlueprintStorefront} from "../src/BlueprintStorefront.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeployStorefront is Script {
    // Private key (for Anvil) used for deployments.
    uint256 public DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function run() external returns (address) {
        // Get the deployer address from environment variables and broadcast.
        address deployer;
        if (block.chainid == 31337) {
            uint256 deployerKey = DEFAULT_ANVIL_PRIVATE_KEY;
            deployer = vm.addr(deployerKey);
        } else {
            string memory pkString = vm.envString("PRIVATE_KEY");
            uint256 deployerKey = vm.parseUint(pkString);
            deployer = vm.addr(deployerKey);
        }
        vm.startBroadcast(deployer);
        // Deploy the proxy with admin initialization only.
        address proxy = Upgrades.deployUUPSProxy(
            "BlueprintStorefront.sol",
            abi.encodeWithSelector(BlueprintStorefront.initialize.selector, deployer)
        );
        console.log("BlueprintStorefront deployed at:", proxy);

        // Configure additional parameters using environment variables.
        address paymentToken = vm.envAddress("BLUEPRINT_TOKEN_ADDRESS");
        uint256 buybackBps = vm.envUint("TREASURY_BPS");
        uint256 creatorBps = vm.envUint("CREATOR_BPS");
        uint256 blueprintBps = vm.envUint("BLUEPRINT_BPS");
        address buybackWallet = vm.envAddress("TREASURY_ADDRESS");
        address creatorWallet = vm.envAddress("CREATOR_ADDRESS");
        address blueprintWallet = vm.envAddress("BLUEPRINT_ADDRESS");
        if (paymentToken == address(0)) {
            revert("BLUEPRINT_TOKEN_ADDRESS is not set");
        }
        if (buybackBps == 0) {
            revert("TREASURY_BPS is not set");
        }
        if (creatorBps == 0) {
            revert("CREATOR_BPS is not set");
        }
        if (blueprintBps == 0) {
            revert("BLUEPRINT_BPS is not set");
        }
        if (buybackWallet == address(0)) {
            revert("TREASURY_ADDRESS is not set");
        }
        if (creatorWallet == address(0)) {
            revert("CREATOR_ADDRESS is not set");
        }
        if (blueprintWallet == address(0)) {
            revert("BLUEPRINT_ADDRESS is not set");
        }
        BlueprintStorefront(proxy).setPaymentToken(paymentToken);
        BlueprintStorefront(proxy).updateSplits(buybackBps, creatorBps, blueprintBps);
        BlueprintStorefront(proxy).setBuybackWallet(buybackWallet);
        BlueprintStorefront(proxy).setCreatorWallet(creatorWallet);
        BlueprintStorefront(proxy).setBlueprintWallet(blueprintWallet);

        console.log("Configuration set:");
        console.log(" PaymentToken:", paymentToken);
        console.log(" BuybackBps:", buybackBps);
        console.log(" CreatorBps:", creatorBps);
        console.log(" BlueprintBps:", blueprintBps);
        console.log(" BuybackWallet:", buybackWallet);
        console.log(" CreatorWallet:", creatorWallet);
        console.log(" BlueprintWallet:", blueprintWallet);
        return proxy;
    }
}
