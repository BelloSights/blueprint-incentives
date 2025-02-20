import { GetContractReturnType, PublicClient, WalletClient } from "viem";
import { escrowAbi, factoryAbi, incentiveAbi } from "../abis";
import { blueprintStorefrontAbi } from "../abis/blueprintStorefrontAbi";

export type IncentiveContract = GetContractReturnType<
  typeof incentiveAbi,
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
export type FactoryContract = GetContractReturnType<
  typeof factoryAbi,
  PublicClient | WalletClient
> & {
  publicClient?: PublicClient;
};
export type StorefrontContract = GetContractReturnType<
  typeof blueprintStorefrontAbi,
  PublicClient | WalletClient
> & {
  publicClient?: PublicClient;
};
