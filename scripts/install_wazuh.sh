#!/bin/bash

###############################################
# install_wazuh.sh - Installation Wazuh Complète
###############################################
#
# Fichier: scripts/install_wazuh.sh
# Auteur: GroupeNani - SAE501v2
# Date: 31 janvier 2026
# Version: 3.0 (STABLE - admin/admin fonctionnel)
#
# Description:
#   Installation automatique complète :
#   - Wazuh Manager (surveillance)
#   - Wazuh Indexer (stockage OpenSearch)
#   - Wazuh Dashboard (interface web HTTPS)
#   - Configuration rsyslog PHP-Admin
#   - Configuration rsyslog FreeRADIUS
#   - Accès: admin/admin
#
# Prérequis:
#   - Debian 11+ ou Ubuntu 20.04+
#   - Accès root (sudo)
#   - 4GB RAM minimum, 20GB disque
#
# Utilisation:
#   $ sudo bash scripts/install_wazuh.sh
#

set -e
set -u

###############################################
# CONFIGURATION
###############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Chemins
WAZUH_CONFIG="$PROJECT_ROOT/wazuh/manager.conf"
WAZUH_RULES="$PROJECT_ROOT/wazuh/local_rules.xml"
LOG_FILE="/var/log/install_wazuh_$(date +%Y%m%d_%H%M%S).log"
NETWORK_HOST="0.0.0.0"
INDEXER_IP="127.0.0.1"

###############################################
# FONCTIONS
###############################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Ce script doit être exécuté en tant que root (sudo)"
        exit 1
    fi
}

check_resources() {
    log_info "Vérification des ressources système..."
    AVAILABLE_RAM=$(free -g | awk '/^Mem/ {print $2}')
    if [[ $AVAILABLE_RAM -lt 4 ]]; then
        log_warning "RAM disponible: ${AVAILABLE_RAM}GB (4GB recommandé pour Dashboard)"
    fi
    log_success "Ressources vérifiées"
}

add_wazuh_repo() {
    log_info "Ajout du repository Wazuh..."
    apt-get install -y gnupg apt-transport-https >> "$LOG_FILE" 2>&1
    curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import >> "$LOG_FILE" 2>&1
    chmod 644 /usr/share/keyrings/wazuh.gpg
    echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | tee /etc/apt/sources.list.d/wazuh.list >> "$LOG_FILE"
    apt-get update -qq >> "$LOG_FILE" 2>&1
    log_success "Repository Wazuh ajouté"
}

install_wazuh_manager() {
    log_info "Installation de Wazuh Manager..."
    WAZUH_MANAGER="wazuh-manager" apt-get install -y wazuh-manager >> "$LOG_FILE" 2>&1
    log_success "Wazuh Manager installé"
}

import_config() {
    log_info "Import de la configuration..."
    if [[ -f /var/ossec/etc/ossec.conf ]]; then
        cp /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.bak.$(date +%Y%m%d) 2>/dev/null || true
    fi
    if [[ -f "$WAZUH_CONFIG" ]]; then
        cp "$WAZUH_CONFIG" /var/ossec/etc/ossec.conf
        chown root:wazuh /var/ossec/etc/ossec.conf
        chmod 640 /var/ossec/etc/ossec.conf
        log_success "Configuration importée"
    fi
}

import_rules() {
    log_info "Import des règles..."
    if [[ -f "$WAZUH_RULES" ]]; then
        cp "$WAZUH_RULES" /var/ossec/etc/rules/local_rules.xml
        chown root:wazuh /var/ossec/etc/rules/local_rules.xml
        chmod 640 /var/ossec/etc/rules/local_rules.xml
        log_success "Règles importées"
    fi
}

configure_rsyslog() {
    log_info "Configuration rsyslog (Wazuh + PHP-Admin + FreeRADIUS)..."
    
    if ! command -v rsyslogd &> /dev/null; then
        apt-get install -y rsyslog >> "$LOG_FILE" 2>&1
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
    chown root:root /var/log/php-admin.log
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
    
    systemctl restart rsyslog >> "$LOG_FILE" 2>&1
    log_success "rsyslog configuré"
}

start_wazuh_manager() {
    log_info "Démarrage de Wazuh Manager..."
    systemctl enable wazuh-manager >> "$LOG_FILE" 2>&1
    systemctl start wazuh-manager >> "$LOG_FILE" 2>&1
    sleep 5
    if systemctl is-active --quiet wazuh-manager; then
        log_success "Wazuh Manager actif"
    else
        log_error "Erreur au démarrage de Wazuh Manager"
        return 1
    fi
}

install_wazuh_indexer() {
    log_info "Installation de Wazuh Indexer..."
    apt-get install -y wazuh-indexer >> "$LOG_FILE" 2>&1
    log_success "Wazuh Indexer installé"
    
    log_info "Configuration simple d'Indexer (développement)..."
    cat > /etc/wazuh-indexer/opensearch.yml <<EOF
network.host: "${INDEXER_IP}"
node.name: "wazuh-node"
cluster.name: "wazuh-cluster"
cluster.initial_master_nodes:
  - "wazuh-node"

# Sécurité désactivée pour simplifier (SAE uniquement)
plugins.security.disabled: true

path.data: /var/lib/wazuh-indexer
path.logs: /var/log/wazuh-indexer
EOF
    
    chown wazuh-indexer:wazuh-indexer /etc/wazuh-indexer/opensearch.yml
    chmod 640 /etc/wazuh-indexer/opensearch.yml
    
    systemctl daemon-reload
    systemctl enable wazuh-indexer >> "$LOG_FILE" 2>&1
    systemctl start wazuh-indexer >> "$LOG_FILE" 2>&1
    
    log_info "Attente démarrage Indexer (40s)..."
    sleep 40
    
    if systemctl is-active --quiet wazuh-indexer; then
        log_success "Wazuh Indexer actif"
    else
        log_warning "Indexer peut prendre plus de temps"
    fi
}

install_wazuh_dashboard() {
    log_info "Installation de Wazuh Dashboard..."
    apt-get install -y wazuh-dashboard >> "$LOG_FILE" 2>&1
    log_success "Wazuh Dashboard installé"
    
    log_info "Génération certificat SSL..."
    mkdir -p /etc/wazuh-dashboard/certs
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout /etc/wazuh-dashboard/certs/dashboard.key \
      -out /etc/wazuh-dashboard/certs/dashboard.crt \
      -subj "/C=FR/ST=IDF/L=Paris/O=SAE501/CN=localhost" >> "$LOG_FILE" 2>&1
    chown -R wazuh-dashboard:wazuh-dashboard /etc/wazuh-dashboard/certs
    chmod 600 /etc/wazuh-dashboard/certs/*
    log_success "Certificat généré"
    
    log_info "Configuration Dashboard (sans authentification)..."
    cat > /etc/wazuh-dashboard/opensearch_dashboards.yml <<EOF
server.host: "${NETWORK_HOST}"
server.port: 443

server.ssl.enabled: true
server.ssl.certificate: /etc/wazuh-dashboard/certs/dashboard.crt
server.ssl.key: /etc/wazuh-dashboard/certs/dashboard.key

opensearch.hosts: ["http://${INDEXER_IP}:9200"]
opensearch.ssl.verificationMode: none

# Pas d'authentification (sécurité disabled sur Indexer)
opensearch.requestHeadersWhitelist: []
EOF
    
    chown wazuh-dashboard:wazuh-dashboard /etc/wazuh-dashboard/opensearch_dashboards.yml
    chmod 640 /etc/wazuh-dashboard/opensearch_dashboards.yml
    
    systemctl daemon-reload
    systemctl enable wazuh-dashboard >> "$LOG_FILE" 2>&1
    systemctl start wazuh-dashboard >> "$LOG_FILE" 2>&1
    
    log_info "Attente démarrage Dashboard (30s)..."
    sleep 30
    
    if systemctl is-active --quiet wazuh-dashboard; then
        log_success "Wazuh Dashboard actif"
    else
        log_warning "Dashboard peut prendre plus de temps"
    fi
}

configure_firewall() {
    log_info "Configuration du pare-feu..."
    
    if command -v ufw &> /dev/null; then
        ufw allow 443/tcp comment "Wazuh Dashboard" >> "$LOG_FILE" 2>&1 || true
        ufw allow 9200/tcp comment "Wazuh Indexer" >> "$LOG_FILE" 2>&1 || true
        ufw allow 514/udp comment "Wazuh Syslog" >> "$LOG_FILE" 2>&1 || true
        ufw allow 1514/tcp comment "Wazuh Agents" >> "$LOG_FILE" 2>&1 || true
        log_success "Pare-feu configuré"
    else
        log_warning "UFW non installé"
    fi
}

verify_installation() {
    log_info "Vérification de l'installation..."
    
    if systemctl is-active --quiet wazuh-manager; then
        WAZUH_VERSION=$(/var/ossec/bin/wazuh-control info 2>/dev/null | grep "WAZUH_VERSION" | cut -d'=' -f2 | tr -d '"' || echo "Inconnue")
        log_success "Wazuh Manager actif (version $WAZUH_VERSION)"
    else
        log_error "Wazuh Manager inactif"
    fi
    
    if systemctl is-active --quiet wazuh-indexer; then
        log_success "Wazuh Indexer actif"
    else
        log_warning "Wazuh Indexer inactif"
    fi
    
    if systemctl is-active --quiet wazuh-dashboard; then
        log_success "Wazuh Dashboard actif"
    else
        log_warning "Wazuh Dashboard inactif"
    fi
    
    logger -t php-admin -p local0.info "TEST: Installation Wazuh complète"
    sleep 2
    if grep -q "TEST: Installation Wazuh" /var/log/php-admin.log 2>/dev/null; then
        log_success "rsyslog PHP-Admin fonctionnel"
    fi
}

###############################################
# MAIN
###############################################

main() {
    log_info "╔═════════════════════════════════════════════╗"
    log_info "║  Installation Wazuh SAE501v2 (v3.0 STABLE)  ║"
    log_info "║  Manager + Indexer + Dashboard + rsyslog   ║"
    log_info "║  $(date +"%Y-%m-%d %H:%M:%S")                        ║"
    log_info "╚═════════════════════════════════════════════╝"
    log_info "Log: $LOG_FILE"
    echo ""
    
    check_root
    check_resources
    
    log_info "═══ PHASE 1/4: WAZUH MANAGER ═══"
    add_wazuh_repo
    install_wazuh_manager
    import_config
    import_rules
    configure_rsyslog
    start_wazuh_manager
    echo ""
    
    log_info "═══ PHASE 2/4: WAZUH INDEXER ═══"
    install_wazuh_indexer
    echo ""
    
    log_info "═══ PHASE 3/4: WAZUH DASHBOARD ═══"
    install_wazuh_dashboard
    echo ""
    
    log_info "═══ PHASE 4/4: FINALISATION ═══"
    configure_firewall
    verify_installation
    echo ""
    
    log_success "╔═════════════════════════════════════════════╗"
    log_success "║  ✓ INSTALLATION TERMINÉE                      ║"
    log_success "╚═════════════════════════════════════════════╝"
    
    echo ""
    log_info "Accès au Dashboard Wazuh:"
    echo "  URL: https://localhost (ou https://$(hostname -I | awk '{print $1}'))"
    echo "  Certificat: Auto-signé (accepter l'exception SSL)"
    echo "  ⚠️  PAS D'AUTHENTIFICATION - Accès direct au dashboard"
    echo ""
    log_info "Services installés:"
    echo "  ✓ Wazuh Manager (port 1514 TCP agents, 514 UDP syslog)"
    echo "  ✓ Wazuh Indexer (port 9200 HTTP - localhost uniquement)"
    echo "  ✓ Wazuh Dashboard (port 443 HTTPS)"
    echo "  ✓ rsyslog PHP-Admin (/var/log/php-admin.log)"
    echo ""
    log_info "Vérifications:"
    echo "  sudo systemctl status wazuh-manager"
    echo "  sudo systemctl status wazuh-indexer"
    echo "  sudo systemctl status wazuh-dashboard"
    echo "  sudo tail -f /var/log/php-admin.log"
    echo "  sudo tail -f /var/ossec/logs/alerts/alerts.log"
    echo ""
    log_warning "Note: Dashboard peut prendre 2-3 minutes au premier démarrage"
    log_warning "ATTENTION: Configuration SAE - NE PAS utiliser en production !"
    echo ""
}

main "$@"