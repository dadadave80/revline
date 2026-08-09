import {
  createPublicClient,
  createWalletClient,
  custom,
  getAddress,
  http,
  type Address,
  type EIP1193Provider,
} from "viem";
import { arcTestnet } from "./chain";

declare global {
  interface Window {
    ethereum?: EIP1193Provider;
  }
}

const arcChainId = `0x${arcTestnet.id.toString(16)}`;

export const publicClient = createPublicClient({
  chain: arcTestnet,
  transport: http(),
});

function ethereum(): EIP1193Provider {
  if (!window.ethereum) throw new Error("An injected wallet is required");
  return window.ethereum;
}

function hasErrorCode(error: unknown, code: number): boolean {
  return typeof error === "object" && error !== null && "code" in error && error.code === code;
}

export async function ensureArcNetwork(): Promise<void> {
  const provider = ethereum();

  try {
    await provider.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: arcChainId }],
    });
  } catch (error) {
    if (!hasErrorCode(error, 4902)) throw error;

    await provider.request({
      method: "wallet_addEthereumChain",
      params: [{
        chainId: arcChainId,
        chainName: arcTestnet.name,
        nativeCurrency: arcTestnet.nativeCurrency,
        rpcUrls: arcTestnet.rpcUrls.default.http,
        blockExplorerUrls: [arcTestnet.blockExplorers.default.url],
      }],
    });

    await provider.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: arcChainId }],
    });
  }
}

export async function connectWallet() {
  const provider = ethereum();
  const accounts = await provider.request({ method: "eth_requestAccounts" }) as string[];
  const account = accounts[0];
  if (!account) throw new Error("Wallet returned no account");

  await ensureArcNetwork();

  return {
    account: getAddress(account) as Address,
    walletClient: createWalletClient({
      chain: arcTestnet,
      transport: custom(provider),
    }),
  };
}
