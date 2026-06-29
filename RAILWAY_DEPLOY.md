# Railway Deploy

This guide configures SettleFlow as a single-service Railway deployment for
public demo and reviewer evaluation.

## Runtime shape

- builder: `Dockerfile`
- activation health check: `/up`
- readiness endpoint available separately at `/ready`
- database migration/bootstrap: `bin/docker-entrypoint` runs `db:prepare`
- background jobs: `SOLID_QUEUE_IN_PUMA=true` for the single-service demo path

The demo path is intentionally simpler than the Kamal topology. It is meant to
prove the product surface, not to model the final production split of web and
job processes.

## Required variables

Set these in Railway:

```bash
RAILS_ENV=production
DATABASE_URL=${{Postgres.DATABASE_URL}}
RAILS_MASTER_KEY=<local config/master.key>
SOLID_QUEUE_IN_PUMA=true
RAILS_SERVE_STATIC_FILES=true
SETTLEFLOW_OPERATOR_EMAIL=<ops-login-email>
SETTLEFLOW_OPERATOR_PASSWORD=<ops-login-password>
SETTLEFLOW_OPERATOR_ROLE=admin
```

Optional variables for richer demo behavior:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=<collector-endpoint>
REDIS_URL=<managed-redis-url>
CLICKHOUSE_URL=<analytics-http-endpoint>
```

## Suggested flow

```bash
railway login
railway init --name settleflow-financial-core
railway add --database postgres
railway up
railway domain
```

## Five-minute verification

After deploy:

```bash
railway status
railway logs
curl -fsS "$RAILWAY_PUBLIC_DOMAIN/up"
curl -fsS "$RAILWAY_PUBLIC_DOMAIN/ready"
```

Then sign in to `/ops` with the configured operator account and exercise one
read-only path plus one financial write path through the API or the ops console.

## Limits

- The Railway path is a demo topology, not the final production topology.
- Single-service mode shares the web process with Solid Queue supervision.
- ClickHouse, Redis, and provider adapters remain optional integrations for this
  deployment path.
