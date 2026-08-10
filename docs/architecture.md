# Revline MVP architecture

Revline is one EIP-2535 Diamond on Arc Testnet. Project-owned facets share one ERC-7201-style Revline storage namespace; pinned Lattice modules keep independent namespaced storage for access control, pause state, reentrancy protection, introspection, and upgrades.

```text
Base Sepolia reserve wallet
        |
        | Circle App Kit / CCTP
        v
+---------------------------+
|       Arc Testnet         |
|                           |
|  Revline Diamond          |
|  +---------------------+  |
|  | MerchantFacet       |  |
|  | InvoiceFacet        |  |
|  | CreditFacet         |  |
|  +---------------------+  |
|  | Lattice infra       |  |
|  | AccessControl       |  |
|  | Pausable            |  |
|  | ReentrancyGuard     |  |
|  | Admin DiamondCut    |  |
|  +---------------------+  |
|           |               |
|           | USDC advance  |
|           v               |
|       Merchant            |
|           ^               |
|           | net revenue   |
| Customer -+               |
|      invoice payment      |
|           |               |
|           +--> repayment  |
+---------------------------+
```

## Components

- `MerchantFacet` registers merchants, updates payout addresses, lets the underwriter enable credit, and exposes merchant/revenue views.
- `InvoiceFacet` creates and cancels invoices. `payInvoice` is the only revenue-recognition entry point: it pulls gross USDC, records gross revenue, applies any principal-first repayment, and sends the net amount to the merchant payout.
- `CreditFacet` quotes fixed V1 credit, creates one active advance per merchant, tracks principal receivables separately from fees, and exposes pool statistics.
- `RevlineStorage` holds the USDC address, merchants, invoices, advances, daily revenue buckets, and protocol totals in a shared ERC-7201-style namespace.
- `CreditMath`, `RevenueLib`, and `USDCTransferLib` centralize the fixed economics, 30-day UTC bucket calculation, and safe ERC-20 calls.
- Lattice supplies the Diamond proxy, `Receive` zero-selector routing, loupe/ERC-165, `AccessControl`, `Pausable`, shared `ReentrancyGuard`, and admin-gated Diamond cuts. `Receive` accepts empty-calldata native Arc value only; it does not alter Revline’s six-decimal ERC-20 reserve accounting. Lattice is infrastructure only, not the Revline product or reserve-accounting model.

## Asset and accounting flow

All values below are six-decimal Arc USDC ERC-20 units.

```text
reserve/direct/CCTP funding -> Diamond liquid USDC only
successful payInvoice       -> merchant gross revenue + Diamond settlement
draw                         -> liquid USDC decreases; principal receivable increases
principal repayment         -> liquid USDC increases; principal receivable decreases
fee repayment               -> liquid USDC and realized fee income increase
```

`managedAssets = liquid USDC + outstanding principal`. Fees are not receivables and are recognized only after collection. A 50 USDC invoice always records 50 USDC gross revenue even when 10 USDC is retained for repayment.

## Trust boundaries

- Merchants and customers are untrusted callers. A payer must differ from the merchant address, but the MVP does not prove that they are independently controlled.
- Underwriters decide whether a registered merchant may draw; this human gate is the MVP mitigation for sybil revenue and unsecured-credit risk.
- The admin controls pause, roles, and upgrades and should be treated as fully trusted for the MVP.
- Arc USDC is fixed at `0x3600000000000000000000000000000000000000`; direct transfers and CCTP mints affect liquidity but cannot write revenue state.
- The browser receives only public chain configuration and the public Diamond address. Signer keys and the credential-bearing script RPC stay in local Node/Foundry configuration.

## Deployment composition

`DeployRevline.s.sol` installs Receive, ERC-165, access control, pausing, loupe, admin DiamondCut, and the three Revline facets. `RevlineInit` runs during Diamond initialization, grants the deployer default-admin and underwriter roles, registers interfaces, starts unpaused, and stores the USDC address. The deployment tests verify role ownership, zero-selector routing, upgrade authorization, pause behavior, native/ERC-20 accounting separation, and initializer composition.
