#!/bin/bash
#
# install_radius.sh - Installation FreeRADIUS simple
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FR_CONF="/etc/freeradius/3.0"

echo "──────────────────────────────────────"
echo "🚀 Installation FreeRADIUS (SANS GROUPES)"
echo "──────────────────────────────────────"

# Vérifier root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ce script doit être exécuté en root (sudo)"
  exit 1
fi

# 1. Installation paquets
echo "[1/15] Installation paquets..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  freeradius \
  freeradius-mysql \
  freeradius-utils \
  mariadb-server \
  mariadb-client \
  > /dev/null 2>&1

# 2. Démarrage MySQL
echo "[2/15] Configuration MySQL..."
systemctl enable mariadb > /dev/null 2>&1
systemctl start mariadb

# 3. Sécurisation MySQL
echo "[3/15] Sécurisation MySQL..."
mysql -u root -e "
  DELETE FROM mysql.user WHERE User='';
  DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
  DROP DATABASE IF EXISTS test;
  DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
  FLUSH PRIVILEGES;
" 2>/dev/null || true

# 4. Création base et utilisateur
echo "[4/15] Création base de données RADIUS..."
if [ -f "$PROJECT_ROOT/radius/sql/init_appuser.sql" ]; then
  mysql -u root < "$PROJECT_ROOT/radius/sql/init_appuser.sql"
else
  echo "❌ Fichier init_appuser.sql introuvable"
  exit 1
fi

# 5. Création tables (SANS GROUPES)
echo "[5/15] Création des tables (SIMPLE - SANS GROUPES)..."
if [ -f "$PROJECT_ROOT/radius/sql/create_tables.sql" ]; then
  mysql -u root radius < "$PROJECT_ROOT/radius/sql/create_tables.sql"
  echo "  ✅ Tables créées: nas, radcheck, radreply, radacct, radpostauth"
else
  echo "❌ Fichier create_tables.sql introuvable"
  exit 1
fi

# 6. Configuration FreeRADIUS - clients.conf
echo "[6/15] Configuration clients RADIUS..."
if [ -f "$PROJECT_ROOT/radius/clients.conf" ]; then
  cp "$FR_CONF/clients.conf" "$FR_CONF/clients.conf.backup" 2>/dev/null || true
  cp "$PROJECT_ROOT/radius/clients.conf" "$FR_CONF/clients.conf"
  chmod 640 "$FR_CONF/clients.conf"
  chown root:freerad "$FR_CONF/clients.conf"
fi

# 7. Configuration FreeRADIUS - users
echo "[7/15] Configuration users..."
if [ -f "$PROJECT_ROOT/radius/users.txt" ]; then
  cp "$FR_CONF/users" "$FR_CONF/users.backup" 2>/dev/null || true
  cp "$PROJECT_ROOT/radius/users.txt" "$FR_CONF/users"
  chmod 640 "$FR_CONF/users"
  chown root:freerad "$FR_CONF/users"
fi

# 8. Configuration SQL module (SANS GROUPES - CLÉ DE LA SOLUTION)
echo "[8/15] Configuration module SQL (SANS GROUPES)..."
cat > "$FR_CONF/mods-available/sql" <<'EOF'
sql {
    driver = "rlm_sql_mysql"
    dialect = "mysql"
    
    server = "localhost"
    port = 3306
    login = "radius_app"
    password = "RadiusAppPass!2026"
    
    radius_db = "radius"
    
    # Tables utilisées (authentification simple)
    acct_table1 = "radacct"
    acct_table2 = "radacct"
    postauth_table = "radpostauth"
    authcheck_table = "radcheck"
    authreply_table = "radreply"
    
    # ✅ CLÉ : DÉSACTIVER COMPLÈTEMENT LES GROUPES
    read_groups = no
    
    # Lecture des clients depuis MySQL
    read_clients = yes
    client_table = "nas"
    
    # Pool de connexions
    pool {
        start = 5
        min = 4
        max = 10
        spare = 3
        uses = 0
        lifetime = 0
        idle_timeout = 60
    }
    
    # ✅ NE PAS INCLURE queries.conf (contient les requêtes de groupes)
    # Commentaire : On utilise les requêtes par défaut embarquées dans FreeRADIUS
}
EOF

chmod 640 "$FR_CONF/mods-available/sql"
chown root:freerad "$FR_CONF/mods-available/sql"

# Activer module SQL
ln -sf ../mods-available/sql "$FR_CONF/mods-enabled/sql" 2>/dev/null || true

echo "  ✅ Module SQL configuré SANS système de groupes"
echo "  ✅ read_groups = no (pas de warnings)"

# 9. Configuration module LINELOG pour logging
echo "[9/15] Configuration logging..."
cat > "$FR_CONF/mods-available/linelog" <<'EOF'
linelog {
    filename = "/var/log/freeradius/radius.log"
    format = "%t [%{reply:Packet-Type}] user=%{User-Name} nas=%{NAS-IP-Address} mac=%{Calling-Station-Id}"
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

# Ajouter www-data au groupe freerad
if ! groups www-data 2>/dev/null | grep -q freerad; then
    usermod -a -G freerad www-data 2>/dev/null || true
    echo "  ✅ www-data ajouté au groupe freerad"
fi

# 9bis. ✨ CORRECTIF: Activer les logs d'authentification dans radiusd.conf
echo "[9bis/15] Activation logs d'authentification dans radiusd.conf..."
RADIUSD_CONF="$FR_CONF/radiusd.conf"

if [ -f "$RADIUSD_CONF" ]; then
    # Backup
    cp "$RADIUSD_CONF" "${RADIUSD_CONF}.backup" 2>/dev/null || true
    
    # Activer auth = yes, auth_badpass = yes, auth_goodpass = yes
    sed -i '/^\s*auth\s*=/ s/=.*/= yes/' "$RADIUSD_CONF"
    sed -i '/^\s*auth_badpass\s*=/ s/=.*/= yes/' "$RADIUSD_CONF"
    sed -i '/^\s*auth_goodpass\s*=/ s/=.*/= yes/' "$RADIUSD_CONF"
    
    echo "  ✅ Logs d'authentification activés:"
    echo "     auth = yes (toutes les authentifications)"
    echo "     auth_badpass = yes (échecs)"
    echo "     auth_goodpass = yes (succès)"
else
    echo "  ⚠️  radiusd.conf introuvable, logs par défaut"
fi

# 10. Configurer logrotate
echo "[10/15] Configuration logrotate..."
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

# 11. Activer linelog dans sites
echo "[11/15] Activation linelog..."
if ! grep -q "^[[:space:]]*linelog" "$FR_CONF/sites-available/default"; then
    sed -i '/^post-auth {$/a\        linelog' "$FR_CONF/sites-available/default"
fi

if ! grep -q "^[[:space:]]*linelog" "$FR_CONF/sites-available/inner-tunnel"; then
    sed -i '/^post-auth {$/a\        linelog' "$FR_CONF/sites-available/inner-tunnel"
fi

# 12. Génération certificats TLS
echo "[12/15] Génération certificats TLS..."
cd "$FR_CONF/certs"

sed -i 's/default_days\s*=.*/default_days = 3650/' ca.cnf 2>/dev/null || true
sed -i 's/countryName_default\s*=.*/countryName_default = FR/' ca.cnf 2>/dev/null || true
sed -i 's/stateOrProvinceName_default\s*=.*/stateOrProvinceName_default = IDF/' ca.cnf 2>/dev/null || true
sed -i 's/localityName_default\s*=.*/localityName_default = Paris/' ca.cnf 2>/dev/null || true

make > /dev/null 2>&1 || {
  echo "⚠️  Génération certificats échouée, utilisation par défaut"
}

cd - > /dev/null

# Activer module EAP
ln -sf ../mods-available/eap "$FR_CONF/mods-enabled/eap" 2>/dev/null || true

# 13. Permissions finales
echo "[13/15] Configuration permissions..."
chown -R root:freerad "$FR_CONF"
chmod -R 750 "$FR_CONF"
chmod 640 "$FR_CONF/clients.conf" 2>/dev/null || true
chmod 640 "$FR_CONF/users" 2>/dev/null || true

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

# 14. Démarrage service
echo "──────────────────────────────────────"
echo "[14/15] Démarrage FreeRADIUS..."
systemctl enable freeradius > /dev/null 2>&1
systemctl restart freeradius

sleep 3

# Test authentification
echo "──────────────────────────────────────"
echo "🧪 Test authentification..."
if radtest alice@gym.fr Alice@123! 127.0.0.1 1812 testing123 2>&1 | grep -q "Access-Accept"; then
  echo "✅ Test réussi"
  sleep 2
  echo "📝 Logs:"
  tail -3 /var/log/freeradius/radius.log 2>/dev/null | sed 's/^/  /' || echo "  (en cours...)"
else
  echo "⚠️  Test échoué"
fi

echo ""
systemctl status freeradius --no-pager

echo ""
echo "──────────────────────────────────────"
echo "✅ Installation terminée (VERSION ULTRA-SIMPLE)"
echo ""
echo "📋 ARCHITECTURE:"
echo "  ✅ Pas de groupes - tous les users ont les mêmes droits"
echo "  ✅ Fitness-Pro = authentification RADIUS"
echo "  ✅ Fitness-Guest = WPA2-PSK (pas RADIUS)"
echo "  ✅ read_groups = no → AUCUN WARNING"
echo "  ✅ Logs d'authentification activés dans radiusd.conf"
echo ""
echo "📝 Commandes:"
echo "  systemctl status freeradius"
echo "  sudo freeradius -X"
echo "  radtest alice@gym.fr Alice@123! 127.0.0.1 1812 testing123"
echo "  tail -f /var/log/freeradius/radius.log"
echo "  mysql -u radius_app -pRadiusAppPass!2026 radius -e 'SELECT * FROM v_users_simple;'"
echo ""
echo "🔐 MySQL:"
echo "  Base: radius"
echo "  User: radius_app"
echo "  Pass: RadiusAppPass!2026"
echo ""
echo "✅ 5 utilisateurs créés avec les mêmes droits"
echo "✅ Logs dans /var/log/freeradius/radius.log"
echo "──────────────────────────────────────"

exit 0
