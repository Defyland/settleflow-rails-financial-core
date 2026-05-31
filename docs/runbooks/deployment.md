# Deployment Runbook

## Target

Production deployment uses Docker, Thruster, Kamal, Rails credentials, PostgreSQL, and the Solid adapters for queue, cache, and cable.

## Required secrets

- `RAILS_MASTER_KEY`
- `KAMAL_REGISTRY_PASSWORD`
- `SETTLEFLOW_RAILS_FINANCIAL_CORE_DATABASE_PASSWORD`
- `SETTLEFLOW_OPERATOR_EMAIL`
- `SETTLEFLOW_OPERATOR_PASSWORD`

## Preflight

1. Provision PostgreSQL databases for `primary`, `queue`, `cache`, and `cable`.
2. Confirm `POSTGRES_HOST`, `POSTGRES_PORT`, and `POSTGRES_USER` in `config/deploy.yml`.
3. Set registry credentials and Rails secrets in the Kamal secrets store.
4. Run `bin/ci` locally and ensure the Docker build passes.

## Deploy

1. Build and push the image with Kamal.
2. Run database migrations.
3. Boot web and job roles.
4. Check `/up`, `/ready`, and `/metrics`.
5. Sign in to `/ops` with the seeded admin operator and verify outbox, ledger, and Pix pages render.

## Rollback

1. Roll back the Kamal image to the previous tag.
2. Do not roll back financial ledger migrations without an explicit data repair plan.
3. If a migration added nullable columns only, leave the schema forward-compatible and restore app code first.
4. Preserve outbox and audit rows generated during the failed release.
