#!/usr/bin/env bash
# ==============================================================================
# Tytul:        30-patroni.sh
# Opis:         Rola patroni (pg1/pg2/pg3): pip install patroni[etcd3] +
#               psycopg2-binary, render /etc/patroni/patroni.yml,
#               systemd unit, enable patroni.service. Konfig wczytuje hasla z
#               envow PATRONI_REPL_PWD, PATRONI_SUPER_PWD, PATRONI_REWIND_PWD,
#               PATRONI_APP_PASSWORD wstawionych przez orchestrator.
# Description [EN]: Role patroni (pg1/pg2/pg3): pip install patroni[etcd3] +
#               psycopg2-binary, render /etc/patroni/patroni.yml, systemd unit,
#               enable patroni.service. Reads passwords from env injected by
#               orchestrator.
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# <repo>:       <repo>
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - Rocky 9.x, role pg-node, postgres18-server, etcd, root
#                    - envy: PATRONI_REPL_PWD/SUPER_PWD/REWIND_PWD/APP_PASSWORD
#                            WATCHDOG_MODE
# Requirements [EN]: - Rocky 9.x, role pg-node, postgres18-server, etcd, root
#                    - env vars: PATRONI_REPL_PWD/SUPER_PWD/REWIND_PWD/APP_PASSWORD
#                                WATCHDOG_MODE
#
# Uzycie [PL]:       PATRONI_REPL_PWD=... PATRONI_SUPER_PWD=... PATRONI_REWIND_PWD=... \
#                    PATRONI_APP_PASSWORD=... WATCHDOG_MODE=automatic \
#                    /usr/local/lib/postgres18-ha-lab/roles/30-patroni.sh install
# Usage [EN]:        same as above
# ==============================================================================

set -euo pipefail
source /usr/local/lib/postgres18-ha-lab/lib/common.sh

ROLE=patroni
LOG=/var/log/postgres18-ha-lab/${ROLE}.log
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

LIB_DIR=/usr/local/lib/postgres18-ha-lab
SCOPE=${PATRONI_SCOPE:-pg-ha-lab}
HOSTNAME_SHORT=$(hostname -s)
IP=$(lab_ip)
WATCHDOG_MODE=${WATCHDOG_MODE:-automatic}

install_packages() {
    log_step "Installing python3-pip + Patroni"
    # psycopg2-binary to gotowy wheel (wkompilowany libpq) — NIE wymaga pg headers,
    # wiec postgresql18-devel jest zbedny; do tego ciagnie perl-IPC-Run, ktorego nie
    # ma w BaseOS/AppStream/PGDG (jest w EPEL) -> "nothing provides perl(IPC::Run)".
    # psycopg2-binary is a prebuilt wheel (bundled libpq) — needs no pg headers, so
    # postgresql18-devel is unnecessary; it also pulls perl-IPC-Run, absent from
    # BaseOS/AppStream/PGDG (it's in EPEL) -> "nothing provides perl(IPC::Run)".
    dnf install -y python3-pip python3-devel gcc
    pip3 install --quiet --upgrade 'patroni[etcd3]>=4.1' 'psycopg2-binary>=2.9' 'python-etcd>=0.4'
}

configure() {
    log_step "Rendering /etc/patroni/patroni.yml"
    install -d -m 0755 /etc/patroni
    : "${PATRONI_REPL_PWD:?missing env}"
    : "${PATRONI_SUPER_PWD:?missing env}"
    : "${PATRONI_REWIND_PWD:?missing env}"
    : "${PATRONI_APP_PASSWORD:?missing env}"
    render_template "$LIB_DIR/templates/patroni.yml.tmpl" /etc/patroni/patroni.yml \
        "SCOPE=$SCOPE" "HOSTNAME=$HOSTNAME_SHORT" "IP=$IP" \
        "REPL_PWD=$PATRONI_REPL_PWD" "SUPER_PWD=$PATRONI_SUPER_PWD" "REWIND_PWD=$PATRONI_REWIND_PWD" \
        "APP_USER=lab" "APP_PASSWORD=$PATRONI_APP_PASSWORD" \
        "WATCHDOG_MODE=$WATCHDOG_MODE"
    chown -R postgres:postgres /etc/patroni
    chmod 600 /etc/patroni/patroni.yml
}

install_unit() {
    log_step "Installing patroni.service"
    cat > /etc/systemd/system/patroni.service <<'EOF'
[Unit]
Description=Patroni — PostgreSQL HA
After=network-online.target etcd.service
Wants=network-online.target

[Service]
Type=simple
User=postgres
Group=postgres
ExecStart=/usr/local/bin/patroni /etc/patroni/patroni.yml
KillMode=process
KillSignal=SIGINT
Restart=on-failure
TimeoutSec=30

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now patroni
}

verify() {
    log_step "Verifying Patroni"
    retry 18 5 curl -fsS "http://$IP:8008/health" -o /dev/null
    log_ok "Patroni REST up at $IP:8008"
}

cmd_install() {
    require_root
    install_packages
    configure
    install_unit
    verify
}

case "${1:-install}" in
    install) cmd_install ;;
    verify)  verify ;;
    *) echo "Usage: $0 {install|verify}"; exit 2 ;;
esac
