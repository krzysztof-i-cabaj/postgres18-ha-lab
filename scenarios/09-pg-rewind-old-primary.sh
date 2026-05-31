#!/usr/bin/env bash
# ==============================================================================
# Tytul:        09-pg-rewind-old-primary.sh
# Opis:         Po zabiciu lidera i failoverze restart starego primary; Patroni
#               uruchamia pg_rewind i wezel dolacza jako replika/sync_standby.
# Description [EN]: After killing the leader and failover, restart the old primary;
#               Patroni runs pg_rewind and the node rejoins as replica/sync_standby.
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - uruchamiac na VM cli; dzialajacy klaster PG/Patroni/etcd/HAProxy
#                    - scenarios/lib/assertions.sh; ssh root@ do wezlow pg*
#                    - DESTRUKCYJNY: zabija proces postgres na liderze
# Requirements [EN]: - run on the cli VM; a running PG/Patroni/etcd/HAProxy cluster
#                    - scenarios/lib/assertions.sh; ssh root@ to pg* nodes
#                    - DESTRUCTIVE: kills the postgres process on the leader
#
# Uzycie [PL]:       z hosta: lab.ps1 scenario 09  |  na cli: bash scenarios/09-pg-rewind-old-primary.sh
# Usage [EN]:        from host: lab.ps1 scenario 09 | on cli: bash scenarios/09-pg-rewind-old-primary.sh
# ==============================================================================
set -euo pipefail
SCENARIO_DIR=$(dirname "$(readlink -f "$0")")
source "$SCENARIO_DIR/lib/assertions.sh"
scenario_start "09-pg-rewind-old-primary"
rc=0
prev_leader=$(patroni_leader)
# Wymus failover: pkill postgresa + stop Patroni (samo pkill nie wystarcza -- Patroni
# zrestartowalby postgres lokalnie przed wygasnieciem lease). / Force failover: kill
# postgres + stop Patroni (pkill alone is not enough -- Patroni would restart postgres
# locally before the lease expires).
ssh -o StrictHostKeyChecking=accept-new "root@${prev_leader}.lab.test" "pkill -9 postgres; systemctl stop patroni" || true
wait_leader_change "$prev_leader" 60 || true
ssh -o StrictHostKeyChecking=accept-new "root@${prev_leader}.lab.test" "systemctl restart patroni"
# Stary primary ma dolaczyc jako replika -- pg_rewind uzgadnia rozbiezna os czasu.
wait_member_role "$prev_leader" 60 replica sync_standby || true
role=$(patroni_member_role "$prev_leader")
if [[ "$role" == "replica" || "$role" == "sync_standby" ]]; then
    assert_msg_pass "old primary $prev_leader rejoined as $role (pg_rewind likely succeeded)"
else
    assert_msg_fail "old primary unexpected role: $role"
    rc=1
fi
scenario_end "$rc"
