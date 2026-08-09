# Revline

Revenue-backed USDC working-capital advances on Arc Testnet. Only payments made through `payInvoice` count as verified merchant revenue. All protocol USDC values use six decimals.

## Arc Testnet deployment

Copy `.env.example` to `.env`, add funded local wallet keys, and keep `.env` uncommitted. Set `ARC_TESTNET_RPC_URL` in local `.env` to the supplied canonical Arc Testnet value; it is runtime configuration and must not be committed or exposed to browser code.

```sh
source .env
forge script script/DeployRevline.s.sol:DeployRevline \
  --rpc-url "$ARC_TESTNET_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast -vvvv
```

Set the printed Diamond address as `REVLINE_ADDRESS` in local `.env`. The deployer is also the initial underwriter.

Enable an already registered merchant:

```sh
source .env
forge script script/EnableMerchant.s.sol:EnableMerchant \
  --rpc-url "$ARC_TESTNET_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast -vvvv
```

Seed the canonical demo with an unused merchant wallet and a customer wallet holding at least 500 USDC. The underwriter wallet must hold at least 1,000 USDC for the reserve transfer. The script sends 1,000 USDC directly to the Diamond as reserve funding, then routes three payments totaling 500 USDC through real invoices; reserve funding does not create merchant revenue.
Set `MERCHANT_ADDRESS` to the address derived from `MERCHANT_PRIVATE_KEY` before running the smoke checks.

```sh
source .env
forge script script/SeedDemo.s.sol:SeedDemo \
  --rpc-url "$ARC_TESTNET_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast -vvvv
```

`SeedDemo` intentionally rejects an already registered merchant. Use a fresh merchant key for a repeatable 500-USDC demo rather than accidentally adding revenue to an existing profile.

## Smoke checks

```sh
source .env
cast call "$REVLINE_ADDRESS" \
  "getMerchant(address)(bool,bool,address,uint64,uint256,uint256,uint256,uint256,string)" \
  "$MERCHANT_ADDRESS" --rpc-url "$ARC_TESTNET_RPC_URL"

cast call "$REVLINE_ADDRESS" "trailingRevenue(address)(uint256)" \
  "$MERCHANT_ADDRESS" --rpc-url "$ARC_TESTNET_RPC_URL"

cast call "$REVLINE_ADDRESS" "creditQuote(address)(uint256,uint256,uint256,bool,bool,bool)" \
  "$MERCHANT_ADDRESS" --rpc-url "$ARC_TESTNET_RPC_URL"

cast call "$REVLINE_ADDRESS" "poolStats()(uint256,uint256,uint256,uint256,uint256,uint256)" \
  --rpc-url "$ARC_TESTNET_RPC_URL"
```

For the seeded demo, expect `trailingRevenue = 500000000`, `creditLimit = 100000000`, and `liquidUSDC >= 1000000000` before an advance draw.

## Arcscan evidence

No canonical Arc deployment has been recorded in this repository yet. After a live deployment, replace these placeholders with immutable transaction URLs:

- Diamond deployment: `https://testnet.arcscan.app/tx/<DEPLOYMENT_TX_HASH>`
- Historical invoice payment: `https://testnet.arcscan.app/tx/<INVOICE_PAYMENT_TX_HASH>`
- Advance draw: `https://testnet.arcscan.app/tx/<ADVANCE_DRAW_TX_HASH>`
- Post-draw invoice payment: `https://testnet.arcscan.app/tx/<POST_DRAW_PAYMENT_TX_HASH>`

## Local verification

```sh
forge fmt --check
forge build
forge test -vv
```
