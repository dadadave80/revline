import { getAddress, type Abi, type Address, type Hex, type WalletClient } from "viem";
import revlineAbiJson from "./abi/revline.json";
import { publicClient } from "./wallet";

export const revlineAbi = revlineAbiJson as Abi;
export const CANONICAL_REVLINE_ADDRESS = "0x6F06657d1cFe8598d15Ef9b8705963d1e6F7EDc4" as const;

export function getRevlineAddress(): Address {
  const configured = import.meta.env.VITE_REVLINE_ADDRESS?.trim();
  const address = !configured || configured === "0x" ? CANONICAL_REVLINE_ADDRESS : configured;
  return getAddress(address);
}

export const revlineContract = () => ({
  address: getRevlineAddress(),
  abi: revlineAbi,
});

export const readRevline = <T>(functionName: string, args: readonly unknown[] = []) =>
  publicClient.readContract({
    ...revlineContract(),
    functionName,
    args,
  } as never) as Promise<T>;

export const writeRevline = (
  walletClient: WalletClient,
  account: Address,
  functionName: string,
  args: readonly unknown[] = [],
) => walletClient.writeContract({
  account,
  ...revlineContract(),
  functionName,
  args,
} as never) as Promise<Hex>;
