"""Connection string builders for haproxy / direct libpq targets."""

from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class ConnTarget:
    """A resolved connection target."""

    name: str
    conninfo: str


def build_target(target: str, dbname: str = "labdb", user: str = "lab", password: str = "lab") -> ConnTarget:
    """Build a libpq conninfo string for the given target.

    target = "haproxy" -> single host db.lab.test:5000 (HAProxy primary)
    target = "direct"  -> multi-host string with target_session_attrs=read-write
    """
    pwd = os.environ.get("PGPASSWORD", password)
    if target == "haproxy":
        return ConnTarget(
            name="haproxy",
            conninfo=f"host=db.lab.test port=5000 dbname={dbname} user={user} password={pwd}",
        )
    if target == "direct":
        hosts = "pg1.lab.test,pg2.lab.test,pg3.lab.test"
        return ConnTarget(
            name="direct",
            conninfo=(
                f"host={hosts} port=5432 dbname={dbname} user={user} password={pwd} "
                "target_session_attrs=read-write"
            ),
        )
    raise ValueError(f"unknown target: {target!r} (use 'haproxy' or 'direct')")
