#!/usr/bin/env python3
# ==============================================================================
# Tytul:        gen_report.py
# Opis:         Generator raportu z przebiegu scenariuszy HA. Czyta logi scenariuszy
#               (/var/log/.../scenarios/*.log) oraz metryki JSON z pgha-client
#               (app/*.json) i tworzy RUN_REPORT.md, RUN_REPORT_PL.md oraz
#               interaktywny run-report.html (GitHub Pages).
# Description [EN]: HA scenario run report generator. Reads scenario logs and the
#               pgha-client JSON metrics (app/*.json) and emits RUN_REPORT.md,
#               RUN_REPORT_PL.md and an interactive run-report.html (GitHub Pages).
#
# Autor:        KCB Kris
# Data:         2026-05-31
# Wersja:       1.0
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - Python 3.11+ (tylko biblioteka standardowa)
# Requirements [EN]: - Python 3.11+ (standard library only)
#
# Uzycie [PL]:       python3 gen_report.py --log-dir /var/log/postgres18-ha-lab/scenarios --out-dir docs
# Usage [EN]:        python3 gen_report.py --log-dir /var/log/postgres18-ha-lab/scenarios --out-dir docs
# ==============================================================================
"""Generuje raport MD + interaktywny HTML z logow scenariuszy i metryk pgha-client."""

from __future__ import annotations

import argparse
import html
import json
import re
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

LOG_RE = re.compile(r"^(?P<num>\d{2})-(?P<name>.+)-(?P<ts>\d{8}T\d{6})\.log$")


@dataclass
class Scenario:
    """Pojedynczy scenariusz odtworzony z najnowszego logu."""

    num: str
    name: str
    started: str
    result: str  # PASS | FAIL | UNKNOWN
    lines: list[str] = field(default_factory=list)
    log_path: str = ""

    @property
    def summary_line(self) -> str:
        """Pierwsza linia PASS opisujaca kluczowy efekt (do tabeli)."""
        for ln in self.lines:
            if ln.startswith("PASS "):
                return ln[5:]
        for ln in self.lines:
            if ln.startswith("INFO "):
                return ln[5:]
        return ""


def discover_scenarios(log_dir: Path) -> list[Scenario]:
    """Znajdz najnowszy log per scenariusz (po numerze NN) i sparsuj go."""
    latest: dict[str, Path] = {}
    for f in sorted(log_dir.glob("*.log")):
        m = LOG_RE.match(f.name)
        if not m:
            continue
        num = m.group("num")
        if num not in latest or f.name > latest[num].name:  # nazwa zawiera timestamp
            latest[num] = f
    scenarios: list[Scenario] = []
    for num in sorted(latest):
        scenarios.append(_parse_log(latest[num]))
    return scenarios


def _parse_log(path: Path) -> Scenario:
    raw = path.read_text(encoding="utf-8", errors="replace").splitlines()
    name = ""
    started = ""
    result = "UNKNOWN"
    body: list[str] = []
    for ln in raw:
        s = ln.rstrip()
        if s.startswith(" SCENARIO: "):
            name = s.removeprefix(" SCENARIO: ").strip()
        elif s.startswith(" STARTED:"):
            started = s.split(":", 1)[1].strip()
        elif "SCENARIO PASSED:" in s:
            result = "PASS"
        elif "SCENARIO FAILED:" in s:
            result = "FAIL"
        elif set(s) == {"="} or s.startswith(" ENDED:") or s.startswith(" LOG:"):
            continue
        else:
            if s:
                body.append(s)
    m = LOG_RE.match(path.name)
    num = m.group("num") if m else "??"
    short = (m.group("name") if m else name) or name
    return Scenario(num=num, name=short, started=started, result=result, lines=body, log_path=str(path))


def load_app_metrics(app_dir: Path) -> dict[str, Any]:
    """Wczytaj writer.json/reader.json + snapshoty klastra (jesli sa)."""
    out: dict[str, Any] = {}
    for key in ("writer", "reader"):
        p = app_dir / f"{key}.json"
        if p.is_file():
            try:
                out[key] = json.loads(p.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, OSError):
                pass
    for key in ("cluster-before", "cluster-after"):
        p = app_dir / f"{key}.json"
        if p.is_file():
            try:
                out[key] = json.loads(p.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, OSError):
                pass
    return out


def _leader_of(cluster: dict[str, Any] | None) -> str:
    if not cluster:
        return "?"
    for m in cluster.get("members", []):
        if m.get("role") == "leader":
            return str(m.get("name", "?"))
    return "?"


# ----------------------------------------------------------------------------
# Markdown
# ----------------------------------------------------------------------------

_MD_TXT = {
    "en": {
        "title_std": "# 🧪 PostgreSQL 18 HA Lab — Scenario Run Report",
        "title_agentic": "# 🤖 PostgreSQL 18 HA Lab — Agentic full-suite run (`scenario all`)",
        "goal": "> 🎯 Auto-generated report of the HA failure-scenario run: results table, "
                "full command/output transcript per scenario, and **app-perspective failover "
                "metrics** (downtime, reconnects) captured by `pgha-client`.",
        "method": "> 🤖 **Executed agentically** against the live cluster: an agent drove the full suite "
                  "(`scenarios/run-all.sh`, 01–13) over SSH (key auth) to `cli`, and performed the "
                  "host action for scenario 03 (`VBoxManage poweroff`/`startvm`) from the host. The "
                  "cluster was **not reset between scenarios** — it self-healed throughout.",
        "results": "## 📊 Results",
        "app": "## 🐍 App-driven failover (scenario 13)",
        "app_none": "_No `pgha-client` metrics found (run scenario 13 to generate them)._",
        "transcripts": "## 📜 Transcripts (command + output)",
        "cols": ("#", "Scenario", "Result", "Key observation"),
        "metric": ("Metric", "Value"),
        "generated": "Generated",
    },
    "pl": {
        "title_std": "# 🧪 PostgreSQL 18 HA Lab — Raport przebiegu scenariuszy",
        "title_agentic": "# 🤖 PostgreSQL 18 HA Lab — Agentowy przebieg pełnej suity (`scenario all`)",
        "goal": "> 🎯 Automatycznie wygenerowany raport przebiegu scenariuszy awarii HA: tabela "
                "wynikow, pelny transcript komend/outputow per scenariusz oraz **metryki "
                "failoveru z perspektywy aplikacji** (downtime, reconnecty) zebrane przez `pgha-client`.",
        "method": "> 🤖 **Wykonane agentowo** na żywym klastrze: agent przeprowadził pełną suitę "
                  "(`scenarios/run-all.sh`, 01–13) przez SSH (klucz) na `cli`, a akcję hosta dla "
                  "scenariusza 03 (`VBoxManage poweroff`/`startvm`) wykonał z hosta. Klaster **nie był "
                  "resetowany między scenariuszami** — samodzielnie się odbudowywał.",
        "results": "## 📊 Wyniki",
        "app": "## 🐍 Failover sterowany aplikacja (scenariusz 13)",
        "app_none": "_Brak metryk `pgha-client` (uruchom scenariusz 13, aby je wygenerowac)._",
        "transcripts": "## 📜 Transcripty (komenda + output)",
        "cols": ("#", "Scenariusz", "Wynik", "Kluczowa obserwacja"),
        "metric": ("Metryka", "Wartosc"),
        "generated": "Wygenerowano",
    },
}


def _badges(passed: int, total: int, date: str, *, page: str, agentic: bool) -> str:
    res = "success" if passed == total and total > 0 else ("critical" if total else "lightgrey")
    page_label = page.replace("-", "--")  # shields.io: literal '-' must be doubled
    badges = [
        f"[![Result](https://img.shields.io/badge/Scenarios-{passed}%2F{total}_PASS-{res})]()",
        f"[![Date](https://img.shields.io/badge/Date-{date.replace('-', '--')}-blue)]()",
        "[![Stack](https://img.shields.io/badge/Stack-Patroni%2Betcd%2BHAProxy-darkgreen)]()",
        "[![Client](https://img.shields.io/badge/Driver-pgha--client-blueviolet)]()",
        f"[![Page](https://img.shields.io/badge/Page-{page_label}-orange)]()",
    ]
    if agentic:
        badges.insert(2, "[![Run](https://img.shields.io/badge/Run-agentic-blueviolet)]()")
    return "\n".join(badges)


def render_md(
    scenarios: list[Scenario],
    app: dict[str, Any],
    lang: str,
    generated_at: str,
    *,
    agentic: bool = False,
    page_name: str = "run-report.html",
    other_md: str = "RUN_REPORT_PL.md",
) -> str:
    t = _MD_TXT[lang]
    total = len(scenarios)
    passed = sum(1 for s in scenarios if s.result == "PASS")
    date = generated_at.split(" ")[0]
    title = t["title_agentic"] if agentic else t["title_std"]
    other_label = "Polish" if lang == "en" else "Wersja EN"
    page = (f"> Interactive page (GitHub Pages): [`{page_name}`]({page_name}). {other_label}: "
            f"[{other_md}]({other_md})." if lang == "en"
            else f"> Strona interaktywna (GitHub Pages): [`{page_name}`]({page_name}). {other_label}: "
                 f"[{other_md}]({other_md}).")
    out: list[str] = [title, "", _badges(passed, total, date, page=page_name, agentic=agentic), "",
                      t["goal"], page]
    if agentic:
        out.append(t["method"])
    out += ["", t["results"], ""]

    c = t["cols"]
    out.append(f"| {c[0]} | {c[1]} | {c[2]} | {c[3]} |")
    out.append("|---|---|---|---|")
    for s in scenarios:
        mark = "✅ PASS" if s.result == "PASS" else ("❌ FAIL" if s.result == "FAIL" else "❔ ?")
        obs = s.summary_line.replace("|", "\\|")
        out.append(f"| {s.num} | `{s.name}` | {mark} | {obs} |")
    out.append("")

    # App-driven failover metrics
    out.append(t["app"])
    out.append("")
    w, r = app.get("writer"), app.get("reader")
    if w or r:
        before = _leader_of(app.get("cluster-before"))
        after = _leader_of(app.get("cluster-after"))
        out.append(f"**Leader:** `{before}` → `{after}`")
        out.append("")
        mh = t["metric"]
        out.append(f"| {mh[0]} | {mh[1]} |")
        out.append("|---|---|")
        if w:
            out.append(f"| writer inserts | {w.get('inserts', '?')} |")
            out.append(f"| outages | {w.get('outages', '?')} |")
            out.append(f"| reconnects | {w.get('reconnects', '?')} |")
            out.append(f"| **max downtime (s)** | **{w.get('downtime_max_sec', '?')}** |")
            out.append(f"| total downtime (s) | {w.get('downtime_total_sec', '?')} |")
            out.append(f"| writer actual Hz | {w.get('actual_hz', '?')} |")
        if r:
            out.append(f"| reader selects | {r.get('selects', '?')} |")
            out.append(f"| reader max_id | {r.get('max_id_start', '?')} → {r.get('max_id_end', '?')} |")
        out.append("")
    else:
        out.append(t["app_none"])
        out.append("")

    # Transcripts
    out.append(t["transcripts"])
    out.append("")
    for s in scenarios:
        mark = "✅" if s.result == "PASS" else ("❌" if s.result == "FAIL" else "❔")
        out.append(f"### {mark} {s.num} — `{s.name}`")
        out.append("")
        out.append("```text")
        out.extend(s.lines)
        out.append("```")
        out.append("")

    out.append(f"---\n\n_{t['generated']}: {generated_at}_")
    return "\n".join(out) + "\n"


# ----------------------------------------------------------------------------
# HTML (interactive, GitHub Pages)
# ----------------------------------------------------------------------------

# Per-language UI strings for the interactive HTML report. Polish text uses HTML
# numeric entities so this source file stays ASCII-safe.
_HTML_TXT = {
    "en": {
        "doctitle_std": "PostgreSQL 18 HA Lab &mdash; Scenario Run Report",
        "doctitle_agentic": "PostgreSQL 18 HA Lab &mdash; Agentic full-suite run",
        "h1_std": "&#129514; PostgreSQL 18 HA Lab &mdash; Scenario Run Report",
        "h1_agentic": "&#129302; PostgreSQL 18 HA Lab &mdash; Agentic full-suite run (scenario all)",
        "badge_agentic": "&#129302; agentic run",
        "goal_std": "<strong>What is this?</strong> Auto-generated report of the HA failure-scenario "
                    "run &mdash; results table, app-perspective failover metrics (<code>pgha-client</code>) "
                    "and collapsible transcripts (command + output) for each scenario.",
        "goal_agentic": "<strong>&#129302; Executed agentically.</strong> An agent drove the full suite "
                        "(<code>scenarios/run-all.sh</code>, 01&ndash;13) over SSH to <code>cli</code>, and "
                        "performed the host action for scenario 03 (<code>VBoxManage poweroff/startvm</code>) "
                        "from the host. The cluster was not reset between scenarios &mdash; it self-healed "
                        "throughout. Below: results table, app failover metrics and collapsible transcripts.",
        "h_results": "&#128202; Results",
        "cols": ("#", "Scenario", "Result", "Key observation"),
        "h_app": "&#128013; App-driven failover",
        "bar": "downtime window: {dmax:.1f}s of {dur:.0f}s ({outages} outage, {reconnects} reconnect)",
        "app_none": "<em>No pgha-client metrics (run scenario 13).</em>",
        "h_trans": "&#128220; Transcripts",
        "footer": "Generated",
    },
    "pl": {
        "doctitle_std": "PostgreSQL 18 HA Lab &mdash; Raport przebiegu scenariuszy",
        "doctitle_agentic": "PostgreSQL 18 HA Lab &mdash; Agentowy przebieg pe&#322;nej suity",
        "h1_std": "&#129514; PostgreSQL 18 HA Lab &mdash; Raport przebiegu scenariuszy",
        "h1_agentic": "&#129302; PostgreSQL 18 HA Lab &mdash; Agentowy przebieg pe&#322;nej suity (scenario all)",
        "badge_agentic": "&#129302; wykonane agentowo",
        "goal_std": "<strong>Co to jest?</strong> Automatyczny raport przebiegu scenariuszy awarii HA "
                    "&mdash; tabela wynik&oacute;w, metryki failoveru z perspektywy aplikacji "
                    "(<code>pgha-client</code>) oraz rozwijane transcripty (komenda + output) "
                    "ka&#380;dego scenariusza.",
        "goal_agentic": "<strong>&#129302; Wykonane agentowo.</strong> Agent przeprowadzi&#322; pe&#322;n&#261; "
                        "suit&#281; (<code>scenarios/run-all.sh</code>, 01&ndash;13) przez SSH na "
                        "<code>cli</code>, a akcj&#281; hosta dla scenariusza 03 "
                        "(<code>VBoxManage poweroff/startvm</code>) wykona&#322; z hosta. Klaster nie by&#322; "
                        "resetowany mi&#281;dzy scenariuszami &mdash; sam si&#281; odbudowywa&#322;. "
                        "Poni&#380;ej: tabela wynik&oacute;w, metryki failoveru aplikacji i rozwijane transcripty.",
        "h_results": "&#128202; Wyniki",
        "cols": ("#", "Scenariusz", "Wynik", "Kluczowa obserwacja"),
        "h_app": "&#128013; Failover sterowany aplikacj&#261;",
        "bar": "okno niedost&#281;pno&#347;ci: {dmax:.1f}s z {dur:.0f}s ({outages} outage, {reconnects} reconnect)",
        "app_none": "<em>Brak metryk pgha-client (uruchom scenariusz 13).</em>",
        "h_trans": "&#128220; Transcripty",
        "footer": "Wygenerowano",
    },
}

_HTML_HEAD = """<!DOCTYPE html>
<html lang="pl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PostgreSQL 18 HA Lab &mdash; Scenario Run Report</title>
<style>
  :root { --bg:#0d1117; --panel:#161b22; --fg:#c9d1d9; --muted:#8b949e; --grn:#3fb950;
          --red:#f85149; --ylw:#d29922; --blu:#58a6ff; --vio:#bc8cff; --bord:#30363d; }
  * { box-sizing:border-box; }
  body { margin:0; background:var(--bg); color:var(--fg);
         font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif; line-height:1.55; }
  .wrap { max-width:1080px; margin:0 auto; padding:32px 20px 80px; }
  h1 { font-size:2rem; margin:.2em 0; }
  h2 { border-bottom:1px solid var(--bord); padding-bottom:.3em; margin-top:2em; }
  .badges span { display:inline-block; margin:2px 4px 2px 0; }
  .badge { background:var(--panel); border:1px solid var(--bord); border-radius:6px;
           padding:3px 10px; font-size:.8rem; color:var(--muted); }
  .badge.ok { color:var(--grn); border-color:var(--grn); }
  .badge.bad { color:var(--red); border-color:var(--red); }
  .goal { background:var(--panel); border-left:4px solid var(--blu); padding:14px 18px;
          border-radius:6px; margin:18px 0; }
  table { width:100%; border-collapse:collapse; margin:14px 0; font-size:.92rem; }
  th,td { text-align:left; padding:8px 10px; border-bottom:1px solid var(--bord); vertical-align:top; }
  th { color:var(--muted); font-weight:600; }
  td.num { color:var(--vio); font-weight:700; white-space:nowrap; }
  td.scn { color:var(--blu); font-family:monospace; white-space:nowrap; }
  td.ok { color:var(--grn); white-space:nowrap; }
  td.bad { color:var(--red); white-space:nowrap; font-weight:700; }
  .metrics td.k { color:var(--muted); } .metrics td.v { color:var(--fg); font-weight:600; }
  .bar { background:#010409; border:1px solid var(--bord); border-radius:6px; height:26px;
         position:relative; margin:10px 0; overflow:hidden; }
  .bar .gap { background:linear-gradient(90deg,var(--red),var(--ylw)); height:100%; }
  .bar .lbl { position:absolute; top:0; left:8px; line-height:26px; font-size:.8rem; color:var(--fg); }
  details { background:var(--panel); border:1px solid var(--bord); border-radius:8px;
            margin:10px 0; padding:0 14px; }
  details[open] { padding-bottom:10px; }
  summary { cursor:pointer; padding:12px 0; font-weight:600; }
  summary .ok { color:var(--grn); } summary .bad { color:var(--red); }
  pre.term { background:#010409; border:1px solid var(--bord); border-radius:8px; padding:16px;
             overflow-x:auto; font-family:Consolas,Menlo,monospace; font-size:.82rem;
             line-height:1.45; white-space:pre; }
  pre.term span { display:block; }
  .pass { color:var(--grn); } .fail { color:var(--red); font-weight:700; }
  .info { color:var(--ylw); } .cmd { color:var(--blu); }
  footer { margin-top:50px; color:var(--muted); font-size:.85rem;
           border-top:1px solid var(--bord); padding-top:18px; }
  a { color:var(--blu); }
</style>
</head>
<body>
<div class="wrap">
"""


def _line_class(ln: str) -> str:
    if ln.startswith("PASS "):
        return "pass"
    if ln.startswith("FAIL "):
        return "fail"
    if ln.startswith("INFO "):
        return "info"
    return ""


def render_html(scenarios: list[Scenario], app: dict[str, Any], generated_at: str,
                *, agentic: bool = False, lang: str = "pl") -> str:
    t = _HTML_TXT[lang]
    total = len(scenarios)
    passed = sum(1 for s in scenarios if s.result == "PASS")
    failed = total - passed
    doctitle = t["doctitle_agentic"] if agentic else t["doctitle_std"]
    head = (_HTML_HEAD
            .replace('<html lang="pl">', f'<html lang="{lang}">')
            .replace("<title>PostgreSQL 18 HA Lab &mdash; Scenario Run Report</title>",
                     f"<title>{doctitle}</title>"))
    parts: list[str] = [head]
    h1 = t["h1_agentic"] if agentic else t["h1_std"]
    parts.append(f"  <h1>{h1}</h1>")
    ok_cls = "ok" if failed == 0 and total else "bad"
    parts.append('  <div class="badges">')
    parts.append(f'    <span class="badge {ok_cls}">&#10003; {passed}/{total} PASS</span>')
    parts.append(f'    <span class="badge">{html.escape(generated_at.split(" ")[0])}</span>')
    if agentic:
        parts.append(f'    <span class="badge">{t["badge_agentic"]}</span>')
    parts.append('    <span class="badge">Patroni + etcd + HAProxy + PgBouncer</span>')
    parts.append('    <span class="badge">driver: pgha-client</span>')
    parts.append("  </div>")
    goal = t["goal_agentic"] if agentic else t["goal_std"]
    parts.append(f'  <div class="goal">{goal}</div>')

    # Results table
    parts.append(f'  <h2>{t["h_results"]}</h2>')
    c = t["cols"]
    parts.append(f"  <table><thead><tr><th>{c[0]}</th><th>{c[1]}</th><th>{c[2]}</th>"
                 f"<th>{c[3]}</th></tr></thead><tbody>")
    for s in scenarios:
        if s.result == "PASS":
            cell = '<td class="ok">&#10003; PASS</td>'
        elif s.result == "FAIL":
            cell = '<td class="bad">&#10007; FAIL</td>'
        else:
            cell = "<td>?</td>"
        parts.append(f'    <tr><td class="num">{s.num}</td><td class="scn">{html.escape(s.name)}</td>'
                     f"{cell}<td>{html.escape(s.summary_line)}</td></tr>")
    parts.append("  </tbody></table>")

    # App metrics + downtime bar
    parts.append(f'  <h2>{t["h_app"]}</h2>')
    w, r = app.get("writer"), app.get("reader")
    if w or r:
        before = _leader_of(app.get("cluster-before"))
        after = _leader_of(app.get("cluster-after"))
        parts.append(f"  <p>Leader: <code>{html.escape(before)}</code> &rarr; "
                     f"<code>{html.escape(after)}</code></p>")
        if w:
            dur = float(w.get("duration_sec") or w.get("elapsed_sec") or 0) or 1.0
            dmax = float(w.get("downtime_max_sec") or 0)
            pct = max(2.0, min(100.0, dmax / dur * 100.0)) if dmax else 0.0
            lbl = t["bar"].format(dmax=dmax, dur=dur,
                                  outages=w.get("outages", 0), reconnects=w.get("reconnects", 0))
            parts.append('  <div class="bar">'
                         f'<div class="gap" style="width:{pct:.1f}%"></div>'
                         f'<span class="lbl">{lbl}</span></div>')
        parts.append('  <table class="metrics"><tbody>')

        def row(k: str, v: Any) -> str:
            return f'    <tr><td class="k">{k}</td><td class="v">{html.escape(str(v))}</td></tr>'

        if w:
            parts.append(row("writer inserts", w.get("inserts", "?")))
            parts.append(row("outages", w.get("outages", "?")))
            parts.append(row("reconnects", w.get("reconnects", "?")))
            parts.append(row("max downtime (s)", w.get("downtime_max_sec", "?")))
            parts.append(row("total downtime (s)", w.get("downtime_total_sec", "?")))
            parts.append(row("writer actual Hz", w.get("actual_hz", "?")))
        if r:
            parts.append(row("reader selects", r.get("selects", "?")))
            parts.append(row("reader max_id", f"{r.get('max_id_start', '?')} -> {r.get('max_id_end', '?')}"))
        parts.append("  </tbody></table>")
    else:
        parts.append(f'  <p>{t["app_none"]}</p>')

    # Collapsible transcripts
    parts.append(f'  <h2>{t["h_trans"]}</h2>')
    for s in scenarios:
        badge = ('<span class="ok">&#10003; PASS</span>' if s.result == "PASS"
                 else '<span class="bad">&#10007; FAIL</span>' if s.result == "FAIL"
                 else "?")
        is_open = " open" if s.result == "FAIL" else ""
        parts.append(f"  <details{is_open}><summary>{s.num} &mdash; "
                     f"<code>{html.escape(s.name)}</code> &nbsp; {badge}</summary>")
        parts.append('    <pre class="term">')
        for ln in s.lines:
            cls = _line_class(ln)
            span = f'<span class="{cls}">{html.escape(ln)}</span>' if cls else f"<span>{html.escape(ln)}</span>"
            parts.append(span)
        parts.append("    </pre>")
        parts.append("  </details>")

    parts.append(f'  <footer>{t["footer"]}: {html.escape(generated_at)} '
                 "&mdash; <code>report/gen_report.py</code></footer>")
    parts.append("</div>\n</body>\n</html>")
    return "\n".join(parts) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description="Generate HA scenario run report (MD + HTML).")
    ap.add_argument("--log-dir", default="/var/log/postgres18-ha-lab/scenarios",
                    help="Directory with scenario *.log files.")
    ap.add_argument("--app-dir", default=None,
                    help="Directory with pgha-client *.json (default: <log-dir>/app).")
    ap.add_argument("--out-dir", default="docs", help="Output directory for the report files.")
    ap.add_argument("--generated-at", default=None,
                    help="Override the report timestamp (default: now).")
    ap.add_argument("--agentic", action="store_true",
                    help="Brand the report as an agentic full-suite run "
                         "(AGENTIC_RUN_ALL.md / _PL.md / agentic-run-all.html).")
    args = ap.parse_args()

    log_dir = Path(args.log_dir)
    app_dir = Path(args.app_dir) if args.app_dir else log_dir / "app"
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    generated_at = args.generated_at or datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    scenarios = discover_scenarios(log_dir) if log_dir.is_dir() else []
    app = load_app_metrics(app_dir) if app_dir.is_dir() else {}

    md_en, md_pl, page_en, page_pl = (
        ("AGENTIC_RUN_ALL.md", "AGENTIC_RUN_ALL_PL.md", "agentic-run-all.html", "agentic-run-all_PL.html")
        if args.agentic else
        ("RUN_REPORT.md", "RUN_REPORT_PL.md", "run-report.html", "run-report_PL.html")
    )
    # Each language points at its own interactive HTML page (EN -> *.html, PL -> *_PL.html).
    (out_dir / md_en).write_text(
        render_md(scenarios, app, "en", generated_at, agentic=args.agentic,
                  page_name=page_en, other_md=md_pl), encoding="utf-8")
    (out_dir / md_pl).write_text(
        render_md(scenarios, app, "pl", generated_at, agentic=args.agentic,
                  page_name=page_pl, other_md=md_en), encoding="utf-8")
    (out_dir / page_en).write_text(
        render_html(scenarios, app, generated_at, agentic=args.agentic, lang="en"), encoding="utf-8")
    (out_dir / page_pl).write_text(
        render_html(scenarios, app, generated_at, agentic=args.agentic, lang="pl"), encoding="utf-8")

    print(f"Wrote report for {len(scenarios)} scenarios to {out_dir}/ "
          f"({md_en}, {md_pl}, {page_en}, {page_pl})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
