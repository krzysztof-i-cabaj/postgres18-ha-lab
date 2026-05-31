#!/usr/bin/env bash
# ==============================================================================
# Tytul:        02-kill-primary-hard.sh
# Opis:         Twardy failover: pkill -9 postgres na liderze; weryfikacja zmiany
#               lidera oraz braku utraty danych (sentinel commitowany przed awaria).
# Description [EN]: Hard failover: pkill -9 postgres on the leader; verify leader
#               change and zero data loss (sentinel committed before the kill).
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - uruchamiac na VM cli; dzialajacy klaster PG/Patroni/etcd/HAProxy
#                    - scenarios/lib/assertions.sh; ssh root@ do wezlow pg*
#                    - tabela demo public.pgha_writer_log (sentinel zero-data-loss)
#                    - DESTRUKCYJNY: zabija proces postgres na liderze
# Requirements [EN]: - run on the cli VM; a running PG/Patroni/etcd/HAProxy cluster
#                    - scenarios/lib/assertions.sh; ssh root@ to pg* nodes
#                    - demo table public.pgha_writer_log (zero-data-loss sentinel)
#                    - DESTRUCTIVE: kills the postgres process on the leader
#
# Uzycie [PL]:       z hosta: lab.ps1 scenario 02  |  na cli: bash scenarios/02-kill-primary-hard.sh
# Usage [EN]:        from host: lab.ps1 scenario 02 | on cli: bash scenarios/02-kill-primary-hard.sh
# ==============================================================================
set -euo pipefail
SCENARIO_DIR=$(dirname "$(readlink -f "$0")")
source "$SCENARIO_DIR/lib/assertions.sh"
scenario_start "02-kill-primary-hard"
rc=0

assert_demo_schema || { scenario_end 1; exit 1; }

prev_leader=$(patroni_leader)
# Commit wiersza-sentinela PRZED awaria -- synchronous_mode ma go zachowac.
sentinel_id=$(write_sentinel)
assert_msg_info "previous leader: $prev_leader, sentinel id=$sentinel_id"

# Samo `pkill -9 postgres` NIE wywola failoveru: Patroni (osobny proces) zrestartuje
# postgres lokalnie szybciej niz wygasnie lease etcd (TTL 30s) -> lider sie nie zmienia.
# Dlatego po twardym zabiciu postgresa zatrzymujemy tez Patroni (stop = systemd go nie
# wskrzesi), co zwalnia lease i wymusza promocje sync_standby. / `pkill -9 postgres`
# alone won't fail over: Patroni restarts postgres locally before the etcd lease (TTL
# 30s) expires. So after the hard kill we also stop Patroni (stop = systemd won't
# resurrect it), releasing the lease and forcing the sync_standby to be promoted.
ssh -o StrictHostKeyChecking=accept-new "root@${prev_leader}.lab.test" "pkill -9 postgres; systemctl stop patroni" || true

assert_msg_info "waiting up to 60s for new leader"
if wait_leader_change "$prev_leader" 60; then
    assert_leader_changed "$prev_leader" || rc=$?
else
    assert_msg_fail "leader did not change within 60s"; rc=1
fi

# Cluster should re-stabilise; wait for HAProxy to re-route, then reads/writes resume
# Bufor na "rise" nowego lidera w HAProxy (inter 5s) + ustanowienie sync_standby,
# inaczej backend :5000 oscyluje tuz po failoverze. / Buffer for HAProxy to "rise"
# the new leader (inter 5s) + establish sync_standby; the :5000 backend flaps right
# after failover otherwise.
sleep 12
wait_haproxy_primary 30 || true
wait_writable 30 || true   # sync_mode: poczekaj az nowy sync_standby pozwoli na zapis
assert_can_read || rc=$?
assert_can_write || rc=$?
# Faktyczna weryfikacja tezy "failover bez utraty danych".
assert_row_survived "$sentinel_id" || rc=$?

# Przywroc stary wezel (zatrzymalismy go powyzej) -- Patroni zrobi pg_rewind
# i dolaczy go jako replike. / Bring the old node back (we stopped it above) --
# Patroni runs pg_rewind and rejoins it as a replica.
ssh -o StrictHostKeyChecking=accept-new "root@${prev_leader}.lab.test" "systemctl start patroni" || true

scenario_end "$rc"
