"""CLI dispatcher for pgha-client."""

from __future__ import annotations

import sys

import click

from . import monitor as monitor_mod
from . import reader as reader_mod
from . import writer as writer_mod

_REPORT = click.option(
    "--report", "report", type=click.Path(dir_okay=False), default=None,
    help="Write a JSON run summary (HA metrics) to this file.",
)


@click.group()
def cli() -> None:
    """pgha-client — writer/reader/monitor for the PG18 HA lab."""


@cli.command()
@click.option("--rate", type=float, default=10.0, help="Inserts per second.")
@click.option("--target", type=click.Choice(["haproxy", "direct"]), default="haproxy")
@click.option("--duration", type=float, default=None, help="Stop after N seconds (default: forever).")
@_REPORT
def writer(rate: float, target: str, duration: float | None, report: str | None) -> None:
    writer_mod.run(rate_hz=rate, target=target, duration_sec=duration, report_path=report)


@cli.command()
@click.option("--rate", type=float, default=10.0)
@click.option("--target", type=click.Choice(["haproxy", "direct"]), default="haproxy")
@click.option("--duration", type=float, default=None)
@_REPORT
def reader(rate: float, target: str, duration: float | None, report: str | None) -> None:
    reader_mod.run(rate_hz=rate, target=target, duration_sec=duration, report_path=report)


@cli.command()
@click.option("--refresh", type=float, default=1.0)
@click.option("--snapshot", is_flag=True, default=False, help="Print one cluster-state JSON and exit.")
def monitor(refresh: float, snapshot: bool) -> None:
    if snapshot:
        sys.exit(monitor_mod.snapshot())
    monitor_mod.run(refresh_sec=refresh)


if __name__ == "__main__":
    cli()
