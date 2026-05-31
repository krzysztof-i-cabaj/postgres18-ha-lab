"""Reader — SELECT at a constant rate, reports max id seen, reconnects on failure."""

from __future__ import annotations

import time
from collections.abc import Iterator
from contextlib import contextmanager

import psycopg
from rich.console import Console

from .connstr import build_target
from .metrics import OutageTracker, build_summary, write_report

console = Console()


@contextmanager
def _connect(conninfo: str) -> Iterator[psycopg.Connection]:
    conn = None
    try:
        conn = psycopg.connect(conninfo, autocommit=True, connect_timeout=5)
        yield conn
    finally:
        if conn is not None:
            conn.close()


def run(
    rate_hz: float = 10.0,
    target: str = "haproxy",
    duration_sec: float | None = None,
    report_path: str | None = None,
) -> int:
    """Run reader; returns number of successful SELECTs.

    Sledzi ``max_id`` (od pierwszego do ostatniego odczytu) — wzrost dowodzi, ze
    zapisy postepowaly i replikowaly sie mimo failoveru. Gdy ``report_path``
    ustawione, na koniec zapisuje JSON z metrykami.
    """
    tgt = build_target(target)
    interval = 1.0 / rate_hz
    selects = 0
    tracker = OutageTracker()
    max_id = 0
    max_id_start: int | None = None
    start = time.time()
    next_tick = start

    console.log(f"[bold cyan]reader[/] target={tgt.name} rate={rate_hz} Hz")

    while True:
        if duration_sec is not None and (time.time() - start) >= duration_sec:
            break
        try:
            with _connect(tgt.conninfo) as conn, conn.cursor() as cur:
                while True:
                    if duration_sec is not None and (time.time() - start) >= duration_sec:
                        break
                    cur.execute("SELECT COALESCE(MAX(id), 0) FROM pgha_writer_log")
                    row = cur.fetchone()
                    cur_max = int(row[0]) if row else 0
                    if max_id_start is None:
                        max_id_start = cur_max
                    if cur_max > max_id:
                        max_id = cur_max
                    selects += 1
                    tracker.on_success(time.time())
                    if selects % 50 == 0:
                        elapsed = time.time() - start
                        console.log(
                            f"  {selects} selects in {elapsed:.1f}s "
                            f"max_id={max_id} ({tracker.reconnects} reconnects, "
                            f"{tracker.downtime_total_sec:.1f}s downtime)"
                        )
                    next_tick += interval
                    sleep_for = next_tick - time.time()
                    if sleep_for > 0:
                        time.sleep(sleep_for)
                    else:
                        next_tick = time.time()
        except (psycopg.OperationalError, psycopg.InterfaceError) as exc:
            tracker.on_error(time.time())
            console.log(f"[yellow]reader reconnect after error:[/] {exc}")
            time.sleep(2.0)
            next_tick = time.time()
            continue

    summary = build_summary(
        role="reader",
        target=tgt.name,
        rate_hz=rate_hz,
        duration_sec=duration_sec,
        elapsed_sec=time.time() - start,
        count_label="selects",
        count=selects,
        tracker=tracker,
        extra={"max_id_start": max_id_start or 0, "max_id_end": max_id},
    )
    write_report(report_path, summary)
    console.log(
        f"[bold green]reader done[/] selects={selects} max_id={max_id} "
        f"outages={tracker.outages} reconnects={tracker.reconnects} "
        f"downtime={tracker.downtime_total_sec:.1f}s"
    )
    return selects
