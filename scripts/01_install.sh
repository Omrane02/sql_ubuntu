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

#restart
log "Redemarrage de PostgreSQL"
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
