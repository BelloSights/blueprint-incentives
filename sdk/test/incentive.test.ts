import dotenv from "dotenv";
import path from "path";
import { erc20Abi, zeroAddress } from "viem";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { IncentiveSDK } from "../src/incentiveSdk";
import { TreasurySDK } from "../src/treasurySdk";
import {
  DIFFICULTIES,
  factoryContract,
  publicClient,
  QUEST_TYPES,
  TOKEN_TYPES,
  walletClient,
} from "../src/viem";
import {
  ERC20_TOKEN,
  QUEST_ID,
  TEST_COMMUNITIES,
  TEST_CUBE_DATA,
  TEST_TAGS,
  TEST_TITLE,
  TOTAL_ERC20,
} from "./mocks";

dotenv.config({
  path: path.resolve(__dirname, "../../.env"),
});

describe.skip("Incentive SDK", () => {
  let sdk: IncentiveSDK;
  let treasurySdk: TreasurySDK;
  let escrowAddress: string;

  beforeAll(async () => {
    sdk = new IncentiveSDK(publicClient, walletClient);
    treasurySdk = new TreasurySDK(publicClient, walletClient);

    // Get escrow address using the updated mapping
    escrowAddress = await sdk.getEscrowAddress(QUEST_ID);
    console.log("escrow address:", escrowAddress);

    // Approve ERC20 tokens for the escrow
    const approveHash = await walletClient.writeContract({
      address: ERC20_TOKEN,
      abi: erc20Abi,
      functionName: "approve",
      args: [escrowAddress, TOTAL_ERC20],
    });
    await publicClient.waitForTransactionReceipt({ hash: approveHash });
    console.log("approved erc20");

    // Transfer ERC20 tokens to the escrow
    const transferHash = await walletClient.writeContract({
      address: ERC20_TOKEN,
      abi: erc20Abi,
      functionName: "transfer",
      args: [escrowAddress, TOTAL_ERC20],
    });
    await publicClient.waitForTransactionReceipt({ hash: transferHash });
    console.log("funded erc20");

    // Check ERC20 balances and allowance
    const erc20Balance = await publicClient.readContract({
      address: ERC20_TOKEN,
      abi: erc20Abi,
      functionName: "balanceOf",
      args: [walletClient.account.address],
    });
    console.log("Wallet ERC20 Balance:", erc20Balance);
    const allowance = await publicClient.readContract({
      address: ERC20_TOKEN,
      abi: erc20Abi,
      functionName: "allowance",
      args: [walletClient.account.address, escrowAddress],
    });
    console.log("ERC20 Allowance:", allowance);

    // Log the transaction nonce before further actions
    const preNonce = await publicClient.getTransactionCount({
      address: walletClient.account.address,
      blockTag: "pending",
    });
    console.log("Pre nonce:", preNonce);

    // Check if treasury is set in the incentive contract
    const incentiveContract = await sdk.getCubeContract();
    const currentTreasury = await publicClient.readContract({
      ...incentiveContract,
      functionName: "s_treasury",
    });
    if (currentTreasury === zeroAddress) {
      if (!process.env.TREASURY_ADDRESS) {
        throw new Error(
          "TREASURY_ADDRESS is not set in the environment variables"
        );
      }
      const setTreasuryHash = await walletClient.writeContract({
        ...incentiveContract,
        functionName: "setTreasury",
        args: [process.env.TREASURY_ADDRESS as `0x${string}`],
      });
      await publicClient.waitForTransactionReceipt({ hash: setTreasuryHash });
      console.log("Treasury set to", process.env.TREASURY_ADDRESS);
    }

    // Delay to allow state propagation
    await new Promise((resolve) => setTimeout(resolve, 2000));

    // Verify the factory contract's incentive address
    const factoryIncentiveAddress = await publicClient.readContract({
      ...factoryContract,
      functionName: "i_incentive",
    });
    console.log("factoryIncentiveAddress", factoryIncentiveAddress);
    if (factoryIncentiveAddress !== incentiveContract.address) {
      throw new Error(`
        Factory contract is pointing to wrong Incentive address:
        Expected: ${incentiveContract.address}
        Actual: ${factoryIncentiveAddress}
      `);
    }

    // Whitelist the ERC20 token for the quest in the factory contract
    const whitelistTx = await walletClient.writeContract({
      ...factoryContract,
      functionName: "addTokenToWhitelist",
      args: [QUEST_ID, ERC20_TOKEN],
    });
    await publicClient.waitForTransactionReceipt({ hash: whitelistTx });
    console.log("ERC20 token whitelisted");

    const currentNonce = await publicClient.getTransactionCount({
      address: walletClient.account.address,
      blockTag: "pending",
    });
    console.log("Current nonce:", currentNonce);
  }, 60_000);

  describe("Quest Lifecycle", () => {
    it("should initialize a new quest", async () => {
      const txHash = await sdk.initializeQuest(
        QUEST_ID,
        TEST_COMMUNITIES,
        TEST_TITLE,
        DIFFICULTIES.INTERMEDIATE,
        QUEST_TYPES.QUEST,
        TEST_TAGS
      );
      const receipt = await publicClient.waitForTransactionReceipt({
        hash: txHash,
      });
      console.log("initialize quest txHash", txHash);
      console.log("initialize quest receipt", receipt);
      expect(receipt.status).toBe("success");

      const isActive = await sdk.isQuestActive(QUEST_ID);
      expect(isActive).toBe(true);
    });

    it("should mint a new incentive with valid signature", async () => {
      const signature = await sdk.generateCubeSignature(TEST_CUBE_DATA);
      const txHash = await sdk.claimReward(TEST_CUBE_DATA, signature);
      const receipt = await publicClient.waitForTransactionReceipt({
        hash: txHash,
      });
      console.log("mint incentive txHash", txHash);
      console.log("mint incentive receipt", receipt);
      expect(receipt.status).toBe("success");
    });
  }, 60_000);

  afterAll(async () => {
    // Unpublish the quest to enable fund withdrawal
    const unpublishTxHash = await sdk.unpublishQuest(QUEST_ID);
    const unpublishReceipt = await publicClient.waitForTransactionReceipt({
      hash: unpublishTxHash,
    });
    expect(unpublishReceipt.status).toBe("success");

    // Wait for state propagation
    await new Promise((resolve) => setTimeout(resolve, 5000));
    const isActive = await sdk.isQuestActive(QUEST_ID);
    expect(isActive).toBe(false);

    // Delay between transactions
    await new Promise((resolve) => setTimeout(resolve, 2000));

    // Get current nonce for ERC20 withdrawal
    const erc20Nonce = await publicClient.getTransactionCount({
      address: walletClient.account.address,
      blockTag: "pending",
    });
    console.log("erc20Nonce", erc20Nonce);

    // Withdraw ERC20 funds from the escrow
    const erc20WithdrawHash = await sdk.withdrawFromEscrow(
      QUEST_ID,
      walletClient.account.address,
      ERC20_TOKEN,
      0n,
      TOKEN_TYPES.ERC20
    );
    await publicClient.waitForTransactionReceipt({ hash: erc20WithdrawHash });

    // Verify the final ERC20 balance in the escrow is zero
    const escrow = await sdk.getEscrowContract(QUEST_ID);
    const finalBalance = await publicClient.readContract({
      ...escrow,
      functionName: "escrowERC20Reserves",
      args: [ERC20_TOKEN],
    });
    console.log("finalBalance", finalBalance);
    expect(finalBalance).toBe(0n);
  }, 60_000);
}, 60_000);
