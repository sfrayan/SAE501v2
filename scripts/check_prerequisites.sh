#!/bin/bash
#
# check_prerequisites.sh - Vérification prérequis SAE501v2
# À exécuter AVANT install_all.sh
#
# Usage: bash scripts/check_prerequisites.sh
#

set -u

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

FAIL_COUNT=0
WARN_COUNT=0

echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════╗"
echo "║       SAE 5.01 - Vérification des Prérequis           ║"
echo "║       $(date +"%Y-%m-%d %H:%M:%S")                           ║"
echo "╚════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# 1. Vérifier Debian 11
echo -n "🐧 Vérification OS version... "
if lsb_release -d 2>/dev/null | grep -q "Debian GNU/Linux 11"; then
    echo -e "${GREEN}✓ Debian 11${NC}"
else
    OS=$(lsb_release -d 2>/dev/null | cut -f2- || echo "Inconnu")
    echo -e "${RED}✗ Pas Debian 11 (détecté: $OS)${NC}"
    ((FAIL_COUNT++))
fi

# 2. Vérifier RAM
echo -n "💾 Vérification RAM... "
RAM_MB=$(free -m | awk '/^Mem:/ {print $2}')
if [ "$RAM_MB" -ge 3800 ]; then
    echo -e "${GREEN}✓ ${RAM_MB}MB (≥4GB requis)${NC}"
else
    echo -e "${RED}✗ ${RAM_MB}MB (minimum 4GB requis)${NC}"
    echo -e "${YELLOW}   ⚠️  Wazuh nécessite au moins 4GB de RAM${NC}"
    ((FAIL_COUNT++))
fi

# 3. Vérifier espace disque
echo -n "💿 Vérification espace disque... "
DISK_GB=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$DISK_GB" -ge 20 ]; then
    echo -e "${GREEN}✓ ${DISK_GB}GB libres (≥20GB requis)${NC}"
else
    echo -e "${RED}✗ ${DISK_GB}GB (minimum 20GB requis)${NC}"
    ((FAIL_COUNT++))
fi

# 4. Vérifier CPU cores
echo -n "⚙️  Vérification CPU... "
CPU_CORES=$(nproc)
if [ "$CPU_CORES" -ge 2 ]; then
    echo -e "${GREEN}✓ ${CPU_CORES} cores${NC}"
else
    echo -e "${YELLOW}⚠ ${CPU_CORES} core (2 cores recommandés)${NC}"
    ((WARN_COUNT++))
fi

# 5. Vérifier interface enp0s8 (Bridge)
echo -n "🌐 Vérification enp0s8 (Bridge)... "
if ip addr show enp0s8 2>/dev/null | grep -q "inet 192.168.10.100"; then
    echo -e "${GREEN}✓ 192.168.10.100/24 configurée${NC}"
elif ip addr show enp0s8 &>/dev/null; then
    IP=$(ip addr show enp0s8 | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    if [ -n "$IP" ]; then
        echo -e "${RED}✗ IP incorrecte: $IP (attendu: 192.168.10.100)${NC}"
    else
        echo -e "${RED}✗ Pas d'IP configurée${NC}"
    fi
    ((FAIL_COUNT++))
else
    echo -e "${RED}✗ Interface enp0s8 inexistante${NC}"
    ((FAIL_COUNT++))
fi

# 6. Vérifier interface enp0s3 (NAT)
echo -n "🌐 Vérification enp0s3 (NAT)... "
if ip addr show enp0s3 2>/dev/null | grep -q "inet "; then
    IP=$(ip addr show enp0s3 | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    echo -e "${GREEN}✓ $IP (accès Internet)${NC}"
else
    echo -e "${RED}✗ Interface enp0s3 non configurée${NC}"
    ((FAIL_COUNT++))
fi

# 7. Vérifier connectivité Internet
echo -n "🌍 Vérification connexion Internet... "
if ping -I enp0s3 -c 2 -W 3 8.8.8.8 &>/dev/null 2>&1; then
    echo -e "${GREEN}✓ Connexion OK (via enp0s3)${NC}"
else
    echo -e "${RED}✗ Pas de connexion Internet${NC}"
    echo -e "${YELLOW}   ⚠️  enp0s3 doit avoir accès Internet pour apt-get${NC}"
    ((FAIL_COUNT++))
fi

# 8. Vérifier apt sources
echo -n "📦 Vérification sources APT... "
if timeout 10 sudo apt update &>/dev/null; then
    echo -e "${GREEN}✓ apt update réussi${NC}"
else
    echo -e "${RED}✗ Échec apt update${NC}"
    ((FAIL_COUNT++))
fi

# 9. Vérifier accès root
echo -n "🔐 Vérification accès sudo... "
if sudo -n true 2>/dev/null; then
    echo -e "${GREEN}✓ Accès root OK${NC}"
else
    echo -e "${YELLOW}⚠ Mot de passe sudo requis${NC}"
    ((WARN_COUNT++))
fi

# 10. Vérifier dépendances de base
echo -n "🛠️  Vérification dépendances... "
MISSING_DEPS=()
for cmd in git curl wget; do
    if ! command -v $cmd &>/dev/null; then
        MISSING_DEPS+=($cmd)
    fi
done

if [ ${#MISSING_DEPS[@]} -eq 0 ]; then
    echo -e "${GREEN}✓ git, curl, wget installés${NC}"
else
    echo -e "${YELLOW}⚠ Manquant: ${MISSING_DEPS[*]}${NC}"
    echo -e "${YELLOW}   Installation: sudo apt install -y ${MISSING_DEPS[*]}${NC}"
    ((WARN_COUNT++))
fi

# 11. Vérifier si services déjà installés
echo ""
echo "🔍 Vérification services existants..."
SERVICES_INSTALLED=()

if systemctl is-active --quiet freeradius 2>/dev/null; then
    SERVICES_INSTALLED+=("FreeRADIUS")
fi
if systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mariadb 2>/dev/null; then
    SERVICES_INSTALLED+=("MySQL/MariaDB")
fi
if command -v docker &>/dev/null && docker ps 2>/dev/null | grep -q "wazuh"; then
    SERVICES_INSTALLED+=("Wazuh")
fi
if systemctl is-active --quiet apache2 2>/dev/null; then
    SERVICES_INSTALLED+=("Apache")
fi

if [ ${#SERVICES_INSTALLED[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠ Services déjà installés: ${SERVICES_INSTALLED[*]}${NC}"
    echo -e "${YELLOW}   Installation peut écraser la configuration existante${NC}"
    ((WARN_COUNT++))
else
    echo -e "${GREEN}✓ Aucun service existant détecté${NC}"
fi

# Résumé
echo ""
echo "══════════════════════════════════════════════════════════"
echo ""

if [ "$FAIL_COUNT" -eq 0 ] && [ "$WARN_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✅ TOUS LES PRÉREQUIS SONT SATISFAITS !${NC}"
    echo ""
    echo "Vous pouvez continuer avec :"
    echo -e "${CYAN}  sudo bash scripts/install_all.sh${NC}"
    echo ""
    exit 0
elif [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  PRÉREQUIS OK AVEC ${WARN_COUNT} AVERTISSEMENT(S)${NC}"
    echo ""
    echo "Vous pouvez continuer, mais vérifiez les avertissements ci-dessus."
    echo ""
    echo "Pour continuer :"
    echo -e "${CYAN}  sudo bash scripts/install_all.sh${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}❌ ${FAIL_COUNT} PRÉREQUIS CRITIQUES MANQUANTS${NC}"
    if [ "$WARN_COUNT" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  ${WARN_COUNT} avertissement(s) supplémentaire(s)${NC}"
    fi
    echo ""
    echo "📖 Actions requises :"
    echo ""
    
    # Suggestions basées sur les erreurs
    if ip addr show enp0s8 &>/dev/null && ! ip addr show enp0s8 | grep -q "192.168.10.100"; then
        echo "1. Configurer l'interface enp0s8 :"
        echo "   sudo nano /etc/network/interfaces"
        echo "   Ajouter :"
        echo "   auto enp0s8"
        echo "   iface enp0s8 inet static"
        echo "       address 192.168.10.100"
        echo "       netmask 255.255.255.0"
        echo ""
        echo "   Puis : sudo systemctl restart networking"
        echo ""
    fi
    
    if ! ip addr show enp0s3 &>/dev/null || ! ip addr show enp0s3 | grep -q "inet "; then
        echo "2. Configurer l'interface enp0s3 :"
        echo "   sudo nano /etc/network/interfaces"
        echo "   Ajouter :"
        echo "   auto enp0s3"
        echo "   iface enp0s3 inet dhcp"
        echo ""
        echo "   Puis : sudo systemctl restart networking"
        echo ""
    fi
    
    echo "📚 Consultez le README.md section 'Configuration Réseau IMPORTANTE'"
    echo ""
    exit 1
fi
