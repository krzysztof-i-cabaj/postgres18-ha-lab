#!/usr/bin/env bash
# ==============================================================================
# Tytul:        00-common.sh
# Opis:         Wspolne ustawienia dla VMek nie-infra: DNS klient -> infra,
#               chrony klient -> infra, /etc/hosts, modprobe softdog (dla
#               PG nodes), repo PGDG (lazy — wlasciwy install w 20-postgresql).
# Description [EN]: Common settings for non-infra VMs: DNS client -> infra,
#               chrony client -> infra, /etc/hosts, modprobe softdog (for
#               PG nodes), PGDG repo (lazy — actual install in 20-postgresql).
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# <repo>:       <repo>
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - Rocky 9.x, root, infra DNS+NTP zywe na 192.168.56.10
# Requirements [EN]: - Rocky 9.x, root, infra DNS+NTP up at 192.168.56.10
#
# Uzycie [PL]:       /usr/local/lib/postgres18-ha-lab/roles/00-common.sh install|verify
# Usage [EN]:        /usr/local/lib/postgres18-ha-lab/roles/00-common.sh install|verify
# ==============================================================================

set -euo pipefail
source /usr/local/lib/postgres18-ha-lab/lib/common.sh

ROLE=$(lab_role)
LOG=/var/log/postgres18-ha-lab/00-common.log
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

INFRA_IP=$(lab_infra_ip)
DOMAIN=$(lab_domain)
LIB_DIR=/usr/local/lib/postgres18-ha-lab

install_packages() {
    log_step "Installing baseline tooling (bind-utils, jq, NetworkManager)"
    dnf install -y bind-utils jq curl
}

configure_dns() {
    log_step "Pointing DNS at infra ($INFRA_IP)"
    # Find the primary connection (NetworkManager)
    local conn
    conn=$(nmcli -g NAME,DEVICE c show --active | grep ':enp0s3' | head -1 | cut -d: -f1)
    if [[ -z "$conn" ]]; then
        log_warn "no active NetworkManager connection on enp0s3, falling back to /etc/resolv.conf"
        chattr -i /etc/resolv.conf 2>/dev/null || true
        cat > /etc/resolv.conf <<EOF
search ${DOMAIN}
nameserver ${INFRA_IP}
EOF
        return
    fi
    nmcli connection modify "$conn" \
        ipv4.dns "$INFRA_IP" \
        ipv4.ignore-auto-dns yes \
        ipv4.dns-search "$DOMAIN"
    nmcli connection up "$conn" >/dev/null
}

configure_hosts() {
    log_step "Writing /etc/hosts (fallback if DNS fails)"
    cat > /etc/hosts.lab <<EOF
127.0.0.1   localhost localhost.localdomain
::1         localhost localhost.localdomain
$INFRA_IP   infra.$DOMAIN infra
192.168.56.11 pg1.$DOMAIN pg1
192.168.56.12 pg2.$DOMAIN pg2
192.168.56.13 pg3.$DOMAIN pg3
192.168.56.20 lb.$DOMAIN lb db.$DOMAIN db
192.168.56.30 cli.$DOMAIN cli
EOF
    cp /etc/hosts.lab /etc/hosts
}

configure_chrony() {
    log_step "Configuring chrony as client of $INFRA_IP"
    render_template "$LIB_DIR/templates/chrony-client.conf.tmpl" \
        /etc/chrony.conf "INFRA_IP=$INFRA_IP"
    systemctl enable --now chronyd
    systemctl restart chronyd
}

configure_softdog() {
    if [[ "$ROLE" != "pg-node" ]]; then
        return
    fi
    log_step "Loading softdog kernel module (Patroni watchdog)"
    echo softdog > /etc/modules-load.d/softdog.conf
    modprobe softdog || log_warn "modprobe softdog failed; watchdog mode will need to be 'off'"
    if [[ -e /dev/watchdog ]]; then
        chown root:root /dev/watchdog
        chmod 0660 /dev/watchdog
    fi
}

verify() {
    log_step "Verifying common setup"
    dig +short pg1."$DOMAIN" | grep -q '^192\.168\.56\.11$' || { log_err "DNS via infra not working"; return 1; }
    chronyc sources -v | grep -qE '\^?\*' || log_warn "chrony has no sync yet (transient)"
    if [[ "$ROLE" == "pg-node" ]]; then
        [[ -e /dev/watchdog ]] || log_warn "no /dev/watchdog (Patroni watchdog mode must be 'off')"
    fi
    log_ok "common setup OK on $(lab_hostname)"
}

cmd_install() {
    require_root
    install_packages
    configure_dns
    configure_hosts
    configure_chrony
    configure_softdog
    sleep 2
    verify
}

case "${1:-install}" in
    install) cmd_install ;;
    verify)  verify ;;
    *) echo "Usage: $0 {install|verify}"; exit 2 ;;
esac
