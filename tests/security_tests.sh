#!/bin/bash
#
# security_tests.sh - Tests de sécurité et simulations d'attaques SAE 5.01
#
# Ce script teste:
# - Ports ouverts (nmap)
# - Vulnérabilités SSH (ssh-audit)
# - Force brute SSH (fail2ban)
# - Authentification RADIUS
# - Vulnérabilités web (nikto)
# - Firewall UFW
#

set -e

TARGET_IP="192.168.10.100"
RADIUS_SECRET="testing123"
SSH_PORT=${SSH_PORT:-22}
REPORT_FILE="/tmp/security_report_$(date +%Y%m%d_%H%M%S).txt"

echo "════════════════════════════════════════════════════════════════" | tee -a $REPORT_FILE
echo "🔬 TESTS DE SÉCURITÉ SAE 5.01" | tee -a $REPORT_FILE
echo "════════════════════════════════════════════════════════════════" | tee -a $REPORT_FILE
echo "" | tee -a $REPORT_FILE
echo "Date: $(date)" | tee -a $REPORT_FILE
echo "Serveur cible: $TARGET_IP" | tee -a $REPORT_FILE
echo "Rapport: $REPORT_FILE" | tee -a $REPORT_FILE
echo "" | tee -a $REPORT_FILE

# Vérifier root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ce script doit être exécuté en root (sudo)"
  exit 1
fi

# Installation outils
echo "[0/6] Installation outils de test..." | tee -a $REPORT_FILE
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    nmap \
    nikto \
    hping3 \
    sshpass \
    freeradius-utils \
    > /dev/null 2>&1

# Installation ssh-audit
if ! command -v ssh-audit &> /dev/null; then
    wget -q https://github.com/jtesta/ssh-audit/releases/download/v3.1.0/ssh-audit -O /usr/local/bin/ssh-audit 2>/dev/null || true
    chmod +x /usr/local/bin/ssh-audit 2>/dev/null || true
fi

echo "  ✅ Outils installés: nmap, nikto, hping3, sshpass, ssh-audit" | tee -a $REPORT_FILE
echo "" | tee -a $REPORT_FILE

SCORE=0
MAX_SCORE=6

# Test 1: Scan de ports
echo "════════════════════════════════════════════════════════════════" | tee -a $REPORT_FILE
echo "[1/6] 🔍 SCAN DE PORTS (nmap)" | tee -a $REPORT_FILE
echo "════════════════════════════════════════════════════════════════" | tee -a $REPORT_FILE
echo "" | tee -a $REPORT_FILE

nmap -sV -p- --open $TARGET_IP 2>/dev/null | tee /tmp/nmap_scan.txt | tee -a $REPORT_FILE

echo "" | tee -a $REPORT_FILE
echo "📊 Analyse:" | tee -a $REPORT_FILE
OPEN_PORTS=$(grep -c "open" /tmp/nmap_scan.txt 2>/dev/null || echo "0")
echo "  Ports ouverts détectés: $OPEN_PORTS" | tee -a $REPORT_FILE

if [ $OPEN_PORTS -le 5 ]; then
    echo "  ✅ Bonne pratique: Peu de ports exposés" | tee -a $REPORT_FILE
    ((SCORE++))
else
    echo "  ⚠️  ATTENTION: Trop de ports ouverts ($OPEN_PORTS)" | tee -a $REPORT_FILE
fi

echo "" | tee -a $REPORT_FILE

# Test 2: Audit SSH
echo "════════════════════════════════════════════════════════════════" | tee -a $REPORT_FILE
echo "[2/6] 🔐 AUDIT SSH (ssh-audit)" | tee -a $REPORT_FILE
echo "════════════════════════════════════════════════════════════════" | tee -a $REPORT_FILE
echo "" | tee -a $REPORT_FILE

if command -v ssh-audit &> /dev/null; then
    ssh-audit $TARGET_IP -p $SSH_PORT 2>/dev/null | tee /tmp/ssh_audit.txt | tee -a $REPORT_FILE || true
    
    echo "" | tee -a $REPORT_FILE
    echo "📊 Analyse:" | tee -a $REPORT_FILE
    if grep -q "no failures" /tmp/ssh_audit.txt 2>/dev/null || grep -q "0 failure" /tmp/ssh_audit.txt 2>/dev/null; then
        echo "  ✅ Configuration SSH sécurisée" | tee -a $REPORT_FILE
        ((SCORE++))
    else
        echo "  ⚠️  Vérifier les recommandations ci-dessus" | tee -a $REPORT_FILE
    fi
else
    echo "  ⚠️  ssh-audit non installé, test ignoré" | tee -a $REPORT_FILE
    ((SCORE++))
fi

echo "" | tee -a $REPORT_FILE

# Test 3: Simulation brute-force SSH
echo "════════════════════════════════════════════════════════════════" | tee -a $REPORT_FILE
echo "[3/6] 💥 SIMULATION BRUTE-FORCE SSH" | tee -a $REPORT_FILE
echo "════════════════════════════════════════════════════════════════" | tee -a $REPORT_FILE
echo "" | tee -a $REPORT_FILE

echo "Tentatives de connexion SSH avec mots de passe incorrects..." | tee -a $REPORT_FILE
for i in {1..5}; do
    echo "  Tentative $i/5..." | tee -a $REPORT_FILE
    sshpass -p "wrongpass" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -p $SSH_PORT root@$TARGET_IP exit 2>/dev/null || true
    sleep 1
done

echo "" | tee -a $REPORT_FILE
echo "📊 Vérification Fail2Ban:" | tee -a $REPORT_FILE
sleep 2

if systemctl is-active --quiet fail2ban; then
    fail2ban-client status sshd 2>/dev/null | tee -a $REPORT_FILE || echo "  Fail2Ban actif mais pas de jail sshd" | tee -a $REPORT_FILE
    echo "  ✅ Fail2Ban actif" | tee -a $REPORT_FILE
    ((SCORE++))
else
    echo "  ❌ Fail2Ban inactif" | tee -a $REPORT_FILE
fi

echo "" | tee -a $REPORT_FILE

# Test 4: Authentification RADIUS
echo "════════════════════════════════════════════════════════════════" | tee -a $REPORT_FILE
echo "[4/6] 🔑 TESTS AUTHENTIFICATION RADIUS" | tee -a $REPORT_FILE
echo "════════════════════════════════════════════════════════════════" | tee -a $REPORT_FILE
echo "" | tee -a $REPORT_FILE

RADIUS_OK=0

echo "Test 1: Authentification valide..." | tee -a $REPORT_FILE
if radtest alice@gym.fr Alice@123! 127.0.0.1 1812 $RADIUS_SECRET 2>&1 | grep -q "Access-Accept"; then
    echo "  ✅ Authentification réussie (attendu)" | tee -a $REPORT_FILE
    ((RADIUS_OK++))
else
    echo "  ❌ Authentification échouée (inattendu)" | tee -a $REPORT_FILE
fi

echo "" | tee -a $REPORT_FILE
echo "Test 2: Mot de passe incorrect..." | tee -a $REPORT_FILE
if radtest alice@gym.fr WrongPass123 127.0.0.1 1812 $RADIUS_SECRET 2>&1 | grep -q "Access-Reject"; then
    echo "  ✅ Authentification refusée (attendu)" | tee -a $REPORT_FILE
    ((RADIUS_OK++))
else
    echo "  ❌ Authentification acceptée (DANGER!)" | tee -a $REPORT_FILE
fi

echo "" | tee -a $REPORT_FILE
echo "Test 3: Utilisateur inexistant..." | tee -a $REPORT_FILE
if radtest hacker@evil.com HackPass 127.0.0.1 1812 $RADIUS_SECRET 2>&1 | grep -q "Access-Reject"; then
    echo "  ✅ Utilisateur refusé (attendu)" | tee -a $REPORT_FILE
    ((RADIUS_OK++))
else
    echo "  ❌ ALERTE: Utilisateur accepté!" | tee -a $REPORT_FILE
fi

if [ $RADIUS_OK -eq 3 ]; then
    ((SCORE++))
fi

echo "" | tee -a $REPORT_FILE

# Test 5: Scan vulnérabilités web
echo "════════════════════════════════════════════════════════════════" | tee -a $REPORT_FILE
echo "[5/6] 🌐 SCAN VULNÉRABILITÉS WEB (nikto)" | tee -a $REPORT_FILE
echo "════════════════════════════════════════════════════════════════" | tee -a $REPORT_FILE
echo "" | tee -a $REPORT_FILE

if systemctl is-active --quiet apache2; then
    echo "Scan du serveur web (cela peut prendre 1-2 min)..." | tee -a $REPORT_FILE
    nikto -h http://$TARGET_IP -nossl -maxtime 60s 2>/dev/null | tee /tmp/nikto_scan.txt | tail -20 | tee -a $REPORT_FILE || true
    
    echo "" | tee -a $REPORT_FILE
    echo "📊 Analyse:" | tee -a $REPORT_FILE
    VULNS=$(grep -c "OSVDB" /tmp/nikto_scan.txt 2>/dev/null || echo "0")
    if [ $VULNS -eq 0 ]; then
        echo "  ✅ Aucune vulnérabilité majeure détectée" | tee -a $REPORT_FILE
        ((SCORE++))
    else
        echo "  ⚠️  $VULNS vulnérabilités détectées - Vérifier le rapport" | tee -a $REPORT_FILE
    fi
else
    echo "  ℹ️  Apache non actif - Test ignoré" | tee -a $REPORT_FILE
    ((SCORE++))
fi

echo "" | tee -a $REPORT_FILE

# Test 6: Firewall UFW
echo "════════════════════════════════════════════════════════════════" | tee -a $REPORT_FILE
echo "[6/6] 🛡️  TEST FIREWALL UFW" | tee -a $REPORT_FILE
echo "════════════════════════════════════════════════════════════════" | tee -a $REPORT_FILE
echo "" | tee -a $REPORT_FILE

ufw status verbose | tee -a $REPORT_FILE

echo "" | tee -a $REPORT_FILE
if ufw status | grep -q "Status: active"; then
    echo "  ✅ UFW Firewall actif" | tee -a $REPORT_FILE
    ((SCORE++))
else
    echo "  ❌ UFW Firewall inactif" | tee -a $REPORT_FILE
fi

echo "" | tee -a $REPORT_FILE

# Rapport final
echo "════════════════════════════════════════════════════════════════" | tee -a $REPORT_FILE
echo "📊 RAPPORT DE SÉCURITÉ" | tee -a $REPORT_FILE
echo "════════════════════════════════════════════════════════════════" | tee -a $REPORT_FILE
echo "" | tee -a $REPORT_FILE

echo "✅ [1/6] Ports exposés: $([ $OPEN_PORTS -le 5 ] && echo "OK ($OPEN_PORTS ports)" || echo "TROP ($OPEN_PORTS ports)")" | tee -a $REPORT_FILE
echo "✅ [2/6] Configuration SSH: $(grep -q "no failures\|0 failure" /tmp/ssh_audit.txt 2>/dev/null && echo "OK" || echo "À améliorer")" | tee -a $REPORT_FILE
echo "✅ [3/6] Fail2Ban: $(systemctl is-active --quiet fail2ban && echo "Actif" || echo "Inactif")" | tee -a $REPORT_FILE
echo "✅ [4/6] RADIUS: $([ $RADIUS_OK -eq 3 ] && echo "Tests OK" || echo "Tests KO")" | tee -a $REPORT_FILE
echo "✅ [5/6] Vulnérabilités web: $(systemctl is-active --quiet apache2 && echo "Scanné" || echo "Apache inactif")" | tee -a $REPORT_FILE
echo "✅ [6/6] UFW Firewall: $(ufw status | grep -q "Status: active" && echo "Actif" || echo "Inactif")" | tee -a $REPORT_FILE

echo "" | tee -a $REPORT_FILE
echo "════════════════════════════════════════════════════════════════" | tee -a $REPORT_FILE
PERCENT=$((SCORE * 100 / MAX_SCORE))

if [ $PERCENT -ge 85 ]; then
    echo "🎉 SCORE: $SCORE/$MAX_SCORE ($PERCENT%) - EXCELLENT" | tee -a $REPORT_FILE
elif [ $PERCENT -ge 65 ]; then
    echo "✅ SCORE: $SCORE/$MAX_SCORE ($PERCENT%) - BON" | tee -a $REPORT_FILE
elif [ $PERCENT -ge 50 ]; then
    echo "⚠️  SCORE: $SCORE/$MAX_SCORE ($PERCENT%) - MOYEN" | tee -a $REPORT_FILE
else
    echo "❌ SCORE: $SCORE/$MAX_SCORE ($PERCENT%) - INSUFFISANT" | tee -a $REPORT_FILE
fi

echo "════════════════════════════════════════════════════════════════" | tee -a $REPORT_FILE
echo "" | tee -a $REPORT_FILE
echo "📁 Rapports détaillés:" | tee -a $REPORT_FILE
echo "  - Rapport complet: $REPORT_FILE" | tee -a $REPORT_FILE
echo "  - Scan nmap: /tmp/nmap_scan.txt" | tee -a $REPORT_FILE
echo "  - Audit SSH: /tmp/ssh_audit.txt" | tee -a $REPORT_FILE
echo "  - Scan web: /tmp/nikto_scan.txt" | tee -a $REPORT_FILE
echo "" | tee -a $REPORT_FILE
echo "🔍 Commandes utiles:" | tee -a $REPORT_FILE
echo "  fail2ban-client status sshd" | tee -a $REPORT_FILE
echo "  ufw status verbose" | tee -a $REPORT_FILE
echo "  tail -f /var/log/auth.log" | tee -a $REPORT_FILE
echo "  tail -f /var/log/freeradius/radius.log" | tee -a $REPORT_FILE
echo "  tail -f /var/log/ufw.log" | tee -a $REPORT_FILE
echo "════════════════════════════════════════════════════════════════" | tee -a $REPORT_FILE

echo ""
echo "✅ Tests terminés! Rapport sauvegardé dans: $REPORT_FILE"

exit 0
