# pgha-client

[![License](https://img.shields.io/badge/License-MIT-blue)]()
[![Python](https://img.shields.io/badge/Python-3.11+-darkgreen)]()
[![psycopg](https://img.shields.io/badge/psycopg-3.2+-336791)]()

> Writer / reader / monitor test client for the PostgreSQL 18 HA lab.
> Polish counterpart: [README_PL.md](README_PL.md).

Installed automatically by `60-client.sh` on the `cli` VM. Run as `lab` user.

## Commands

```
pgha-client writer  [--rate HZ] [--target {haproxy,direct}] [--duration SEC] [--report FILE]
pgha-client reader  [--rate HZ] [--target {haproxy,direct}] [--duration SEC] [--report FILE]
pgha-client monitor [--refresh SEC] [--snapshot]
```

## Targets

- `haproxy` (default) — connects to `db.lab.test:5000` (HAProxy primary listener).
- `direct` — multi-host libpq via `target_session_attrs=read-write`.

## HA metrics (`--report`)

`writer`/`reader` track the **availability gap** across a failover and, when
`--report FILE` is given, write a JSON summary at the end:

```json
{ "role": "writer", "inserts": 540, "outages": 1, "reconnects": 4,
  "downtime_total_sec": 7.0, "downtime_max_sec": 7.0, "actual_hz": 8.97 }
```

`reader` additionally reports `max_id_start` / `max_id_end` (proof writes progressed
and replicated). These files feed the report generator (`report/gen_report.py` →
`docs/run-report.html`) and are produced by scenario 13.

`monitor --snapshot` prints a single cluster-state JSON (from the Patroni REST API)
and exits — used to capture `cluster-before.json` / `cluster-after.json`.

## Examples

```bash
# Steady write at 10 Hz through HAProxy
pgha-client writer --rate 10

# Read-only client at 50 Hz
pgha-client reader --rate 50

# 60s timed run that records HA metrics to JSON (as in scenario 13)
pgha-client writer --rate 10 --duration 60 --report /tmp/writer.json

# Live cluster TUI (rich.live)
pgha-client monitor

# One-shot cluster state as JSON
pgha-client monitor --snapshot
```
