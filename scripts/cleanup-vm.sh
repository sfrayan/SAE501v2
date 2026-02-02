#!/bin/bash
###############################################
# cleanup-vm.sh - Nettoyage complet VM SAE 5.01
###############################################
# Exécuter AVANT : rm -rf SAE501v2 && git clone ...
# Usage: sudo bash cleanup-vm.sh

set -e

echo "🧹 NETTOYAGE VM SAE 5.01..."
echo ""

# ===== ARRÊTER LES SERVICES =====
echo "[1/7] Arrêt des services..."
sudo systemctl stop freeradius 2>/dev/null || echo "  ⚠ FreeRADIUS non trouvé"
sudo systemctl stop apache2 2>/dev/null || echo "  ⚠ Apache2 non trouvé"
sudo systemctl stop nginx 2>/dev/null || echo "  ⚠ Nginx non trouvé"
sudo systemctl stop mysql 2>/dev/null || echo "  ⚠ MySQL non trouvé"
sudo systemctl stop mariadb 2>/dev/null || echo "  ⚠ MariaDB non trouvé"

# Arrêter Wazuh Docker
if command -v docker &>/dev/null; then
    echo "  Arrêt Wazuh Docker..."
    cd /opt/wazuh-docker/single-node 2>/dev/null && docker compose down 2>/dev/null || echo "  ⚠ Wazuh Docker non trouvé"
fi

echo "✅ Services arrêtés"
echo ""

# ===== SUPPRIMER RÉPERTOIRES D'INSTALLATION =====
echo "[2/7] Suppression répertoires d'installation..."
sudo rm -rf /opt/wazuh-docker 2>/dev/null && echo "  ✓ /opt/wazuh-docker supprimé" || echo "  ⚠ /opt/wazuh-docker non trouvé"
sudo rm -rf /var/www/html/php-admin 2>/dev/null && echo "  ✓ /var/www/html/php-admin supprimé" || echo "  ⚠ PHP-Admin non trouvé"
sudo rm -rf /etc/freeradius 2>/dev/null && echo "  ✓ /etc/freeradius supprimé" || echo "  ⚠ FreeRADIUS non trouvé"

echo "✅ Répertoires supprimés"
echo ""

# ===== NETTOYER BASES DE DONNÉES =====
echo "[3/7] Nettoyage bases de données..."

# MySQL/MariaDB
if command -v mysql &>/dev/null; then
    echo "  Suppression base 'radius'..."
    mysql -e "DROP DATABASE IF EXISTS radius;" 2>/dev/null || echo "  ⚠ Impossible de supprimer la base radius"
    mysql -e "DROP USER IF EXISTS 'radius'@'localhost';" 2>/dev/null || echo "  ⚠ Utilisateur radius introuvable"
    mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || echo "  ⚠ FLUSH PRIVILEGES échoué"
    echo "  ✓ Base de données nettoyée"
else
    echo "  ⚠ MySQL/MariaDB non installé"
fi

echo "✅ Bases de données nettoyées"
echo ""

# ===== NETTOYER LOGS =====
echo "[4/7] Nettoyage des logs..."
sudo rm -rf /var/log/freeradius/* 2>/dev/null && echo "  ✓ Logs FreeRADIUS supprimés" || echo "  ⚠ Logs FreeRADIUS non trouvés"
sudo rm -rf /var/log/wazuh-export/* 2>/dev/null && echo "  ✓ Logs Wazuh export supprimés" || echo "  ⚠ Logs Wazuh non trouvés"
sudo truncate -s 0 /var/log/syslog 2>/dev/null && echo "  ✓ Syslog vidé" || echo "  ⚠ Syslog non accessible"
sudo truncate -s 0 /var/log/auth.log 2>/dev/null && echo "  ✓ Auth.log vidé" || echo "  ⚠ Auth.log non accessible"

echo "✅ Logs nettoyés"
echo ""

# ===== SUPPRIMER UTILISATEURS/GROUPES =====
echo "[5/7] Suppression utilisateurs/groupes..."
sudo userdel -r freerad 2>/dev/null && echo "  ✓ Utilisateur freerad supprimé" || echo "  ⚠ Utilisateur freerad non trouvé"
sudo groupdel freerad 2>/dev/null && echo "  ✓ Groupe freerad supprimé" || echo "  ⚠ Groupe freerad non trouvé"

echo "✅ Utilisateurs/groupes nettoyés"
echo ""

# ===== PURGER PAQUETS =====
echo "[6/7] Purge des paquets (optionnel, décommenter si nécessaire)..."
echo "  Pour purger complètement les paquets anciens, exécutez :"
echo "  sudo apt purge freeradius freeradius-* -y"
echo "  sudo apt purge wazuh-* -y"
echo "  sudo apt autoremove -y"
echo "  sudo apt autoclean -y"

echo "✅ Paquets analysés"
echo ""

# ===== NETTOYER CRONTAB =====
echo "[7/7] Nettoyage crontab..."
# Supprimer les jobs cron de Wazuh
if crontab -l 2>/dev/null | grep -q "export-wazuh-logs"; then
    echo "  Suppression tâche cron Wazuh..."
    crontab -l 2>/dev/null | grep -v "export-wazuh-logs" | crontab - || echo "  ⚠ Erreur suppression crontab"
    echo "  ✓ Tâche cron Wazuh supprimée"
else
    echo "  ✓ Aucune tâche cron Wazuh à supprimer"
fi

echo "✅ Crontab nettoyée"
echo ""

# ===== RÉSUMÉ =====
echo "═══════════════════════════════════════════════════════════════"
echo "✅ NETTOYAGE COMPLET TERMINÉ !"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Prochaines étapes :"
echo "  1. rm -rf ~/SAE501v2"
echo "  2. git clone https://github.com/sfrayan/SAE501v2.git"
echo "  3. cd SAE501v2"
echo "  4. chmod +x scripts/*.sh"
echo "  5. sudo bash scripts/install_radius.sh"
echo "  6. sudo bash scripts/install_php_admin.sh"
echo "  7. sudo bash scripts/install_wazuh.sh"
echo "  8. sudo bash scripts/diagnostics.sh"
echo ""
