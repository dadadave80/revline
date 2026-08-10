import {
  createPublicClient,
  createWalletClient,
  custom,
  getAddress,
  http,
  type Address,
  type EIP1193Provider,
  type WalletClient,
} from "viem";
import { arcTestnet } from "./chain";

declare global {
  interface Window {
    ethereum?: EIP1193Provider;
  }
}

export type DiscoveredWallet = {
  id: string;
  name: string;
  icon?: string;
  provider: EIP1193Provider;
};

export type WalletSession = {
  account: Address;
  chainId: number;
  provider: EIP1193Provider;
  walletClient: WalletClient;
  wallet: DiscoveredWallet;
};

type Eip6963Detail = {
  info: {
    uuid: string;
    name: string;
    icon: string;
  };
  provider: EIP1193Provider;
};

const arcChainId = `0x${arcTestnet.id.toString(16)}`;

export const publicClient = createPublicClient({
  chain: arcTestnet,
  transport: http(),
});

function hasErrorCode(error: unknown, code: number): boolean {
  return typeof error === "object" && error !== null && "code" in error && error.code === code;
}

export function shortAddress(address: Address): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

export function discoverWallets(): Promise<DiscoveredWallet[]> {
  if (typeof window === "undefined") return Promise.resolve([]);

  const found = new Map<string, DiscoveredWallet>();
  const onAnnounce = (event: Event) => {
    const detail = (event as CustomEvent<Eip6963Detail>).detail;
    if (!detail?.info?.uuid || !detail.provider) return;
    found.set(detail.info.uuid, {
      id: detail.info.uuid,
      name: detail.info.name || "Injected wallet",
      icon: detail.info.icon,
      provider: detail.provider,
    });
  };

  window.addEventListener("eip6963:announceProvider", onAnnounce);
  window.dispatchEvent(new Event("eip6963:requestProvider"));

  return new Promise((resolve) => {
    window.setTimeout(() => {
      window.removeEventListener("eip6963:announceProvider", onAnnounce);
      if (found.size === 0 && window.ethereum) {
        found.set("injected", { id: "injected", name: "Browser wallet", provider: window.ethereum });
      }
      resolve([...found.values()]);
    }, 150);
  });
}

export async function switchToArc(provider: EIP1193Provider): Promise<void> {
  try {
    await provider.request({ method: "wallet_switchEthereumChain", params: [{ chainId: arcChainId }] });
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
    await provider.request({ method: "wallet_switchEthereumChain", params: [{ chainId: arcChainId }] });
  }
}

export async function ensureArcNetwork(): Promise<void> {
  if (!window.ethereum) throw new Error("An injected wallet is required");
  await switchToArc(window.ethereum);
}

export async function readWalletSession(wallet: DiscoveredWallet, expectedChainId = arcTestnet.id): Promise<WalletSession> {
  const accounts = await wallet.provider.request({ method: "eth_accounts" }) as string[];
  const chainHex = await wallet.provider.request({ method: "eth_chainId" }) as string;
  const account = accounts[0];
  const chainId = Number.parseInt(chainHex, 16);
  if (!account) throw new Error("Wallet is disconnected");
  if (chainId !== expectedChainId) throw new Error("Switch your wallet to Arc Testnet to use Revline.");
  const normalized = getAddress(account) as Address;
  return {
    account: normalized,
    chainId,
    provider: wallet.provider,
    walletClient: createWalletClient({ account: normalized, chain: arcTestnet, transport: custom(wallet.provider) }),
    wallet,
  };
}

export async function connectWallet(wallet: DiscoveredWallet): Promise<WalletSession> {
  const accounts = await wallet.provider.request({ method: "eth_requestAccounts" }) as string[];
  if (!accounts[0]) throw new Error("Wallet returned no account");
  await switchToArc(wallet.provider);
  return readWalletSession(wallet);
}

export async function requireCurrentSession(session: WalletSession, expectedChainId = arcTestnet.id): Promise<WalletSession> {
  return readWalletSession(session.wallet, expectedChainId);
}
