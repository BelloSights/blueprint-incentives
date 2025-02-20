import dotenv from "dotenv";
import path from "path";
import {
  Address,
  createPublicClient,
  createWalletClient,
  defineChain,
  http,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { blueprintStorefrontAbi } from "../abis/blueprintStorefrontAbi";
import { blueprintTokenAbi } from "../abis/blueprintTokenAbi";
import { factoryAbi } from "../abis/factoryAbi";
import { incentiveAbi } from "../abis/incentiveAbi";
import { treasuryAbi } from "../abis/treasuryAbi";

dotenv.config({
  path: path.resolve(__dirname, "../../.env"),
});

export const TOKEN_TYPES = {
  ERC20: 0,
  ERC721: 1,
  ERC1155: 2,
  NATIVE: 3,
} as const;

export const QUEST_TYPES = {
  QUEST: 0,
  STREAK: 1,
} as const;

export const DIFFICULTIES = {
  BEGINNER: 0,
  INTERMEDIATE: 1,
  ADVANCED: 2,
} as const;

export type Incentive = {
  questId: bigint;
  nonce: bigint;
  toAddress: Address;
  walletProvider: string;
  embedOrigin: string;
  transactions: { txHash: string; networkChainId: string }[];
  reward: {
    tokenAddress: Address;
    chainId: bigint;
    amount: bigint;
    tokenId: bigint;
    tokenType: number;
    rakeBps: bigint;
    factoryAddress: Address;
  };
};

const PRIVATE_KEY = process.env.PRIVATE_KEY as `0x${string}`;
const BASE_SEPOLIA_RPC = process.env.BASE_SEPOLIA_RPC;
const INCENTIVE_PROXY_ADDRESS = process.env.INCENTIVE_PROXY_ADDRESS as `0x${string}`;
const FACTORY_PROXY_ADDRESS = process.env
  .FACTORY_PROXY_ADDRESS as `0x${string}`;
const STOREFRONT_PROXY_ADDRESS = process.env
  .STOREFRONT_PROXY_ADDRESS as `0x${string}`;
const BLUEPRINT_TOKEN_ADDRESS = process.env
  .BLUEPRINT_TOKEN_ADDRESS as `0x${string}`;
const TREASURY_ADDRESS = process.env.TREASURY_ADDRESS as `0x${string}`;

if (!PRIVATE_KEY) {
  throw new Error("PRIVATE_KEY is not set");
}
if (!BASE_SEPOLIA_RPC) {
  throw new Error("BASE_SEPOLIA_RPC is not set");
}
if (!TREASURY_ADDRESS) {
  throw new Error("TREASURY_ADDRESS is not set");
}
if (!INCENTIVE_PROXY_ADDRESS) {
  throw new Error("INCENTIVE_PROXY_ADDRESS is not set");
}
if (!FACTORY_PROXY_ADDRESS) {
  throw new Error("FACTORY_PROXY_ADDRESS is not set");
}
if (!STOREFRONT_PROXY_ADDRESS) {
  throw new Error("STOREFRONT_PROXY_ADDRESS is not set");
}
if (!BLUEPRINT_TOKEN_ADDRESS) {
  throw new Error("BLUEPRINT_TOKEN_ADDRESS is not set");
}

// Define Base Sepolia chain configuration
export const baseSepolia = defineChain({
  id: 84532,
  name: "Base Sepolia",
  network: "base-sepolia",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: {
      http: ["https://sepolia.base.org"],
    },
  },
  blockExplorers: {
    default: {
      name: "Basescan",
      url: "https://sepolia.basescan.org",
    },
  },
  testnet: true,
});

// Create clients
export const publicClient = createPublicClient({
  chain: baseSepolia,
  transport: http(BASE_SEPOLIA_RPC),
});

export const walletClient = createWalletClient({
  chain: baseSepolia,
  transport: http(BASE_SEPOLIA_RPC),
  account: privateKeyToAccount(PRIVATE_KEY),
});

// Contract instances
console.log("Incentive contract address:", INCENTIVE_PROXY_ADDRESS);
export const incentiveContract = {
  address: INCENTIVE_PROXY_ADDRESS,
  abi: incentiveAbi,
  chain: baseSepolia,
};

console.log("Factory contract address:", FACTORY_PROXY_ADDRESS);
export const factoryContract = {
  address: FACTORY_PROXY_ADDRESS,
  abi: factoryAbi,
  chain: baseSepolia,
};

console.log("Storefront contract address:", STOREFRONT_PROXY_ADDRESS);
export const storefrontContract = {
  address: STOREFRONT_PROXY_ADDRESS,
  abi: blueprintStorefrontAbi,
  chain: baseSepolia,
};

console.log("Blueprint token address:", BLUEPRINT_TOKEN_ADDRESS);
export const blueprintTokenContract = {
  address: BLUEPRINT_TOKEN_ADDRESS,
  abi: blueprintTokenAbi,
  chain: baseSepolia,
};

console.log("Treasury contract address:", TREASURY_ADDRESS);
export const treasuryContract = {
  address: TREASURY_ADDRESS,
  abi: treasuryAbi,
  chain: baseSepolia,
};
