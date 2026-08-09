# Revline three-minute demo

## Before recording

- Open the deployed Arc Testnet Diamond on Arcscan.
- Open the Revline merchant dashboard with a registered, underwriter-enabled merchant.
- Confirm the pool has at least 1,000 USDC liquid reserve and the merchant has exactly 500 USDC trailing routed revenue.
- Open a fresh 50 USDC invoice in the customer wallet.
- Keep Arcscan links for deployment, historical payments, draw, post-draw payment, and Circle source/destination evidence ready in separate tabs.
- Do not expose `.env`, RPC credentials, private keys, or wallet seed phrases.

If live credentials are unavailable, use `forge test --match-test test_canonicalRevenueAdvanceAndRepaymentScenario -vvvv` to demonstrate the same numerical state transitions locally and state clearly that it is test evidence, not a live transaction.

## 0:00–0:20 — Problem

“Stablecoin businesses can prove cash flow onchain, but still need working capital without posting crypto collateral.”

Show the landing page and the “Revenue creates credit” loop.

## 0:20–0:40 — Product

“Revline turns routed USDC revenue into an underwriter-approved working-capital advance. Only successful Revline invoice payments count; direct reserve and bridge funding never become merchant revenue.”

Show the merchant and pool navigation.

## 0:40–1:00 — Circle and Arc

Show the Arcscan deployment and the Circle App Kit/CCTP evidence from Base Sepolia to the Revline Diamond.

“Circle moves reserve liquidity to Arc. It increases the pool’s liquid USDC, not merchant revenue.”

## 1:00–1:25 — Merchant

Show:

- trailing 30-day revenue: `500 USDC`;
- credit limit: `100 USDC`;
- advance rate: `20%`;
- fixed fee: `5%`;
- future-revenue repayment share: `20%`.

“The underwriter has explicitly enabled this merchant. Revline’s routed revenue is protocol-verifiable, not fraud-proof underwriting.”

## 1:25–1:50 — Draw

Draw `100 USDC`, wait for confirmation, and open the Arcscan transaction.

Show:

- merchant receives `100 USDC`;
- principal is `100 USDC`;
- fixed fee is `5 USDC`;
- total obligation is `105 USDC`;
- pool liquid USDC changes `1,000 → 900`;
- outstanding principal changes `0 → 100`;
- managed assets remain `1,000 USDC`.

## 1:50–2:30 — Automatic repayment

From the customer wallet, approve the exact `50 USDC` invoice amount if needed, then pay it. Wait for confirmation and open the Arcscan transaction.

Show:

- gross verified revenue: `50 USDC`;
- merchant receives `40 USDC`;
- Revline retains `10 USDC`;
- principal outstanding changes `100 → 90 USDC`;
- remaining total obligation is `95 USDC`;
- lifetime gross revenue changes `500 → 550 USDC`.

## 2:30–2:50 — Accounting

Show pool statistics:

```text
after draw:      liquid 900 + principal 100 = managed assets 1,000
after repayment: liquid 910 + principal  90 = managed assets 1,000
fees earned: 0
```

“Lending exchanges cash for a principal receivable. Principal repayment restores liquidity; it is not profit. The five-USDC fee becomes income only when it is actually collected.”

## 2:50–3:00 — Close

“Revenue creates credit. Future revenue retires credit.”

End on the merchant dashboard with the confirmed repayment transaction visible.

## Evidence checklist

- Diamond address and deployment transaction
- role/underwriter setup transaction
- three historical invoice payments totaling 500 USDC
- reserve balance at or above 1,000 USDC
- 100 USDC draw transaction and merchant balance delta
- 50 USDC post-draw invoice transaction
- merchant `+40`, reserve `+10`, principal `100 → 90`
- managed assets `1,000 → 1,000` across principal-only repayment
- Circle source burn/App Kit result/destination balance delta, if the bridge was run
