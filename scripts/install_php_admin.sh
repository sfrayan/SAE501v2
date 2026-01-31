#!/bin/bash

###############################################
# install_php_admin.sh
# Installation interface PHP-Admin pour gestion RADIUS
# Usage: sudo bash scripts/install_php_admin.sh
###############################################

set -e
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/var/log/install_php_admin_$(date +%Y%m%d_%H%M%S).log"

log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
log_ok()   { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[⚠]${NC} $1" | tee -a "$LOG_FILE"; }
log_err()  { echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"; exit 1; }

# Vérifier root
if [[ $EUID -ne 0 ]]; then
    log_err "Ce script doit être exécuté en tant que root (sudo)"
fi

echo -e "${BLUE}"
echo "╔════════════════════════════════════════╗"
echo "║  Installation PHP-Admin pour SAE 5.01  ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}\n"

# 1. Installer Apache + PHP
log_info "Installation Apache2 et PHP..."
apt-get install -y apache2 php php-mysql libapache2-mod-php \
    >> "$LOG_FILE" 2>&1
log_ok "Apache2 et PHP installés"

# 2. Copier PHP-Admin
log_info "Copie des fichiers PHP-Admin..."
if [[ -d "$PROJECT_ROOT/php-admin" ]]; then
    cp -r "$PROJECT_ROOT/php-admin" /var/www/html/
    log_ok "Fichiers copiés vers /var/www/html/php-admin"
else
    log_err "Répertoire php-admin non trouvé: $PROJECT_ROOT/php-admin"
fi

# 3. Configurer permissions
log_info "Configuration des permissions..."
chown -R www-data:www-data /var/www/html/php-admin
chmod -R 755 /var/www/html/php-admin
chmod -R 644 /var/www/html/php-admin/*.php
log_ok "Permissions configurées"

# 4. Activer Apache2
log_info "Activation d'Apache2..."
systemctl enable apache2 >> "$LOG_FILE" 2>&1
systemctl restart apache2 >> "$LOG_FILE" 2>&1

if systemctl is-active --quiet apache2; then
    log_ok "Apache2 en cours d'exécution"
else
    log_err "Erreur démarrage Apache2"
fi

# 5. Obtenir l'adresse IP
IP=$(hostname -I | awk '{print $1}')

# Résumé
echo -e "\n${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✓ Installation réussie!               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}\n"

echo "🌐 Accès PHP-Admin:"
echo "  http://localhost/php-admin/"
echo "  http://$IP/php-admin/"
echo ""
echo "📝 Voir les logs Apache:"
echo "  $ sudo tail -f /var/log/apache2/error.log"
echo ""
echo "🧪 Tester la connexion:"
echo "  $ curl http://localhost/php-admin/list_users.php"
echo ""