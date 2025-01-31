import { Address, PublicClient, WalletClient } from "viem";
import { escrowAbi, factoryAbi } from "../abis";
import { BPCUBE, cubeContract, factoryContract } from "./viem";

export class CubeSDK {
  private publicClient: PublicClient;
  private walletClient: WalletClient;

  constructor(publicClient: PublicClient, walletClient: WalletClient) {
    this.publicClient = publicClient;
    this.walletClient = walletClient;
  }

  // Factory Methods
  async createEscrow(
    questId: bigint,
    admin: Address,
    whitelistedTokens: Address[],
    treasury: Address
  ) {
    const { address, abi, chain } = factoryContract;
    const account = this.walletClient.account ?? null;
    return this.walletClient.writeContract({
      address,
      abi,
      chain,
      account,
      functionName: "createEscrow",
      args: [questId, admin, whitelistedTokens, treasury],
    });
  }

  async getEscrowAddress(questId: bigint): Promise<Address> {
    const address = await this.publicClient.readContract({
      ...factoryContract,
      functionName: "s_escrows",
      args: [questId],
    });
    return address as Address;
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
      abi: [
        ...factoryAbi,
        ...escrowAbi,
      ],
      chain,
      account,
      functionName: "withdrawFunds",
      args: [questId, to, token, tokenId, tokenType],
      ...overrides,
    });
  }

  // Cube Methods
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
    console.log(
      "this.walletClient.account.address",
      this.walletClient.account.address
    );

    // Verify and grant role using factory contract
    const account = this.walletClient.account.address;
    const SIGNER_ROLE = await this.publicClient.readContract({
      ...cubeContract,
      functionName: "SIGNER_ROLE",
    });
    console.log("SIGNER_ROLE", SIGNER_ROLE);

    // Check if account already has role
    const hasRole = await this.publicClient.readContract({
      ...cubeContract,
      functionName: "hasRole",
      args: [SIGNER_ROLE, account],
    });

    console.log("hasRole", hasRole);

    if (!hasRole) {
      await this.grantRole(account);
      // Wait for role propagation
      await new Promise((resolve) => setTimeout(resolve, 2000));
    }

    // Proceed with initialization
    return this.walletClient.writeContract({
      ...cubeContract,
      account: this.walletClient.account,
      functionName: "initializeQuest",
      args: [questId, communities, title, difficulty, questType, tags],
    });
  }

  async mintCube(cubeData: BPCUBE, signature: `0x${string}`) {
    if (!this.walletClient.account) {
      throw new Error("Wallet account not available");
    }
    // simulate transactions first
    // const tx = await this.publicClient.simulateContract({
    //   ...cubeContract,
    //   abi: [
    //     ...cubeContract.abi,
    //     ...factoryAbi,
    //     ...escrowAbi,
    //   ],
    //   functionName: "mintCube",
    //   args: [cubeData, signature],
    //   value: cubeData.isNative ? cubeData.price : 0n,
    //   gas: 5_000_000n,
    // });
    // check if tx causes issues

    return this.walletClient.writeContract({
      ...cubeContract,
      abi: [
        ...cubeContract.abi,
        ...factoryAbi,
        ...escrowAbi,
      ],
      account: this.walletClient.account,
      functionName: "mintCube",
      args: [cubeData, signature],
      value: cubeData.isNative ? cubeData.price : 0n,
      gas: 5_000_000n,
    });
  }

  async isQuestActive(questId: bigint): Promise<boolean> {
    const active = await this.publicClient.readContract({
      ...cubeContract,
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
    return cubeContract;
  }

  async getEscrowContract(questId: bigint) {
    const escrowAddress = await this.publicClient.readContract({
      ...factoryContract,
      functionName: "s_escrows",
      args: [questId],
    });
    return {
      address: escrowAddress as Address,
      abi: escrowAbi,
    };
  }

  async unpublishQuest(questId: bigint) {
    const { address, abi, chain } = cubeContract;
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

  async generateCubeSignature(cubeData: BPCUBE) {
    if (!this.walletClient.account) {
      throw new Error("Wallet account not available");
    }

    const chainId = await this.publicClient.getChainId();

    // Define EIP-712 domain and types
    const domain = {
      name: "BLUEPRINT",
      version: "1",
      chainId: chainId,
      verifyingContract: cubeContract.address,
    };

    const types = {
      CubeData: [
        { name: "questId", type: "uint256" },
        { name: "nonce", type: "uint256" },
        { name: "price", type: "uint256" },
        { name: "isNative", type: "bool" },
        { name: "toAddress", type: "address" },
        { name: "walletProvider", type: "string" },
        { name: "tokenURI", type: "string" },
        { name: "embedOrigin", type: "string" },
        { name: "transactions", type: "TransactionData[]" },
        { name: "recipients", type: "FeeRecipient[]" },
        { name: "reward", type: "RewardData" },
      ],
      TransactionData: [
        { name: "txHash", type: "string" },
        { name: "networkChainId", type: "string" },
      ],
      FeeRecipient: [
        { name: "recipient", type: "address" },
        { name: "BPS", type: "uint16" },
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

    // Use signTypedData instead of manual hashing
    return this.walletClient.signTypedData({
      account: this.walletClient.account,
      domain,
      types,
      primaryType: "CubeData",
      message: cubeData,
    });
  }

  async grantRole(account: Address) {
    if (!this.walletClient.account) {
      throw new Error("Wallet account not available");
    }
    const SIGNER_ROLE = await this.publicClient.readContract({
      ...cubeContract,
      functionName: "SIGNER_ROLE",
    });

    console.log("SIGNER_ROLE", SIGNER_ROLE);

    return this.walletClient.writeContract({
      ...cubeContract,
      account: this.walletClient.account,
      functionName: "grantRole",
      args: [SIGNER_ROLE, account],
    });
  }
}
