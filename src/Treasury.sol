// SPDX-License-Identifier: Apache-2.0
/*
__________.__                             .__        __   
\______   \  |  __ __   ____ _____________|__| _____/  |_ 
 |    |  _/  | |  |  \_/ __ \\____ \_  __ \  |/    \   __\
 |    |   \  |_|  |  /\  ___/|  |_> >  | \/  |   |  \  |  
 |______  /____/____/  \___  >   __/|__|  |__|___|  /__|  
        \/                 \/|__|                 \/      
*/

pragma solidity 0.8.26;

import "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from
    "@openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from
    "@openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC20Upgradeable} from
    "@openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin-contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @title Treasury
/// @notice Upgradeable treasury contract that can hold BP tokens, ETH, and any ERC20 tokens.
/// The admin (with DEFAULT_ADMIN_ROLE) can withdraw or donate funds to other addresses.
/// The contract is upgradeable using the UUPS proxy pattern.
contract Treasury is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;
    using Address for address payable;

    // =============================================================
    // ROLE DEFINITIONS
    // =============================================================
    // DEFAULT_ADMIN_ROLE is inherited.
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER");

    // =============================================================
    // EVENTS
    // =============================================================
    event Received(address indexed sender, uint256 amount);
    /// @notice Emitted when an ERC20 token is withdrawn.
    event TokenWithdrawn(address indexed token, address indexed to, uint256 amount);
    /// @notice Emitted when ETH is withdrawn.
    event ETHWithdrawn(address indexed to, uint256 amount);
    /// @notice Emitted when a donation is sent from the treasury.
    event DonationSent(address indexed destination, address indexed token, uint256 amount);

    // =============================================================
    // INITIALIZER
    // =============================================================
    /// @notice Initializes the Treasury.
    /// @param _admin The address to be granted the DEFAULT_ADMIN_ROLE and UPGRADER_ROLE.
    function initialize(address _admin) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        // Grant roles to the provided admin address.
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(UPGRADER_ROLE, _admin);
    }

    // =============================================================
    // FALLBACK & RECEIVE FUNCTIONS
    // =============================================================
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    fallback() external payable {
        emit Received(msg.sender, msg.value);
    }

    // =============================================================
    // ADMIN FUNCTIONS (Restricted by DEFAULT_ADMIN_ROLE)
    // =============================================================
    /// @notice Withdraw a specified ERC20 token to a designated address.
    /// @param token Address of the ERC20 token.
    /// @param to Recipient address.
    /// @param amount Amount to withdraw.
    function withdrawToken(address token, address to, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
    {
        require(token != address(0), "Invalid token address");
        require(to != address(0), "Invalid recipient");
        IERC20(token).safeTransfer(to, amount);
        emit TokenWithdrawn(token, to, amount);
    }

    /// @notice Withdraws ETH to a designated address.
    /// @param to Recipient address.
    /// @param amount Amount of ETH to withdraw.
    function withdrawETH(address payable to, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
    {
        require(to != address(0), "Invalid recipient");
        require(address(this).balance >= amount, "Insufficient ETH balance");
        to.sendValue(amount);
        emit ETHWithdrawn(to, amount);
    }

    /// @notice Donates funds from the treasury to a destination.
    /// If token is address(0), ETH is sent; otherwise the ERC20 token is sent.
    /// @param destination The recipient address.
    /// @param token The token to donate (use address(0) for ETH).
    /// @param amount The amount to donate.
    function donate(address destination, address token, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
    {
        require(destination != address(0), "Invalid destination");
        if (token == address(0)) {
            require(address(this).balance >= amount, "Insufficient ETH balance");
            payable(destination).sendValue(amount);
        } else {
            IERC20(token).safeTransfer(destination, amount);
        }
        emit DonationSent(destination, token, amount);
    }

    // =============================================================
    // UUPS UPGRADE AUTHORIZATION
    // =============================================================
    /// @notice Authorizes an upgrade to a new contract implementation.
    /// @dev Overrides the UUPSUpgradeable internal function with access control.
    /// @param newImplementation Address of the new contract implementation.
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}
}
