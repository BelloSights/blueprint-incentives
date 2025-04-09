// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console, Vm} from "forge-std/Test.sol";

import {Incentive} from "../../src/Incentive.sol";
import {Factory} from "../../src/escrow/Factory.sol";
import {Escrow} from "../../src/escrow/Escrow.sol";
import {ITokenType} from "../../src/escrow/interfaces/ITokenType.sol";

import {DeployProxy} from "../../script/DeployProxy.s.sol";
import {DeployEscrow} from "../../script/DeployEscrow.s.sol";
import {Helper} from "../utils/Helper.t.sol";

import {MockERC20} from "../mock/MockERC20.sol";
import {MockERC721} from "../mock/MockERC721.sol";
import {MockERC1155} from "../mock/MockERC1155.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract IncentiveTest is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    /* EVENTS */
    event QuestMetadata(
        uint256 indexed questId,
        Incentive.QuestType questType,
        Incentive.Difficulty difficulty,
        string title,
        string[] tags,
        string[] communities
    );
    event IncentiveTransaction(uint256 indexed cubeTokenId, string txHash, string networkChainId);
    event TokenReward(
        uint256 indexed nonce,
        address indexed tokenAddress,
        uint256 indexed chainId,
        uint256 amount,
        uint256 tokenId,
        ITokenType.TokenType tokenType
    );

    DeployProxy public deployer;
    Incentive public incentiveContract;

    string constant SIGNATURE_DOMAIN = "BLUEPRINT";
    string constant SIGNING_VERSION = "1";

    Helper internal helper;

    uint256 internal ownerPrivateKey;
    address internal ownerPubKey;

    address internal realAccount;
    uint256 internal realPrivateKey;

    DeployEscrow public deployEscrow;
    Factory public factoryContract;
    Escrow public mockEscrow;
    MockERC20 public erc20Mock;
    MockERC721 public erc721Mock;
    MockERC1155 public erc1155Mock;

    // Test Users
    address public adminAddress;
    address public ADMIN = makeAddr("admin");
    uint256 internal adminPrivateKey;
    address public ALICE = makeAddr("alice");
    address public BOB = makeAddr("bob");
    address public TREASURY = makeAddr("treasury");

    address public notAdminAddress;
    uint256 internal notAdminPrivKey;

    address public proxyAddress;

    function getDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(SIGNATURE_DOMAIN)),
                keccak256(bytes(SIGNING_VERSION)),
                block.chainid,
                proxyAddress
            )
        );
    }

    function setUp() public {
        ownerPrivateKey = 0xA11CE;
        ownerPubKey = vm.addr(ownerPrivateKey);

        adminPrivateKey = 0x01;
        adminAddress = vm.addr(adminPrivateKey);

        notAdminPrivKey = 0x099;
        notAdminAddress = vm.addr(notAdminPrivKey);

        deployer = new DeployProxy();
        proxyAddress = deployer.deployProxy(ownerPubKey);
        incentiveContract = Incentive(payable(proxyAddress));

        vm.startBroadcast(ownerPubKey);
        incentiveContract.grantRole(incentiveContract.SIGNER_ROLE(), adminAddress);
        vm.stopBroadcast();

        deployEscrow = new DeployEscrow();
        (
            address factory,
            address escrow,
            address erc20Addr,
            address erc721Addr,
            address erc1155Addr
        ) = deployEscrow.run(adminAddress, TREASURY, proxyAddress);

        mockEscrow = Escrow(payable(escrow));
        erc20Mock = MockERC20(erc20Addr);
        erc721Mock = MockERC721(erc721Addr);
        erc1155Mock = MockERC1155(erc1155Addr);

        factoryContract = Factory(factory);

        vm.startPrank(adminAddress);
        incentiveContract.initializeQuest(
            deployEscrow.QUEST_ID(),
            new string[](0),
            "Quest Title",
            Incentive.Difficulty.BEGINNER,
            Incentive.QuestType.QUEST,
            new string[](0)
        );

        vm.deal(adminAddress, 100 ether);
        fundEscrowContract();

        helper = new Helper();

        vm.stopPrank();
        vm.warp(86400);

        vm.startPrank(ownerPubKey);
        incentiveContract.setTreasury(TREASURY);
        vm.stopPrank();
    }

    function _mintIncentive() internal {
        Incentive.IncentiveData memory _data = helper.getIncentiveData(
            makeAddr("mintTo"),
            address(factoryContract),
            address(erc20Mock),
            0,
            10,
            ITokenType.TokenType.ERC20,
            0,
            137
        );
        _data.nonce = 0;

        bytes32 structHash = helper.getStructHash(_data);
        bytes32 digest = helper.getDigest(getDomainSeparator(), structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        hoax(adminAddress);
        incentiveContract.claimReward(_data, signature);
    }

    function testWithdrawFundsWhenQuestInactive() public {
        vm.startPrank(adminAddress);

        erc20Mock.transfer(address(mockEscrow), 100);

        bool isQuestActive = incentiveContract.isQuestActive(1);
        assert(isQuestActive == true);

        vm.expectRevert(Factory.Factory__IncentiveQuestIsActive.selector);
        factoryContract.withdrawFunds(1, ALICE, address(erc20Mock), 0, ITokenType.TokenType.ERC20);

        uint256 escrowBalanceBefore = erc20Mock.balanceOf(address(mockEscrow));

        incentiveContract.unpublishQuest(1);
        bool isQuestActive2 = incentiveContract.isQuestActive(1);
        assert(isQuestActive2 == false);

        factoryContract.withdrawFunds(1, BOB, address(erc20Mock), 0, ITokenType.TokenType.ERC20);
        vm.stopPrank();

        assert(erc20Mock.balanceOf(BOB) == escrowBalanceBefore);
    }

    function testInitializeQuest() public {
        uint256 questId = 1;
        string[] memory communities = new string[](2);
        communities[0] = "Community1";
        communities[1] = "Community2";
        string memory title = "Quest Title";
        Incentive.Difficulty difficulty = Incentive.Difficulty.BEGINNER;
        Incentive.QuestType questType = Incentive.QuestType.QUEST;
        string[] memory tags = new string[](1);
        tags[0] = "DeFi";

        vm.expectEmit(true, true, false, true);
        emit QuestMetadata(questId, questType, difficulty, title, tags, communities);

        vm.prank(adminAddress);
        incentiveContract.initializeQuest(questId, communities, title, difficulty, questType, tags);
    }

    function testInitializeQuestNotAsSigner() public {
        uint256 questId = 1;
        string[] memory communities = new string[](2);
        communities[0] = "Community1";
        communities[1] = "Community2";
        string memory title = "Quest Title";
        Incentive.Difficulty difficulty = Incentive.Difficulty.BEGINNER;
        Incentive.QuestType questType = Incentive.QuestType.QUEST;
        string[] memory tags = new string[](1);
        tags[0] = "DeFi";

        bytes4 selector = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));
        bytes memory expectedError = abi.encodeWithSelector(selector, ALICE, keccak256("SIGNER"));
        vm.expectRevert(expectedError);
        vm.prank(ALICE);
        incentiveContract.initializeQuest(questId, communities, title, difficulty, questType, tags);
    }

    function fundEscrowContract() internal {
        uint256 amount = 100 ether;
        (bool success,) = address(mockEscrow).call{value: amount}("");
        require(success, "native deposit failed");

        erc721Mock.safeTransferFrom(adminAddress, address(mockEscrow), 2);

        uint256 erc20Amount = 10e18;
        erc20Mock.mint(address(mockEscrow), erc20Amount);

        erc1155Mock.mint(address(mockEscrow), 1e18, 0);
        erc1155Mock.mint(address(adminAddress), 1e18, 0);
    }

    function _getCustomSignedIncentiveMintData(
        address token,
        uint256 tokenId,
        uint256 amount,
        ITokenType.TokenType tokenType,
        uint256 rakeBps,
        uint256 chainId
    ) internal view returns (Incentive.IncentiveData memory, bytes memory) {
        Incentive.IncentiveData memory _data = helper.getIncentiveData(
            BOB, address(factoryContract), token, tokenId, amount, tokenType, rakeBps, chainId
        );

        bytes32 structHash = helper.getStructHash(_data);
        bytes32 digest = helper.getDigest(getDomainSeparator(), structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        return (_data, signature);
    }

    function _getSignedIncentiveMintData()
        internal
        view
        returns (Incentive.IncentiveData memory, bytes memory)
    {
        Incentive.IncentiveData memory _data = helper.getIncentiveData(
            BOB,
            address(factoryContract),
            address(erc20Mock),
            0,
            100,
            ITokenType.TokenType.ERC20,
            0,
            137
        );

        bytes32 structHash = helper.getStructHash(_data);
        bytes32 digest = helper.getDigest(getDomainSeparator(), structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        return (_data, signature);
    }

    function testClaimRewardNativeReward() public {
        uint256 rake = 300;
        (Incentive.IncentiveData memory incentiveData, bytes memory signature) =
        _getCustomSignedIncentiveMintData(
            address(0), 0, 2 ether, ITokenType.TokenType.NATIVE, rake, 137
        );

        hoax(adminAddress);
        incentiveContract.claimReward(incentiveData, signature);
    }

    function testClaimRewardNoReward() public {
        uint256 rake = 300;
        uint256 amount = 100;
        (Incentive.IncentiveData memory incentiveData, bytes memory signature) =
        _getCustomSignedIncentiveMintData(
            address(erc20Mock), 0, amount, ITokenType.TokenType.ERC20, rake, 0
        );

        hoax(adminAddress);
        incentiveContract.claimReward(incentiveData, signature);

        uint256 bobBal = erc20Mock.balanceOf(BOB);
        assertEq(bobBal, 0);
        assertEq(erc20Mock.balanceOf(TREASURY), 0);
    }

    function testClaimRewardERC20Reward() public {
        uint256 rake = 300;
        uint256 amount = 100;
        (Incentive.IncentiveData memory incentiveData, bytes memory signature) =
        _getCustomSignedIncentiveMintData(
            address(erc20Mock), 0, amount, ITokenType.TokenType.ERC20, rake, 137
        );

        hoax(adminAddress);
        incentiveContract.claimReward(incentiveData, signature);

        uint256 bobBal = erc20Mock.balanceOf(BOB);
        uint256 rakePayout = (amount * rake) / 10_000;
        assertEq(bobBal, amount - rakePayout);
        assertEq(erc20Mock.balanceOf(TREASURY), rakePayout);
    }

    function testClaimRewardERC721Reward() public {
        (Incentive.IncentiveData memory incentiveData, bytes memory signature) =
        _getCustomSignedIncentiveMintData(
            address(erc721Mock), 2, 1, ITokenType.TokenType.ERC721, 1, 137
        );

        hoax(adminAddress);
        incentiveContract.claimReward(incentiveData, signature);

        address ownerOf = erc721Mock.ownerOf(2);
        assertEq(ownerOf, BOB);
    }

    function testClaimRewardERC1155Reward() public {
        (Incentive.IncentiveData memory incentiveData, bytes memory signature) =
        _getCustomSignedIncentiveMintData(
            address(erc1155Mock), 0, 2, ITokenType.TokenType.ERC1155, 0, 137
        );

        bool isSigner = incentiveContract.hasRole(keccak256("SIGNER"), adminAddress);
        assertEq(isSigner, true);

        hoax(adminAddress);
        incentiveContract.claimReward(incentiveData, signature);

        uint256 bobBal = erc1155Mock.balanceOf(BOB, 0);
        assertEq(bobBal, 2);
    }

    function testDepositNativeToEscrow() public {
        uint256 preBalance = address(mockEscrow).balance;

        uint256 amount = 100 ether;
        hoax(adminAddress, amount);
        (bool success,) = address(mockEscrow).call{value: amount}("");
        require(success, "native deposit failed");

        uint256 postBalance = address(mockEscrow).balance;
        assertEq(postBalance, preBalance + amount);
    }

    function testDepositERC20ToEscrow() public {
        uint256 preBalance = erc20Mock.balanceOf(address(mockEscrow));

        uint256 amount = 100;
        vm.prank(adminAddress);
        erc20Mock.transfer(address(mockEscrow), amount);

        uint256 postBalance = erc20Mock.balanceOf(address(mockEscrow));

        assertEq(postBalance, preBalance + amount);
    }

    function testDepositERC1155ToEscrow() public {
        uint256 preBalance = erc1155Mock.balanceOf(address(mockEscrow), 0);

        vm.prank(adminAddress);
        uint256 amount = 100;
        erc1155Mock.safeTransferFrom(address(adminAddress), address(mockEscrow), 0, amount, "0x00");

        uint256 postBalance = erc1155Mock.balanceOf(address(mockEscrow), 0);

        assertEq(postBalance, preBalance + amount);
    }

    function testDepositERC721ToEscrow() public {
        uint256 preBalance = erc721Mock.balanceOf(address(mockEscrow));

        vm.prank(adminAddress);
        erc721Mock.safeTransferFrom(adminAddress, address(mockEscrow), 1);

        uint256 postBalance = erc721Mock.balanceOf(address(mockEscrow));

        assertEq(postBalance, preBalance + 1);
        assertEq(erc721Mock.ownerOf(2), address(mockEscrow));
    }

    function testClaimRewardBasic() public {
        (Incentive.IncentiveData memory incentiveData, bytes memory signature) =
            _getSignedIncentiveMintData();

        bool isSigner = incentiveContract.hasRole(keccak256("SIGNER"), adminAddress);
        assertEq(isSigner, true);

        hoax(adminAddress);
        incentiveContract.claimReward(incentiveData, signature);
    }

    function testClaimRewardEvents() public {
        (Incentive.IncentiveData memory incentiveData, bytes memory signature) =
            _getSignedIncentiveMintData();

        hoax(adminAddress);
        vm.expectEmit(true, true, true, true);
        emit IncentiveTransaction(
            incentiveData.questId,
            incentiveData.transactions[0].txHash,
            incentiveData.transactions[0].networkChainId
        );
        vm.expectEmit(true, true, true, true);
        emit TokenReward(
            incentiveData.nonce,
            incentiveData.reward.tokenAddress,
            incentiveData.reward.chainId,
            incentiveData.reward.amount,
            incentiveData.reward.tokenId,
            incentiveData.reward.tokenType
        );

        incentiveContract.claimReward(incentiveData, signature);
    }

    function testNonceReuse() public {
        Incentive.IncentiveData memory data = helper.getIncentiveData(
            ALICE,
            address(factoryContract),
            address(erc20Mock),
            0,
            100,
            ITokenType.TokenType.ERC20,
            0,
            137
        );
        Incentive.IncentiveData memory data2 = helper.getIncentiveData(
            ALICE,
            address(factoryContract),
            address(erc20Mock),
            0,
            100,
            ITokenType.TokenType.ERC20,
            0,
            137
        );
        data.nonce = 1;
        data2.nonce = 1;

        bytes32 structHash = helper.getStructHash(data);
        bytes32 digest = helper.getDigest(getDomainSeparator(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes32 structHash2 = helper.getStructHash(data2);
        bytes32 digest2 = helper.getDigest(getDomainSeparator(), structHash2);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(adminPrivateKey, digest2);
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);

        hoax(adminAddress);
        incentiveContract.claimReward(data, signature);
        vm.expectRevert(Incentive.Incentive__NonceAlreadyUsed.selector);
        incentiveContract.claimReward(data2, signature2);
    }

    function testIncentiveMintDifferentSigners() public {
        Incentive.IncentiveData memory data = helper.getIncentiveData(
            ALICE,
            address(factoryContract),
            address(erc20Mock),
            0,
            100,
            ITokenType.TokenType.ERC20,
            0,
            137
        );
        Incentive.IncentiveData memory data2 = helper.getIncentiveData(
            ALICE,
            address(factoryContract),
            address(erc20Mock),
            0,
            100,
            ITokenType.TokenType.ERC20,
            0,
            137
        );

        data.nonce = 1;
        data2.nonce = 2;

        bytes32 structHash = helper.getStructHash(data);
        bytes32 digest = helper.getDigest(getDomainSeparator(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes32 structHash2 = helper.getStructHash(data2);
        bytes32 digest2 = helper.getDigest(getDomainSeparator(), structHash2);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(notAdminPrivKey, digest2);
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);

        hoax(adminAddress);
        incentiveContract.claimReward(data, signature);
        vm.expectRevert(Incentive.Incentive__IsNotSigner.selector);
        incentiveContract.claimReward(data2, signature2);
    }

    function testMultipleIncentiveDataMint() public {
        Incentive.IncentiveData memory data = helper.getIncentiveData(
            ALICE,
            address(factoryContract),
            address(erc20Mock),
            0,
            100,
            ITokenType.TokenType.ERC20,
            0,
            137
        );
        Incentive.IncentiveData memory data2 = helper.getIncentiveData(
            ALICE,
            address(factoryContract),
            address(erc20Mock),
            0,
            100,
            ITokenType.TokenType.ERC20,
            0,
            137
        );
        data2.nonce = 32142;

        bytes32 structHash = helper.getStructHash(data);
        bytes32 digest = helper.getDigest(getDomainSeparator(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes32 structHash2 = helper.getStructHash(data2);
        bytes32 digest2 = helper.getDigest(getDomainSeparator(), structHash2);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(adminPrivateKey, digest2);
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);

        hoax(adminAddress);
        incentiveContract.claimReward(data, signature);
        incentiveContract.claimReward(data2, signature2);
    }

    function testEmptySignatureArray() public {
        Incentive.IncentiveData memory data = helper.getIncentiveData(
            ALICE,
            address(factoryContract),
            address(erc20Mock),
            0,
            100,
            ITokenType.TokenType.ERC20,
            0,
            137
        );

        hoax(adminAddress);
        vm.expectRevert();
        incentiveContract.claimReward(data, new bytes(0));
    }

    function testInvalidSignature() public {
        Incentive.IncentiveData memory _data = helper.getIncentiveData(
            ALICE,
            address(factoryContract),
            address(erc20Mock),
            0,
            100,
            ITokenType.TokenType.ERC20,
            0,
            137
        );

        bytes32 structHash = helper.getStructHash(_data);
        bytes32 digest = helper.getDigest(getDomainSeparator(), structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(notAdminPrivKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        hoax(adminAddress);
        vm.expectRevert(Incentive.Incentive__IsNotSigner.selector);
        incentiveContract.claimReward(_data, signature);
    }

    function testEmptyIncentiveDataTxs() public {
        Incentive.IncentiveData memory data = helper.getIncentiveData(
            ALICE,
            address(factoryContract),
            address(erc20Mock),
            0,
            100,
            ITokenType.TokenType.ERC20,
            0,
            137
        );
        data.transactions = new Incentive.TransactionData[](1);

        bytes32 structHash = helper.getStructHash(data);
        bytes32 digest = helper.getDigest(getDomainSeparator(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        hoax(adminAddress);
        incentiveContract.claimReward(data, signature);
    }

    function testUnpublishQuest(uint256 questId) public {
        vm.startPrank(adminAddress);
        incentiveContract.initializeQuest(
            questId,
            new string[](0),
            "",
            Incentive.Difficulty.BEGINNER,
            Incentive.QuestType.QUEST,
            new string[](0)
        );
        bool isActive = incentiveContract.isQuestActive(questId);
        assertEq(isActive, true);

        incentiveContract.unpublishQuest(questId);

        vm.stopPrank();
        bool isActive2 = incentiveContract.isQuestActive(questId);
        assert(isActive2 == false);
    }

    function testInitalizeQuestEvent() public {
        uint256 questId = 123;
        string[] memory communities = new string[](1);
        communities[0] = "Community1";
        string memory title = "Quest Title";
        string[] memory tags = new string[](1);
        tags[0] = "NFTs";
        Incentive.Difficulty difficulty = Incentive.Difficulty.BEGINNER;
        Incentive.QuestType questType = Incentive.QuestType.QUEST;

        vm.recordLogs();
        emit QuestMetadata(questId, questType, difficulty, title, tags, communities);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[1], bytes32(uint256(questId)));
    }

    function testTurnOffMinting() public {
        bool isActive = incentiveContract.s_isClaimingActive();

        vm.prank(ownerPubKey);
        incentiveContract.setIsClaimingActive(false);

        bool isActiveUpdated = incentiveContract.s_isClaimingActive();

        assert(isActiveUpdated != isActive);
    }

    function testRevokeSignerRole() public {
        bytes32 signerRole = keccak256("SIGNER");
        bool isSigner = incentiveContract.hasRole(signerRole, adminAddress);
        assertEq(isSigner, true);

        vm.prank(adminAddress);
        incentiveContract.renounceRole(signerRole, adminAddress);
    }

    function testRevokeAdminRole() public {
        bool isAdmin =
            incentiveContract.hasRole(incentiveContract.DEFAULT_ADMIN_ROLE(), ownerPubKey);
        assertEq(isAdmin, true);

        vm.startPrank(ownerPubKey);
        incentiveContract.grantRole(incentiveContract.DEFAULT_ADMIN_ROLE(), adminAddress);
        incentiveContract.revokeRole(incentiveContract.DEFAULT_ADMIN_ROLE(), ownerPubKey);

        bool isAdmin2 =
            incentiveContract.hasRole(incentiveContract.DEFAULT_ADMIN_ROLE(), adminAddress);
        assertEq(isAdmin2, true);
        vm.stopPrank();
    }

    function testRotateAdmin() public {
        bool isAdmin =
            incentiveContract.hasRole(incentiveContract.DEFAULT_ADMIN_ROLE(), ownerPubKey);
        assertEq(isAdmin, true);

        vm.startPrank(ownerPubKey);
        incentiveContract.grantRole(incentiveContract.DEFAULT_ADMIN_ROLE(), ALICE);

        bool isAdmin2 = incentiveContract.hasRole(incentiveContract.DEFAULT_ADMIN_ROLE(), ALICE);
        assertEq(isAdmin2, true);

        incentiveContract.renounceRole(incentiveContract.DEFAULT_ADMIN_ROLE(), ownerPubKey);
        bool isAdmin3 =
            incentiveContract.hasRole(incentiveContract.DEFAULT_ADMIN_ROLE(), ownerPubKey);
        assertEq(isAdmin3, false);
        vm.stopPrank();
    }

    function testGrantDefaultAdminRole() public {
        incentiveContract.DEFAULT_ADMIN_ROLE();

        bool isActive = incentiveContract.s_isClaimingActive();
        assertEq(isActive, true);

        bytes4 selector = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));
        bytes memory expectedError =
            abi.encodeWithSelector(selector, BOB, incentiveContract.DEFAULT_ADMIN_ROLE());
        vm.expectRevert(expectedError);
        vm.prank(BOB);
        incentiveContract.setIsClaimingActive(false);

        bool isActive2 = incentiveContract.s_isClaimingActive();
        assertEq(isActive2, true);

        vm.startBroadcast(ownerPubKey);
        incentiveContract.grantRole(incentiveContract.DEFAULT_ADMIN_ROLE(), BOB);
        vm.stopBroadcast();

        vm.prank(BOB);
        incentiveContract.setIsClaimingActive(false);

        bool isActive3 = incentiveContract.s_isClaimingActive();
        assertEq(isActive3, false);
    }

    function testSetTrueMintingToTrueAgain() public {
        vm.prank(ownerPubKey);
        incentiveContract.setIsClaimingActive(true);
        assertEq(incentiveContract.s_isClaimingActive(), true);
    }

    function testSetFalseMintingToFalseAgain() public {
        vm.startPrank(ownerPubKey);
        incentiveContract.setIsClaimingActive(false);
        incentiveContract.setIsClaimingActive(false);
        vm.stopPrank();
        assertEq(incentiveContract.s_isClaimingActive(), false);
    }

    modifier SetMintingToFalse() {
        vm.startBroadcast(ownerPubKey);
        incentiveContract.setIsClaimingActive(false);
        vm.stopBroadcast();
        _;
    }

    function testIncentiveVersion() public view {
        string memory v = incentiveContract.incentiveVersion();
        assertEq(v, "1");
    }

    function getTestSignature(uint256 privateKey, bytes32 digest)
        internal
        pure
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // Add new test for inactive quest rewards
    function testClaimRewardInactiveQuest() public {
        // Setup
        uint256 questId = 9999; // Use a different questId than the one initialized
        
        // Create data for reward claim
        Incentive.IncentiveData memory data = helper.getIncentiveData(
            ALICE,
            address(factoryContract),
            address(erc20Mock),
            0,
            100,
            ITokenType.TokenType.ERC20,
            0,
            137
        );
        
        // Change the questId to the inactive one
        data.questId = questId;
        
        // Sign the data
        bytes32 structHash = helper.getStructHash(data);
        bytes32 digest = helper.getDigest(getDomainSeparator(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // The quest was not initialized, so it should not be active
        bool isActive = incentiveContract.isQuestActive(questId);
        assertEq(isActive, false);
        
        // Try to claim rewards and expect revert
        vm.prank(adminAddress);
        vm.expectRevert(abi.encodeWithSelector(Incentive.Incentive__QuestInactive.selector, questId));
        incentiveContract.claimReward(data, signature);
        
        // Verify no balance was transferred
        uint256 aliceBal = erc20Mock.balanceOf(ALICE);
        assertEq(aliceBal, 0);
    }
    
    // Test for claiming after unpublishing a quest
    function testClaimRewardUnpublishedQuest() public {
        // Initialize a quest
        uint256 questId = 42;
        vm.prank(adminAddress);
        incentiveContract.initializeQuest(
            questId,
            new string[](0),
            "Temporary Quest",
            Incentive.Difficulty.BEGINNER,
            Incentive.QuestType.QUEST,
            new string[](0)
        );
        
        // Confirm quest is active
        bool isActive = incentiveContract.isQuestActive(questId);
        assertEq(isActive, true);
        
        // Create signed data for claim
        Incentive.IncentiveData memory data = helper.getIncentiveData(
            ALICE,
            address(factoryContract),
            address(erc20Mock),
            0,
            100,
            ITokenType.TokenType.ERC20,
            0,
            137
        );
        
        // Set questId to the one we just initialized
        data.questId = questId;
        
        // Generate signature
        bytes32 structHash = helper.getStructHash(data);
        bytes32 digest = helper.getDigest(getDomainSeparator(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Now unpublish the quest
        vm.prank(adminAddress);
        incentiveContract.unpublishQuest(questId);
        
        // Verify quest is now inactive
        isActive = incentiveContract.isQuestActive(questId);
        assertEq(isActive, false);
        
        // Attempt to claim rewards for the unpublished quest
        vm.prank(adminAddress);
        vm.expectRevert(abi.encodeWithSelector(Incentive.Incentive__QuestInactive.selector, questId));
        incentiveContract.claimReward(data, signature);
        
        // Verify no balance was transferred
        uint256 aliceBal = erc20Mock.balanceOf(ALICE);
        assertEq(aliceBal, 0);
    }
}
