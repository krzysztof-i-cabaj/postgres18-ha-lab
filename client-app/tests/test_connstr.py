"""Tests for connstr builders."""

from __future__ import annotations

import pytest

from pgha_client.connstr import build_target


def test_haproxy_target() -> None:
    t = build_target("haproxy", dbname="labdb", user="lab", password="lab")
    assert t.name == "haproxy"
    assert "host=db.lab.test" in t.conninfo
    assert "port=5000" in t.conninfo


def test_direct_target_has_target_session_attrs() -> None:
    t = build_target("direct", dbname="labdb", user="lab", password="lab")
    assert t.name == "direct"
    assert "target_session_attrs=read-write" in t.conninfo
    assert "host=pg1.lab.test,pg2.lab.test,pg3.lab.test" in t.conninfo


def test_unknown_target() -> None:
    with pytest.raises(ValueError, match="unknown target"):
        build_target("nosuch")
