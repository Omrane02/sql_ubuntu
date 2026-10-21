#!/usr/bin/env bash
#Ce fichier installe et configure PostgreSQL pour Novabank

set -euo pipefail

log() { echo -e "\n==> $*"; }


#root
if [[ $EUID -ne 0 ]]; then
    echo "Erreur: lance le script avec sudo." >&2
    exit 1
fi

#paquets
log "Mise a jur de la liste des paquets"
apt-get update -q

log "Installation de PostgreSQL, du client et du pare-feu"
apt-get install -y postgresql postgresql-client ufw

#cluster
PG_VERSION=$(pg_lsclusters --no-header | awk 'NR==1 {print $1}')
PG_PORT=$(pg_lsclusters --no-header | awk 'NR==1 {print $3}')
CONF_DIR="/etc/postgresql/${PG_VERSION}/main"
log "Cluster détecté : version ${PG_VERSION}, port ${PG_PORT}"

#conf.d réglages
log "Ecriture des reglages Novabank dans ${CONF_DIR}/conf.d/"
mkdir -p "${CONF_DIR}/conf.d"
cat > "${CONF_DIR}/conf.d/novabank.conf" <<'EOF'
# Réglages NovaBank (lus en plus de postgresql.conf)
listen_addresses     = 'localhost,192.168.56.10'
password_encryption  = 'scram-sha-256'
log_connections      = on
log_disconnections   = on
log_statement        = 'ddl'
EOF
chown postgres:postgres "${CONF_DIR}/conf.d/novabank.conf"

#pg_hba.conf : qui peut se connecter
HBA="${CONF_DIR}/pg_hba.conf"
if [[ ! -f "${HBA}.orig" ]]; then
    log "Sauvegarde du pg_hba.conf d'origine"
    cp "${HBA}" "${HBA}.orig"
fi

log "Écriture des règles de connexion dans ${HBA}"
cat > "${HBA}" <<'EOF'
# TYPE  DATABASE  USER                               ADDRESS           METHOD
# (1) administrateur local, par le socket, identifié par son compte Linux
local   all       postgres                                             peer
# (2) propriétaire + application : depuis la VM seulement
local   bankdb    bank_owner,app_user                                  scram-sha-256
host    bankdb    bank_owner,app_user                127.0.0.1/32      scram-sha-256
host    bankdb    bank_owner,app_user                ::1/128           scram-sha-256
# (3) analystes, support, auditeurs : depuis le réseau d'administration
host    bankdb    +g_analyst,+g_support,+g_auditor   192.168.56.0/24   scram-sha-256
# (4) tout le reste est refusé
local   all       all                                                  reject
host    all       all                                0.0.0.0/0         reject
host    all       all                                ::/0              reject
EOF
chown postgres:postgres "${HBA}"
chmod 640 "${HBA}"

# listen_addresses a le contexte "postmaster" : il faut un restart
log "Redémarrage de PostgreSQL"
systemctl restart postgresql

#parefeu
log "Configuration du pare-feu"
ufw allow OpenSSH
ufw allow from 192.168.56.0/24 to any port "${PG_PORT}" proto tcp
ufw --force enable

#verifs
log "État du cluster"
pg_lsclusters
log "État du pare-feu"
ufw status verbose

log "Installation terminée."
