// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {DeployProxy} from "../../script/DeployProxy.s.sol";
import {UpgradeIncentive} from "../../script/UpgradeIncentive.s.sol";
import {Incentive} from "../../src/Incentive.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployAndUpgradeTest is StdCheats, Test {
    DeployProxy public deployProxy;
    UpgradeIncentive public upgradeCube;
    address public OWNER = address(1);
    address public ALICE = address(2);
    address public BOB = address(3);
    address public TREASURY = address(4);

    // This address is set by our deploy script.
    address public proxyAddress;

    function setUp() public {
        deployProxy = new DeployProxy();
        upgradeCube = new UpgradeIncentive();
        proxyAddress = deployProxy.deployProxy(OWNER);

        // Grant UPGRADER role to OWNER.
        vm.startBroadcast(OWNER);
        Incentive(payable(proxyAddress)).grantRole(keccak256("UPGRADER"), OWNER);
        vm.stopBroadcast();
    }

    function testUnauthorizedUpgrade() public {
        bytes4 selector = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));
        bytes memory expectedError = abi.encodeWithSelector(selector, BOB, keccak256("UPGRADER"));
        vm.expectRevert(expectedError);
        upgradeCube.upgradeCube(BOB, proxyAddress);
    }

    function testV2SignerRoleVariable() public {
        upgradeCube.upgradeCube(OWNER, proxyAddress);
        Incentive newCube = Incentive(payable(proxyAddress));
        bytes32 signerRole = newCube.SIGNER_ROLE();
        assertEq(keccak256("SIGNER"), signerRole);
    }
}
