# API Examples

Set the API key and correlation ID:

```bash
export API_KEY=settleflow_dev_key_change_me
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

Inspect a wallet statement:

```bash
curl -sS "$BASE_URL/v1/wallets/<wallet_uuid>/statement" \
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
    "provider_balance_cents": 10000
  }'
```
