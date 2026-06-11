# Benchmark Methodology

Benchmarks use k6 against the HTTP API with a seeded organization and API key.

## Scenarios

- Smoke: one virtual user validates the end-to-end command path.
- Load: steady traffic for normal expected usage.
- Stress: higher VU count to identify saturation.
- Spike: rapid VU ramp to observe queueing and rate-limit behavior.

## Metrics captured

- p50, p95, p99 latency.
- Requests per second.
- Error rate.
- CPU and memory notes from local host or container runtime.
- Database connection pressure.

## Command examples

```bash
BASE_URL=http://localhost:3000 API_KEY="<development API credential printed by bin/rails db:seed>" SCENARIO=smoke k6 run benchmarks/k6-financial-workflow.js
BASE_URL=http://localhost:3000 API_KEY="<development API credential printed by bin/rails db:seed>" SCENARIO=load k6 run benchmarks/k6-financial-workflow.js
BASE_URL=http://localhost:3000 API_KEY="<development API credential printed by bin/rails db:seed>" SCENARIO=stress k6 run benchmarks/k6-financial-workflow.js
BASE_URL=http://localhost:3000 API_KEY="<development API credential printed by bin/rails db:seed>" SCENARIO=spike k6 run benchmarks/k6-financial-workflow.js
```
