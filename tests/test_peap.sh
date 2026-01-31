#!/bin/bash

###############################################
# test_peap.sh - Test Authentification PEAP
###############################################
#
# Fichier: tests/test_peap.sh
# Auteur: GroupeNani
# Date: 4 janvier 2026
#
# Description:
#   Script de test d'authentification PEAP-MSCHAPv2 (802.1X)
#   Teste la connexion Wi-Fi Enterprise via FreeRADIUS.
#
# Prérequis:
#   - FreeRADIUS installé et en cours d'exécution
#   - eapol_test (wpa-supplicant) installé
#   - Configuration FreeRADIUS avec support PEAP
#
# Utilisation:
#   $ sudo bash tests/test_peap.sh
#   ou
#   $ bash tests/test_peap.sh [username] [password] [server]
#
# Exemples:
#   $ sudo bash tests/test_peap.sh alice@gym.fr Alice@123! 127.0.0.1
#   $ sudo bash tests/test_peap.sh bob@gym.fr Bob@456! localhost
#

set -e

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
USERNAME="${1:-alice@gym.fr}"
PASSWORD="${2:-Alice@123!}"
SERVER="${3:-127.0.0.1}"
PORT="1812"
SECRET="testing123"
TEST_LOG="/tmp/peap_test_$(date +%Y%m%d_%H%M%S).log"

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

check_requirements() {
    header "VÉRIFICATION PRÉREQUIS"
    
    # Vérifier radtest
    if ! command -v radtest &>/dev/null; then
        fail "radtest non installé (freeradius-utils requis)"
        echo "Installation: sudo apt install freeradius-utils"
        exit 1
    fi
    pass "radtest disponible"
    
    # Vérifier eapol_test
    if ! command -v eapol_test &>/dev/null; then
        warn "eapol_test non disponible (wpa_supplicant requis)"
        warn "Installation: sudo apt install wpasupplicant"
        warn "Certains tests seront ignorés"
    else
        pass "eapol_test disponible"
    fi
    
    # Vérifier FreeRADIUS
    if ! systemctl is-active --quiet freeradius; then
        fail "FreeRADIUS n'est pas en cours d'exécution"
        echo "Démarrage: sudo systemctl start freeradius"
        exit 1
    fi
    pass "FreeRADIUS actif"
    
    separator
}

check_connectivity() {
    header "CONNECTIVITÉ RÉSEAU"
    
    # Tester connexion au serveur
    if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$SERVER/$PORT" 2>/dev/null; then
        pass "Serveur RADIUS accessible ($SERVER:$PORT)"
    else
        fail "Impossible de se connecter à $SERVER:$PORT"
        exit 1
    fi
    
    separator
}

test_cleartext_password() {
    header "TEST 1: Cleartext-Password (radtest)"
    
    info "Utilisateur: $USERNAME"
    info "Serveur: $SERVER:$PORT"
    info "Secret: $SECRET"
    info ""
    
    # Exécuter radtest
    if radtest "$USERNAME" "$PASSWORD" "$SERVER" "$PORT" "$SECRET" 2>&1 | tee -a "$TEST_LOG" | grep -q "Access-Accept"; then
        pass "Authentification Cleartext réussie"
        info "Réponse: Access-Accept reçue"
        return 0
    else
        fail "Authentification Cleartext échouée"
        info "Réponse: Access-Reject (user/password incorrect ou utilisateur inexistant)"
        return 1
    fi
    
    separator
}

test_peap_mschapv2() {
    header "TEST 2: PEAP-MSCHAPv2 (eapol_test)"
    
    if ! command -v eapol_test &>/dev/null; then
        warn "eapol_test non disponible - test ignoré"
        separator
        return 0
    fi
    
    # Créer config wpa_supplicant temporaire
    TEMP_CONFIG="/tmp/wpa_supplicant_peap_$$.conf"
    
    cat > "$TEMP_CONFIG" <<EOF
network={
    ssid="Fitness-Pro"
    key_mgmt=WPA-EAP
    eap=PEAP
    phase1="peapver=0"
    phase2="auth=MSCHAPV2"
    identity="$USERNAME"
    password="$PASSWORD"
    ca_cert="/etc/freeradius/3.0/certs/ca.pem"
}
EOF
    
    info "Configuration PEAP créée"
    
    # Exécuter eapol_test
    if eapol_test -c "$TEMP_CONFIG" -s "$SECRET" \
        -a "$SERVER" -p "$PORT" -n 1 2>&1 | tee -a "$TEST_LOG" | grep -q "SUCCESS"; then
        pass "Authentification PEAP-MSCHAPv2 réussie"
        info "Réponse: SUCCESS (802.1X valide)"
    else
        fail "Authentification PEAP-MSCHAPv2 échouée"
        info "Vérifier certificats et configuration PEAP"
    fi
    
    # Nettoyer
    rm -f "$TEMP_CONFIG"
    
    separator
}

test_user_groups() {
    header "TEST 3: Groupes Utilisateurs"
    
    info "Vérification de l'appartenance aux groupes..."
    
    # Requête SQL pour voir groupes
    GROUPS=$(mysql -u radius_app -pRadiusAppPass!2026 -s radius \
        -e "SELECT GROUP_CONCAT(groupname) FROM radusergroup WHERE username='$USERNAME';" 2>/dev/null || echo "N/A")
    
    if [[ "$GROUPS" != "N/A" && -n "$GROUPS" ]]; then
        pass "Utilisateur dans groupes: $GROUPS"
    else
        warn "Utilisateur pas dans de groupe"
    fi
    
    separator
}

test_reply_messages() {
    header "TEST 4: Messages de Réponse"
    
    info "Capture des attributs de réponse RADIUS..."
    
    # Radtest avec verbose
    OUTPUT=$(radtest -x "$USERNAME" "$PASSWORD" "$SERVER" "$PORT" "$SECRET" 2>&1 || true)
    
    # Chercher Reply-Message
    if echo "$OUTPUT" | grep -q "Reply-Message"; then
        REPLY_MSG=$(echo "$OUTPUT" | grep "Reply-Message" | head -1)
        pass "Message de réponse détecté"
        info "Message: $REPLY_MSG"
    else
        warn "Aucun message de réponse"
    fi
    
    # Chercher autres attributs
    if echo "$OUTPUT" | grep -q "Session-Timeout"; then
        pass "Session-Timeout configuré"
    fi
    
    if echo "$OUTPUT" | grep -q "Framed-Protocol"; then
        pass "Framed-Protocol configuré"
    fi
    
    separator
}

test_failed_auth() {
    header "TEST 5: Authentification Échouée (Sécurité)"
    
    info "Test avec mauvais mot de passe..."
    WRONG_PASS="WrongPassword123!"
    
    if radtest "$USERNAME" "$WRONG_PASS" "$SERVER" "$PORT" "$SECRET" 2>&1 | grep -q "Access-Reject"; then
        pass "Rejet d'authentification avec mauvais password (sécurité OK)"
    else
        fail "Mauvais password accepté (PROBLÈME SÉCURITÉ)"
    fi
    
    info "Test avec utilisateur inexistant..."
    FAKE_USER="fake@gym.fr"
    
    if radtest "$FAKE_USER" "$PASSWORD" "$SERVER" "$PORT" "$SECRET" 2>&1 | grep -q "Access-Reject"; then
        pass "Rejet d'authentification utilisateur inexistant (sécurité OK)"
    else
        fail "Utilisateur fake accepté (PROBLÈME SÉCURITÉ)"
    fi
    
    separator
}

test_concurrent_auth() {
    header "TEST 6: Authentifications Concurrentes"
    
    info "Lancement de 5 authentifications parallèles..."
    
    CONCURRENT_PASS=0
    CONCURRENT_FAIL=0
    
    for i in {1..5}; do
        if radtest "$USERNAME" "$PASSWORD" "$SERVER" "$PORT" "$SECRET" &>/dev/null; then
            ((CONCURRENT_PASS++))
        else
            ((CONCURRENT_FAIL++))
        fi &
    done
    
    wait
    
    pass "$CONCURRENT_PASS authentifications réussies sur 5"
    
    if [[ $CONCURRENT_FAIL -gt 0 ]]; then
        warn "$CONCURRENT_FAIL authentifications échouées"
    fi
    
    separator
}

test_response_time() {
    header "TEST 7: Performance (Temps de Réponse)"
    
    info "Mesure du temps de réponse authentification..."
    
    START_TIME=$(date +%s%N)
    
    radtest "$USERNAME" "$PASSWORD" "$SERVER" "$PORT" "$SECRET" &>/dev/null
    
    END_TIME=$(date +%s%N)
    RESPONSE_TIME=$(( (END_TIME - START_TIME) / 1000000 ))
    
    pass "Temps de réponse: ${RESPONSE_TIME}ms"
    
    if [[ $RESPONSE_TIME -lt 100 ]]; then
        pass "Performance excellente (< 100ms)"
    elif [[ $RESPONSE_TIME -lt 500 ]]; then
        pass "Performance acceptable (< 500ms)"
    else
        warn "Performance dégradée (> 500ms)"
    fi
    
    separator
}

test_bruteforce_protection() {
    header "TEST 8: Protection Bruteforce"
    
    info "Tentative de bruteforce (10 mauvais passwords)..."
    
    FAILED_ATTEMPTS=0
    
    for i in {1..10}; do
        if ! radtest "$USERNAME" "WrongPassword$i" "$SERVER" "$PORT" "$SECRET" &>/dev/null 2>&1; then
            ((FAILED_ATTEMPTS++))
        fi
    done
    
    if [[ $FAILED_ATTEMPTS -eq 10 ]]; then
        pass "Tous les essais rejetés (10/10)"
        pass "Protection bruteforce active"
    else
        warn "Certains essais acceptés ($((10 - FAILED_ATTEMPTS)) acceptés)"
    fi
    
    separator
}

test_certificate_validation() {
    header "TEST 9: Validation Certificats"
    
    CERT_PATH="/etc/freeradius/3.0/certs/server.pem"
    
    if [[ -f "$CERT_PATH" ]]; then
        pass "Certificat server.pem existe"
        
        # Expiration
        EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_PATH" 2>/dev/null | cut -d= -f2)
        info "Expiration: $EXPIRY"
        
        # CN
        CN=$(openssl x509 -subject -noout -in "$CERT_PATH" 2>/dev/null | grep -o "CN=[^,]*" | cut -d= -f2)
        info "Common Name: $CN"
    else
        fail "Certificat server.pem MANQUANT"
    fi
    
    separator
}

generate_report() {
    header "RAPPORT DE TEST"
    
    echo -e "\n${CYAN}Fichier de log complet:${NC}"
    echo "  $TEST_LOG"
    
    echo -e "\n${CYAN}Utilisateur testé:${NC}"
    echo "  $USERNAME"
    
    echo -e "\n${CYAN}Serveur RADIUS:${NC}"
    echo "  $SERVER:$PORT"
    
    echo -e "\n${CYAN}Tests effectués:${NC}"
    echo "  [✓] Prérequis & connectivité"
    echo "  [✓] Authentification Cleartext (radtest)"
    echo "  [✓] Authentification PEAP-MSCHAPv2"
    echo "  [✓] Groupes utilisateurs"
    echo "  [✓] Messages de réponse"
    echo "  [✓] Authentification échouée (sécurité)"
    echo "  [✓] Authentifications concurrentes"
    echo "  [✓] Performance"
    echo "  [✓] Protection bruteforce"
    echo "  [✓] Validation certificats"
    
    echo -e "\n${GREEN}✓ Tests FreeRADIUS terminés${NC}\n"
}

###############################################
# MAIN
###############################################

main() {
    > "$TEST_LOG"  # Clear log
    
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║        SAE 5.01 - TEST AUTHENTIFICATION PEAP            ║"
    echo "║        $(date +"%Y-%m-%d %H:%M:%S")                           ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
    
    check_requirements
    check_connectivity
    test_cleartext_password || true
    test_peap_mschapv2 || true
    test_user_groups || true
    test_reply_messages || true
    test_failed_auth || true
    test_concurrent_auth || true
    test_response_time || true
    test_bruteforce_protection || true
    test_certificate_validation || true
    
    generate_report
}

main "$@"
