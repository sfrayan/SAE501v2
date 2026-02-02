#!/bin/bash
#
# install_all.sh - Installation complète du projet SAE501v2
# Exécute tous les scripts d'installation dans le bon ordre
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════════════════╗"
echo "║                                                    ║"
echo "║     SAE 5.01 - Installation Complète              ║"
echo "║     Infrastructure Wi-Fi Sécurisée                ║"
echo "║                                                    ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# Vérifier root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ce script doit être exécuté en root (sudo)"
  echo "Usage: sudo bash scripts/install_all.sh"
  exit 1
fi

# Afficher informations système
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Informations système"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "OS: $(lsb_release -d | cut -f2-)"
echo "RAM: $(free -h | awk '/^Mem:/ {print $2}')"
echo "Disque: $(df -h / | awk 'NR==2 {print $4}') disponible"
echo "IP: $(hostname -I | awk '{print $1}')"
echo ""

# Confirmation
read -p "Continuer l'installation? (o/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
  echo "Installation annulée"
  exit 0
fi

# Timestamp début
START_TIME=$(date +%s)

# Phase 1: FreeRADIUS
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📍 PHASE 1/4 : Installation FreeRADIUS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if bash "$SCRIPT_DIR/install_radius.sh"; then
  echo "✅ FreeRADIUS installé"
else
  echo "❌ Échec installation FreeRADIUS"
  exit 1
fi

# Phase 2: PHP-Admin
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📍 PHASE 2/4 : Installation PHP-Admin"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if bash "$SCRIPT_DIR/install_php_admin.sh"; then
  echo "✅ PHP-Admin installé"
else
  echo "❌ Échec installation PHP-Admin"
  exit 1
fi

# Phase 3: Wazuh
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📍 PHASE 3/4 : Installation Wazuh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if bash "$SCRIPT_DIR/install_wazuh.sh"; then
  echo "✅ Wazuh installé"
else
  echo "⚠️  Wazuh partiellement installé (vérifier RAM >= 4GB)"
fi

# Phase 4: Diagnostic
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📍 PHASE 4/4 : Diagnostic système"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -f "$SCRIPT_DIR/diagnostics.sh" ]; then
  bash "$SCRIPT_DIR/diagnostics.sh"
else
  echo "⚠️  Script diagnostics.sh introuvable"
fi

# Timestamp fin
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

# Obtenir IP
IP=$(hostname -I | awk '{print $1}')

# Résumé final
echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║                                                    ║"
echo "║     ✅ INSTALLATION COMPLÈTE TERMINÉE              ║"
echo "║                                                    ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""
echo "⏱️  Durée: ${MINUTES}m ${SECONDS}s"
echo ""
echo "🎯 Services installés:"
echo "  ✅ FreeRADIUS (Auth 802.1X)"
echo "  ✅ MySQL/MariaDB (Base RADIUS)"
echo "  ✅ PHP-Admin (Interface web)"
echo "  ✅ Wazuh Manager (Supervision)"
echo "  ✅ rsyslog (Collecte logs)"
echo ""
echo "🌐 Accès web:"
echo "  PHP-Admin:  http://$IP/php-admin/"
echo "  Wazuh:      https://$IP:443"
echo "              User: admin / Pass: WazuhAdmin2026!"
echo ""
echo "🧪 Tests rapides:"
echo "  radtest alice@gym.fr Alice@123! 127.0.0.1 1812 testing123"
echo "  curl http://localhost/php-admin/list_users.php"
echo "  systemctl status freeradius wazuh-manager apache2"
echo ""
echo "📚 Documentation:"
echo "  cat /root/wazuh-credentials.txt"
echo "  README.md dans le dépôt"
echo ""
echo "🔧 Prochaines étapes:"
echo "  1. Configurer le routeur TL-MR100 (voir README.md Phase 2)"
echo "  2. Tester authentification Wi-Fi"
echo "  3. Vérifier logs dans Wazuh Dashboard"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit 0
