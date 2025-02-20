// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {Incentive} from "../src/Incentive.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeployProxy is Script {
    // Private key (for Anvil) used for deployments.
    uint256 public DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 public deployerKey;

    string public SIGNATURE_DOMAIN;
    string public SIGNING_VERSION;
    address public TREASURY;

    constructor() {
        SIGNATURE_DOMAIN = vm.envString("SIGNATURE_DOMAIN");
        SIGNING_VERSION = vm.envString("SIGNING_VERSION");
        TREASURY = vm.envAddress("TREASURY_ADDRESS");
    }

    function run() external returns (address) {
        if (block.chainid == 31337) {
            deployerKey = DEFAULT_ANVIL_PRIVATE_KEY;
        } else {
            string memory pkString = vm.envString("PRIVATE_KEY");
            deployerKey = vm.parseUint(pkString);
        }
        address proxy = deployProxy(vm.addr(deployerKey));
        return proxy;
    }

    function deployProxy(address _admin) public returns (address) {
        vm.startBroadcast(_admin);
        Options memory opts;
        opts.unsafeSkipStorageCheck = block.chainid == 31337; // Only skip on Anvil
        address proxy = Upgrades.deployUUPSProxy(
            "Incentive.sol",
            abi.encodeCall(Incentive.initialize, (SIGNATURE_DOMAIN, SIGNING_VERSION, _admin, TREASURY)),
            opts
        );
        vm.stopBroadcast();
        return address(proxy);
    }
}
