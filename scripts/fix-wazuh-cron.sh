#!/bin/bash
###############################################
# fix-wazuh-cron.sh - Configuration cron Wazuh
###############################################
# Exécutez ce script si le diagnostic indique:
# "✗ Cron export : Pas configuré"
#
# Usage: sudo bash scripts/fix-wazuh-cron.sh

set -e

echo "🔧 FIX RAPIDE - Configuration cron export Wazuh"
echo ""

if [ "$EUID" -ne 0 ]; then
  echo "❌ Exécuter en root (sudo)"
  exit 1
fi

# Vérifier que Wazuh Docker est installé
if ! command -v docker &>/dev/null; then
    echo "❌ Docker n'est pas installé. Installez Wazuh d'abord."
    exit 1
fi

if ! docker ps 2>/dev/null | grep -q "wazuh.manager"; then
    echo "❌ Wazuh Docker n'est pas en cours d'exécution."
    echo "Démarrez-le avec : cd /opt/wazuh-docker/single-node && docker compose up -d"
    exit 1
fi

echo "[1/4] Vérification du conteneur Wazuh..."
echo "✅ Wazuh Docker en cours d'exécution"

# Créer le répertoire d'export
echo "[2/4] Création répertoire d'export..."
mkdir -p /var/log/wazuh-export
chmod 755 /var/log/wazuh-export
echo "✅ Répertoire /var/log/wazuh-export créé"

# Créer le script d'export
echo "[3/4] Création script d'export..."
cat > /usr/local/bin/export-wazuh-logs.sh <<'SCRIPT'
#!/bin/bash
LOG_FILE="/var/log/wazuh-export/alerts.json"

# Ensure container is running
if ! docker exec single-node-wazuh.manager-1 echo "test" > /dev/null 2>&1; then
  echo "[]" > "$LOG_FILE"
  chmod 644 "$LOG_FILE"
  exit 0
fi

# Export logs
docker exec single-node-wazuh.manager-1 tail -n 1000 /var/ossec/logs/alerts/alerts.json > "$LOG_FILE" 2>/dev/null || echo "[]" > "$LOG_FILE"
chmod 644 "$LOG_FILE"
SCRIPT

chmod +x /usr/local/bin/export-wazuh-logs.sh
echo "✅ Script /usr/local/bin/export-wazuh-logs.sh créé"

# Configurer le cron
echo "[4/4] Configuration cron..."

# Supprimer ancienne entrée si existe
crontab -l 2>/dev/null | grep -v "export-wazuh-logs" > /tmp/crontab_tmp 2>/dev/null || true

# Ajouter nouvelle entrée
echo "*/2 * * * * /usr/local/bin/export-wazuh-logs.sh" >> /tmp/crontab_tmp

# Installer le crontab
crontab /tmp/crontab_tmp
rm -f /tmp/crontab_tmp

echo "✅ Cron configuré : */2 * * * * /usr/local/bin/export-wazuh-logs.sh"

# Exécuter immédiatement
echo ""
echo "Exécution initiale du script d'export..."
/usr/local/bin/export-wazuh-logs.sh

if [[ -f /var/log/wazuh-export/alerts.json ]]; then
    SIZE=$(stat -c %s /var/log/wazuh-export/alerts.json 2>/dev/null)
    echo "✅ Export réussi : $SIZE bytes"
else
    echo "⚠ Fichier d'export non créé"
fi

echo ""
echo "════════════════════════════════════════"
echo "✅ FIX TERMINÉ !"
echo "════════════════════════════════════════"
echo ""
echo "Vérifier :"
echo "  crontab -l                                      # Voir le cron"
echo "  cat /var/log/wazuh-export/alerts.json | head   # Voir les logs"
echo "  sudo bash scripts/diagnostics.sh                # Re-tester"
echo ""
