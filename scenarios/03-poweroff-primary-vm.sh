#!/usr/bin/env bash
# ==============================================================================
# Tytul:        03-poweroff-primary-vm.sh
# Opis:         Twardy poweroff VMki lidera (VBoxManage, po stronie hosta). Cli
#               loguje wymagana akcje hosta i czeka az lider sie zmieni.
# Description [EN]: Hard poweroff of the leader VM (VBoxManage, host-side). The cli
#               logs the required host action and waits for the leader to change.
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - uruchamiac przez lab.ps1 scenario 03 (akcja hosta: VBoxManage)
#                    - scenarios/lib/assertions.sh; ssh root@ do wezlow pg*
#                    - host musi wylaczyc VMke lidera, a potem ja podniesc
# Requirements [EN]: - run via lab.ps1 scenario 03 (host action: VBoxManage)
#                    - scenarios/lib/assertions.sh; ssh root@ to pg* nodes
#                    - host must power off the leader VM, then start it back
#
# Uzycie [PL]:       z hosta: lab.ps1 scenario 03 (cli sam nie wylaczy VMki)
# Usage [EN]:        from host: lab.ps1 scenario 03 (cli cannot power off the VM)
# ==============================================================================
set -euo pipefail
SCENARIO_DIR=$(dirname "$(readlink -f "$0")")
source "$SCENARIO_DIR/lib/assertions.sh"
scenario_start "03-poweroff-primary-vm"
rc=0

prev_leader=$(patroni_leader)
assert_msg_info "previous leader: $prev_leader (host should poweroff its VM)"
assert_msg_info "from host: VBoxManage controlvm $prev_leader poweroff"

# Wait for the host to power off the VM (signal: leader changes)
if wait_leader_change "$prev_leader" 90; then
    assert_leader_changed "$prev_leader" || rc=$?
    assert_msg_info "host should now: VBoxManage startvm $prev_leader --type headless"
else
    assert_msg_fail "no failover within 90s -- was VM actually powered off?"
    rc=1
fi

scenario_end "$rc"
