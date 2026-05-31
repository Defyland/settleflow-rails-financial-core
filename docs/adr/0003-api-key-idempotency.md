# ADR 0003: API Keys and Idempotent Commands

## Status

Accepted.

## Context

Financial APIs are commonly called by servers, retry after network failures, and must prevent duplicated debits. Tenant isolation must be simple to operate in local and CI environments.

## Decision

SettleFlow authenticates v1 endpoints with `X-Api-Key`. Current API credentials are issued once, returned only at creation, looked up by non-secret prefixes, and stored as HMAC-SHA256 digests using the Rails secret key base. Credentials support scopes, expiry, revocation, and last-used tracking. Legacy organization-level SHA-256 API key digests remain only for seed/demo compatibility.

Write endpoints accept `Idempotency-Key`; the service stores method, path, request hash, status, response status, and response body.

## Consequences

- Duplicate retries with the same payload replay the original response.
- Reusing a key with a different payload returns `409 idempotency_conflict`.
- Credential rotation is handled by issuing a replacement credential and revoking the old one.
- JWT/OIDC can be added later without weakening current tenant scoping.
