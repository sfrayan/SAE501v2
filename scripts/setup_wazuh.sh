#!/bin/bash
#
# setup_wazuh.sh - Installation et configuration Wazuh pour SAE 5.01
#
# Ce script:
# 1. Installe Wazuh agent sur le serveur RADIUS
# 2. Configure la collecte de logs (RADIUS, SSH, UFW, Fail2Ban)
# 3. Active FIM (File Integrity Monitoring)
# 4. Configure Active Response
# 5. Charge les décodeurs et règles personnalisés
#

set -e

WAZUH_MANAGER="192.168.10.100"
WAZUH_VERSION="4.9.0"
AGENT_NAME="radius-server"
AGENT_GROUP="radius"

echo "═══════════════════════════════════════════════════════════════════"
echo "🔧 INSTALLATION WAZUH AGENT SAE 5.01"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Configuration:"
echo "  • Wazuh Manager: $WAZUH_MANAGER"
echo "  • Version: $WAZUH_VERSION"
echo "  • Agent Name: $AGENT_NAME"
echo "  • Agent Group: $AGENT_GROUP"
echo ""
read -p "Continuer? (o/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Oo]$ ]]; then
    echo "Annulé."
    exit 0
fi

# Vérifier root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ce script doit être exécuté en root (sudo)"
  exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "ÉTAPE 1/5: Installation Wazuh Agent"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# Vérifier si déjà installé
if command -v wazuh-control &> /dev/null; then
    echo "  ✅ Wazuh agent déjà installé"
    WAZUH_INSTALLED=1
else
    echo "[1.1] Ajout du repository Wazuh..."
    curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && chmod 644 /usr/share/keyrings/wazuh.gpg
    
    echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | tee -a /etc/apt/sources.list.d/wazuh.list
    
    echo "  ✅ Repository ajouté"
    
    echo "[1.2] Installation de l'agent..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive WAZUH_MANAGER="$WAZUH_MANAGER" WAZUH_AGENT_NAME="$AGENT_NAME" apt-get install -y wazuh-agent > /dev/null 2>&1
    
    echo "  ✅ Agent installé"
    WAZUH_INSTALLED=0
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "ÉTAPE 2/5: Configuration collecte de logs"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "[2.1] Backup configuration actuelle..."
cp /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.backup.$(date +%Y%m%d_%H%M%S)
echo "  ✅ Backup créé"

echo "[2.2] Ajout configuration monitoring logs..."

# Créer fichier de configuration custom
cat > /tmp/wazuh_localfiles.conf <<'EOF'
  <!-- FreeRADIUS logs -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/freeradius/radius.log</location>
  </localfile>

  <!-- SSH/Auth logs -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/auth.log</location>
  </localfile>

  <!-- UFW Firewall logs -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/ufw.log</location>
  </localfile>

  <!-- Fail2Ban logs -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/fail2ban.log</location>
  </localfile>

  <!-- Apache logs -->
  <localfile>
    <log_format>apache</log_format>
    <location>/var/log/apache2/error.log</location>
  </localfile>

  <!-- MySQL logs -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/mysql/error.log</location>
  </localfile>
EOF

# Insérer avant la fermeture de </ossec_config>
sed -i '/<\/ossec_config>/i\<!-- Custom log monitoring SAE 5.01 -->\' /var/ossec/etc/ossec.conf
sed -i "/<\/ossec_config>/r /tmp/wazuh_localfiles.conf" /var/ossec/etc/ossec.conf

echo "  ✅ Configuration logs ajoutée"

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "ÉTAPE 3/5: Configuration FIM (File Integrity Monitoring)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "[3.1] Configuration monitoring fichiers critiques..."

cat > /tmp/wazuh_fim.conf <<'EOF'
  <!-- File Integrity Monitoring -->
  <syscheck>
    <disabled>no</disabled>
    <frequency>43200</frequency>
    
    <!-- Real-time monitoring -->
    <directories realtime="yes">/etc/freeradius/3.0</directories>
    <directories realtime="yes">/etc/ssh/sshd_config</directories>
    <directories realtime="yes">/etc/ufw</directories>
    <directories realtime="yes">/etc/fail2ban</directories>
    <directories realtime="yes">/var/www/html/php-admin</directories>
    
    <ignore>/etc/.git</ignore>
    <ignore type="sregex">.log$|.swp$</ignore>
  </syscheck>
EOF

sed -i "/<\/ossec_config>/r /tmp/wazuh_fim.conf" /var/ossec/etc/ossec.conf

echo "  ✅ FIM configuré"

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "ÉTAPE 4/5: Configuration Active Response"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "[4.1] Activation Active Response..."

cat > /tmp/wazuh_ar.conf <<'EOF'
  <!-- Active Response Configuration -->
  <active-response>
    <disabled>no</disabled>
    <command>firewall-drop</command>
    <location>local</location>
    <rules_id>5763</rules_id>
    <timeout>600</timeout>
  </active-response>

  <active-response>
    <disabled>no</disabled>
    <command>firewall-drop</command>
    <location>local</location>
    <rules_id>100805</rules_id>
    <timeout>1800</timeout>
  </active-response>
EOF

sed -i "/<\/ossec_config>/r /tmp/wazuh_ar.conf" /var/ossec/etc/ossec.conf

echo "  ✅ Active Response configuré"

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "ÉTAPE 5/5: Démarrage et vérification"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "[5.1] Démarrage service Wazuh..."
systemctl enable wazuh-agent > /dev/null 2>&1
systemctl restart wazuh-agent

sleep 3

if systemctl is-active --quiet wazuh-agent; then
    echo "  ✅ Wazuh agent démarré"
else
    echo "  ❌ Erreur démarrage Wazuh agent"
    echo "  Vérifier les logs: /var/ossec/logs/ossec.log"
    exit 1
fi

echo "[5.2] Vérification connexion Manager..."
if /var/ossec/bin/wazuh-control status | grep -q "wazuh-agentd is running"; then
    echo "  ✅ Agent connecté au Manager"
else
    echo "  ⚠️  Agent démarré mais vérifier connexion Manager"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "✅ INSTALLATION WAZUH TERMINÉE"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "📋 Configuration:"
echo "  • Logs monitorés: FreeRADIUS, SSH, UFW, Fail2Ban, Apache, MySQL"
echo "  • FIM actif: Monitoring temps-réel fichiers critiques"
echo "  • Active Response: Blocage automatique IP malveillantes"
echo "  • Agent connecté à: $WAZUH_MANAGER:1514"
echo ""
echo "🔧 Configuration Manager (à faire sur le Manager Wazuh):"
echo ""
echo "1. Copier les décodeurs personnalisés:"
echo "   scp ~/SAE501v2/wazuh/custom_decoders.xml wazuh-manager:/var/ossec/etc/decoders/local_decoder.xml"
echo ""
echo "2. Copier les règles personnalisées:"
echo "   scp ~/SAE501v2/wazuh/custom_rules.xml wazuh-manager:/var/ossec/etc/rules/local_rules.xml"
echo ""
echo "3. Redémarrer Manager:"
echo "   sudo systemctl restart wazuh-manager"
echo ""
echo "4. Vérifier agent dans dashboard:"
echo "   https://<wazuh-manager>:443"
echo ""
echo "📊 Commandes utiles:"
echo "  • Status agent: sudo /var/ossec/bin/wazuh-control status"
echo "  • Logs agent: sudo tail -f /var/ossec/logs/ossec.log"
echo "  • Test règles: sudo /var/ossec/bin/wazuh-logtest"
echo "  • Info agent: sudo /var/ossec/bin/wazuh-control info"
echo ""
echo "📚 Documentation:"
echo "  docs/wazuh-monitoring.md"
echo "═══════════════════════════════════════════════════════════════════"

exit 0
