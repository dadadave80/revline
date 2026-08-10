import { keccak256, toBytes, type Address } from "viem";
import { publicClient } from "./wallet";
import { getRevlineAddress } from "./contract";

export const DEFAULT_ADMIN_ROLE = `0x${"00".repeat(32)}` as `0x${string}`;
export const UNDERWRITER_ROLE = keccak256(toBytes("REVLINE_UNDERWRITER_ROLE"));

export const adminAbi = [
  { type: "function", name: "grantRole", stateMutability: "nonpayable", inputs: [{ name: "role", type: "bytes32" }, { name: "account", type: "address" }], outputs: [] },
  { type: "function", name: "revokeRole", stateMutability: "nonpayable", inputs: [{ name: "role", type: "bytes32" }, { name: "account", type: "address" }], outputs: [] },
  { type: "function", name: "pause", stateMutability: "nonpayable", inputs: [], outputs: [] },
  { type: "function", name: "unpause", stateMutability: "nonpayable", inputs: [], outputs: [] },
  { type: "function", name: "paused", stateMutability: "view", inputs: [], outputs: [{ name: "", type: "bool" }] },
] as const;

const roleAbi = [{
  type: "function", name: "hasRole", stateMutability: "view", inputs: [
    { name: "role", type: "bytes32" }, { name: "account", type: "address" },
  ], outputs: [{ name: "", type: "bool" }],
}] as const;

export async function loadCapabilities(account: Address) {
  const address = getRevlineAddress();
  const [admin, underwriter] = await Promise.all([
    publicClient.readContract({ address, abi: roleAbi, functionName: "hasRole", args: [DEFAULT_ADMIN_ROLE, account] }),
    publicClient.readContract({ address, abi: roleAbi, functionName: "hasRole", args: [UNDERWRITER_ROLE, account] }),
  ]);
  return { account, isAdmin: admin, isUnderwriter: underwriter };
}
