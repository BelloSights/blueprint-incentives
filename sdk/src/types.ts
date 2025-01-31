import { GetContractReturnType, PublicClient, WalletClient } from "viem";
import { cubeAbi, escrowAbi, factoryAbi } from "../abis";

export type CubeContract = GetContractReturnType<
  typeof cubeAbi,
  PublicClient | WalletClient
> & {
  publicClient?: PublicClient;
};
export type EscrowContract = GetContractReturnType<
  typeof escrowAbi,
  PublicClient | WalletClient
> & {
  publicClient?: PublicClient;
};
export type FactoryContract = GetContractReturnType<typeof factoryAbi, PublicClient | WalletClient> & {
  publicClient?: PublicClient;
};
