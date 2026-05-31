#!/usr/bin/env bash
# ==============================================================================
# Tytul:        orchestrate.sh
# Opis:         Orkiestrator klastra. Dziala na cli VM. Czyta lab.config.json
#               (transferowane przez host przez scp), iteruje przez VMki w
#               kolejnosci zaleznosci (etcd -> postgresql -> patroni ->
#               haproxy -> pgbouncer -> client), wywoluje role/*.sh przez SSH.
#               Na koniec tworzy demo DB i uzytkownika.
# Description [EN]: Cluster orchestrator. Runs on cli VM. Reads lab.config.json
#               (uploaded by host via scp), iterates VMs in dependency order
#               (etcd -> postgresql -> patroni -> haproxy -> pgbouncer ->
#               client), invokes role/*.sh via SSH. Creates demo DB+user at end.
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# <repo>:       <repo>
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - cli VM ma SSH bez hasla do wszystkich VMek
#                    - guest/ rozpakowane w /usr/local/lib/postgres18-ha-lab
#                    - lab.config.json w tym samym katalogu, chmod 600
# Requirements [EN]: - cli VM has passwordless SSH to every VM
#                    - guest/ unpacked under /usr/local/lib/postgres18-ha-lab
#                    - lab.config.json in that directory, chmod 600
#
# Uzycie [PL]:       /usr/local/lib/postgres18-ha-lab/orchestrate.sh
# Usage [EN]:        /usr/local/lib/postgres18-ha-lab/orchestrate.sh
# ==============================================================================

set -euo pipefail
source /usr/local/lib/postgres18-ha-lab/lib/common.sh

LIB_DIR=/usr/local/lib/postgres18-ha-lab
CFG_JSON=$LIB_DIR/lab.config.json
LOG=/var/log/postgres18-ha-lab/orchestrate.log
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

# Guard jednej instancji: przerwany ssh (Ctrl+C na hoscie) zostawia osierocony
# orchestrate dzialajacy dalej na cli; powtorny `lab.ps1 provision` odpalilby drugi
# rownolegle -> kolizja (np. wiele `dnf` na tym samym wezle = blokada rpm, build
# "wisi"). flock przepuszcza tylko jedna instancje i od razu zglasza zajety lock.
# Single-instance guard: an interrupted ssh (Ctrl+C on the host) leaves an orphaned
# orchestrate still running on cli; a repeated `lab.ps1 provision` would start a
# second one in parallel -> collision (e.g. multiple `dnf` on one node = rpm lock,
# build "hangs"). flock admits only one instance and reports a held lock at once.
exec 9>/var/lock/postgres18-ha-lab-orchestrate.lock
if ! flock -n 9; then
    log_err "Inna instancja orchestrate.sh juz dziala (lock zajety) / another orchestrate.sh is already running. Aborting."
    exit 3
fi

if [[ ! -f "$CFG_JSON" ]]; then
    log_err "$CFG_JSON not found"
    exit 1
fi

# --- Helpers -----------------------------------------------------------------
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

remote() {
    # remote <host> <cmd...>
    local h=$1; shift
    ssh $SSH_OPTS "root@$h" "$@"
}

# Read JSON via jq (must be installed)
if ! command -v jq >/dev/null; then
    dnf install -y jq
fi

PG_NODES=( $(jq -r '.Vms[] | select(.Role=="pg-node") | .Hostname' "$CFG_JSON") )
LB_HOST=$(jq -r '.Vms[] | select(.Role=="lb") | .Hostname' "$CFG_JSON")
CLI_HOST=$(jq -r '.Vms[] | select(.Role=="cli") | .Hostname' "$CFG_JSON")

REPL_PWD=$(jq -r '.Secrets.ReplicatorPassword' "$CFG_JSON")
SUPER_PWD=$(jq -r '.Secrets.SuperuserPassword' "$CFG_JSON")
REWIND_PWD=$(jq -r '.Secrets.RewindPassword' "$CFG_JSON")
APP_PWD=$(jq -r '.Secrets.AppUserPassword' "$CFG_JSON")
WATCHDOG_MODE=$(jq -r '.Watchdog.Mode' "$CFG_JSON")
DOMAIN=$(jq -r '.Domain' "$CFG_JSON")
DBNAME=$(jq -r '.Cluster.Database' "$CFG_JSON")
APP_USER=$(jq -r '.Cluster.AppUser' "$CFG_JSON")

# Reject placeholder passwords
for v in "$REPL_PWD" "$SUPER_PWD" "$REWIND_PWD"; do
    if [[ "$v" == '@@REPLACE@@' || -z "$v" ]]; then
        log_err "Refusing to orchestrate with placeholder/empty password. Edit lab.config.psd1 on the host."
        exit 2
    fi
done

# --- Distribute guest/ to every node so 00-common etc. are available ---------
distribute_to() {
    local host=$1
    log_step "Distributing guest/ to $host"
    # scp -rp zamiast rsync: Rocky 9 minimal NIE zawiera rsync ("command not
    # found"), a scp jest czescia openssh (@core) na cli i na kazdym wezle.
    # Pliki sa male, wiec brak delta-transferu rsync nie ma znaczenia.
    # scp -rp instead of rsync: Rocky 9 minimal ships NO rsync ("command not
    # found"); scp is part of openssh (@core) on cli and every node. The files
    # are tiny, so losing rsync's delta transfer is irrelevant.
    ssh $SSH_OPTS "root@$host" "mkdir -p $LIB_DIR/lib $LIB_DIR/roles $LIB_DIR/templates"
    scp $SSH_OPTS -rp "$LIB_DIR/lib/"*       "root@$host:$LIB_DIR/lib/"
    scp $SSH_OPTS -rp "$LIB_DIR/roles/"*     "root@$host:$LIB_DIR/roles/"
    scp $SSH_OPTS -rp "$LIB_DIR/templates/"* "root@$host:$LIB_DIR/templates/"
    ssh $SSH_OPTS "root@$host" "chmod +x $LIB_DIR/roles/*.sh $LIB_DIR/lib/*.sh"
}

ALL_HOSTS=( $(jq -r '.Vms[] | select(.Role!="infra") | .Hostname' "$CFG_JSON") )
for h in "${ALL_HOSTS[@]}"; do
    if [[ "$h" == "$CLI_HOST" ]]; then continue; fi   # we are running here
    distribute_to "$h"
done

# --- 1. etcd on pg1/pg2/pg3 (parallel) ---------------------------------------
log_step "Phase 1: etcd"
pids=()
for h in "${PG_NODES[@]}"; do
    remote "$h" "$LIB_DIR/roles/10-etcd.sh install" &
    pids+=($!)
done
# wait TYLKO na PIDy tych zadan. Gole `wait` w bash 5.x (EL9) czeka takze na proces
# substitution `tee` z `exec > >(tee -a LOG)`, ktory nigdy nie konczy -> bariera
# wisi wiecznie mimo zakonczenia zadan (objaw: log staje po Fazie 1, brak Fazy 2).
# wait ONLY on these job PIDs. A bare `wait` in bash 5.x (EL9) also waits on the
# `tee` process substitution from `exec > >(tee -a LOG)`, which never exits -> the
# barrier hangs forever even after jobs finish (symptom: log stalls after Phase 1).
wait "${pids[@]}"

# --- 2. postgresql binaries (parallel) ---------------------------------------
log_step "Phase 2: postgresql binaries"
pids=()
for h in "${PG_NODES[@]}"; do
    remote "$h" "$LIB_DIR/roles/20-postgresql.sh install" &
    pids+=($!)
done
wait "${pids[@]}"   # patrz Faza 1: nie czekaj na proces substitution `tee` (bash 5.x hang)

# --- 3. patroni (sequential — clearer logs, leader emerges) ------------------
log_step "Phase 3: patroni"
for h in "${PG_NODES[@]}"; do
    remote "$h" "PATRONI_REPL_PWD='$REPL_PWD' PATRONI_SUPER_PWD='$SUPER_PWD' PATRONI_REWIND_PWD='$REWIND_PWD' PATRONI_APP_PASSWORD='$APP_PWD' WATCHDOG_MODE='$WATCHDOG_MODE' $LIB_DIR/roles/30-patroni.sh install"
done

# Wait for cluster to converge
log_step "Waiting for Patroni leader election"
for i in {1..30}; do
    LEADER=$(remote "${PG_NODES[0]}" "curl -fsS http://localhost:8008/cluster | jq -r '.members[] | select(.role==\"leader\") | .name' 2>/dev/null || true")
    if [[ -n "$LEADER" && "$LEADER" != "null" ]]; then
        log_ok "Leader: $LEADER"
        break
    fi
    sleep 5
done

# --- 4. haproxy + pgbouncer on lb --------------------------------------------
log_step "Phase 4: haproxy + pgbouncer on $LB_HOST"
remote "$LB_HOST" "$LIB_DIR/roles/40-haproxy.sh install"
remote "$LB_HOST" "APP_USER='$APP_USER' APP_DB='$DBNAME' APP_PWD='$APP_PWD' SUPER_PWD='$SUPER_PWD' $LIB_DIR/roles/50-pgbouncer.sh install"

# --- 5. client app on cli (we are here) --------------------------------------
log_step "Phase 5: client app on cli (here)"
$LIB_DIR/roles/60-client.sh install

# --- 6. demo DB + user -------------------------------------------------------
log_step "Phase 6: creating demo database '$DBNAME' and user '$APP_USER'"
# CREATE DATABASE nie moze dzialac w bloku DO/funkcji (PostgreSQL: "cannot be
# executed from a function") -> wykonujemy bezposrednio; "already exists" jest
# nieszkodliwe (idempotencja przy ponownym provision).
# CREATE DATABASE can't run inside a DO/function block (PostgreSQL) -> run it
# directly; "already exists" is harmless (idempotent re-provision).
PGPASSWORD="$SUPER_PWD" remote "${PG_NODES[0]}" "psql -h 127.0.0.1 -U postgres -c 'CREATE DATABASE $DBNAME' 2>&1 | grep -v 'already exists' || true"
PGPASSWORD="$SUPER_PWD" remote "${PG_NODES[0]}" "psql -h 127.0.0.1 -U postgres -c \"DO \\\$\\\$BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='$APP_USER') THEN CREATE ROLE $APP_USER LOGIN PASSWORD '$APP_PWD'; END IF; END\\\$\\\$\" 2>&1 || true"
PGPASSWORD="$SUPER_PWD" remote "${PG_NODES[0]}" "psql -h 127.0.0.1 -U postgres -c \"GRANT ALL ON DATABASE $DBNAME TO $APP_USER\" 2>&1 || true"

# Tabela demo pgha_writer_log -- wymagana przez scenariusze (assert_demo_schema,
# write_sentinel) i klienta testowego (client-app/writer.py). Tworzymy w bazie
# labdb na liderze (zreplikuje sie na standby); wlascicielem $APP_USER, by mial
# INSERT/SELECT + sekwencje. Schemat zgodny z client-app/pgha_client/writer.py.
# Demo table pgha_writer_log -- required by scenarios (assert_demo_schema,
# write_sentinel) and the test client (client-app/writer.py). Created in labdb on
# the leader (replicates to standbys); owned by $APP_USER so it has INSERT/SELECT +
# the sequence. Schema matches client-app/pgha_client/writer.py.
PGPASSWORD="$SUPER_PWD" remote "${PG_NODES[0]}" "psql -h 127.0.0.1 -U postgres -d $DBNAME -c 'CREATE TABLE IF NOT EXISTS pgha_writer_log (id BIGSERIAL PRIMARY KEY, ts TIMESTAMPTZ NOT NULL DEFAULT now(), payload TEXT NOT NULL, host TEXT NOT NULL DEFAULT inet_server_addr()::text); ALTER TABLE pgha_writer_log OWNER TO $APP_USER;' 2>&1 || true"

# --- 7. final state -----------------------------------------------------------
log_step "Phase 7: cluster state"
remote "${PG_NODES[0]}" "patronictl -c /etc/patroni/patroni.yml list" || log_warn "patronictl unavailable"

log_ok "Orchestration complete. Try: psql -h $LB_HOST -p 5000 -U $APP_USER -d $DBNAME"
