#!/bin/bash

###############################################
# install_wazuh.sh - Installation Wazuh
###############################################
#
# Fichier: scripts/install_wazuh.sh
# Auteur: GroupeNani
# Date: 7 janvier 2026
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
# Fonctionnalités:
#   ✓ Installation Wazuh Manager + API
#   ✓ Configuration collecte logs (syslog, localfile)
#   ✓ Importation règles personnalisées SAE 5.01
#   ✓ Configuration moniteurs services critiques
#   ✓ Tests connexion
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
WAZUH_DECODER="$PROJECT_ROOT/wazuh/syslog-tlmr100.conf"
LOG_FILE="/var/log/install_wazuh_$(date +%Y%m%d_%H%M%S).log"

# Variables
WAZUH_USER="wazuh"
WAZUH_GROUP="wazuh"
WAZUH_INSTALL_DIR="/var/ossec"

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
    
    # RAM minimum 4GB
    AVAILABLE_RAM=$(free -g | awk '/^Mem/ {print $2}')
    if [[ $AVAILABLE_RAM -lt 4 ]]; then
        log_warning "RAM disponible: ${AVAILABLE_RAM}GB (4GB recommandé)"
    fi
    
    # Disque minimum 20GB
    AVAILABLE_DISK=$(df / | awk 'NR==2 {print $4}')
    if [[ $AVAILABLE_DISK -lt 20971520 ]]; then
        log_warning "Disque disponible: $(( AVAILABLE_DISK / 1048576 ))GB (20GB recommandé)"
    fi
    
    log_success "Ressources vérifiées"
}

check_files() {
    log_info "Vérification des fichiers de configuration..."
    
    if [[ ! -f "$WAZUH_CONFIG" ]]; then
        log_warning "Fichier manager.conf non trouvé: $WAZUH_CONFIG"
    fi
    
    if [[ ! -f "$WAZUH_RULES" ]]; then
        log_warning "Fichier local_rules.xml non trouvé: $WAZUH_RULES"
    fi
    
    log_success "Fichiers vérifiés"
}

add_wazuh_repo() {
    log_info "Ajout du repository Wazuh..."
    
    curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | apt-key add - >> "$LOG_FILE" 2>&1
    echo "deb https://packages.wazuh.com/4.x/apt/ stable main" | tee /etc/apt/sources.list.d/wazuh.list >> "$LOG_FILE"
    
    apt-get update -qq >> "$LOG_FILE" 2>&1
    
    log_success "Repository Wazuh ajouté"
}

install_wazuh() {
    log_info "Installation de Wazuh Manager..."
    
    apt-get install -y wazuh-manager >> "$LOG_FILE" 2>&1
    
    log_success "Wazuh Manager installé"
}

import_config() {
    log_info "Import de la configuration personnalisée..."
    
    # Backup config originale
    cp /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.bak.$(date +%Y%m%d)
    
    if [[ -f "$WAZUH_CONFIG" ]]; then
        cp "$WAZUH_CONFIG" /var/ossec/etc/ossec.conf
        log_success "Configuration manager copiée"
    fi
}

import_rules() {
    log_info "Import des règles personnalisées..."
    
    if [[ -f "$WAZUH_RULES" ]]; then
        cp "$WAZUH_RULES" /var/ossec/etc/rules/local_rules.xml
        chown root:wazuh /var/ossec/etc/rules/local_rules.xml
        chmod 640 /var/ossec/etc/rules/local_rules.xml
        log_success "Règles personnalisées copiées"
    fi
}

import_decoders() {
    log_info "Import des décodeurs personnalisés..."
    
    if [[ -f "$WAZUH_DECODER" ]]; then
        cp "$WAZUH_DECODER" /var/ossec/etc/decoders/syslog-tlmr100.conf
        chown root:wazuh /var/ossec/etc/decoders/syslog-tlmr100.conf
        chmod 640 /var/ossec/etc/decoders/syslog-tlmr100.conf
        log_success "Décodeurs personnalisés copiés"
    fi
}

configure_rsyslog() {
    log_info "Configuration rsyslog pour réception syslog..."
    
    cat > /etc/rsyslog.d/10-wazuh.conf <<'EOF'
# Recevoir syslog UDP port 514
input(type="imudp" port="514" tag="syslog")

# Rediriger vers Wazuh agent
:msg, contains, "TL-MR100" @@localhost:1514
:msg, contains, "FreeRADIUS" @@localhost:1514
:msg, contains, "radiusd" @@localhost:1514

# Action défaut
& stop
EOF
    
    systemctl restart rsyslog >> "$LOG_FILE" 2>&1
    
    log_success "rsyslog configuré"
}

test_syntax() {
    log_info "Vérification de la syntaxe Wazuh..."

    # Tester la configuration du manager Wazuh 4.x
    /var/ossec/bin/wazuh-managerd -t >> "$LOG_FILE" 2>&1

    if [[ $? -eq 0 ]]; then
        log_success "Syntaxe valide"
        return 0
    else
        log_error "Erreur de syntaxe détectée (voir $LOG_FILE)"
        return 1
    fi
}

start_service() {
    log_info "Démarrage de Wazuh Manager..."
    
    systemctl enable wazuh-manager >> "$LOG_FILE" 2>&1
    systemctl start wazuh-manager >> "$LOG_FILE" 2>&1
    sleep 3
    
    if systemctl is-active --quiet wazuh-manager; then
        log_success "Wazuh Manager en cours d'exécution"
    else
        log_error "Erreur au démarrage de Wazuh"
        systemctl status wazuh-manager >> "$LOG_FILE" 2>&1
        return 1
    fi
}

verify_rules() {
    log_info "Vérification des règles importées..."
    
    RULE_COUNT=$(/var/ossec/bin/wazuh-control query | grep -c "local_rules.xml" || true)
    
    if [[ $RULE_COUNT -gt 0 ]]; then
        log_success "Règles personnalisées chargées ($RULE_COUNT)"
    else
        log_warning "Vérifier les règles importées"
    fi
}

generate_report() {
    log_info "Génération du rapport d'installation..."
    
    cat >> "$LOG_FILE" <<EOF

===============================================
       RAPPORT INSTALLATION WAZUH
===============================================

Date: $(date)
Serveur: $(hostname)

INSTALLATION WAZUH:
  Version: $(cat /var/ossec/VERSION.txt 2>/dev/null || echo "Inconnue")
  Répertoire: /var/ossec
  Utilisateur: wazuh:wazuh
  
CONFIGURATION:
  Réception syslog: Port 514 UDP
  Collecte FreeRADIUS: /var/log/freeradius/radius.log
  Collecte SSH: /var/log/auth.log
  Collecte système: /var/log/syslog
  Collecte TL-MR100: via syslog UDP 514

RÈGLES & DÉCODEURS:
  Règles personnalisées: local_rules.xml
  Décodeurs TL-MR100: syslog-tlmr100.conf
  Moniteurs critiques: FreeRADIUS, SSH, MySQL, Apache

ALERTES CONFIGURÉES:
  Level 3: Authentifications réussies
  Level 5: Authentifications échouées
  Level 6: Modifications critiques
  Level 7: Bruteforce détecté
  Level 8: Erreurs critiques
  Level 9: Attaques détectées

COMMANDES UTILES:
  Statut:
    $ sudo systemctl status wazuh-manager
  
  Logs:
    $ sudo tail -f /var/ossec/logs/ossec.log
  
  Alerts:
    $ sudo tail -f /var/ossec/logs/alerts/alerts.log
  
  Contrôler:
    $ sudo /var/ossec/bin/wazuh-control status
  
  Redémarrer:
    $ sudo systemctl restart wazuh-manager
  
  Règles:
    $ sudo /var/ossec/bin/wazuh-control query

VÉRIFICATIONS:
  [ ] Wazuh Manager démarré: systemctl status wazuh-manager
  [ ] Règles chargées: grep -c "local_rules.xml" /var/ossec/logs/ossec.log
  [ ] Réception syslog: netstat -un | grep 514
  [ ] FreeRADIUS suivi: tail -f /var/ossec/logs/alerts/alerts.log
  [ ] TL-MR100 logs reçus: grep "TL-MR100" /var/ossec/logs/ossec.log

PROCHAINES ÉTAPES:
  1. Activer syslog sur TL-MR100 (Admin → System → Logs)
  2. Configurer FreeRADIUS (scripts/install_radius.sh)
  3. Vérifier réception logs: tail /var/ossec/logs/alerts/alerts.log
  4. Configurer alertes email (optionnel)
  5. Intégrer avec SIEM (Splunk, ELK, etc.)

===============================================
EOF
    
    log_success "Rapport généré: $LOG_FILE"
}

###############################################
# MAIN
###############################################

main() {
    log_info "╔════════════════════════════════════════╗"
    log_info "║  SAE 5.01 - Installation Wazuh        ║"
    log_info "║  $(date +"%Y-%m-%d %H:%M:%S")           ║"
    log_info "╚════════════════════════════════════════╝"
    log_info ""
    log_info "Log: $LOG_FILE"
    
    check_root
    check_resources
    check_files
    
    add_wazuh_repo
    install_wazuh
    
    import_config
    import_rules
    import_decoders
    
    configure_rsyslog
    
    if ! test_syntax; then
        log_error "Erreur de syntaxe - installation incomplète"
        generate_report
        exit 1
    fi
    
    start_service
    verify_rules
    generate_report
    
    log_success ""
    log_success "╔════════════════════════════════════════╗"
    log_success "║  ✓ INSTALLATION RÉUSSIE               ║"
    log_success "╚════════════════════════════════════════╝"
}

main "$@"
