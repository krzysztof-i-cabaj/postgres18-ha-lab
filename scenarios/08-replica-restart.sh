#!/usr/bin/env bash
# ==============================================================================
# Tytul:        08-replica-restart.sh
# Opis:         systemctl restart patroni na replice; lider bez zmiany (zmiana
#               dopuszczalna), replika dolacza i klaster wraca do 3 czlonkow.
# Description [EN]: systemctl restart patroni on a replica; leader unchanged
#               (change acceptable), replica rejoins, cluster back to 3 members.
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
# Uzycie [PL]:       z hosta: lab.ps1 scenario 08  |  na cli: bash scenarios/08-replica-restart.sh
# Usage [EN]:        from host: lab.ps1 scenario 08 | on cli: bash scenarios/08-replica-restart.sh
# ==============================================================================
set -euo pipefail
SCENARIO_DIR=$(dirname "$(readlink -f "$0")")
source "$SCENARIO_DIR/lib/assertions.sh"
scenario_start "08-replica-restart"
rc=0
prev_leader=$(patroni_leader)
candidates=$(patroni_cluster_json | jq -r '.members[] | select(.role!="leader") | .name')
replica=$(echo "$candidates" | head -1)
ssh -o StrictHostKeyChecking=accept-new "root@${replica}.lab.test" "systemctl restart patroni"
wait_member_count 3 30 || true
assert_leader_exists || rc=$?
assert_member_count 3 || rc=$?
new_leader=$(patroni_leader)
# Miekki check: lider nie powinien sie zmienic, ale zmiana jest dopuszczalna.
[[ "$new_leader" == "$prev_leader" ]] && assert_msg_pass "leader unchanged" || assert_msg_info "leader changed (acceptable)"
scenario_end "$rc"
