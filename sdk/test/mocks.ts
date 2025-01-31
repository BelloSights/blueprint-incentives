import { parseEther } from "viem";
import {
  BPCUBE,
  factoryContract,
  TOKEN_TYPES,
  walletClient,
} from "../src/viem";

// Test configuration from .env
export const QUEST_ID = 1n;
export const TEST_TITLE = "Base Sepolia Quest";
export const TEST_COMMUNITIES = ["base-community"];
export const TEST_TAGS = ["DeFi", "Base"];
export const TREASURY = "0x5fF6AD4ee6997C527cf9D6F2F5e82E68BF775649";

// Token addresses on Base Sepolia
export const ERC20_TOKEN = "0xC213E15FC6071620e3633432F5A08D936Ecc0846";
export const NFT_TOKEN = "0x2bBadb5d5b9A7394fE422fA26EC1152D5F32e4d4";
export const NFT_ID = 2n;
export const L3_TOKEN = ERC20_TOKEN;

// Total funding amounts
export const TOTAL_NATIVE = parseEther("0.01");
export const TOTAL_ERC20 = parseEther("10"); // 20 tokens with 18 decimals

// Per-user reward amounts
export const REWARD_NATIVE = parseEther("0.001");
export const REWARD_ERC20 = parseEther("1");
export const RAKE_BPS = 2500n; // 25%
export const CUBE_PRICE = parseEther("0.0001");

export const TEST_CUBE_DATA: BPCUBE = {
  questId: QUEST_ID,
  nonce: BigInt(Date.now()),
  price: CUBE_PRICE,
  isNative: true,
  toAddress: walletClient.account.address,
  walletProvider: "zerion",
  tokenURI: "ipfs://test",
  embedOrigin: "https://bp.fun",
  transactions: [
    {
      txHash:
        "0x4010f0412ece7c96dbffb2ba622b778b008a115f593a933dc75d1208bf9d49ce",
      networkChainId: String(walletClient.chain.id),
    },
  ],
  recipients: [
    { recipient: walletClient.account.address, BPS: Number(RAKE_BPS) },
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