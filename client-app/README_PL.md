# pgha-client

[![Licencja](https://img.shields.io/badge/Licencja-MIT-blue)]()
[![Python](https://img.shields.io/badge/Python-3.11+-darkgreen)]()
[![psycopg](https://img.shields.io/badge/psycopg-3.2+-336791)]()

> Klient testowy writer / reader / monitor dla laboratorium PostgreSQL 18 HA.
> Wersja angielska: [README.md](README.md).

Instalowany automatycznie przez `60-client.sh` na maszynie `cli`. Uruchamiany z konta `lab`.

## Komendy

```
pgha-client writer  [--rate HZ] [--target {haproxy,direct}] [--duration SEC] [--report FILE]
pgha-client reader  [--rate HZ] [--target {haproxy,direct}] [--duration SEC] [--report FILE]
pgha-client monitor [--refresh SEC] [--snapshot]
```

## Cele połączenia

- `haproxy` (domyślny) — połączenie do `db.lab.test:5000` (HAProxy primary listener).
- `direct` — multi-host libpq z parametrem `target_session_attrs=read-write`.

## Metryki HA (`--report`)

`writer`/`reader` mierzą **okno niedostępności** podczas failoveru i — gdy podano
`--report FILE` — zapisują na końcu podsumowanie JSON:

```json
{ "role": "writer", "inserts": 540, "outages": 1, "reconnects": 4,
  "downtime_total_sec": 7.0, "downtime_max_sec": 7.0, "actual_hz": 8.97 }
```

`reader` dodatkowo raportuje `max_id_start` / `max_id_end` (dowód, że zapisy
postępowały i replikowały się). Pliki te zasilają generator raportu
(`report/gen_report.py` → `docs/run-report_PL.html`) i są produkowane przez scenariusz 13.

`monitor --snapshot` wypisuje jednorazowo stan klastra jako JSON (z Patroni REST API)
i kończy — używany do przechwycenia `cluster-before.json` / `cluster-after.json`.

## Przykłady

```bash
# Stały zapis 10 Hz przez HAProxy
pgha-client writer --rate 10

# Klient read-only 50 Hz
pgha-client reader --rate 50

# Przebieg 60s z zapisem metryk HA do JSON (jak w scenariuszu 13)
pgha-client writer --rate 10 --duration 60 --report /tmp/writer.json

# Live TUI klastra (rich.live)
pgha-client monitor

# Jednorazowy stan klastra jako JSON
pgha-client monitor --snapshot
```
