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
  echo "[1/7] Installation Docker..."
  
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
  echo "[1/7] Docker OK"
fi

# Install UFW
echo "[2/7] Installation UFW..."
if ! command -v ufw &> /dev/null; then
  apt-get update -qq
  apt-get install -y ufw > /dev/null 2>&1
  echo "✅ UFW installé"
else
  echo "✅ UFW déjà installé"
fi

# System config
echo "[3/7] Configuration système..."
grep -q "vm.max_map_count=262144" /etc/sysctl.conf || echo "vm.max_map_count=262144" >> /etc/sysctl.conf
sysctl -w vm.max_map_count=262144 > /dev/null

# Clone Wazuh
echo "[4/7] Téléchargement Wazuh..."
rm -rf "$WAZUH_DIR"
git clone https://github.com/wazuh/wazuh-docker.git -b v4.14.2 --single-branch "$WAZUH_DIR" > /dev/null 2>&1
cd "$WAZUH_DIR/single-node"

# Generate certs
echo "[5/7] Génération certificats..."
docker compose -f generate-indexer-certs.yml run --rm generator > /dev/null 2>&1

# Deploy
echo "[6/7] Démarrage Wazuh (2-3 min)..."
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
echo "[7/7] Configuration cron export..."
(crontab -l 2>/dev/null | grep -v export-wazuh-logs; echo "*/2 * * * * /usr/local/bin/export-wazuh-logs.sh") | crontab -
echo "✅ Cron configuré : */2 * * * * /usr/local/bin/export-wazuh-logs.sh"

# Initial log export
/usr/local/bin/export-wazuh-logs.sh

# Configure UFW rules
echo "Configuration UFW..."
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
echo ""
echo "Vérifier cron: crontab -l"
echo "Vérifier UFW:  sudo ufw status"
echo "Vérifier logs: cat /var/log/wazuh-export/alerts.json"
echo ""
echo "📖 Infos complètes: cat /root/wazuh-info.txt"
echo ""
