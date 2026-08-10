import { useEffect, useState } from "react";
import { getAddress, type Address } from "viem";
import { getRevlineAddress, readRevline, revlineAbi } from "../contract";
import { adminAbi, loadCapabilities, UNDERWRITER_ROLE } from "../roles";
import { publicClient, requireCurrentSession, type WalletSession } from "../wallet";

type Operation = "enable" | "disable" | "grant" | "revoke" | "pause" | "unpause";
type Merchant = { registered: boolean; creditEnabled: boolean; name: string };

export default function AdminSectionScreen({ account, session, section }: { account?: Address; session?: WalletSession; section: "underwriting" | "protocol" }) {
  const [authorized, setAuthorized] = useState<boolean>();
  const [error, setError] = useState<string>();
  const [target, setTarget] = useState("");
  const [merchant, setMerchant] = useState<Merchant>();
  const [paused, setPaused] = useState<boolean>();
  const [busy, setBusy] = useState(false);
  const [hash, setHash] = useState<string>();

  useEffect(() => {
    if (!account) return;
    setAuthorized(undefined);
    setError(undefined);
    loadCapabilities(account)
      .then((caps) => setAuthorized(section === "underwriting" ? caps.isUnderwriter : caps.isAdmin))
      .catch((cause) => setError(cause instanceof Error ? cause.message : "Unable to verify onchain permissions."));
    if (section === "protocol") {
      publicClient.readContract({ address: getRevlineAddress(), abi: adminAbi, functionName: "paused" })
        .then(setPaused)
        .catch(() => setError("Unable to read protocol pause state."));
    }
  }, [account, section]);

  const merchantAddress = () => getAddress(target.trim());

  const loadMerchant = async () => {
    const profile = await readRevline<Merchant>("getMerchant", [merchantAddress()]);
    setMerchant(profile);
    if (!profile.registered) throw new Error("This address is not a registered Revline merchant.");
    return profile;
  };

  const submit = async (operation: Operation) => {
    if (!session) return;
    setBusy(true); setError(undefined); setHash(undefined);
    try {
      const current = await requireCurrentSession(session);
      const caps = await loadCapabilities(current.account);
      const needsUnderwriter = operation === "enable" || operation === "disable";
      if (needsUnderwriter && !caps.isUnderwriter) throw new Error("This wallet no longer has the Underwriter role.");
      if (!needsUnderwriter && !caps.isAdmin) throw new Error("This wallet no longer has the Admin role.");

      let tx: `0x${string}`;
      if (needsUnderwriter) {
        await loadMerchant();
        tx = await current.walletClient.writeContract({
          account: current.account,
          address: getRevlineAddress(),
          abi: revlineAbi,
          functionName: "setCreditEnabled",
          args: [merchantAddress(), operation === "enable"],
        } as never);
      } else {
        if (operation === "revoke" && target.toLowerCase() === current.account.toLowerCase() && !window.confirm("Revoke your own Underwriter role?")) return;
        const args = operation === "grant" || operation === "revoke" ? [UNDERWRITER_ROLE, getAddress(target.trim())] : [];
        tx = await current.walletClient.writeContract({
          account: current.account,
          address: getRevlineAddress(),
          abi: adminAbi,
          functionName: operation === "grant" ? "grantRole" : operation === "revoke" ? "revokeRole" : operation,
          args,
        } as never);
      }

      setHash(tx);
      const receipt = await publicClient.waitForTransactionReceipt({ hash: tx });
      if (receipt.status !== "success") throw new Error("Transaction reverted.");
      if (needsUnderwriter) await loadMerchant();
      if (operation === "pause" || operation === "unpause") setPaused(operation === "pause");
    } catch (cause) {
      setError(cause instanceof Error ? (cause as Error & { shortMessage?: string }).shortMessage ?? cause.message : "Transaction failed.");
    } finally { setBusy(false); }
  };

  if (!account) return <section className="welcome"><h1>Admin Console</h1><p>Connect an authorized wallet to continue.</p></section>;
  if (error && authorized === undefined) return <section className="welcome"><h1>Admin Console unavailable</h1><p className="notice notice-error">{error}</p></section>;
  if (authorized === undefined) return <p className="loading">Checking onchain permissions…</p>;
  if (!authorized) return <section className="welcome"><h1>Access denied</h1><p className="notice notice-error">This wallet is not authorized for the {section} console.</p><a href="#/admin">Return to Admin Console</a></section>;

  return <section className="welcome admin-console">
    <p className="eyebrow">Authorized console</p><h1>{section === "underwriting" ? "Merchant underwriting" : "Protocol controls"}</h1>
    {error && <p className="notice notice-error" role="alert">{error}</p>}
    {hash && <p className="notice notice-success">Confirmed: <a href={`https://testnet.arcscan.app/tx/${hash}`} target="_blank" rel="noreferrer">View on Arcscan</a></p>}

    {section === "underwriting" ? <form onSubmit={(event) => { event.preventDefault(); void loadMerchant().catch((cause) => setError(cause instanceof Error ? cause.message : "Unable to load merchant.")); }}>
      <label>Registered merchant address<input value={target} onChange={(event) => { setTarget(event.target.value); setMerchant(undefined); }} placeholder="0x…" required /></label>
      <div className="hero-actions"><button className="button button-secondary" disabled={busy || !target}>Check merchant</button></div>
      {merchant?.registered && <div className="notice"><strong>{merchant.name}</strong><br />Credit is currently {merchant.creditEnabled ? "enabled" : "disabled"}.</div>}
      <div className="hero-actions"><button type="button" className="button" disabled={busy || !merchant?.registered || merchant.creditEnabled} onClick={() => void submit("enable")}>{busy ? "Waiting…" : "Enable credit"}</button><button type="button" className="button button-secondary" disabled={busy || !merchant?.registered || !merchant.creditEnabled} onClick={() => void submit("disable")}>Disable credit</button></div>
    </form> : <>
      <form onSubmit={(event) => { event.preventDefault(); void submit("grant"); }}>
        <label>Underwriter wallet address<input value={target} onChange={(event) => setTarget(event.target.value)} placeholder="0x…" required /></label>
        <div className="hero-actions"><button className="button" disabled={busy || !target}>{busy ? "Waiting…" : "Grant Underwriter role"}</button><button type="button" className="button button-secondary" disabled={busy || !target} onClick={() => void submit("revoke")}>Revoke role</button></div>
      </form>
      <div className="card protocol-state"><strong>Protocol is {paused ? "paused" : "active"}.</strong><div className="hero-actions"><button className="button" disabled={busy || paused === true} onClick={() => void submit("pause")}>Pause protocol</button><button className="button button-secondary" disabled={busy || paused !== true} onClick={() => void submit("unpause")}>Unpause protocol</button></div></div>
    </>}
    <p><a href="#/admin">Back to Admin Console</a></p>
  </section>;
}
