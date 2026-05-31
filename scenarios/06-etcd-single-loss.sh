#!/usr/bin/env bash
# ==============================================================================
# Tytul:        06-etcd-single-loss.sh
# Opis:         Stop etcd na jednym wezle; kworum (2/3) trzyma, klaster dziala.
#               etcd restartowany na koncu.
# Description [EN]: Stop etcd on a single node; quorum (2/3) holds, cluster keeps
#               working. etcd is restarted at the end.
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
# Uzycie [PL]:       z hosta: lab.ps1 scenario 06  |  na cli: bash scenarios/06-etcd-single-loss.sh
# Usage [EN]:        from host: lab.ps1 scenario 06 | on cli: bash scenarios/06-etcd-single-loss.sh
# ==============================================================================
set -euo pipefail
SCENARIO_DIR=$(dirname "$(readlink -f "$0")")
source "$SCENARIO_DIR/lib/assertions.sh"
scenario_start "06-etcd-single-loss"
rc=0
target=pg3.lab.test
ssh -o StrictHostKeyChecking=accept-new "root@$target" "systemctl stop etcd"
sleep 5
assert_leader_exists || rc=$?
assert_can_write || rc=$?
ssh -o StrictHostKeyChecking=accept-new "root@$target" "systemctl start etcd"
scenario_end "$rc"
