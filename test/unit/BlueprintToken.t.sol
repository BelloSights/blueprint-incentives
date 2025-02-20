// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console, Vm} from "forge-std/Test.sol";
import {BlueprintToken} from "../../src/BlueprintToken.sol";
import {DeployToken} from "../../script/DeployToken.s.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract BPTokenTest is Test {
    BlueprintToken public blueprintToken;

    uint256 internal ownerPrivateKey;
    address internal ownerPubKey;

    DeployToken public deployer;

    // Test Users
    uint256 public DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address public ALICE = vm.addr(DEFAULT_ANVIL_PRIVATE_KEY);
    address public BOB = makeAddr("bob");

    address public adminAddress;
    uint256 internal adminPrivateKey;

    address public proxyAddress;

    function setUp() public {
        deployer = new DeployToken();
        proxyAddress = deployer.deployProxy();
        blueprintToken = BlueprintToken(payable(proxyAddress));
    }

    function testInitialSupply() public view {
        assertEq(blueprintToken.totalSupply(), 10_000_000_000 * 10 ** 18);
    }

    function testOwner() public view {
        assertEq(blueprintToken.owner(), ALICE);
    }

    function testChangeOwner() public {
        vm.prank(ALICE);
        blueprintToken.transferOwnership(BOB);

        vm.prank(BOB);
        blueprintToken.acceptOwnership();
        assertEq(blueprintToken.owner(), BOB);
    }

    function testTransfer() public {
        vm.prank(ALICE);
        blueprintToken.transfer(BOB, 100);
        assertEq(blueprintToken.balanceOf(BOB), 100);
    }

    function testBurn() public {
        uint256 initialBalance = blueprintToken.balanceOf(ALICE);
        vm.prank(ALICE);
        uint256 burnAmount = 100;
        blueprintToken.burn(burnAmount);

        assertEq(blueprintToken.balanceOf(ALICE), initialBalance - burnAmount);
    }

    function testBurnWithAllowance() public {
        uint256 initialBalance = blueprintToken.balanceOf(ALICE);
        uint256 burnAmount = 50;

        vm.prank(ALICE);
        blueprintToken.approve(BOB, burnAmount);

        vm.prank(BOB);
        blueprintToken.burnFrom(ALICE, burnAmount);

        assertEq(blueprintToken.balanceOf(ALICE), initialBalance - burnAmount);
    }
}
