#!/usr/bin/env bash
# ==============================================================================
# Tytul:        20-postgresql.sh
# Opis:         Rola postgresql (pg1/pg2/pg3): repo PGDG, install pg18-server,
#               kreacja /var/lib/pgsql/18/data (pusty — Patroni zrobi initdb),
#               WYLACZONA postgresql-18.service (Patroni nia zarzadza).
# Description [EN]: Role postgresql (pg1/pg2/pg3): PGDG repo, install
#               pg18-server, create /var/lib/pgsql/18/data (empty — Patroni
#               will initdb), DISABLED postgresql-18.service (Patroni manages it).
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# <repo>:       <repo>
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - Rocky 9.x, root, dnf, internet (PGDG repo)
# Requirements [EN]: - Rocky 9.x, root, dnf, internet (PGDG repo)
#
# Uzycie [PL]:       /usr/local/lib/postgres18-ha-lab/roles/20-postgresql.sh install|verify
# Usage [EN]:        /usr/local/lib/postgres18-ha-lab/roles/20-postgresql.sh install|verify
# ==============================================================================

set -euo pipefail
source /usr/local/lib/postgres18-ha-lab/lib/common.sh

ROLE=postgresql
LOG=/var/log/postgres18-ha-lab/${ROLE}.log
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

install_packages() {
    log_step "Adding PGDG repo + installing PostgreSQL 18"
    dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
    dnf -qy module disable postgresql || true
    dnf install -y postgresql18-server postgresql18-contrib
}

configure() {
    log_step "Preparing /var/lib/pgsql/18/data (Patroni will initdb)"
    install -d -m 0700 -o postgres -g postgres /var/lib/pgsql/18/data

    # Patroni manages PG, so disable the OS service
    systemctl disable --now postgresql-18 2>/dev/null || true
}

configure_firewall() {
    log_step "Opening 5432/tcp"
    firewall-cmd --permanent --add-port=5432/tcp
    firewall-cmd --permanent --add-port=8008/tcp   # Patroni REST
    firewall-cmd --reload
}

verify() {
    log_step "Verifying"
    /usr/pgsql-18/bin/postgres --version | grep -q 'postgres (PostgreSQL) 18'
    log_ok "PG 18 binaries available"
}

cmd_install() {
    require_root
    install_packages
    configure
    configure_firewall
    verify
}

case "${1:-install}" in
    install) cmd_install ;;
    verify)  verify ;;
    *) echo "Usage: $0 {install|verify}"; exit 2 ;;
esac
