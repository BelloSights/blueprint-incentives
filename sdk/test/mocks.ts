import { Address, parseEther } from "viem";
import {
  blueprintTokenContract,
  factoryContract,
  Incentive,
  TOKEN_TYPES,
  walletClient,
} from "../src/viem";

// Test configuration from .env
export const QUEST_ID = 1n;
export const TEST_TITLE = "Base Sepolia Quest";
export const TEST_COMMUNITIES = ["base-community"];
export const TEST_TAGS = ["DeFi", "Base"];

// Total funding amounts
export const TOTAL_NATIVE = parseEther("0.01");
export const TOTAL_ERC20 = parseEther("10");

// Per-user reward amounts
export const ERC20_TOKEN = blueprintTokenContract.address;
export const REWARD_NATIVE = parseEther("0.001");
export const REWARD_ERC20 = parseEther("1");
export const RAKE_BPS = 2500n; // 25%

export const TEST_CUBE_DATA: Incentive = {
  questId: QUEST_ID,
  nonce: BigInt(Date.now()),
  toAddress: walletClient.account.address,
  walletProvider: "zerion",
  embedOrigin: "https://bp.fun",
  transactions: [
    {
      txHash:
        "0x4010f0412ece7c96dbffb2ba622b778b008a115f593a933dc75d1208bf9d49ce",
      networkChainId: String(walletClient.chain.id),
    },
  ],
  reward: {
    tokenAddress: ERC20_TOKEN,
    chainId: BigInt(walletClient.chain.id),
    amount: REWARD_ERC20,
    tokenId: 0n,
    tokenType: TOKEN_TYPES.ERC20,
    rakeBps: RAKE_BPS,
    factoryAddress: factoryContract.address,
  },
};

// Unique item ID for testing
export const TEST_ITEM_ID = 1001n;
export const TEST_ITEM_PRODUCT_TYPE = 0;
export const TEST_ITEM_NAME = "Blueprint T-Shirt";
export const TEST_ITEM_METADATA = "ipfs://item-metadata";
export const TEST_ITEM_PRICE = parseEther("0.05"); // Price in ETH
export const TEST_ITEM_SUPPLY = 100n;
export const TEST_PURCHASE_LIMIT = 2n;
export const CREATOR_ADDRESS = walletClient.account.address;

// Define the purchase structure for storefront purchases
export type BPStorefrontPurchase = {
  itemId: bigint;
  nonce: bigint;
  buyer: Address;
  quantity: bigint;
  paymentMethod: string;
  metadata: string;
};

// Test purchase data example
export const TEST_PURCHASE_DATA: BPStorefrontPurchase = {
  itemId: TEST_ITEM_ID,
  nonce: BigInt(Date.now()),
  buyer: walletClient.account.address,
  quantity: 1n,
  paymentMethod: "ETH",
  metadata: "ipfs://purchase-metadata",
};
