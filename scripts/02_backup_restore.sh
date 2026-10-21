#!/usr/bin/env bash
set -euo pipefail

DB="bankdb"
TEST_DB="bankdb_restore_test"
BACKUP_DIR="$(cd "$(dirname "$0")/.." && pwd)/backups"
FILE="${BACKUP_DIR}/bankdb_$(date +%Y%m%d_%H%M%S).dump"

COUNT_SQL="
SELECT 'customers',    count(*)::text FROM core.customers
UNION ALL SELECT 'accounts',     count(*)::text FROM core.accounts
UNION ALL SELECT 'transfers',    count(*)::text FROM core.transfers
UNION ALL SELECT 'transactions', count(*)::text FROM core.transactions
UNION ALL SELECT 'fraud_alerts', count(*)::text FROM core.fraud_alerts
UNION ALL SELECT 'audit_log',    count(*)::text FROM audit.audit_log
UNION ALL SELECT 'total_soldes', sum(balance)::text FROM core.accounts
ORDER BY 1;"

log() { echo -e "\n==> $*"; }

if [[ $EUID -eq 0 ]]; then
    echo "Erreur : lance ce script SANS sudo (il l'utilise lui-même)." >&2
    exit 1
fi

mkdir -p "${BACKUP_DIR}"

log "Sauvegarde de ${DB} au format custom"
sudo -u postgres pg_dump -Fc "${DB}" > "${FILE}"
ls -lh "${FILE}"

log "Création de la base temporaire ${TEST_DB}"
sudo -u postgres dropdb --if-exists "${TEST_DB}"
sudo -u postgres createdb -O bank_owner "${TEST_DB}"

log "Restauration dans ${TEST_DB}"
sudo -u postgres pg_restore -d "${TEST_DB}" < "${FILE}"

log "Comparaison des comptages"
SRC=$(mktemp)
DST=$(mktemp)
sudo -u postgres psql -d "${DB}"      -At -F ' | ' -c "${COUNT_SQL}" > "${SRC}"
sudo -u postgres psql -d "${TEST_DB}" -At -F ' | ' -c "${COUNT_SQL}" > "${DST}"

echo "--- ${DB} ---";      cat "${SRC}"
echo "--- ${TEST_DB} ---"; cat "${DST}"

if diff -q "${SRC}" "${DST}" > /dev/null; then
    log "OK : la sauvegarde est restaurée à l'identique"
else
    log "ERREUR : différences entre la base et sa restauration"
    diff "${SRC}" "${DST}"
    exit 1
fi

rm -f "${SRC}" "${DST}"

log "Suppression de la base temporaire"
sudo -u postgres dropdb "${TEST_DB}"

log "Sauvegarde conservée : ${FILE}"
