// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import {Treasury} from "../src/Treasury.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {console} from "forge-std/console.sol";

contract DeployTreasury is Script {
    // Private key (for Anvil) used for deployments.
    uint256 public DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function run() external returns (address) {
        address deployer;
        address treasuryAddress = vm.envAddress("TREASURY_ADDRESS");
        if (treasuryAddress == address(0)) {
            revert("TREASURY_ADDRESS is not set");
        }
        if (block.chainid == 31337) {
            uint256 deployerKey = DEFAULT_ANVIL_PRIVATE_KEY;
            deployer = vm.addr(deployerKey);
        } else {
            string memory pkString = vm.envString("PRIVATE_KEY");
            uint256 deployerKey = vm.parseUint(pkString);
            deployer = vm.addr(deployerKey);
        }
        vm.startBroadcast(deployer);
        // Deploy Treasury behind a UUPS proxy.
        address proxy = Upgrades.deployUUPSProxy(
            "Treasury.sol", abi.encodeCall(Treasury.initialize, (treasuryAddress))
        );
        console.log("Treasury deployed at:", proxy);
        // Set TREASURY_ADDRESS accordingly.
        return proxy;
    }
}
