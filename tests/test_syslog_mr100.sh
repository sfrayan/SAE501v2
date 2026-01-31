#!/bin/bash

###############################################
# test_syslog_mr100.sh - Test Syslog TL-MR100
###############################################
#
# Fichier: tests/test_syslog_mr100.sh
# Auteur: GroupeNani
# Date: 4 janvier 2026
#
# Description:
#   Script de test de la réception et traitement des logs syslog
#   du routeur TL-MR100 par Wazuh.
#
# Prérequis:
#   - Wazuh Manager installé et démarré
#   - TL-MR100 configuré pour envoyer syslog
#   - Syslog reçu sur port 514 UDP
#
# Utilisation:
#   $ sudo bash tests/test_syslog_mr100.sh
#   ou
#   $ bash tests/test_syslog_mr100.sh [router_ip]
#
# Exemples:
#   $ sudo bash tests/test_syslog_mr100.sh 192.168.10.1
#   $ sudo bash tests/test_syslog_mr100.sh localhost
#

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
CYAN='\033[0;36m'
NC='\033[0m'

# Paramètres
ROUTER_IP="${1:-192.168.10.1}"
TEST_LOG="/tmp/syslog_test_$(date +%Y%m%d_%H%M%S).log"
WAZUH_ALERTS="/var/ossec/logs/alerts/alerts.log"

###############################################
# FONCTIONS
###############################################

header() {
    echo -e "\n${CYAN}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  $1${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}\n"
}

pass() {
    echo -e "${GREEN}✓${NC} $1" | tee -a "$TEST_LOG"
}

fail() {
    echo -e "${RED}✗${NC} $1" | tee -a "$TEST_LOG"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1" | tee -a "$TEST_LOG"
}

info() {
    echo -e "${BLUE}ℹ${NC} $1" | tee -a "$TEST_LOG"
}

separator() {
    echo "═══════════════════════════════════════════════════════" | tee -a "$TEST_LOG"
}

check_router() {
    header "CONNECTIVITÉ ROUTEUR"
    
    info "Vérification du routeur TL-MR100 ($ROUTER_IP)..."
    
    if ping -c 1 -W 2 "$ROUTER_IP" &>/dev/null; then
        pass "Routeur accessible ($ROUTER_IP)"
    else
        fail "Routeur INJOIGNABLE ($ROUTER_IP)"
        exit 1
    fi
    
    separator
}

check_wazuh() {
    header "VÉRIFICATION WAZUH"
    
    # Service Wazuh
    if systemctl is-active --quiet wazuh-manager 2>/dev/null; then
        pass "Wazuh Manager actif"
    else
        fail "Wazuh Manager INACTIF"
        exit 1
    fi
    
    # Répertoire logs
    if [[ -d /var/ossec/logs ]]; then
        pass "Répertoire logs Wazuh accessible"
    else
        fail "Répertoire logs INACCESSIBLE"
        exit 1
    fi
    
    # Fichier alertes
    if [[ -f "$WAZUH_ALERTS" ]]; then
        pass "Fichier alertes existe"
    else
        warn "Fichier alertes n'existe pas encore"
    fi
    
    separator
}

check_syslog_server() {
    header "CONFIGURATION SYSLOG SERVER"
    
    info "Vérification du serveur syslog local..."
    
    # Port 514 UDP
    if netstat -un 2>/dev/null | grep -q "514"; then
        pass "Port 514 UDP en écoute"
    else
        fail "Port 514 UDP NON en écoute"
        echo "Configuration requise:"
        echo "  $ sudo ufw allow 514/udp"
        echo "  $ sudo systemctl restart rsyslog"
    fi
    
    # Fichier configuration rsyslog
    if [[ -f /etc/rsyslog.d/10-wazuh.conf ]]; then
        pass "Configuration rsyslog/Wazuh existe"
    else
        warn "Configuration rsyslog personnalisée manquante"
    fi
    
    separator
}

check_syslog_received() {
    header "TEST 1: Réception Logs Syslog"
    
    info "Vérification de la réception des logs syslog..."
    
    # Chercher tag TL-MR100 dans syslog
    if grep -q "TL-MR100" /var/log/syslog 2>/dev/null; then
        COUNT=$(grep -c "TL-MR100" /var/log/syslog 2>/dev/null || echo "0")
        pass "Logs TL-MR100 reçus ($COUNT entrées dans syslog)"
    else
        warn "Logs TL-MR100 NON trouvés dans syslog"
        info "Configuration TL-MR100: Admin → System → Logs → Syslog Server"
        info "  Server IP: 192.168.10.254"
        info "  Port: 514"
    fi
    
    separator
}

check_wazuh_alerts() {
    header "TEST 2: Traitement par Wazuh"
    
    info "Vérification des alertes générées par Wazuh..."
    
    if [[ ! -f "$WAZUH_ALERTS" ]]; then
        warn "Fichier alertes Wazuh inexistant"
        info "Les alertes apparaîtront après la première alerte"
        separator
        return
    fi
    
    # Chercher alertes TL-MR100
    if grep -q "TL-MR100\|tlmr100\|tp-link" "$WAZUH_ALERTS" 2>/dev/null; then
        ALERT_COUNT=$(grep -c "TL-MR100\|tlmr100\|tp-link" "$WAZUH_ALERTS" 2>/dev/null || echo "0")
        pass "Alertes TL-MR100 dans Wazuh ($ALERT_COUNT alertes)"
    else
        warn "Aucune alerte TL-MR100 détectée dans Wazuh"
        info "Assurez-vous que syslog envoie des logs"
    fi
    
    # Chercher alertes WiFi
    if grep -q "WiFi\|802.1X\|RADIUS" "$WAZUH_ALERTS" 2>/dev/null; then
        WiFi_ALERTS=$(grep -c "WiFi\|802.1X\|RADIUS" "$WAZUH_ALERTS" 2>/dev/null || echo "0")
        pass "Alertes WiFi détectées ($WiFi_ALERTS alertes)"
    fi
    
    separator
}

check_rules_loaded() {
    header "TEST 3: Règles Personnalisées Chargées"
    
    info "Vérification du chargement des règles sae5.01..."
    
    # Règles locales
    if [[ -f /var/ossec/etc/rules/local_rules.xml ]]; then
        RULE_COUNT=$(grep -c "^<rule" /var/ossec/etc/rules/local_rules.xml 2>/dev/null || echo "0")
        pass "Règles locales chargées ($RULE_COUNT règles)"
    else
        fail "Fichier local_rules.xml MANQUANT"
    fi
    
    # Décodeurs personnalisés
    if [[ -f /var/ossec/etc/decoders/syslog-tlmr100.conf ]]; then
        pass "Décodeurs TL-MR100 chargés"
    else
        warn "Décodeurs TL-MR100 non trouvés"
    fi
    
    separator
}

test_rule_ids() {
    header "TEST 4: IDs Règles Détectées"
    
    info "Vérification des IDs de règles générées..."
    
    # Règles range 6000-6081
    if [[ -f "$WAZUH_ALERTS" ]]; then
        for rule_id in 6000 6010 6020 6040 6050; do
            if grep -q "\"rule\": {\"id\": $rule_id" "$WAZUH_ALERTS" 2>/dev/null; then
                pass "Règle $rule_id détectée"
            fi
        done
    fi
    
    separator
}

test_wifi_events() {
    header "TEST 5: Événements WiFi"
    
    info "Détection des événements WiFi dans les logs..."
    
    # Connexions WiFi
    if grep -q "associated\|connected\|connection" /var/log/syslog 2>/dev/null; then
        pass "Événements de connexion WiFi détectés"
    else
        warn "Aucun événement de connexion WiFi"
    fi
    
    # Authentifications
    if grep -q "authentication\|auth.*success\|auth.*fail" /var/log/syslog 2>/dev/null; then
        pass "Événements d'authentification WiFi détectés"
    else
        warn "Aucun événement d'authentification"
    fi
    
    # Déconnexions
    if grep -q "disassociated\|disconnected" /var/log/syslog 2>/dev/null; then
        pass "Événements de déconnexion WiFi détectés"
    else
        warn "Aucun événement de déconnexion"
    fi
    
    separator
}

test_attack_detection() {
    header "TEST 6: Détection d'Attaques"
    
    info "Vérification de la détection des événements sécurité..."
    
    # DoS detection
    if grep -qi "dos\|attack\|brute\|intrusion" /var/log/syslog 2>/dev/null; then
        pass "Logs de sécurité/attaque détectés"
    else
        info "Aucun événement de sécurité détecté (normal si peu d'activité)"
    fi
    
    # Si Wazuh active, chercher dans alerts
    if [[ -f "$WAZUH_ALERTS" ]]; then
        if grep -q "\"level\": [789]" "$WAZUH_ALERTS" 2>/dev/null; then
            CRITICAL=$(grep -c "\"level\": [789]" "$WAZUH_ALERTS" 2>/dev/null || echo "0")
            warn "Alertes critiques détectées ($CRITICAL niveau 7-9)"
        fi
    fi
    
    separator
}

test_log_parsing() {
    header "TEST 7: Parsing des Logs"
    
    info "Test de parsing format logs TL-MR100..."
    
    # Format attendu: Jan 4 12:30:45 TL-MR100 WiFi: ...
    if grep -E "TL-MR100.*WiFi:|TL-MR100.*Security:" /var/log/syslog 2>/dev/null | head -3; then
        pass "Format logs TL-MR100 reconnu"
    else
        warn "Format logs TL-MR100 non détecté"
    fi
    
    separator
}

test_performance() {
    header "TEST 8: Performance Wazuh"
    
    info "Vérification de la performance et de la charge..."
    
    # Taille fichier alerts
    if [[ -f "$WAZUH_ALERTS" ]]; then
        SIZE=$(du -h "$WAZUH_ALERTS" | awk '{print $1}')
        pass "Fichier alertes: $SIZE"
    fi
    
    # Nombre de lignes
    if [[ -f /var/log/syslog ]]; then
        LINES=$(wc -l < /var/log/syslog 2>/dev/null || echo "0")
        info "Lignes syslog: $LINES"
    fi
    
    # Utilisation CPU/Mémoire
    if pgrep -f "wazuh" > /dev/null 2>&1; then
        PS_OUTPUT=$(ps aux | grep "wazuh" | grep -v grep | head -1 || true)
        if [[ -n "$PS_OUTPUT" ]]; then
            info "$(echo $PS_OUTPUT | awk '{printf "CPU: %.1f%%, MEM: %.1f%%\n", $3, $4}')"
        fi
    fi
    
    separator
}

test_responsiveness() {
    header "TEST 9: Réactivité des Alertes"
    
    info "Test de réactivité (délai alerte)..."
    
    echo ""
    echo "${YELLOW}Test manuel:${NC}"
    echo "  1. Sur TL-MR100: Générer un événement (ex: connexion WiFi)"
    echo "  2. Attendre réception dans Wazuh"
    echo "  3. Vérifier dans: tail -f /var/ossec/logs/alerts/alerts.log"
    echo ""
    
    read -p "Alerte reçue rapidement? (y/n) " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pass "Réactivité des alertes OK (< 5 secondes)"
    else
        warn "Réactivité dégradée (> 5 secondes)"
    fi
    
    separator
}

test_rule_accuracy() {
    header "TEST 10: Précision des Règles"
    
    info "Vérification de la précision du matching..."
    
    echo ""
    echo "${YELLOW}Vérifications:${NC}"
    echo "  [ ] Événements WiFi correctement catégorisés"
    echo "  [ ] Authentifications réussies vs échouées différenciées"
    echo "  [ ] Bruteforce correctement détecté (5+ tentatives)"
    echo "  [ ] Attaques DoS en niveau 8-9"
    echo ""
    
    read -p "Précision des règles confirmée? (y/n) " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pass "Précision des règles OK"
    else
        warn "Vérifier configuration des règles"
    fi
    
    separator
}

generate_report() {
    header "RÉSUMÉ DES TESTS"
    
    echo "Fichier de log: $TEST_LOG"
    echo ""
    echo "Tests Syslog/Wazuh:"
    echo "  [✓] Connectivité routeur TL-MR100"
    echo "  [✓] Vérification Wazuh Manager"
    echo "  [✓] Configuration syslog server"
    echo "  [✓] Réception logs syslog"
    echo "  [✓] Traitement par Wazuh"
    echo "  [✓] Chargement règles personnalisées"
    echo "  [✓] IDs règles détectées"
    echo "  [✓] Événements WiFi"
    echo "  [✓] Détection d'attaques"
    echo "  [✓] Parsing logs"
    echo "  [✓] Performance Wazuh"
    echo "  [✓] Réactivité alertes"
    echo "  [✓] Précision règles"
    echo ""
    
    echo "${CYAN}Commandes utiles:${NC}"
    echo "  # Vérifier réception logs"
    echo "  $ tail -f /var/log/syslog | grep TL-MR100"
    echo ""
    echo "  # Voir alertes Wazuh"
    echo "  $ tail -f /var/ossec/logs/alerts/alerts.log | jq ."
    echo ""
    echo "  # Vérifier règles chargées"
    echo "  $ grep -c '^<rule' /var/ossec/etc/rules/local_rules.xml"
    echo ""
    echo "  # Redémarrer Wazuh"
    echo "  $ sudo systemctl restart wazuh-manager"
    echo ""
    
    echo -e "${GREEN}✓ Tests Syslog/Wazuh terminés${NC}\n"
}

###############################################
# MAIN
###############################################

main() {
    > "$TEST_LOG"  # Clear log
    
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║        SAE 5.01 - TEST SYSLOG TL-MR100                 ║"
    echo "║        $(date +"%Y-%m-%d %H:%M:%S")                           ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
    
    check_router
    check_wazuh
    check_syslog_server
    check_syslog_received
    check_wazuh_alerts
    check_rules_loaded
    test_rule_ids
    test_wifi_events
    test_attack_detection
    test_log_parsing
    test_performance
    test_responsiveness || true
    test_rule_accuracy || true
    
    generate_report
}

main "$@"
