#!/bin/bash
#
# install_wazuh.sh - Installation Wazuh Manager only (lightweight)
# Version corrigée sans Indexer/Dashboard
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# IP STATIQUE DU SERVEUR
SERVER_IP="192.168.10.100"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🛡️  Installation Wazuh Manager (lightweight)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Vérifier root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ce script doit être exécuté en root (sudo)"
  exit 1
fi

# 1. Installation prérequis
echo "[1/9] Installation prérequis..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  gnupg \
  apt-transport-https \
  curl \
  rsyslog \
  lsb-release \
  > /dev/null 2>&1

# 2. Ajout dépôt Wazuh
echo "[2/9] Configuration dépôt Wazuh..."
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import > /dev/null 2>&1
chmod 644 /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list
apt-get update -qq

# 3. Installation Wazuh Manager
echo "[3/9] Installation Wazuh Manager..."
WAZUH_MANAGER="wazuh-manager" apt-get install -y wazuh-manager > /dev/null 2>&1

# 4. Configuration rsyslog pour réception logs
echo "[4/9] Configuration rsyslog..."
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

# 5. Configuration Wazuh Manager minimale
echo "[5/9] Configuration Wazuh Manager..."
cat > /var/ossec/etc/ossec.conf <<'EOF'
<ossec_config>
  <global>
    <jsonout_output>yes</jsonout_output>
    <alerts_log>yes</alerts_log>
    <logall>no</logall>
    <logall_json>no</logall_json>
    <email_notification>no</email_notification>
  </global>

  <alerts>
    <log_alert_level>3</log_alert_level>
  </alerts>

  <!-- Monitoring logs système -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/syslog</location>
  </localfile>

  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/auth.log</location>
  </localfile>

  <!-- Monitoring FreeRADIUS -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/freeradius/radius.log</location>
  </localfile>

  <!-- Monitoring logs RADIUS auth -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/radius-auth.log</location>
  </localfile>

  <!-- Monitoring logs remote syslog -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/remote-syslog.log</location>
  </localfile>

  <remote>
    <connection>secure</connection>
    <port>1514</port>
    <protocol>tcp</protocol>
    <queue_size>131072</queue_size>
  </remote>

  <ruleset>
    <decoder_dir>ruleset/decoders</decoder_dir>
    <rule_dir>ruleset/rules</rule_dir>
    <rule_exclude>0215-policy_rules.xml</rule_exclude>
    <list>etc/lists/audit-keys</list>
    <list>etc/lists/amazon/aws-eventnames</list>
    <list>etc/lists/security-eventchannel</list>
  </ruleset>

  <rule_test>
    <enabled>yes</enabled>
    <threads>1</threads>
    <max_sessions>64</max_sessions>
    <session_timeout>15m</session_timeout>
  </rule_test>

  <auth>
    <disabled>no</disabled>
    <port>1515</port>
    <use_source_ip>no</use_source_ip>
    <force>
      <enabled>yes</enabled>
      <key_mismatch>yes</key_mismatch>
      <disconnected_time>1h</disconnected_time>
      <after_registration_time>1h</after_registration_time>
    </force>
    <purge>yes</purge>
    <use_password>no</use_password>
  </auth>

  <cluster>
    <disabled>yes</disabled>
  </cluster>

</ossec_config>
EOF

# Fixer les permissions
chown root:wazuh /var/ossec/etc/ossec.conf
chmod 640 /var/ossec/etc/ossec.conf

# 6. Règles personnalisées
echo "[6/9] Configuration règles personnalisées..."
cat > /var/ossec/etc/rules/local_rules.xml <<'EOF'
<group name="local,syslog,radius,">

  <!-- Règle: Auth RADIUS réussie -->
  <rule id="100001" level="3">
    <decoded_as>radiusd</decoded_as>
    <match>Login OK</match>
    <description>RADIUS: Authentification réussie</description>
    <group>authentication_success,pci_dss_10.2.5,</group>
  </rule>

  <!-- Règle: Auth RADIUS échouée -->
  <rule id="100002" level="5">
    <decoded_as>radiusd</decoded_as>
    <match>Login incorrect</match>
    <description>RADIUS: Authentification échouée</description>
    <group>authentication_failed,pci_dss_10.2.4,pci_dss_10.2.5,</group>
  </rule>

  <!-- Règle: Bruteforce RADIUS (5 échecs en 2 min) -->
  <rule id="100003" level="10" frequency="5" timeframe="120">
    <if_matched_sid>100002</if_matched_sid>
    <same_source_ip />
    <description>RADIUS: Tentative bruteforce détectée</description>
    <group>authentication_failures,pci_dss_11.4,pci_dss_10.2.4,pci_dss_10.2.5,</group>
  </rule>

  <!-- Règle: Logs routeur WiFi -->
  <rule id="100010" level="3">
    <match>WiFi|wireless|WLAN</match>
    <description>Routeur WiFi: Événement WiFi</description>
    <group>wifi,</group>
  </rule>

  <!-- Règle: Déconnexion WiFi -->
  <rule id="100011" level="4">
    <match>disassociated|deauthenticated</match>
    <description>Routeur WiFi: Client déconnecté</description>
    <group>wifi,</group>
  </rule>

</group>
EOF

chown root:wazuh /var/ossec/etc/rules/local_rules.xml
chmod 640 /var/ossec/etc/rules/local_rules.xml

# 7. Désactiver wazuh-csyslogd dans systemd (CRITIQUE)
echo "[7/9] Désactivation wazuh-csyslogd..."
if [ -f /var/ossec/bin/wazuh-csyslogd ]; then
  # Renommer l'exécutable pour empêcher son lancement
  mv /var/ossec/bin/wazuh-csyslogd /var/ossec/bin/wazuh-csyslogd.disabled
  echo "✅ wazuh-csyslogd désactivé"
fi

# 8. Démarrage Wazuh Manager
echo "[8/9] Démarrage Wazuh Manager..."
systemctl daemon-reload
systemctl enable wazuh-manager > /dev/null 2>&1
systemctl restart wazuh-manager
sleep 5

# Vérifier status
if systemctl is-active --quiet wazuh-manager; then
  echo "✅ Wazuh Manager démarré"
else
  echo "⚠️  Problème démarrage Wazuh Manager"
  echo "Logs d'erreur:"
  tail -20 /var/ossec/logs/ossec.log
  journalctl -xeu wazuh-manager.service | tail -20
  exit 1
fi

# 9. Configuration firewall
echo "[9/9] Configuration pare-feu..."
if command -v ufw >/dev/null 2>&1; then
  ufw --force enable > /dev/null 2>&1
  ufw allow 22/tcp comment 'SSH' > /dev/null 2>&1
  ufw allow 1812/udp comment 'RADIUS Auth' > /dev/null 2>&1
  ufw allow 1813/udp comment 'RADIUS Accounting' > /dev/null 2>&1
  ufw allow 514/udp comment 'Syslog' > /dev/null 2>&1
  ufw allow 1514/tcp comment 'Wazuh Agent' > /dev/null 2>&1
  ufw allow 80/tcp comment 'Apache HTTP' > /dev/null 2>&1
  ufw reload > /dev/null 2>&1
fi

# Fichier d'informations
cat > /root/wazuh-info.txt <<EOF
╔════════════════════════════════════════╗
║    WAZUH MANAGER - INFORMATIONS           ║
╚════════════════════════════════════════╝

📊 Status Wazuh Manager:
  IP: $SERVER_IP (statique)
  Port Agent: 1514/tcp
  Port Syslog: 514/udp

🔥 Ports UFW ouverts:
  22/tcp    → SSH
  80/tcp    → Apache (PHP-Admin)
  514/udp   → Syslog (logs routeur)
  1514/tcp  → Wazuh Agent
  1812/udp  → RADIUS Auth
  1813/udp  → RADIUS Accounting

📊 Status services:
  systemctl status wazuh-manager
  systemctl status rsyslog

📝 Logs importants:
  /var/ossec/logs/ossec.log          - Wazuh Manager
  /var/ossec/logs/alerts/alerts.log  - Alertes (texte)
  /var/ossec/logs/alerts/alerts.json - Alertes (JSON)
  /var/log/remote-syslog.log         - Logs routeur
  /var/log/radius-auth.log           - Auth RADIUS
  /var/log/php-admin.log             - PHP-Admin

🔍 Commandes utiles:
  # Voir alertes en temps réel
  sudo tail -f /var/ossec/logs/alerts/alerts.log
  
  # Voir alertes JSON
  sudo tail -f /var/ossec/logs/alerts/alerts.json | jq
  
  # Voir logs RADIUS
  sudo tail -f /var/log/radius-auth.log
  
  # Rechercher auth
  sudo grep -i "authentication" /var/log/radius-auth.log
  
  # Status UFW
  sudo ufw status verbose
  
  # Tester réception syslog
  echo "Test message" | logger -t test-wazuh
  sleep 2
  sudo grep "test-wazuh" /var/ossec/logs/alerts/alerts.log

⚠️  NOTE IMPORTANTE:
  Wazuh Manager uniquement (pas de Dashboard)
  Consultez les alertes via fichiers logs
  Pour Dashboard: installer Indexer sur machine 4GB+ RAM

╚════════════════════════════════════════╝
EOF

chmod 600 /root/wazuh-info.txt

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Installation Wazuh Manager terminée"
echo ""
echo "📋 Fichier d'informations créé:"
echo "  cat /root/wazuh-info.txt"
echo ""
echo "📊 Voir alertes:"
echo "  sudo tail -f /var/ossec/logs/alerts/alerts.log"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit 0
