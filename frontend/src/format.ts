import { formatUnits, parseUnits } from "viem";

export const parseUSDC = (value: string) => parseUnits(value, 6);
export const formatUSDC = (value: bigint) => formatUnits(value, 6);
