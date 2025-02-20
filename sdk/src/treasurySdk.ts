import { PublicClient, WalletClient } from "viem";
import { treasuryContract } from "./viem";

export class TreasurySDK {
  private publicClient: PublicClient;
  private walletClient: WalletClient;

  constructor(publicClient: PublicClient, walletClient: WalletClient) {
    this.publicClient = publicClient;
    this.walletClient = walletClient;
  }

  async donate(
    destination: string,
    token: string,
    amount: bigint
  ): Promise<`0x${string}`> {
    const account = this.walletClient.account?.address;
    if (!account) throw new Error("Wallet account not available");
    return await this.walletClient.writeContract({
      address: treasuryContract.address,
      abi: treasuryContract.abi,
      functionName: "donate",
      args: [destination as `0x${string}`, token as `0x${string}`, amount],
      chain: treasuryContract.chain,
      account,
    });
  }

  async grantRole(role: string, account: string): Promise<`0x${string}`> {
    const walletAccount = this.walletClient.account?.address;
    if (!walletAccount) throw new Error("Wallet account not available");
    return await this.walletClient.writeContract({
      address: treasuryContract.address,
      abi: treasuryContract.abi,
      functionName: "grantRole",
      args: [role as `0x${string}`, account as `0x${string}`],
      chain: treasuryContract.chain,
      account: walletAccount,
    });
  }

  async revokeRole(role: string, account: string): Promise<`0x${string}`> {
    const walletAccount = this.walletClient.account?.address;
    if (!walletAccount) throw new Error("Wallet account not available");
    return await this.walletClient.writeContract({
      address: treasuryContract.address,
      abi: treasuryContract.abi,
      functionName: "revokeRole",
      args: [role as `0x${string}`, account as `0x${string}`],
      chain: treasuryContract.chain,
      account: walletAccount,
    });
  }

  async withdrawETH(to: string, amount: bigint): Promise<`0x${string}`> {
    const walletAccount = this.walletClient.account?.address;
    if (!walletAccount) throw new Error("Wallet account not available");
    return await this.walletClient.writeContract({
      address: treasuryContract.address,
      abi: treasuryContract.abi,
      functionName: "withdrawETH",
      args: [to as `0x${string}`, amount],
      chain: treasuryContract.chain,
      account: walletAccount,
    });
  }

  async withdrawToken(
    token: string,
    to: string,
    amount: bigint
  ): Promise<`0x${string}`> {
    const walletAccount = this.walletClient.account?.address;
    if (!walletAccount) throw new Error("Wallet account not available");
    return await this.walletClient.writeContract({
      address: treasuryContract.address,
      abi: treasuryContract.abi,
      functionName: "withdrawToken",
      args: [token as `0x${string}`, to as `0x${string}`, amount],
      chain: treasuryContract.chain,
      account: walletAccount,
    });
  }
}
