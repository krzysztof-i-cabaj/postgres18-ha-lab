#!/usr/bin/env bash
# ==============================================================================
# Tytul:        01-baseline.sh
# Opis:         Sanity klastra: lider, kworum etcd, 3 czlonkow, read+write przez HAProxy.
# Description [EN]: Cluster sanity: leader, etcd quorum, 3 members, read+write via HAProxy.
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - uruchamiac na VM cli; dzialajacy klaster PG/Patroni/etcd/HAProxy
#                    - scenarios/lib/assertions.sh; ssh root@ do wezlow pg*
# Requirements [EN]: - run on the cli VM; a running PG/Patroni/etcd/HAProxy cluster
#                    - scenarios/lib/assertions.sh; ssh root@ to pg* nodes
#
# Uzycie [PL]:       z hosta: lab.ps1 scenario 01  |  na cli: bash scenarios/01-baseline.sh
# Usage [EN]:        from host: lab.ps1 scenario 01 | on cli: bash scenarios/01-baseline.sh
# ==============================================================================
set -euo pipefail
SCENARIO_DIR=$(dirname "$(readlink -f "$0")")
source "$SCENARIO_DIR/lib/assertions.sh"
scenario_start "01-baseline"
rc=0
assert_leader_exists || rc=$?
assert_etcd_quorum   || rc=$?
assert_member_count 3 || rc=$?
assert_can_write || rc=$?
assert_can_read  || rc=$?
scenario_end "$rc"
