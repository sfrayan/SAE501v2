#!/bin/bash
set -e

SERVER_IP="${SERVER_IP:-192.168.10.100}"
WAZUH_DIR="/opt/wazuh-docker"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [ "$EUID" -ne 0 ]; then
  echo "❌ Exécuter en root (sudo)"
  exit 1
fi

echo "🐳 Installation Wazuh Manager (Docker)"
echo "IP: $SERVER_IP"
echo ""

# Install Docker if needed
if ! command -v docker &> /dev/null; then
  echo "[1/10] Installation Docker..."
  
  # Detect OS
  . /etc/os-release
  OS_ID=$ID
  OS_VERSION_CODENAME=$VERSION_CODENAME
  
  echo "OS détecté: $OS_ID $OS_VERSION_CODENAME"
  
  apt-get update -qq
  apt-get install -y ca-certificates curl gnupg lsb-release > /dev/null 2>&1
  install -m 0755 -d /etc/apt/keyrings
  
  # Remove old Docker GPG key if exists
  rm -f /etc/apt/keyrings/docker.asc /etc/apt/keyrings/docker.gpg
  
  if [ "$OS_ID" = "debian" ]; then
    # Debian
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $OS_VERSION_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  elif [ "$OS_ID" = "ubuntu" ]; then
    # Ubuntu
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $OS_VERSION_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  else
    echo "❌ OS non supporté: $OS_ID"
    exit 1
  fi
  
  apt-get update -qq
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1
  systemctl enable --now docker > /dev/null 2>&1
  echo "✅ Docker installé"
else
  echo "[1/10] Docker OK"
fi

# Install UFW
echo "[2/10] Installation UFW..."
if ! command -v ufw &> /dev/null; then
  apt-get update -qq
  apt-get install -y ufw > /dev/null 2>&1
  echo "✅ UFW installé"
else
  echo "✅ UFW déjà installé"
fi

# System config
echo "[3/10] Configuration système..."
grep -q "vm.max_map_count=262144" /etc/sysctl.conf || echo "vm.max_map_count=262144" >> /etc/sysctl.conf
sysctl -w vm.max_map_count=262144 > /dev/null

# Clone Wazuh
echo "[4/10] Téléchargement Wazuh..."
rm -rf "$WAZUH_DIR"
git clone https://github.com/wazuh/wazuh-docker.git -b v4.14.2 --single-branch "$WAZUH_DIR" > /dev/null 2>&1
cd "$WAZUH_DIR/single-node"

# Generate certs
echo "[5/10] Génération certificats..."
docker compose -f generate-indexer-certs.yml run --rm generator > /dev/null 2>&1

# Deploy
echo "[6/10] Démarrage Wazuh (2-3 min)..."
docker compose up -d

# Wait for Wazuh to be ready
echo "Attente du démarrage complet..."
sleep 45

# Get credentials
ADMIN_USER=$(grep "INDEXER_USERNAME" docker-compose.yml | cut -d':' -f2 | tr -d ' "' | head -1)
ADMIN_PASS=$(grep "INDEXER_PASSWORD" docker-compose.yml | cut -d':' -f2 | tr -d ' "' | head -1)

# Create logs directory for PHP access
mkdir -p /var/log/wazuh-export
chmod 755 /var/log/wazuh-export

# Setup log export script
cat > /usr/local/bin/export-wazuh-logs.sh <<'SCRIPT'
#!/bin/bash
LOG_FILE="/var/log/wazuh-export/alerts.json"

# Ensure container is running
if ! docker exec single-node-wazuh.manager-1 echo "test" > /dev/null 2>&1; then
  echo "[]" > "$LOG_FILE"
  chmod 644 "$LOG_FILE"
  exit 0
fi

# Export logs
docker exec single-node-wazuh.manager-1 tail -n 1000 /var/ossec/logs/alerts/alerts.json > "$LOG_FILE" 2>/dev/null || echo "[]" > "$LOG_FILE"
chmod 644 "$LOG_FILE"
SCRIPT

chmod +x /usr/local/bin/export-wazuh-logs.sh

# Setup cron job
echo "[7/10] Configuration cron export..."
crontab -l 2>/dev/null | grep -v export-wazuh-logs > /tmp/crontab.tmp || true
echo "*/2 * * * * /usr/local/bin/export-wazuh-logs.sh" >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm -f /tmp/crontab.tmp
echo "✅ Cron configuré : */2 * * * * /usr/local/bin/export-wazuh-logs.sh"

# Initial log export
/usr/local/bin/export-wazuh-logs.sh

# Copy Wazuh rules
echo "[8/10] Configuration règles Wazuh..."
if [ -f "$PROJECT_ROOT/wazuh/local_rules.xml" ]; then
    docker cp "$PROJECT_ROOT/wazuh/local_rules.xml" single-node-wazuh.manager-1:/var/ossec/etc/rules/
    docker exec single-node-wazuh.manager-1 chown root:wazuh /var/ossec/etc/rules/local_rules.xml
    docker exec single-node-wazuh.manager-1 chmod 640 /var/ossec/etc/rules/local_rules.xml
    echo "✅ Règles Wazuh copiées"
else
    echo "⚠️  Fichier local_rules.xml introuvable"
fi

# Configure rsyslog for RADIUS logs
echo "[9/10] Configuration rsyslog pour logs RADIUS..."
cat > /etc/rsyslog.d/30-radius.conf <<'RSYSLOG'
# Capture logs FreeRADIUS
:programname, isequal, "freeradius" /var/log/freeradius/radius.log
:programname, isequal, "freeradius" @@127.0.0.1:1514
:programname, isequal, "freeradius" stop
RSYSLOG

# Redémarrer rsyslog
if systemctl is-active --quiet rsyslog; then
    systemctl restart rsyslog
    echo "✅ rsyslog configuré et redémarré"
else
    echo "ℹ️ rsyslog non actif, configuration sauvegardée"
fi

# Configure UFW rules
echo "[10/10] Configuration UFW..."
ufw --force enable > /dev/null 2>&1
ufw allow 443/tcp comment 'Wazuh Dashboard' > /dev/null 2>&1
ufw allow 1514/tcp comment 'Wazuh Agent Registration' > /dev/null 2>&1
ufw allow 1515/tcp comment 'Wazuh Agent Communication' > /dev/null 2>&1
ufw allow 514/udp comment 'Syslog' > /dev/null 2>&1
ufw allow 1812/udp comment 'RADIUS Auth' > /dev/null 2>&1
ufw allow 1813/udp comment 'RADIUS Accounting' > /dev/null 2>&1
ufw allow 80/tcp comment 'HTTP PHP Admin' > /dev/null 2>&1
ufw allow 22/tcp comment 'SSH' > /dev/null 2>&1
echo "✅ UFW configuré"

# Restart Wazuh to apply rules
docker exec single-node-wazuh.manager-1 /var/ossec/bin/wazuh-control restart > /dev/null 2>&1 || true
echo "✅ Wazuh redémarré"

# Save info
cat > /root/wazuh-info.txt <<EOF
╔══════════════════════════════════════╗
║   WAZUH DOCKER - SAE 5.01          ║
╚══════════════════════════════════════╝

📊 ACCÈS
URL:      https://$SERVER_IP:443
Username: $ADMIN_USER
Password: $ADMIN_PASS

🐳 GESTION
Répertoire: $WAZUH_DIR/single-node

Statut:     docker compose ps
Logs:       docker compose logs -f wazuh.manager
Redémarrer: docker compose restart
Arrêter:    docker compose stop
Démarrer:   docker compose start

📁 LOGS EXPORTÉS
Fichier: /var/log/wazuh-export/alerts.json
MàJ:     Toutes les 2 minutes (cron)
Web:     http://$SERVER_IP/php-admin/wazuh_logs.php

Vérifier export:
sudo /usr/local/bin/export-wazuh-logs.sh
cat /var/log/wazuh-export/alerts.json | head -5

🔧 DEBUG
docker exec single-node-wazuh.manager-1 tail -f /var/ossec/logs/ossec.log
docker exec single-node-wazuh.manager-1 cat /var/ossec/logs/alerts/alerts.json | tail -10

🔥 FIREWALL UFW
sudo ufw status numbered

📝 LOGS RADIUS
Fichier: /var/log/freeradius/radius.log
Test:    radtest alice@gym.fr Alice@123! 127.0.0.1 1812 testing123
Voir:    tail -f /var/log/freeradius/radius.log
EOF

chmod 600 /root/wazuh-info.txt

echo ""
echo "──────────────────────────────────────"
echo "✅ Installation complète !"
echo "──────────────────────────────────────"
echo ""
echo "Dashboard: https://$SERVER_IP:443"
echo "User:      $ADMIN_USER"
echo "Pass:      $ADMIN_PASS"
echo "Logs Web:  http://$SERVER_IP/php-admin/wazuh_logs.php"
echo ""
echo "✅ UFW activé et configuré"
echo "✅ Cron export logs actif (toutes les 2 min)"
echo "✅ rsyslog configuré pour logs RADIUS"
echo "✅ Règles Wazuh installées"
echo ""
echo "Vérifier cron: crontab -l"
echo "Vérifier UFW:  sudo ufw status"
echo "Vérifier logs: cat /var/log/wazuh-export/alerts.json"
echo ""
echo "📜 Infos complètes: cat /root/wazuh-info.txt"
echo ""
