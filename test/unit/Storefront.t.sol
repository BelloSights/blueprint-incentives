// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console, Vm} from "forge-std/Test.sol";
import {BlueprintStorefront} from "../../src/BlueprintStorefront.sol";
import {MockERC20} from "../mock/MockERC20.sol";

contract StorefrontTest is Test {
    BlueprintStorefront public storefront;
    MockERC20 public mockToken;

    // Test addresses.
    address public owner = vm.addr(1);
    uint256 constant OWNER_PRIVATE_KEY = 1;
    address public buybackWallet = address(0x2);
    address public creatorWallet = address(0x3);
    address public blueprintWallet = address(0x4);
    address public user = address(0x5);

    // Constants for item details.
    uint256 constant ITEM_PRICE = 100 ether;
    uint256 constant ITEM_SUPPLY = 10;

    // Split basis points: initial splits: 80% (8000), 10% (1000), 10% (1000).
    uint256 constant INITIAL_BUYBACK_BPS = 8000;
    uint256 constant INITIAL_CREATOR_BPS = 1000;
    uint256 constant INITIAL_BLUEPRINT_BPS = 1000;

    function setUp() public {
        // Deploy mock ERC20 token and mint tokens to user.
        mockToken = new MockERC20();
        mockToken.mint(user, 500 ether);

        // Deploy BlueprintStorefront contract and initialize with admin only.
        storefront = new BlueprintStorefront();
        storefront.initialize(owner);

        // Configure the contract via admin functions.
        vm.prank(owner);
        storefront.setPaymentToken(address(mockToken));
        vm.prank(owner);
        storefront.updateSplits(INITIAL_BUYBACK_BPS, INITIAL_CREATOR_BPS, INITIAL_BLUEPRINT_BPS);
        vm.prank(owner);
        storefront.setBuybackWallet(buybackWallet);
        vm.prank(owner);
        storefront.setCreatorWallet(creatorWallet);
        vm.prank(owner);
        storefront.setBlueprintWallet(blueprintWallet);

        // Grant the SIGNER_ROLE to the owner so that owner can sign purchase requests.
        vm.prank(owner);
        storefront.addSigner(owner);

        // Approve the storefront to spend tokens on behalf of the user.
        vm.prank(user);
        mockToken.approve(address(storefront), 500 ether);
    }

    function testInitialSplits() public view {
        assertEq(storefront.buybackBps(), INITIAL_BUYBACK_BPS);
        assertEq(storefront.creatorBps(), INITIAL_CREATOR_BPS);
        assertEq(storefront.blueprintBps(), INITIAL_BLUEPRINT_BPS);
    }

    function testUpdateSplits() public {
        // Update splits to 7000, 2000, 1000 (sum = 10000).
        vm.prank(owner);
        storefront.updateSplits(7000, 2000, 1000);
        assertEq(storefront.buybackBps(), 7000);
        assertEq(storefront.creatorBps(), 2000);
        assertEq(storefront.blueprintBps(), 1000);
    }

    function testUpdateSplitsFailsWhenSumNotEqual() public {
        vm.prank(owner);
        vm.expectRevert("Splits must sum to 10000");
        storefront.updateSplits(5000, 2000, 2000); // Sum is 9000.
    }

    function testSetWallets() public {
        address newBuyback = address(0x10);
        address newCreator = address(0x11);
        address newBlueprint = address(0x12);
        vm.prank(owner);
        storefront.setBuybackWallet(newBuyback);
        vm.prank(owner);
        storefront.setCreatorWallet(newCreator);
        vm.prank(owner);
        storefront.setBlueprintWallet(newBlueprint);
        assertEq(storefront.buybackWallet(), newBuyback);
        assertEq(storefront.creatorWallet(), newCreator);
        assertEq(storefront.blueprintWallet(), newBlueprint);
    }

    function testSetWalletsFailsWithZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BlueprintStorefront.BLUEPRINT_STOREFRONT__InvalidBuybackWallet.selector
            )
        );
        storefront.setBuybackWallet(address(0));

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BlueprintStorefront.BLUEPRINT_STOREFRONT__InvalidCreatorWallet.selector
            )
        );
        storefront.setCreatorWallet(address(0));

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BlueprintStorefront.BLUEPRINT_STOREFRONT__InvalidBlueprintWallet.selector
            )
        );
        storefront.setBlueprintWallet(address(0));
    }

    function testSetPaymentToken() public {
        // Test setting a valid payment token.
        vm.prank(owner);
        storefront.setPaymentToken(address(mockToken));
        assertEq(address(storefront.paymentToken()), address(mockToken));
    }

    function testSetPaymentTokenFailsWithZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BlueprintStorefront.BLUEPRINT_STOREFRONT__InvalidPaymentTokenAddress.selector
            )
        );
        storefront.setPaymentToken(address(0));
    }

    function testSetItemAndQuery() public {
        // Owner sets an item with id 1.
        vm.prank(owner);
        storefront.setItem(
            1, ITEM_PRICE, ITEM_SUPPLY, BlueprintStorefront.ProductType.PHYSICAL, true
        );

        // Test getRemainingSupply: should be ITEM_SUPPLY.
        uint256 remaining = storefront.getRemainingSupply(1);
        assertEq(remaining, ITEM_SUPPLY);

        // Test getActiveItemIds: should contain item id 1.
        uint256[] memory activeIds = storefront.getActiveItemIds();
        assertEq(activeIds.length, 1);
        assertEq(activeIds[0], 1);

        // Test getAllItems.
        BlueprintStorefront.ItemDetail[] memory details = storefront.getAllItems();
        assertEq(details.length, 1);
        assertEq(details[0].itemId, 1);
        assertEq(details[0].price, ITEM_PRICE);
        assertEq(details[0].totalSupply, ITEM_SUPPLY);
        assertEq(details[0].sold, 0);
        assertEq(uint256(details[0].productType), uint256(BlueprintStorefront.ProductType.PHYSICAL));
        assertTrue(details[0].active);
    }

    function testBatchUpdateItems() public {
        // Owner sets two items.
        vm.prank(owner);
        storefront.setItem(1, 100 ether, 10, BlueprintStorefront.ProductType.DIGITAL, true);
        vm.prank(owner);
        storefront.setItem(2, 200 ether, 20, BlueprintStorefront.ProductType.PHYSICAL, true);

        // Batch update: change prices and supplies, deactivate item 1.
        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;
        uint256[] memory prices = new uint256[](2);
        prices[0] = 150 ether;
        prices[1] = 250 ether;
        uint256[] memory supplies = new uint256[](2);
        supplies[0] = 12;
        supplies[1] = 22;
        bool[] memory actives = new bool[](2);
        actives[0] = false;
        actives[1] = true;

        vm.prank(owner);
        storefront.updateItems(ids, prices, supplies, actives);

        // Verify updates.
        BlueprintStorefront.ItemDetail[] memory details = storefront.getAllItems();
        for (uint256 i = 0; i < details.length; i++) {
            if (details[i].itemId == 1) {
                assertEq(details[i].price, 150 ether);
                assertEq(details[i].totalSupply, 12);
                assertFalse(details[i].active);
            } else if (details[i].itemId == 2) {
                assertEq(details[i].price, 250 ether);
                assertEq(details[i].totalSupply, 22);
                assertTrue(details[i].active);
            }
        }
    }

    function testDeactivateAndReactivateItem() public {
        vm.prank(owner);
        storefront.setItem(
            1, ITEM_PRICE, ITEM_SUPPLY, BlueprintStorefront.ProductType.PHYSICAL, true
        );

        // Deactivate item 1.
        vm.prank(owner);
        storefront.deactivateItem(1);
        BlueprintStorefront.ItemDetail[] memory details = storefront.getAllItems();
        for (uint256 i = 0; i < details.length; i++) {
            if (details[i].itemId == 1) {
                assertFalse(details[i].active);
            }
        }

        // Reactivate item 1.
        vm.prank(owner);
        storefront.reactivateItem(1);
        details = storefront.getAllItems();
        for (uint256 i = 0; i < details.length; i++) {
            if (details[i].itemId == 1) {
                assertTrue(details[i].active);
            }
        }
    }

    function testPurchaseItem() public {
        // Owner sets an item.
        vm.prank(owner);
        storefront.setItem(
            1, ITEM_PRICE, ITEM_SUPPLY, BlueprintStorefront.ProductType.PHYSICAL, true
        );
        uint256 remainingBefore = storefront.getRemainingSupply(1);
        assertEq(remainingBefore, ITEM_SUPPLY);

        // --- Build a valid EIP-712 signature for the purchase request with nonce = 0 ---
        uint256 nonce0 = 0;
        uint256 itemId = 1;
        bytes32 typeHash = keccak256("PurchaseRequest(uint256 itemId,uint256 nonce,address buyer)");
        bytes32 structHash0 = keccak256(abi.encode(typeHash, itemId, nonce0, user));
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("BlueprintStorefront")),
                keccak256(bytes("1")),
                block.chainid,
                address(storefront)
            )
        );
        bytes32 digest0 = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash0));
        (uint8 v0, bytes32 r0, bytes32 s0) = vm.sign(OWNER_PRIVATE_KEY, digest0);
        bytes memory signature0 = abi.encodePacked(r0, s0, v0);

        // --- User calls purchaseItem with nonce 0 ---
        vm.prank(user);
        storefront.purchaseItem(itemId, nonce0, signature0);

        uint256 remainingAfter = storefront.getRemainingSupply(1);
        assertEq(remainingAfter, ITEM_SUPPLY - 1);

        // --- Build a valid signature for a new purchase attempt with nonce = 1 ---
        uint256 nonce1 = 1;
        bytes32 structHash1 = keccak256(abi.encode(typeHash, itemId, nonce1, user));
        bytes32 digest1 = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash1));
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(OWNER_PRIVATE_KEY, digest1);
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);

        // --- The second purchase should revert with AlreadyPurchased ---
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BlueprintStorefront.BLUEPRINT_STOREFRONT__AlreadyPurchased.selector
            )
        );
        storefront.purchaseItem(itemId, nonce1, signature1);
    }

    function testEmergencyWithdraw() public {
        // Transfer some tokens to the storefront contract.
        vm.prank(user);
        mockToken.transfer(address(storefront), 100 ether);
        uint256 contractBalance = mockToken.balanceOf(address(storefront));

        // Owner withdraws funds.
        vm.prank(owner);
        storefront.emergencyWithdraw(address(mockToken), contractBalance);
        uint256 ownerBalance = mockToken.balanceOf(owner);
        assertEq(ownerBalance, contractBalance);
    }
}
