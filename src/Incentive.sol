// SPDX-License-Identifier: Apache-2.0
/*
.____                             ________
|    |   _____  ___.__. __________\_____  \
|    |   \__  \<   |  |/ __ \_  __ \_(__  <
|    |___ / __ \\___  \  ___/|  | \/       \
|_______ (____  / ____|\___  >__| /______  /
        \/    \/\/         \/            \/
*/

pragma solidity 0.8.26;

import {EIP712Upgradeable} from
    "@openzeppelin-contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from
    "@openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ITokenType} from "./escrow/interfaces/ITokenType.sol";
import {IFactory} from "./escrow/interfaces/IFactory.sol";

/// @title Incentive
/// @notice Modified so that it no longer mints an NFT nor processes any payments.
/// Instead, it simply verifies an EIP-712–signed "IncentiveData" struct (preventing replay via a nonce),
/// calls the factory to distribute rewards (if provided),
/// and now enforces that a reward for a given quest may only be claimed once every 24 hours.
contract Incentive is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    EIP712Upgradeable,
    ReentrancyGuardUpgradeable,
    ITokenType
{
    using ECDSA for bytes32;

    // ===== ERRORS =====
    error Incentive__IsNotSigner();
    error Incentive__ClaimingIsNotActive();
    error Incentive__WithdrawFailed();
    error Incentive__NonceAlreadyUsed();
    error Incentive__TreasuryNotSet();
    error Incentive__InvalidAdminAddress();
    error Incentive__ClaimCooldownNotExpired(uint256 timeLeft);

    // ===== STATE =====
    bool public s_isClaimingActive;
    mapping(uint256 => bool) internal s_nonces;
    mapping(uint256 => bool) internal s_quests;
    address public s_treasury; // used for withdrawals if needed

    // 24-hour claim interval (in seconds)
    uint256 public constant CLAIM_INTERVAL = 86400;
    // Mapping: questId => (claimer => timestamp of last claim)
    mapping(uint256 => mapping(address => uint256)) public s_lastClaimed;

    // Roles
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER");

    // EIP712 typehashes (we update IncentiveData so it no longer has price, isNative, tokenURI or recipients)
    bytes32 internal constant TX_DATA_HASH =
        keccak256("TransactionData(string txHash,string networkChainId)");
    bytes32 internal constant REWARD_DATA_HASH = keccak256(
        "RewardData(address tokenAddress,uint256 chainId,uint256 amount,uint256 tokenId,uint8 tokenType,uint256 rakeBps,address factoryAddress)"
    );
    bytes32 internal constant INCENTIVE_DATA_HASH = keccak256(
        "IncentiveData(uint256 questId,uint256 nonce,address toAddress,string walletProvider,string embedOrigin,TransactionData[] transactions,RewardData reward)RewardData(address tokenAddress,uint256 chainId,uint256 amount,uint256 tokenId,uint8 tokenType,uint256 rakeBps,address factoryAddress)TransactionData(string txHash,string networkChainId)"
    );

    // ===== ENUMS =====
    enum QuestType {
        QUEST,
        STREAK
    }

    enum Difficulty {
        BEGINNER,
        INTERMEDIATE,
        ADVANCED
    }

    // ===== EVENTS =====

    /// @notice Emitted when a new quest is initialized
    /// @param questId The unique identifier of the quest
    /// @param questType The type of the quest (QUEST, STREAK)
    /// @param difficulty The difficulty level of the quest (BEGINNER, INTERMEDIATE, ADVANCED)
    /// @param title The title of the quest
    /// @param tags An array of tags associated with the quest
    /// @param communities An array of communities associated with the quest
    event QuestMetadata(
        uint256 indexed questId,
        QuestType questType,
        Difficulty difficulty,
        string title,
        string[] tags,
        string[] communities
    );

    /// @notice Emitted for each transaction associated with a Incentive claim
    /// This event is designed to support both EVM and non-EVM blockchains
    /// @param questId The quest ID of the Incentive
    /// @param txHash The hash of the transaction
    /// @param networkChainId The network and chain ID of the transaction in the format <network>:<chain-id>
    event IncentiveTransaction(uint256 indexed questId, string txHash, string networkChainId);

    /// @notice Emitted when there is a reward associated with a Incentive
    /// @param nonce The nonce of the TokenReward event
    /// @param tokenAddress The token address of the reward
    /// @param chainId The blockchain chain ID where the transaction occurred
    /// @param amount The amount of the reward
    /// @param tokenId Token ID of the reward (only applicable for ERC721 and ERC1155)
    /// @param tokenType The type of reward token
    event TokenReward(
        uint256 indexed nonce,
        address indexed tokenAddress,
        uint256 indexed chainId,
        uint256 amount,
        uint256 tokenId,
        TokenType tokenType
    );
    /// @notice Emitted when the minting switch is turned on/off
    /// @param isActive The boolean showing if the minting is active or not
    event MintingSwitch(bool isActive);

    /// @notice Emitted when the contract balance is withdrawn by an admin
    /// @param amount The contract's balance that was withdrawn
    event ContractWithdrawal(uint256 amount);

    /// @notice Emitted when a quest is disabled
    /// @param questId The ID of the quest that was disabled
    event QuestDisabled(uint256 indexed questId);

    /// @notice Emitted when the treasury address is updated
    /// @param newTreasury The new treasury address
    event UpdatedTreasury(address indexed newTreasury);

    // ===== STRUCTS =====
    struct TransactionData {
        string txHash;
        string networkChainId;
    }

    /// @dev Contains data about the token rewards associated with a Incentive.
    /// @param tokenAddress The token address of the reward
    /// @param chainId The blockchain chain ID where the transaction occurred
    /// @param amount The amount of the reward
    /// @param tokenId The token ID
    /// @param tokenType The token type
    /// @param rakeBps The rake basis points
    /// @param factoryAddress The escrow factory address
    struct RewardData {
        address tokenAddress;
        uint256 chainId;
        uint256 amount;
        uint256 tokenId;
        TokenType tokenType;
        uint256 rakeBps;
        address factoryAddress;
    }

    /// @dev Represents the data needed for claiming a Incentive token reward.
    /// @param questId The ID of the quest associated with the Incentive
    /// @param nonce A unique number to prevent replay attacks
    /// @param toAddress The address where the Incentive will be minted
    /// @param walletProvider The wallet provider used for the transaction
    /// @param embedOrigin The origin source of the Incentive's embed content
    /// @param transactions An array of transactions related to the Incentive
    /// @param reward Data about the reward associated with the Incentive
    struct IncentiveData {
        uint256 questId;
        uint256 nonce;
        address toAddress;
        string walletProvider;
        string embedOrigin;
        TransactionData[] transactions;
        RewardData reward;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Returns the version of the contract.
    function incentiveVersion() external pure returns (string memory) {
        return "1";
    }

    /// @notice Initializes the contract.
    /// @param _signingDomain The EIP-712 domain name.
    /// @param _signatureVersion The EIP-712 version.
    /// @param _admin The admin address.
    /// @param _treasury The treasury address.
    function initialize(
        string memory _signingDomain,
        string memory _signatureVersion,
        address _admin,
        address _treasury
    ) external initializer {
        if (_admin == address(0)) revert Incentive__InvalidAdminAddress();
        __EIP712_init(_signingDomain, _signatureVersion);
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        s_isClaimingActive = true;
        s_treasury = _treasury;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(SIGNER_ROLE, _admin);
        _grantRole(UPGRADER_ROLE, _admin);
    }

    /// @notice Authorizes an upgrade to a new contract implementation
    /// @dev Overrides the UUPSUpgradeable internal function with access control.
    /// @param newImplementation Address of the new contract implementation
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}

    /// @notice Checks whether a quest is active or not
    /// @param questId Unique identifier for the quest
    function isQuestActive(uint256 questId) public view returns (bool) {
        return s_quests[questId];
    }

    /// @notice Called by a user to "claim" their reward.
    /// No payment is required – only gas.
    /// Enforces that a reward for a given quest can only be claimed once every 24 hours.
    /// @param data A IncentiveData struct containing the details for reward distribution.
    /// @param signature The EIP-712 signature over the IncentiveData.
    function claimReward(IncentiveData calldata data, bytes calldata signature)
        external
        nonReentrant
    {
        if (!s_isClaimingActive) {
            revert Incentive__ClaimingIsNotActive();
        }
        if (s_treasury == address(0)) {
            revert Incentive__TreasuryNotSet();
        }

        // Check cooldown: each address can claim for a given quest only once every 24 hours.
        uint256 lastClaim = s_lastClaimed[data.questId][msg.sender];
        if (block.timestamp < lastClaim + CLAIM_INTERVAL) {
            uint256 timeLeft = (lastClaim + CLAIM_INTERVAL) - block.timestamp;
            revert Incentive__ClaimCooldownNotExpired(timeLeft);
        }

        // Validate signature and nonce.
        _validateSignature(data, signature);
        // Update last claimed timestamp.
        s_lastClaimed[data.questId][msg.sender] = block.timestamp;

        // For every transaction submitted, emit a IncentiveTransaction event.
        for (uint256 i = 0; i < data.transactions.length; i++) {
            emit IncentiveTransaction(
                data.questId, data.transactions[i].txHash, data.transactions[i].networkChainId
            );
        }

        // If reward data is provided (i.e. chainId is nonzero) then call the factory
        // to distribute rewards and emit a TokenReward event.
        if (data.reward.chainId != 0) {
            if (data.reward.factoryAddress != address(0)) {
                IFactory(data.reward.factoryAddress).distributeRewards(
                    data.questId,
                    data.reward.tokenAddress,
                    data.toAddress,
                    data.reward.amount,
                    data.reward.tokenId,
                    data.reward.tokenType,
                    data.reward.rakeBps
                );
            }
            emit TokenReward(
                data.nonce,
                data.reward.tokenAddress,
                data.reward.chainId,
                data.reward.amount,
                data.reward.tokenId,
                data.reward.tokenType
            );
        }
    }

    /// @dev Verifies the signature and makes sure the nonce has not been used.
    function _validateSignature(IncentiveData calldata data, bytes calldata signature) internal {
        address signer = _getSigner(data, signature);
        if (!hasRole(SIGNER_ROLE, signer)) {
            revert Incentive__IsNotSigner();
        }
        if (s_nonces[data.nonce]) {
            revert Incentive__NonceAlreadyUsed();
        }
        s_nonces[data.nonce] = true;
    }

    /// @notice Recovers the signer's address from the IncentiveData and its associated signature
    /// @dev Utilizes EIP-712 typed data hashing and ECDSA signature recovery
    /// @param data The IncentiveData struct containing the details of the minting request
    /// @param sig The signature associated with the IncentiveData
    /// @return The address of the signer who signed the IncentiveData
    function _getSigner(IncentiveData calldata data, bytes calldata sig)
        internal
        view
        returns (address)
    {
        bytes32 digest = _computeDigest(data);
        return digest.recover(sig);
    }

    /// @notice Internal function to compute the EIP712 digest for IncentiveData
    /// @dev Generates the digest that must be signed by the signer.
    /// @param data The IncentiveData to generate a digest for
    /// @return The computed EIP712 digest
    function _computeDigest(IncentiveData calldata data) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(_getStructHash(data)));
    }

    /// @notice Internal function to generate the struct hash for IncentiveData
    /// @dev Encodes the IncentiveData struct into a hash as per EIP712 standard.
    /// @param data The IncentiveData struct to hash
    /// @return A hash representing the encoded IncentiveData
    function _getStructHash(IncentiveData calldata data) internal pure returns (bytes memory) {
        return abi.encode(
            INCENTIVE_DATA_HASH,
            data.questId,
            data.nonce,
            data.toAddress,
            _encodeString(data.walletProvider),
            _encodeString(data.embedOrigin),
            _encodeCompletedTxs(data.transactions),
            _encodeReward(data.reward)
        );
    }

    /// @notice Encodes a string into a bytes32 hash
    /// @dev Used for converting strings into a consistent format for EIP712 encoding
    /// @param _string The string to be encoded
    /// @return The keccak256 hash of the encoded string
    function _encodeString(string calldata _string) internal pure returns (bytes32) {
        return keccak256(bytes(_string));
    }

    /// @notice Encodes a transaction data into a byte array
    /// @dev Used for converting transaction data into a consistent format for EIP712 encoding
    /// @param transaction The TransactionData struct to be encoded
    /// @return A byte array representing the encoded transaction data
    function _encodeTx(TransactionData calldata transaction) internal pure returns (bytes memory) {
        return abi.encode(
            TX_DATA_HASH,
            _encodeString(transaction.txHash),
            _encodeString(transaction.networkChainId)
        );
    }

    /// @notice Encodes an array of transaction data into a single bytes32 hash
    /// @dev Used to aggregate multiple transactions into a single hash for EIP712 encoding
    /// @param txData An array of TransactionData structs to be encoded
    /// @return A bytes32 hash representing the aggregated and encoded transaction data
    function _encodeCompletedTxs(TransactionData[] calldata txData)
        internal
        pure
        returns (bytes32)
    {
        bytes32[] memory encodedTxs = new bytes32[](txData.length);
        for (uint256 i = 0; i < txData.length; i++) {
            encodedTxs[i] = keccak256(_encodeTx(txData[i]));
        }
        return keccak256(abi.encodePacked(encodedTxs));
    }

    /// @notice Encodes the reward data for a Incentive mint
    /// @param data An array of FeeRecipient structs to be encoded
    /// @return A bytes32 hash representing the encoded reward data
    function _encodeReward(RewardData calldata data) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                REWARD_DATA_HASH,
                data.tokenAddress,
                data.chainId,
                data.amount,
                data.tokenId,
                data.tokenType,
                data.rakeBps,
                data.factoryAddress
            )
        );
    }

    /// @notice Enables or disables the reward claim process
    /// @dev Can only be called by an account with the default admin role.
    /// @param _isActive Boolean indicating whether minting should be active
    function setIsMintingActive(bool _isActive) external onlyRole(DEFAULT_ADMIN_ROLE) {
        s_isClaimingActive = _isActive;
        emit MintingSwitch(_isActive);
    }

    /// @notice Sets a new treasury address
    /// @dev Can only be called by an account with the default admin role.
    /// @param _treasury Address of the new treasury to receive fees
    function setTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        s_treasury = _treasury;
        emit UpdatedTreasury(_treasury);
    }

    /// @notice Withdraws the contract's balance to the message sender
    /// @dev Can only be called by an account with the default admin role.
    function withdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 withdrawAmount = address(this).balance;
        (bool success,) = msg.sender.call{value: withdrawAmount}("");
        if (!success) {
            revert Incentive__WithdrawFailed();
        }
        emit ContractWithdrawal(withdrawAmount);
    }

    /// @notice Initializes a new quest with given parameters
    /// @dev Can only be called by an account with the signer role.
    /// @param questId Unique identifier for the quest
    /// @param communities Array of community names associated with the quest
    /// @param title Title of the quest
    /// @param difficulty Difficulty level of the quest
    /// @param questType Type of the quest
    /// @param tags Array of tags associated with the quest
    function initializeQuest(
        uint256 questId,
        string[] memory communities,
        string memory title,
        Difficulty difficulty,
        QuestType questType,
        string[] memory tags
    ) external onlyRole(SIGNER_ROLE) {
        s_quests[questId] = true;
        emit QuestMetadata(questId, questType, difficulty, title, tags, communities);
    }

    /// @notice Unpublishes and disables a quest
    /// @dev Can only be called by an account with the signer role
    /// @param questId Unique identifier for the quest
    function unpublishQuest(uint256 questId) external onlyRole(SIGNER_ROLE) {
        s_quests[questId] = false;
        emit QuestDisabled(questId);
    }

    /// @notice Returns how many seconds remain before a user may claim a reward again for a given quest.
    /// @param questId The quest identifier.
    /// @param claimant The address of the user.
    /// @return The number of seconds remaining (or 0 if the cooldown has expired).
    function getClaimCooldown(uint256 questId, address claimant) external view returns (uint256) {
        uint256 nextClaimTime = s_lastClaimed[questId][claimant] + CLAIM_INTERVAL;
        if (block.timestamp >= nextClaimTime) {
            return 0;
        }
        return nextClaimTime - block.timestamp;
    }

    /// @notice Checks if the contract implements an interface
    /// @dev Overrides the supportsInterface function of ERC721Upgradeable and AccessControlUpgradeable.
    /// @param interfaceId The interface identifier, as specified in ERC-165
    /// @return True if the contract implements the interface, false otherwise
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
