#!/usr/bin/env bash
# ==============================================================================
# Tytul:        12-cascading-failure.sh
# Opis:         Kaskada awarii: zabij lidera, potem zabij nowego lidera; klaster
#               wybiera trzeciego, a po restarcie wraca do 3 czlonkow.
# Description [EN]: Cascading failure: kill the leader, then kill the new leader;
#               the cluster elects a third, then converges back to 3 members.
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - uruchamiac na VM cli; dzialajacy klaster PG/Patroni/etcd/HAProxy
#                    - scenarios/lib/assertions.sh; ssh root@ do wezlow pg*
#                    - DESTRUKCYJNY: zabija postgres na dwoch kolejnych liderach
# Requirements [EN]: - run on the cli VM; a running PG/Patroni/etcd/HAProxy cluster
#                    - scenarios/lib/assertions.sh; ssh root@ to pg* nodes
#                    - DESTRUCTIVE: kills postgres on two successive leaders
#
# Uzycie [PL]:       z hosta: lab.ps1 scenario 12  |  na cli: bash scenarios/12-cascading-failure.sh
# Usage [EN]:        from host: lab.ps1 scenario 12 | on cli: bash scenarios/12-cascading-failure.sh
# ==============================================================================
set -euo pipefail
SCENARIO_DIR=$(dirname "$(readlink -f "$0")")
source "$SCENARIO_DIR/lib/assertions.sh"
scenario_start "12-cascading-failure"
rc=0

# get_leader (nie goly patroni_leader): ponawia az lider niepusty -- przejsciowy
# pusty odczyt z DCS dawal `ssh root@.lab.test` i falszywy brak failoveru.
# get_leader (not bare patroni_leader): retries until non-empty -- a transient empty
# DCS read produced `ssh root@.lab.test` and a spurious "no failover".
p1=$(get_leader 15) || { assert_msg_fail "no leader visible at start"; scenario_end 1; exit 1; }
# pkill + stop Patroni = deterministyczny failover (samo pkill -> lokalny restart, brak
# zmiany lidera). / pkill + stop Patroni = deterministic failover (pkill alone -> local
# restart, no leader change).
ssh -o StrictHostKeyChecking=accept-new "root@${p1}.lab.test" "pkill -9 postgres; systemctl stop patroni" || true
if wait_leader_change "$p1" 60; then
    assert_leader_changed "$p1" || rc=$?
else
    assert_msg_fail "no first failover within 60s"; rc=1
fi
# Zanim zadamy DRUGA awarie, nowy lider musi ustanowic nowy sync_standby -- inaczej
# po jego smierci zaden wezel nie bedzie uprawniony do promocji (synchronous_mode)
# i drugi failover nie nastapi. Czekamy az zapis wroci (= sync_standby gotowy).
# Before the SECOND failure, the new leader must establish a fresh sync_standby --
# otherwise no node is promotion-eligible after it dies (synchronous_mode) and the
# second failover never happens. Wait for writes to resume (= sync_standby ready).
wait_writable 40 || true
sleep 8
p2=$(get_leader 15) || { assert_msg_fail "no leader visible before second kill"; rc=1; }

[[ -n "${p2:-}" ]] && ssh -o StrictHostKeyChecking=accept-new "root@${p2}.lab.test" "pkill -9 postgres; systemctl stop patroni" || true
if wait_leader_change "$p2" 60; then
    assert_leader_changed "$p2" || rc=$?
else
    assert_msg_fail "no second failover within 60s"; rc=1
fi

# Bring back the two killed nodes; wait for convergence back to 3 members.
ssh -o StrictHostKeyChecking=accept-new "root@${p1}.lab.test" "systemctl restart patroni" || true
ssh -o StrictHostKeyChecking=accept-new "root@${p2}.lab.test" "systemctl restart patroni" || true
wait_member_count 3 60 || true
assert_member_count 3 || rc=$?

scenario_end "$rc"
