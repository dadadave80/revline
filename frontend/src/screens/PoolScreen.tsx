import { useCallback, useEffect, useState } from "react";
import MetricCard from "../components/MetricCard";
import { readRevline } from "../contract";
import { formatUSDC } from "../format";

type PoolStats = {
  liquidUSDC: bigint;
  outstandingPrincipal: bigint;
  totalAdvanced: bigint;
  totalRepaid: bigint;
  totalFeesEarned: bigint;
  managedAssets: bigint;
};

export default function PoolScreen() {
  const [stats, setStats] = useState<PoolStats>();
  const [error, setError] = useState<string>();
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(undefined);
    try {
      setStats(await readRevline<PoolStats>("poolStats"));
    } catch (cause) {
      setError(cause instanceof Error ? (cause as Error & { shortMessage?: string }).shortMessage ?? cause.message : "Unable to load live pool statistics.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);

  return <div className="pool-screen">
    <section className="screen-intro">
      <div><p className="eyebrow">Protocol reserve</p><h1>Pool health, live on Arc.</h1><p>USDC balances and receivables are read directly from the Revline Diamond.</p></div>
      <button className="button button-secondary" onClick={() => void refresh()} disabled={loading}>{loading ? "Refreshing…" : "Refresh"}</button>
    </section>
    {error && <p className="notice notice-error" role="alert">{error}</p>}
    <section className="metrics pool-metrics" aria-label="Live pool statistics">
      <MetricCard label="Liquid USDC" value={stats ? `${formatUSDC(stats.liquidUSDC)} USDC` : "—"} detail="Reserve available on Arc" />
      <MetricCard label="Outstanding principal" value={stats ? `${formatUSDC(stats.outstandingPrincipal)} USDC` : "—"} detail="Active receivable exposure" />
      <MetricCard label="Managed assets" value={stats ? `${formatUSDC(stats.managedAssets)} USDC` : "—"} detail="Liquid USDC + outstanding principal" />
      <MetricCard label="Total advanced" value={stats ? `${formatUSDC(stats.totalAdvanced)} USDC` : "—"} detail="Principal deployed" />
      <MetricCard label="Total repayments" value={stats ? `${formatUSDC(stats.totalRepaid)} USDC` : "—"} detail="Principal + financing fees collected" />
      <MetricCard label="Realized financing fees" value={stats ? `${formatUSDC(stats.totalFeesEarned)} USDC` : "—"} detail="Fees collected, never projected" />
    </section>
    <section className="accounting-card card" aria-labelledby="accounting-heading">
      <p className="eyebrow">Accounting treatment</p>
      <h2 id="accounting-heading">Receivables stay visible.</h2>
      <ul>
        <li>Reserve capital is settled on Arc.</li>
        <li>Outstanding principal is treated as receivable exposure.</li>
        <li>Financing fees are recognized only when repaid.</li>
      </ul>
    </section>
    <section className="circle-card card" aria-labelledby="circle-heading">
      <div>
        <p className="eyebrow">Circle integration</p>
        <h2 id="circle-heading">Cross-chain reserve funding</h2>
        <p>Reserve can be funded from Base Sepolia through Circle App Kit / CCTP.</p>
      </div>
      <div className="circle-balance"><span>Live reserve balance</span><strong>{stats ? `${formatUSDC(stats.liquidUSDC)} USDC` : "—"}</strong><small>Funding is reserve liquidity, not merchant revenue.</small></div>
    </section>
  </div>;
}
