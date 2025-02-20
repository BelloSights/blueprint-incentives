// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";

import {Factory} from "../src/escrow/Factory.sol";
import {IFactory} from "../src/escrow/interfaces/IFactory.sol";
import {MockERC20} from "../test/mock/MockERC20.sol";
import {MockERC721} from "../test/mock/MockERC721.sol";
import {MockERC1155} from "../test/mock/MockERC1155.sol";

import {Incentive} from "../src/Incentive.sol";

import {IERC20} from "@openzeppelin-contracts/interfaces/IERC20.sol";
import {IERC721} from "@openzeppelin-contracts/interfaces/IERC721.sol";
import {IERC1155} from "@openzeppelin-contracts/interfaces/IERC1155.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeployEscrow is Script {
    // private key is the same for everyone
    uint256 public DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 public deployerKey;

    uint256 public constant QUEST_ID = 1;

    Factory public factoryContract;
    address erc20Mock;
    address erc721Mock;
    address erc1155Mock;

    function deploy() external returns (address, address) {
        // Get the deployer address from environment variables and broadcast.
        address deployer;
        if (block.chainid == 31337) {
            deployerKey = DEFAULT_ANVIL_PRIVATE_KEY;
            deployer = vm.addr(deployerKey);
        } else {
            string memory pkString = vm.envString("PRIVATE_KEY");
            deployerKey = vm.parseUint(pkString);
            deployer = vm.addr(deployerKey);
        }

        address treasury = vm.envAddress("TREASURY_ADDRESS");
        if (treasury == address(0)) {
            revert("Treasury address is required");
        }
        address incentive = vm.envAddress("INCENTIVE_PROXY_ADDRESS");
        if (incentive == address(0)) {
            revert("Incentive address is required");
        }
        // address blueprintToken = vm.envAddress("BLUEPRINT_TOKEN_ADDRESS");
        // if (blueprintToken == address(0)) {
        //     revert("Blueprint token address is required");
        // }

        address factory = deployFactory(deployer, incentive);
        factoryContract = Factory(factory);

        address[] memory whitelistedTokens = new address[](0);
        // whitelistedTokens[0] = blueprintToken;

        vm.startBroadcast(deployer);
        uint256 registeredQuest = factoryContract.s_questToEscrow(QUEST_ID);
        if (registeredQuest == 0) {
            uint256 escrowId = factoryContract.createEscrow(deployer, whitelistedTokens, treasury);
            factoryContract.registerQuest(QUEST_ID, escrowId);
        } else {
            console.log("DeployEscrow: Quest", QUEST_ID, "already registered.");
        }
        vm.stopBroadcast();

        // Now that the quest is registered, get the escrow address
        address escrow = factoryContract.getEscrow(QUEST_ID);

        return (factory, escrow);
    }

    function run(address admin, address treasury, address incentive)
        external
        returns (address, address, address, address, address)
    {
        // deploy NFT contracts and set factory address
        deployTokenContracts(admin);

        address factory = deployFactory(admin, incentive);
        factoryContract = Factory(factory);

        address[] memory whitelistedTokens = new address[](3);
        whitelistedTokens[0] = erc20Mock;
        whitelistedTokens[1] = erc721Mock;
        whitelistedTokens[2] = erc1155Mock;

        vm.startBroadcast(admin);
        uint256 registeredQuest = factoryContract.s_questToEscrow(QUEST_ID);
        if (registeredQuest == 0) {
            uint256 escrowId = factoryContract.createEscrow(admin, whitelistedTokens, treasury);
            factoryContract.registerQuest(QUEST_ID, escrowId);
        } else {
            console.log("DeployEscrow: Quest", QUEST_ID, "already registered.");
        }
        vm.stopBroadcast();

        // Now that the quest is registered, get the escrow address
        address escrow = factoryContract.getEscrow(QUEST_ID);

        return (factory, escrow, erc20Mock, erc721Mock, erc1155Mock);
    }

    function deployTokenContracts(address admin) public {
        address erc20 = deployERC20Mock(admin);
        address erc721 = deployERC721Mock(admin);
        address erc1155 = deployERC1155Mock(admin);

        erc20Mock = erc20;
        erc721Mock = erc721;
        erc1155Mock = erc1155;
    }

    function deployFactory(address _admin, address incentive) public returns (address) {
        vm.startBroadcast(_admin);
        Options memory opts;
        opts.constructorData = abi.encode(Incentive(incentive));
        opts.unsafeSkipStorageCheck = block.chainid == 31337; // Only skip on Anvil
        address proxy = Upgrades.deployUUPSProxy(
            "Factory.sol", abi.encodeCall(Factory.initialize, (_admin)), opts
        );
        vm.stopBroadcast();
        return proxy;
    }

    function depositToFactory(address depositor, uint256 amount) public {
        vm.startBroadcast(depositor);
        address escrowAddr = factoryContract.getEscrow(QUEST_ID);
        IERC20(erc20Mock).transfer(escrowAddr, amount);
        vm.stopBroadcast();
    }

    function deployERC20Mock(address _admin) public returns (address) {
        vm.startBroadcast(_admin);
        MockERC20 erc20 = new MockERC20();
        erc20.mint(_admin, 20e18);
        vm.stopBroadcast();
        return address(erc20);
    }

    function deployERC721Mock(address _admin) public returns (address) {
        vm.startBroadcast(_admin);
        MockERC721 erc721 = new MockERC721();

        erc721.mint(_admin);
        erc721.mint(_admin);
        erc721.mint(_admin);

        vm.stopBroadcast();
        return address(erc721);
    }

    function deployERC1155Mock(address _admin) public returns (address) {
        vm.startBroadcast(_admin);
        MockERC1155 erc1155 = new MockERC1155();
        erc1155.mint(_admin, 100, 0);

        vm.stopBroadcast();
        return address(erc1155);
    }
}
