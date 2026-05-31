#!/usr/bin/env bash
# ==============================================================================
# Tytul:        05-network-partition.sh
# Opis:         Partycja sieciowa lidera (iptables DROP dla 192.168.56.0/24);
#               watchdog + wygasniecie leasu etcd wymuszaja failover, potem heal.
# Description [EN]: Network partition of the leader (iptables DROP for 192.168.56.0/24);
#               watchdog + etcd lease expiry force failover, then the partition heals.
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - uruchamiac na VM cli; dzialajacy klaster PG/Patroni/etcd/HAProxy
#                    - scenarios/lib/assertions.sh; ssh root@ do wezlow pg*
#                    - DESTRUKCYJNY: modyfikuje iptables na liderze (flush na koncu)
# Requirements [EN]: - run on the cli VM; a running PG/Patroni/etcd/HAProxy cluster
#                    - scenarios/lib/assertions.sh; ssh root@ to pg* nodes
#                    - DESTRUCTIVE: modifies iptables on the leader (flushed at end)
#
# Uzycie [PL]:       z hosta: lab.ps1 scenario 05  |  na cli: bash scenarios/05-network-partition.sh
# Usage [EN]:        from host: lab.ps1 scenario 05 | on cli: bash scenarios/05-network-partition.sh
# ==============================================================================
set -euo pipefail
SCENARIO_DIR=$(dirname "$(readlink -f "$0")")
source "$SCENARIO_DIR/lib/assertions.sh"
scenario_start "05-network-partition"
rc=0
prev_leader=$(patroni_leader)
assert_msg_info "partitioning $prev_leader (self-healing after ~75s)"

# Partycja SELF-HEALING. Odcinamy lidera od CALEJ podsieci labu (DROP 192.168.56.0/24)
# -- co odcina go takze od cli i hosta, wiec NIE da sie zagoic zdalnie przez ssh
# (proba wisi w nieskonczonosc). Zamiast tego uruchamiamy na wezle ODLACZONY proces
# (setsid, przezywa zerwanie ssh): odetnij -> poczekaj 75s -> sam zagoj (iptables -F).
# `sleep 2` pozwala ssh czysto wrocic, zanim DROP zerwie polaczenie; `timeout 10` +
# ConnectTimeout to bezpieczniki, by ten krok nigdy nie wisial.
# SELF-HEALING partition. Dropping the whole lab subnet also cuts the node off from
# cli and the host, so it cannot be healed over ssh (the attempt hangs forever).
# Instead run a DETACHED process on the node (setsid survives the ssh teardown):
# drop -> wait 75s -> self-heal (iptables -F). `sleep 2` lets ssh return cleanly
# before DROP kills the link; `timeout 10` + ConnectTimeout are guards so this step
# can never hang.
timeout 10 ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 "root@${prev_leader}.lab.test" \
  "setsid bash -c 'sleep 2; iptables -I INPUT -s 192.168.56.0/24 -j DROP; iptables -I OUTPUT -d 192.168.56.0/24 -j DROP; sleep 75; iptables -F INPUT; iptables -F OUTPUT' >/dev/null 2>&1 &" || true

if wait_leader_change "$prev_leader" 60; then
    assert_leader_changed "$prev_leader" || rc=$?
else
    assert_msg_fail "no failover within 60s"
    rc=1
fi

# Partycja zagoi sie SAMA po ~75s (timer na wezle); stary lider wroci jako replika.
# Celowo BRAK zdalnego `iptables -F` -- bylby nieosiagalny przez odcieta siec.
# The partition self-heals after ~75s (on-node timer); the old leader rejoins as a
# replica. Intentionally NO remote `iptables -F` -- it would be unreachable.
assert_msg_info "partition self-heals in ~75s; old leader rejoins as replica"

scenario_end "$rc"
