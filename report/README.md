# 📊 report/ — HA scenario run report generator

[![Python](https://img.shields.io/badge/Python-3.11%2B-blue)]()
[![Deps](https://img.shields.io/badge/Deps-stdlib_only-success)]()
[![Output](https://img.shields.io/badge/Output-MD_%2B_HTML-blueviolet)]()
[![Pages](https://img.shields.io/badge/GitHub-Pages_ready-orange)]()

> 🎯 Turns scenario logs and `pgha-client` JSON metrics into a results table, a full
> command/output transcript per scenario, and **app-perspective failover metrics**
> (downtime, reconnects). Produces `RUN_REPORT.md` / `RUN_REPORT_PL.md` and the
> interactive pages `run-report.html` (EN) / `run-report_PL.html` (PL) for GitHub Pages.
> Wersja polska: [README_PL.md](README_PL.md).

## 🧩 Inputs

| Source | Path (default) | Produced by |
|---|---|---|
| Scenario logs | `/var/log/postgres18-ha-lab/scenarios/<NN>-<name>-<ts>.log` | `scenarios/*.sh` (`scenario_start`/`scenario_end`) |
| App metrics | `<log-dir>/app/{writer,reader}.json` | `pgha-client writer/reader --report` (scenario 13) |
| Cluster snapshots | `<log-dir>/app/cluster-{before,after}.json` | `pgha-client monitor --snapshot` (scenario 13) |

The newest log per scenario number (`NN`) is used; older runs are ignored.

## 🚀 Usage

```bash
# On the cli VM (after running scenarios):
python3 report/gen_report.py \
    --log-dir /var/log/postgres18-ha-lab/scenarios \
    --out-dir /usr/local/lib/postgres18-ha-lab/report/out

# From the Windows host (scp logs back, generate, place in docs/):
.\lab.ps1 report
```

| Flag | Default | Meaning |
|---|---|---|
| `--log-dir` | `/var/log/postgres18-ha-lab/scenarios` | directory with scenario `*.log` |
| `--app-dir` | `<log-dir>/app` | directory with `pgha-client` JSON |
| `--out-dir` | `docs` | where to write the report files (MD + HTML, EN + PL) |
| `--generated-at` | now | override the report timestamp |

## ✅ Output

- `RUN_REPORT.md` / `RUN_REPORT_PL.md` — Markdown (badges, results table, app metrics, transcripts).
- `run-report.html` (EN) / `run-report_PL.html` (PL) — self-contained dark-theme pages; collapsible
  `<details>` transcripts, colourised `PASS`/`FAIL`/`INFO`, and a downtime bar from the writer
  metrics. Drop into `docs/` (`.nojekyll` already present) for GitHub Pages.
  (`--agentic` brands the run as a full-suite report: `AGENTIC_RUN_ALL.md` / `_PL.md` +
  `agentic-run-all.html` / `agentic-run-all_PL.html`.)

## 🔗 Related

- [`../scenarios/13-app-failover-continuous.sh`](../scenarios/13-app-failover-continuous.sh) — produces the app metrics.
- [`../client-app/README.md`](../client-app/README.md) — `pgha-client` writer/reader/monitor + `--report`.
- [`../docs/AGENTIC_RUN_ALL.md`](../docs/AGENTIC_RUN_ALL.md) — the agentic full-suite run report.
