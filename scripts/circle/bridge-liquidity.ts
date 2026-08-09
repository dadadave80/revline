import { AppKit } from "@circle-fin/app-kit";
import { createViemAdapterFromPrivateKey } from "@circle-fin/adapter-viem-v2";
import { inspect } from "node:util";

const privateKey = process.env.BASE_SEPOLIA_PRIVATE_KEY as `0x${string}`;
const revline = process.env.REVLINE_ADDRESS as `0x${string}`;
const amount = process.argv[2] ?? "100.00";

if (!privateKey || !revline) {
  throw new Error("Missing BASE_SEPOLIA_PRIVATE_KEY or REVLINE_ADDRESS");
}

const kit = new AppKit();

const adapter = createViemAdapterFromPrivateKey({
  privateKey,
});

kit.on("*", (payload) => {
  console.log("[circle]", payload);
});

const result = await kit.bridge({
  from: {
    adapter,
    chain: "Base_Sepolia",
  },
  to: {
    chain: "Arc_Testnet",
    recipientAddress: revline,
    useForwarder: true,
  },
  amount,
});

console.log(inspect(result, false, null, true));

if (result.state !== "success") {
  process.exitCode = 1;
}
