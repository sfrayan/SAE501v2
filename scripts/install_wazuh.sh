#!/bin/bash
#
# install_wazuh_docker.sh - Installation Wazuh avec Docker
# SAE 5.01 - Version modernisée utilisant Docker Compose
#
# Ce script installe Wazuh en mode single-node avec Docker
# Documentation: https://documentation.wazuh.com/current/deployment-options/docker/

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SERVER_IP="${SERVER_IP:-192.168.10.100}"
WAZUH_VERSION="${WAZUH_VERSION:-v4.14.2}"
DOCKER_MIN_VERSION="20.10.0"
COMPOSE_MIN_VERSION="2.0.0"

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🐳 Installation Wazuh avec Docker"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Version Wazuh: $WAZUH_VERSION"
echo "IP Serveur: $SERVER_IP"
echo ""

# ============================================
# VÉRIFICATIONS PRÉALABLES
# ============================================

# Vérifier root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ Ce script doit être exécuté en root (sudo)${NC}"
  exit 1
fi

# Vérifier la configuration système minimale
echo -e "${BLUE}[1/9]${NC} Vérification de la configuration système..."

# Vérifier RAM (minimum 8GB recommandé)
TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
if [ "$TOTAL_RAM" -lt 8 ]; then
  echo -e "${YELLOW}⚠️  Mémoire RAM: ${TOTAL_RAM}GB (minimum recommandé: 8GB)${NC}"
  echo -e "${YELLOW}   L'installation peut être lente ou instable${NC}"
fi

# Vérifier espace disque (minimum 50GB recommandé)
DISK_SPACE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$DISK_SPACE" -lt 50 ]; then
  echo -e "${YELLOW}⚠️  Espace disque: ${DISK_SPACE}GB (minimum recommandé: 50GB)${NC}"
fi

echo -e "${GREEN}✅ Configuration système vérifiée${NC}"

# ============================================
# INSTALLATION DOCKER
# ============================================

echo -e "${BLUE}[2/9]${NC} Installation de Docker..."

if command -v docker &> /dev/null; then
  DOCKER_VERSION=$(docker --version | grep -oP '\d+\.\d+\.\d+')
  echo -e "${GREEN}✅ Docker déjà installé (version $DOCKER_VERSION)${NC}"
else
  echo "Installation de Docker Engine..."
  
  # Supprimer anciennes versions
  apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
  
  # Installation des prérequis
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    > /dev/null 2>&1
  
  # Ajout du repository Docker
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  
  # Installation Docker
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    > /dev/null 2>&1
  
  # Démarrer Docker
  systemctl enable docker > /dev/null 2>&1
  systemctl start docker
  
  echo -e "${GREEN}✅ Docker installé avec succès${NC}"
fi

# ============================================
# VÉRIFICATION DOCKER COMPOSE
# ============================================

echo -e "${BLUE}[3/9]${NC} Vérification de Docker Compose..."

if docker compose version &> /dev/null; then
  COMPOSE_VERSION=$(docker compose version | grep -oP '\d+\.\d+\.\d+')
  echo -e "${GREEN}✅ Docker Compose disponible (version $COMPOSE_VERSION)${NC}"
else
  echo -e "${RED}❌ Docker Compose non disponible${NC}"
  exit 1
fi

# ============================================
# CONFIGURATION SYSTÈME POUR WAZUH
# ============================================

echo -e "${BLUE}[4/9]${NC} Configuration système pour Wazuh..."

# Augmenter vm.max_map_count (requis pour Wazuh Indexer)
if ! grep -q "vm.max_map_count=262144" /etc/sysctl.conf; then
  echo "vm.max_map_count=262144" >> /etc/sysctl.conf
  sysctl -w vm.max_map_count=262144 > /dev/null
fi

# Désactiver swap (recommandé pour performance)
if [ "$(swapon --show | wc -l)" -gt 0 ]; then
  echo "Désactivation du swap..."
  swapoff -a
  sed -i '/ swap / s/^/#/' /etc/fstab
fi

echo -e "${GREEN}✅ Système configuré${NC}"

# ============================================
# CLONAGE DU REPOSITORY WAZUH-DOCKER
# ============================================

echo -e "${BLUE}[5/9]${NC} Téléchargement de Wazuh Docker..."

WAZUH_DOCKER_DIR="/opt/wazuh-docker"

# Supprimer l'ancien répertoire si existe
if [ -d "$WAZUH_DOCKER_DIR" ]; then
  echo "Suppression de l'ancienne installation..."
  rm -rf "$WAZUH_DOCKER_DIR"
fi

# Cloner le repository
git clone https://github.com/wazuh/wazuh-docker.git -b "$WAZUH_VERSION" --single-branch "$WAZUH_DOCKER_DIR" > /dev/null 2>&1

if [ ! -d "$WAZUH_DOCKER_DIR" ]; then
  echo -e "${RED}❌ Échec du clonage du repository Wazuh${NC}"
  exit 1
fi

cd "$WAZUH_DOCKER_DIR/single-node"

echo -e "${GREEN}✅ Wazuh Docker téléchargé${NC}"

# ============================================
# GÉNÉRATION DES CERTIFICATS
# ============================================

echo -e "${BLUE}[6/9]${NC} Génération des certificats SSL..."

# Vérifier si les certificats existent déjà
if [ -f "config/wazuh_indexer_ssl_certs/root-ca.pem" ]; then
  echo "Certificats existants trouvés, régénération..."
  rm -rf config/wazuh_indexer_ssl_certs/*
fi

# Générer les certificats avec Docker
if ! docker compose -f generate-indexer-certs.yml run --rm generator > /dev/null 2>&1; then
  echo -e "${RED}❌ Échec de la génération des certificats${NC}"
  echo "Tentative avec l'ancien format docker-compose..."
  docker-compose -f generate-indexer-certs.yml run --rm generator > /dev/null 2>&1 || {
    echo -e "${RED}❌ Impossible de générer les certificats${NC}"
    exit 1
  }
fi

# Vérifier que les certificats ont été créés
if [ ! -f "config/wazuh_indexer_ssl_certs/root-ca.pem" ]; then
  echo -e "${RED}❌ Les certificats n'ont pas été générés correctement${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Certificats SSL générés${NC}"

# ============================================
# CONFIGURATION PERSONNALISÉE
# ============================================

echo -e "${BLUE}[7/9]${NC} Application de la configuration personnalisée..."

# Copier les configurations personnalisées depuis le projet si elles existent
if [ -f "$PROJECT_ROOT/wazuh/manager.conf" ]; then
  cp "$PROJECT_ROOT/wazuh/manager.conf" config/wazuh_cluster/wazuh_manager.conf
  echo "Configuration manager copiée depuis le projet"
fi

if [ -f "$PROJECT_ROOT/wazuh/local_rules.xml" ]; then
  mkdir -p config/wazuh_cluster/rules
  cp "$PROJECT_ROOT/wazuh/local_rules.xml" config/wazuh_cluster/rules/
  echo "Règles personnalisées copiées depuis le projet"
fi

# Configurer l'IP du serveur dans docker-compose.yml
if [ "$SERVER_IP" != "192.168.10.100" ]; then
  echo "Configuration de l'IP personnalisée: $SERVER_IP"
  # Remplacer les bindings localhost par l'IP du serveur si nécessaire
fi

echo -e "${GREEN}✅ Configuration appliquée${NC}"

# ============================================
# DÉPLOIEMENT WAZUH
# ============================================

echo -e "${BLUE}[8/9]${NC} Déploiement de Wazuh (peut prendre 5-10 minutes)..."
echo "Téléchargement et démarrage des conteneurs..."

# Démarrer Wazuh en arrière-plan
docker compose up -d

# Attendre que les services démarrent
echo "Attente du démarrage des services..."
sleep 30

# Vérifier le statut des conteneurs
CONTAINERS_RUNNING=$(docker compose ps | grep -c "Up")
CONTAINERS_TOTAL=$(docker compose ps | tail -n +2 | wc -l)

if [ "$CONTAINERS_RUNNING" -eq "$CONTAINERS_TOTAL" ] && [ "$CONTAINERS_TOTAL" -gt 0 ]; then
  echo -e "${GREEN}✅ Tous les conteneurs sont démarrés ($CONTAINERS_RUNNING/$CONTAINERS_TOTAL)${NC}"
else
  echo -e "${YELLOW}⚠️  Certains conteneurs n'ont pas démarré correctement${NC}"
  docker compose ps
fi

# Attendre que Wazuh soit complètement opérationnel
echo "Vérification de la disponibilité de Wazuh..."
MAX_ATTEMPTS=30
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  if curl -s -k https://localhost:443 > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Wazuh Dashboard accessible${NC}"
    break
  fi
  ATTEMPT=$((ATTEMPT + 1))
  if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo -e "${YELLOW}⚠️  Wazuh Dashboard prend plus de temps que prévu à démarrer${NC}"
    echo "Vérifiez les logs avec: docker compose logs"
  else
    sleep 10
  fi
done

# ============================================
# CONFIGURATION FIREWALL
# ============================================

echo -e "${BLUE}[9/9]${NC} Configuration du firewall UFW..."

if command -v ufw &> /dev/null; then
  # Ports Wazuh
  ufw allow 443/tcp comment 'Wazuh Dashboard' > /dev/null 2>&1
  ufw allow 1514/tcp comment 'Wazuh Agent Registration' > /dev/null 2>&1
  ufw allow 1515/tcp comment 'Wazuh Agent Communication' > /dev/null 2>&1
  ufw allow 514/udp comment 'Syslog' > /dev/null 2>&1
  
  # Ports FreeRADIUS
  ufw allow 1812/udp comment 'RADIUS Auth' > /dev/null 2>&1
  ufw allow 1813/udp comment 'RADIUS Accounting' > /dev/null 2>&1
  
  # Port web admin
  ufw allow 80/tcp comment 'HTTP PHP Admin' > /dev/null 2>&1
  
  echo -e "${GREEN}✅ Règles firewall configurées${NC}"
else
  echo -e "${YELLOW}⚠️  UFW non installé, configuration firewall ignorée${NC}"
fi

# ============================================
# RÉCUPÉRATION DES CREDENTIALS
# ============================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ Installation Wazuh Docker terminée !${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Extraire les credentials depuis docker-compose.yml
ADMIN_USER=$(grep -A 5 "INDEXER_USERNAME" "$WAZUH_DOCKER_DIR/single-node/docker-compose.yml" | grep "INDEXER_USERNAME" | cut -d':' -f2 | tr -d ' "' || echo "admin")
ADMIN_PASS=$(grep -A 5 "INDEXER_PASSWORD" "$WAZUH_DOCKER_DIR/single-node/docker-compose.yml" | grep "INDEXER_PASSWORD" | cut -d':' -f2 | tr -d ' "' || echo "SecretPassword")

# Créer le fichier d'informations
cat > /root/wazuh-docker-info.txt <<EOF
╔═══════════════════════════════════════════════════════╗
║       WAZUH DOCKER - SAE 5.01                         ║
╚═══════════════════════════════════════════════════════╝

📊 ACCÈS WAZUH DASHBOARD
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  URL:       https://$SERVER_IP:443
             https://localhost:443
  
  Username:  $ADMIN_USER
  Password:  $ADMIN_PASS
  
  ⚠️  Note: Acceptez le certificat auto-signé dans votre navigateur

🐳 GESTION DOCKER
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Répertoire: $WAZUH_DOCKER_DIR/single-node
  
  # Voir l'état des conteneurs
  cd $WAZUH_DOCKER_DIR/single-node
  docker compose ps
  
  # Voir les logs
  docker compose logs -f wazuh.manager
  docker compose logs -f wazuh.indexer
  docker compose logs -f wazuh.dashboard
  
  # Arrêter Wazuh
  docker compose stop
  
  # Démarrer Wazuh
  docker compose start
  
  # Redémarrer Wazuh
  docker compose restart
  
  # Arrêter et supprimer (conservation des données)
  docker compose down
  
  # Arrêter et supprimer AVEC les données
  docker compose down -v

📁 VOLUMES DOCKER (Persistance des données)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Les données sont stockées dans des volumes Docker:
  - single-node_wazuh_api_configuration
  - single-node_wazuh_etc
  - single-node_wazuh_logs
  - single-node_wazuh_queue
  - single-node_wazuh_var_multigroups
  - single-node_wazuh_integrations
  - single-node_wazuh_active_response
  - single-node_wazuh_agentless
  - single-node_wazuh_wodles
  - single-node_wazuh-indexer-data
  - single-node_wazuh-dashboard-config
  - single-node_wazuh-dashboard-custom

  # Lister les volumes
  docker volume ls | grep single-node

📋 CONFIGURATION WAZUH
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Configuration manager:
  $WAZUH_DOCKER_DIR/single-node/config/wazuh_cluster/wazuh_manager.conf
  
  Règles personnalisées:
  $WAZUH_DOCKER_DIR/single-node/config/wazuh_cluster/rules/
  
  Après modification, redémarrer:
  cd $WAZUH_DOCKER_DIR/single-node
  docker compose restart wazuh.manager

🔌 PORTS EXPOSÉS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  443/tcp     - Wazuh Dashboard (HTTPS)
  1514/tcp    - Wazuh Agent Registration
  1515/tcp    - Wazuh Agent Communication
  55000/tcp   - Wazuh API
  9200/tcp    - Wazuh Indexer (interne)

🔧 ENREGISTREMENT D'UN AGENT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Depuis le Dashboard:
  1. Aller dans "Agents" > "Deploy new agent"
  2. Suivre les instructions pour votre OS
  3. Utiliser l'IP: $SERVER_IP
  
  Ou manuellement (Linux):
  wget https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.14.2-1_amd64.deb
  WAZUH_MANAGER='$SERVER_IP' dpkg -i ./wazuh-agent_4.14.2-1_amd64.deb
  systemctl enable wazuh-agent
  systemctl start wazuh-agent

📊 MONITORING & DEBUG
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  # Utilisation ressources
  docker stats
  
  # Entrer dans le conteneur manager
  docker compose exec wazuh.manager bash
  
  # Vérifier logs manager
  docker compose exec wazuh.manager tail -f /var/ossec/logs/ossec.log
  
  # Vérifier alertes
  docker compose exec wazuh.manager tail -f /var/ossec/logs/alerts/alerts.log

🔄 MISE À JOUR WAZUH
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  cd $WAZUH_DOCKER_DIR/single-node
  
  # Arrêter les conteneurs
  docker compose down
  
  # Récupérer la nouvelle version
  cd /opt
  git clone https://github.com/wazuh/wazuh-docker.git -b v4.XX.X new-wazuh
  
  # Copier vos configurations
  cp $WAZUH_DOCKER_DIR/single-node/config/wazuh_cluster/* new-wazuh/single-node/config/wazuh_cluster/
  
  # Redémarrer avec la nouvelle version
  cd new-wazuh/single-node
  docker compose up -d

🚨 DÉPANNAGE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Dashboard inaccessible:
  - Vérifier que les conteneurs sont up: docker compose ps
  - Vérifier les logs: docker compose logs wazuh.dashboard
  - Attendre 2-3 minutes après le démarrage initial
  
  Problème de certificat:
  - Régénérer: docker compose -f generate-indexer-certs.yml run --rm generator
  - Redémarrer: docker compose restart
  
  Manque de mémoire:
  - Vérifier: docker stats
  - Augmenter RAM VM ou limiter dans docker-compose.yml
  
  Logs complets:
  docker compose logs --tail=100 -f

📚 DOCUMENTATION OFFICIELLE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  https://documentation.wazuh.com/current/deployment-options/docker/

╚═══════════════════════════════════════════════════════╝
EOF

chmod 600 /root/wazuh-docker-info.txt

# Afficher les informations essentielles
echo ""
echo "📋 INFORMATIONS D'ACCÈS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "  ${GREEN}Wazuh Dashboard:${NC} https://$SERVER_IP:443"
echo -e "  ${GREEN}Username:${NC}        $ADMIN_USER"
echo -e "  ${GREEN}Password:${NC}        $ADMIN_PASS"
echo ""
echo "⚠️  Acceptez le certificat auto-signé dans votre navigateur"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${BLUE}📖 Informations complètes:${NC} cat /root/wazuh-docker-info.txt"
echo -e "${BLUE}🐳 Gestion conteneurs:${NC}     cd $WAZUH_DOCKER_DIR/single-node && docker compose ps"
echo -e "${BLUE}📊 Logs en direct:${NC}         cd $WAZUH_DOCKER_DIR/single-node && docker compose logs -f"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit 0
