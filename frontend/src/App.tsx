import { useEffect, useState } from "react";
import { shortAddress } from "./wallet";
import { useWallet } from "./WalletProvider";
import LandingScreen from "./screens/LandingScreen";
import MerchantScreen from "./screens/MerchantScreen";
import PayInvoiceScreen from "./screens/PayInvoiceScreen";
import PoolScreen from "./screens/PoolScreen";
import AdminConsoleScreen from "./screens/AdminConsoleScreen";
import AdminSectionScreen from "./screens/AdminSectionScreen";
import "./styles.css";

function App() {
  const { wallets, session, status, error, connect, disconnect, switchNetwork } = useWallet();
  const [walletMenuOpen, setWalletMenuOpen] = useState(false);
  const [route, setRoute] = useState(() => window.location.hash);

  useEffect(() => {
    const onHashChange = () => setRoute(window.location.hash);
    window.addEventListener("hashchange", onHashChange);
    return () => window.removeEventListener("hashchange", onHashChange);
  }, []);

  useEffect(() => {
    if (!walletMenuOpen) return;
    const close = (event: PointerEvent) => {
      if (!(event.target as Element).closest(".wallet-entry")) setWalletMenuOpen(false);
    };
    const escape = (event: KeyboardEvent) => { if (event.key === "Escape") setWalletMenuOpen(false); };
    document.addEventListener("pointerdown", close);
    document.addEventListener("keydown", escape);
    return () => {
      document.removeEventListener("pointerdown", close);
      document.removeEventListener("keydown", escape);
    };
  }, [walletMenuOpen]);

  const connecting = status === "connecting" || status === "discovering";
  const openWalletMenu = async () => { setWalletMenuOpen(true); };

  const payRoute = route.match(/^#\/pay\/(.+)$/)?.[1];
  const currentRoute = route || "#/";
  const isMerchantRoute = currentRoute === "#/merchant";
  const isPoolRoute = currentRoute === "#/pool";
  const isAdminRoute = currentRoute === "#/admin";
  const adminSection = currentRoute === "#/admin/underwriting" ? "underwriting" : currentRoute === "#/admin/protocol" ? "protocol" : undefined;

  return (
    <main className="app-shell">
      <header className="topbar">
        <a className="brand" href="#/" aria-label="Revline home">Revline</a>
        <nav className="topnav" aria-label="Primary navigation">
          <a className={currentRoute === "#/" ? "active" : undefined} href="#/">Overview</a>
          <a className={isMerchantRoute ? "active" : undefined} href="#/merchant">Merchant</a>
          <a className={isPoolRoute ? "active" : undefined} href="#/pool">Pool</a>
          {session && <a className={isAdminRoute || adminSection ? "active" : undefined} href="#/admin">Admin</a>}
        </nav>
        <div className="wallet-entry">
          <button className="button button-secondary" onClick={() => status === "wrong-chain" ? void switchNetwork() : setWalletMenuOpen((open) => !open)} disabled={connecting}>
            {connecting ? "Connecting…" : status === "wrong-chain" ? "Switch to Arc" : session ? shortAddress(session.account) : "Connect wallet"}
          </button>
          {walletMenuOpen && !session && (
            <div className="wallet-menu" role="dialog" aria-label="Choose a wallet">
              <strong>Choose a wallet</strong>
              {wallets.length === 0 ? <p className="muted">No injected wallets detected.</p> : wallets.map((wallet) => (
                <button key={wallet.id} className="wallet-option" onClick={() => { void connect(wallet); setWalletMenuOpen(false); }}>
                  {wallet.icon && <img src={wallet.icon} alt="" width="24" height="24" />}
                  <span>{wallet.name}</span>
                </button>
              ))}
            </div>
          )}
          {walletMenuOpen && session && (
            <div className="wallet-menu" role="dialog" aria-label="Connected wallet">
              <strong>{shortAddress(session.account)}</strong>
              <button className="wallet-option" onClick={() => { disconnect(); setWalletMenuOpen(false); }}>Disconnect session</button>
              <span className="muted">Wallet permissions remain unchanged.</span>
            </div>
          )}
        </div>
      </header>
      {error && <p className="notice notice-error" role="alert">{error}</p>}
      {payRoute ? (
        <PayInvoiceScreen invoiceId={payRoute} session={session} onConnect={openWalletMenu} />
      ) : adminSection ? (
        <AdminSectionScreen account={session?.account} session={session} section={adminSection} />
      ) : isAdminRoute ? (
        <AdminConsoleScreen account={session?.account} />
      ) : isPoolRoute ? (
        <PoolScreen />
      ) : isMerchantRoute && session ? (
        <MerchantScreen account={session.account} walletClient={session.walletClient} />
      ) : isMerchantRoute ? (
        <section className="welcome">
          <p className="eyebrow">Merchant dashboard</p>
          <h1>Connect to manage your revenue line.</h1>
          <p>Use an Arc Testnet wallet to register your business, issue invoices, and view available credit.</p>
          <button className="button" onClick={() => setWalletMenuOpen(true)} disabled={connecting}>Connect wallet</button>
        </section>
      ) : (
        <LandingScreen />
      )}
    </main>
  );
}

export default App;
