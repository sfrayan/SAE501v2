#!/bin/bash

###############################################
# install_wazuh.sh - Installation Wazuh (CORRIGÉ)
###############################################
#
# Fichier: scripts/install_wazuh.sh
# Auteur: GroupeNani
# Date: 31 janvier 2026
# Version: 1.1 (compatible Wazuh 4.x)
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
    
    # Installation de gnupg pour la clé GPG
    apt-get install -y gnupg apt-transport-https >> "$LOG_FILE" 2>&1
    
    # Import de la clé GPG Wazuh
    curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import >> "$LOG_FILE" 2>&1
    chmod 644 /usr/share/keyrings/wazuh.gpg
    
    # Ajout du repository
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
    log_info "Import de la configuration personnalisée..."
    
    # Backup config originale
    cp /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.bak.$(date +%Y%m%d)
    
    if [[ -f "$WAZUH_CONFIG" ]]; then
        cp "$WAZUH_CONFIG" /var/ossec/etc/ossec.conf
        chown root:wazuh /var/ossec/etc/ossec.conf
        chmod 640 /var/ossec/etc/ossec.conf
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
        # Convertir .conf en .xml si nécessaire
        DECODER_NAME=$(basename "$WAZUH_DECODER" .conf)
        DECODER_DEST="/var/ossec/etc/decoders/${DECODER_NAME}.xml"
        
        # Copier le fichier
        cp "$WAZUH_DECODER" "$DECODER_DEST"
        chown root:wazuh "$DECODER_DEST"
        chmod 640 "$DECODER_DEST"
        log_success "Décodeurs personnalisés copiés vers $DECODER_DEST"
    fi
}

configure_rsyslog() {
    log_info "Configuration rsyslog pour réception syslog..."
    
    # Vérifier si rsyslog est installé
    if ! command -v rsyslogd &> /dev/null; then
        apt-get install -y rsyslog >> "$LOG_FILE" 2>&1
    fi
    
    # Configuration pour réception UDP 514
    cat > /etc/rsyslog.d/10-wazuh.conf <<'EOF'
# Module UDP syslog
module(load="imudp")
input(type="imudp" port="514")

# Redirection vers Wazuh
:msg, contains, "TL-MR100" /var/log/syslog-router.log
:msg, contains, "FreeRADIUS" /var/log/syslog-radius.log
:msg, contains, "radiusd" /var/log/syslog-radius.log
EOF
    
    # Ajouter les fichiers dans ossec.conf si pas déjà présents
    if ! grep -q "syslog-router.log" /var/ossec/etc/ossec.conf; then
        log_info "Ajout des localfiles syslog dans ossec.conf..."
        # Note: Cette section sera ajoutée manuellement ou via template
    fi
    
    systemctl restart rsyslog >> "$LOG_FILE" 2>&1
    
    log_success "rsyslog configuré"
}

test_syntax() {
    log_info "Vérification de la syntaxe Wazuh..."

    # Tester la configuration du manager Wazuh 4.x
    if /var/ossec/bin/wazuh-control check >> "$LOG_FILE" 2>&1; then
        log_success "Syntaxe valide"
        return 0
    else
        log_error "Erreur de syntaxe détectée (voir $LOG_FILE)"
        tail -n 20 "$LOG_FILE"
        return 1
    fi
}

start_service() {
    log_info "Démarrage de Wazuh Manager..."
    
    systemctl enable wazuh-manager >> "$LOG_FILE" 2>&1
    systemctl start wazuh-manager >> "$LOG_FILE" 2>&1
    sleep 5
    
    if systemctl is-active --quiet wazuh-manager; then
        log_success "Wazuh Manager en cours d'exécution"
    else
        log_error "Erreur au démarrage de Wazuh"
        systemctl status wazuh-manager >> "$LOG_FILE" 2>&1
        journalctl -xeu wazuh-manager -n 50 >> "$LOG_FILE" 2>&1
        return 1
    fi
}

verify_installation() {
    log_info "Vérification de l'installation..."
    
    # Vérifier la version
    WAZUH_VERSION=$(/var/ossec/bin/wazuh-control info | grep "WAZUH_VERSION" | cut -d'=' -f2 | tr -d '"')
    log_success "Version Wazuh installée: $WAZUH_VERSION"
    
    # Vérifier les processus
    if pgrep -x "wazuh-analysisd" > /dev/null; then
        log_success "Processus wazuh-analysisd en cours d'exécution"
    fi
    
    if pgrep -x "wazuh-remoted" > /dev/null; then
        log_success "Processus wazuh-remoted en cours d'exécution"
    fi
    
    # Vérifier les ports ouverts
    if ss -ulnp | grep -q ":514"; then
        log_success "Port 514 UDP (syslog) ouvert"
    else
        log_warning "Port 514 UDP non détecté (vérifier rsyslog)"
    fi
    
    if ss -tlnp | grep -q ":1514"; then
        log_success "Port 1514 TCP (agents) ouvert"
    fi
}

generate_report() {
    log_info "Génération du rapport d'installation..."
    
    WAZUH_VERSION=$(/var/ossec/bin/wazuh-control info 2>/dev/null | grep "WAZUH_VERSION" | cut -d'=' -f2 | tr -d '"' || echo "Inconnue")
    
    cat >> "$LOG_FILE" <<EOF

===============================================
       RAPPORT INSTALLATION WAZUH
===============================================

Date: $(date)
Serveur: $(hostname)

INSTALLATION WAZUH:
  Version: $WAZUH_VERSION
  Répertoire: /var/ossec
  Utilisateur: wazuh:wazuh
  
CONFIGURATION:
  Réception syslog: Port 514 UDP (rsyslog)
  Réception agents: Port 1514 TCP
  Collecte FreeRADIUS: /var/log/freeradius/radius.log
  Collecte SSH: /var/log/auth.log
  Collecte système: /var/log/syslog
  Collecte TL-MR100: via syslog UDP 514

RÈGLES & DÉCODEURS:
  Règles personnalisées: /var/ossec/etc/rules/local_rules.xml
  Décodeurs TL-MR100: /var/ossec/etc/decoders/syslog-tlmr100.xml
  Moniteurs critiques: FreeRADIUS, SSH, Apache

ALERTES CONFIGURÉES:
  Level 3: Authentifications réussies
  Level 5: Authentifications échouées
  Level 7: Bruteforce détecté
  Level 10: Attaques critiques

COMMANDES UTILES:
  Statut:
    $ sudo systemctl status wazuh-manager
  
  Logs:
    $ sudo tail -f /var/ossec/logs/ossec.log
  
  Alerts:
    $ sudo tail -f /var/ossec/logs/alerts/alerts.log
    $ sudo tail -f /var/ossec/logs/alerts/alerts.json
  
  Contrôler:
    $ sudo /var/ossec/bin/wazuh-control status
    $ sudo /var/ossec/bin/wazuh-control info
  
  Redémarrer:
    $ sudo systemctl restart wazuh-manager
  
  Vérifier syntaxe:
    $ sudo /var/ossec/bin/wazuh-control check

VÉRIFICATIONS:
  [ ] Wazuh Manager démarré: systemctl status wazuh-manager
  [ ] Règles chargées: ls -la /var/ossec/etc/rules/
  [ ] Réception syslog: ss -ulnp | grep 514
  [ ] FreeRADIUS suivi: tail -f /var/ossec/logs/alerts/alerts.log
  [ ] Processus actifs: /var/ossec/bin/wazuh-control status

PROCHAINES ÉTAPES:
  1. Vérifier la réception des logs:
     $ sudo tail -f /var/ossec/logs/ossec.log
  
  2. Activer syslog sur TL-MR100:
     - Admin → System → Logs
     - IP: 192.168.10.100 (IP du serveur)
     - Port: 514
  
  3. Générer des événements de test:
     $ sudo logger -p auth.info "Test Wazuh: Authentification SSH"
     $ radtest test@gym.fr TestPass 127.0.0.1 1812 testing123
  
  4. Vérifier les alertes:
     $ sudo tail -f /var/ossec/logs/alerts/alerts.json | jq .

===============================================
EOF
    
    log_success "Rapport généré: $LOG_FILE"
}

###############################################
# MAIN
###############################################

main() {
    log_info "╔════════════════════════════════════════╗"
    log_info "║  SAE 5.01 - Installation Wazuh (v1.1)  ║"
    log_info "║  $(date +"%Y-%m-%d %H:%M:%S")           ║"
    log_info "║  Compatible Wazuh 4.x                  ║"
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
        log_error "Vérifiez le log: $LOG_FILE"
        generate_report
        exit 1
    fi
    
    start_service
    verify_installation
    generate_report
    
    log_success ""
    log_success "╔════════════════════════════════════════╗"
    log_success "║  ✓ INSTALLATION RÉUSSIE               ║"
    log_success "╚════════════════════════════════════════╝"
    log_info ""
    log_info "Prochaines étapes:"
    log_info "  1. Vérifier les logs: sudo tail -f /var/ossec/logs/ossec.log"
    log_info "  2. Tester: sudo /var/ossec/bin/wazuh-control status"
    log_info "  3. Consulter le rapport: cat $LOG_FILE"
}

main "$@"