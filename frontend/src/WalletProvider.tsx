import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from "react";
import type { EIP1193Provider } from "viem";
import { arcTestnet } from "./chain";
import {
  connectWallet,
  discoverWallets,
  readWalletSession,
  switchToArc,
  type DiscoveredWallet,
  type WalletSession,
} from "./wallet";

type WalletStatus = "discovering" | "disconnected" | "connecting" | "connected" | "wrong-chain";
type WalletContextValue = {
  wallets: DiscoveredWallet[];
  session?: WalletSession;
  status: WalletStatus;
  error?: string;
  connect(wallet?: DiscoveredWallet): Promise<void>;
  disconnect(): void;
  switchNetwork(): Promise<void>;
};

const WalletContext = createContext<WalletContextValue | undefined>(undefined);
const selectedWalletKey = "revline:selected-wallet";

type EventProvider = EIP1193Provider & {
  on?: (event: "accountsChanged" | "chainChanged", listener: () => void) => void;
  removeListener?: (event: "accountsChanged" | "chainChanged", listener: () => void) => void;
};

function message(cause: unknown): string {
  const text = cause instanceof Error ? cause.message : "Unable to connect wallet";
  if (/user rejected|rejected the request|denied/i.test(text)) return "Wallet request rejected.";
  return text;
}

export function WalletProvider({ children }: { children: ReactNode }) {
  const [wallets, setWallets] = useState<DiscoveredWallet[]>([]);
  const [selected, setSelected] = useState<DiscoveredWallet>();
  const [session, setSession] = useState<WalletSession>();
  const [status, setStatus] = useState<WalletStatus>("discovering");
  const [error, setError] = useState<string>();

  const refresh = useCallback(async (wallet: DiscoveredWallet) => {
    const accounts = await wallet.provider.request({ method: "eth_accounts" }) as string[];
    if (!accounts[0]) {
      setSession(undefined);
      setStatus("disconnected");
      return;
    }
    const chainHex = await wallet.provider.request({ method: "eth_chainId" }) as string;
    if (Number.parseInt(chainHex, 16) !== arcTestnet.id) {
      setSession(undefined);
      setStatus("wrong-chain");
      setError("Switch this wallet to Arc Testnet.");
      return;
    }
    setSession(await readWalletSession(wallet));
    setStatus("connected");
    setError(undefined);
  }, []);

  useEffect(() => {
    discoverWallets().then(async (found) => {
      setWallets(found);
      const stored = localStorage.getItem(selectedWalletKey);
      const ordered = [...found].sort((a) => a.id === stored ? -1 : 1);
      for (const wallet of ordered) {
        const accounts = await wallet.provider.request({ method: "eth_accounts" }) as string[];
        if (!accounts[0]) continue;
        setSelected(wallet);
        await refresh(wallet);
        return;
      }
      setStatus("disconnected");
    }).catch((cause) => {
      setStatus("disconnected");
      setError(message(cause));
    });
  }, [refresh]);

  useEffect(() => {
    const provider = selected?.provider as EventProvider | undefined;
    if (!provider?.on) return;
    const update = () => { if (selected) void refresh(selected); };
    provider.on("accountsChanged", update);
    provider.on("chainChanged", update);
    return () => {
      provider.removeListener?.("accountsChanged", update);
      provider.removeListener?.("chainChanged", update);
    };
  }, [refresh, selected]);

  const connect = async (wallet = wallets[0]) => {
    if (!wallet) {
      setError("Install or enable an injected wallet to continue.");
      return;
    }
    setStatus("connecting");
    setError(undefined);
    try {
      const next = await connectWallet(wallet);
      setSelected(wallet);
      setSession(next);
      setStatus("connected");
      localStorage.setItem(selectedWalletKey, wallet.id);
    } catch (cause) {
      setStatus("disconnected");
      setError(message(cause));
    }
  };

  const disconnect = () => {
    setSession(undefined);
    setSelected(undefined);
    setStatus("disconnected");
    setError(undefined);
    localStorage.removeItem(selectedWalletKey);
  };

  const switchNetwork = async () => {
    if (!selected) return;
    setStatus("connecting");
    try {
      await switchToArc(selected.provider);
      await refresh(selected);
    } catch (cause) {
      setStatus("wrong-chain");
      setError(message(cause));
    }
  };

  return <WalletContext.Provider value={{ wallets, session, status, error, connect, disconnect, switchNetwork }}>{children}</WalletContext.Provider>;
}

export function useWallet() {
  const value = useContext(WalletContext);
  if (!value) throw new Error("useWallet must be used inside WalletProvider");
  return value;
}
