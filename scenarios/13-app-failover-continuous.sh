#!/usr/bin/env bash
# ==============================================================================
# Tytul:        13-app-failover-continuous.sh
# Opis:         Failover z perspektywy aplikacji: pgha-client writer+reader generuja
#               ciagly ruch, w trakcie zabijamy lidera; mierzymy okno niedostepnosci
#               (downtime, outages, reconnecty) i dowodzimy ciaglosci zapisu/odczytu.
# Description [EN]: App-perspective failover: pgha-client writer+reader drive continuous
#               load while we kill the leader; measure the availability gap (downtime,
#               outages, reconnects) and prove writes/reads kept flowing.
#
# Autor:        KCB Kris
# Data:         2026-05-31
# Wersja:       1.0
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - uruchamiac na VM cli; dzialajacy klaster PG/Patroni/etcd/HAProxy
#                    - pgha-client (client-app) zainstalowany (60-client.sh)
#                    - scenarios/lib/assertions.sh; ssh root@ do wezlow pg*; jq
#                    - tabela demo public.pgha_writer_log (kolumna host = inet_server_addr)
#                    - DESTRUKCYJNY: zabija proces postgres na liderze
# Requirements [EN]: - run on the cli VM; a running PG/Patroni/etcd/HAProxy cluster
#                    - pgha-client (client-app) installed (60-client.sh)
#                    - scenarios/lib/assertions.sh; ssh root@ to pg* nodes; jq
#                    - demo table public.pgha_writer_log (host column = inet_server_addr)
#                    - DESTRUCTIVE: kills the postgres process on the leader
#
# Uzycie [PL]:       z hosta: lab.ps1 scenario 13  |  na cli: bash scenarios/13-app-failover-continuous.sh
# Usage [EN]:        from host: lab.ps1 scenario 13 | on cli: bash scenarios/13-app-failover-continuous.sh
# ==============================================================================
set -euo pipefail
SCENARIO_DIR=$(dirname "$(readlink -f "$0")")
source "$SCENARIO_DIR/lib/assertions.sh"
scenario_start "13-app-failover-continuous"
rc=0

# Katalog na artefakty aplikacji (JSON metryk + snapshoty klastra) obok logow scenariuszy.
# App artefacts (metrics JSON + cluster snapshots) next to the scenario logs.
APP_DIR="$(dirname "$SCENARIO_LOG")/app"
mkdir -p "$APP_DIR"
WRITER_JSON="$APP_DIR/writer.json"
READER_JSON="$APP_DIR/reader.json"
DURATION=60          # czas trwania obciazenia (s)
RATE=10              # operacji/s
DOWNTIME_BUDGET=45   # maks. akceptowalne najdluzsze okno niedostepnosci (s)
export PGPASSWORD=lab

PGHA=$(command -v pgha-client || true)
if [[ -z "$PGHA" ]]; then
    assert_msg_fail "pgha-client not found on PATH -- uruchom role 60-client.sh (pip install -e client-app)"
    scenario_end 1; exit 1
fi

assert_demo_schema || { scenario_end 1; exit 1; }

prev_leader=$(patroni_leader)
# Punkt odniesienia: liczymy rozne wezly obslugujace zapis tylko dla biezacego przebiegu.
base_id=$(psql_haproxy "SELECT COALESCE(MAX(id),0) FROM pgha_writer_log")
assert_msg_info "previous leader: $prev_leader, base id=$base_id, load ${RATE}Hz/${DURATION}s"

# Snapshot stanu klastra PRZED awaria (do raportu).
"$PGHA" monitor --snapshot > "$APP_DIR/cluster-before.json" 2>/dev/null || true

# Start ciaglego obciazenia w tle: writer przez HAProxy (:5000), reader bezposrednio
# przez multi-host libpq (target_session_attrs=read-write). Oba reconnectuja przy failoverze.
"$PGHA" writer --rate "$RATE" --target haproxy --duration "$DURATION" --report "$WRITER_JSON" &
writer_pid=$!
"$PGHA" reader --rate "$RATE" --target direct  --duration "$DURATION" --report "$READER_JSON" &
reader_pid=$!
assert_msg_info "writer pid=$writer_pid, reader pid=$reader_pid -- rozbieg 8s przed awaria"
sleep 8

# Wstrzykniecie awarii lidera (technika ze scenariusza 02): samo pkill nie wystarczy,
# Patroni wskrzesza postgres lokalnie przed wygasnieciem lease -> stop patroni zwalnia lease.
# Inject leader failure (technique from scenario 02): pkill alone won't fail over;
# Patroni restarts postgres before the lease expires -> stop patroni releases the lease.
assert_msg_info "killing leader $prev_leader (pkill -9 postgres + systemctl stop patroni)"
ssh -o StrictHostKeyChecking=accept-new "root@${prev_leader}.lab.test" \
    "pkill -9 postgres; systemctl stop patroni" || true

assert_msg_info "waiting up to 60s for new leader"
if wait_leader_change "$prev_leader" 60; then
    assert_leader_changed "$prev_leader" || rc=$?
else
    assert_msg_fail "leader did not change within 60s"; rc=1
fi
wait_haproxy_primary 30 || true
wait_writable 30 || true

# Czekamy az obciazenie w tle dobiegnie konca (--duration) i zapisze JSON.
# Wait for the background load to finish (--duration) and flush its JSON report.
assert_msg_info "waiting for background load to finish (writer/reader)"
wait "$writer_pid" 2>/dev/null || true
wait "$reader_pid" 2>/dev/null || true

# Snapshot stanu klastra PO failoverze (do raportu).
"$PGHA" monitor --snapshot > "$APP_DIR/cluster-after.json" 2>/dev/null || true

# --- Asercje na metrykach aplikacji ---
assert_app_kept_writing "$WRITER_JSON" || rc=$?
assert_downtime_within "$WRITER_JSON" "$DOWNTIME_BUDGET" || rc=$?
assert_reads_progressed "$READER_JSON" || rc=$?
assert_multi_host_served 2 "$base_id" || rc=$?
assert_can_read || rc=$?
assert_can_write || rc=$?

# Przywroc stary wezel -- Patroni zrobi pg_rewind i dolaczy go jako replike.
# Bring the old node back -- Patroni runs pg_rewind and rejoins it as a replica.
ssh -o StrictHostKeyChecking=accept-new "root@${prev_leader}.lab.test" "systemctl start patroni" || true
wait_member_count 3 60 || true

scenario_end "$rc"
