#!/usr/bin/env bash
# ==============================================================================
# Tytul:        04-graceful-switchover.sh
# Opis:         Planowy switchover (patronictl): kontrolowana zmiana lidera bez
#               utraty danych; po zmianie write nadal dziala.
# Description [EN]: Planned switchover (patronictl): controlled leadership change
#               with no data loss; writes continue afterwards.
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
# Uzycie [PL]:       z hosta: lab.ps1 scenario 04  |  na cli: bash scenarios/04-graceful-switchover.sh
# Usage [EN]:        from host: lab.ps1 scenario 04 | on cli: bash scenarios/04-graceful-switchover.sh
# ==============================================================================
set -euo pipefail
SCENARIO_DIR=$(dirname "$(readlink -f "$0")")
source "$SCENARIO_DIR/lib/assertions.sh"
scenario_start "04-graceful-switchover"
rc=0
prev_leader=$(patroni_leader)
# W synchronous_mode Patroni przyjmuje switchover TYLKO do aktualnego sync_standby
# (inaczej: "412, candidate name does not match with sync_standby"). Wybieramy wiec
# sync_standby; fallback na dowolna replike, gdyby tryb byl async.
# In synchronous_mode Patroni only accepts a switchover to the current sync_standby
# (else "412, candidate ... does not match with sync_standby"). Pick sync_standby;
# fall back to any replica if the mode happens to be async.
new_leader=$(patroni_cluster_json | jq -r '.members[] | select(.role=="sync_standby") | .name' | head -1)
[[ -z "$new_leader" ]] && new_leader=$(patroni_cluster_json | jq -r '.members[] | select(.role!="leader") | .name' | head -1)

assert_msg_info "switchover $prev_leader -> $new_leader"
# Patroni 4.x: opcja to --leader (dawne --master usuniete). / Patroni 4.x uses
# --leader (the old --master was removed).
ssh -o StrictHostKeyChecking=accept-new "root@${prev_leader}.lab.test" "patronictl -c /etc/patroni/patroni.yml switchover --leader $prev_leader --candidate $new_leader --force"

wait_leader_change "$prev_leader" 30 || true
assert_leader_changed "$prev_leader" || rc=$?
# Po switchover HAProxy musi przejsc health-check "rise" nowego lidera (inter 5s),
# a klaster ustanowic nowy sync_standby -- bez bufora backend :5000 oscyluje
# UP/DOWN i pierwszy zapis trafia w okno niedostepnosci. / After switchover give
# HAProxy time to "rise" the new leader (inter 5s) and the cluster to establish a
# new sync_standby; otherwise the :5000 backend flaps and the first write misses.
sleep 12
wait_haproxy_primary 30 || true
wait_writable 30 || true   # sync_mode: poczekaj az nowy sync_standby pozwoli na zapis
assert_can_write || rc=$?
scenario_end "$rc"
