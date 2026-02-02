#!/bin/bash
#
# hardening.sh - Script complet de hardening SAE 5.01
#
# Sécurise le serveur RADIUS:
# - SSH: Authentification par clés uniquement, désactivation root
# - UFW: Firewall avec règles strictes
# - Fail2Ban: Protection anti brute-force
# - Permissions: FreeRADIUS, MySQL, Apache
#

set -e

SSH_PORT=${SSH_PORT:-22}
LAN_NETWORK="192.168.10.0/24"
RADIUS_SECRET="testing123"

echo "═══════════════════════════════════════════════════════════════"
echo "🔒 HARDENING COMPLET SAE 5.01"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Ce script va sécuriser le serveur en 4 étapes:"
echo "  1. 🔐 Hardening SSH (authentification par clés uniquement)"
echo "  2. 🛡️  Configuration Firewall UFW"
echo "  3. 🚫 Protection Fail2Ban (anti brute-force)"
echo "  4. 🔒 Permissions fichiers"
echo ""
read -p "Continuer? (o/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Oo]$ ]]; then
    echo "Annulé."
    exit 0
fi

# Vérifier root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ce script doit être exécuté en root (sudo)"
  exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "ÉTAPE 1/4: HARDENING SSH"
echo "═══════════════════════════════════════════════════════════════"
echo ""

SSHD_CONFIG="/etc/ssh/sshd_config"

# Backup configuration
echo "[1.1] Backup configuration SSH..."
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
echo "  ✅ Backup créé"

# Vérifier qu'une clé SSH existe
echo "[1.2] Vérification clés SSH..."
CURRENT_USER=$(logname 2>/dev/null || echo $SUDO_USER)
if [ -n "$CURRENT_USER" ] && [ -d "/home/$CURRENT_USER/.ssh" ]; then
    if [ -f "/home/$CURRENT_USER/.ssh/authorized_keys" ]; then
        echo "  ✅ Clés SSH trouvées pour $CURRENT_USER"
    else
        echo "  ⚠️  ATTENTION: Aucune clé SSH trouvée!"
        echo "  ⚠️  Créez une clé SSH AVANT de désactiver l'authentification par mot de passe:"
        echo "      Sur votre PC:"
        echo "        ssh-keygen -t ed25519 -f ~/.ssh/sae501_key"
        echo "        ssh-copy-id -i ~/.ssh/sae501_key.pub $CURRENT_USER@192.168.10.100"
        read -p "Continuer quand même? (o/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Oo]$ ]]; then
            exit 1
        fi
    fi
fi

# Configuration SSH durcie
echo "[1.3] Application configuration sécurisée..."

# Port SSH
sed -i "s/^#*Port .*/Port $SSH_PORT/" "$SSHD_CONFIG"

# Désactiver connexion root
sed -i "s/^#*PermitRootLogin .*/PermitRootLogin no/" "$SSHD_CONFIG"

# Authentification par clés uniquement
sed -i "s/^#*PubkeyAuthentication .*/PubkeyAuthentication yes/" "$SSHD_CONFIG"
sed -i "s/^#*PasswordAuthentication .*/PasswordAuthentication no/" "$SSHD_CONFIG"
sed -i "s/^#*ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/" "$SSHD_CONFIG"
sed -i "s/^#*UsePAM .*/UsePAM no/" "$SSHD_CONFIG"

# Désactiver authentifications dangereuses
sed -i "s/^#*PermitEmptyPasswords .*/PermitEmptyPasswords no/" "$SSHD_CONFIG"
sed -i "s/^#*HostbasedAuthentication .*/HostbasedAuthentication no/" "$SSHD_CONFIG"

# Protocole SSH v2 uniquement
if ! grep -q "^Protocol 2" "$SSHD_CONFIG"; then
    echo "Protocol 2" >> "$SSHD_CONFIG"
fi

# Algorithmes cryptographiques forts
if ! grep -q "^Ciphers" "$SSHD_CONFIG"; then
    echo "Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr" >> "$SSHD_CONFIG"
fi

if ! grep -q "^MACs" "$SSHD_CONFIG"; then
    echo "MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256" >> "$SSHD_CONFIG"
fi

if ! grep -q "^KexAlgorithms" "$SSHD_CONFIG"; then
    echo "KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256" >> "$SSHD_CONFIG"
fi

# Limitation tentatives
sed -i "s/^#*MaxAuthTries .*/MaxAuthTries 3/" "$SSHD_CONFIG"
sed -i "s/^#*MaxSessions .*/MaxSessions 2/" "$SSHD_CONFIG"

# Timeout session
sed -i "s/^#*ClientAliveInterval .*/ClientAliveInterval 300/" "$SSHD_CONFIG"
sed -i "s/^#*ClientAliveCountMax .*/ClientAliveCountMax 2/" "$SSHD_CONFIG"

# Désactiver X11 forwarding
sed -i "s/^#*X11Forwarding .*/X11Forwarding no/" "$SSHD_CONFIG"

echo "  ✅ Configuration SSH durcie"

# Bannière de connexion
echo "[1.4] Configuration bannière..."
cat > /etc/ssh/banner <<'BANNER'
╔══════════════════════════════════════════════════════════╗
║                    AVERTISSEMENT                         ║
║                                                          ║
║  Accès réservé aux utilisateurs autorisés uniquement    ║
║  Toute tentative d'accès non autorisé sera journalisée  ║
║  et poursuivie conformément à la loi.                    ║
║                                                          ║
║  SAE 5.01 - Architecture Wi-Fi Sécurisée                ║
╚══════════════════════════════════════════════════════════╝
BANNER

if ! grep -q "^Banner" "$SSHD_CONFIG"; then
    echo "Banner /etc/ssh/banner" >> "$SSHD_CONFIG"
fi

echo "  ✅ Bannière configurée"

# Vérification configuration
echo "[1.5] Vérification configuration SSH..."
if sshd -t 2>/dev/null; then
    echo "  ✅ Configuration SSH valide"
else
    echo "  ❌ Erreur de configuration SSH"
    sshd -t
    exit 1
fi

# Redémarrage SSH
echo "[1.6] Redémarrage service SSH..."
systemctl restart ssh

if systemctl is-active --quiet ssh; then
    echo "  ✅ SSH redémarré avec succès"
else
    echo "  ❌ Erreur au redémarrage SSH"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "ÉTAPE 2/4: CONFIGURATION FIREWALL UFW"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Installation UFW
echo "[2.1] Installation UFW..."
if ! command -v ufw &> /dev/null; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y ufw > /dev/null 2>&1
    echo "  ✅ UFW installé"
else
    echo "  ✅ UFW déjà installé"
fi

# Réinitialisation UFW
echo "[2.2] Réinitialisation UFW..."
ufw --force reset > /dev/null 2>&1
echo "  ✅ UFW réinitialisé"

# Politique par défaut: DENY
echo "[2.3] Configuration politique par défaut..."
ufw default deny incoming
ufw default allow outgoing
ufw default deny routed
echo "  ✅ Politique: DENY incoming, ALLOW outgoing"

# Règles d'accès
echo "[2.4] Configuration règles d'accès..."

# SSH - Limité pour éviter brute force
echo "  → SSH (port $SSH_PORT) avec limitation"
ufw limit $SSH_PORT/tcp comment 'SSH with rate limiting'

# RADIUS - Depuis le LAN uniquement
echo "  → RADIUS (1812/UDP) depuis LAN"
ufw allow from $LAN_NETWORK to any port 1812 proto udp comment 'RADIUS authentication'

# HTTP/HTTPS - Pour PHP-Admin (depuis LAN)
echo "  → HTTP (80/TCP) depuis LAN"
ufw allow from $LAN_NETWORK to any port 80 proto tcp comment 'PHP-Admin HTTP'

echo "  → HTTPS (443/TCP) depuis LAN"
ufw allow from $LAN_NETWORK to any port 443 proto tcp comment 'PHP-Admin HTTPS'

# Syslog - Depuis routeur uniquement
echo "  → Syslog (514/UDP) depuis routeur"
ufw allow from 192.168.10.1 to any port 514 proto udp comment 'Syslog from router'

# Wazuh - Local uniquement (docker)
echo "  → Wazuh (1514/UDP) local"
ufw allow from 127.0.0.1 to any port 1514 proto udp comment 'Wazuh local'

# MySQL - Local uniquement (sécurité renforcée)
echo "  → MySQL (3306/TCP) local uniquement"
ufw deny from any to any port 3306 comment 'MySQL blocked externally'

# Loopback
echo "  → Interface loopback (lo)"
ufw allow in on lo
ufw allow out on lo

# Log des paquets bloqués
echo "[2.5] Activation logging..."
ufw logging medium
echo "  ✅ Logging: medium (logs dans /var/log/ufw.log)"

# Activation UFW
echo "[2.6] Activation UFW..."
ufw --force enable > /dev/null 2>&1

if ufw status | grep -q "Status: active"; then
    echo "  ✅ UFW activé"
else
    echo "  ❌ Erreur activation UFW"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "ÉTAPE 3/4: PROTECTION FAIL2BAN"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Installation fail2ban
echo "[3.1] Installation Fail2Ban..."
if ! command -v fail2ban-client &> /dev/null; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban > /dev/null 2>&1
    echo "  ✅ Fail2Ban installé"
else
    echo "  ✅ Fail2Ban déjà installé"
fi

# Configuration Fail2Ban pour SSH
echo "[3.2] Configuration Fail2Ban..."
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = $SSH_PORT
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200
EOF

systemctl enable fail2ban > /dev/null 2>&1
systemctl restart fail2ban

echo "  ✅ Fail2Ban configuré (3 tentatives max, ban 2h)"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "ÉTAPE 4/4: PERMISSIONS FICHIERS"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# FreeRADIUS
echo "[4.1] Permissions FreeRADIUS..."
if [ -d /etc/freeradius/3.0 ]; then
    chown -R root:freerad /etc/freeradius/3.0
    chmod -R 750 /etc/freeradius/3.0
    chmod 640 /etc/freeradius/3.0/clients.conf 2>/dev/null || true
    chmod 640 /etc/freeradius/3.0/users 2>/dev/null || true
    echo "  ✅ Permissions FreeRADIUS configurées"
else
    echo "  ⚠️  FreeRADIUS non trouvé"
fi

# MySQL
echo "[4.2] Permissions MySQL..."
if [ -d /var/lib/mysql ]; then
    chown -R mysql:mysql /var/lib/mysql
    chmod 700 /var/lib/mysql
    echo "  ✅ Permissions MySQL configurées"
else
    echo "  ⚠️  MySQL non trouvé"
fi

# Apache/PHP
echo "[4.3] Permissions Apache/PHP..."
if [ -d /var/www/html/php-admin ]; then
    chown -R www-data:www-data /var/www/html/php-admin
    chmod -R 750 /var/www/html/php-admin
    echo "  ✅ Permissions PHP-Admin configurées"
else
    echo "  ⚠️  PHP-Admin non trouvé"
fi

# Logs
echo "[4.4] Permissions logs..."
if [ -d /var/log/freeradius ]; then
    chown -R freerad:freerad /var/log/freeradius
    chmod 750 /var/log/freeradius
    chmod 640 /var/log/freeradius/*.log 2>/dev/null || true
    echo "  ✅ Permissions logs FreeRADIUS configurées"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ HARDENING COMPLET TERMINÉ"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "📋 Résumé de la sécurisation:"
echo ""
echo "🔐 SSH:"
echo "  ✅ Port: $SSH_PORT"
echo "  ✅ Authentification: Clés SSH uniquement"
echo "  ✅ Connexion root: Désactivée"
echo "  ✅ Tentatives max: 3"
echo "  ✅ Timeout session: 10 min"
echo "  ✅ Algorithmes: Cryptographie forte"
echo ""
echo "🛡️  Firewall UFW:"
echo "  ✅ SSH ($SSH_PORT/TCP) - Rate limited"
echo "  ✅ RADIUS (1812/UDP) - LAN uniquement"
echo "  ✅ HTTP (80/TCP) - LAN uniquement"
echo "  ✅ Syslog (514/UDP) - Routeur uniquement"
echo "  ❌ MySQL (3306/TCP) - Bloqué externalement"
echo "  ✅ Politique par défaut: DENY"
echo ""
echo "🚫 Fail2Ban:"
echo "  ✅ Protection SSH active"
echo "  ✅ Max tentatives: 3"
echo "  ✅ Durée ban: 2 heures"
echo ""
echo "🔒 Permissions:"
echo "  ✅ FreeRADIUS: root:freerad (750)"
echo "  ✅ MySQL: mysql:mysql (700)"
echo "  ✅ PHP-Admin: www-data:www-data (750)"
echo "  ✅ Logs: freerad:freerad (640)"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "⚠️  IMPORTANT - VÉRIFICATIONS IMMÉDIATES:"
echo ""
echo "1. 🧪 Testez SSH dans un NOUVEAU terminal (NE FERMEZ PAS CELUI-CI!):"
echo "   ssh -i ~/.ssh/sae501_key $CURRENT_USER@192.168.10.100"
echo ""
echo "   Si le test échoue:"
echo "   - Restaurez la config: sudo cp ${SSHD_CONFIG}.backup.* $SSHD_CONFIG"
echo "   - Redémarrez SSH: sudo systemctl restart ssh"
echo ""
echo "2. 🔍 Vérifiez le firewall:"
echo "   sudo ufw status verbose"
echo ""
echo "3. 📊 Consultez les logs:"
echo "   sudo fail2ban-client status sshd"
echo "   sudo tail -f /var/log/auth.log"
echo "   sudo tail -f /var/log/ufw.log"
echo ""
echo "4. 🧪 Lancez les tests de sécurité:"
echo "   cd ~/SAE501v2/tests"
echo "   sudo bash security_tests.sh"
echo ""
echo "📚 Documentation:"
echo "  docs/hardening-linux.md"
echo "═══════════════════════════════════════════════════════════════"

exit 0
