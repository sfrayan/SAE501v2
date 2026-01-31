#!/bin/bash

###############################################
# install_radius.sh - Installation FreeRADIUS
###############################################
#
# Fichier: scripts/install_radius.sh
# Auteur: GroupeNani
# Date: 4 janvier 2026
#
# Description:
#   Script d'installation et configuration automatique de FreeRADIUS
#   pour l'authentification Wi-Fi Enterprise (802.1X) SAE 5.01.
#
# Prérequis:
#   - Debian 11+ ou Ubuntu 20.04+
#   - Accès root (sudo)
#   - MariaDB/MySQL installé et démarré
#
# Utilisation:
#   $ sudo bash scripts/install_radius.sh
#
# Fonctionnalités:
#   ✓ Installation FreeRADIUS + modules MySQL
#   ✓ Création base de données RADIUS
#   ✓ Configuration clients NAS (routeurs)
#   ✓ Génération certificats TLS
#   ✓ Activation PEAP-MSCHAPv2
#   ✓ Tests authentification
#

set -e  # Exit on error
set -u  # Exit on undefined variable

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
FREERADIUS_CONFIG="/etc/freeradius/3.0"
FREERADIUS_CERTS="$FREERADIUS_CONFIG/certs"
SQL_SCRIPT="$PROJECT_ROOT/radius/sql/create_tables.sql"
INIT_SCRIPT="$PROJECT_ROOT/radius/sql/init_appuser.sql"
CLIENTS_CONF="$PROJECT_ROOT/radius/clients.conf"
USERS_FILE="$PROJECT_ROOT/radius/users.txt"
LOG_FILE="/var/log/install_radius_$(date +%Y%m%d_%H%M%S).log"

# Variables
MYSQL_HOST="localhost"
MYSQL_ROOT_USER="root"
RADIUS_DATABASE="radius"

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

check_mysql() {
    log_info "Vérification MySQL/MariaDB..."
    if ! systemctl is-active --quiet mysql && ! systemctl is-active --quiet mariadb; then
        log_error "MySQL/MariaDB n'est pas en cours d'exécution"
        echo "Installation: sudo apt install mariadb-server"
        exit 1
    fi
    log_success "MySQL/MariaDB actif"
}

check_files() {
    log_info "Vérification des fichiers requis..."
    
    if [[ ! -f "$INIT_SCRIPT" ]]; then
        log_error "Fichier SQL non trouvé: $INIT_SCRIPT"
        exit 1
    fi
    
    if [[ ! -f "$SQL_SCRIPT" ]]; then
        log_error "Fichier SQL non trouvé: $SQL_SCRIPT"
        exit 1
    fi
    
    if [[ ! -f "$CLIENTS_CONF" ]]; then
        log_warning "Fichier clients.conf non trouvé: $CLIENTS_CONF"
    fi
    
    log_success "Fichiers vérifiés"
}

install_freeradius() {
    log_info "Installation des paquets FreeRADIUS..."
    
    apt-get update -qq
    apt-get install -y freeradius freeradius-mysql freeradius-utils \
        >> "$LOG_FILE" 2>&1
    
    log_success "FreeRADIUS installé"
}

setup_database() {
    log_info "Configuration base de données RADIUS..."
    
    # Créer utilisateur MySQL
    mysql -u "$MYSQL_ROOT_USER" < "$INIT_SCRIPT" >> "$LOG_FILE" 2>&1
    log_success "Utilisateur MySQL créé"
    
    # Créer tables
    mysql -u "$MYSQL_ROOT_USER" "$RADIUS_DATABASE" < "$SQL_SCRIPT" >> "$LOG_FILE" 2>&1
    log_success "Tables RADIUS créées"
}

configure_clients() {
    log_info "Configuration clients RADIUS..."
    
    if [[ -f "$CLIENTS_CONF" ]]; then
        cp "$CLIENTS_CONF" "$FREERADIUS_CONFIG/clients.conf"
        log_success "Configuration clients copiée"
    else
        log_warning "clients.conf non disponible - utiliser config par défaut"
    fi
}

configure_users() {
    log_info "Configuration utilisateurs de test..."
    
    if [[ -f "$USERS_FILE" ]]; then
        cp "$USERS_FILE" "$FREERADIUS_CONFIG/users"
        log_success "Fichier utilisateurs copié"
    else
        log_warning "Fichier users non disponible"
    fi
}

generate_certificates() {
    log_info "Génération des certificats TLS..."
    
    cd "$FREERADIUS_CERTS"
    make >> "$LOG_FILE" 2>&1
    cd - > /dev/null
    
    log_success "Certificats générés"
}

configure_modules() {
    log_info "Configuration modules FreeRADIUS..."
    
    # Activer module SQL
    if [[ ! -L "$FREERADIUS_CONFIG/mods-enabled/sql" ]]; then
        ln -sf ../mods-available/sql "$FREERADIUS_CONFIG/mods-enabled/sql"
    fi
    log_success "Module SQL activé"
    
    # Activer module EAP
    if [[ ! -L "$FREERADIUS_CONFIG/mods-enabled/eap" ]]; then
        ln -sf ../mods-available/eap "$FREERADIUS_CONFIG/mods-enabled/eap"
    fi
    log_success "Module EAP activé"
}

set_permissions() {
    log_info "Configuration des permissions..."
    
    chown -R root:freerad "$FREERADIUS_CONFIG"
    chmod -R 750 "$FREERADIUS_CONFIG"
    chmod 640 "$FREERADIUS_CONFIG/clients.conf"
    
    mkdir -p /var/log/freeradius
    chown freerad:freerad /var/log/freeradius
    chmod 750 /var/log/freeradius
    
    log_success "Permissions configurées"
}

test_syntax() {
    log_info "Vérification de la syntaxe FreeRADIUS..."
    
    if freeradius -XC > /dev/null 2>&1; then
        log_success "Syntaxe valide"
        return 0
    else
        log_error "Erreur de syntaxe dans la configuration"
        freeradius -XC | tail -20 >> "$LOG_FILE"
        return 1
    fi
}

start_service() {
    log_info "Démarrage de FreeRADIUS..."
    
    systemctl enable freeradius >> "$LOG_FILE" 2>&1
    systemctl restart freeradius >> "$LOG_FILE" 2>&1
    sleep 2
    
    if systemctl is-active --quiet freeradius; then
        log_success "FreeRADIUS en cours d'exécution"
    else
        log_error "Erreur au démarrage de FreeRADIUS"
        systemctl status freeradius >> "$LOG_FILE" 2>&1
        return 1
    fi
}

test_radius() {
    log_info "Test d'authentification RADIUS..."
    
    if radtest alice@gym.fr Alice@123! 127.0.0.1 1812 testing123 \
        >> "$LOG_FILE" 2>&1; then
        log_success "Test radtest réussi"
    else
        log_warning "Test radtest échoué - vérifier les logs"
    fi
}

generate_report() {
    log_info "Génération du rapport d'installation..."
    
    cat >> "$LOG_FILE" <<EOF

===============================================
      RAPPORT INSTALLATION FREERADIUS
===============================================

Date: $(date)
Serveur: $(hostname)

CONFIGURATION:
  Base de données: $RADIUS_DATABASE
  Utilisateur MySQL: radius_app
  Serveur FreeRADIUS: $FREERADIUS_CONFIG
  Certificats: $FREERADIUS_CERTS

UTILISATEURS DE TEST:
  - alice@gym.fr / Alice@123! (Staff)
  - bob@gym.fr / Bob@456! (Staff)
  - charlie@gym.fr / Charlie@789! (Guest)
  - david@gym.fr / David@2026! (Manager)
  - emma@gym.fr / Emma@2026! (Réception)

COMMANDES UTILES:
  Statut:
    $ sudo systemctl status freeradius
  
  Logs:
    $ sudo tail -f /var/log/freeradius/radius.log
  
  Test radtest:
    $ radtest alice@gym.fr Alice@123! 127.0.0.1 1812 testing123
  
  Redémarrer:
    $ sudo systemctl restart freeradius
  
  Utilisateurs BD:
    $ mysql -u radius_app -p radius -e "SELECT username FROM radcheck;"

VÉRIFICATIONS REQUISES:
  [ ] Routeur TL-MR100 configuré avec le bon secret RADIUS
  [ ] Port 1812-1813 UDP ouvert dans UFW
  [ ] Certificats générés avec succès
  [ ] Test radtest réussi
  [ ] Logs FreeRADIUS accessibles

PROCHAINES ÉTAPES:
  1. Configurer le routeur TL-MR100 (secret RADIUS)
  2. Ajouter utilisateurs via PHP-Admin ou SQL directement
  3. Tester connexion Wi-Fi depuis un client
  4. Configurer Wazuh pour surveillance
  5. Activer hardening Linux (scripts/hardening.sh)

===============================================
EOF
    
    log_success "Rapport généré: $LOG_FILE"
}

###############################################
# MAIN
###############################################

main() {
    log_info "╔════════════════════════════════════════╗"
    log_info "║  SAE 5.01 - Installation FreeRADIUS   ║"
    log_info "║  $(date +"%Y-%m-%d %H:%M:%S")           ║"
    log_info "╚════════════════════════════════════════╝"
    log_info ""
    log_info "Log: $LOG_FILE"
    
    check_root
    check_mysql
    check_files
    
    install_freeradius
    setup_database
    configure_clients
    configure_users
    generate_certificates
    configure_modules
    set_permissions
    
    if ! test_syntax; then
        log_error "Erreur de syntaxe détectée - installation incomplète"
        generate_report
        exit 1
    fi
    
    start_service
    test_radius
    generate_report
    
    log_success ""
    log_success "╔════════════════════════════════════════╗"
    log_success "║  ✓ INSTALLATION RÉUSSIE               ║"
    log_success "╚════════════════════════════════════════╝"
}

main "$@"
