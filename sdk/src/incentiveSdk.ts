import { Address, PublicClient, WalletClient } from "viem";
import { escrowAbi, factoryAbi } from "../abis";
import { factoryContract, Incentive, incentiveContract } from "./viem";

export class IncentiveSDK {
  private publicClient: PublicClient;
  private walletClient: WalletClient;

  constructor(publicClient: PublicClient, walletClient: WalletClient) {
    this.publicClient = publicClient;
    this.walletClient = walletClient;
  }

  // Factory Methods
  async createEscrow(
    questId: bigint,
    whitelistedTokens: Address[],
    treasury: Address
  ) {
    const { address, abi, chain } = factoryContract;
    const account = this.walletClient.account?.address;
    if (!account) throw new Error("Wallet account not available");

    // Call createEscrow with the caller as creator
    const escrowIdTx = await this.walletClient.writeContract({
      address,
      abi,
      chain,
      account,
      functionName: "createEscrow",
      args: [account, whitelistedTokens, treasury],
    });
    // (Assume the returned value is the escrow ID.)
    const escrowId = escrowIdTx as unknown as bigint;

    // Register the quest with the new escrow ID
    await this.walletClient.writeContract({
      address,
      abi,
      chain,
      account,
      functionName: "registerQuest",
      args: [questId, escrowId],
    });

    return escrowId;
  }

  async getEscrowAddress(questId: bigint): Promise<Address> {
    // First, retrieve the escrow ID for this quest
    const escrowId = await this.publicClient.readContract({
      ...factoryContract,
      functionName: "s_questToEscrow",
      args: [questId],
    });
    // Then, get the escrow info using that escrow ID
    const escrowInfo = await this.publicClient.readContract({
      ...factoryContract,
      functionName: "s_escrows",
      args: [escrowId],
    });
    return escrowInfo[1];
  }

  async distributeRewards(
    questId: bigint,
    token: Address,
    to: Address,
    amount: bigint,
    rewardTokenId: bigint,
    tokenType: number,
    rakeBps: bigint
  ) {
    const { address, abi, chain } = factoryContract;
    const account = this.walletClient.account ?? null;
    return this.walletClient.writeContract({
      address,
      abi,
      chain,
      account,
      functionName: "distributeRewards",
      args: [questId, token, to, amount, rewardTokenId, tokenType, rakeBps],
    });
  }

  // Escrow Methods
  async getEscrowBalance(questId: bigint): Promise<bigint> {
    const escrow = await this.getEscrowContract(questId);
    const balance = await this.publicClient.readContract({
      ...escrow,
      functionName: "escrowNativeBalance",
    });
    return balance as bigint;
  }

  async withdrawFromEscrow(
    questId: bigint,
    to: Address,
    token: Address,
    tokenId: bigint,
    tokenType: number,
    overrides: Record<string, any> = {}
  ) {
    const { address, chain } = factoryContract;
    const account = this.walletClient.account ?? null;
    return this.walletClient.writeContract({
      address,
      abi: [...factoryAbi, ...escrowAbi],
      chain,
      account,
      functionName: "withdrawFunds",
      args: [questId, to, token, tokenId, tokenType],
      ...overrides,
    });
  }

  // Incentive Methods
  async initializeQuest(
    questId: bigint,
    communities: string[],
    title: string,
    difficulty: number,
    questType: number,
    tags: string[]
  ) {
    if (!this.walletClient.account) {
      throw new Error("Wallet account not available");
    }
    console.log("Wallet address:", this.walletClient.account.address);

    // Verify and grant role using the incentive contract
    const account = this.walletClient.account.address;
    const SIGNER_ROLE = await this.publicClient.readContract({
      ...incentiveContract,
      functionName: "SIGNER_ROLE",
    });
    console.log("SIGNER_ROLE", SIGNER_ROLE);

    // Check if the account already has the role
    const hasRole = await this.publicClient.readContract({
      ...incentiveContract,
      functionName: "hasRole",
      args: [SIGNER_ROLE, account],
    });
    console.log("hasRole", hasRole);

    if (!hasRole) {
      await this.grantRole(account);
      // Wait briefly for role propagation
      await new Promise((resolve) => setTimeout(resolve, 2000));
    }

    // Initialize the quest
    return this.walletClient.writeContract({
      ...incentiveContract,
      account: this.walletClient.account,
      functionName: "initializeQuest",
      args: [questId, communities, title, difficulty, questType, tags],
    });
  }

  async claimReward(incentiveData: Incentive, signature: `0x${string}`) {
    if (!this.walletClient.account) {
      throw new Error("Wallet account not available");
    }
    // New claimReward is nonpayable so we do not send native value
    return this.walletClient.writeContract({
      ...incentiveContract,
      abi: [...incentiveContract.abi, ...factoryAbi, ...escrowAbi],
      account: this.walletClient.account,
      functionName: "claimReward",
      args: [incentiveData, signature],
    });
  }

  async isQuestActive(questId: bigint): Promise<boolean> {
    const active = await this.publicClient.readContract({
      ...incentiveContract,
      functionName: "isQuestActive",
      args: [questId],
    });
    return active as boolean;
  }

  // Helper Methods
  async getFactoryContract() {
    return factoryContract;
  }

  async getCubeContract() {
    return incentiveContract;
  }

  async getEscrowContract(questId: bigint) {
    const escrowId = await this.publicClient.readContract({
      ...factoryContract,
      functionName: "s_questToEscrow",
      args: [questId],
    });
    const escrowInfo = await this.publicClient.readContract({
      ...factoryContract,
      functionName: "s_escrows",
      args: [escrowId],
    });
    return {
      address: escrowInfo[1],
      abi: escrowAbi,
    };
  }

  async unpublishQuest(questId: bigint) {
    const { address, abi, chain } = incentiveContract;
    const account = this.walletClient.account ?? null;
    return this.walletClient.writeContract({
      address,
      abi,
      chain,
      account,
      functionName: "unpublishQuest",
      args: [questId],
    });
  }

  async generateCubeSignature(incentiveData: Incentive) {
    if (!this.walletClient.account) {
      throw new Error("Wallet account not available");
    }
    const chainId = await this.publicClient.getChainId();

    // Define the EIP‑712 domain and types for the new IncentiveData structure
    const domain = {
      name: "BLUEPRINT",
      version: "1",
      chainId: chainId,
      verifyingContract: incentiveContract.address,
    };

    const types = {
      IncentiveData: [
        { name: "questId", type: "uint256" },
        { name: "nonce", type: "uint256" },
        { name: "toAddress", type: "address" },
        { name: "walletProvider", type: "string" },
        { name: "embedOrigin", type: "string" },
        { name: "transactions", type: "TransactionData[]" },
        { name: "reward", type: "RewardData" },
      ],
      TransactionData: [
        { name: "txHash", type: "string" },
        { name: "networkChainId", type: "string" },
      ],
      RewardData: [
        { name: "tokenAddress", type: "address" },
        { name: "chainId", type: "uint256" },
        { name: "amount", type: "uint256" },
        { name: "tokenId", type: "uint256" },
        { name: "tokenType", type: "uint8" },
        { name: "rakeBps", type: "uint256" },
        { name: "factoryAddress", type: "address" },
      ],
    };

    return this.walletClient.signTypedData({
      account: this.walletClient.account,
      domain,
      types,
      primaryType: "IncentiveData",
      message: incentiveData,
    });
  }

  async grantRole(account: Address) {
    if (!this.walletClient.account) {
      throw new Error("Wallet account not available");
    }
    const SIGNER_ROLE = await this.publicClient.readContract({
      ...incentiveContract,
      functionName: "SIGNER_ROLE",
    });
    console.log("SIGNER_ROLE", SIGNER_ROLE);
    return this.walletClient.writeContract({
      ...incentiveContract,
      account: this.walletClient.account,
      functionName: "grantRole",
      args: [SIGNER_ROLE, account],
    });
  }
}
