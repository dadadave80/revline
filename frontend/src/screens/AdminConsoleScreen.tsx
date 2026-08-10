import { useEffect, useState } from "react";
import type { Address } from "viem";
import { loadCapabilities } from "../roles";

type Props = { account?: Address };

export default function AdminConsoleScreen({ account }: Props) {
  const [capabilities, setCapabilities] = useState<{ isAdmin: boolean; isUnderwriter: boolean }>();
  const [error, setError] = useState<string>();
  useEffect(() => {
    if (!account) return;
    loadCapabilities(account).then(setCapabilities).catch((cause) => setError(cause instanceof Error ? cause.message : "Unable to verify admin access."));
  }, [account]);
  if (!account) return <section className="welcome"><h1>Admin Console</h1><p>Connect an authorized wallet to continue.</p></section>;
  if (error) return <section className="welcome"><h1>Admin Console unavailable</h1><p className="notice notice-error">{error}</p></section>;
  if (!capabilities) return <p className="loading">Checking onchain permissions…</p>;
  if (!capabilities.isAdmin && !capabilities.isUnderwriter) return <section className="welcome"><h1>Admin Console</h1><p className="notice notice-error">This wallet has no privileged Revline role.</p></section>;
  return <section className="welcome"><p className="eyebrow">Privileged operations</p><h1>Admin Console</h1><p>Choose the authorized console for this wallet.</p><div className="hero-actions">
    {capabilities.isUnderwriter && <a className="button" href="#/admin/underwriting">Open underwriting</a>}
    {capabilities.isAdmin && <a className="button button-secondary" href="#/admin/protocol">Open protocol controls</a>}
  </div></section>;
}
