#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SQL_DIR="${ROOT}/sql"
DB="bankdb"
OWNER="bank_owner"
PROJECT_ROLES="app_user auditor1 support1 analyst1 g_app g_auditor g_support g_analyst bank_owner"
LOGIN_ROLES="analyst1 support1 auditor1 app_user"

log() { echo -e "\n==> $*"; }

if [[ $EUID -eq 0 ]]; then
    echo "Erreur : lance ce script SANS sudo (il l'utilise lui-même)." >&2
    exit 1
fi

echo "ATTENTION : la base ${DB} et tous les rôles du projet vont être SUPPRIMÉS."
echo "Pense à lancer scripts/02_backup_restore.sh avant si tu veux garder les données."
read -r -p "Tape OUI pour continuer : " answer
if [[ "${answer}" != "OUI" ]]; then
    echo "Annulé, rien n'a été supprimé."
    exit 0
fi

START=${SECONDS}

log "Suppression de la base ${DB}"
sudo -u postgres psql -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS ${DB} WITH (FORCE);"

log "Suppression des rôles du projet"
for role in ${PROJECT_ROLES}; do
    sudo -u postgres psql -v ON_ERROR_STOP=1 -q -c "DROP ROLE IF EXISTS ${role};"
done

log "Rejeu des fichiers SQL dans l'ordre"
for file in "${SQL_DIR}"/[0-9][0-9]_*.sql; do
    name="$(basename "${file}")"

    case "${name}" in
        00_*|04_*)
            log "${name}  (postgres)"
            sudo -u postgres psql -v ON_ERROR_STOP=1 < "${file}"
            ;;
        *)
            log "${name}  (${OWNER})"
            psql -h 127.0.0.1 -U "${OWNER}" -d "${DB}" -v ON_ERROR_STOP=1 < "${file}"
            ;;
    esac

    if [[ "${name}" == 00_* ]]; then
        log "Nouveau mot de passe pour ${OWNER}"
        sudo -u postgres psql -c "\password ${OWNER}"
        read -r -s -p "Retape-le pour les fichiers suivants : " PGPASSWORD
        echo
        export PGPASSWORD
    fi
done

unset PGPASSWORD

log "Mots de passe des comptes (analyste, support, auditeur, appli)"
read -r -p "Les définir maintenant ? (o/N) : " setpw
if [[ "${setpw}" == "o" ]]; then
    for role in ${LOGIN_ROLES}; do
        echo "--- ${role}"
        sudo -u postgres psql -c "\password ${role}"
    done
fi

log "Reconstruction terminée en $(( SECONDS - START )) secondes."
