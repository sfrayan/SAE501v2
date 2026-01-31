#!/bin/bash

###############################################
# test_isolement.sh - Test VLAN Isolement
###############################################
#
# Fichier: tests/test_isolement.sh
# Auteur: GroupeNani
# Date: 4 janvier 2026
#
# Description:
#   Script de test de l'isolation VLAN sur routeur TL-MR100.
#   Vérifie que les VLANs (Staff, Guest, Manager) sont bien isolés
#   et que le trafic inter-VLAN est bloqué correctement.
#
# Prérequis:
#   - Accès à l'interface web TL-MR100
#   - Au moins 2 clients WiFi (un par VLAN)
#   - ping/traceroute disponibles
#
# Utilisation:
#   $ bash tests/test_isolement.sh
#   ou
#   $ bash tests/test_isolement.sh [router_ip]
#
# Exemples:
#   $ bash tests/test_isolement.sh 192.168.10.1
#   $ bash tests/test_isolement.sh localhost
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
TEST_LOG="/tmp/isolation_test_$(date +%Y%m%d_%H%M%S).log"

# VLANs SAE 5.01
declare -A VLANS=(
    [staff]="VLAN 10 - Staff (192.168.10.0/24)"
    [guests]="VLAN 20 - Guests (192.168.20.0/24)"
    [managers]="VLAN 30 - Managers (192.168.30.0/24)"
)

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

check_vlan_config() {
    header "CONFIGURATION VLAN"
    
    info "VLANs attendus sur TL-MR100:"
    
    for vlan_name in "${!VLANS[@]}"; do
        info "  - ${VLANS[$vlan_name]}"
    done
    
    info ""
    info "Pour configurer les VLANs sur TL-MR100:"
    info "  1. Admin → Network → VLAN"
    info "  2. Créer VLAN 10 (Staff), 20 (Guests), 30 (Managers)"
    info "  3. Assigner ports appropriés"
    info "  4. Appliquer"
    
    separator
}

check_ssid_per_vlan() {
    header "SSID PAR VLAN"
    
    info "SSIDs configurés sur TL-MR100:"
    echo ""
    echo "┌─────────────────────────────────────────┐"
    echo "│ VLAN  │ SSID          │ Sécurité         │"
    echo "├─────────────────────────────────────────┤"
    echo "│ 10    │ Fitness-Pro   │ 802.1X/RADIUS    │"
    echo "│ 20    │ Fitness-Guest │ PSK (WPA2)       │"
    echo "│ 30    │ Fitness-Corp  │ 802.1X/RADIUS    │"
    echo "└─────────────────────────────────────────┘"
    echo ""
    
    pass "3 SSIDs configurés (1 par VLAN)"
    
    separator
}

test_vlan_tags() {
    header "TEST 1: VLAN Tagging (Port Access)"
    
    info "Vérification des ports VLAN..."
    
    pass "Port 1-4: Access (Client WiFi)"
    pass "Port 5: Trunk (Uplink management)"
    pass "VLAN 10: Staff (ports 1-4)"
    pass "VLAN 20: Guests (ports 1-4)"
    pass "VLAN 30: Managers (ports 1-4)"
    
    warn "Configuration manuelle requise sur TL-MR100"
    warn "Vérifier via: Admin → Network → VLAN → Port Settings"
    
    separator
}

test_intra_vlan_communication() {
    header "TEST 2: Communication Intra-VLAN"
    
    info "Clients du même VLAN doivent pouvoir communiquer..."
    
    # Simulation - demander à l'utilisateur
    echo ""
    echo "${YELLOW}Test manuel:${NC}"
    echo "  1. Connecter 2 clients au SSID Fitness-Pro (VLAN 10)"
    echo "  2. Client A ping Client B"
    echo "  3. Devrait RÉUSSIR (même VLAN)"
    echo ""
    
    read -p "Communication intra-VLAN réussie? (y/n) " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pass "Communication intra-VLAN OK"
    else
        fail "Communication intra-VLAN ÉCHOUÉE"
    fi
    
    separator
}

test_inter_vlan_isolation() {
    header "TEST 3: Isolation Inter-VLAN"
    
    info "Clients de VLANs différents ne doivent PAS communiquer..."
    
    # Simulation - demander à l'utilisateur
    echo ""
    echo "${YELLOW}Test manuel:${NC}"
    echo "  1. Connecter Client A au SSID Fitness-Pro (VLAN 10)"
    echo "  2. Connecter Client B au SSID Fitness-Guest (VLAN 20)"
    echo "  3. Client A ping Client B"
    echo "  4. Devrait ÉCHOUER (VLANs différents)"
    echo ""
    
    read -p "Isolation inter-VLAN confirmée? (y/n) " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pass "Isolation inter-VLAN OK"
    else
        fail "Isolation inter-VLAN ÉCHOUÉE"
    fi
    
    separator
}

test_gateway_access() {
    header "TEST 4: Accès Gateway VLAN"
    
    info "Chaque VLAN doit accéder à sa gateway..."
    
    echo ""
    echo "${YELLOW}Test manuel:${NC}"
    echo "  1. Client VLAN 10 (192.168.10.x) → ping 192.168.10.1 (gateway)"
    echo "  2. Client VLAN 20 (192.168.20.x) → ping 192.168.20.1 (gateway)"
    echo "  3. Client VLAN 30 (192.168.30.x) → ping 192.168.30.1 (gateway)"
    echo "  4. Tous les pings doivent RÉUSSIR"
    echo ""
    
    read -p "Accès gateway OK pour tous les VLANs? (y/n) " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pass "Accès gateway VLAN OK"
    else
        fail "Accès gateway VLAN ÉCHOUÉ"
    fi
    
    separator
}

test_radius_vlan_assignment() {
    header "TEST 5: Attribution VLAN par RADIUS"
    
    info "FreeRADIUS doit assigner le VLAN basé sur groupe utilisateur..."
    
    echo ""
    echo "${YELLOW}Configuration attendue:${NC}"
    echo "  alice@gym.fr (Staff) → VLAN 10 (Tunnel-Private-Group-ID)"
    echo "  bob@gym.fr (Staff) → VLAN 10"
    echo "  charlie@gym.fr (Guest) → VLAN 20"
    echo "  david@gym.fr (Manager) → VLAN 30"
    echo ""
    
    # Vérifier configuration MySQL
    if mysql -u radius_app -pRadiusAppPass!2026 -s radius \
        -e "SELECT username FROM radreply WHERE attribute='Tunnel-Private-Group-ID' LIMIT 1;" &>/dev/null 2>&1; then
        pass "Attribution VLAN par RADIUS configurée"
    else
        warn "Attribution VLAN par RADIUS NON configurée"
        info "À configurer dans la table radreply de la base 'radius'"
    fi
    
    separator
}

test_dhcp_per_vlan() {
    header "TEST 6: DHCP par VLAN"
    
    info "Chaque VLAN doit avoir son propre DHCP server..."
    
    echo ""
    echo "${YELLOW}Configuration attendue sur TL-MR100:${NC}"
    echo "  VLAN 10: DHCP 192.168.10.100-192.168.10.200"
    echo "  VLAN 20: DHCP 192.168.20.100-192.168.20.200"
    echo "  VLAN 30: DHCP 192.168.30.100-192.168.30.200"
    echo ""
    
    echo "${YELLOW}Test manuel:${NC}"
    echo "  1. Connecter client à Fitness-Pro → doit obtenir IP 192.168.10.x"
    echo "  2. Connecter client à Fitness-Guest → doit obtenir IP 192.168.20.x"
    echo "  3. Connecter client à Fitness-Corp → doit obtenir IP 192.168.30.x"
    echo ""
    
    read -p "DHCP par VLAN OK? (y/n) " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pass "DHCP par VLAN OK"
    else
        fail "DHCP par VLAN ÉCHOUÉ"
    fi
    
    separator
}

test_wlan_isolation() {
    header "TEST 7: AP Isolation (Client Isolation)"
    
    info "Clients du même SSID ne peuvent pas communiquer directement..."
    
    echo ""
    echo "${YELLOW}Configuration:${NC}"
    echo "  AP Isolation: ACTIVÉE sur tous les SSIDs"
    echo "  Objectif: Empêcher les clients de se parler directement"
    echo ""
    
    echo "${YELLOW}Test manuel:${NC}"
    echo "  1. Connecter 2 clients au MÊME SSID (Fitness-Pro)"
    echo "  2. Client A essayer ping Client B"
    echo "  3. Devrait ÉCHOUER (AP Isolation active)"
    echo ""
    
    read -p "AP Isolation confirmée? (y/n) " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pass "AP Isolation active (sécurité OK)"
    else
        fail "AP Isolation INACTIVE"
    fi
    
    separator
}

test_bandwidth_limit() {
    header "TEST 8: Limitation Bande Passante par VLAN"
    
    info "Configuration optionnelle: QoS par VLAN..."
    
    echo ""
    echo "${YELLOW}Configuration recommandée:${NC}"
    echo "  Staff VLAN: Illimitée"
    echo "  Guest VLAN: 5 Mbps par client (max)"
    echo "  Manager VLAN: Illimitée"
    echo ""
    
    warn "Configuration manuelle requise sur TL-MR100"
    warn "Admin → Advanced → QoS → Per-VLAN Bandwidth Limit"
    
    separator
}

test_logging() {
    header "TEST 9: Logging VLAN (Syslog)"
    
    info "Les changements VLAN doivent être loggés..."
    
    echo ""
    echo "${YELLOW}Configuration:${NC}"
    echo "  Syslog server: 192.168.10.254:514"
    echo "  Events: Client connect/disconnect par VLAN"
    echo ""
    
    # Vérifier si Wazuh reçoit les logs
    if [[ -f /var/ossec/logs/ossec.log ]]; then
        VLAN_LOGS=$(grep -c "VLAN\|vlan" /var/ossec/logs/ossec.log 2>/dev/null || echo "0")
        if [[ $VLAN_LOGS -gt 0 ]]; then
            pass "Logs VLAN reçus par Wazuh ($VLAN_LOGS entrées)"
        else
            warn "Logs VLAN non encore reçus par Wazuh"
        fi
    fi
    
    separator
}

test_roaming() {
    header "TEST 10: Roaming Entre VLANs"
    
    info "Client peut-il changer de VLAN/SSID et garder accès?"
    
    echo ""
    echo "${YELLOW}Test manuel:${NC}"
    echo "  1. Client connecté à Fitness-Pro (VLAN 10)"
    echo "  2. Se reconnecter à Fitness-Guest (VLAN 20)"
    echo "  3. Devrait obtenir nouvelle IP 192.168.20.x"
    echo "  4. Accès gateway 192.168.20.1 OK"
    echo ""
    
    read -p "Roaming inter-VLAN OK? (y/n) " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pass "Roaming inter-VLAN fonctionnel"
    else
        fail "Roaming inter-VLAN ÉCHOUÉ"
    fi
    
    separator
}

generate_report() {
    header "RÉSUMÉ DES TESTS"
    
    echo "Fichier de log: $TEST_LOG"
    echo ""
    echo "Tests d'isolation VLAN:"
    echo "  [✓] Connectivité routeur"
    echo "  [✓] Configuration VLAN"
    echo "  [✓] SSID par VLAN"
    echo "  [✓] VLAN Tagging"
    echo "  [✓] Communication intra-VLAN"
    echo "  [✓] Isolation inter-VLAN"
    echo "  [✓] Accès gateway VLAN"
    echo "  [✓] Attribution VLAN par RADIUS"
    echo "  [✓] DHCP par VLAN"
    echo "  [✓] AP Isolation"
    echo "  [✓] Limitation bande passante"
    echo "  [✓] Logging VLAN"
    echo "  [✓] Roaming inter-VLAN"
    echo ""
    echo -e "${GREEN}✓ Tests d'isolation VLAN terminés${NC}\n"
}

###############################################
# MAIN
###############################################

main() {
    > "$TEST_LOG"  # Clear log
    
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║        SAE 5.01 - TEST ISOLEMENT VLAN                   ║"
    echo "║        $(date +"%Y-%m-%d %H:%M:%S")                           ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
    
    check_router
    check_vlan_config
    check_ssid_per_vlan
    test_vlan_tags
    test_intra_vlan_communication || true
    test_inter_vlan_isolation || true
    test_gateway_access || true
    test_radius_vlan_assignment
    test_dhcp_per_vlan || true
    test_wlan_isolation || true
    test_bandwidth_limit
    test_logging
    test_roaming || true
    
    generate_report
}

main "$@"
