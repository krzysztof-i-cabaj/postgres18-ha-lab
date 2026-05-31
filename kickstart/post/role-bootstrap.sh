#!/usr/bin/env bash
# ==============================================================================
# Tytul:        role-bootstrap.sh
# Opis:         Pierwszy boot kazdej VMki — czyta /etc/postgres18-ha-lab/role,
#               sciaga z KS servera odpowiedni guest/roles/*.sh i guest/lib/*.sh,
#               uruchamia `install`, oznacza .bootstrapped (idempotencja).
# Description [EN]: Each VM's first boot — reads /etc/postgres18-ha-lab/role,
#               pulls the appropriate guest/roles/*.sh and guest/lib/*.sh from
#               the KS server, runs `install`, marks .bootstrapped (idempotent).
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# <repo>:       <repo>
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - Rocky 9.x, network-online.target, curl, /etc/postgres18-ha-lab/*
# Requirements [EN]: - Rocky 9.x, network-online.target, curl, /etc/postgres18-ha-lab/*
#
# Uzycie [PL]:       Wywolywany przez systemd (firstboot-role.service)
# Usage [EN]:        Invoked by systemd (firstboot-role.service)
# ==============================================================================

set -euo pipefail

LOG_DIR=/var/log/postgres18-ha-lab
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_DIR/role-bootstrap.log") 2>&1

echo "[role-bootstrap] $(date -Is) starting"

CFG_DIR=/etc/postgres18-ha-lab
ROLE=$(cat "$CFG_DIR/role")
KS_SERVER=$(cat "$CFG_DIR/ks_server")
MARK_DIR=/var/lib/postgres18-ha-lab
MARK="$MARK_DIR/.bootstrapped"
LIB_DIR=/usr/local/lib/postgres18-ha-lab

mkdir -p "$LIB_DIR/lib" "$LIB_DIR/roles" "$LIB_DIR/templates" "$MARK_DIR"

if [[ -f "$MARK" ]]; then
    echo "[role-bootstrap] already bootstrapped, exiting"
    exit 0
fi

# Map role to script filename(s). Non-infra VMs run 00-common first (DNS+NTP
# client wiring), then the role-specific script. Infra runs 05-infra only —
# it cannot depend on itself for DNS.
case "$ROLE" in
    infra)    SCRIPTS=( "05-infra.sh" ) ;;
    pg-node)  SCRIPTS=( "00-common.sh" ) ;;     # PG/Patroni installed by orchestrator
    lb)       SCRIPTS=( "00-common.sh" ) ;;     # haproxy/pgbouncer installed by orchestrator
    cli)      SCRIPTS=( "00-common.sh" ) ;;     # client app installed by orchestrator
    *)        echo "[role-bootstrap] unknown role: $ROLE"; exit 2 ;;
esac

# Always pull common.sh helper
curl -fsSL "$KS_SERVER/guest/lib/common.sh" -o "$LIB_DIR/lib/common.sh"
chmod +x "$LIB_DIR/lib/common.sh"

# Templates needed at first boot (only for infra)
if [[ "$ROLE" == "infra" ]]; then
    for tmpl in unbound-lab.conf.tmpl chrony-server.conf.tmpl; do
        curl -fsSL "$KS_SERVER/guest/templates/$tmpl" -o "$LIB_DIR/templates/$tmpl"
    done
fi

# Pull and execute role scripts
for s in "${SCRIPTS[@]}"; do
    curl -fsSL "$KS_SERVER/guest/roles/$s" -o "$LIB_DIR/roles/$s"
    chmod +x "$LIB_DIR/roles/$s"
    echo "[role-bootstrap] running $s install"
    "$LIB_DIR/roles/$s" install
done

touch "$MARK"
echo "[role-bootstrap] $(date -Is) done"
