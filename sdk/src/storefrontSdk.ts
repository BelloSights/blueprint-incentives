import { Address, PublicClient, WalletClient } from "viem";
import { storefrontContract } from "./viem";

// Define the purchase data structure for the storefront
export type BPStorefrontPurchase = {
  itemId: bigint;
  nonce: bigint;
  buyer: Address;
  quantity: bigint;
  paymentMethod: string;
  metadata: string;
};

export class StorefrontSDK {
  private publicClient: PublicClient;
  private walletClient: WalletClient;

  constructor(publicClient: PublicClient, walletClient: WalletClient) {
    this.publicClient = publicClient;
    this.walletClient = walletClient;
  }

  // List a new item for sale using the "setItem" function
  async setItem(
    itemId: bigint,
    price: bigint,
    totalSupply: bigint,
    productType: number,
    active: boolean
  ) {
    const { address, abi, chain } = storefrontContract;
    const account = this.walletClient.account?.address;
    if (!account) throw new Error("Wallet account not available");
    return this.walletClient.writeContract({
      address,
      abi,
      chain,
      account,
      functionName: "setItem",
      args: [itemId, price, totalSupply, productType, active],
    });
  }

  // Update an existing item (using "updateItems" with single‑element arrays)
  async updateItem(
    itemId: bigint,
    price: bigint,
    totalSupply: bigint,
    active: boolean
  ) {
    const { address, abi, chain } = storefrontContract;
    const account = this.walletClient.account?.address;
    if (!account) throw new Error("Wallet account not available");
    return this.walletClient.writeContract({
      address,
      abi,
      chain,
      account,
      functionName: "updateItems",
      args: [[itemId], [price], [totalSupply], [active]],
    });
  }

  // Retrieve item details by calling the "items" mapping
  async getItemDetails(itemId: bigint): Promise<any> {
    return this.publicClient.readContract({
      ...storefrontContract,
      functionName: "items",
      args: [itemId],
    });
  }

  // Purchase an item using a signed BPStorefrontPurchase struct.
  // The storefront contract's purchaseItem function expects (itemId, nonce, signature)
  async purchaseItem(
    purchaseData: BPStorefrontPurchase,
    signature: `0x${string}`,
    overrides: Record<string, any> = {}
  ) {
    const { address, abi, chain } = storefrontContract;
    if (!this.walletClient.account)
      throw new Error("Wallet account not available");
    return this.walletClient.writeContract({
      address,
      abi,
      chain,
      account: this.walletClient.account,
      functionName: "purchaseItem",
      args: [purchaseData.itemId, purchaseData.nonce, signature],
      ...overrides,
    });
  }

  // Emergency withdrawal to recover tokens stuck in the contract
  async emergencyWithdraw(tokenAddress: Address, amount: bigint) {
    const { address, abi, chain } = storefrontContract;
    if (!this.walletClient.account)
      throw new Error("Wallet account not available");
    return this.walletClient.writeContract({
      address,
      abi,
      chain,
      account: this.walletClient.account,
      functionName: "emergencyWithdraw",
      args: [tokenAddress, amount],
    });
  }

  // Generate an EIP‑712 signature for a storefront purchase
  async generatePurchaseSignature(
    purchaseData: BPStorefrontPurchase
  ): Promise<`0x${string}`> {
    if (!this.walletClient.account)
      throw new Error("Wallet account not available");
    const chainId = await this.publicClient.getChainId();

    const domain = {
      name: "BLUEPRINT_STORE",
      version: "1",
      chainId: chainId,
      verifyingContract: storefrontContract.address,
    };

    const types = {
      BPStorefrontPurchase: [
        { name: "itemId", type: "uint256" },
        { name: "nonce", type: "uint256" },
        { name: "buyer", type: "address" },
        { name: "quantity", type: "uint256" },
        { name: "paymentMethod", type: "string" },
        { name: "metadata", type: "string" },
      ],
    };

    return this.walletClient.signTypedData({
      account: this.walletClient.account,
      domain,
      types,
      primaryType: "BPStorefrontPurchase",
      message: purchaseData,
    });
  }
}
