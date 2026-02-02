#!/bin/bash

###############################################
# diagnostics.sh - Diagnostic Système SAE 5.01
###############################################
#
# Fichier: scripts/diagnostics.sh
# Auteur: GroupeNani
# Date: 4 janvier 2026
#
# Description:
#   Script de diagnostic complet du déploiement SAE 5.01.
#   Vérifie l'état de tous les services, ports, certificats, BD, etc.
#
# Utilisation:
#   $ sudo bash scripts/diagnostics.sh
#   ou
#   $ bash scripts/diagnostics.sh (sans sudo, mais certains tests requis root)
#
# Sortie:
#   Génère un rapport HTML et un fichier de diagnostic complet
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

# Output files
DIAG_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DIAG_LOG="/tmp/diag_${DIAG_TIMESTAMP}.txt"
DIAG_HTML="/tmp/diag_${DIAG_TIMESTAMP}.html"
DIAG_JSON="/tmp/diag_${DIAG_TIMESTAMP}.json"

# Conteurs
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

###############################################
# FONCTIONS
###############################################

header() {
    echo -e "\n${CYAN}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  $1${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}\n"
}

pass() {
    echo -e "${GREEN}✓${NC} $1" | tee -a "$DIAG_LOG"
    ((PASS_COUNT++))
}

fail() {
    echo -e "${RED}✗${NC} $1" | tee -a "$DIAG_LOG"
    ((FAIL_COUNT++))
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1" | tee -a "$DIAG_LOG"
    ((WARN_COUNT++))
}

info() {
    echo -e "${BLUE}ℹ${NC} $1" | tee -a "$DIAG_LOG"
}

separator() {
    echo "═══════════════════════════════════════════════════════" | tee -a "$DIAG_LOG"
}

###############################################
# CONTRÔLES SYSTÈME
###############################################

check_system() {
    header "SYSTÈME"
    
    HOSTNAME=$(hostname)
    OS=$(lsb_release -d | cut -f2)
    KERNEL=$(uname -r)
    UPTIME=$(uptime -p 2>/dev/null || uptime)
    
    info "Hostname: $HOSTNAME"
    info "OS: $OS"
    info "Kernel: $KERNEL"
    info "Uptime: $UPTIME"
    
    separator
}

check_users() {
    header "UTILISATEURS & GROUPES"
    
    if id wazuh &>/dev/null; then
        pass "Utilisateur wazuh existe"
    else
        info "Utilisateur wazuh n'existe pas (Wazuh non installé)"
    fi
    
    if id freerad &>/dev/null; then
        pass "Utilisateur freerad existe"
    else
        fail "Utilisateur freerad n'existe pas"
    fi
    
    separator
}

check_freeradius() {
    header "FREERADIUS"
    
    # Service
    if systemctl is-active --quiet freeradius; then
        pass "Service FreeRADIUS actif"
    else
        fail "Service FreeRADIUS INACTIF"
    fi
    
    # Port 1812-1813
    if ss -lun 2>/dev/null | grep -q ":1812\|:1813"; then
        pass "Ports 1812-1813 UDP en écoute"
    else
        warn "Ports 1812-1813 UDP NON détectés"
    fi
    
    # Config
    if [[ -f /etc/freeradius/3.0/clients.conf ]]; then
        pass "Fichier clients.conf existe"
    else
        fail "clients.conf MANQUANT"
    fi
    
    # Base de données
    if [[ -f /etc/freeradius/3.0/mods-enabled/sql ]]; then
        pass "Module SQL activé"
    else
        warn "Module SQL non détecté"
    fi
    
    # Certificats
    if [[ -f /etc/freeradius/3.0/certs/server.pem ]]; then
        CERT_DATE=$(openssl x509 -in /etc/freeradius/3.0/certs/server.pem -noout -enddate 2>/dev/null | cut -d= -f2)
        pass "Certificat server.pem valide (expire: $CERT_DATE)"
    else
        fail "Certificat server.pem MANQUANT"
    fi
    
    separator
}

check_mysql() {
    header "MYSQL/MARIADB"
    
    if systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mariadb 2>/dev/null; then
        pass "Service MySQL/MariaDB actif"
    else
        fail "MySQL/MariaDB INACTIF"
    fi
    
    # Port 3306
    if ss -ltn 2>/dev/null | grep -q ":3306"; then
        pass "Port 3306 TCP en écoute"
    else
        warn "Port 3306 TCP non en écoute"
    fi
    
    # Base RADIUS
    if mysql -e "SELECT 1 FROM radius.radcheck LIMIT 1;" &>/dev/null; then
        USERS=$(mysql -s -e "SELECT COUNT(*) FROM radius.radcheck;" 2>/dev/null | tr -d ' ')
        pass "Base 'radius' accessible ($USERS utilisateurs)"
    else
        fail "Base 'radius' NON ACCESSIBLE"
    fi
    
    separator
}

check_wazuh() {
    header "WAZUH"
    
    # Check Docker Wazuh
    if command -v docker &>/dev/null && docker ps 2>/dev/null | grep -q "wazuh.manager"; then
        pass "Wazuh Docker en cours d'exécution"
        
        # Vérifier les logs exportés
        if [[ -f /var/log/wazuh-export/alerts.json ]]; then
            SIZE=$(stat -c %s /var/log/wazuh-export/alerts.json 2>/dev/null)
            if [[ $SIZE -gt 10 ]]; then
                pass "Logs Wazuh exportés: $SIZE bytes"
            else
                fail "Logs Wazuh : Fichier vide (0 bytes)"
            fi
        else
            fail "Logs Wazuh : Fichier d'export manquant"
        fi
        
        # Vérifier cron export
        if crontab -l 2>/dev/null | grep -q "export-wazuh-logs"; then
            pass "Cron export : Configuré"
        else
            fail "Cron export : Pas configuré"
        fi
        
    elif pgrep -x wazuh-analysisd >/dev/null 2>&1; then
        pass "Service Wazuh Manager actif (natif)"
    else
        warn "Service Wazuh Manager non actif (optionnel)"
    fi
    
    # Répertoire
    if [[ -d /var/ossec ]] || [[ -d /opt/wazuh-docker ]]; then
        pass "Répertoire Wazuh existe"
    else
        warn "Wazuh non installé (optionnel)"
    fi
    
    separator
}

check_web() {
    header "SERVICES WEB"
    
    # PHP-Admin
    if [[ -d /var/www/html/php-admin ]]; then
        pass "Répertoire PHP-Admin existe"
        
        if [[ -f /var/www/html/php-admin/index.php ]]; then
            pass "Fichier index.php existe"
        else
            fail "index.php MANQUANT"
        fi
    else
        warn "Répertoire PHP-Admin non trouvé"
    fi
    
    # Apache/Nginx
    if systemctl is-active --quiet apache2; then
        pass "Apache en cours d'exécution"
    elif systemctl is-active --quiet nginx; then
        pass "Nginx en cours d'exécution"
    else
        warn "Apache/Nginx n'est pas en cours d'exécution"
    fi
    
    separator
}

check_routing() {
    header "RÉSEAU & ROUTING"
    
    # Interface enp0s8 (Bridge)
    if ip addr show enp0s8 2>/dev/null | grep -q "inet.*192.168.10"; then
        IP=$(ip addr show enp0s8 | grep "inet.*192.168.10" | awk '{print $2}' | cut -d/ -f1)
        pass "Interface enp0s8 (Bridge) : $IP"
    else
        warn "Interface enp0s8 non trouvée ou pas d'IP 192.168.10.x"
    fi
    
    # Interface enp0s3 (NAT)
    if ip addr show enp0s3 2>/dev/null | grep -q "inet"; then
        IP=$(ip addr show enp0s3 | grep "inet" | grep -v inet6 | awk '{print $2}' | cut -d/ -f1 | head -1)
        pass "Interface enp0s3 (NAT) : $IP"
    else
        warn "Interface enp0s3 non trouvée"
    fi
    
    # Gateway
    GATEWAY=$(ip route | grep "^default" | awk '{print $3}')
    if [[ -n "$GATEWAY" ]]; then
        pass "Gateway configurée: $GATEWAY"
    else
        warn "Gateway non configurée"
    fi
    
    # DNS
    if grep -q "nameserver" /etc/resolv.conf; then
        DNS=$(grep "nameserver" /etc/resolv.conf | head -1 | awk '{print $2}')
        pass "DNS configuré: $DNS"
    else
        warn "DNS non configuré"
    fi
    
    separator
}

check_firewall() {
    header "FIREWALL & SÉCURITÉ"

    # UFW status
    if command -v ufw &>/dev/null; then
        if ufw status | grep -q "Status: active"; then
            pass "UFW : Installé et actif"

            # Ports RADIUS (1812-1813)
            if ufw status | grep -qE "1812/(tcp|udp)|1813/(tcp|udp)"; then
                pass "Règles UFW présentes pour les ports RADIUS (1812-1813)"
            else
                warn "Aucune règle UFW explicite pour les ports 1812-1813 (RADIUS)"
            fi

            # Port SSH 22
            if ufw status | grep -q "22/tcp"; then
                pass "Port 22 SSH autorisé par UFW"
            else
                warn "Port 22 SSH potentiellement bloqué par UFW"
            fi
        else
            warn "UFW installé mais inactif"
        fi
    else
        fail "UFW : Pas installé"
    fi
    
    separator
}

check_logs() {
    header "LOGS"
    
    # FreeRADIUS logs
    if [[ -f /var/log/freeradius/radius.log ]]; then
        SIZE=$(du -h /var/log/freeradius/radius.log | awk '{print $1}')
        pass "Log FreeRADIUS accessible ($SIZE)"
    else
        warn "Log FreeRADIUS non trouvé"
    fi
    
    # Syslog
    if [[ -f /var/log/syslog ]]; then
        SIZE=$(du -h /var/log/syslog | awk '{print $1}')
        pass "Syslog accessible ($SIZE)"
    else
        warn "Syslog non trouvé"
    fi
    
    # Auth logs
    if [[ -f /var/log/auth.log ]]; then
        SIZE=$(du -h /var/log/auth.log | awk '{print $1}')
        pass "Auth.log accessible ($SIZE)"
    else
        warn "Auth.log non trouvé"
    fi
    
    separator
}

check_files() {
    header "FICHIERS PROJET"
    
    declare -a FILES=(
        "radius/clients.conf"
        "radius/users.txt"
        "radius/sql/init_appuser.sql"
        "radius/sql/create_tables.sql"
        "wazuh/manager.conf"
        "wazuh/local_rules.xml"
        "wazuh/syslog-tlmr100.conf"
        "php-admin/index.php"
        "php-admin/config.php"
        "scripts/install_radius.sh"
        "scripts/install_wazuh.sh"
        "scripts/diagnostics.sh"
    )
    
    for file in "${FILES[@]}"; do
        if [[ -f "$PROJECT_ROOT/$file" ]]; then
            pass "$file"
        else
            fail "$file MANQUANT"
        fi
    done
    
    separator
}

check_connectivity() {
    header "CONNECTIVITÉ"
    
    # Ping router TL-MR100 (gateway)
    if ping -c 1 -W 2 192.168.10.1 &>/dev/null; then
        pass "Ping routeur TP-Link (192.168.10.1) OK"
    else
        warn "Ping routeur TP-Link échoué (vérifier câble RJ45)"
    fi
    
    # Ping DNS externe
    if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        pass "Connectivité internet OK (8.8.8.8)"
    else
        warn "Pas de connectivité internet"
    fi
    
    separator
}

generate_summary() {
    header "RÉSUMÉ"
    
    TOTAL=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT))
    
    echo -e "${GREEN}✓ PASS: $PASS_COUNT${NC}"
    echo -e "${RED}✗ FAIL: $FAIL_COUNT${NC}"
    echo -e "${YELLOW}⚠ WARN: $WARN_COUNT${NC}"
    echo "  TOTAL: $TOTAL"
    
    # Score
    if [[ $TOTAL -gt 0 ]]; then
        PERCENTAGE=$((PASS_COUNT * 100 / TOTAL))
        echo ""
        echo "Score: ${PERCENTAGE}%"
        
        if [[ $PERCENTAGE -ge 90 ]]; then
            echo -e "${GREEN}État: ✓ EXCELLENT${NC}"
        elif [[ $PERCENTAGE -ge 70 ]]; then
            echo -e "${YELLOW}État: ⚠ BON${NC}"
        else
            echo -e "${RED}État: ✗ CRITIQUE${NC}"
        fi
    fi
    
    separator
    
    echo -e "\n${BLUE}Fichiers de rapport:${NC}"
    echo "  Log: $DIAG_LOG"
    echo "  JSON: $DIAG_JSON"
    echo ""
}

generate_html_report() {
    cat > "$DIAG_HTML" <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Diagnostic SAE 5.01</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .section { margin: 20px 0; border: 1px solid #ddd; padding: 15px; }
        .pass { color: #27ae60; }
        .fail { color: #e74c3c; }
        .warn { color: #f39c12; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
    </style>
</head>
<body>
    <h1>📊 Diagnostic SAE 5.01</h1>
    <p>Généré: $(date)</p>
    
    <div class="section">
        <h2>Résumé</h2>
        <table>
            <tr>
                <td><strong>PASS</strong></td>
                <td class="pass">$PASS_COUNT</td>
            </tr>
            <tr>
                <td><strong>FAIL</strong></td>
                <td class="fail">$FAIL_COUNT</td>
            </tr>
            <tr>
                <td><strong>WARN</strong></td>
                <td class="warn">$WARN_COUNT</td>
            </tr>
        </table>
    </div>
    
    <div class="section">
        <h2>Détails</h2>
        <pre>$(cat "$DIAG_LOG")</pre>
    </div>
</body>
</html>
EOF
    
    echo "Rapport HTML généré: $DIAG_HTML"
}

###############################################
# MAIN
###############################################

main() {
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║        SAE 5.01 - DIAGNOSTIC SYSTÈME COMPLET            ║"
    echo "║        $(date +"%Y-%m-%d %H:%M:%S")                           ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
    
    > "$DIAG_LOG"  # Clear log
    
    check_system
    check_users
    check_freeradius
    check_mysql
    check_wazuh
    check_web
    check_routing
    check_firewall
    check_logs
    check_files
    check_connectivity
    
    generate_summary
    generate_html_report
}

main "$@"
