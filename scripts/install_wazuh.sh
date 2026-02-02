#!/bin/bash
#
# install_wazuh.sh - Installation Wazuh Manager minimal
# SAE 5.01 - Version simplifiée cohérente avec la doc officielle
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SERVER_IP="192.168.10.100"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🛡️  Installation Wazuh Manager (minimal)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Vérifier root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ce script doit être exécuté en root (sudo)"
  exit 1
fi

# 1. Installation prérequis
echo "[1/6] Installation prérequis..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  gnupg \
  apt-transport-https \
  curl \
  rsyslog \
  lsb-release \
  > /dev/null 2>&1

# 2. Ajout dépôt Wazuh officiel
echo "[2/6] Configuration dépôt Wazuh..."
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import > /dev/null 2>&1
chmod 644 /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list
apt-get update -qq

# 3. Installation Wazuh Manager uniquement
echo "[3/6] Installation Wazuh Manager..."
WAZUH_MANAGER="wazuh-manager" apt-get install -y wazuh-manager > /dev/null 2>&1

# 4. Configuration rsyslog pour réception logs
echo "[4/6] Configuration rsyslog..."

# Activer module UDP
cat > /etc/rsyslog.d/10-wazuh-input.conf <<'EOF'
# Module UDP pour réception syslog
module(load="imudp")
input(type="imudp" port="514")

# Template pour logs avec timestamp
$template RemoteFormat,"%TIMESTAMP:::date-rfc3339% %HOSTNAME% %syslogtag%%msg:::sp-if-no-1st-sp%%msg:::drop-last-lf%\n"

# Logs distants vers fichier dédié
:fromhost-ip, !isequal, "127.0.0.1" /var/log/remote-syslog.log;RemoteFormat
& stop
EOF

# Logs FreeRADIUS
cat > /etc/rsyslog.d/20-freeradius.conf <<'EOF'
:programname, isequal, "radiusd" /var/log/radius-auth.log
:msg, contains, "Login OK" /var/log/radius-auth.log
:msg, contains, "Login incorrect" /var/log/radius-auth.log
& stop
EOF

# Créer fichiers logs
touch /var/log/remote-syslog.log /var/log/radius-auth.log
chmod 644 /var/log/remote-syslog.log /var/log/radius-auth.log

# Rotation logs
cat > /etc/logrotate.d/wazuh-custom <<'EOF'
/var/log/remote-syslog.log
/var/log/radius-auth.log
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

systemctl restart rsyslog

# 5. Configuration Wazuh Manager (utilise les fichiers du projet)
echo "[5/6] Configuration Wazuh Manager..."

# Copier configuration depuis le projet si disponible
if [ -f "$PROJECT_ROOT/wazuh/manager.conf" ]; then
  cp "$PROJECT_ROOT/wazuh/manager.conf" /var/ossec/etc/ossec.conf
  echo "✅ Configuration copiée depuis wazuh/manager.conf"
else
  # Configuration minimale par défaut
  cat > /var/ossec/etc/ossec.conf <<'EOF'
<ossec_config>
  <global>
    <jsonout_output>yes</jsonout_output>
    <alerts_log>yes</alerts_log>
    <logall>no</logall>
    <logall_json>no</logall_json>
  </global>

  <alerts>
    <log_alert_level>3</log_alert_level>
  </alerts>

  <!-- Monitoring logs système -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/auth.log</location>
  </localfile>

  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/syslog</location>
  </localfile>

  <!-- Monitoring FreeRADIUS -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/freeradius/radius.log</location>
  </localfile>

  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/radius-auth.log</location>
  </localfile>

  <!-- Monitoring logs routeur -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/remote-syslog.log</location>
  </localfile>

  <!-- Remote connection pour agents -->
  <remote>
    <connection>secure</connection>
    <port>1514</port>
    <protocol>tcp</protocol>
    <queue_size>131072</queue_size>
  </remote>

  <!-- Ruleset -->
  <ruleset>
    <decoder_dir>ruleset/decoders</decoder_dir>
    <rule_dir>ruleset/rules</rule_dir>
    <list>etc/lists/audit-keys</list>
  </ruleset>

  <!-- Auth pour agents -->
  <auth>
    <disabled>no</disabled>
    <port>1515</port>
    <use_source_ip>no</use_source_ip>
    <purge>yes</purge>
    <use_password>no</use_password>
  </auth>

  <!-- Cluster désactivé (single node) -->
  <cluster>
    <disabled>yes</disabled>
  </cluster>

</ossec_config>
EOF
fi

# Copier règles personnalisées si disponibles
if [ -f "$PROJECT_ROOT/wazuh/local_rules.xml" ]; then
  cp "$PROJECT_ROOT/wazuh/local_rules.xml" /var/ossec/etc/rules/local_rules.xml
  echo "✅ Règles personnalisées copiées depuis wazuh/local_rules.xml"
else
  # Règles minimales pour RADIUS
  cat > /var/ossec/etc/rules/local_rules.xml <<'EOF'
<group name="local,syslog,radius,">

  <!-- Auth RADIUS réussie -->
  <rule id="100001" level="3">
    <decoded_as>radiusd</decoded_as>
    <match>Login OK</match>
    <description>RADIUS: Authentification réussie</description>
    <group>authentication_success,pci_dss_10.2.5,</group>
  </rule>

  <!-- Auth RADIUS échouée -->
  <rule id="100002" level="5">
    <decoded_as>radiusd</decoded_as>
    <match>Login incorrect</match>
    <description>RADIUS: Authentification échouée</description>
    <group>authentication_failed,pci_dss_10.2.4,pci_dss_10.2.5,</group>
  </rule>

  <!-- Bruteforce RADIUS -->
  <rule id="100003" level="10" frequency="5" timeframe="120">
    <if_matched_sid>100002</if_matched_sid>
    <same_source_ip />
    <description>RADIUS: Tentative bruteforce détectée</description>
    <group>authentication_failures,pci_dss_11.4,</group>
  </rule>

</group>
EOF
fi

# Permissions
chown root:wazuh /var/ossec/etc/ossec.conf
chmod 640 /var/ossec/etc/ossec.conf
chown root:wazuh /var/ossec/etc/rules/local_rules.xml
chmod 640 /var/ossec/etc/rules/local_rules.xml

# 6. Démarrage Wazuh Manager
echo "[6/6] Démarrage Wazuh Manager..."
systemctl daemon-reload
systemctl enable wazuh-manager > /dev/null 2>&1
systemctl restart wazuh-manager
sleep 5

# Vérifier status
if systemctl is-active --quiet wazuh-manager; then
  echo "✅ Wazuh Manager opérationnel"
else
  echo "⚠️  Problème démarrage Wazuh Manager"
  echo "Logs d'erreur:"
  tail -20 /var/ossec/logs/ossec.log
  exit 1
fi

# Fichier d'informations
cat > /root/wazuh-info.txt <<EOF
╔════════════════════════════════════════╗
║   WAZUH MANAGER - SAE 5.01             ║
╚════════════════════════════════════════╝

📊 Configuration:
  IP: $SERVER_IP
  Port Agent: 1514/tcp
  Port Syslog: 514/udp

📝 Logs à monitorer:
  /var/ossec/logs/ossec.log          - Manager
  /var/ossec/logs/alerts/alerts.log  - Alertes
  /var/ossec/logs/alerts/alerts.json - JSON
  /var/log/remote-syslog.log         - Routeur
  /var/log/radius-auth.log           - RADIUS

🔍 Commandes utiles:
  # Voir alertes temps réel
  sudo tail -f /var/ossec/logs/alerts/alerts.log

  # Alertes JSON formatées
  sudo tail -f /var/ossec/logs/alerts/alerts.json | jq

  # Logs RADIUS
  sudo tail -f /var/log/radius-auth.log

  # Status service
  sudo systemctl status wazuh-manager

  # Tester réception syslog
  logger -t test-wazuh "Message de test"
  sleep 2
  sudo grep "test-wazuh" /var/log/syslog

🔧 Ports firewall nécessaires:
  22/tcp    - SSH
  80/tcp    - Apache (PHP-Admin)
  514/udp   - Syslog
  1514/tcp  - Wazuh Agent
  1515/tcp  - Wazuh Auth
  1812/udp  - RADIUS Auth
  1813/udp  - RADIUS Accounting

Configuration UFW:
  sudo ufw allow 514/udp
  sudo ufw allow 1514/tcp
  sudo ufw allow 1515/tcp

╚════════════════════════════════════════╝
EOF

chmod 600 /root/wazuh-info.txt

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Installation Wazuh Manager terminée"
echo ""
echo "📋 Informations: cat /root/wazuh-info.txt"
echo "📊 Alertes: sudo tail -f /var/ossec/logs/alerts/alerts.log"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit 0
