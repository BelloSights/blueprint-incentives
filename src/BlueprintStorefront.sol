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

import {EIP712Upgradeable} from
    "@openzeppelin-contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from
    "@openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC20Upgradeable} from
    "@openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC721Upgradeable} from
    "@openzeppelin-contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {AccessControlUpgradeable} from
    "@openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/// @title BlueprintStorefront
/// @notice A storefront that accepts payments for items either in BP tokens or in ETH.
/// The incoming funds are split into three parts:
///  - creatorWallet receives its share;
///  - buybackWallet (the BuybackHook address) receives its share for later swapping/liquidity;
///  - blueprintWallet (treasury) receives its share.
contract BlueprintStorefront is
    Initializable,
    EIP712Upgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for ERC20Upgradeable;

    // =============================================================
    // ERROR CODES
    // =============================================================
    error BLUEPRINT_STOREFRONT__InvalidAdminAddress();
    error BLUEPRINT_STOREFRONT__InvalidSignature();
    error BLUEPRINT_STOREFRONT__NonceAlreadyUsed();
    error BLUEPRINT_STOREFRONT__ItemDoesNotExist();
    error BLUEPRINT_STOREFRONT__ItemNotActive();
    error BLUEPRINT_STOREFRONT__ItemSoldOut();
    error BLUEPRINT_STOREFRONT__AlreadyPurchased();
    error BLUEPRINT_STOREFRONT__InsufficientETH();
    error BLUEPRINT_STOREFRONT__InvalidPaymentTokenAddress();
    error BLUEPRINT_STOREFRONT__InvalidBuybackWallet();
    error BLUEPRINT_STOREFRONT__InvalidCreatorWallet();
    error BLUEPRINT_STOREFRONT__InvalidBlueprintWallet();

    // =============================================================
    // ROLE DEFINITIONS
    // =============================================================
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER");
    // DEFAULT_ADMIN_ROLE is inherited

    // =============================================================
    // ITEM STRUCTURES & STORAGE
    // =============================================================
    enum ProductType {
        PHYSICAL,
        DIGITAL
    }

    struct Item {
        uint256 price;
        uint256 totalSupply;
        uint256 sold;
        ProductType productType;
        bool active;
        bool exists;
    }

    // Mapping from itemId to Item details.
    mapping(uint256 => Item) public items;
    // To help with queries we track an array of item IDs.
    uint256[] private itemIds;
    // Mapping to record if an address has purchased a given item.
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

    // =============================================================
    // SPLIT & PAYMENT VARIABLES
    // =============================================================
    // For splitting funds, the sum of the basis points must equal 10000.
    uint256 public buybackBps;
    uint256 public creatorBps;
    uint256 public blueprintBps;

    // Distribution wallet addresses.
    address public buybackWallet;
    address public creatorWallet;
    address public blueprintWallet;

    // Payment token (BP token).
    ERC20Upgradeable public paymentToken;

    // =============================================================
    // EIP-712 PURCHASE REQUEST STRUCT
    // =============================================================
    struct PurchaseRequest {
        uint256 itemId;
        uint256 nonce;
        address buyer;
    }

    // The typehash for the PurchaseRequest struct.
    bytes32 public constant PURCHASE_REQUEST_TYPEHASH =
        keccak256("PurchaseRequest(uint256 itemId,uint256 nonce,address buyer)");

    // Mapping to track used nonces (to prevent replay attacks).
    mapping(uint256 => bool) public usedNonces;

    // =============================================================
    // EVENTS
    // =============================================================
    event ItemSet(
        uint256 indexed itemId,
        uint256 price,
        uint256 totalSupply,
        ProductType productType,
        bool active
    );
    event ItemUpdated(uint256 indexed itemId, uint256 price, uint256 totalSupply, bool active);
    event ItemDeactivated(uint256 indexed itemId);
    event ItemReactivated(uint256 indexed itemId);
    event ItemPurchased(uint256 indexed itemId, address indexed buyer, uint256 price);
    event SplitUpdated(uint256 buybackBps, uint256 creatorBps, uint256 blueprintBps);
    event PaymentTokenUpdated(address newPaymentToken);
    event BuybackWalletUpdated(address newBuybackWallet);
    event CreatorWalletUpdated(address newCreatorWallet);
    event BlueprintWalletUpdated(address newBlueprintWallet);
    event EmergencyWithdrawal(address token, uint256 amount);

    // =============================================================
    // INITIALIZER
    // =============================================================
    /// @notice Initializes the BlueprintStorefront with admin only.
    /// @param _admin Address to be granted the DEFAULT_ADMIN_ROLE.
    function initialize(address _admin) public initializer {
        __EIP712_init("BlueprintStorefront", "1");
        __ReentrancyGuard_init();
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        // Grant the DEFAULT_ADMIN_ROLE to the provided admin.
        if (_admin == address(0)) revert BLUEPRINT_STOREFRONT__InvalidAdminAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(UPGRADER_ROLE, _admin);
    }

    // =============================================================
    // ADMIN CONFIGURATION FUNCTIONS
    // =============================================================

    /// @notice Sets the payment token.
    /// @param _paymentToken Address of the ERC20 token used for payments.
    function setPaymentToken(address _paymentToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_paymentToken == address(0)) revert BLUEPRINT_STOREFRONT__InvalidPaymentTokenAddress();
        paymentToken = ERC20Upgradeable(_paymentToken);
        emit PaymentTokenUpdated(_paymentToken);
    }

    /// @notice Updates the split percentages.
    /// @param _buybackBps Buyback split in basis points.
    /// @param _creatorBps Creator split in basis points.
    /// @param _blueprintBps Blueprint split in basis points.
    function updateSplits(uint256 _buybackBps, uint256 _creatorBps, uint256 _blueprintBps)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _updateSplits(_buybackBps, _creatorBps, _blueprintBps);
    }

    /// @notice Sets the buyback wallet address.
    /// @param _buybackWallet Address of the wallet receiving the buyback portion.
    function setBuybackWallet(address _buybackWallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_buybackWallet == address(0)) revert BLUEPRINT_STOREFRONT__InvalidBuybackWallet();
        buybackWallet = _buybackWallet;
        emit BuybackWalletUpdated(_buybackWallet);
    }

    /// @notice Sets the creator wallet address.
    /// @param _creatorWallet Address of the wallet receiving the creator portion.
    function setCreatorWallet(address _creatorWallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_creatorWallet == address(0)) revert BLUEPRINT_STOREFRONT__InvalidCreatorWallet();
        creatorWallet = _creatorWallet;
        emit CreatorWalletUpdated(_creatorWallet);
    }

    /// @notice Sets the blueprint wallet address.
    /// @param _blueprintWallet Address of the wallet receiving the blueprint portion.
    function setBlueprintWallet(address _blueprintWallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_blueprintWallet == address(0)) revert BLUEPRINT_STOREFRONT__InvalidBlueprintWallet();
        blueprintWallet = _blueprintWallet;
        emit BlueprintWalletUpdated(_blueprintWallet);
    }

    // =============================================================
    // INTERNAL SPLIT LOGIC
    // =============================================================
    function _updateSplits(uint256 _buybackBps, uint256 _creatorBps, uint256 _blueprintBps)
        internal
    {
        require(_buybackBps + _creatorBps + _blueprintBps == 10000, "Splits must sum to 10000");
        buybackBps = _buybackBps;
        creatorBps = _creatorBps;
        blueprintBps = _blueprintBps;
        emit SplitUpdated(_buybackBps, _creatorBps, _blueprintBps);
    }

    // =============================================================
    // ROLE MANAGEMENT FUNCTIONS (Admin Only)
    // =============================================================
    function addAdmin(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account == address(0)) revert BLUEPRINT_STOREFRONT__InvalidAdminAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, account);
    }

    function removeAdmin(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account == address(0)) revert BLUEPRINT_STOREFRONT__InvalidAdminAddress();
        _revokeRole(DEFAULT_ADMIN_ROLE, account);
    }

    function addSigner(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account == address(0)) revert BLUEPRINT_STOREFRONT__InvalidAdminAddress();
        _grantRole(SIGNER_ROLE, account);
    }

    function removeSigner(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account == address(0)) revert BLUEPRINT_STOREFRONT__InvalidAdminAddress();
        _revokeRole(SIGNER_ROLE, account);
    }

    // =============================================================
    // ITEM MANAGEMENT FUNCTIONS (Admin Only)
    // =============================================================
    function setItem(
        uint256 itemId,
        uint256 price,
        uint256 totalSupply,
        ProductType productType,
        bool active
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(price > 0, "Price must be > 0");
        require(totalSupply > 0, "Supply must be > 0");
        // If the item is new, record its ID.
        if (!items[itemId].exists) {
            itemIds.push(itemId);
        }
        items[itemId] = Item({
            price: price,
            totalSupply: totalSupply,
            sold: items[itemId].sold,
            productType: productType,
            active: active,
            exists: true
        });
        emit ItemSet(itemId, price, totalSupply, productType, active);
    }

    /// @notice Admin function to update multiple items.
    function updateItems(
        uint256[] calldata _itemIds,
        uint256[] calldata _prices,
        uint256[] calldata _totalSupplies,
        bool[] calldata _activeStatuses
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            _itemIds.length == _prices.length && _prices.length == _totalSupplies.length
                && _totalSupplies.length == _activeStatuses.length,
            "Array lengths mismatch"
        );
        for (uint256 i = 0; i < _itemIds.length; i++) {
            uint256 id = _itemIds[i];
            require(items[id].exists, "Item does not exist");
            items[id].price = _prices[i];
            items[id].totalSupply = _totalSupplies[i];
            items[id].active = _activeStatuses[i];
            emit ItemUpdated(id, _prices[i], _totalSupplies[i], _activeStatuses[i]);
        }
    }

    /// @notice Admin function to deactivate an item.
    function deactivateItem(uint256 itemId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!items[itemId].exists) revert BLUEPRINT_STOREFRONT__ItemDoesNotExist();
        items[itemId].active = false;
        emit ItemDeactivated(itemId);
    }

    /// @notice Admin function to reactivate an item.
    function reactivateItem(uint256 itemId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!items[itemId].exists) revert BLUEPRINT_STOREFRONT__ItemDoesNotExist();
        items[itemId].active = true;
        emit ItemReactivated(itemId);
    }

    /// @notice Returns the remaining supply for an item.
    function getRemainingSupply(uint256 itemId) public view returns (uint256) {
        if (!items[itemId].exists) revert BLUEPRINT_STOREFRONT__ItemDoesNotExist();
        return items[itemId].totalSupply - items[itemId].sold;
    }

    /// @notice Returns an array of active item IDs.
    function getActiveItemIds() external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < itemIds.length; i++) {
            if (items[itemIds[i]].active) {
                count++;
            }
        }
        uint256[] memory activeIds = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < itemIds.length; i++) {
            if (items[itemIds[i]].active) {
                activeIds[index] = itemIds[i];
                index++;
            }
        }
        return activeIds;
    }

    /// @notice Returns detailed information for all items.
    struct ItemDetail {
        uint256 itemId;
        uint256 price;
        uint256 totalSupply;
        uint256 sold;
        ProductType productType;
        bool active;
    }

    /// @notice Returns detailed information for all items.
    function getAllItems() external view returns (ItemDetail[] memory) {
        ItemDetail[] memory details = new ItemDetail[](itemIds.length);
        for (uint256 i = 0; i < itemIds.length; i++) {
            uint256 id = itemIds[i];
            Item storage it = items[id];
            details[i] = ItemDetail({
                itemId: id,
                price: it.price,
                totalSupply: it.totalSupply,
                sold: it.sold,
                productType: it.productType,
                active: it.active
            });
        }
        return details;
    }

    // =============================================================
    // PURCHASE FUNCTION (Open to All, With Signature Verification)
    // =============================================================
    /// @notice Purchase an item (user pays in BP tokens).
    /// The payment is split into three portions:
    ///  - buyback portion sent to buybackWallet (hook),
    ///  - creator portion sent to creatorWallet,
    ///  - treasury portion sent to blueprintWallet.
    /// @param itemId The ID of the item to purchase.
    /// @param nonce A unique number to prevent replay attacks.
    /// @param signature The EIP-712 signature produced by an account with SIGNER_ROLE.
    function purchaseItem(uint256 itemId, uint256 nonce, bytes calldata signature)
        external
        nonReentrant
        whenNotPaused
    {
        // Build the purchase request.
        PurchaseRequest memory request =
            PurchaseRequest({itemId: itemId, nonce: nonce, buyer: msg.sender});
        // Compute the EIP-712 digest.
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(PURCHASE_REQUEST_TYPEHASH, request.itemId, request.nonce, request.buyer)
            )
        );
        // Recover the signer.
        address recoveredSigner = ECDSA.recover(digest, signature);
        if (!hasRole(SIGNER_ROLE, recoveredSigner)) revert BLUEPRINT_STOREFRONT__InvalidSignature();
        if (usedNonces[nonce]) revert BLUEPRINT_STOREFRONT__NonceAlreadyUsed();
        usedNonces[nonce] = true;

        // Check that the item exists, is active, and has remaining supply.
        if (!items[itemId].exists) revert BLUEPRINT_STOREFRONT__ItemDoesNotExist();
        if (!items[itemId].active) revert BLUEPRINT_STOREFRONT__ItemNotActive();
        if (getRemainingSupply(itemId) == 0) revert BLUEPRINT_STOREFRONT__ItemSoldOut();
        if (hasClaimed[itemId][msg.sender]) revert BLUEPRINT_STOREFRONT__AlreadyPurchased();

        // Transfer payment tokens from the buyer.
        uint256 price = items[itemId].price;
        paymentToken.safeTransferFrom(msg.sender, address(this), price);

        // Mark the item as purchased.
        hasClaimed[itemId][msg.sender] = true;
        items[itemId].sold += 1;

        // Split funds among the distribution wallets.
        uint256 buybackAmount = (price * buybackBps) / 10000;
        uint256 creatorAmount = (price * creatorBps) / 10000;
        uint256 treasuryAmount = price - buybackAmount - creatorAmount;

        paymentToken.safeTransfer(buybackWallet, buybackAmount);
        paymentToken.safeTransfer(creatorWallet, creatorAmount);
        paymentToken.safeTransfer(blueprintWallet, treasuryAmount);

        emit ItemPurchased(itemId, msg.sender, price);
    }

    // =============================================================
    // EMERGENCY FUNCTION
    // =============================================================
    /// @notice Allows an admin to withdraw any ERC20 tokens stuck in the contract.
    /// @param tokenAddress The address of the ERC20 token to withdraw.
    /// @param amount The amount of tokens to withdraw.
    function emergencyWithdraw(address tokenAddress, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        ERC20Upgradeable token = ERC20Upgradeable(tokenAddress);
        token.safeTransfer(msg.sender, amount);
        emit EmergencyWithdrawal(tokenAddress, amount);
    }

    /// @notice Authorizes an upgrade to a new contract implementation
    /// @dev Overrides the UUPSUpgradeable internal function with access control.
    /// @param newImplementation Address of the new contract implementation
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}
}
