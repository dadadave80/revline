import { useCallback, useEffect, useState } from "react";
import { decodeEventLog, type Address, type TransactionReceipt, type WalletClient } from "viem";
import CreditCard from "../components/CreditCard";
import InvoiceTable, { type MerchantInvoice } from "../components/InvoiceTable";
import MetricCard from "../components/MetricCard";
import { readRevline, revlineAbi, writeRevline } from "../contract";
import { formatUSDC, parseUSDC } from "../format";
import { publicClient } from "../wallet";

type Merchant = {
  registered: boolean;
  creditEnabled: boolean;
  activeAdvanceId: bigint;
  totalBorrowed: bigint;
  totalRepaid: bigint;
  name: string;
};

type CreditQuote = {
  trailingRevenue: bigint;
  creditLimit: bigint;
  drawableNow: bigint;
  creditEnabled: boolean;
};

type Advance = {
  principal: bigint;
  principalOutstanding: bigint;
  fee: bigint;
  totalOwed: bigint;
  repaid: bigint;
};

type PoolStats = { liquidUSDC: bigint };

type Invoice = Omit<MerchantInvoice, "id">;
type DashboardState = {
  merchant: Merchant;
  quote: CreditQuote;
  pool: PoolStats;
  advance?: Advance;
  invoices: MerchantInvoice[];
};

type MerchantScreenProps = { account: Address; walletClient: WalletClient };

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as Address;
const arcscan = (hash: string) => `https://testnet.arcscan.app/tx/${hash}`;

function transactionError(cause: unknown) {
  if (!(cause instanceof Error)) return "Transaction failed.";
  if (/user rejected|rejected the request|denied/i.test(cause.message)) return "Wallet transaction was rejected.";
  return (cause as Error & { shortMessage?: string }).shortMessage ?? cause.message;
}

function invoiceIdFromReceipt(receipt: TransactionReceipt): bigint | undefined {
  for (const log of receipt.logs) {
    try {
      const decoded = decodeEventLog({ abi: revlineAbi, data: log.data, topics: log.topics });
      const args = decoded.args as { invoiceId?: unknown } | undefined;
      if (decoded.eventName === "InvoiceCreated" && typeof args?.invoiceId === "bigint") return args.invoiceId;
    } catch {
      // A receipt can contain logs from other contracts.
    }
  }
}

export default function MerchantScreen({ account, walletClient }: MerchantScreenProps) {
  const [state, setState] = useState<DashboardState>();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string>();
  const [tx, setTx] = useState<{ label: string; hash?: string }>();
  const [businessName, setBusinessName] = useState("");
  const [invoiceAmount, setInvoiceAmount] = useState("");
  const [invoiceMemo, setInvoiceMemo] = useState("");
  const [invoiceExpiry, setInvoiceExpiry] = useState("");
  const [createdInvoiceId, setCreatedInvoiceId] = useState<bigint>();

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(undefined);
    try {
      const [merchant, trailingRevenue, quote, pool, ids] = await Promise.all([
        readRevline<Merchant>("getMerchant", [account]),
        readRevline<bigint>("trailingRevenue", [account]),
        readRevline<CreditQuote>("creditQuote", [account]),
        readRevline<PoolStats>("poolStats"),
        readRevline<bigint[]>("getMerchantInvoiceIds", [account]),
      ]);
      const [advance, invoices] = await Promise.all([
        merchant.activeAdvanceId === 0n ? Promise.resolve(undefined) : readRevline<Advance>("getAdvance", [merchant.activeAdvanceId]),
        Promise.all(ids.map(async (id) => ({ id, ...await readRevline<Invoice>("getInvoice", [id]) }))),
      ]);
      setState({ merchant, quote: { ...quote, trailingRevenue }, pool, advance, invoices: [...invoices].reverse() });
    } catch (cause) {
      setError(cause instanceof Error ? (cause as Error & { shortMessage?: string }).shortMessage ?? cause.message : "Unable to load Revline state.");
    } finally {
      setLoading(false);
    }
  }, [account]);

  useEffect(() => { void refresh(); }, [refresh]);

  const submit = async (label: string, functionName: string, args: readonly unknown[] = []) => {
    setError(undefined);
    setTx({ label: `${label}: awaiting wallet…` });
    try {
      const hash = await writeRevline(walletClient, account, functionName, args);
      setTx({ label: `${label}: confirming…`, hash });
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      if (receipt.status !== "success") throw new Error("Transaction reverted.");
      return receipt;
    } catch (cause) {
      setTx(undefined);
      setError(transactionError(cause));
      return undefined;
    }
  };

  const register = async (event: React.FormEvent) => {
    event.preventDefault();
    const length = new TextEncoder().encode(businessName.trim()).length;
    if (length === 0 || length > 64) {
      setError("Business name must be 1–64 UTF-8 bytes.");
      return;
    }
    const receipt = await submit("Registering business", "registerMerchant", [businessName.trim()]);
    if (receipt) {
      setTx({ label: "Business registered", hash: receipt.transactionHash });
      await refresh();
    }
  };

  const draw = async (amount: bigint) => {
    const receipt = await submit("Drawing advance", "drawAdvance", [amount]);
    if (receipt) {
      setTx({ label: "Advance drawn", hash: receipt.transactionHash });
      await refresh();
    }
  };

  const createInvoice = async (event: React.FormEvent) => {
    event.preventDefault();
    let amount: bigint;
    try {
      amount = parseUSDC(invoiceAmount);
    } catch {
      setError("Enter a valid USDC amount with up to 6 decimal places.");
      return;
    }
    const memoLength = new TextEncoder().encode(invoiceMemo).length;
    if (amount <= 0n || memoLength > 120) {
      setError(amount <= 0n ? "Invoice amount must be greater than zero." : "Memo must be 120 UTF-8 bytes or fewer.");
      return;
    }
    const expiresAt = invoiceExpiry ? Math.floor(new Date(`${invoiceExpiry}T00:00:00`).getTime() / 1000) : 0;
    if (!Number.isSafeInteger(expiresAt) || (expiresAt !== 0 && expiresAt <= Math.floor(Date.now() / 1000))) {
      setError("Expiration must be a future date.");
      return;
    }
    const receipt = await submit("Creating invoice", "createInvoice", [amount, BigInt(expiresAt), invoiceMemo]);
    if (receipt) {
      const invoiceId = invoiceIdFromReceipt(receipt);
      setCreatedInvoiceId(invoiceId);
      setTx({ label: "Invoice created", hash: receipt.transactionHash });
      setInvoiceAmount("");
      setInvoiceMemo("");
      setInvoiceExpiry("");
      await refresh();
    }
  };

  const pending = Boolean(tx && !tx.label.endsWith("registered") && !tx.label.endsWith("drawn") && !tx.label.endsWith("created"));

  if (loading && !state) return <p className="loading">Loading live Revline state…</p>;

  if (!state?.merchant.registered) {
    return <section className="registration card">
      <p className="eyebrow">Merchant account</p>
      <h1>Register your business</h1>
      <p>Route invoice payments through Revline to establish verifiable revenue history.</p>
      <form onSubmit={register}>
        <label htmlFor="business-name">Business name</label>
        <input id="business-name" value={businessName} maxLength={64} onChange={(event) => setBusinessName(event.target.value)} placeholder="Acme Studio" disabled={pending} />
        <button className="button" disabled={pending}>{pending ? "Processing…" : "Register business"}</button>
      </form>
      {error && <p className="notice notice-error" role="alert">{error}</p>}
      {tx && <TransactionStatus tx={tx} />}
    </section>;
  }

  const debt = state.advance ? state.advance.totalOwed - state.advance.repaid : 0n;
  return <div className="merchant-screen">
    <section className="screen-intro">
      <div><p className="eyebrow">Merchant dashboard</p><h1>{state.merchant.name}</h1><p>Verified revenue is created only when customers pay your Revline invoices.</p></div>
      <button className="button button-secondary" onClick={() => void refresh()} disabled={loading || pending}>{loading ? "Refreshing…" : "Refresh"}</button>
    </section>
    {error && <p className="notice notice-error" role="alert">{error}</p>}
    {tx && <TransactionStatus tx={tx} />}
    <section className="metrics" aria-label="Merchant metrics">
      <MetricCard label="Verified 30d revenue" value={`${formatUSDC(state.quote.trailingRevenue)} USDC`} detail="Protocol-routed invoice payments only" />
      <MetricCard label="Credit limit" value={`${formatUSDC(state.quote.creditLimit)} USDC`} detail="20% of trailing verified revenue" />
      <MetricCard label="Active debt" value={`${formatUSDC(debt)} USDC`} detail={state.advance ? "Principal and fee are repaid from routed revenue" : "No active revenue advance"} />
      <MetricCard label="Pool liquidity" value={`${formatUSDC(state.pool.liquidUSDC)} USDC`} detail="Available protocol reserve" />
    </section>
    <CreditCard trailingRevenue={state.quote.trailingRevenue} creditLimit={state.quote.creditLimit} drawableNow={state.quote.drawableNow} creditEnabled={state.merchant.creditEnabled} activeAdvance={state.advance} pending={pending} onDraw={draw} />
    <section className="invoice-create card" aria-labelledby="create-invoice-heading">
      <div className="section-heading"><div><p className="eyebrow">Collect revenue</p><h2 id="create-invoice-heading">Create an invoice</h2></div></div>
      <form className="invoice-form" onSubmit={createInvoice}>
        <label>Amount (USDC)<input inputMode="decimal" value={invoiceAmount} onChange={(event) => setInvoiceAmount(event.target.value)} disabled={pending} required /></label>
        <label>Memo<input value={invoiceMemo} maxLength={120} onChange={(event) => setInvoiceMemo(event.target.value)} disabled={pending} placeholder="Website design deposit" /></label>
        <label>Expiration date <span>(optional)</span><input type="date" value={invoiceExpiry} onChange={(event) => setInvoiceExpiry(event.target.value)} disabled={pending} /></label>
        <button className="button" disabled={pending}>{pending ? "Processing…" : "Create invoice"}</button>
      </form>
      {createdInvoiceId !== undefined && <p className="invoice-created">Invoice #{createdInvoiceId.toString()} is ready: <a href={`/#/pay/${createdInvoiceId.toString()}`}>/#/pay/{createdInvoiceId.toString()}</a></p>}
    </section>
    <InvoiceTable invoices={state.invoices} />
  </div>;
}

function TransactionStatus({ tx }: { tx: { label: string; hash?: string } }) {
  return <p className="notice notice-success" role="status">{tx.label}{tx.hash && <> · <a href={arcscan(tx.hash)} target="_blank" rel="noreferrer">View on Arcscan</a></>}</p>;
}
