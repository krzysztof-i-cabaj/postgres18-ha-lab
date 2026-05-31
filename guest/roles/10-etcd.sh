#!/usr/bin/env bash
# ==============================================================================
# Tytul:        10-etcd.sh
# Opis:         Rola etcd (uruchamiana na pg1/pg2/pg3): instalacja etcd 3.5+,
#               render konfiguracji, enable etcd.service, weryfikacja health.
# Description [EN]: Role etcd (runs on pg1/pg2/pg3): install etcd 3.5+, render
#               config, enable etcd.service, verify health.
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# <repo>:       <repo>
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - Rocky 9.x, root, dnf, role pg-node, dzialajacy DNS
# Requirements [EN]: - Rocky 9.x, root, dnf, role pg-node, working DNS
#
# Uzycie [PL]:       /usr/local/lib/postgres18-ha-lab/roles/10-etcd.sh install|verify
# Usage [EN]:        /usr/local/lib/postgres18-ha-lab/roles/10-etcd.sh install|verify
# ==============================================================================

set -euo pipefail
source /usr/local/lib/postgres18-ha-lab/lib/common.sh

ROLE=etcd
LOG=/var/log/postgres18-ha-lab/${ROLE}.log
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

LIB_DIR=/usr/local/lib/postgres18-ha-lab
HOSTNAME_SHORT=$(hostname -s)
IP=$(lab_ip)

# etcd NIE jest w repozytoriach Rocky/RHEL 9 (usuniety z EL8+, brak tez w EPEL),
# wiec instalujemy oficjalna binarke z GitHub releases. Pelna wersja patch
# (config trzyma tylko '3.5'); mozna nadpisac przez ETCD_VERSION=... w env.
# etcd is NOT in Rocky/RHEL 9 repos (dropped in EL8+, not in EPEL either), so we
# install the official GitHub-release binary. Full patch version (config keeps
# only '3.5'); override with ETCD_VERSION=... in the environment.
ETCD_VERSION="${ETCD_VERSION:-3.5.21}"
ETCD_ARCH=linux-amd64

install_packages() {
    log_step "Installing etcd ${ETCD_VERSION} (binarka z GitHub — brak w repo EL9)"
    if command -v /usr/local/bin/etcd >/dev/null 2>&1 \
        && /usr/local/bin/etcd --version 2>/dev/null | grep -q "etcd Version: ${ETCD_VERSION}"; then
        log_ok "etcd ${ETCD_VERSION} already installed"
    else
        local dir="etcd-v${ETCD_VERSION}-${ETCD_ARCH}"
        local tgz="/tmp/${dir}.tar.gz"
        local url="https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/${dir}.tar.gz"
        # Rocky 9 minimal nie ma tar/gzip (nie sa w @core) — doinstaluj przed rozpakowaniem.
        # Rocky 9 minimal ships no tar/gzip (not in @core) — install before extracting.
        command -v tar >/dev/null 2>&1 || dnf install -y tar gzip
        retry 3 5 curl -fsSL "$url" -o "$tgz"
        tar -xzf "$tgz" -C /tmp
        install -m 0755 "/tmp/${dir}/etcd"    /usr/local/bin/etcd
        install -m 0755 "/tmp/${dir}/etcdctl" /usr/local/bin/etcdctl
        rm -rf "$tgz" "/tmp/${dir}"
    fi
    # Systemowy user etcd (pakiet RPM by go utworzyl; przy binarce robimy sami).
    # System etcd user (the RPM would create it; with the binary we do it ourselves).
    id etcd &>/dev/null || useradd --system --home-dir /var/lib/etcd --shell /sbin/nologin etcd
}

configure() {
    log_step "Rendering /etc/etcd/etcd.conf.yml"
    install -d -m 0755 /etc/etcd
    render_template "$LIB_DIR/templates/etcd.conf.tmpl" /etc/etcd/etcd.conf.yml \
        "HOSTNAME=$HOSTNAME_SHORT" "IP=$IP"

    install -d -m 0700 -o etcd -g etcd /var/lib/etcd

    # Pelny unit etcd.service — binarka z GitHub nie dostarcza wlasnego (inaczej
    # niz RPM), wiec tworzymy go sami zamiast override.conf na nieistniejacym
    # serwisie. Type=notify: etcd zglasza gotowosc przez sd_notify.
    # Full etcd.service unit — the GitHub binary ships no service (unlike the
    # RPM), so we create it instead of an override.conf on a non-existent unit.
    log_step "Installing /etc/systemd/system/etcd.service"
    cat > /etc/systemd/system/etcd.service <<'EOF'
[Unit]
Description=etcd key-value store
Documentation=https://github.com/etcd-io/etcd
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=etcd
ExecStart=/usr/local/bin/etcd --config-file=/etc/etcd/etcd.conf.yml
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

configure_firewall() {
    log_step "Opening etcd ports 2379/2380"
    firewall-cmd --permanent --add-port=2379/tcp
    firewall-cmd --permanent --add-port=2380/tcp
    firewall-cmd --reload
}

enable_service() {
    log_step "Enabling etcd"
    systemctl enable --now etcd
    sleep 5
}

verify() {
    log_step "Verifying etcd"
    retry 12 5 /usr/local/bin/etcdctl --endpoints="http://$IP:2379" endpoint health
    log_ok "etcd healthy on $IP:2379"
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
