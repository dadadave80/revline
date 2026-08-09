import { getAddress, type Abi, type Address, type Hex, type WalletClient } from "viem";
import revlineAbiJson from "./abi/revline.json";
import { publicClient } from "./wallet";

export const revlineAbi = revlineAbiJson as Abi;

export function getRevlineAddress(): Address {
  const address = import.meta.env.VITE_REVLINE_ADDRESS;
  if (!address || address === "0x") throw new Error("VITE_REVLINE_ADDRESS is required");
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
