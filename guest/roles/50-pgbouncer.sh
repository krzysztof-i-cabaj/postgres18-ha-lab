#!/usr/bin/env bash
# ==============================================================================
# Tytul:        50-pgbouncer.sh
# Opis:         Rola pgbouncer na VMce 'lb': transaction pooling,
#               listen :6432, backend 127.0.0.1:5000 (HAProxy primary).
#               Userlist md5 hashes: APP_USER + postgres.
# Description [EN]: Role pgbouncer on the 'lb' VM: transaction pooling,
#               listen :6432, backend 127.0.0.1:5000 (HAProxy primary).
#               Userlist md5 hashes: APP_USER + postgres.
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# <repo>:       <repo>
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - Rocky 9.x, role lb, dnf, PGDG repo (zalozony w 20-postgresql)
#                      LUB AppStream pgbouncer; envy APP_PWD/SUPER_PWD
# Requirements [EN]: - Rocky 9.x, role lb, dnf, PGDG repo (assumed installed)
#                      OR AppStream pgbouncer; env APP_PWD/SUPER_PWD
#
# Uzycie [PL]:       APP_PWD=lab SUPER_PWD=... /usr/local/.../50-pgbouncer.sh install
# Usage [EN]:        APP_PWD=lab SUPER_PWD=... /usr/local/.../50-pgbouncer.sh install
# ==============================================================================

set -euo pipefail
source /usr/local/lib/postgres18-ha-lab/lib/common.sh

ROLE=pgbouncer
LOG=/var/log/postgres18-ha-lab/${ROLE}.log
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

LIB_DIR=/usr/local/lib/postgres18-ha-lab
APP_USER=${APP_USER:-lab}
APP_DB=${APP_DB:-labdb}

install_packages() {
    log_step "Installing pgbouncer"
    # PGDG repo expected from 20-postgresql.sh; if we are on lb only, install repo too
    if ! rpm -q pgdg-redhat-repo >/dev/null 2>&1; then
        dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
    fi
    dnf install -y pgbouncer
}

md5_pg() {
    # PostgreSQL md5 hash format: 'md5' + md5(password + username)
    local pwd=$1 user=$2
    printf "md5%s" "$(printf '%s%s' "$pwd" "$user" | md5sum | cut -d' ' -f1)"
}

configure() {
    log_step "Rendering /etc/pgbouncer/pgbouncer.ini and userlist.txt"
    : "${APP_PWD:?missing env}"
    : "${SUPER_PWD:?missing env}"

    install -d -m 0750 -o pgbouncer -g pgbouncer /etc/pgbouncer
    render_template "$LIB_DIR/templates/pgbouncer.ini.tmpl" /etc/pgbouncer/pgbouncer.ini \
        "APP_DB=$APP_DB"

    local app_md5 super_md5
    app_md5=$(md5_pg "$APP_PWD" "$APP_USER")
    super_md5=$(md5_pg "$SUPER_PWD" "postgres")

    render_template "$LIB_DIR/templates/userlist.txt.tmpl" /etc/pgbouncer/userlist.txt \
        "APP_USER=$APP_USER" "APP_PWD_MD5=$app_md5" "SUPER_PWD_MD5=$super_md5"
    chmod 0600 /etc/pgbouncer/userlist.txt
    chown pgbouncer:pgbouncer /etc/pgbouncer/userlist.txt /etc/pgbouncer/pgbouncer.ini
}

enable_service() {
    log_step "Enabling pgbouncer"
    systemctl enable --now pgbouncer
}

verify() {
    log_step "Verifying pgbouncer"
    retry 6 3 ss -lnt | grep -qE ':6432\b'
    log_ok "pgbouncer listening on :6432"
}

cmd_install() {
    require_root
    install_packages
    configure
    enable_service
    verify
}

case "${1:-install}" in
    install) cmd_install ;;
    verify)  verify ;;
    *) echo "Usage: $0 {install|verify}"; exit 2 ;;
esac
