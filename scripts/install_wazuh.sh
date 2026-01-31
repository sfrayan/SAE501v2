#!/bin/bash

###############################################
# install_wazuh.sh - Installation Wazuh
###############################################
#
# Fichier: scripts/install_wazuh.sh
# Auteur: GroupeNani
# Date: 31 janvier 2026
# Version: 1.3 (Final)
#
# Description:
#   Script d'installation et configuration automatique de Wazuh Manager
#   pour la surveillance sécurité SAE 5.01.
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
        log_warning "RAM disponible: ${AVAILABLE_RAM}GB (4GB recommandé)"
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

install_wazuh() {
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
    log_info "Configuration rsyslog..."
    if ! command -v rsyslogd &> /dev/null; then
        apt-get install -y rsyslog >> "$LOG_FILE" 2>&1
    fi
    cat > /etc/rsyslog.d/10-wazuh.conf <<'EOF'
module(load="imudp")
input(type="imudp" port="514")
EOF
    systemctl restart rsyslog >> "$LOG_FILE" 2>&1
    log_success "rsyslog configuré"
}

test_syntax() {
    log_info "Vérification de la configuration..."
    systemctl stop wazuh-manager >> "$LOG_FILE" 2>&1 || true
    if /var/ossec/bin/wazuh-control start >> "$LOG_FILE" 2>&1; then
        sleep 2
        if pgrep -x "wazuh-analysisd" > /dev/null; then
            log_success "Configuration valide - Wazuh démarré"
            /var/ossec/bin/wazuh-control stop >> "$LOG_FILE" 2>&1 || true
            return 0
        fi
    fi
    log_error "Erreur de configuration"
    return 1
}

start_service() {
    log_info "Démarrage de Wazuh..."
    systemctl enable wazuh-manager >> "$LOG_FILE" 2>&1
    systemctl start wazuh-manager >> "$LOG_FILE" 2>&1
    sleep 5
    if systemctl is-active --quiet wazuh-manager; then
        log_success "Wazuh Manager en cours d'exécution"
    else
        log_error "Erreur au démarrage"
        return 1
    fi
}

verify_installation() {
    log_info "Vérification de l'installation..."
    WAZUH_VERSION=$(/var/ossec/bin/wazuh-control info 2>/dev/null | grep "WAZUH_VERSION" | cut -d'=' -f2 | tr -d '"' || echo "Inconnue")
    log_success "Version Wazuh: $WAZUH_VERSION"
    if pgrep -x "wazuh-analysisd" > /dev/null; then
        log_success "Processus wazuh-analysisd actif"
    fi
}

###############################################
# MAIN
###############################################

main() {
    log_info "╔════════════════════════════════════════╗"
    log_info "║  SAE 5.01 - Installation Wazuh (v1.3)  ║"
    log_info "║  $(date +"%Y-%m-%d %H:%M:%S")           ║"
    log_info "╚════════════════════════════════════════╝"
    log_info "Log: $LOG_FILE"
    
    check_root
    check_resources
    add_wazuh_repo
    install_wazuh
    import_config
    import_rules
    configure_rsyslog
    
    if ! test_syntax; then
        log_error "Installation incomplète"
        exit 1
    fi
    
    start_service
    verify_installation
    
    log_success "╔════════════════════════════════════════╗"
    log_success "║  ✓ INSTALLATION RÉUSSIE               ║"
    log_success "╚════════════════════════════════════════╝"
}

main "$@"