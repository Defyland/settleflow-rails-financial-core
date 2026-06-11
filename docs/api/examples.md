# API Examples

Set the API key and correlation ID:

```bash
export API_KEY="<development API credential printed by bin/rails db:seed>"
export BASE_URL=http://localhost:3000
```

Create a customer:

```bash
curl -sS "$BASE_URL/v1/customers" \
  -H "X-Api-Key: $API_KEY" \
  -H "Idempotency-Key: customer-001" \
  -H "Content-Type: application/json" \
  -d '{
    "external_id": "customer-001",
    "legal_name": "Maria Silva",
    "document_kind": "cpf",
    "document_number": "11144477735"
  }'
```

Create a wallet:

```bash
curl -sS "$BASE_URL/v1/wallets" \
  -H "X-Api-Key: $API_KEY" \
  -H "Idempotency-Key: wallet-001" \
  -H "Content-Type: application/json" \
  -d '{
    "customer_id": "<customer_uuid>",
    "external_id": "wallet-001",
    "currency": "BRL"
  }'
```

Fund a wallet:

```bash
curl -sS "$BASE_URL/v1/fundings" \
  -H "X-Api-Key: $API_KEY" \
  -H "Idempotency-Key: funding-001" \
  -H "Content-Type: application/json" \
  -d '{
    "wallet_id": "<wallet_uuid>",
    "external_id": "funding-001",
    "amount_cents": 10000
  }'
```

Post an internal transfer:

```bash
curl -sS "$BASE_URL/v1/transfers" \
  -H "X-Api-Key: $API_KEY" \
  -H "Idempotency-Key: transfer-001" \
  -H "Content-Type: application/json" \
  -d '{
    "source_wallet_id": "<source_wallet_uuid>",
    "destination_wallet_id": "<destination_wallet_uuid>",
    "external_id": "transfer-001",
    "amount_cents": 2500,
    "memo": "shared bill"
  }'
```

Post a split:

```bash
curl -sS "$BASE_URL/v1/split_payments" \
  -H "X-Api-Key: $API_KEY" \
  -H "Idempotency-Key: split-001" \
  -H "Content-Type: application/json" \
  -d '{
    "source_wallet_id": "<source_wallet_uuid>",
    "external_id": "split-001",
    "entries": [
      { "destination_wallet_id": "<destination_wallet_uuid_1>", "amount_cents": 2000 },
      { "destination_wallet_id": "<destination_wallet_uuid_2>", "amount_cents": 3000 }
    ],
    "memo": "merchant split"
  }'
```

Schedule and settle a D+N payout:

```bash
curl -sS "$BASE_URL/v1/payouts" \
  -H "X-Api-Key: $API_KEY" \
  -H "Idempotency-Key: payout-001" \
  -H "Content-Type: application/json" \
  -d '{
    "wallet_id": "<wallet_uuid>",
    "external_id": "payout-001",
    "amount_cents": 4000,
    "settlement_delay_days": 1,
    "destination_reference": "bank-account-001"
  }'

curl -sS "$BASE_URL/v1/payouts/<payout_uuid>/settle" \
  -H "X-Api-Key: $API_KEY" \
  -H "Idempotency-Key: payout-001-settle" \
  -H "Content-Type: application/json" \
  -d '{}'
```

Create a Pix payment:

```bash
curl -sS "$BASE_URL/v1/pix_payments" \
  -H "X-Api-Key: $API_KEY" \
  -H "Idempotency-Key: pix-001" \
  -H "Content-Type: application/json" \
  -d '{
    "wallet_id": "<wallet_uuid>",
    "external_id": "pix-001",
    "pix_key": "receiver@example.com",
    "receiver_name": "Receiver Ltd",
    "amount_cents": 4500
  }'
```

Settle a refund for a settled Pix payment:

```bash
curl -sS "$BASE_URL/v1/refunds" \
  -H "X-Api-Key: $API_KEY" \
  -H "Idempotency-Key: refund-001" \
  -H "Content-Type: application/json" \
  -d '{
    "pix_payment_id": "<pix_payment_uuid>",
    "external_id": "refund-001",
    "amount_cents": 1500,
    "reason": "customer_request"
  }'
```

Open a MED case through the public API:

```bash
curl -sS "$BASE_URL/v1/med_cases" \
  -H "X-Api-Key: $API_KEY" \
  -H "Idempotency-Key: med-001" \
  -H "Content-Type: application/json" \
  -d '{
    "pix_payment_id": "<pix_payment_uuid>",
    "external_id": "med-001",
    "amount_cents": 1500,
    "reason": "fraud_report"
  }'

```

MED acceptance and rejection are not public write commands. They require ops maker-checker approval in `/ops`; the public API returns `authorization_failed` for terminal MED resolution attempts.

Inspect a wallet statement:

```bash
curl -sS "$BASE_URL/v1/wallets/<wallet_uuid>/statement" \
  -H "X-Api-Key: $API_KEY"
```

Explain a wallet balance:

```bash
curl -sS "$BASE_URL/v1/wallets/<wallet_uuid>/balance_explanation" \
  -H "X-Api-Key: $API_KEY"
```

Run reconciliation:

```bash
curl -sS "$BASE_URL/v1/reconciliation_runs" \
  -H "X-Api-Key: $API_KEY" \
  -H "Idempotency-Key: recon-2026-05-29" \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "bank-sandbox",
    "statement_date": "2026-05-29",
    "provider_balance_cents": 10000,
    "statement_entries": [
      { "external_id": "funding-001", "amount_cents": 10000, "occurred_on": "2026-05-29" }
    ]
  }'
```
