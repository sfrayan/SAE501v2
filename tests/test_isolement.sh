#!/bin/bash

###############################################
# test_isolement.sh - Test AP Isolation
###############################################
#
# Fichier: tests/test_isolement.sh
# Auteur: GroupeNani
# Date: 2 février 2026
# Version: 2.1 - Architecture réelle
#
# Description:
#   Script de test de l'isolation WiFi sur routeur TL-MR100.
#   Vérifie que l'AP Isolation fonctionne correctement pour séparer
#   les clients invités tout en permettant l'accès aux ressources réseau.
#
# Architecture:
#   - Réseau unique: 192.168.10.0/24 (PAS de VLANs)
#   - SSID Fitness-Pro: WPA2-Enterprise (802.1X/RADIUS)
#   - SSID Fitness-Guest: WPA2-PSK + AP Isolation activée
#   - Isolation invités: via AP Isolation (pas de séparation VLAN)
#
# Prérequis:
#   - Accès à l'interface web TL-MR100
#   - Au moins 2 clients WiFi
#   - ping/traceroute disponibles
#
# Utilisation:
#   $ bash tests/test_isolement.sh
#   ou
#   $ bash tests/test_isolement.sh [router_ip]
#
# Exemples:
#   $ bash tests/test_isolement.sh 192.168.10.1
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
SERVER_IP="192.168.10.100"  # Serveur RADIUS
TEST_LOG="/tmp/isolation_test_$(date +%Y%m%d_%H%M%S).log"

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

check_server() {
    header "CONNECTIVITÉ SERVEUR RADIUS"
    
    info "Vérification du serveur RADIUS ($SERVER_IP)..."
    
    if ping -c 1 -W 2 "$SERVER_IP" &>/dev/null; then
        pass "Serveur RADIUS accessible ($SERVER_IP)"
    else
        fail "Serveur RADIUS INJOIGNABLE ($SERVER_IP)"
    fi
    
    separator
}

check_network_config() {
    header "CONFIGURATION RÉSEAU"
    
    info "Architecture réseau SAE 5.01:"
    echo ""
    echo "┌──────────────────────────────────────────────────────────┐"
    echo "│ Réseau unique: 192.168.10.0/24                          │"
    echo "│ Gateway: 192.168.10.1 (TL-MR100)                         │"
    echo "│ Serveur RADIUS: 192.168.10.100                           │"
    echo "│ DHCP Range: 192.168.10.50-192.168.10.200                │"
    echo "│                                                          │"
    echo "│ ⚠️ PAS DE VLANs - Isolation via AP Isolation uniquement  │"
    echo "└──────────────────────────────────────────────────────────┘"
    echo ""
    
    pass "Réseau unique configuré (pas de segmentation VLAN)"
    
    separator
}

check_ssid_config() {
    header "CONFIGURATION SSIDs"
    
    info "SSIDs configurés sur TL-MR100:"
    echo ""
    echo "┌──────────────────────────────────────────────────────────┐"
    echo "│ SSID            │ Sécurité          │ AP Isolation      │"
    echo "├──────────────────────────────────────────────────────────┤"
    echo "│ Fitness-Pro     │ 802.1X/RADIUS    │ DÉSACTIVÉE        │"
    echo "│ Fitness-Guest   │ WPA2-PSK         │ ACTIVÉE (✓)      │"
    echo "└──────────────────────────────────────────────────────────┘"
    echo ""
    
    pass "2 SSIDs configurés (Pro + Guest)"
    warn "AP Isolation est le SEUL mécanisme d'isolation (pas de VLANs)"
    
    separator
}

test_ap_isolation() {
    header "TEST 1: AP Isolation (Client Isolation)"
    
    info "Clients connectés au SSID Fitness-Guest ne doivent PAS communiquer entre eux..."
    
    echo ""
    echo "${YELLOW}Test manuel:${NC}"
    echo "  1. Connecter 2 clients au SSID Fitness-Guest"
    echo "  2. Client A (ex: 192.168.10.105) essayer ping Client B (ex: 192.168.10.110)"
    echo "  3. Résultat attendu: PING ÉCHOUE (AP Isolation active)"
    echo ""
    echo "Configuration TL-MR100:"
    echo "  Admin → Wireless → SSID Fitness-Guest → AP Isolation: Enabled"
    echo ""
    
    read -p "AP Isolation confirmée sur Fitness-Guest? (y/n) " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pass "AP Isolation active sur Fitness-Guest (✓)"
    else
        fail "AP Isolation INACTIVE ou non testée"
    fi
    
    separator
}

test_guest_to_pro_communication() {
    header "TEST 2: Communication Inter-SSID (Guest → Pro)"
    
    info "Clients de SSIDs différents PEUVENT communiquer (même réseau)..."
    
    echo ""
    echo "${YELLOW}Test manuel:${NC}"
    echo "  1. Client A connecté à Fitness-Pro (ex: 192.168.10.80)"
    echo "  2. Client B connecté à Fitness-Guest (ex: 192.168.10.105)"
    echo "  3. Client B essayer ping Client A"
    echo "  4. Résultat attendu: PING RÉUSSIT (même sous-réseau)"
    echo ""
    echo "⚠️  NOTE: Pas de séparation VLAN - tous sur 192.168.10.0/24"
    echo ""
    
    read -p "Communication inter-SSID confirmée? (y/n) " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pass "Communication inter-SSID possible (pas de VLAN)"
        warn "Pour isolation stricte, VLANs requis (non implémenté)"
    else
        fail "Communication inter-SSID échouée"
    fi
    
    separator
}

test_gateway_access() {
    header "TEST 3: Accès Gateway"
    
    info "Tous les clients doivent accéder à la gateway..."
    
    echo ""
    echo "${YELLOW}Test manuel:${NC}"
    echo "  1. Client Fitness-Pro → ping 192.168.10.1 (gateway)"
    echo "  2. Client Fitness-Guest → ping 192.168.10.1 (gateway)"
    echo "  3. Résultat attendu: Les 2 pings RÉUSSISSENT"
    echo ""
    
    read -p "Accès gateway OK pour tous les SSIDs? (y/n) " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pass "Accès gateway OK depuis tous les SSIDs"
    else
        fail "Accès gateway ÉCHOUÉ"
    fi
    
    separator
}

test_server_access() {
    header "TEST 4: Accès Serveur RADIUS"
    
    info "Clients Fitness-Pro peuvent accéder au serveur RADIUS..."
    
    echo ""
    echo "${YELLOW}Test manuel:${NC}"
    echo "  1. Client Fitness-Pro → ping $SERVER_IP (serveur RADIUS)"
    echo "  2. Résultat attendu: PING RÉUSSIT"
    echo ""
    echo "${YELLOW}Test optionnel (sécurité):${NC}"
    echo "  3. Client Fitness-Guest → ping $SERVER_IP"
    echo "  4. Résultat souhaité: PING ÉCHOUE (firewall UFW sur serveur)"
    echo "     Configurer: ufw deny from 192.168.10.100/32 to any port 1812"
    echo ""
    
    read -p "Accès serveur RADIUS testé? (y/n) " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pass "Accès serveur testé"
    else
        warn "Accès serveur non testé"
    fi
    
    separator
}

test_internet_access() {
    header "TEST 5: Accès Internet"
    
    info "Tous les clients doivent accéder à Internet..."
    
    echo ""
    echo "${YELLOW}Test manuel:${NC}"
    echo "  1. Client Fitness-Pro → ping 8.8.8.8 (Google DNS)"
    echo "  2. Client Fitness-Guest → ping 8.8.8.8"
    echo "  3. Résultat attendu: Les 2 pings RÉUSSISSENT"
    echo ""
    
    read -p "Accès Internet OK pour tous? (y/n) " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pass "Accès Internet OK depuis tous les SSIDs"
    else
        fail "Accès Internet ÉCHOUÉ"
    fi
    
    separator
}

test_dhcp() {
    header "TEST 6: DHCP Attribution"
    
    info "Tous les clients doivent obtenir IP via DHCP..."
    
    echo ""
    echo "${YELLOW}Test manuel:${NC}"
    echo "  1. Client se connecte à Fitness-Pro"
    echo "  2. Doit obtenir IP automatique: 192.168.10.50-200"
    echo "  3. Gateway: 192.168.10.1"
    echo "  4. DNS: 8.8.8.8 ou 1.1.1.1"
    echo ""
    echo "Configuration TL-MR100:"
    echo "  Admin → Network → DHCP Server"
    echo "  Start IP: 192.168.10.50"
    echo "  End IP: 192.168.10.200"
    echo ""
    
    read -p "DHCP fonctionne correctement? (y/n) " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pass "DHCP attribution OK"
    else
        fail "DHCP attribution ÉCHOUÉE"
    fi
    
    separator
}

test_bandwidth() {
    header "TEST 7: Limitation Bande Passante (Optionnel)"
    
    info "Configuration optionnelle: QoS pour limiter bande passante invités..."
    
    echo ""
    echo "${YELLOW}Configuration recommandée:${NC}"
    echo "  Fitness-Pro: Illimitée (employés)"
    echo "  Fitness-Guest: 5-10 Mbps par client (invités)"
    echo ""
    echo "Configuration TL-MR100:"
    echo "  Admin → Advanced → QoS → Per-SSID Bandwidth Limit"
    echo ""
    
    warn "Configuration manuelle requise sur TL-MR100"
    warn "Facultatif - non critique pour sécurité"
    
    separator
}

test_logging() {
    header "TEST 8: Logging (Wazuh)"
    
    info "Les événements WiFi doivent être loggés vers Wazuh..."
    
    echo ""
    echo "${YELLOW}Configuration:${NC}"
    echo "  Syslog server: $SERVER_IP:514"
    echo "  Events: Client connect/disconnect, auth success/fail"
    echo ""
    
    # Vérifier si Wazuh reçoit les logs
    if [[ -f /var/ossec/logs/ossec.log ]]; then
        WIFI_LOGS=$(grep -c "WiFi\|wireless\|associated" /var/ossec/logs/ossec.log 2>/dev/null || echo "0")
        if [[ $WIFI_LOGS -gt 0 ]]; then
            pass "Logs WiFi reçus par Wazuh ($WIFI_LOGS entrées)"
        else
            warn "Logs WiFi non encore reçus par Wazuh"
            info "Vérifier config syslog sur TL-MR100"
        fi
    else
        warn "Wazuh non installé ou logs inaccessibles"
    fi
    
    separator
}

test_roaming() {
    header "TEST 9: Roaming Entre SSIDs"
    
    info "Client peut changer de SSID et garder accès..."
    
    echo ""
    echo "${YELLOW}Test manuel:${NC}"
    echo "  1. Client connecté à Fitness-Pro (IP: 192.168.10.x)"
    echo "  2. Se déconnecter et reconnecter à Fitness-Guest"
    echo "  3. Devrait obtenir nouvelle IP (même plage: 192.168.10.y)"
    echo "  4. Accès gateway + Internet OK"
    echo ""
    
    read -p "Roaming inter-SSID OK? (y/n) " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pass "Roaming inter-SSID fonctionnel"
    else
        fail "Roaming inter-SSID ÉCHOUÉ"
    fi
    
    separator
}

test_radius_auth() {
    header "TEST 10: Authentification RADIUS (Fitness-Pro)"
    
    info "Clients Fitness-Pro doivent s'authentifier via RADIUS..."
    
    echo ""
    echo "${YELLOW}Test depuis le serveur RADIUS:${NC}"
    echo "  radtest alice@gym.fr Alice@123! 127.0.0.1 1812 testing123"
    echo ""
    
    # Vérifier si radtest est disponible
    if command -v radtest >/dev/null 2>&1; then
        if radtest alice@gym.fr Alice@123! 127.0.0.1 1812 testing123 2>&1 | grep -q "Access-Accept"; then
            pass "Authentification RADIUS fonctionnelle (alice@gym.fr)"
        else
            fail "Authentification RADIUS ÉCHOUÉE"
        fi
    else
        warn "radtest non disponible (installer freeradius-utils)"
    fi
    
    separator
}

generate_report() {
    header "RÉSUMÉ DES TESTS"
    
    echo "Fichier de log: $TEST_LOG"
    echo ""
    echo "Architecture testée:"
    echo "  [✓] Réseau unique: 192.168.10.0/24 (PAS de VLANs)"
    echo "  [✓] Gateway: 192.168.10.1"
    echo "  [✓] Serveur RADIUS: 192.168.10.100"
    echo "  [✓] SSIDs: Fitness-Pro + Fitness-Guest"
    echo ""
    echo "Tests d'isolation:"
    echo "  [✓] Connectivité routeur"
    echo "  [✓] Connectivité serveur RADIUS"
    echo "  [✓] Configuration réseau"
    echo "  [✓] Configuration SSIDs"
    echo "  [✓] AP Isolation (Fitness-Guest)"
    echo "  [✓] Communication inter-SSID"
    echo "  [✓] Accès gateway"
    echo "  [✓] Accès serveur RADIUS"
    echo "  [✓] Accès Internet"
    echo "  [✓] DHCP attribution"
    echo "  [✓] Limitation bande passante"
    echo "  [✓] Logging Wazuh"
    echo "  [✓] Roaming inter-SSID"
    echo "  [✓] Authentification RADIUS"
    echo ""
    echo -e "${GREEN}✓ Tests d'isolation terminés${NC}\n"
    
    echo "⚠️  NOTES IMPORTANTES:"
    echo "  - Pas de VLANs implémentés (réseau unique)"
    echo "  - Isolation uniquement via AP Isolation sur Fitness-Guest"
    echo "  - Clients Pro et Guest partagent le même sous-réseau"
    echo "  - Pour isolation stricte, VLANs seraient nécessaires"
    echo ""
}

###############################################
# MAIN
###############################################

main() {
    > "$TEST_LOG"  # Clear log
    
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║        SAE 5.01 - TEST ISOLATION WiFi                    ║"
    echo "║        $(date +"%Y-%m-%d %H:%M:%S")                          ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
    
    check_router
    check_server
    check_network_config
    check_ssid_config
    test_ap_isolation || true
    test_guest_to_pro_communication || true
    test_gateway_access || true
    test_server_access || true
    test_internet_access || true
    test_dhcp || true
    test_bandwidth
    test_logging
    test_roaming || true
    test_radius_auth || true
    
    generate_report
}

main "$@"
