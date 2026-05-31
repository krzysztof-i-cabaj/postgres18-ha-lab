#!/usr/bin/env bash
# ==============================================================================
# Tytul:        40-haproxy.sh
# Opis:         Rola haproxy na VMce 'lb': :5000 primary, :5001 replicas,
#               :7000 stats UI. HTTP-check via Patroni REST API.
# Description [EN]: Role haproxy on the 'lb' VM: :5000 primary, :5001 replicas,
#               :7000 stats UI. HTTP-check via Patroni REST API.
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# <repo>:       <repo>
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - Rocky 9.x, role lb, root, dnf, AppStream haproxy
# Requirements [EN]: - Rocky 9.x, role lb, root, dnf, AppStream haproxy
#
# Uzycie [PL]:       /usr/local/lib/postgres18-ha-lab/roles/40-haproxy.sh install|verify
# Usage [EN]:        /usr/local/lib/postgres18-ha-lab/roles/40-haproxy.sh install|verify
# ==============================================================================

set -euo pipefail
source /usr/local/lib/postgres18-ha-lab/lib/common.sh

ROLE=haproxy
LOG=/var/log/postgres18-ha-lab/${ROLE}.log
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

LIB_DIR=/usr/local/lib/postgres18-ha-lab

install_packages() {
    log_step "Installing haproxy"
    dnf install -y haproxy
}

configure() {
    log_step "Writing /etc/haproxy/haproxy.cfg"
    install -m 0644 "$LIB_DIR/templates/haproxy.cfg.tmpl" /etc/haproxy/haproxy.cfg
    setsebool -P haproxy_connect_any 1 2>/dev/null || true
}

configure_firewall() {
    log_step "Opening 5000/5001/7000 in firewalld"
    firewall-cmd --permanent --add-port=5000/tcp
    firewall-cmd --permanent --add-port=5001/tcp
    firewall-cmd --permanent --add-port=7000/tcp
    firewall-cmd --permanent --add-port=6432/tcp   # PgBouncer
    firewall-cmd --reload
}

enable_service() {
    log_step "Enabling haproxy"
    systemctl enable --now haproxy
}

verify() {
    log_step "Verifying haproxy"
    retry 6 3 ss -lnt | grep -qE ':5000\b'
    retry 6 3 ss -lnt | grep -qE ':5001\b'
    retry 6 3 ss -lnt | grep -qE ':7000\b'
    log_ok "haproxy listening on 5000/5001/7000"
}

cmd_install() {
    require_root
    install_packages
    configure
    configure_firewall
    enable_service
    verify
}

case "${1:-install}" in
    install) cmd_install ;;
    verify)  verify ;;
    *) echo "Usage: $0 {install|verify}"; exit 2 ;;
esac
