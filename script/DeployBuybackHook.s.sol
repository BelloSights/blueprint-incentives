// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {Constants} from "./base/Constants.sol";
import {BuybackHook} from "../src/uniswap/BuybackHook.sol";
import {HookMiner} from "../test/utils/HookMiner.sol";

/// @notice Mines the address and deploys the BuybackHook contract via CREATE2.
contract DeployBuybackHookScript is Script, Constants {
    function setUp() public {}

    function run() public {
        // Hook contracts must have specific flags encoded in the address.
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_DONATE_FLAG);

        // Mine a salt that will produce a hook address with the correct flags.
        // Pass the 5 constructor arguments: POOLMANAGER, BLUEPRINT_TOKEN, POSITION_MANAGER, and tick bounds.
        bytes memory constructorArgs = abi.encode(
            POOLMANAGER,
            address(BLUEPRINT_TOKEN),
            address(POSITION_MANAGER),
            int24(-600),
            int24(600)
        );
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(BuybackHook).creationCode, constructorArgs);

        // Deploy the hook using CREATE2.
        vm.broadcast();
        BuybackHook buybackHook = new BuybackHook{salt: salt}(POOLMANAGER);
        require(
            address(buybackHook) == hookAddress, "DeployBuybackHookScript: hook address mismatch"
        );
    }
}
