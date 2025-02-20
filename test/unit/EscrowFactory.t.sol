// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

error AccessControlUnauthorizedAccount(address account, bytes32 requiredRole);

import {DeployProxy} from "../../script/DeployProxy.s.sol";
import {DeployEscrow} from "../../script/DeployEscrow.s.sol";
import {Incentive} from "../../src/Incentive.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {MockERC721} from "../mock/MockERC721.sol";
import {MockERC1155} from "../mock/MockERC1155.sol";
import {Test, console, Vm} from "forge-std/Test.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {Escrow} from "../../src/escrow/Escrow.sol";
import {Factory} from "../../src/escrow/Factory.sol";
import {ITokenType} from "../../src/escrow/interfaces/ITokenType.sol";

contract EscrowFactoryTest is Test {
    DeployEscrow public deployer;
    Factory public factoryContract;

    string constant SIGNATURE_DOMAIN = "BLUEPRINT";
    string constant SIGNING_VERSION = "1";

    uint256 internal ownerPrivateKey;
    address internal ownerPubKey;

    address internal realAccount;
    uint256 internal realPrivateKey;

    // Test Users
    address public adminAddress;
    address public ADMIN = makeAddr("admin");
    uint256 internal adminPrivateKey;
    address public ALICE = makeAddr("alice");
    address public BOB = makeAddr("bob");

    address public notAdminAddress;
    uint256 internal notAdminPrivKey;

    address public proxyAddress;
    DeployProxy public proxyDeployer;
    Incentive public incentiveContract;

    address public factoryAddr;
    address public escrowAddr;
    Escrow public escrowMock;
    MockERC20 public erc20Mock;
    MockERC721 public erc721Mock;
    MockERC1155 public erc1155Mock;

    address[] public whitelistedTokens;

    address public treasury;
    uint256 public escrowId;

    event EscrowRegistered(
        address indexed registror, address indexed escrowAddress, uint256 indexed questId
    );

    function setUp() public {
        ownerPrivateKey = 0xA11CE;
        ownerPubKey = vm.addr(ownerPrivateKey);

        adminPrivateKey = 0x01;
        adminAddress = vm.addr(adminPrivateKey);

        notAdminPrivKey = 0x099;
        notAdminAddress = vm.addr(notAdminPrivKey);

        treasury = makeAddr("treasury");

        proxyDeployer = new DeployProxy();
        proxyAddress = proxyDeployer.deployProxy(ownerPubKey);
        incentiveContract = Incentive(payable(proxyAddress));

        vm.startBroadcast(ownerPubKey);
        incentiveContract.grantRole(incentiveContract.SIGNER_ROLE(), adminAddress);
        vm.stopBroadcast();

        // deploy all necessary contracts and set up dependencies
        deployer = new DeployEscrow();
        (,, address _erc20Mock, address _erc721Mock, address _erc1155Mock) =
            deployer.run(adminAddress, treasury, address(0));

        whitelistedTokens.push(address(_erc20Mock));
        whitelistedTokens.push(address(_erc721Mock));
        whitelistedTokens.push(address(_erc1155Mock));

        factoryAddr = deployer.deployFactory(adminAddress, proxyAddress);
        factoryContract = Factory(payable(factoryAddr));

        bool hasRole = factoryContract.hasRole(factoryContract.DEFAULT_ADMIN_ROLE(), adminAddress);
        assert(hasRole);

        vm.startPrank(adminAddress);
        escrowId = factoryContract.createEscrow(adminAddress, whitelistedTokens, treasury);
        vm.stopPrank();

        (, escrowAddr,,) = factoryContract.s_escrows(escrowId);
        escrowMock = Escrow(payable(escrowAddr));

        assert(escrowMock.s_whitelistedTokens(_erc20Mock));

        vm.startPrank(adminAddress);
        factoryContract.registerQuest(escrowId, escrowId);
        vm.stopPrank();

        erc20Mock = MockERC20(_erc20Mock);
        erc721Mock = MockERC721(_erc721Mock);
        erc1155Mock = MockERC1155(_erc1155Mock);
    }

    function createEscrow() public returns (uint256) {
        vm.startPrank(adminAddress);
        uint256 newEscrowId =
            factoryContract.createEscrow(adminAddress, whitelistedTokens, treasury);
        vm.stopPrank();
        return newEscrowId;
    }

    function testDepositNative(uint256 amount) public {
        hoax(adminAddress, amount);
        uint256 preBalEscrow = escrowAddr.balance;
        uint256 preBalAdmin = adminAddress.balance;

        (bool success,) = address(escrowAddr).call{value: amount}("");
        require(success, "native deposit failed");

        uint256 postBalEscrow = escrowAddr.balance;
        uint256 postBalAdmin = adminAddress.balance;

        assertEq(postBalEscrow, preBalEscrow + amount);
        assertEq(postBalAdmin, preBalAdmin - amount);
    }

    function testDepositERC20(uint256 amount) public {
        uint256 preBalance = erc20Mock.balanceOf(escrowAddr);

        uint256 preBalanceAdmin = erc20Mock.balanceOf(adminAddress);
        if (amount > preBalanceAdmin) {
            return;
        }

        vm.startBroadcast(adminAddress);

        erc20Mock.transfer(escrowAddr, amount);
        vm.stopBroadcast();

        uint256 postBalance = erc20Mock.balanceOf(escrowAddr);

        assertEq(postBalance, preBalance + amount);
    }

    function testDepositERC721() public {
        uint256 preBalance = erc721Mock.balanceOf(escrowAddr);
        vm.startBroadcast(adminAddress);
        erc721Mock.safeTransferFrom(adminAddress, escrowAddr, 2);
        vm.stopBroadcast();

        uint256 postBalance = erc721Mock.balanceOf(escrowAddr);

        assertEq(postBalance, preBalance + 1);
        assertEq(erc721Mock.ownerOf(2), escrowAddr);
    }

    function testDepositERC1155() public {
        uint256 preBalance = erc1155Mock.balanceOf(escrowAddr, 0);
        vm.startBroadcast(adminAddress);
        erc1155Mock.safeTransferFrom(adminAddress, escrowAddr, 0, 1, "0x00");
        vm.stopBroadcast();

        uint256 postBalance = erc1155Mock.balanceOf(escrowAddr, 0);

        assertEq(postBalance, preBalance + 1);
    }

    function testCreateEscrow(uint256 amount) public {
        vm.prank(adminAddress);
        escrowId = factoryContract.createEscrow(adminAddress, whitelistedTokens, treasury);
        (, address newEscrow,,) = factoryContract.s_escrows(escrowId);

        MockERC20 erc20 = new MockERC20();
        erc20.mint(newEscrow, amount);

        assertEq(Escrow(payable(newEscrow)).escrowERC20Reserves(address(erc20)), amount);
    }

    // test withdrawal
    function testNativeWithdrawalByAdmin(uint256 nativeAmount) public {
        uint256 newEscrowId = createEscrow();

        vm.startPrank(adminAddress);
        incentiveContract.initializeQuest(
            newEscrowId,
            new string[](0),
            "Test Quest",
            Incentive.Difficulty.BEGINNER,
            Incentive.QuestType.QUEST,
            new string[](0)
        );
        factoryContract.registerQuest(newEscrowId, newEscrowId);
        vm.stopPrank();

        nativeAmount = bound(nativeAmount, 0, type(uint256).max);
        testDepositNative(nativeAmount);

        (, address questEscrow,,) = factoryContract.s_escrows(newEscrowId);
        hoax(BOB, nativeAmount);
        (bool success,) = address(questEscrow).call{value: nativeAmount}("");
        require(success, "native deposit failed");

        uint256 balNative = questEscrow.balance;
        assertEq(balNative, nativeAmount);

        vm.startPrank(adminAddress);
        incentiveContract.unpublishQuest(newEscrowId);
        factoryContract.withdrawFunds(
            newEscrowId, ALICE, address(0), 0, ITokenType.TokenType.NATIVE
        );
        vm.stopPrank();

        assertEq(questEscrow.balance, 0);
        assertEq(ALICE.balance, nativeAmount);
    }

    function testErc20WithdrawalByAdmin(uint256 erc20Amount) public {
        vm.startPrank(adminAddress);
        incentiveContract.initializeQuest(
            escrowId,
            new string[](0),
            "Test Quest",
            Incentive.Difficulty.BEGINNER,
            Incentive.QuestType.QUEST,
            new string[](0)
        );
        incentiveContract.unpublishQuest(escrowId);
        vm.stopPrank();
        erc20Amount = bound(erc20Amount, 0, type(uint64).max);
        erc20Mock.mint(escrowAddr, erc20Amount);

        uint256 preBalEscrow = erc20Mock.balanceOf(escrowAddr);
        uint256 balErc20 = escrowMock.escrowERC20Reserves(address(erc20Mock));

        assertEq(preBalEscrow, balErc20);

        vm.prank(adminAddress);
        factoryContract.withdrawFunds(
            escrowId, ALICE, address(erc20Mock), 0, ITokenType.TokenType.ERC20
        );

        uint256 postBalAlice = erc20Mock.balanceOf(ALICE);

        assert(erc20Mock.balanceOf(escrowAddr) == 0);
        assert(escrowMock.escrowERC20Reserves(address(erc20Mock)) == 0);
        assert(postBalAlice == erc20Amount);
    }

    function testErc20WithdrawalByNonAdmin(uint256 erc20Amount) public {
        vm.startPrank(adminAddress);
        incentiveContract.initializeQuest(
            escrowId,
            new string[](0),
            "Test Quest",
            Incentive.Difficulty.BEGINNER,
            Incentive.QuestType.QUEST,
            new string[](0)
        );
        incentiveContract.unpublishQuest(escrowId);
        vm.stopPrank();
        erc20Amount = bound(erc20Amount, 0, type(uint64).max);
        erc20Mock.mint(escrowAddr, erc20Amount);

        vm.prank(ALICE);
        vm.expectRevert();
        factoryContract.withdrawFunds(
            escrowId, ALICE, address(erc20Mock), 0, ITokenType.TokenType.ERC20
        );
    }

    function testChangeEscrowAdminAndWhitelistToken() public {
        vm.startPrank(adminAddress);
        incentiveContract.initializeQuest(
            escrowId,
            new string[](0),
            "Test Quest",
            Incentive.Difficulty.BEGINNER,
            Incentive.QuestType.QUEST,
            new string[](0)
        );
        vm.stopPrank();
        vm.prank(ALICE);
        address tokenToAdd = makeAddr("tokenToAdd");

        // Non-admin (ALICE) attempt should revert
        vm.expectRevert();
        factoryContract.addTokenToWhitelist(escrowId, tokenToAdd);

        // Admin call should succeed
        vm.prank(adminAddress);
        factoryContract.addTokenToWhitelist(escrowId, tokenToAdd);

        bool isWhitelisted = escrowMock.s_whitelistedTokens(tokenToAdd);
        assert(isWhitelisted);
    }

    function testRemoveTokenFromWhitelist() public {
        vm.startPrank(adminAddress);
        incentiveContract.initializeQuest(
            escrowId,
            new string[](0),
            "Test Quest",
            Incentive.Difficulty.BEGINNER,
            Incentive.QuestType.QUEST,
            new string[](0)
        );
        vm.stopPrank();
        bool isWhitelisted = escrowMock.s_whitelistedTokens(address(erc20Mock));
        assert(isWhitelisted);

        vm.prank(adminAddress);
        factoryContract.removeTokenFromWhitelist(escrowId, address(erc20Mock));

        bool isWhitelistedPostRemoval = escrowMock.s_whitelistedTokens(address(erc20Mock));
        assert(!isWhitelistedPostRemoval);
    }

    function testUpdateAdminWithdrawByDefaultAdmin(uint256 erc20Amount) public {
        vm.startPrank(adminAddress);
        incentiveContract.initializeQuest(
            escrowId,
            new string[](0),
            "Test Quest",
            Incentive.Difficulty.BEGINNER,
            Incentive.QuestType.QUEST,
            new string[](0)
        );
        incentiveContract.unpublishQuest(escrowId);
        vm.stopPrank();
        erc20Amount = bound(erc20Amount, 0, type(uint64).max);
        erc20Mock.mint(escrowAddr, erc20Amount);

        vm.prank(ALICE);
        vm.expectRevert();
        factoryContract.withdrawFunds(
            escrowId, ALICE, address(erc20Mock), 0, ITokenType.TokenType.ERC20
        );

        // update admin but withdraw by default admin, which should still work
        vm.startPrank(adminAddress);
        factoryContract.withdrawFunds(
            escrowId, ALICE, address(erc20Mock), 0, ITokenType.TokenType.ERC20
        );
        vm.stopPrank();

        assert(erc20Mock.balanceOf(ALICE) == erc20Amount);
    }

    function testCreateEscrowByNonAdmin() public {
        vm.startBroadcast(ALICE);
        bytes4 selector = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));
        bytes memory expectedError =
            abi.encodeWithSelector(selector, ALICE, factoryContract.DEFAULT_ADMIN_ROLE());
        vm.expectRevert(expectedError);
        factoryContract.createEscrow(ALICE, whitelistedTokens, treasury);
        vm.stopBroadcast();
    }

    function testCreateDoubleEscrow() public {
        // Allow multiple escrows to be created; verify that a new escrowId is successfully created
        vm.startPrank(adminAddress);
        uint256 newEscrowId =
            factoryContract.createEscrow(adminAddress, whitelistedTokens, treasury);
        vm.stopPrank();

        (, address newEscrow,,) = factoryContract.s_escrows(newEscrowId);
        // Assert that the new escrow address is valid (non-zero)
        assert(newEscrow != address(0));

        // create second escrow
        vm.startPrank(adminAddress);
        uint256 newEscrowId2 =
            factoryContract.createEscrow(adminAddress, whitelistedTokens, treasury);
        vm.stopPrank();

        (, address newEscrow2,,) = factoryContract.s_escrows(newEscrowId2);
        assert(newEscrow2 != address(0));
        assert(newEscrow2 != newEscrow);
    }

    function testDistributeRewardsNotCUBE() public {
        vm.startPrank(adminAddress);
        incentiveContract.initializeQuest(
            escrowId,
            new string[](0),
            "Test Quest",
            Incentive.Difficulty.BEGINNER,
            Incentive.QuestType.QUEST,
            new string[](0)
        );
        vm.stopPrank();
        vm.startPrank(adminAddress);
        erc20Mock.mint(escrowAddr, 1e18);
        vm.expectRevert(Factory.Factory__OnlyCallableByIncentive.selector);
        factoryContract.distributeRewards(
            escrowId, address(erc20Mock), BOB, 1e18, 0, ITokenType.TokenType.ERC20, 300
        );
        vm.stopPrank();
    }

    function testRotateAdmin() public {
        bool isAdmin = factoryContract.hasRole(factoryContract.DEFAULT_ADMIN_ROLE(), adminAddress);
        assertEq(isAdmin, true);

        vm.startPrank(adminAddress);
        factoryContract.grantRole(factoryContract.DEFAULT_ADMIN_ROLE(), ALICE);

        bool isAdminAlice = factoryContract.hasRole(factoryContract.DEFAULT_ADMIN_ROLE(), ALICE);
        assertEq(isAdminAlice, true);

        factoryContract.renounceRole(factoryContract.DEFAULT_ADMIN_ROLE(), adminAddress);
        bool isAdminPostRenounce =
            factoryContract.hasRole(factoryContract.DEFAULT_ADMIN_ROLE(), adminAddress);
        assertEq(isAdminPostRenounce, false);
        vm.stopPrank();
    }

    function testDepositERC721ToFactory() public {
        vm.prank(adminAddress);
        bytes4 selector = bytes4(keccak256("ERC721InvalidReceiver(address)"));
        bytes memory expectedError = abi.encodeWithSelector(selector, factoryAddr);
        vm.expectRevert(expectedError);
        IERC721(erc721Mock).safeTransferFrom(adminAddress, factoryAddr, 1);
    }

    function testDepositERC1155ToFactory() public {
        vm.prank(adminAddress);
        bytes4 selector = bytes4(keccak256("ERC1155InvalidReceiver(address)"));
        bytes memory expectedError = abi.encodeWithSelector(selector, factoryAddr);
        vm.expectRevert(expectedError);
        ERC1155(erc1155Mock).safeTransferFrom(adminAddress, factoryAddr, 0, 1, "0x00");
    }

    function testDepositToFactoryWithoutData(uint256 amount) public {
        amount = bound(amount, 0, type(uint256).max);
        hoax(ALICE, amount);
        (bool success,) = factoryAddr.call{value: amount}("");
        assert(!success);
    }

    function testDepositToFactoryWithData(uint256 amount) public {
        amount = bound(amount, 0, type(uint256).max);
        hoax(ALICE, amount);
        (bool success,) = factoryAddr.call{value: amount}("some data");
        assert(!success);
    }
}
