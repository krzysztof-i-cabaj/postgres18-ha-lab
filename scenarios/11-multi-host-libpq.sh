#!/usr/bin/env bash
# ==============================================================================
# Tytul:        11-multi-host-libpq.sh
# Opis:         Polaczenie z pominieciem HAProxy: multi-host libpq z
#               target_session_attrs=read-write samo znajduje zapisywalny wezel.
# Description [EN]: Connect bypassing HAProxy: multi-host libpq with
#               target_session_attrs=read-write finds the writeable node itself.
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - uruchamiac na VM cli; dzialajacy klaster PG/Patroni
#                    - scenarios/lib/assertions.sh; psql z obsluga multi-host libpq
#                    - nie wymaga HAProxy (laczy bezposrednio do pg*)
# Requirements [EN]: - run on the cli VM; a running PG/Patroni cluster
#                    - scenarios/lib/assertions.sh; psql with multi-host libpq
#                    - HAProxy not required (connects directly to pg*)
#
# Uzycie [PL]:       z hosta: lab.ps1 scenario 11  |  na cli: bash scenarios/11-multi-host-libpq.sh
# Usage [EN]:        from host: lab.ps1 scenario 11 | on cli: bash scenarios/11-multi-host-libpq.sh
# ==============================================================================
set -euo pipefail
SCENARIO_DIR=$(dirname "$(readlink -f "$0")")
source "$SCENARIO_DIR/lib/assertions.sh"
scenario_start "11-multi-host-libpq"
rc=0

CONN="host=pg1.lab.test,pg2.lab.test,pg3.lab.test port=5432 dbname=labdb user=lab password=lab target_session_attrs=read-write"
result=$(PGPASSWORD=lab psql "$CONN" -At -c "SELECT inet_server_addr()" 2>&1) || { assert_msg_fail "$result"; rc=1; }
if [[ -n "$result" && "$result" != *"FATAL"* ]]; then
    assert_msg_pass "multi-host libpq routed to: $result"
else
    assert_msg_fail "multi-host libpq failed: $result"
    rc=1
fi

scenario_end "$rc"
