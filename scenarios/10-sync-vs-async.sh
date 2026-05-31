#!/usr/bin/env bash
# ==============================================================================
# Tytul:        10-sync-vs-async.sh
# Opis:         Przelaczanie synchronous_mode (patronictl edit-config) i pokazanie
#               tradeoff trwalosc vs dostepnosc zapisu. Przywraca tryb sync.
# Description [EN]: Toggle synchronous_mode (patronictl edit-config) and show the
#               durability-vs-write-availability tradeoff. Restores sync mode.
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - uruchamiac na VM cli; dzialajacy klaster PG/Patroni/etcd/HAProxy
#                    - scenarios/lib/assertions.sh; ssh root@ do wezlow pg*
#                    - zmienia konfiguracje DCS (edit-config); przywracana na koncu
# Requirements [EN]: - run on the cli VM; a running PG/Patroni/etcd/HAProxy cluster
#                    - scenarios/lib/assertions.sh; ssh root@ to pg* nodes
#                    - changes DCS config (edit-config); restored at the end
#
# Uzycie [PL]:       z hosta: lab.ps1 scenario 10  |  na cli: bash scenarios/10-sync-vs-async.sh
# Usage [EN]:        from host: lab.ps1 scenario 10 | on cli: bash scenarios/10-sync-vs-async.sh
# ==============================================================================
set -euo pipefail
SCENARIO_DIR=$(dirname "$(readlink -f "$0")")
source "$SCENARIO_DIR/lib/assertions.sh"
scenario_start "10-sync-vs-async"
rc=0

leader=$(patroni_leader)
assert_msg_info "current synchronous_mode at $leader:"
ssh -o StrictHostKeyChecking=accept-new "root@${leader}.lab.test" "patronictl -c /etc/patroni/patroni.yml show-config | grep -E 'synchronous_mode'"

assert_msg_info "switching to async (synchronous_mode=false), then back"
# Patroni 4.x: edit-config --apply oczekuje PLIKU (nie inline JSON) -> zapisujemy
# najpierw plik tymczasowy na wezle, potem go aplikujemy. / Patroni 4.x: edit-config
# --apply expects a FILE (not inline JSON) -> write a temp file on the node first.
ssh -o StrictHostKeyChecking=accept-new "root@${leader}.lab.test" "printf '%s\n' '{\"synchronous_mode\": false}' > /tmp/pgha_cfg.json && patronictl -c /etc/patroni/patroni.yml edit-config --apply /tmp/pgha_cfg.json --force; rm -f /tmp/pgha_cfg.json" || true
sleep 3
assert_can_write || rc=$?
ssh -o StrictHostKeyChecking=accept-new "root@${leader}.lab.test" "printf '%s\n' '{\"synchronous_mode\": true}' > /tmp/pgha_cfg.json && patronictl -c /etc/patroni/patroni.yml edit-config --apply /tmp/pgha_cfg.json --force; rm -f /tmp/pgha_cfg.json" || true

scenario_end "$rc"
