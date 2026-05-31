#!/usr/bin/env bash
# ==============================================================================
# Tytul:        common.sh
# Opis:         Wspolne helpery shell dla wszystkich guest/roles/*.sh:
#               log_step, log_ok, log_warn, log_err, render_template,
#               require_root, retry, jq_or_python.
# Description [EN]: Shared shell helpers for every guest/roles/*.sh:
#               log_step, log_ok, log_warn, log_err, render_template,
#               require_root, retry, jq_or_python.
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# <repo>:       <repo>
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - bash 4+, sed, awk
# Requirements [EN]: - bash 4+, sed, awk
#
# Uzycie [PL]:       source /usr/local/lib/postgres18-ha-lab/lib/common.sh
# Usage [EN]:        source /usr/local/lib/postgres18-ha-lab/lib/common.sh
# ==============================================================================

# shellcheck shell=bash
set -euo pipefail

# --- ANSI colors -------------------------------------------------------------
if [[ -t 1 ]]; then
    C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YLW=$'\e[33m'
    C_CYAN=$'\e[36m'; C_DIM=$'\e[2m'; C_RST=$'\e[0m'
else
    C_RED=''; C_GRN=''; C_YLW=''; C_CYAN=''; C_DIM=''; C_RST=''
fi

log_step() { echo "${C_CYAN}==>${C_RST} $*"; }
log_ok()   { echo "${C_GRN}  OK${C_RST} $*"; }
log_warn() { echo "${C_YLW} WARN${C_RST} $*" >&2; }
log_err()  { echo "${C_RED} FAIL${C_RST} $*" >&2; }

# --- root check --------------------------------------------------------------
require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_err "must run as root (use sudo)"
        exit 1
    fi
}

# --- Retry: retry <attempts> <sleep> <cmd...> -------------------------------
retry() {
    local n=${1:-3}; shift
    local s=${1:-2}; shift
    local i
    for ((i=1; i<=n; i++)); do
        if "$@"; then return 0; fi
        log_warn "attempt $i/$n failed: $* (sleep ${s}s)"
        sleep "$s"
    done
    return 1
}

# --- Render template with @@VAR@@ substitution -----------------------------
# Usage: render_template <input.tmpl> <output> [VAR1=val1 VAR2=val2 ...]
render_template() {
    local input=$1
    local output=$2
    shift 2
    local content
    content=$(cat "$input")
    while [[ $# -gt 0 ]]; do
        local kv=$1; shift
        local k=${kv%%=*}
        local v=${kv#*=}
        # Use printf '%s' to avoid backslash interpretation
        content=$(printf '%s' "$content" | sed "s|@@${k}@@|${v//|/\\|}|g")
    done
    printf '%s' "$content" > "$output"
}

# --- Read /etc/postgres18-ha-lab/* values -----------------------------------
lab_role()      { cat /etc/postgres18-ha-lab/role; }
lab_hostname()  { cat /etc/postgres18-ha-lab/hostname; }
lab_ip()        { cat /etc/postgres18-ha-lab/ip; }
lab_infra_ip()  { cat /etc/postgres18-ha-lab/infra_ip; }
lab_domain()    { cat /etc/postgres18-ha-lab/domain; }
lab_ks_server() { cat /etc/postgres18-ha-lab/ks_server; }

# --- Wait helpers -----------------------------------------------------------
wait_for_tcp() {
    local host=$1 port=$2 timeout=${3:-60}
    local i
    for ((i=0; i<timeout; i++)); do
        if (echo > /dev/tcp/"$host"/"$port") 2>/dev/null; then
            return 0
        fi
        sleep 1
    done
    return 1
}

wait_for_dns() {
    local name=$1 server=${2:-127.0.0.1} timeout=${3:-60}
    local i
    for ((i=0; i<timeout; i++)); do
        if dig +short +time=2 +tries=1 "@$server" "$name" | grep -qE '^[0-9.]+$'; then
            return 0
        fi
        sleep 1
    done
    return 1
}
