#!/usr/bin/env bash
# ==============================================================================
# Tytul:        60-client.sh
# Opis:         Rola cli (test client + orchestrator host): instalacja python3,
#               psycopg, rich, click, pgha-client (z lokalnego /usr/local/lib/...).
# Description [EN]: Role cli (test client + orchestrator host): install python3,
#               psycopg, rich, click, pgha-client (from local /usr/local/lib/...).
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# <repo>:       <repo>
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - Rocky 9.x, role cli, root, dnf, internet (pip)
# Requirements [EN]: - Rocky 9.x, role cli, root, dnf, internet (pip)
#
# Uzycie [PL]:       /usr/local/lib/postgres18-ha-lab/roles/60-client.sh install|verify
# Usage [EN]:        /usr/local/lib/postgres18-ha-lab/roles/60-client.sh install|verify
# ==============================================================================

set -euo pipefail
source /usr/local/lib/postgres18-ha-lab/lib/common.sh

ROLE=client
LOG=/var/log/postgres18-ha-lab/${ROLE}.log
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

LIB_DIR=/usr/local/lib/postgres18-ha-lab
CLIENT_DIR=$LIB_DIR/client-app

install_packages() {
    log_step "Installing python tooling and PostgreSQL 18 client"
    if ! rpm -q pgdg-redhat-repo >/dev/null 2>&1; then
        dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
    fi
    dnf -qy module disable postgresql || true
    # pgha-client wymaga Pythona >=3.11; domyslny python3 w Rocky 9.8 to 3.9, ktory
    # pip ODRZUCA przy editable install (requires-python). Instalujemy python3.11
    # jawnie. / pgha-client needs Python >=3.11; Rocky 9.8 default python3 is 3.9,
    # which pip REJECTS for the editable install -- install python3.11 explicitly.
    dnf install -y python3.11 python3.11-pip postgresql18
}

install_app() {
    log_step "Installing pgha-client (editable from $CLIENT_DIR, Python 3.11)"
    if [[ -d "$CLIENT_DIR" && -f "$CLIENT_DIR/pyproject.toml" ]]; then
        # python3.11 -m pip: pewniejsze niz pip3.11 (zawsze trafia do 3.11). Konsolowy
        # skrypt `pgha-client` laduje w /usr/local/bin (na PATH). / use python3.11 -m pip
        # so the console script lands in /usr/local/bin (on PATH).
        python3.11 -m pip install --quiet --upgrade -e "$CLIENT_DIR"
    else
        log_warn "client-app not present at $CLIENT_DIR; will be installed by orchestrator"
    fi
}

verify() {
    log_step "Verifying"
    /usr/pgsql-18/bin/psql --version | grep -qE 'psql.*18'
    python3.11 -c 'import pgha_client' && command -v pgha-client >/dev/null \
        && log_ok "pgha-client (Python 3.11) ready" \
        || log_warn "pgha-client not importable -- check 'python3.11 -m pip install -e $CLIENT_DIR'"
    log_ok "PG client + python tooling ready"
}

cmd_install() {
    require_root
    install_packages
    install_app
    verify
}

case "${1:-install}" in
    install) cmd_install ;;
    verify)  verify ;;
    *) echo "Usage: $0 {install|verify}"; exit 2 ;;
esac
