import { useEffect, useState } from "react";
import { formatUSDC, parseUSDC } from "../format";

type CreditCardProps = {
  trailingRevenue: bigint;
  creditLimit: bigint;
  drawableNow: bigint;
  creditEnabled: boolean;
  activeAdvance?: {
    principal: bigint;
    principalOutstanding: bigint;
    fee: bigint;
    totalOwed: bigint;
    repaid: bigint;
  };
  pending: boolean;
  onDraw: (amount: bigint) => Promise<void>;
};

export default function CreditCard({
  trailingRevenue,
  creditLimit,
  drawableNow,
  creditEnabled,
  activeAdvance,
  pending,
  onDraw,
}: CreditCardProps) {
  const [amount, setAmount] = useState(formatUSDC(drawableNow));
  const [error, setError] = useState<string>();

  useEffect(() => setAmount(formatUSDC(drawableNow)), [drawableNow]);

  const draw = async (event: React.FormEvent) => {
    event.preventDefault();
    try {
      const parsed = parseUSDC(amount);
      if (parsed <= 0n || parsed > drawableNow) {
        setError(`Enter an amount from 0.000001 to ${formatUSDC(drawableNow)} USDC.`);
        return;
      }
      setError(undefined);
      await onDraw(parsed);
    } catch {
      setError("Enter a valid USDC amount with up to 6 decimal places.");
    }
  };

  const progress = activeAdvance && activeAdvance.totalOwed > 0n
    ? Number((activeAdvance.repaid * 10000n) / activeAdvance.totalOwed) / 100
    : 0;

  return (
    <section className="credit-card" aria-labelledby="credit-heading">
      <div className="section-heading">
        <div>
          <p className="eyebrow">Revenue advance</p>
          <h2 id="credit-heading">Your available credit</h2>
        </div>
        <strong className="credit-amount">{formatUSDC(drawableNow)} USDC</strong>
      </div>
      <dl className="credit-summary">
        <div><dt>Trailing 30d revenue</dt><dd>{formatUSDC(trailingRevenue)} USDC</dd></div>
        <div><dt>Credit limit</dt><dd>{formatUSDC(creditLimit)} USDC</dd></div>
      </dl>
      <p className="terms">20% advance rate · 20% of routed revenue repays · 5% fixed fee</p>

      {activeAdvance ? (
        <div className="advance-progress">
          <div className="progress-copy"><span>Active debt</span><strong>{formatUSDC(activeAdvance.totalOwed - activeAdvance.repaid)} USDC remaining</strong></div>
          <div className="progress-track" aria-label={`${progress}% repaid`}><span style={{ width: `${progress}%` }} /></div>
          <p>Principal remaining {formatUSDC(activeAdvance.principalOutstanding)} USDC · Fixed fee {formatUSDC(activeAdvance.fee)} USDC</p>
        </div>
      ) : creditEnabled ? (
        <form className="draw-form" onSubmit={draw}>
          <label htmlFor="draw-amount">Draw amount (USDC)</label>
          <div className="input-action">
            <input id="draw-amount" inputMode="decimal" value={amount} onChange={(event) => setAmount(event.target.value)} disabled={pending || drawableNow === 0n} />
            <button className="button" disabled={pending || drawableNow === 0n}>{pending ? "Processing…" : "Draw advance"}</button>
          </div>
          {error && <p className="field-error" role="alert">{error}</p>}
        </form>
      ) : (
        <p className="notice">Underwriter approval is pending. Credit becomes drawable once approved and your verified 30-day revenue reaches 100 USDC.</p>
      )}
    </section>
  );
}
