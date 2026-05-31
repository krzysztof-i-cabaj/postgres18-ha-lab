"""Tests for run-metrics tracking and JSON report serialization (no DB needed)."""

from __future__ import annotations

import json
from pathlib import Path

from pgha_client.metrics import OutageTracker, build_summary, write_report


def test_outage_tracker_single_window() -> None:
    """Wiele bledow z rzedu = jedno okno niedostepnosci; downtime = od 1. bledu do sukcesu."""
    t = OutageTracker()
    t.on_success(0.0)  # zdrowy zapis
    t.on_error(10.0)   # start okna
    t.on_error(12.0)   # ten sam outage (reconnect)
    t.on_error(14.0)
    t.on_success(15.0)  # recovery -> downtime = 5.0s
    assert t.outages == 1
    assert t.reconnects == 3
    assert t.downtime_total_sec == 5.0
    assert t.downtime_max_sec == 5.0


def test_outage_tracker_two_windows() -> None:
    t = OutageTracker()
    t.on_error(1.0)
    t.on_success(3.0)   # okno 1 = 2.0s
    t.on_error(10.0)
    t.on_success(14.0)  # okno 2 = 4.0s
    assert t.outages == 2
    assert t.downtime_total_sec == 6.0
    assert t.downtime_max_sec == 4.0


def test_build_summary_writer() -> None:
    t = OutageTracker()
    t.on_error(1.0)
    t.on_success(2.5)
    s = build_summary(
        role="writer", target="haproxy", rate_hz=10.0, duration_sec=60.0,
        elapsed_sec=60.0, count_label="inserts", count=540, tracker=t,
    )
    assert s["role"] == "writer"
    assert s["inserts"] == 540
    assert s["outages"] == 1
    assert s["actual_hz"] == 9.0
    assert s["downtime_total_sec"] == 1.5


def test_build_summary_reader_extra() -> None:
    s = build_summary(
        role="reader", target="direct", rate_hz=10.0, duration_sec=None,
        elapsed_sec=0.0, count_label="selects", count=0, tracker=OutageTracker(),
        extra={"max_id_start": 100, "max_id_end": 640},
    )
    assert s["selects"] == 0
    assert s["actual_hz"] == 0.0   # brak dzielenia przez zero
    assert s["max_id_end"] == 640


def test_write_report_roundtrip(tmp_path: Path) -> None:
    target = tmp_path / "sub" / "writer.json"  # katalog nadrzedny tworzony automatycznie
    summary = build_summary(
        role="writer", target="haproxy", rate_hz=5.0, duration_sec=10.0,
        elapsed_sec=10.0, count_label="inserts", count=50, tracker=OutageTracker(),
    )
    write_report(str(target), summary)
    assert json.loads(target.read_text(encoding="utf-8")) == summary


def test_write_report_noop_when_path_none(tmp_path: Path) -> None:
    write_report(None, {"x": 1})  # nie rzuca, nic nie zapisuje
    assert not list(tmp_path.iterdir())
