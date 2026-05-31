# 📊 report/ — generator raportu z przebiegu scenariuszy HA

[![Python](https://img.shields.io/badge/Python-3.11%2B-blue)]()
[![Zaleznosci](https://img.shields.io/badge/Zaleznosci-tylko_stdlib-success)]()
[![Wyjscie](https://img.shields.io/badge/Wyjscie-MD_%2B_HTML-blueviolet)]()
[![Pages](https://img.shields.io/badge/GitHub-Pages_ready-orange)]()

> 🎯 Zamienia logi scenariuszy i metryki JSON z `pgha-client` w tabelę wyników, pełny
> transcript komend/outputów per scenariusz oraz **metryki failoveru z perspektywy
> aplikacji** (downtime, reconnecty). Tworzy `RUN_REPORT.md` / `RUN_REPORT_PL.md` oraz
> interaktywne strony `run-report.html` (EN) / `run-report_PL.html` (PL) dla GitHub Pages.
> English version: [README.md](README.md).

## 🧩 Wejście

| Źródło | Ścieżka (domyślna) | Tworzone przez |
|---|---|---|
| Logi scenariuszy | `/var/log/postgres18-ha-lab/scenarios/<NN>-<nazwa>-<ts>.log` | `scenarios/*.sh` (`scenario_start`/`scenario_end`) |
| Metryki aplikacji | `<log-dir>/app/{writer,reader}.json` | `pgha-client writer/reader --report` (scenariusz 13) |
| Snapshoty klastra | `<log-dir>/app/cluster-{before,after}.json` | `pgha-client monitor --snapshot` (scenariusz 13) |

Dla każdego numeru scenariusza (`NN`) brany jest najnowszy log; starsze przebiegi są pomijane.

## 🚀 Użycie

```bash
# Na VM cli (po uruchomieniu scenariuszy):
python3 report/gen_report.py \
    --log-dir /var/log/postgres18-ha-lab/scenarios \
    --out-dir /usr/local/lib/postgres18-ha-lab/report/out

# Z hosta Windows (scp logów, generacja, umieszczenie w docs/):
.\lab.ps1 report
```

| Flaga | Domyślnie | Znaczenie |
|---|---|---|
| `--log-dir` | `/var/log/postgres18-ha-lab/scenarios` | katalog z logami scenariuszy `*.log` |
| `--app-dir` | `<log-dir>/app` | katalog z JSON-ami `pgha-client` |
| `--out-dir` | `docs` | gdzie zapisać pliki raportu (MD + HTML, EN + PL) |
| `--generated-at` | teraz | nadpisanie znacznika czasu raportu |

## ✅ Wyjście

- `RUN_REPORT.md` / `RUN_REPORT_PL.md` — Markdown (badge'y, tabela wyników, metryki app, transcripty).
- `run-report.html` (EN) / `run-report_PL.html` (PL) — samodzielne strony w dark theme; rozwijane
  transcripty `<details>`, koloryzowane `PASS`/`FAIL`/`INFO` oraz pasek okna niedostępności z metryk
  writera. Wrzuć do `docs/` (`.nojekyll` już jest) pod GitHub Pages.
  (`--agentic` brenduje przebieg jako raport pełnej suity: `AGENTIC_RUN_ALL.md` / `_PL.md` +
  `agentic-run-all.html` / `agentic-run-all_PL.html`.)

## 🔗 Powiązane

- [`../scenarios/13-app-failover-continuous.sh`](../scenarios/13-app-failover-continuous.sh) — produkuje metryki aplikacji.
- [`../client-app/README_PL.md`](../client-app/README_PL.md) — `pgha-client` writer/reader/monitor + `--report`.
- [`../docs/AGENTIC_RUN_ALL_PL.md`](../docs/AGENTIC_RUN_ALL_PL.md) — raport przebiegu pełnej suity (agentowy).
