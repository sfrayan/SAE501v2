#!/bin/bash
#
# install_radius.sh - Installation complète FreeRADIUS + MySQL
# Version corrigée avec configuration SQL, EAP et LOGGING DÉTAILLÉ
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FR_CONF="/etc/freeradius/3.0"

echo "──────────────────────────────────────"
echo "🚀 Installation FreeRADIUS + MySQL"
echo "──────────────────────────────────────"

# Vérifier root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ce script doit être exécuté en root (sudo)"
  exit 1
fi

# 1. Installation paquets
echo "[1/13] Installation paquets..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  freeradius \
  freeradius-mysql \
  freeradius-utils \
  mariadb-server \
  mariadb-client \
  expect \
  > /dev/null 2>&1

# 2. Démarrage MySQL
echo "[2/13] Configuration MySQL..."
systemctl enable mariadb > /dev/null 2>&1
systemctl start mariadb

# 3. Sécurisation MySQL (automated)
echo "[3/13] Sécurisation MySQL..."
mysql -u root -e "
  DELETE FROM mysql.user WHERE User='';
  DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
  DROP DATABASE IF EXISTS test;
  DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
  FLUSH PRIVILEGES;
" 2>/dev/null || true

# 4. Création base et utilisateur
echo "[4/13] Création base de données RADIUS..."
if [ -f "$PROJECT_ROOT/radius/sql/init_appuser.sql" ]; then
  mysql -u root < "$PROJECT_ROOT/radius/sql/init_appuser.sql"
else
  echo "❌ Fichier init_appuser.sql introuvable"
  exit 1
fi

# 5. Création tables
echo "[5/13] Création des tables..."
if [ -f "$PROJECT_ROOT/radius/sql/create_tables.sql" ]; then
  mysql -u root radius < "$PROJECT_ROOT/radius/sql/create_tables.sql"
else
  echo "❌ Fichier create_tables.sql introuvable"
  exit 1
fi

# 6. Configuration FreeRADIUS - clients.conf
echo "[6/13] Configuration clients RADIUS..."
if [ -f "$PROJECT_ROOT/radius/clients.conf" ]; then
  cp "$FR_CONF/clients.conf" "$FR_CONF/clients.conf.backup" 2>/dev/null || true
  cp "$PROJECT_ROOT/radius/clients.conf" "$FR_CONF/clients.conf"
  chmod 640 "$FR_CONF/clients.conf"
  chown root:freerad "$FR_CONF/clients.conf"
fi

# 7. Configuration FreeRADIUS - users
echo "[7/13] Configuration users..."
if [ -f "$PROJECT_ROOT/radius/users.txt" ]; then
  cp "$FR_CONF/users" "$FR_CONF/users.backup" 2>/dev/null || true
  cp "$PROJECT_ROOT/radius/users.txt" "$FR_CONF/users"
  chmod 640 "$FR_CONF/users"
  chown root:freerad "$FR_CONF/users"
fi

# 8. Configuration SQL module (SANS LES QUERIES DE GROUPE)
echo "[8/13] Configuration module SQL..."
cat > "$FR_CONF/mods-available/sql" <<'EOF'
sql {
    driver = "rlm_sql_mysql"
    dialect = "mysql"
    
    server = "localhost"
    port = 3306
    login = "radius_app"
    password = "RadiusAppPass!2026"
    
    radius_db = "radius"
    
    acct_table1 = "radacct"
    acct_table2 = "radacct"
    postauth_table = "radpostauth"
    authcheck_table = "radcheck"
    authreply_table = "radreply"
    groupcheck_table = "radgroupcheck"
    groupreply_table = "radgroupreply"
    usergroup_table = "radusergroup"
    
    # Désactivé pour éviter les warnings MySQL
    # group_membership_query = "..."
    # groupcheck_query = "..."
    # groupreply_query = "..."
    
    read_clients = yes
    client_table = "nas"
    
    pool {
        start = 5
        min = 4
        max = 10
        spare = 3
        uses = 0
        lifetime = 0
        idle_timeout = 60
    }
}
EOF

chmod 640 "$FR_CONF/mods-available/sql"
chown root:freerad "$FR_CONF/mods-available/sql"

# Activer module SQL
ln -sf ../mods-available/sql "$FR_CONF/mods-enabled/sql" 2>/dev/null || true

# 9. Configuration module LINELOG pour logging détaillé (SANS collision avec detail.log)
echo "[9/13] Configuration logging détaillé..."
cat > "$FR_CONF/mods-available/linelog" <<'EOF'
linelog {
    filename = "/var/log/freeradius/radius.log"
    
    format = "%t user=%{%{User-Name}:-unknown} result=%{%{reply:Packet-Type}:-Unknown} client=%{%{Packet-Src-IP-Address}:-0.0.0.0} nas=%{%{NAS-IP-Address}:-unknown} mac=%{%{Calling-Station-Id}:-unknown} auth_type=%{%{control:Auth-Type}:-None}"
    
    permissions = 0640
    
    reference = "messages.%{%{Packet-Type}:-default}"
}
EOF

chmod 640 "$FR_CONF/mods-available/linelog"
chown root:freerad "$FR_CONF/mods-available/linelog"

# Activer module linelog
ln -sf ../mods-available/linelog "$FR_CONF/mods-enabled/linelog" 2>/dev/null || true

# Créer le fichier de log
mkdir -p /var/log/freeradius
touch /var/log/freeradius/radius.log
chown freerad:freerad /var/log/freeradius/radius.log
chmod 640 /var/log/freeradius/radius.log

# 10. Configurer logrotate
echo "[10/13] Configuration logrotate..."
cat > /etc/logrotate.d/freeradius <<'LOGROTATE'
/var/log/freeradius/radius.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 freerad freerad
    postrotate
        systemctl reload freeradius > /dev/null 2>&1 || true
    endscript
}
LOGROTATE

# 11. Utiliser le linelog pour les logs post-auth (au lieu de créer auth_log duplicate)
echo "[11/13] Configuration post-auth logging..."
if ! grep -q "post-auth" "$FR_CONF/sites-available/default"; then
    sed -i '/post-auth {/a\        linelog' "$FR_CONF/sites-available/default"
fi
if ! grep -q "post-auth" "$FR_CONF/sites-available/inner-tunnel"; then
    sed -i '/post-auth {/a\        linelog' "$FR_CONF/sites-available/inner-tunnel"
fi

# 12. Génération certificats TLS
echo "[12/13] Génération certificats TLS..."
cd "$FR_CONF/certs"

# Configurer le certificat
sed -i 's/default_days\s*=.*/default_days = 3650/' ca.cnf
sed -i 's/countryName_default\s*=.*/countryName_default = FR/' ca.cnf
sed -i 's/stateOrProvinceName_default\s*=.*/stateOrProvinceName_default = IDF/' ca.cnf
sed -i 's/localityName_default\s*=.*/localityName_default = Paris/' ca.cnf
sed -i 's/organizationName_default\s*=.*/organizationName_default = SAE501/' ca.cnf

make > /dev/null 2>&1 || {
  echo "⚠️  Génération certificats échouée, utilisation des certificats par défaut"
}

cd - > /dev/null

# Activer module EAP
ln -sf ../mods-available/eap "$FR_CONF/mods-enabled/eap" 2>/dev/null || true

# 13. Permissions finales
echo "[13/13] Configuration permissions..."
chown -R root:freerad "$FR_CONF"
chmod -R 750 "$FR_CONF"
chmod 640 "$FR_CONF/clients.conf"
chmod 640 "$FR_CONF/users"

# Vérifier syntaxe
echo "──────────────────────────────────────"
echo "🔍 Vérification configuration..."
if freeradius -XC > /dev/null 2>&1; then
  echo "✅ Configuration FreeRADIUS valide"
else
  echo "❌ Erreur de configuration"
  freeradius -XC
  exit 1
fi

# Démarrage service
echo "──────────────────────────────────────"
echo "🔄 Démarrage services..."
systemctl enable freeradius > /dev/null 2>&1
systemctl restart freeradius

# Attendre démarrage
sleep 3

# Test authentification
echo "──────────────────────────────────────"
echo "🧪 Test authentification..."
if radtest alice@gym.fr Alice@123! 127.0.0.1 1812 testing123 2>&1 | grep -q "Access-Accept"; then
  echo "✅ Test authentification réussi"
  echo "📝 Vérifier logs: tail -f /var/log/freeradius/radius.log"
else
  echo "⚠️  Test authentification échoué (vérifier logs)"
fi

# Afficher status
systemctl status freeradius --no-pager

echo "──────────────────────────────────────"
echo "✅ Installation FreeRADIUS terminée"
echo ""
echo "📝 Commandes utiles:"
echo "  systemctl status freeradius"
echo "  sudo freeradius -X                    # Mode debug"
echo "  radtest alice@gym.fr Alice@123! 127.0.0.1 1812 testing123"
echo "  tail -f /var/log/freeradius/radius.log"
echo ""
echo "🔐 Identifiants MySQL:"
echo "  Base: radius"
echo "  User: radius_app"
echo "  Pass: RadiusAppPass!2026"
echo ""
echo "✅ Logging détaillé activé dans /var/log/freeradius/radius.log"
echo "──────────────────────────────────────"

exit 0
