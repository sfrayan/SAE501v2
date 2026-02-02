#!/bin/bash
# Installation Wazuh minimaliste - SAE501v2
# Aucun message dans le terminal - installation silencieuse complète

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Vérification root silencieuse
[ "$EUID" -ne 0 ] && exit 1

# 1. Dépendances système
apt-get update -qq >/dev/null 2>&1
apt-get install -y gnupg apt-transport-https curl rsyslog >/dev/null 2>&1

# 2. Repository Wazuh
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import >/dev/null 2>&1
chmod 644 /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list
apt-get update -qq >/dev/null 2>&1

# 3. Installation Wazuh Manager
WAZUH_MANAGER="wazuh-manager" apt-get install -y wazuh-manager >/dev/null 2>&1

# 4. Copie configuration depuis dépôt Git
if [ -f "$PROJECT_ROOT/wazuh/manager.conf" ]; then
    cp /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.backup 2>/dev/null || true
    cp "$PROJECT_ROOT/wazuh/manager.conf" /var/ossec/etc/ossec.conf
    chown root:wazuh /var/ossec/etc/ossec.conf
    chmod 640 /var/ossec/etc/ossec.conf
fi

# 5. Copie règles depuis dépôt Git
if [ -f "$PROJECT_ROOT/wazuh/local_rules.xml" ]; then
    cp "$PROJECT_ROOT/wazuh/local_rules.xml" /var/ossec/etc/rules/local_rules.xml
    chown root:wazuh /var/ossec/etc/rules/local_rules.xml
    chmod 640 /var/ossec/etc/rules/local_rules.xml
fi

# 6. Configuration rsyslog pour PHP-Admin
cat > /etc/rsyslog.d/10-wazuh.conf <<'EOF'
module(load="imudp")
input(type="imudp" port="514")
EOF

cat > /etc/rsyslog.d/20-php-admin.conf <<'EOF'
:programname, isequal, "php-admin" /var/log/php-admin.log
& stop
EOF

touch /var/log/php-admin.log
chmod 644 /var/log/php-admin.log

cat > /etc/logrotate.d/php-admin <<'EOF'
/var/log/php-admin.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0644 root root
}
EOF

systemctl restart rsyslog >/dev/null 2>&1

# 7. Démarrage Wazuh Manager
systemctl daemon-reload
systemctl enable wazuh-manager >/dev/null 2>&1
systemctl start wazuh-manager >/dev/null 2>&1
sleep 5

# 8. Installation Wazuh Indexer
apt-get install -y wazuh-indexer >/dev/null 2>&1

cat > /etc/wazuh-indexer/opensearch.yml <<'EOF'
network.host: "127.0.0.1"
node.name: "wazuh-node"
cluster.name: "wazuh-cluster"
cluster.initial_master_nodes:
  - "wazuh-node"
plugins.security.disabled: true
path.data: /var/lib/wazuh-indexer
path.logs: /var/log/wazuh-indexer
EOF

chown wazuh-indexer:wazuh-indexer /etc/wazuh-indexer/opensearch.yml
chmod 640 /etc/wazuh-indexer/opensearch.yml

systemctl daemon-reload
systemctl enable wazuh-indexer >/dev/null 2>&1
systemctl start wazuh-indexer >/dev/null 2>&1
sleep 40

# 9. Installation Wazuh Dashboard
apt-get install -y wazuh-dashboard >/dev/null 2>&1

mkdir -p /etc/wazuh-dashboard/certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/wazuh-dashboard/certs/dashboard.key \
  -out /etc/wazuh-dashboard/certs/dashboard.crt \
  -subj "/C=FR/ST=IDF/L=Paris/O=SAE501/CN=localhost" >/dev/null 2>&1

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
opensearch.requestHeadersWhitelist: []
EOF

chown wazuh-dashboard:wazuh-dashboard /etc/wazuh-dashboard/opensearch_dashboards.yml
chmod 640 /etc/wazuh-dashboard/opensearch_dashboards.yml

systemctl daemon-reload
systemctl enable wazuh-dashboard >/dev/null 2>&1
systemctl start wazuh-dashboard >/dev/null 2>&1
sleep 30

# 10. Configuration pare-feu
if command -v ufw >/dev/null 2>&1; then
    ufw allow 443/tcp >/dev/null 2>&1 || true
    ufw allow 9200/tcp >/dev/null 2>&1 || true
    ufw allow 514/udp >/dev/null 2>&1 || true
    ufw allow 1514/tcp >/dev/null 2>&1 || true
fi

exit 0
