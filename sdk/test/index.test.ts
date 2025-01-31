import console from "console";
import dotenv from "dotenv";
import path from "path";
import { erc20Abi, erc721Abi, zeroAddress } from "viem";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { CubeSDK } from "../src/sdk";
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
  L3_TOKEN,
  NFT_ID,
  NFT_TOKEN,
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

describe("Cube SDK", () => {
  let sdk: CubeSDK;
  let escrowAddress: `0x${string}`;

  beforeAll(async () => {
    sdk = new CubeSDK(publicClient, walletClient);
    // Get escrow address
    escrowAddress = await sdk.getEscrowAddress(QUEST_ID);
    console.log("escrow address:", escrowAddress);

    // Approve ERC20 tokens first
    const approveHash = await walletClient.writeContract({
      address: ERC20_TOKEN,
      abi: erc20Abi,
      functionName: "approve",
      args: [escrowAddress, TOTAL_ERC20],
    });
    await publicClient.waitForTransactionReceipt({ hash: approveHash });
    console.log("approved erc20");

    // Fund escrow with total amounts
    // const escrow = await sdk.getEscrowContract(QUEST_ID);
    // console.log("escrow contract:", escrow);

    // Fund ERC20
    const transferHash = await walletClient.writeContract({
      address: ERC20_TOKEN,
      abi: erc20Abi,
      functionName: "transfer",
      args: [escrowAddress, TOTAL_ERC20],
    });
    await publicClient.waitForTransactionReceipt({ hash: transferHash });
    console.log("funded erc20");

    // First verify NFT ownership
    const initialOwner = await publicClient.readContract({
      address: NFT_TOKEN,
      abi: erc721Abi,
      functionName: "ownerOf",
      args: [NFT_ID],
    });
    console.log("Initial NFT Owner:", initialOwner);

    if (
      initialOwner.toLowerCase() !== walletClient.account.address.toLowerCase()
    ) {
      throw new Error(
        `Test account ${walletClient.account.address} does not own NFT ${NFT_ID}`
      );
    }

    // NFT approval (standard ERC721 flow)
    // const nftApproveEscrowHash = await walletClient.writeContract({
    //   address: NFT_TOKEN,
    //   abi: erc721Abi,
    //   functionName: "approve",
    //   args: [escrowAddress, NFT_ID], // Should be (spender, tokenId)
    // });
    // await publicClient.waitForTransactionReceipt({
    //   hash: nftApproveEscrowHash,
    // });
    const nftApprovalWalletHash = await walletClient.writeContract({
      address: NFT_TOKEN,
      abi: erc721Abi,
      functionName: "approve",
      args: [walletClient.account.address, NFT_ID],
    });
    await publicClient.waitForTransactionReceipt({
      hash: nftApprovalWalletHash,
    });
    console.log("approved nft");

    // Fund NFT
    const nftTransferHash = await walletClient.writeContract({
      address: NFT_TOKEN,
      abi: erc721Abi,
      functionName: "transferFrom",
      args: [walletClient.account.address, escrowAddress, NFT_ID],
    });
    const nftTransferReceipt = await publicClient.waitForTransactionReceipt({
      hash: nftTransferHash,
    });
    console.log("NFT Transfer Status:", nftTransferReceipt.status);

    // Check balances
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

    // Check NFT ownership
    const nftOwner = await publicClient.readContract({
      address: NFT_TOKEN,
      abi: erc721Abi,
      functionName: "ownerOf",
      args: [NFT_ID],
    });
    console.log("NFT owner:", nftOwner);

    // Add after each transaction
    const preNonce = await publicClient.getTransactionCount({
      address: walletClient.account.address,
      blockTag: "pending",
    });
    console.log("Pre nonce:", preNonce);

    // Check if l3 token is set
    const cubeContract = await sdk.getCubeContract();
    const l3TokenAddress = await publicClient.readContract({
      ...cubeContract,
      functionName: "s_l3Token",
    });
    console.log("L3_TOKEN_ADDRESS", l3TokenAddress);
    if (l3TokenAddress !== L3_TOKEN) {
      const setL3TxHash = await walletClient.writeContract({
        ...cubeContract,
        functionName: "setL3TokenAddress",
        args: [L3_TOKEN],
      });
      // Wait for transaction confirmation
      await publicClient.waitForTransactionReceipt({ hash: setL3TxHash });
      console.log("L3 token set and confirmed");
    }

    // Check if treasury is set
    const currentTreasury = await publicClient.readContract({
      ...cubeContract,
      functionName: "s_treasury",
    });
    if (currentTreasury === zeroAddress) {
      if (!process.env.TREASURY_ADDRESS) {
        throw new Error(
          "TREASURY_ADDRESS is not set in the environment variables"
        );
      }
      const setTreasuryHash = await walletClient.writeContract({
        ...cubeContract,
        functionName: "setTreasury",
        args: [process.env.TREASURY_ADDRESS as `0x${string}`],
      });
      await publicClient.waitForTransactionReceipt({ hash: setTreasuryHash });
      console.log(
        "Treasury set to wallet address",
        process.env.TREASURY_ADDRESS
      );
    }

    // Add delay after setting treasury
    await new Promise((resolve) => setTimeout(resolve, 2000));

    // Add to beforeAll hook
    const factoryCubeAddress = await publicClient.readContract({
      ...factoryContract,
      functionName: "i_cube",
    });
    console.log("factoryCubeAddress", factoryCubeAddress);

    if (factoryCubeAddress !== cubeContract.address) {
      throw new Error(`
        Factory contract is pointing to wrong CUBE address:
        Expected: ${cubeContract.address}
        Actual: ${factoryCubeAddress}
      `);
    }

    // Add token to escrow whitelist
    const whitelistTx = await walletClient.writeContract({
      ...factoryContract,
      functionName: "addTokenToWhitelist",
      args: [QUEST_ID, ERC20_TOKEN],
    });
    await publicClient.waitForTransactionReceipt({ hash: whitelistTx });
    console.log("token whitelisted");

    // Add after each transaction
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

    it("should mint a new cube with valid signature", async () => {
      const signature = await sdk.generateCubeSignature(TEST_CUBE_DATA);
      const txHash = await sdk.mintCube(TEST_CUBE_DATA, signature);
      const receipt = await publicClient.waitForTransactionReceipt({
        hash: txHash,
      });
      console.log("mint cube txHash", txHash);
      console.log("mint cube receipt", receipt);
      expect(receipt.status).toBe("success");
    });
  }, 60_000);

  afterAll(async () => {
    // Unpublish quest to withdraw funds
    const unpublishTxHash = await sdk.unpublishQuest(QUEST_ID);
    const unpublishReceipt = await publicClient.waitForTransactionReceipt({
      hash: unpublishTxHash,
    });
    expect(unpublishReceipt.status).toBe("success");

    // Increase delay for state propagation
    await new Promise((resolve) => setTimeout(resolve, 5000));
    const isActive = await sdk.isQuestActive(QUEST_ID);
    expect(isActive).toBe(false);

    // Add delay between transactions
    await new Promise((resolve) => setTimeout(resolve, 2000));

    // Get current nonce for ERC20 withdrawal
    const erc20Nonce = await publicClient.getTransactionCount({
      address: walletClient.account.address,
      blockTag: "pending",
    });
    console.log("erc20Nonce", erc20Nonce);

    // Withdraw ERC20 (remove nonce parameter)
    const erc20WithdrawHash = await sdk.withdrawFromEscrow(
      QUEST_ID,
      walletClient.account.address,
      ERC20_TOKEN,
      0n,
      TOKEN_TYPES.ERC20
    );
    await publicClient.waitForTransactionReceipt({ hash: erc20WithdrawHash });

    // Get current nonce for NFT withdrawal
    const nftNonce = await publicClient.getTransactionCount({
      address: walletClient.account.address,
      blockTag: "pending",
    });
    console.log("nftNonce", nftNonce);

    // Withdraw NFT (remove nonce parameter)
    const nftWithdrawHash = await sdk.withdrawFromEscrow(
      QUEST_ID,
      walletClient.account.address,
      NFT_TOKEN,
      NFT_ID,
      TOKEN_TYPES.ERC721
    );

    const nftReceipt = await publicClient.waitForTransactionReceipt({
      hash: nftWithdrawHash,
    });
    expect(nftReceipt.status).toBe("success");

    // Verify final balance
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
