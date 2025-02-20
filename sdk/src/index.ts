import "dotenv/config";
import { IncentiveSDK } from "./incentiveSdk";
import { StorefrontSDK } from "./storefrontSdk";
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
  storefrontContract,
  walletClient,
} from "./viem";

export {
  factoryContract,
  incentiveContract,
  IncentiveSDK,
  publicClient,
  storefrontContract,
  StorefrontSDK,
  walletClient,
  type EscrowContract,
  type FactoryContract,
  type IncentiveContract,
  type StorefrontContract
};

