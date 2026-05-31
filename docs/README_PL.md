# 📘 Indeks dokumentacji

[![Licencja](https://img.shields.io/badge/Licencja-MIT-blue)]()
[![Jezyk](https://img.shields.io/badge/J%C4%99zyk-PL-darkgreen)]()
[![Format](https://img.shields.io/badge/Format-Pary_Markdown-orange)]()

> 🎯 Dokumentacja laboratorium PostgreSQL 18 HA. Pary Markdown: każdy `.md`
> ma odpowiednik `_PL.md` po polsku. Wersja angielska tego indeksu:
> [README.md](README.md).

> 🏠 **Strona główna projektu (GitHub Pages):** 🇵🇱 [index_PL.html](index_PL.html) · [index.html](index.html) —
> wizualna strona-wizytówka (przegląd, architektura, komponenty, scenariusze, wyniki).

## Strony

- [ARCHITECTURE_PL.md](ARCHITECTURE_PL.md) — komponenty, sekwencja failover, infra (DNS+NTP)
- [SETUP_PL.md](SETUP_PL.md) — walkthrough Windows 11, wymagania, integracja NRPT
- [SCENARIOS_PL.md](SCENARIOS_PL.md) — 13 scenariuszy awarii z oczekiwanym outputem
- [RUN_REPORT_PL.md](RUN_REPORT_PL.md) — auto-generowany raport przebiegu + interaktywny [run-report_PL.html](run-report_PL.html) (budowany przez `lab.ps1 report`)
- [AGENTIC_RUN_ALL_PL.md](AGENTIC_RUN_ALL_PL.md) — agentowy przebieg pełnej suity (13/13 PASS) + interaktywny [agentic-run-all_PL.html](agentic-run-all_PL.html) (budowany przez `lab.ps1 report agentic`)
- [TROUBLESHOOTING_PL.md](TROUBLESHOOTING_PL.md) — VBox/scancode, fallback NRPT, watchdog

## Diagramy

Referowane z poszczególnych stron MD. Źródła w `diagrams/`:

- `architecture_PL.svg` — widok komponentów i połączeń całego labu (PL); `architecture.svg` — wersja EN
- `failover-flow_PL.svg` — co się dzieje gdy umiera primary (PL); `failover-flow.svg` — wersja EN
- `dns-flow_PL.svg` — jak rozwiązanie nazwy z hosta dociera do infra (PL); `dns-flow.svg` — wersja EN
