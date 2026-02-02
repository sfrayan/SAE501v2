#!/bin/bash
#
# uninstall_wazuh.sh - Désinstallation Wazuh Docker
# SAE 5.01 - Script de nettoyage complet
#
# Ce script désinstalle proprement Wazuh Docker
# Usage: sudo bash uninstall_wazuh.sh [--keep-data] [--force]

set -e

WAZUH_DOCKER_DIR="/opt/wazuh-docker"
BACKUP_DIR="/root/wazuh-backup-$(date +%Y%m%d-%H%M%S)"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Options
KEEP_DATA=false
FORCE=false

# Parse arguments
for arg in "$@"; do
  case $arg in
    --keep-data)
      KEEP_DATA=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --help)
      echo "Usage: sudo bash uninstall_wazuh.sh [options]"
      echo ""
      echo "Options:"
      echo "  --keep-data    Conserver les volumes Docker (données Wazuh)"
      echo "  --force        Ne pas demander de confirmation"
      echo "  --help         Afficher cette aide"
      echo ""
      echo "Exemples:"
      echo "  sudo bash uninstall_wazuh.sh                  # Désinstallation complète"
      echo "  sudo bash uninstall_wazuh.sh --keep-data      # Garder les données"
      echo "  sudo bash uninstall_wazuh.sh --force          # Sans confirmation"
      exit 0
      ;;
  esac
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🗑️  Désinstallation Wazuh Docker"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Vérifier root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ Ce script doit être exécuté en root (sudo)${NC}"
  exit 1
fi

# Vérifier si Wazuh est installé
if [ ! -d "$WAZUH_DOCKER_DIR" ]; then
  echo -e "${YELLOW}⚠️  Wazuh Docker n'est pas installé dans $WAZUH_DOCKER_DIR${NC}"
  echo ""
  echo "Voulez-vous quand même nettoyer les conteneurs/volumes Wazuh existants ? (o/N)"
  read -r response
  if [[ ! "$response" =~ ^[oO]$ ]]; then
    echo "Annulation."
    exit 0
  fi
fi

# Afficher les informations
echo -e "${BLUE}Configuration:${NC}"
echo "  Répertoire: $WAZUH_DOCKER_DIR"
echo "  Conserver données: $KEEP_DATA"
echo "  Mode forcé: $FORCE"
echo ""

# Confirmation
if [ "$FORCE" = false ]; then
  echo -e "${YELLOW}⚠️  ATTENTION: Cette action va:${NC}"
  echo "  1. Arrêter tous les conteneurs Wazuh"
  echo "  2. Supprimer les conteneurs"
  if [ "$KEEP_DATA" = false ]; then
    echo "  3. 🚨 SUPPRIMER TOUS LES VOLUMES (données perdues)"
  else
    echo "  3. Conserver les volumes (données préservées)"
  fi
  echo "  4. Supprimer le répertoire $WAZUH_DOCKER_DIR"
  echo "  5. Nettoyer les images Docker"
  echo ""
  echo -n "Êtes-vous sûr de vouloir continuer ? (o/N): "
  read -r response
  if [[ ! "$response" =~ ^[oO]$ ]]; then
    echo "Annulation."
    exit 0
  fi
fi

echo ""

# ============================================
# SAUVEGARDE (OPTIONNELLE)
# ============================================

if [ -d "$WAZUH_DOCKER_DIR/single-node" ]; then
  echo -e "${BLUE}[1/7]${NC} Proposition de sauvegarde..."
  
  if [ "$FORCE" = false ]; then
    echo -n "Voulez-vous sauvegarder les configurations avant suppression ? (O/n): "
    read -r backup_response
    if [[ ! "$backup_response" =~ ^[nN]$ ]]; then
      echo "Création de la sauvegarde dans $BACKUP_DIR..."
      mkdir -p "$BACKUP_DIR"
      
      # Sauvegarder configurations
      if [ -d "$WAZUH_DOCKER_DIR/single-node/config" ]; then
        cp -r "$WAZUH_DOCKER_DIR/single-node/config" "$BACKUP_DIR/"
        echo "✅ Configurations sauvegardées"
      fi
      
      # Sauvegarder docker-compose.yml
      if [ -f "$WAZUH_DOCKER_DIR/single-node/docker-compose.yml" ]; then
        cp "$WAZUH_DOCKER_DIR/single-node/docker-compose.yml" "$BACKUP_DIR/"
        echo "✅ docker-compose.yml sauvegardé"
      fi
      
      # Sauvegarder fichier info
      if [ -f "/root/wazuh-docker-info.txt" ]; then
        cp "/root/wazuh-docker-info.txt" "$BACKUP_DIR/"
        echo "✅ wazuh-docker-info.txt sauvegardé"
      fi
      
      echo -e "${GREEN}✅ Sauvegarde créée: $BACKUP_DIR${NC}"
    else
      echo "Sauvegarde ignorée."
    fi
  else
    echo "Mode forcé: sauvegarde ignorée."
  fi
else
  echo -e "${BLUE}[1/7]${NC} Pas de configurations à sauvegarder."
fi

# ============================================
# ARRÊT DES CONTENEURS
# ============================================

echo -e "${BLUE}[2/7]${NC} Arrêt des conteneurs Wazuh..."

if [ -d "$WAZUH_DOCKER_DIR/single-node" ]; then
  cd "$WAZUH_DOCKER_DIR/single-node"
  
  # Arrêter les conteneurs
  if docker compose ps -q 2>/dev/null | grep -q .; then
    echo "Arrêt des conteneurs..."
    docker compose stop > /dev/null 2>&1 || true
    echo -e "${GREEN}✅ Conteneurs arrêtés${NC}"
  else
    echo "Aucun conteneur en cours d'exécution."
  fi
else
  echo "Répertoire $WAZUH_DOCKER_DIR/single-node introuvable."
fi

# ============================================
# SUPPRESSION DES CONTENEURS
# ============================================

echo -e "${BLUE}[3/7]${NC} Suppression des conteneurs..."

if [ -d "$WAZUH_DOCKER_DIR/single-node" ]; then
  cd "$WAZUH_DOCKER_DIR/single-node"
  
  if [ "$KEEP_DATA" = true ]; then
    echo "Suppression des conteneurs (conservation des volumes)..."
    docker compose down > /dev/null 2>&1 || true
  else
    echo "Suppression des conteneurs ET des volumes..."
    docker compose down -v > /dev/null 2>&1 || true
  fi
  
  echo -e "${GREEN}✅ Conteneurs supprimés${NC}"
fi

# Nettoyer les conteneurs orphelins
ORPHAN_CONTAINERS=$(docker ps -a --filter "name=wazuh" -q)
if [ -n "$ORPHAN_CONTAINERS" ]; then
  echo "Suppression des conteneurs orphelins..."
  docker rm -f $ORPHAN_CONTAINERS > /dev/null 2>&1 || true
  echo "✅ Conteneurs orphelins supprimés"
fi

# ============================================
# SUPPRESSION DES VOLUMES (SI NON CONSERVÉS)
# ============================================

echo -e "${BLUE}[4/7]${NC} Gestion des volumes..."

if [ "$KEEP_DATA" = true ]; then
  echo -e "${GREEN}✅ Volumes conservés (données préservées)${NC}"
  echo ""
  echo "Volumes conservés:"
  docker volume ls | grep single-node || echo "Aucun volume trouvé"
  echo ""
  echo -e "${YELLOW}⚠️  Pour supprimer les volumes plus tard:${NC}"
  echo "  docker volume ls | grep single-node | awk '{print \$2}' | xargs docker volume rm"
else
  WAZUH_VOLUMES=$(docker volume ls --filter "name=single-node" -q)
  if [ -n "$WAZUH_VOLUMES" ]; then
    echo "Suppression des volumes Wazuh..."
    echo "$WAZUH_VOLUMES" | xargs docker volume rm > /dev/null 2>&1 || true
    echo -e "${GREEN}✅ Volumes supprimés${NC}"
  else
    echo "Aucun volume à supprimer."
  fi
fi

# ============================================
# SUPPRESSION DES IMAGES
# ============================================

echo -e "${BLUE}[5/7]${NC} Suppression des images Docker..."

WAZUH_IMAGES=$(docker images --filter "reference=wazuh/*" -q)
if [ -n "$WAZUH_IMAGES" ]; then
  echo "Suppression des images Wazuh..."
  echo "$WAZUH_IMAGES" | xargs docker rmi -f > /dev/null 2>&1 || true
  echo -e "${GREEN}✅ Images supprimées${NC}"
else
  echo "Aucune image Wazuh à supprimer."
fi

# ============================================
# SUPPRESSION DU RÉPERTOIRE
# ============================================

echo -e "${BLUE}[6/7]${NC} Suppression du répertoire..."

if [ -d "$WAZUH_DOCKER_DIR" ]; then
  echo "Suppression de $WAZUH_DOCKER_DIR..."
  rm -rf "$WAZUH_DOCKER_DIR"
  echo -e "${GREEN}✅ Répertoire supprimé${NC}"
else
  echo "Répertoire déjà supprimé."
fi

# Supprimer fichier info
if [ -f "/root/wazuh-docker-info.txt" ]; then
  rm -f "/root/wazuh-docker-info.txt"
  echo "✅ wazuh-docker-info.txt supprimé"
fi

# ============================================
# NETTOYAGE CONFIGURATION SYSTÈME
# ============================================

echo -e "${BLUE}[7/7]${NC} Nettoyage configuration système..."

# Réactiver swap si désactivé
if [ "$(swapon --show | wc -l)" -eq 0 ]; then
  echo -n "Voulez-vous réactiver le swap ? (o/N): "
  if [ "$FORCE" = false ]; then
    read -r swap_response
    if [[ "$swap_response" =~ ^[oO]$ ]]; then
      sed -i '/swap/s/^#//' /etc/fstab 2>/dev/null || true
      swapon -a 2>/dev/null || true
      echo "✅ Swap réactivé"
    fi
  else
    echo "Mode forcé: swap non réactivé"
  fi
fi

# Garder vm.max_map_count (peut être utile pour d'autres apps)
echo "ℹ️  vm.max_map_count=262144 conservé dans /etc/sysctl.conf"
echo "   (peut être utile pour Elasticsearch, etc.)"

# Règles firewall
echo ""
echo -e "${YELLOW}⚠️  Règles firewall UFW conservées${NC}"
echo "Pour les supprimer manuellement:"
echo "  sudo ufw delete allow 443/tcp"
echo "  sudo ufw delete allow 1514/tcp"
echo "  sudo ufw delete allow 1515/tcp"
echo "  sudo ufw delete allow 514/udp"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ Désinstallation Wazuh terminée !${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ -d "$BACKUP_DIR" ]; then
  echo -e "${BLUE}💾 Sauvegarde disponible:${NC} $BACKUP_DIR"
fi

if [ "$KEEP_DATA" = true ]; then
  echo -e "${BLUE}📊 Volumes conservés:${NC}"
  docker volume ls | grep single-node || echo "Aucun volume"
fi

echo ""
echo "🎉 Wazuh Docker a été désinstallé avec succès"
echo ""

# Vérification finale
echo "Vérification finale:"
echo "  Conteneurs Wazuh: $(docker ps -a --filter 'name=wazuh' -q | wc -l)"
echo "  Volumes single-node: $(docker volume ls --filter 'name=single-node' -q | wc -l)"
echo "  Images Wazuh: $(docker images --filter 'reference=wazuh/*' -q | wc -l)"
echo ""

exit 0
