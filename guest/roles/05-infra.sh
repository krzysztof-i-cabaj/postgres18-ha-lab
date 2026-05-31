#!/usr/bin/env bash
# ==============================================================================
# Tytul:        05-infra.sh
# Opis:         Rola infra: Unbound (autorytatywny dla lab.test, recursive dla
#               reszty) + chronyd (NTP server dla labowych klientow).
#               Pierwsza VMka — pozostale czekaja na DNS.
# Description [EN]: Role infra: Unbound (authoritative for lab.test, recursive
#               for everything else) + chronyd (NTP server for lab clients).
#               First VM — every other VM waits for its DNS.
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# <repo>:       <repo>
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - Rocky 9.x, root, dnf, firewalld, network-online
# Requirements [EN]: - Rocky 9.x, root, dnf, firewalld, network-online
#
# Uzycie [PL]:       /usr/local/lib/postgres18-ha-lab/roles/05-infra.sh install|verify
# Usage [EN]:        /usr/local/lib/postgres18-ha-lab/roles/05-infra.sh install|verify
# ==============================================================================

set -euo pipefail
source /usr/local/lib/postgres18-ha-lab/lib/common.sh

ROLE=infra
LOG=/var/log/postgres18-ha-lab/${ROLE}.log
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

DOMAIN=$(lab_domain)
LIB_DIR=/usr/local/lib/postgres18-ha-lab

install_packages() {
    log_step "Installing unbound + chrony"
    dnf install -y unbound chrony bind-utils
}

configure_unbound() {
    log_step "Writing Unbound config (authoritative for $DOMAIN)"
    # EL9/Rocky: glowny unbound.conf dolacza /etc/unbound/conf.d/*.conf (NIE unbound.conf.d/,
    # ktore jest konwencja Debiana). Zapis w zlym katalogu = config sie nie laduje
    # (brak strefy lab.test, brak interface 0.0.0.0 -> nasluch tylko na 127.0.0.1).
    # EL9/Rocky includes /etc/unbound/conf.d/*.conf (not Debian-style unbound.conf.d/).
    install -d -m 0755 /etc/unbound/conf.d
    render_template "$LIB_DIR/templates/unbound-lab.conf.tmpl" \
        /etc/unbound/conf.d/lab.conf "DOMAIN=$DOMAIN"
}

configure_chrony() {
    log_step "Writing chrony server config"
    install -m 0644 "$LIB_DIR/templates/chrony-server.conf.tmpl" /etc/chrony.conf
}

configure_firewall() {
    log_step "Opening DNS (53) + NTP (123) in firewalld"
    systemctl enable --now firewalld
    firewall-cmd --permanent --add-port=53/udp
    firewall-cmd --permanent --add-port=53/tcp
    firewall-cmd --permanent --add-port=123/udp
    firewall-cmd --reload
}

enable_service() {
    log_step "Enabling unbound + chronyd"
    systemctl enable --now unbound
    systemctl restart chronyd

    # Replace stub /etc/resolv.conf so this VM uses itself for DNS
    log_step "Pointing /etc/resolv.conf at 127.0.0.1"
    chattr -i /etc/resolv.conf 2>/dev/null || true
    cat > /etc/resolv.conf <<EOF
search ${DOMAIN}
nameserver 127.0.0.1
EOF
}

verify() {
    log_step "Verifying"
    dig @127.0.0.1 pg1."$DOMAIN" +short | grep -q '^192\.168\.56\.11$' || { log_err "forward A lookup failed"; return 1; }
    dig @127.0.0.1 -x 192.168.56.12 +short | grep -q '^pg2\.'"$DOMAIN"'\.$' || { log_err "reverse PTR failed"; return 1; }
    dig @127.0.0.1 db."$DOMAIN" +short | grep -q '^192\.168\.56\.20$' || { log_err "CNAME db.$DOMAIN failed"; return 1; }
    chronyc tracking | grep -q 'Stratum' || { log_err "chrony not running"; return 1; }
    ss -lntu | grep -qE ':53\b' || { log_err "port 53 not listening"; return 1; }
    ss -lntu | grep -qE ':123\b' || { log_err "port 123 not listening"; return 1; }
    log_ok "infra DNS+NTP healthy"
}

cmd_install() {
    require_root
    install_packages
    configure_unbound
    configure_chrony
    configure_firewall
    enable_service
    sleep 2
    verify
}

case "${1:-install}" in
    install) cmd_install ;;
    verify)  verify ;;
    *) echo "Usage: $0 {install|verify}"; exit 2 ;;
esac
