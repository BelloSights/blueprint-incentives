import "dotenv/config";
import { IncentiveSDK } from "./incentiveSdk";
import {
  EscrowContract,
  FactoryContract,
  IncentiveContract,
  StorefrontContract,
} from "./types";
import {
  factoryContract,
  incentiveContract,
  publicClient,
  walletClient
} from "./viem";

export {
  factoryContract,
  incentiveContract,
  IncentiveSDK,
  publicClient,
  walletClient,
  type EscrowContract,
  type FactoryContract,
  type IncentiveContract,
  type StorefrontContract
};

