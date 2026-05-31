"""Run metrics — availability-gap tracking + JSON report (shared by writer/reader).

Sledzi okna niedostepnosci (downtime) podczas failoveru i serializuje podsumowanie
do JSON, ktore konsumuje generator raportu (report/gen_report.py).
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class OutageTracker:
    """Tracks availability gaps across reconnects during a failover.

    Wolaj ``on_error(now)`` przy kazdym zlapanym bledzie polaczenia oraz
    ``on_success(now)`` przy kazdej udanej operacji. Pojedyncze okno
    niedostepnosci moze obejmowac wiele prob reconnectu (liczone jako jeden outage).
    """

    outages: int = 0
    reconnects: int = 0
    downtime_total_sec: float = 0.0
    downtime_max_sec: float = 0.0
    _in_outage: bool = field(default=False, repr=False)
    _outage_start: float = field(default=0.0, repr=False)

    def on_error(self, now: float) -> None:
        """Zarejestruj blad polaczenia (start nowego okna, jesli nie trwa)."""
        self.reconnects += 1
        if not self._in_outage:
            self._in_outage = True
            self._outage_start = now
            self.outages += 1

    def on_success(self, now: float) -> None:
        """Zarejestruj sukces (domkniecie okna niedostepnosci, jesli trwalo)."""
        if self._in_outage:
            gap = max(0.0, now - self._outage_start)
            self.downtime_total_sec += gap
            self.downtime_max_sec = max(self.downtime_max_sec, gap)
            self._in_outage = False


def build_summary(
    *,
    role: str,
    target: str,
    rate_hz: float,
    duration_sec: float | None,
    elapsed_sec: float,
    count_label: str,
    count: int,
    tracker: OutageTracker,
    extra: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Zbuduj slownik podsumowania przebiegu (czysta funkcja, bez I/O ani czasu)."""
    actual_hz = round(count / elapsed_sec, 2) if elapsed_sec > 0 else 0.0
    summary: dict[str, Any] = {
        "role": role,
        "target": target,
        "rate_hz": rate_hz,
        "duration_sec": duration_sec,
        "elapsed_sec": round(elapsed_sec, 2),
        count_label: count,
        "actual_hz": actual_hz,
        "outages": tracker.outages,
        "reconnects": tracker.reconnects,
        "downtime_total_sec": round(tracker.downtime_total_sec, 2),
        "downtime_max_sec": round(tracker.downtime_max_sec, 2),
    }
    if extra:
        summary.update(extra)
    return summary


def write_report(report_path: str | None, summary: dict[str, Any]) -> None:
    """Zapisz podsumowanie do pliku JSON (tworzy katalog nadrzedny). No-op gdy brak sciezki."""
    if not report_path:
        return
    path = Path(report_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(summary, indent=2, sort_keys=True), encoding="utf-8")
