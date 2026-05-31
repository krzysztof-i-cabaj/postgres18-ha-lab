#!/usr/bin/env bash
# ==============================================================================
# Tytul:        07-etcd-quorum-loss.sh
# Opis:         Stop etcd na 2 wezlach -> utrata kworum; Patroni wchodzi w
#               DCS-failsafe (read-only). etcd restartowany, kworum przywracane.
# Description [EN]: Stop etcd on 2 nodes -> quorum loss; Patroni enters DCS
#               failsafe (read-only). etcd restarted, quorum restored.
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
# Uzycie [PL]:       z hosta: lab.ps1 scenario 07  |  na cli: bash scenarios/07-etcd-quorum-loss.sh
# Usage [EN]:        from host: lab.ps1 scenario 07 | on cli: bash scenarios/07-etcd-quorum-loss.sh
# ==============================================================================
set -euo pipefail
SCENARIO_DIR=$(dirname "$(readlink -f "$0")")
source "$SCENARIO_DIR/lib/assertions.sh"
scenario_start "07-etcd-quorum-loss"
rc=0

ssh -o StrictHostKeyChecking=accept-new "root@pg2.lab.test" "systemctl stop etcd"
ssh -o StrictHostKeyChecking=accept-new "root@pg3.lab.test" "systemctl stop etcd"
sleep 10

# Reads should still work; writes may or may not (depends on Patroni failsafe)
assert_can_read || rc=$?

# Restore quorum
ssh -o StrictHostKeyChecking=accept-new "root@pg2.lab.test" "systemctl start etcd"
ssh -o StrictHostKeyChecking=accept-new "root@pg3.lab.test" "systemctl start etcd"
wait_etcd_quorum 30 || true
assert_etcd_quorum || rc=$?

scenario_end "$rc"
