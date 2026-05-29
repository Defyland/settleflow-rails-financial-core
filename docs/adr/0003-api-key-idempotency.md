# ADR 0003: API Keys and Idempotent Commands

## Status

Accepted.

## Context

Financial APIs are commonly called by servers, retry after network failures, and must prevent duplicated debits. Tenant isolation must be simple to operate in local and CI environments.

## Decision

SettleFlow authenticates v1 endpoints with `X-Api-Key`. API keys are stored as SHA-256 digests. Write endpoints accept `Idempotency-Key`; the service stores method, path, request hash, status, response status, and response body.

## Consequences

- Duplicate retries with the same payload replay the original response.
- Reusing a key with a different payload returns `409 idempotency_conflict`.
- API key rotation is not implemented yet and is listed in the roadmap.
- JWT/OIDC can be added later without weakening current tenant scoping.
