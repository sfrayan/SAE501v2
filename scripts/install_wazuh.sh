#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

[ "$EUID" -ne 0 ] && exit 1

apt-get update -qq >/dev/null 2>&1
apt-get install -y gnupg apt-transport-https curl rsyslog >/dev/null 2>&1

curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import >/dev/null 2>&1
chmod 644 /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list
apt-get update -qq >/dev/null 2>&1

WAZUH_MANAGER="wazuh-manager" apt-get install -y wazuh-manager >/dev/null 2>&1

if [ -f "$PROJECT_ROOT/wazuh/manager.conf" ]; then
    cp /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.backup 2>/dev/null || true
    cp "$PROJECT_ROOT/wazuh/manager.conf" /var/ossec/etc/ossec.conf
    chown root:wazuh /var/ossec/etc/ossec.conf
    chmod 640 /var/ossec/etc/ossec.conf
fi

if [ -f "$PROJECT_ROOT/wazuh/local_rules.xml" ]; then
    cp "$PROJECT_ROOT/wazuh/local_rules.xml" /var/ossec/etc/rules/local_rules.xml
    chown root:wazuh /var/ossec/etc/rules/local_rules.xml
    chmod 640 /var/ossec/etc/rules/local_rules.xml
fi

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

systemctl daemon-reload
systemctl enable wazuh-manager >/dev/null 2>&1
systemctl start wazuh-manager >/dev/null 2>&1
sleep 5

apt-get install -y wazuh-indexer >/dev/null 2>&1

cat > /etc/wazuh-indexer/opensearch.yml <<'EOF'
network.host: "127.0.0.1"
node.name: "wazuh-node"
cluster.name: "wazuh-cluster"
cluster.initial_master_nodes:
  - "wazuh-node"
path.data: /var/lib/wazuh-indexer
path.logs: /var/log/wazuh-indexer
EOF

chown wazuh-indexer:wazuh-indexer /etc/wazuh-indexer/opensearch.yml
chmod 640 /etc/wazuh-indexer/opensearch.yml

systemctl daemon-reload
systemctl enable wazuh-indexer >/dev/null 2>&1
systemctl start wazuh-indexer >/dev/null 2>&1
sleep 40

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
opensearch.username: "admin"
opensearch.password: "WazuhAdmin2026!"
EOF

chown wazuh-dashboard:wazuh-dashboard /etc/wazuh-dashboard/opensearch_dashboards.yml
chmod 640 /etc/wazuh-dashboard/opensearch_dashboards.yml

systemctl daemon-reload
systemctl enable wazuh-dashboard >/dev/null 2>&1
systemctl start wazuh-dashboard >/dev/null 2>&1
sleep 30

if command -v ufw >/dev/null 2>&1; then
    ufw --force enable >/dev/null 2>&1
    ufw allow 22/tcp comment 'SSH' >/dev/null 2>&1
    ufw allow 443/tcp comment 'Wazuh Dashboard HTTPS' >/dev/null 2>&1
    ufw allow 1812/udp comment 'RADIUS Auth' >/dev/null 2>&1
    ufw allow 1813/udp comment 'RADIUS Accounting' >/dev/null 2>&1
    ufw allow 514/udp comment 'Syslog' >/dev/null 2>&1
    ufw allow 1514/tcp comment 'Wazuh Agent' >/dev/null 2>&1
    ufw reload >/dev/null 2>&1
fi

cat > /root/wazuh-credentials.txt <<'EOF'
╔════════════════════════════════════════╗
║       WAZUH - INFORMATIONS ACCÈS       ║
╚════════════════════════════════════════╝

URL Dashboard:
  https://IP-DE-VOTRE-VM:443
  https://localhost:443

Identifiants par défaut:
  Username: admin
  Password: WazuhAdmin2026!

Ports UFW ouverts:
  - 22/tcp    → SSH
  - 443/tcp   → Wazuh Dashboard HTTPS
  - 1812/udp  → RADIUS Authentification
  - 1813/udp  → RADIUS Accounting
  - 514/udp   → Syslog (logs TL-MR100)
  - 1514/tcp  → Wazuh Agent

Commandes utiles:
  Statut services:
    systemctl status wazuh-manager
    systemctl status wazuh-indexer
    systemctl status wazuh-dashboard

  Logs:
    tail -f /var/ossec/logs/ossec.log
    tail -f /var/log/wazuh-indexer/wazuh-cluster.log

  Pare-feu:
    ufw status verbose

NOTE IMPORTANTE:
  - Certificat auto-signé: accepter l'exception
    dans le navigateur lors de la première connexion
  - Pour changer le mot de passe admin:
    /usr/share/wazuh-indexer/bin/hash-password.sh

╚════════════════════════════════════════╝
EOF

chmod 600 /root/wazuh-credentials.txt

exit 0
