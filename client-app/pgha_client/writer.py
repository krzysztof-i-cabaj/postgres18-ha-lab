"""Writer — INSERTs at a constant rate, reports throughput, reconnects on failover."""

from __future__ import annotations

import time
from collections.abc import Iterator
from contextlib import contextmanager

import psycopg
from rich.console import Console

from .connstr import build_target
from .metrics import OutageTracker, build_summary, write_report

console = Console()
SCHEMA_DDL = """
CREATE TABLE IF NOT EXISTS pgha_writer_log (
    id BIGSERIAL PRIMARY KEY,
    ts TIMESTAMPTZ NOT NULL DEFAULT now(),
    payload TEXT NOT NULL,
    host TEXT NOT NULL DEFAULT inet_server_addr()::text
);
"""


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
    """Run writer; returns number of successful inserts.

    Gdy ``report_path`` ustawione, na koniec zapisuje JSON z metrykami HA
    (inserts, outages, reconnects, okno niedostepnosci) do generatora raportu.
    """
    tgt = build_target(target)
    interval = 1.0 / rate_hz
    inserts = 0
    tracker = OutageTracker()
    start = time.time()
    next_tick = start

    console.log(f"[bold cyan]writer[/] target={tgt.name} rate={rate_hz} Hz")

    while True:
        if duration_sec is not None and (time.time() - start) >= duration_sec:
            break
        try:
            with _connect(tgt.conninfo) as conn, conn.cursor() as cur:
                # Best-effort bootstrap (wygoda przy uruchomieniu standalone). W labie
                # tabela juz istnieje (tworzy ja orchestrate.sh, owner=lab), a user `lab`
                # nie ma CREATE na schemacie public (PG15+) -> ignorujemy brak uprawnien.
                # autocommit=True: nieudane CREATE nie psuje kolejnych zapytan.
                # Best-effort bootstrap; in the lab the table already exists and `lab`
                # lacks CREATE on schema public (PG15+) -> ignore the privilege error.
                try:
                    cur.execute(SCHEMA_DDL)
                except psycopg.errors.InsufficientPrivilege:
                    pass
                while True:
                    if duration_sec is not None and (time.time() - start) >= duration_sec:
                        break
                    payload = f"hb-{inserts}"
                    cur.execute("INSERT INTO pgha_writer_log (payload) VALUES (%s)", (payload,))
                    inserts += 1
                    tracker.on_success(time.time())
                    if inserts % 50 == 0:
                        elapsed = time.time() - start
                        console.log(
                            f"  {inserts} inserts in {elapsed:.1f}s "
                            f"({inserts / elapsed:.1f} actual Hz, {tracker.reconnects} reconnects, "
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
            console.log(f"[yellow]writer reconnect after error:[/] {exc}")
            time.sleep(2.0)
            next_tick = time.time()
            continue

    summary = build_summary(
        role="writer",
        target=tgt.name,
        rate_hz=rate_hz,
        duration_sec=duration_sec,
        elapsed_sec=time.time() - start,
        count_label="inserts",
        count=inserts,
        tracker=tracker,
    )
    write_report(report_path, summary)
    console.log(
        f"[bold green]writer done[/] inserts={inserts} outages={tracker.outages} "
        f"reconnects={tracker.reconnects} downtime={tracker.downtime_total_sec:.1f}s"
    )
    return inserts
