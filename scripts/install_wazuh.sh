#!/bin/bash
set -e

SERVER_IP="${SERVER_IP:-192.168.10.100}"
WAZUH_DIR="/opt/wazuh-docker"

if [ "$EUID" -ne 0 ]; then
  echo "❌ Exécuter en root (sudo)"
  exit 1
fi

echo "🐳 Installation Wazuh Manager (Docker)"
echo "IP: $SERVER_IP"
echo ""

# Install Docker if needed
if ! command -v docker &> /dev/null; then
  echo "[1/5] Installation Docker..."
  apt-get update -qq
  apt-get install -y ca-certificates curl > /dev/null 2>&1
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update -qq
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin > /dev/null 2>&1
  systemctl enable --now docker > /dev/null 2>&1
  echo "✅ Docker installé"
else
  echo "[1/5] Docker OK"
fi

# System config
echo "[2/5] Configuration système..."
grep -q "vm.max_map_count=262144" /etc/sysctl.conf || echo "vm.max_map_count=262144" >> /etc/sysctl.conf
sysctl -w vm.max_map_count=262144 > /dev/null

# Clone Wazuh
echo "[3/5] Téléchargement Wazuh..."
rm -rf "$WAZUH_DIR"
git clone https://github.com/wazuh/wazuh-docker.git -b v4.14.2 --single-branch "$WAZUH_DIR" > /dev/null 2>&1
cd "$WAZUH_DIR/single-node"

# Generate certs
echo "[4/5] Génération certificats..."
docker compose -f generate-indexer-certs.yml run --rm generator > /dev/null 2>&1

# Deploy
echo "[5/5] Démarrage Wazuh (2-3 min)..."
docker compose up -d
sleep 30

# Get credentials
ADMIN_USER=$(grep "INDEXER_USERNAME" docker-compose.yml | cut -d':' -f2 | tr -d ' "' | head -1)
ADMIN_PASS=$(grep "INDEXER_PASSWORD" docker-compose.yml | cut -d':' -f2 | tr -d ' "' | head -1)

# Create logs directory for PHP access
mkdir -p /var/log/wazuh-export
chmod 755 /var/log/wazuh-export

# Setup log export cron
cat > /usr/local/bin/export-wazuh-logs.sh <<'SCRIPT'
#!/bin/bash
LOG_FILE="/var/log/wazuh-export/alerts.json"
docker exec single-node-wazuh.manager-1 tail -n 1000 /var/ossec/logs/alerts/alerts.json > "$LOG_FILE" 2>/dev/null || echo '[]' > "$LOG_FILE"
chmod 644 "$LOG_FILE"
SCRIPT

chmod +x /usr/local/bin/export-wazuh-logs.sh
(crontab -l 2>/dev/null | grep -v export-wazuh-logs; echo "*/2 * * * * /usr/local/bin/export-wazuh-logs.sh") | crontab -
/usr/local/bin/export-wazuh-logs.sh

# UFW rules
if command -v ufw &> /dev/null; then
  ufw allow 443/tcp comment 'Wazuh Dashboard' > /dev/null 2>&1
  ufw allow 1514/tcp comment 'Wazuh Agent' > /dev/null 2>&1
  ufw allow 514/udp comment 'Syslog' > /dev/null 2>&1
fi

# Save info
cat > /root/wazuh-info.txt <<EOF
╔════════════════════════════════════╗
║   WAZUH DOCKER - SAE 5.01          ║
╚════════════════════════════════════╝

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

🔧 DEBUG
docker exec single-node-wazuh.manager-1 tail -f /var/ossec/logs/ossec.log
EOF

chmod 600 /root/wazuh-info.txt

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Wazuh Manager installé"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Dashboard: https://$SERVER_IP:443"
echo "User:      $ADMIN_USER"
echo "Pass:      $ADMIN_PASS"
echo "Logs Web:  http://$SERVER_IP/php-admin/wazuh_logs.php"
echo ""
echo "📖 Détails: cat /root/wazuh-info.txt"
echo ""
