import { useState } from "react";
import type { Address, WalletClient } from "viem";
import { connectWallet } from "./wallet";
import MerchantScreen from "./screens/MerchantScreen";
import "./styles.css";

function App() {
  const [session, setSession] = useState<{ account: Address; walletClient: WalletClient }>();
  const [error, setError] = useState<string>();
  const [connecting, setConnecting] = useState(false);

  const connect = async () => {
    setConnecting(true);
    setError(undefined);
    try {
      setSession(await connectWallet());
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Unable to connect wallet");
    } finally {
      setConnecting(false);
    }
  };

  return (
    <main className="app-shell">
      <header className="topbar">
        <a className="brand" href="#/" aria-label="Revline home">Revline</a>
        <button className="button button-secondary" onClick={connect} disabled={connecting}>
          {connecting ? "Connecting…" : session ? `${session.account.slice(0, 6)}…${session.account.slice(-4)}` : "Connect wallet"}
        </button>
      </header>
      {error && <p className="notice notice-error" role="alert">{error}</p>}
      {session ? (
        <MerchantScreen account={session.account} walletClient={session.walletClient} />
      ) : (
        <section className="welcome">
          <h1>Revenue-backed working capital</h1>
          <p>Connect an Arc Testnet wallet to register your business, issue invoices, and view available credit.</p>
          <button className="button" onClick={connect} disabled={connecting}>Connect wallet</button>
        </section>
      )}
    </main>
  );
}

export default App;
