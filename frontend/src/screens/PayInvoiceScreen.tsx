import { useCallback, useEffect, useState } from "react";
import { getAddress, type Address, type WalletClient } from "viem";
import { ARC_USDC, arcTestnet } from "../chain";
import { getRevlineAddress, readRevline, writeRevline } from "../contract";
import { formatUSDC } from "../format";
import { ensureArcNetwork, publicClient } from "../wallet";

type Invoice = {
  merchant: Address;
  amount: bigint;
  expiresAt: bigint;
  status: number;
  memo: string;
};

type Merchant = {
  activeAdvanceId: bigint;
  name: string;
};

type CheckoutState = { invoice: Invoice; merchant: Merchant };
type PayInvoiceScreenProps = {
  invoiceId: string;
  account?: Address;
  walletClient?: WalletClient;
  onConnect: () => Promise<void>;
};

const erc20Abi = [
  {
    type: "function",
    name: "allowance",
    stateMutability: "view",
    inputs: [{ name: "owner", type: "address" }, { name: "spender", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "approve",
    stateMutability: "nonpayable",
    inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }],
    outputs: [{ name: "", type: "bool" }],
  },
] as const;

const arcscan = (hash: string) => `https://testnet.arcscan.app/tx/${hash}`;
const now = () => BigInt(Math.floor(Date.now() / 1000));

async function activeWalletAccount(expected: Address): Promise<Address> {
  const accounts = await window.ethereum?.request({ method: "eth_accounts" }) as string[] | undefined;
  const active = accounts?.[0];
  if (!active || getAddress(active) !== expected) throw new Error("Wallet account changed. Reconnect before continuing.");
  return expected;
}

function paymentError(cause: unknown): string {
  const error = cause instanceof Error ? cause : new Error("Payment could not be completed.");
  const message = `${(error as Error & { shortMessage?: string }).shortMessage ?? ""} ${error.message}`;
  if (/user rejected|rejected the request|denied/i.test(message)) return "The wallet transaction was rejected.";
  if (/InvoiceExpired/i.test(message)) return "This invoice has expired and can no longer be paid.";
  if (/InvoiceNotOpen/i.test(message)) return "This invoice is no longer open. It may already be paid or cancelled.";
  if (/InvoiceNotFound/i.test(message)) return "This invoice could not be found.";
  if (/insufficient funds for gas/i.test(message)) return "Your wallet needs more Arc Testnet USDC for network fees.";
  if (/USDCTransferFailed|insufficient funds|exceeds balance|transfer amount exceeds/i.test(message)) return "Your wallet does not have enough USDC to pay this invoice.";
  if (/chain|network|wallet_switchEthereumChain|wallet_addEthereumChain/i.test(message)) return "Switch your wallet to Arc Testnet to pay this invoice.";
  return (error as Error & { shortMessage?: string }).shortMessage ?? error.message;
}

function invoiceStatus(invoice: Invoice): "Open" | "Paid" | "Cancelled" | "Expired" | "Unknown" {
  if (invoice.status === 1 && invoice.expiresAt !== 0n && invoice.expiresAt <= now()) return "Expired";
  return ["Unknown", "Open", "Paid", "Cancelled"][invoice.status] as ReturnType<typeof invoiceStatus> ?? "Unknown";
}

function expiry(invoice: Invoice): string {
  if (invoice.expiresAt === 0n) return "No expiration";
  const seconds = Number(invoice.expiresAt);
  return Number.isSafeInteger(seconds) ? new Date(seconds * 1_000).toLocaleString() : "Expiration unavailable";
}

export default function PayInvoiceScreen({ invoiceId: invoiceIdText, account, walletClient, onConnect }: PayInvoiceScreenProps) {
  const invoiceId = /^\d+$/.test(invoiceIdText) ? BigInt(invoiceIdText) : undefined;
  const [state, setState] = useState<CheckoutState>();
  const [allowance, setAllowance] = useState<bigint>();
  const [loading, setLoading] = useState(true);
  const [allowanceLoading, setAllowanceLoading] = useState(false);
  const [pending, setPending] = useState(false);
  const [notice, setNotice] = useState<string>();
  const [error, setError] = useState<string>();
  const [approvalHash, setApprovalHash] = useState<string>();
  const [paymentHash, setPaymentHash] = useState<string>();

  const refresh = useCallback(async (preserveState = false): Promise<boolean> => {
    if (invoiceId === undefined) {
      setError("The invoice link is invalid.");
      setLoading(false);
      return false;
    }

    setLoading(true);
    setError(undefined);
    try {
      const invoice = await readRevline<Invoice>("getInvoice", [invoiceId]);
      if (invoice.status === 0) throw new Error("This invoice could not be found.");
      const merchant = await readRevline<Merchant>("getMerchant", [invoice.merchant]);
      setState({ invoice, merchant });
      return true;
    } catch (cause) {
      if (!preserveState) setState(undefined);
      setError(cause instanceof Error ? (cause as Error & { shortMessage?: string }).shortMessage ?? cause.message : "Unable to load this invoice.");
      return false;
    } finally {
      setLoading(false);
    }
  }, [invoiceId]);

  useEffect(() => { void refresh(); }, [refresh]);

  useEffect(() => {
    if (!account || !state || invoiceStatus(state.invoice) !== "Open") {
      setAllowance(undefined);
      setAllowanceLoading(false);
      return;
    }

    let cancelled = false;
    setAllowanceLoading(true);
    void activeWalletAccount(account).then((activeAccount) => publicClient.readContract({
      address: ARC_USDC,
      abi: erc20Abi,
      functionName: "allowance",
      args: [activeAccount, getRevlineAddress()],
    })).then((value) => {
      if (!cancelled) setAllowance(value);
    }).catch((cause) => {
      if (!cancelled) setError(cause instanceof Error ? cause.message : "Unable to check USDC approval.");
    }).finally(() => {
      if (!cancelled) setAllowanceLoading(false);
    });

    return () => { cancelled = true; };
  }, [account, state]);

  const pay = async () => {
    if (!state || !account || !walletClient || invoiceId === undefined) return;
    setPending(true);
    setError(undefined);
    setApprovalHash(undefined);
    setPaymentHash(undefined);
    try {
      await ensureArcNetwork();
      const payer = await activeWalletAccount(account);
      setNotice("Checking your USDC balance…");
      const [balance, currentAllowance] = await Promise.all([
        publicClient.readContract({ address: ARC_USDC, abi: erc20Abi, functionName: "balanceOf", args: [payer] }),
        publicClient.readContract({ address: ARC_USDC, abi: erc20Abi, functionName: "allowance", args: [payer, getRevlineAddress()] }),
      ]);
      if (balance < state.invoice.amount) throw new Error("Insufficient USDC.");

      if (currentAllowance < state.invoice.amount) {
        setNotice("Approving the exact invoice amount…");
        const approvalAccount = await activeWalletAccount(account);
        const approvalHash = await walletClient.writeContract({
          account: approvalAccount,
          chain: arcTestnet,
          address: ARC_USDC,
          abi: erc20Abi,
          functionName: "approve",
          args: [getRevlineAddress(), state.invoice.amount],
        });
        setNotice("Confirming USDC approval…");
        const approval = await publicClient.waitForTransactionReceipt({ hash: approvalHash });
        if (approval.status !== "success") throw new Error("USDC approval was not confirmed.");
        setApprovalHash(approval.transactionHash);
      }

      setNotice("Submitting payment…");
      const paymentAccount = await activeWalletAccount(account);
      const hash = await writeRevline(walletClient, paymentAccount, "payInvoice", [invoiceId]);
      setNotice("Confirming payment…");
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      if (receipt.status !== "success") throw new Error("Payment transaction reverted.");
      setPaymentHash(receipt.transactionHash);
      setNotice("Payment complete.");
      setState((current) => current && { ...current, invoice: { ...current.invoice, status: 2 } });
      if (!await refresh(true)) setNotice("Payment complete. The invoice status will refresh when the connection is restored.");
    } catch (cause) {
      setNotice(undefined);
      const message = paymentError(cause);
      await refresh();
      setError(message);
    } finally {
      setPending(false);
    }
  };

  if (loading && !state) return <p className="loading">Loading invoice…</p>;
  if (!state) return <section className="checkout card"><h1>Invoice unavailable</h1><p className="notice notice-error" role="alert">{error ?? "Unable to load this invoice."}</p><a className="button button-secondary" href="#/">Back to Revline</a></section>;

  const status = invoiceStatus(state.invoice);
  const canPay = status === "Open";
  const needsApproval = allowance !== undefined && allowance < state.invoice.amount;
  const actionLabel = !account ? "Connect wallet to pay" : !canPay ? "Invoice not payable" : allowanceLoading ? "Checking USDC approval…" : needsApproval ? "Approve & Pay" : "Pay invoice";

  return <section className="checkout card" aria-labelledby="invoice-heading">
    <a className="back-link" href="#/">← Back to Revline</a>
    <div className="checkout-heading">
      <div><p className="eyebrow">Invoice from</p><h1 id="invoice-heading">{state.merchant.name || "Revline merchant"}</h1></div>
      <span className={`status status-${status.toLowerCase()}`}>{status}</span>
    </div>
    <p className="checkout-memo">{state.invoice.memo || "Invoice payment"}</p>
    <dl className="invoice-details">
      <div><dt>Amount due</dt><dd className="checkout-amount">{formatUSDC(state.invoice.amount)} USDC</dd></div>
      <div><dt>Expires</dt><dd>{expiry(state.invoice)}</dd></div>
    </dl>
    {state.merchant.activeAdvanceId !== 0n && <p className="financing-disclosure">20% of routed revenue from this payment is currently applied to the merchant’s financing obligation.</p>}
    {status === "Paid" && <p className="notice notice-success" role="status">This invoice has already been paid.</p>}
    {status === "Cancelled" && <p className="notice notice-error" role="alert">This invoice was cancelled by the merchant.</p>}
    {status === "Expired" && <p className="notice notice-error" role="alert">This invoice expired and can no longer be paid.</p>}
    {error && <p className="notice notice-error" role="alert">{error}</p>}
    {notice && <p className="notice notice-success" role="status">{notice}</p>}
    {approvalHash && <p className="notice notice-success" role="status">USDC approved · <a href={arcscan(approvalHash)} target="_blank" rel="noreferrer">View approval on Arcscan</a></p>}
    {paymentHash && <div className="payment-success" role="status"><strong>Payment received</strong><span>{formatUSDC(state.invoice.amount)} USDC paid in full.</span><a href={arcscan(paymentHash)} target="_blank" rel="noreferrer">View payment on Arcscan</a></div>}
    <button className="button checkout-action" onClick={() => { if (!account) void onConnect(); else void pay(); }} disabled={pending || (!account ? false : !canPay || allowanceLoading)}>
      {pending ? "Processing…" : actionLabel}
    </button>
  </section>;
}
