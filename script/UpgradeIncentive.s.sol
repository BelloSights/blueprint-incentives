// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Incentive} from "../src/Incentive.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract UpgradeIncentive is Script {
    uint256 public DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 public deployerKey;

    function run() public {
        address proxyAddr = getProxyAddress();
        address admin = getAdminAddress();
        upgradeCube(admin, proxyAddr);
    }

    function getProxyAddress() internal view returns (address) {
        if (block.chainid == 31337) {
            return abi.decode(
                vm.parseJson(
                    vm.readFile("broadcast/DeployProxy.s.sol/31337/run-latest.json"),
                    ".transactions[0].contractAddress"
                ),
                (address)
            );
        }
        return vm.envAddress("INCENTIVE_PROXY_ADDRESS");
    }

    function getAdminAddress() internal view returns (address) {
        if (block.chainid == 31337) {
            return vm.addr(DEFAULT_ANVIL_PRIVATE_KEY);
        }
        return vm.envAddress("DEPLOYER_ADDRESS");
    }

    function upgradeCube(address _admin, address _proxyAddress) public {
        console.log("admin ", _admin);
        vm.startBroadcast(_admin);
        Options memory opts;
        opts.unsafeSkipStorageCheck = block.chainid == 31337; // Only skip on Anvil
        Upgrades.upgradeProxy(_proxyAddress, "Incentive.sol", new bytes(0), opts);
        vm.stopBroadcast();
    }
}
