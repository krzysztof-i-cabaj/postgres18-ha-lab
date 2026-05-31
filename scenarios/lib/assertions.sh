#!/usr/bin/env bash
# ==============================================================================
# Tytul:        assertions.sh
# Opis:         Biblioteka asercji dla scenariuszy awarii. Funkcje zwracaja 0
#               (PASS) / >0 (FAIL) i loguja wynik. Source z scenarios/*.sh.
# Description [EN]: Assertion library for failure scenarios. Functions return 0
#               (PASS) / >0 (FAIL) and log the result. Sourced by scenarios/*.sh.
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# <repo>:       <repo>
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - bash 4+, curl, jq, psql, ssh do PG nodes, sed (GNU)
#                    - tabela demo public.pgha_writer_log (tworzona przez guest/orchestrate.sh)
# Requirements [EN]: - bash 4+, curl, jq, psql, ssh to PG nodes, GNU sed
#                    - demo table public.pgha_writer_log (created by guest/orchestrate.sh)
#
# Uzycie [PL]:       source scenarios/lib/assertions.sh
# Usage [EN]:        source scenarios/lib/assertions.sh
# ==============================================================================

# shellcheck shell=bash
set -euo pipefail

PG_NODES_DEFAULT=("pg1.lab.test" "pg2.lab.test" "pg3.lab.test")
LB_HOST_DEFAULT="lb.lab.test"

if [[ -z "${C_GRN:-}" ]]; then
    if [[ -t 1 ]]; then
        C_GRN=$'\e[32m'; C_RED=$'\e[31m'; C_YLW=$'\e[33m'; C_RST=$'\e[0m'
    else
        C_GRN=''; C_RED=''; C_YLW=''; C_RST=''
    fi
fi

assert_msg_pass() { echo "${C_GRN}PASS${C_RST} $*"; }
assert_msg_fail() { echo "${C_RED}FAIL${C_RST} $*" >&2; }
assert_msg_info() { echo "${C_YLW}INFO${C_RST} $*"; }

# --- Patroni cluster state via REST -----------------------------------------
patroni_cluster_json() {
    local node
    for node in "${PG_NODES_DEFAULT[@]}"; do
        if curl -fsS --max-time 3 "http://$node:8008/cluster" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

patroni_leader() {
    patroni_cluster_json | jq -r '.members[] | select(.role=="leader") | .name' 2>/dev/null
}

patroni_member_count() {
    patroni_cluster_json | jq -r '.members | length' 2>/dev/null
}

patroni_member_role() {
    local name=$1
    patroni_cluster_json | jq -r ".members[] | select(.name==\"$name\") | .role"
}

# get_leader [timeout_sec] -- echo nazwy lidera, ponawiajac az bedzie niepusty.
# Chroni przed przejsciowym brakiem lidera w DCS (curl trafia w okno elekcji/blip):
# bez tego pojedynczy pusty odczyt daje `ssh root@.lab.test` i psuje scenariusz.
# echo the leader name, retrying until non-empty -- guards against a transient
# leaderless DCS read (otherwise an empty read yields `ssh root@.lab.test`).
get_leader() {
    local t=${1:-15} i l
    for ((i=0; i<t; i++)); do
        l=$(patroni_leader)
        if [[ -n "$l" && "$l" != "null" ]]; then printf '%s' "$l"; return 0; fi
        sleep 1
    done
    return 1
}

assert_leader_exists() {
    local leader
    leader=$(patroni_leader)
    if [[ -n "$leader" && "$leader" != "null" ]]; then
        assert_msg_pass "leader is $leader"
        return 0
    fi
    assert_msg_fail "no leader visible"
    return 1
}

assert_leader_changed() {
    local prev=$1
    local cur
    cur=$(patroni_leader)
    if [[ "$cur" != "$prev" && -n "$cur" && "$cur" != "null" ]]; then
        assert_msg_pass "leader changed: $prev -> $cur"
        return 0
    fi
    assert_msg_fail "leader did not change (still $cur)"
    return 1
}

wait_until() {
    # wait_until <timeout_sec> <cmd...>
    local t=$1; shift
    local i
    for ((i=0; i<t; i++)); do
        if "$@" >/dev/null 2>&1; then return 0; fi
        sleep 1
    done
    return 1
}

# --- Polling predicates (ciche) + waitery -----------------------------------
# Predykaty zwracaja tylko status (bez logow) i sa wolane w biezacym shellu
# przez wait_until -- dzieki temu maja dostep do funkcji patroni_* (bash -c by nie mial).

_leader_differs() {
    local prev=$1 cur
    cur=$(patroni_leader)
    [[ -n "$cur" && "$cur" != "null" && "$cur" != "$prev" ]]
}

# wait_leader_change <prev_leader> [timeout_sec] -- 0 gdy lider sie zmienil
wait_leader_change() { wait_until "${2:-60}" _leader_differs "$1"; }

_member_count_is() { [[ "$(patroni_member_count)" == "$1" ]]; }

# wait_member_count <n> [timeout_sec] -- 0 gdy widocznych jest n czlonkow
wait_member_count() { wait_until "${2:-60}" _member_count_is "$1"; }

_member_role_in() {
    local name=$1; shift
    local role
    role=$(patroni_member_role "$name")
    [[ -n "$role" && " $* " == *" $role "* ]]
}

# wait_member_role <name> <timeout_sec> <role...> -- 0 gdy wezel ma jedna z rol
wait_member_role() { local name=$1 t=$2; shift 2; wait_until "$t" _member_role_in "$name" "$@"; }

# --- Connectivity through HAProxy -------------------------------------------
psql_haproxy() {
    local sql=$1
    # head -n1: dla INSERT ... RETURNING psql potrafi dokleic wiersz tagu polecenia
    # ("INSERT 0 1") po wartosci -> bierzemy tylko 1. linie (czysty id/licznik),
    # inaczej skazony id psuje pozniejsze `WHERE id = $id`.
    # head -n1: for INSERT ... RETURNING psql may append the command-tag line
    # ("INSERT 0 1") after the value -> take only the 1st line (clean id/count),
    # otherwise a polluted id breaks later `WHERE id = $id`.
    #
    # timeout 8 + PGCONNECT_TIMEOUT=5: tuz po failoverze HAProxy na :5000 przejsciowo
    # nie ma backendu (stary lider martwy, nowy jeszcze nie "rise") -> goly psql bez
    # timeoutu potrafi wisiec w nieskonczonosc (akceptowane polaczenie czeka na backend).
    # Bounduje to i connect, i zapytanie, by predykaty wait_* (wait_haproxy_primary,
    # wait_writable) mogly ponowic, zamiast zablokowac caly scenariusz. / right after a
    # failover the :5000 backend is transiently absent and a plain psql can hang forever;
    # bound both connect and query so the wait_* predicates can retry.
    PGPASSWORD=lab PGCONNECT_TIMEOUT=5 timeout 8 psql -h "$LB_HOST_DEFAULT" -p 5000 -U lab -d labdb -At -c "$sql" 2>/dev/null | head -n1
}

assert_can_write() {
    local r
    r=$(psql_haproxy "INSERT INTO pgha_writer_log (payload) VALUES ('assert-write-' || extract(epoch from now())) RETURNING id") || true
    if [[ -n "$r" ]]; then
        assert_msg_pass "write through HAProxy ok (id=$r)"
        return 0
    fi
    assert_msg_fail "write through HAProxy failed"
    return 1
}

assert_can_read() {
    local r
    r=$(psql_haproxy "SELECT count(*) FROM pgha_writer_log") || true
    if [[ -n "$r" ]]; then
        assert_msg_pass "read through HAProxy ok (rows=$r)"
        return 0
    fi
    assert_msg_fail "read through HAProxy failed"
    return 1
}

assert_member_count() {
    local n=$1 cur
    cur=$(patroni_member_count)
    if [[ "$cur" == "$n" ]]; then
        assert_msg_pass "$n members visible"
        return 0
    fi
    assert_msg_fail "expected $n members, got '$cur'"
    return 1
}

# --- Demo schema + weryfikacja braku utraty danych --------------------------
# Guard: jasny komunikat zamiast cichego FAIL gdy brak schematu demo.
assert_demo_schema() {
    if [[ "$(psql_haproxy "SELECT to_regclass('public.pgha_writer_log') IS NOT NULL")" == "t" ]]; then
        return 0
    fi
    assert_msg_fail "pgha_writer_log missing -- uruchom guest/orchestrate.sh (demo schema)"
    return 1
}

# write_sentinel -- wstawia wiersz i wypisuje jego id na stdout (commit PRZED awaria).
write_sentinel() {
    psql_haproxy "INSERT INTO pgha_writer_log (payload) VALUES ('sentinel-' || clock_timestamp()) RETURNING id"
}

# assert_row_survived <id> -- 0 gdy wiersz przetrwal failover (dowod braku utraty danych).
assert_row_survived() {
    local id=$1 r
    r=$(psql_haproxy "SELECT 1 FROM pgha_writer_log WHERE id = $id") || true
    if [[ "$r" == "1" ]]; then
        assert_msg_pass "committed row $id survived failover (no data loss)"
        return 0
    fi
    assert_msg_fail "committed row $id LOST across failover (data loss!)"
    return 1
}

_haproxy_primary_up() { [[ "$(psql_haproxy "SELECT 1")" == "1" ]]; }

# wait_haproxy_primary [timeout_sec] -- 0 gdy HAProxy (port 5000) znow trafia do
# lidera po failoverze (zastepuje sztywne "sleep na re-stabilizacje").
wait_haproxy_primary() { wait_until "${1:-30}" _haproxy_primary_up; }

# Po failoverze/switchoverze w synchronous_mode nowy lider moze przejsciowo
# odrzucac ZAPIS, dopoki nie ustanowi sie nowy sync_standby (SELECT przechodzi,
# INSERT nie). Czekamy az zapis faktycznie wroci -- to nie blad, to trwalosc HA.
# After failover/switchover in synchronous_mode the new leader may transiently
# reject WRITES until a new sync_standby is established (SELECT passes, INSERT
# doesn't). Wait until writes actually resume -- not a bug, it's HA durability.
_can_write_ok() { [[ -n "$(psql_haproxy "INSERT INTO pgha_writer_log (payload) VALUES ('probe-'||clock_timestamp()) RETURNING id")" ]]; }
wait_writable() { wait_until "${1:-30}" _can_write_ok; }

# --- etcd health -------------------------------------------------------------
etcd_healthy_count() {
    local healthy=0 node
    for node in "${PG_NODES_DEFAULT[@]}"; do
        if ssh -o StrictHostKeyChecking=accept-new "root@$node" \
            "etcdctl --endpoints=http://localhost:2379 endpoint health" >/dev/null 2>&1; then
            healthy=$((healthy + 1))
        fi
    done
    printf '%s' "$healthy"
}

assert_etcd_quorum() {
    local healthy
    healthy=$(etcd_healthy_count)
    if (( healthy >= 2 )); then
        assert_msg_pass "etcd quorum healthy ($healthy/3 nodes)"
        return 0
    fi
    assert_msg_fail "etcd quorum lost ($healthy/3 nodes)"
    return 1
}

_etcd_quorum_ok() { local h; h=$(etcd_healthy_count); (( h >= 2 )); }

# wait_etcd_quorum [timeout_sec] -- 0 gdy kworum (>=2/3) wrocilo
wait_etcd_quorum() { wait_until "${1:-30}" _etcd_quorum_ok; }

# --- App-driven failover (pgha-client JSON reports) -------------------------
# Asercje czytaja JSON wygenerowany przez `pgha-client writer/reader --report`.
# Wspolny guard na brak/uszkodzony plik -> czytelny FAIL zamiast cichego bledu jq.
# Assertions read JSON produced by `pgha-client writer/reader --report`.
_app_json_ok() {
    local f=$1
    if [[ ! -s "$f" ]] || ! jq -e . "$f" >/dev/null 2>&1; then
        assert_msg_fail "app report missing or invalid JSON: $f"
        return 1
    fi
    return 0
}

# assert_app_kept_writing <writer.json> -- 0 gdy app pisala (inserts>0) i realnie
# trafila w okno awarii oraz wstala (outages>=1). / writer kept writing and recovered.
assert_app_kept_writing() {
    local f=$1 inserts outages
    _app_json_ok "$f" || return 1
    inserts=$(jq -r '.inserts // 0' "$f")
    outages=$(jq -r '.outages // 0' "$f")
    if (( inserts > 0 && outages >= 1 )); then
        assert_msg_pass "app kept writing across failover (inserts=$inserts, outages=$outages)"
        return 0
    fi
    assert_msg_fail "app did not exercise failover (inserts=$inserts, outages=$outages)"
    return 1
}

# assert_downtime_within <report.json> <max_sec> -- 0 gdy najdluzsze okno
# niedostepnosci <= max_sec (failover zmiescil sie w budzecie). / max outage within budget.
assert_downtime_within() {
    local f=$1 max=$2 dmax
    _app_json_ok "$f" || return 1
    dmax=$(jq -r '.downtime_max_sec // 0' "$f")
    if jq -e --argjson m "$max" '.downtime_max_sec <= $m' "$f" >/dev/null; then
        assert_msg_pass "max downtime ${dmax}s within budget (<= ${max}s)"
        return 0
    fi
    assert_msg_fail "max downtime ${dmax}s exceeded budget (> ${max}s)"
    return 1
}

# assert_reads_progressed <reader.json> -- 0 gdy max_id wzrosl (zapisy postepowaly
# i replikowaly sie podczas testu). / reads observed new rows during the run.
assert_reads_progressed() {
    local f=$1 a b
    _app_json_ok "$f" || return 1
    a=$(jq -r '.max_id_start // 0' "$f")
    b=$(jq -r '.max_id_end // 0' "$f")
    if (( b > a )); then
        assert_msg_pass "reads progressed (max_id $a -> $b)"
        return 0
    fi
    assert_msg_fail "reads did not progress (max_id stuck at $a)"
    return 1
}

# assert_multi_host_served [min_hosts] [since_id] -- 0 gdy zapisy od `since_id`
# obsluzylo >= min roznych wezlow (kolumna host = inet_server_addr) -- dowod, ze
# HAProxy przelaczyl primary. `since_id` ogranicza liczenie do biezacego przebiegu
# (tabela kumuluje wiersze z poprzednich scenariuszy). / writes since `since_id`
# served by >= min distinct nodes (proof HAProxy moved the primary).
assert_multi_host_served() {
    local min=${1:-2} since=${2:-0} n
    n=$(psql_haproxy "SELECT count(DISTINCT host) FROM pgha_writer_log WHERE host IS NOT NULL AND id > $since")
    if [[ -n "$n" ]] && (( n >= min )); then
        assert_msg_pass "writes served by $n distinct hosts since id=$since (>= $min, primary moved)"
        return 0
    fi
    assert_msg_fail "writes served by only '$n' hosts since id=$since (expected >= $min)"
    return 1
}

# --- Logging boilerplate -----------------------------------------------------
scenario_start() {
    local name=$1
    SCENARIO_NAME="$name"
    SCENARIO_LOG="/var/log/postgres18-ha-lab/scenarios/${name}-$(date +%Y%m%dT%H%M%S).log"
    mkdir -p "$(dirname "$SCENARIO_LOG")"
    # Terminal dostaje kolory; plik logu -- czysty tekst (sed -u usuwa sekwencje ANSI).
    # PID loggera zapamietujemy, by w scenario_end domknac strumien i poczekac na flush.
    exec > >(tee >(sed -u 's/\x1b\[[0-9;]*m//g' >> "$SCENARIO_LOG")) 2>&1
    _SCENARIO_LOGGER_PID=$!
    echo "================================================================"
    echo " SCENARIO: $name"
    echo " STARTED:  $(date -Is)"
    echo "================================================================"
}

scenario_end() {
    local rc=$1
    echo "================================================================"
    if (( rc == 0 )); then
        echo "${C_GRN} SCENARIO PASSED: $SCENARIO_NAME${C_RST}"
    else
        echo "${C_RED} SCENARIO FAILED: $SCENARIO_NAME (rc=$rc)${C_RST}"
    fi
    echo " ENDED:    $(date -Is)"
    echo " LOG:      $SCENARIO_LOG"
    echo "================================================================"
    # Domknij stdout/stderr by tee dostal EOF, potem zaczekaj na zrzut bufora
    # (eliminuje ucinanie ostatnich linii logu -- race procesu podstawionego).
    exec 1>&- 2>&-
    [[ -n "${_SCENARIO_LOGGER_PID:-}" ]] && wait "$_SCENARIO_LOGGER_PID" 2>/dev/null || true
    return "$rc"
}
