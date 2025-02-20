// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {BlueprintToken} from "../src/BlueprintToken.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/// @notice Deployment script for BlueprintToken proxy using UUPS upgradeability.
/// For production, the TREASURY_ADDRESS is read directly from the environment.
contract DeployToken is Script {
    // Private key (for Anvil) used for deployments.
    uint256 public DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function deployProxy() public returns (address) {
        // Use the private key from the environment to broadcast transactions.
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

        // Set treasury address:
        // On a local/test network (chainid 31337) default to the deployer (ALICE)
        // Otherwise, read treasury address from environment variables.
        address treasuryAddress;
        if (block.chainid == 31337) {
            treasuryAddress = deployer;
        } else {
            treasuryAddress = vm.envAddress("TREASURY_ADDRESS");
            if (treasuryAddress == address(0)) {
                revert("TREASURY_ADDRESS is not set");
            }
        }

        // Deploy a UUPS proxy for BlueprintToken, initializing it with treasuryAddress.
        address proxy = Upgrades.deployUUPSProxy(
            "BlueprintToken.sol", abi.encodeCall(BlueprintToken.initialize, (treasuryAddress))
        );
        vm.stopBroadcast();
        return proxy;
    }

    function run() external returns (address) {
        // Deploy the proxy and log the deployed proxy address.
        address proxy = deployProxy();
        console.log("BlueprintToken proxy deployed at:", proxy);
        return proxy;
    }
}
