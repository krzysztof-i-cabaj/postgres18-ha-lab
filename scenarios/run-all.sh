#!/usr/bin/env bash
# Tytul: run-all.sh — uruchom wszystkie scenariusze, wynik zbiorczy
# Description [EN]: run all scenarios, aggregate result
#
# Miedzy scenariuszami czekamy az klaster sie ustabilizuje (lider + 3/3 + zapis) --
# scenariusze destrukcyjne (02/03/05/09/12/13) zostawiaja klaster w trakcie odbudowy,
# a kolejny test startujacy na nieustabilizowanym klastrze falszywie pada (np. 04 bez
# sync_standby, 12 z pustym liderem, 13 gdy HAProxy nie ma jeszcze backendu). To
# odwzorowuje tempo recznego przebiegu agentowego ("czekaj az 3/3 po kazdym tescie").
# Between scenarios we wait until the cluster settles (leader + 3/3 + writable) --
# destructive scenarios leave it mid-recovery, and the next test starting on an
# unsettled cluster fails spuriously; this mirrors the paced manual agentic run.
set -uo pipefail
SCENARIO_DIR=$(dirname "$(readlink -f "$0")")

PG_NODES=("pg1.lab.test" "pg2.lab.test" "pg3.lab.test")
LB_HOST="lb.lab.test"
SETTLE_TRIES=90   # x2s = do 180s na ciezka odbudowe (pg_rewind po kaskadzie)

_cluster_json() {
    local n
    for n in "${PG_NODES[@]}"; do
        curl -fsS --max-time 3 "http://$n:8008/cluster" 2>/dev/null && return 0
    done
    return 1
}

# settle -- czekaj az klaster bedzie zdrowy (lider widoczny, 3 czlonkow, zapis przez
# HAProxy dziala). Zwraca 0 zawsze (po timeoutcie ostrzega i pozwala isc dalej, by
# nie blokowac calej suity). / wait until the cluster is healthy; never blocks the suite.
settle() {
    local i j leader members writable
    for ((i=0; i<SETTLE_TRIES; i++)); do
        if ! j=$(_cluster_json); then sleep 2; continue; fi
        leader=$(jq -r '.members[]|select(.role=="leader").name' <<<"$j" 2>/dev/null)
        members=$(jq -r '.members|length' <<<"$j" 2>/dev/null)
        writable=$(PGPASSWORD=lab PGCONNECT_TIMEOUT=5 timeout 8 \
            psql -h "$LB_HOST" -p 5000 -U lab -d labdb -At -c "SELECT 1" 2>/dev/null | head -n1)
        if [[ -n "$leader" && "$leader" != "null" && "$members" == "3" && "$writable" == "1" ]]; then
            echo "  [settle] healthy: leader=$leader, members=3, writable -> proceeding"
            return 0
        fi
        sleep 2
    done
    echo "  [settle] WARN: not fully healthy (leader=${leader:-?} members=${members:-?}" \
         "writable=${writable:-?}) -- proceeding anyway"
    return 0
}

PASS=0
FAIL=0
FAILED=()

for s in "$SCENARIO_DIR"/[0-9][0-9]-*.sh; do
    name=$(basename "$s" .sh)
    echo "[settle] stabilising cluster before $name ..."
    settle
    if bash "$s"; then
        ((PASS++))
    else
        ((FAIL++))
        FAILED+=("$name")
    fi
    echo
done

echo "================================================================"
echo " SUITE SUMMARY"
echo "  PASSED: $PASS"
echo "  FAILED: $FAIL"
if (( FAIL > 0 )); then
    echo "  Failed scenarios: ${FAILED[*]}"
fi
echo "================================================================"
exit "$FAIL"
