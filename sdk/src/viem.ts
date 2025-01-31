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
import { cubeAbi } from "../abis/cubeAbi";
import { factoryAbi } from "../abis/factoryAbi";

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

export type BPCUBE = {
  questId: bigint;
  nonce: bigint;
  price: bigint;
  isNative: boolean;
  toAddress: Address;
  walletProvider: string;
  tokenURI: string;
  embedOrigin: string;
  transactions: { txHash: string; networkChainId: string }[];
  recipients: { recipient: Address; BPS: number }[];
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
const DEPLOYED_CUBE_PROXY_ADDRESS = process.env
  .DEPLOYED_CUBE_PROXY_ADDRESS as `0x${string}`;
const DEPLOYED_FACTORY_PROXY_ADDRESS = process.env
  .DEPLOYED_FACTORY_PROXY_ADDRESS as `0x${string}`;
if (!PRIVATE_KEY) {
  throw new Error("PRIVATE_KEY is not set");
}
if (!BASE_SEPOLIA_RPC) {
  throw new Error("BASE_SEPOLIA_RPC is not set");
}
if (!DEPLOYED_CUBE_PROXY_ADDRESS) {
  throw new Error("DEPLOYED_CUBE_PROXY_ADDRESS is not set");
}
if (!DEPLOYED_FACTORY_PROXY_ADDRESS) {
  throw new Error("DEPLOYED_FACTORY_PROXY_ADDRESS is not set");
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
console.log(DEPLOYED_CUBE_PROXY_ADDRESS);
export const cubeContract = {
  address: DEPLOYED_CUBE_PROXY_ADDRESS,
  abi: cubeAbi,
  chain: baseSepolia,
};

console.log(DEPLOYED_FACTORY_PROXY_ADDRESS);
export const factoryContract = {
  address: DEPLOYED_FACTORY_PROXY_ADDRESS,
  abi: factoryAbi,
  chain: baseSepolia,
};
