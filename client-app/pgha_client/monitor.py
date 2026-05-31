"""Monitor — live cluster TUI via Patroni REST API + rich.live."""

from __future__ import annotations

import json
import time
import urllib.request
from typing import Any

from rich.console import Console
from rich.live import Live
from rich.table import Table

PATRONI_NODES = ("pg1.lab.test", "pg2.lab.test", "pg3.lab.test")
console = Console()


def _fetch_cluster() -> dict[str, Any] | None:
    """Try each Patroni REST endpoint until one responds with /cluster JSON."""
    for host in PATRONI_NODES:
        url = f"http://{host}:8008/cluster"
        try:
            with urllib.request.urlopen(url, timeout=2) as resp:
                if resp.status == 200:
                    return json.loads(resp.read().decode("utf-8"))
        except Exception:
            continue
    return None


def _render(cluster: dict[str, Any] | None) -> Table:
    table = Table(title="postgres18-ha-lab — Patroni cluster", expand=True)
    table.add_column("Member")
    table.add_column("Role")
    table.add_column("State")
    table.add_column("TL", justify="right")
    table.add_column("Lag MB", justify="right")

    if cluster is None:
        table.add_row("[red]no Patroni REST reachable[/]", "-", "-", "-", "-")
        return table

    for m in cluster.get("members", []):
        role = m.get("role", "?")
        state = m.get("state", "?")
        tl = str(m.get("timeline", "-"))
        lag = m.get("lag", "-")
        lag_str = "0" if role == "leader" else str(lag)
        style = "bold green" if role == "leader" else ""
        table.add_row(m.get("name", "?"), f"[{style}]{role}[/]", state, tl, lag_str)
    return table


def snapshot() -> int:
    """Jednorazowy fetch stanu klastra -> JSON na stdout (dla raportu BEFORE/AFTER).

    Zwraca 0 gdy Patroni REST odpowiedzial, 1 gdy zaden wezel nie byl osiagalny.
    """
    cluster = _fetch_cluster()
    print(json.dumps(cluster, indent=2, sort_keys=True))
    return 0 if cluster is not None else 1


def run(refresh_sec: float = 1.0) -> None:
    console.log("[bold cyan]monitor[/] polling Patroni REST every", refresh_sec, "s. Ctrl-C to exit.")
    with Live(_render(None), refresh_per_second=2, console=console) as live:
        while True:
            try:
                cluster = _fetch_cluster()
                live.update(_render(cluster))
                time.sleep(refresh_sec)
            except KeyboardInterrupt:
                break
