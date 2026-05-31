# 📘 Documentation index

[![License](https://img.shields.io/badge/License-MIT-blue)]()
[![Lang](https://img.shields.io/badge/Language-EN-darkgreen)]()
[![Format](https://img.shields.io/badge/Format-Markdown_pairs-orange)]()

> 🎯 Documentation for the PostgreSQL 18 HA lab. Markdown pairs: each `.md`
> has a `_PL.md` Polish counterpart. Polish counterpart of this index:
> [README_PL.md](README_PL.md).

> 🏠 **Project home (GitHub Pages):** [index.html](index.html) · 🇵🇱 [index_PL.html](index_PL.html) —
> a visual landing page (overview, architecture, components, scenarios, results).

## Pages

- [ARCHITECTURE.md](ARCHITECTURE.md) — components, failover sequence, infra (DNS+NTP)
- [SETUP.md](SETUP.md) — Windows 11 walkthrough, prereqs, NRPT integration
- [SCENARIOS.md](SCENARIOS.md) — 13 failure-mode scenarios with expected output
- [RUN_REPORT.md](RUN_REPORT.md) — auto-generated run report + interactive [run-report.html](run-report.html) (built by `lab.ps1 report`)
- [AGENTIC_RUN_ALL.md](AGENTIC_RUN_ALL.md) — agentic full-suite run (13/13 PASS) + interactive [agentic-run-all.html](agentic-run-all.html) (built by `lab.ps1 report agentic`)
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — VBox/scancode, NRPT fallback, watchdog

## Diagrams

Referenced from individual MD pages. Sources in `diagrams/`:

- `architecture.svg` — node-and-link view of the full lab
- `failover-flow.svg` — what happens when the primary dies
- `dns-flow.svg` — how a name resolution from the host reaches infra
