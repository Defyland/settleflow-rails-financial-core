# Benchmark Baseline

Baseline target environment:

- Ruby 3.3.6
- Rails 8.1
- PostgreSQL on localhost or Docker
- Puma single process
- k6 from local workstation

## Acceptance thresholds

| Scenario | p95 target | Error rate target |
| --- | ---: | ---: |
| Smoke | < 250 ms | 0% |
| Load | < 500 ms | < 1% |
| Stress | < 1000 ms | < 5% |
| Spike | < 1500 ms | < 5% |

The current implementation is optimized for correctness and observability first. Performance tuning should focus on ledger index selectivity, projection lock contention, and outbox worker throughput.
