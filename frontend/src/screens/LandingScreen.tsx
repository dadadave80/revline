export default function LandingScreen() {
  return (
    <div className="landing-screen">
      <section className="landing-hero">
        <div>
          <span className="status status-open">Revenue-backed USDC</span>
          <h1>Working capital from revenue you already prove onchain.</h1>
          <p>Revline advances USDC against protocol-routed stablecoin revenue and automatically repays from future sales.</p>
          <div className="hero-actions">
            <a className="button" href="#/merchant">Open merchant dashboard</a>
            <a className="text-link" href="#/pool">View protocol pool</a>
          </div>
        </div>
        <aside className="landing-principle" aria-label="Revline principle">
          <span className="metric-label">The Revline loop</span>
          <strong>Revenue creates credit.</strong>
          <span>Future revenue retires credit.</span>
        </aside>
      </section>

      <section className="story" aria-labelledby="how-it-works">
        <div className="section-heading">
          <div>
            <p className="eyebrow">How it works</p>
            <h2 id="how-it-works">A revenue line, not a guess.</h2>
          </div>
          <p>Only successful Revline invoice payments create verified revenue for credit.</p>
        </div>
        <ol className="story-steps">
          <li><span>01</span><strong>Accept USDC</strong><p>Send customers a Revline invoice and collect protocol-routed USDC.</p></li>
          <li><span>02</span><strong>Unlock working capital</strong><p>Eligible merchants draw against their verified 30-day revenue.</p></li>
          <li><span>03</span><strong>Repay automatically as revenue arrives</strong><p>Future invoice payments retire principal first, then financing fees.</p></li>
        </ol>
      </section>
    </div>
  );
}
