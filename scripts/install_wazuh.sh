#!/bin/bash
#
# install_wazuh.sh - Installation Wazuh Manager + Dashboard
# Version corrigée avec configuration rsyslog complète
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🛡️  Installation Wazuh Manager + Dashboard"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Vérifier root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ce script doit être exécuté en root (sudo)"
  exit 1
fi

# 1. Installation prérequis
echo "[1/12] Installation prérequis..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  gnupg \
  apt-transport-https \
  curl \
  rsyslog \
  lsb-release \
  > /dev/null 2>&1

# 2. Ajout dépôt Wazuh
echo "[2/12] Configuration dépôt Wazuh..."
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import > /dev/null 2>&1
chmod 644 /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list
apt-get update -qq

# 3. Installation Wazuh Manager
echo "[3/12] Installation Wazuh Manager..."
WAZUH_MANAGER="wazuh-manager" apt-get install -y wazuh-manager > /dev/null 2>&1

# 4. Configuration Wazuh Manager
echo "[4/12] Configuration Wazuh Manager..."
if [ -f "$PROJECT_ROOT/wazuh/manager.conf" ]; then
  cp /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.backup
  cp "$PROJECT_ROOT/wazuh/manager.conf" /var/ossec/etc/ossec.conf
  chown root:wazuh /var/ossec/etc/ossec.conf
  chmod 640 /var/ossec/etc/ossec.conf
fi

# 5. Règles personnalisées
echo "[5/12] Configuration règles personnalisées..."
if [ -f "$PROJECT_ROOT/wazuh/local_rules.xml" ]; then
  cp "$PROJECT_ROOT/wazuh/local_rules.xml" /var/ossec/etc/rules/local_rules.xml
  chown root:wazuh /var/ossec/etc/rules/local_rules.xml
  chmod 640 /var/ossec/etc/rules/local_rules.xml
fi

# 6. Configuration rsyslog pour réception logs
echo "[6/12] Configuration rsyslog..."
cat > /etc/rsyslog.d/10-wazuh-input.conf <<'EOF'
# Module UDP pour réception syslog
module(load="imudp")
input(type="imudp" port="514")

# Format logs avec timestamp
$template RemoteFormat,"%TIMESTAMP:::date-rfc3339% %HOSTNAME% %syslogtag%%msg:::sp-if-no-1st-sp%%msg:::drop-last-lf%\n"

# Logs par source
:fromhost-ip, !isequal, "127.0.0.1" /var/log/remote-syslog.log;RemoteFormat
& stop
EOF

# Configuration logs FreeRADIUS
cat > /etc/rsyslog.d/20-freeradius.conf <<'EOF'
# Logs FreeRADIUS vers fichier dédié
:programname, isequal, "radiusd" /var/log/radius-auth.log
& stop

# Logs détaillés authentification
:msg, contains, "Login OK" /var/log/radius-auth.log
:msg, contains, "Login incorrect" /var/log/radius-auth.log
& stop
EOF

# Configuration logs PHP-Admin
cat > /etc/rsyslog.d/30-php-admin.conf <<'EOF'
:programname, isequal, "php-admin" /var/log/php-admin.log
& stop
EOF

# Créer fichiers logs
touch /var/log/remote-syslog.log
touch /var/log/radius-auth.log
touch /var/log/php-admin.log
chmod 644 /var/log/remote-syslog.log /var/log/radius-auth.log /var/log/php-admin.log

# Rotation logs
cat > /etc/logrotate.d/wazuh-custom <<'EOF'
/var/log/remote-syslog.log
/var/log/radius-auth.log
/var/log/php-admin.log
{
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0644 root root
    sharedscripts
    postrotate
        /usr/sbin/service rsyslog reload > /dev/null 2>&1 || true
    endscript
}
EOF

# Redémarrer rsyslog
systemctl restart rsyslog

# 7. Configuration Wazuh pour monitorer logs
echo "[7/12] Configuration monitoring logs..."
cat >> /var/ossec/etc/ossec.conf <<'EOF'
  
  <!-- Monitoring logs RADIUS -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/radius-auth.log</location>
  </localfile>
  
  <!-- Monitoring logs remote syslog -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/remote-syslog.log</location>
  </localfile>
  
  <!-- Monitoring logs PHP-Admin -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/php-admin.log</location>
  </localfile>
  
  <!-- Monitoring FreeRADIUS direct -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/freeradius/radius.log</location>
  </localfile>

EOF

# 8. Démarrage Wazuh Manager
echo "[8/12] Démarrage Wazuh Manager..."
systemctl daemon-reload
systemctl enable wazuh-manager > /dev/null 2>&1
systemctl restart wazuh-manager
sleep 5

# Vérifier status
if systemctl is-active --quiet wazuh-manager; then
  echo "✅ Wazuh Manager démarré"
else
  echo "⚠️  Problème démarrage Wazuh Manager"
fi

# 9. Installation Wazuh Indexer (OpenSearch)
echo "[9/12] Installation Wazuh Indexer..."
apt-get install -y wazuh-indexer > /dev/null 2>&1 || {
  echo "⚠️  Wazuh Indexer non installé (nécessite >4GB RAM)"
}

# 10. Configuration Indexer
if command -v wazuh-indexer >/dev/null 2>&1; then
  echo "[10/12] Configuration Indexer..."
  cat > /etc/wazuh-indexer/opensearch.yml <<'EOF'
network.host: "127.0.0.1"
node.name: "wazuh-node"
cluster.name: "wazuh-cluster"
cluster.initial_master_nodes:
  - "wazuh-node"
path.data: /var/lib/wazuh-indexer
path.logs: /var/log/wazuh-indexer
plugins.security.disabled: true
EOF

  chown wazuh-indexer:wazuh-indexer /etc/wazuh-indexer/opensearch.yml
  chmod 640 /etc/wazuh-indexer/opensearch.yml
  
  systemctl enable wazuh-indexer > /dev/null 2>&1
  systemctl restart wazuh-indexer
  sleep 30
fi

# 11. Installation Wazuh Dashboard
echo "[11/12] Installation Wazuh Dashboard..."
apt-get install -y wazuh-dashboard > /dev/null 2>&1 || {
  echo "⚠️  Wazuh Dashboard non installé"
}

# 12. Configuration Dashboard
if command -v wazuh-dashboard >/dev/null 2>&1; then
  echo "[12/12] Configuration Dashboard..."
  
  # Générer certificat auto-signé
  mkdir -p /etc/wazuh-dashboard/certs
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/wazuh-dashboard/certs/dashboard.key \
    -out /etc/wazuh-dashboard/certs/dashboard.crt \
    -subj "/C=FR/ST=IDF/L=Paris/O=SAE501/CN=$(hostname)" > /dev/null 2>&1
  
  chown -R wazuh-dashboard:wazuh-dashboard /etc/wazuh-dashboard/certs
  chmod 600 /etc/wazuh-dashboard/certs/*
  
  cat > /etc/wazuh-dashboard/opensearch_dashboards.yml <<'EOF'
server.host: "0.0.0.0"
server.port: 443
server.ssl.enabled: true
server.ssl.certificate: /etc/wazuh-dashboard/certs/dashboard.crt
server.ssl.key: /etc/wazuh-dashboard/certs/dashboard.key
opensearch.hosts: ["http://127.0.0.1:9200"]
opensearch.ssl.verificationMode: none
opensearch.username: "admin"
opensearch.password: "WazuhAdmin2026!"
EOF

  chown wazuh-dashboard:wazuh-dashboard /etc/wazuh-dashboard/opensearch_dashboards.yml
  chmod 640 /etc/wazuh-dashboard/opensearch_dashboards.yml
  
  systemctl enable wazuh-dashboard > /dev/null 2>&1
  systemctl restart wazuh-dashboard
  sleep 20
fi

# Configuration firewall
echo "Configuration pare-feu..."
if command -v ufw >/dev/null 2>&1; then
  ufw --force enable > /dev/null 2>&1
  ufw allow 22/tcp comment 'SSH' > /dev/null 2>&1
  ufw allow 443/tcp comment 'Wazuh Dashboard HTTPS' > /dev/null 2>&1
  ufw allow 1812/udp comment 'RADIUS Auth' > /dev/null 2>&1
  ufw allow 1813/udp comment 'RADIUS Accounting' > /dev/null 2>&1
  ufw allow 514/udp comment 'Syslog' > /dev/null 2>&1
  ufw allow 1514/tcp comment 'Wazuh Agent' > /dev/null 2>&1
  ufw allow 80/tcp comment 'Apache HTTP' > /dev/null 2>&1
  ufw reload > /dev/null 2>&1
fi

# Obtenir IP
IP=$(hostname -I | awk '{print $1}')

# Fichier d'informations
cat > /root/wazuh-credentials.txt <<EOF
╔════════════════════════════════════════╗
║    WAZUH - INFORMATIONS D'ACCÈS        ║
╚════════════════════════════════════════╝

🌐 URL Dashboard:
  https://$IP:443
  https://$(hostname):443

🔐 Identifiants par défaut:
  Username: admin
  Password: WazuhAdmin2026!

🔥 Ports UFW ouverts:
  22/tcp    → SSH
  80/tcp    → Apache (PHP-Admin)
  443/tcp   → Wazuh Dashboard HTTPS
  514/udp   → Syslog (logs routeur)
  1514/tcp  → Wazuh Agent
  1812/udp  → RADIUS Auth
  1813/udp  → RADIUS Accounting

📊 Status services:
  systemctl status wazuh-manager
  systemctl status wazuh-indexer
  systemctl status wazuh-dashboard
  systemctl status rsyslog

📝 Logs importants:
  /var/ossec/logs/ossec.log          - Wazuh Manager
  /var/ossec/logs/alerts/alerts.json - Alertes Wazuh
  /var/log/remote-syslog.log         - Logs routeur
  /var/log/radius-auth.log           - Auth RADIUS
  /var/log/php-admin.log             - PHP-Admin

🔍 Commandes utiles:
  tail -f /var/ossec/logs/ossec.log
  tail -f /var/log/radius-auth.log
  grep -i "authentication" /var/log/radius-auth.log
  ufw status verbose

⚠️  NOTE CERTIFICAT:
  Certificat auto-signé : accepter l'exception
  dans le navigateur lors de la première connexion

╚════════════════════════════════════════╝
EOF

chmod 600 /root/wazuh-credentials.txt

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Installation Wazuh terminée"
echo ""
echo "📋 Fichier d'informations créé:"
echo "  cat /root/wazuh-credentials.txt"
echo ""
echo "🌐 Accès Dashboard:"
echo "  https://$IP:443"
echo "  Username: admin"
echo "  Password: WazuhAdmin2026!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit 0
