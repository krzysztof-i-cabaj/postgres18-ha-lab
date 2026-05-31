#!/usr/bin/env bash
# ==============================================================================
# Tytul:        assertions.test.sh
# Opis:         Self-test pure funkcji parsujacych z assertions.sh (bez klastra).
#               Nadpisuje patroni_cluster_json fixtura JSON i sprawdza parsery
#               oraz semantyke wait_until. Bramkowany w CI (lint.yml).
# Description [EN]: Self-test for the pure parser functions in assertions.sh
#               (no live cluster). Overrides patroni_cluster_json with a JSON
#               fixture and checks parsers + wait_until semantics. CI-gated.
#
# Autor:        KCB Kris
# Data:         2026-05-26
# Wersja:       1.0
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - bash 4+, jq
# Requirements [EN]: - bash 4+, jq
#
# Uzycie [PL]:       bash scenarios/lib/assertions.test.sh
# Usage [EN]:        bash scenarios/lib/assertions.test.sh
# ==============================================================================

# shellcheck shell=bash source=scenarios/lib/assertions.sh
HERE=$(dirname "$(readlink -f "$0")")
source "$HERE/assertions.sh"
set +e  # assertions.sh wlacza set -e; w self-tescie chcemy kontynuowac po FAIL

# Fixture: 3-wezlowy klaster, lider pg1. Nadpisuje jedyna funkcje sieciowa,
# od ktorej zaleza parsery -- reszta liczona jest lokalnie.
patroni_cluster_json() {
    printf '%s' '{"members":[{"name":"pg1","role":"leader"},{"name":"pg2","role":"replica"},{"name":"pg3","role":"sync_standby"}]}'
}

fail=0
ck() { # ck <nazwa> <got> <want>
    if [[ "$2" == "$3" ]]; then
        echo "PASS $1"
    else
        echo "FAIL $1: got '$2' want '$3'"
        fail=1
    fi
}

# --- Parsery ----------------------------------------------------------------
ck "patroni_leader"        "$(patroni_leader)"          "pg1"
ck "patroni_member_count"  "$(patroni_member_count)"    "3"
ck "patroni_member_role"   "$(patroni_member_role pg2)" "replica"

# --- Predykaty pollingu -----------------------------------------------------
if _leader_differs "pg2"; then echo "PASS _leader_differs-true";  else echo "FAIL _leader_differs-true";  fail=1; fi
if _leader_differs "pg1"; then echo "FAIL _leader_differs-false"; fail=1; else echo "PASS _leader_differs-false"; fi

# pg3 == sync_standby, wiec nalezy do zbioru {replica, sync_standby}
if _member_role_in "pg3" replica sync_standby; then echo "PASS _member_role_in"; else echo "FAIL _member_role_in"; fail=1; fi

# --- wait_until -------------------------------------------------------------
if wait_until 1 false; then echo "FAIL wait_until-timeout"; fail=1; else echo "PASS wait_until-timeout"; fi
if wait_until 1 true;  then echo "PASS wait_until-success"; else echo "FAIL wait_until-success"; fail=1; fi

echo "----------------------------------------------------------------"
if (( fail == 0 )); then
    echo "assertions.test.sh: ALL PASS"
else
    echo "assertions.test.sh: FAILURES present"
fi
exit "$fail"
