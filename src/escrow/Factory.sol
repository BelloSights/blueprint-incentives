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

import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from
    "@openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Escrow} from "./Escrow.sol";
import {Incentive} from "../Incentive.sol";
import {IEscrow} from "./interfaces/IEscrow.sol";
import {IFactory} from "./interfaces/IFactory.sol";
import {ITokenType} from "../escrow/interfaces/ITokenType.sol";

contract Factory is IFactory, Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    // ===== ERRORS =====
    error Factory__OnlyCallableByIncentive();
    error Factory__OnlyCallableByAdmin();
    error Factory__IncentiveQuestIsActive();
    error Factory__NoEscrowForId();
    error Factory__EscrowDisabled();
    error Factory__EscrowAlreadyExists();
    error Factory__ZeroAddress();
    error Factory__QuestAlreadyRegistered();
    error Factory__QuestNotRegistered();

    // ===== STATE =====
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    Incentive public immutable i_incentive;
    uint256 public s_nextEscrowId;

    struct EscrowInfo {
        uint256 escrowId;
        address escrow;
        address creator;
        bool active;
    }

    // Mapping from escrowId to its info.
    mapping(uint256 => EscrowInfo) public s_escrows;
    // Mapping from questId to the escrow id that should be used.
    mapping(uint256 => uint256) public s_questToEscrow;

    // ===== EVENTS =====
    event EscrowRegistered(
        address indexed registror, uint256 indexed escrowId, address indexed escrow, address creator
    );
    event EscrowDisabled(uint256 indexed escrowId);
    event EscrowEnabled(uint256 indexed escrowId);
    event QuestRegistered(uint256 indexed questId, uint256 indexed escrowId);
    event TokenPayout(
        address indexed receiver,
        address indexed tokenAddress,
        uint256 indexed tokenId,
        uint256 amount,
        uint8 tokenType,
        uint256 questId
    );
    event EscrowWithdrawal(
        address indexed caller,
        address indexed receiver,
        address indexed tokenAddress,
        uint256 tokenId,
        uint256 amount,
        uint8 tokenType,
        uint256 questId
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(Incentive incentive) {
        i_incentive = incentive;
        _disableInitializers();
    }

    /// @notice Initializes the Factory contract.
    /// @param admin Address to be granted the default admin role.
    function initialize(address admin) external override initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        unchecked {
            s_nextEscrowId = 1;
        }
    }

    /// @notice Creates a new escrow for a creator.
    /// @param creator The address of the creator (informational only; the escrow is owned by Incentive).
    /// @param whitelistedTokens Array of token addresses to whitelist.
    /// @param treasury Address of the treasury for receiving rake fees.
    /// @return escrowId The unique identifier of the newly deployed escrow.
    function createEscrow(address creator, address[] calldata whitelistedTokens, address treasury)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint256)
    {
        if (creator == address(0)) revert Factory__ZeroAddress();
        uint256 escrowId = s_nextEscrowId;
        // Deploy the new escrow with the Incentive contract as owner.
        address escrowAddress = address(
            new Escrow{salt: bytes32(keccak256(abi.encode(creator, escrowId)))}(
                address(this), whitelistedTokens, treasury
            )
        );
        s_escrows[escrowId] =
            EscrowInfo({escrowId: escrowId, escrow: escrowAddress, creator: creator, active: true});
        emit EscrowRegistered(msg.sender, escrowId, escrowAddress, creator);
        unchecked {
            s_nextEscrowId++;
        }
        return escrowId;
    }

    /// @notice Disables an escrow so that no funds can be sent.
    /// @param escrowId The identifier of the escrow to disable.
    function disableEscrow(uint256 escrowId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        EscrowInfo storage info = s_escrows[escrowId];
        if (info.escrow == address(0)) revert Factory__NoEscrowForId();
        info.active = false;
        emit EscrowDisabled(escrowId);
    }

    /// @notice Re-enables a previously disabled escrow.
    /// @param escrowId The identifier of the escrow to enable.
    function enableEscrow(uint256 escrowId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        EscrowInfo storage info = s_escrows[escrowId];
        if (info.escrow == address(0)) revert Factory__NoEscrowForId();
        info.active = true;
        emit EscrowEnabled(escrowId);
    }

    /// @notice Registers a quest to point to an escrow.
    /// @param questId The quest identifier.
    /// @param escrowId The escrow that should be used.
    /// Only accounts with the DEFAULT_ADMIN_ROLE can call this.
    function registerQuest(uint256 questId, uint256 escrowId)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        // if the quest is already registered, allow idempotent registration for the same escrowId.
        if (s_questToEscrow[questId] != 0) {
            if (s_questToEscrow[questId] == escrowId) {
                return;
            }
            revert Factory__QuestAlreadyRegistered();
        }
        s_questToEscrow[questId] = escrowId;
        emit QuestRegistered(questId, escrowId);
    }

    /// @notice Adds a token to the whitelist for the escrow associated with a quest.
    /// @param questId The quest identifier.
    /// @param token The token address to whitelist.
    function addTokenToWhitelist(uint256 questId, address token)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 escrowId = s_questToEscrow[questId];
        if (escrowId == 0) revert Factory__QuestNotRegistered();
        EscrowInfo storage info = s_escrows[escrowId];
        if (!info.active) revert Factory__EscrowDisabled();
        IEscrow(info.escrow).addTokenToWhitelist(token);
    }

    /// @notice Removes a token from the whitelist for the escrow associated with a quest.
    /// @param questId The quest identifier.
    /// @param token The token address to remove.
    function removeTokenFromWhitelist(uint256 questId, address token)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 escrowId = s_questToEscrow[questId];
        if (escrowId == 0) revert Factory__QuestNotRegistered();
        EscrowInfo storage info = s_escrows[escrowId];
        if (!info.active) revert Factory__EscrowDisabled();
        IEscrow(info.escrow).removeTokenFromWhitelist(token);
    }

    /// @notice Withdraws funds from the escrow associated with a quest.
    /// @param questId The quest identifier.
    /// @param to Recipient address.
    /// @param token The token address (use address(0) for native).
    /// @param tokenId The token ID (if applicable).
    /// @param tokenType The token type.
    function withdrawFunds(
        uint256 questId,
        address to,
        address token,
        uint256 tokenId,
        TokenType tokenType
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (i_incentive.isQuestActive(questId)) revert Factory__IncentiveQuestIsActive();
        uint256 escrowId = s_questToEscrow[questId];
        if (escrowId == 0) revert Factory__QuestNotRegistered();
        EscrowInfo storage info = s_escrows[escrowId];
        if (!info.active) revert Factory__EscrowDisabled();
        if (tokenType == ITokenType.TokenType.NATIVE) {
            uint256 escrowBalance = info.escrow.balance;
            IEscrow(info.escrow).withdrawNative(to, escrowBalance, 0);
            emit EscrowWithdrawal(
                msg.sender, to, address(0), 0, escrowBalance, uint8(tokenType), questId
            );
        } else if (tokenType == ITokenType.TokenType.ERC20) {
            uint256 erc20Amount = IEscrow(info.escrow).escrowERC20Reserves(token);
            IEscrow(info.escrow).withdrawERC20(token, to, erc20Amount, 0);
            emit EscrowWithdrawal(msg.sender, to, token, 0, erc20Amount, uint8(tokenType), questId);
        } else if (tokenType == ITokenType.TokenType.ERC721) {
            IEscrow(info.escrow).withdrawERC721(token, to, tokenId);
            emit EscrowWithdrawal(msg.sender, to, token, tokenId, 1, uint8(tokenType), questId);
        } else if (tokenType == ITokenType.TokenType.ERC1155) {
            uint256 erc1155Amount = IEscrow(info.escrow).escrowERC1155Reserves(token, tokenId);
            IEscrow(info.escrow).withdrawERC1155(token, to, tokenId, erc1155Amount);
            emit EscrowWithdrawal(
                msg.sender, to, token, tokenId, erc1155Amount, uint8(tokenType), questId
            );
        }
    }

    /// @notice Distributes rewards from the escrow associated with a quest.
    /// @param questId The quest identifier.
    /// @param token The token address (use address(0) for native).
    /// @param to Recipient address.
    /// @param amount Amount to send.
    /// @param rewardTokenId The reward token ID (if applicable).
    /// @param tokenType The token type.
    /// @param rakeBps Basis points for rake (if applicable).
    function distributeRewards(
        uint256 questId,
        address token,
        address to,
        uint256 amount,
        uint256 rewardTokenId,
        TokenType tokenType,
        uint256 rakeBps
    ) external override {
        if (msg.sender != address(i_incentive)) revert Factory__OnlyCallableByIncentive();
        uint256 escrowId = s_questToEscrow[questId];
        if (escrowId == 0) revert Factory__QuestNotRegistered();
        EscrowInfo storage info = s_escrows[escrowId];
        if (!info.active) revert Factory__EscrowDisabled();
        if (tokenType == TokenType.NATIVE) {
            IEscrow(info.escrow).withdrawNative(to, amount, rakeBps);
            emit TokenPayout(to, address(0), 0, amount, uint8(tokenType), questId);
        } else if (tokenType == TokenType.ERC20) {
            IEscrow(info.escrow).withdrawERC20(token, to, amount, rakeBps);
            emit TokenPayout(to, token, 0, amount, uint8(tokenType), questId);
        } else if (tokenType == TokenType.ERC721) {
            IEscrow(info.escrow).withdrawERC721(token, to, rewardTokenId);
            emit TokenPayout(to, token, rewardTokenId, 1, uint8(tokenType), questId);
        } else if (tokenType == TokenType.ERC1155) {
            IEscrow(info.escrow).withdrawERC1155(token, to, amount, rewardTokenId);
            emit TokenPayout(to, token, rewardTokenId, amount, uint8(tokenType), questId);
        }
    }

    // ----------------------------------------------------------------
    // Helper function (fulfilling interface) to return the escrow address for a quest.
    // ----------------------------------------------------------------
    function getEscrow(uint256 questId) external view override returns (address) {
        uint256 escrowId = s_questToEscrow[questId];
        if (escrowId == 0) revert Factory__QuestNotRegistered();
        EscrowInfo storage info = s_escrows[escrowId];
        return info.escrow;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        virtual
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {}
}
