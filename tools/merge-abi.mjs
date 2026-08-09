import { mkdir, readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const artifacts = [
  "out/MerchantFacet.sol/MerchantFacet.json",
  "out/InvoiceFacet.sol/InvoiceFacet.json",
  "out/CreditFacet.sol/CreditFacet.json",
];

const entries = await Promise.all(artifacts.map(async (artifact) => {
  const source = await readFile(path.join(root, artifact), "utf8");
  return JSON.parse(source).abi;
}));

const seen = new Set();
const abi = entries.flat().filter((entry) => {
  const key = JSON.stringify(entry);
  if (seen.has(key)) return false;
  seen.add(key);
  return true;
});

const output = path.join(root, "frontend/src/abi/revline.json");
await mkdir(path.dirname(output), { recursive: true });
await writeFile(output, `${JSON.stringify(abi, null, 2)}\n`);
