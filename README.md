# 🏋️ SAE 5.01 - Architecture Wi-Fi Sécurisée avec RADIUS

**Projet académique SAE 5.01** - Déploiement d'une infrastructure Wi-Fi sécurisée avec authentification 802.1X et supervision centralisée.

**Durée totale** : ~3 heures (VM : 30 min + Routeur : 1h + Tests/Hardening : 1.5h)

---

## 📋 Table des matières

1. [⚠️ Prérequis Système](#prerequis)
2. [Objectifs du projet](#objectifs)
3. [Architecture globale](#architecture)
4. [Configuration réseau IMPORTANTE](#config-reseau)
5. [🎯 Ordre d'exécution des scripts](#ordre-execution)
6. [Installation complète](#installation)
7. [Configuration du routeur](#routeur)
8. [Tests et validation](#tests)
9. [Hardening du serveur](#hardening)
10. [Troubleshooting](#troubleshooting)

---

## ⚠️ Prérequis Système (À VÉRIFIER AVANT) {#prerequis}

### 💻 Configuration Matérielle Minimale

- **CPU** : 2 cores minimum
- **RAM** : **4GB minimum** (8GB recommandé pour Wazuh)
- **Disque** : **20GB libres minimum**
- **OS** : **Debian 11 (Bullseye) uniquement**

### ✅ Script de Vérification Automatique

**🚨 EXÉCUTEZ CETTE COMMANDE EN PREMIER :**

```bash
cd ~/SAE501v2
bash scripts/check_prerequisites.sh
```

Ce script vérifie automatiquement :
- ✓ Version OS (Debian 11)
- ✓ Ressources (RAM ≥4GB, Disque ≥20GB)
- ✓ Configuration réseau (enp0s8, enp0s3)
- ✓ Connectivité Internet
- ✓ Dépendances (git, curl, wget)
- ✓ Services déjà installés

**Si le score est vert ✅, vous pouvez continuer. Sinon, suivez les instructions affichées.**

### 🔍 Vérifications Manuelles (si nécessaire)

```bash
# 1. Vérifier la version Debian
lsb_release -d
# Doit afficher: Debian GNU/Linux 11 (bullseye)

# 2. Vérifier RAM disponible
free -h
# Minimum 4GB (3.8G utilisable)

# 3. Vérifier espace disque
df -h /
# Minimum 20GB libres

# 4. Vérifier connexion Internet
ping -c 4 8.8.8.8
# Doit réussir

# 5. Vérifier droits root
sudo -v
# Ne doit pas demander de mot de passe
```

### 📦 Logiciels Requis

```bash
# Installer les dépendances de base
sudo apt update
sudo apt install -y git curl wget net-tools
```

### ☑️ Checklist Pré-Installation

**NE PAS CONTINUER sans valider tous ces points :**

- [ ] Debian 11 confirmé
- [ ] RAM ≥4GB vérifiée
- [ ] Disque ≥20GB vérifié
- [ ] enp0s3 (NAT) configurée avec Internet
- [ ] enp0s8 (Bridge) configurée avec IP 192.168.10.100
- [ ] apt-get fonctionne
- [ ] git, curl, wget installés
- [ ] Accès root (sudo) vérifié
- [ ] Script `check_prerequisites.sh` exécuté avec succès ✅

---

## 🎯 Objectifs {#objectifs}

### Fonctionnels

- ✅ Déployer un **serveur RADIUS centralisé** (FreeRADIUS + MySQL)
- ✅ Configurer une **authentification 802.1X sécurisée** (PEAP-MSCHAPv2, sans certificat client)
- ✅ Mettre en place deux réseaux Wi-Fi :
  - **Fitness-Pro** : Authentification RADIUS (WPA2-Enterprise)
  - **Fitness-Guest** : Mot de passe partagé (WPA2-PSK) avec AP Isolation
- ✅ Implémenter une **interface de gestion PHP** pour ajouter/supprimer des utilisateurs
- ✅ Intégrer une **supervision centralisée Wazuh** avec détection d'intrusion

### Sécurité

- ✅ **Authentification** : PEAP-MSCHAPv2 sans certificat client
- ✅ **Isolation** : AP Isolation pour le réseau invité
- ✅ **Chiffrement** : TLS pour les échanges RADIUS
- ✅ **Hardening** : SSH sécurisé, firewall UFW, permissions restrictives
- ✅ **Audit** : Journalisation complète des authentifications

---

## 🏭 Architecture {#architecture}

### Schéma réseau

```
                    PC PORTABLE (Hôte)
                    ├─ WiFi (wlan0): Internet via Box
                    └─ LAN (enp0s8): Vers routeur TP-Link
                             │
                             │ Câble RJ45
                             ▼
              ┌───────────────────────────────┐
              │  ROUTEUR TP-LINK TL-MR100     │
              │  IP: 192.168.10.1             │
              ├───────────────────────────────┤
              │                                │
              │  SSID: Fitness-Pro            │
              │  - WPA2-Enterprise            │
              │  - Auth RADIUS via VM         │
              │                                │
              │  SSID: Fitness-Guest          │
              │  - WPA2-PSK                   │
              │  - AP Isolation activée       │
              │                                │
              │  RADIUS: 192.168.10.100:1812  │
              │  Syslog: 192.168.10.100:514   │
              └───────────────────────────────┘
                             │
                             │ Réseau 192.168.10.0/24
                             ▼
          ┌───────────────────────────────────┐
          │      VM DEBIAN 11 (Serveur)        │
          ├───────────────────────────────────┤
          │                                    │
          │  enp0s8 (Bridge): 192.168.10.100 │
          │  ├─ Gateway: 192.168.10.1          │
          │  └─ Communication avec routeur    │
          │                                    │
          │  enp0s3 (NAT): 10.0.2.15          │
          │  ├─ Gateway: 10.0.2.2              │
          │  └─ Internet pour apt-get         │
          │                                    │
          │  Services:                        │
          │  ├─ FreeRADIUS: 1812/UDP          │
          │  ├─ MySQL: 3306/TCP (local)       │
          │  ├─ Apache/PHP-Admin: 80/TCP      │
          │  ├─ Wazuh Manager: 1514/UDP       │
          │  └─ rsyslog: 514/UDP              │
          └───────────────────────────────────┘
```

### Flux d'authentification RADIUS

```
Client WiFi → Routeur (192.168.10.1) → VM (192.168.10.100:1812)
     ▲                                            │
     │                                            ▼
     └──────── Access-Accept/Reject ──── FreeRADIUS + MySQL
```

---

## ⚠️ Configuration Réseau IMPORTANTE {#config-reseau}

### VM Debian 11 : 2 interfaces réseau requises

#### Interface enp0s8 (Bridge LAN)

**Rôle** : Communication avec le routeur TP-Link et les clients WiFi

**Configuration** `/etc/network/interfaces` :
```bash
auto enp0s8
iface enp0s8 inet static
    address 192.168.10.100
    netmask 255.255.255.0
    # PAS de gateway ici (pour éviter conflit avec enp0s3)
    dns-nameservers 8.8.8.8 8.8.4.4
```

**Hyperviseur** : Mode Bridge sur l'interface LAN du PC hôte

#### Interface enp0s3 (NAT)

**Rôle** : Accès Internet pour `apt-get`, `wget`, installations de paquets

**Configuration** `/etc/network/interfaces` :
```bash
auto enp0s3
iface enp0s3 inet dhcp
```

**Hyperviseur** : Mode NAT (VirtualBox/VMware)

#### Vérification de la configuration

```bash
# Vérifier les interfaces
ip addr show

# enp0s8 doit avoir: 192.168.10.100
# enp0s3 doit avoir: 10.0.2.15 (ou similaire)

# Vérifier la connectivité routeur
ping 192.168.10.1

# Vérifier l'accès Internet
ping -I enp0s3 8.8.8.8
apt update    # Doit fonctionner via enp0s3
```

---

## 🎯 Ordre d'Exécution des Scripts {#ordre-execution}

**⚠️ IMPORTANT : Suivre cet ordre strictement**

### Phase 0 : Préparation (15 min)

```bash
# 1. Vérifier prérequis système
lsb_release -d && free -h && df -h /

# 2. Cloner le projet
cd ~
git clone https://github.com/sfrayan/SAE501v2.git
cd SAE501v2
chmod +x scripts/*.sh

# 3. VÉRIFICATION OBLIGATOIRE
bash scripts/check_prerequisites.sh
# ⚠️ Si échec : corriger les problèmes avant de continuer
# ✅ Si succès : continuer Phase 1

# 4. Configurer réseau (si pas déjà fait)
sudo nano /etc/network/interfaces
# Ajouter configuration enp0s3 et enp0s8 (voir section Configuration Réseau)
sudo systemctl restart networking

# 5. Vérifier connectivité
ping -I enp0s3 -c 2 8.8.8.8    # Internet via NAT
sudo apt update                  # Doit réussir
```

### Phase 1 : Installation Services (30 min)

**Option A : Installation complète automatique** (👍 Recommandé)

```bash
cd ~/SAE501v2
sudo bash scripts/install_all.sh
```

**Option B : Installation manuelle étape par étape** (Pour apprentissage)

```bash
cd ~/SAE501v2

# Étape 1 : FreeRADIUS (10 min)
sudo bash scripts/install_radius.sh

# Étape 2 : PHP-Admin (5 min)
sudo bash scripts/install_php_admin.sh

# Étape 3 : Wazuh (15 min)
sudo bash scripts/install_wazuh.sh
```

### Phase 2 : Vérification (5 min)

```bash
cd ~/SAE501v2
sudo bash scripts/diagnostics.sh
# Score attendu: > 85% ✅
```

### Phase 3 : Configuration Routeur (45 min)

Voir section [Configuration du Routeur](#routeur) ci-dessous

### Phase 4 : Tests et Validation (30 min)

Voir section [Tests et Validation](#tests) ci-dessous

---

## 🚀 Installation Complète {#installation}

### Phase 1 : Installation VM (30 min)

#### Étape 1.1 : Préparer la VM Debian 11

```bash
# Vérifier les prérequis
lsb_release -d        # Debian 11
free -h               # 4GB RAM minimum
df -h /               # 20GB disque minimum

# Mettre à jour le système
sudo apt update && sudo apt upgrade -y
```

#### Étape 1.2 : Cloner le projet

```bash
cd ~
git clone https://github.com/sfrayan/SAE501v2.git
cd SAE501v2
chmod +x scripts/*.sh
```

#### Étape 1.2bis : Vérifier les prérequis (NOUVEAU)

```bash
# EXÉCUTER EN PREMIER !
bash scripts/check_prerequisites.sh
# Doit afficher ✅ score vert
```

#### Étape 1.3 : Installer FreeRADIUS

```bash
# Installation automatisée
sudo bash scripts/install_radius.sh

# Vérifier
systemctl status freeradius
radtest alice@gym.fr Alice@123! 127.0.0.1 1812 testing123
# Attendu: Access-Accept
```

#### Étape 1.4 : Installer PHP-Admin

```bash
sudo bash scripts/install_php_admin.sh

# Vérifier
curl http://localhost/php-admin/list_users.php
```

#### Étape 1.5 : Installer Wazuh

```bash
sudo bash scripts/install_wazuh.sh

# Vérifier
cd /opt/wazuh-docker/single-node
docker compose ps
cat /root/wazuh-info.txt
```

#### Étape 1.6 : Diagnostic VM

```bash
sudo bash scripts/diagnostics.sh
# Score > 85% = OK ✓
```

---

### Phase 2 : Configuration du Routeur TL-MR100 (1h) {#routeur}

#### Étape 2.1 : Accéder au routeur

1. **Brancher le routeur** en RJ45 sur le port LAN de votre PC
2. **Accéder à l'interface**
   ```
   URL: http://192.168.10.1
   Login: admin
   Password: admin (par défaut)
   ```

#### Étape 2.2 : Configurer le réseau

**Menu** → **Network** → **LAN**

```
IP LAN: 192.168.10.1
Masque: 255.255.255.0
DHCP Server: Activé
  - Start IP: 192.168.10.101
  - End IP: 192.168.10.254
  - Réservation VM: 192.168.10.100
```

#### Étape 2.3 : Configurer RADIUS

**Menu** → **Wireless** → **RADIUS Settings**

```
Primary RADIUS Server:
  IP Address: 192.168.10.100
  Port: 1812
  Shared Secret: testing123
```

#### Étape 2.4 : Configurer les SSID

**SSID 1 - Fitness-Pro (Entreprise)**

```
SSID: Fitness-Pro
Security Mode: WPA2-Enterprise
RADIUS Server: 192.168.10.100:1812
Channel: Auto
Bandwidth: 20MHz
```

**SSID 2 - Fitness-Guest (Invités)**

```
SSID: Fitness-Guest
Security Mode: WPA2-PSK
Password: GuestPass@2026
AP Isolation: Activé (✅ Très important)
Channel: Auto
```

**⚠️ Note** : L'AP Isolation empêche les clients connectés à Fitness-Guest de communiquer entre eux.

#### Étape 2.5 : Configurer Syslog

**Menu** → **System** → **Log**

```
Syslog Server: 192.168.10.100
Port: 514
Protocol: UDP
Enable: ON
```

#### Étape 2.6 : Vérification

```bash
# Depuis votre PC
ping 192.168.10.1       # Routeur
ping 192.168.10.100     # VM

# Scanner les SSID
nmcli dev wifi list | grep Fitness
# Doit afficher:
#   Fitness-Pro
#   Fitness-Guest
```

---

### Phase 3 : Tests (45 min) {#tests}

#### Test 1 : Authentification Fitness-Pro

**Sur un client WiFi :**

1. Se connecter au SSID `Fitness-Pro`
2. Sélectionner **WPA2-Enterprise** / **PEAP**
3. Entrer :
   - **Identité** : `alice@gym.fr`
   - **Mot de passe** : `Alice@123!`
4. Vérifier l'IP obtenue : `192.168.10.x`

**Vérification sur la VM :**

```bash
# Voir les authentifications
sudo tail -f /var/log/freeradius/radius.log

# Doit afficher:
# Login OK: [alice@gym.fr] (from client 192.168.10.1 ...)
```

#### Test 2 : Connexion Fitness-Guest

1. Se connecter au SSID `Fitness-Guest`
2. Entrer le mot de passe : `GuestPass@2026`
3. Vérifier l'IP obtenue : `192.168.10.x`

#### Test 3 : AP Isolation

**Depuis un client Fitness-Guest :**

```bash
# Identifier IP d'un autre client Guest
arp -a

# Tenter de ping
ping <IP_autre_client_guest>
# ✅ Doit échouer (timeout) grâce à l'AP Isolation
```

#### Test 4 : Logs Wazuh

```bash
# Sur la VM
cat /var/log/wazuh-export/alerts.json | head -20

# Accéder à l'interface web
http://192.168.10.100/php-admin/wazuh_logs.php
```

---

### Phase 4 : Hardening (30 min) {#hardening}

#### SSH sécurisé

```bash
# Générer clés SSH (sur votre PC)
ssh-keygen -t ed25519 -f ~/.ssh/sae501_key

# Copier la clé publique sur la VM
ssh-copy-id -i ~/.ssh/sae501_key.pub user@192.168.10.100

# Sur la VM : désactiver authentification par mot de passe
sudo nano /etc/ssh/sshd_config

# Modifier:
PasswordAuthentication no
PermitRootLogin no

# Redémarrer SSH
sudo systemctl restart ssh
```

#### Firewall UFW

```bash
# UFW est installé automatiquement par le script Wazuh
# Vérifier les règles
sudo ufw status verbose

# Ajouter des règles supplémentaires si nécessaire
sudo ufw allow from 192.168.10.0/24 to any port 3306 proto tcp # MySQL (si accès distant)
```

#### Permissions

```bash
# FreeRADIUS
sudo chown -R root:freerad /etc/freeradius/3.0
sudo chmod -R 750 /etc/freeradius/3.0
sudo chmod 640 /etc/freeradius/3.0/clients.conf

# MySQL
sudo chown -R mysql:mysql /var/lib/mysql
sudo chmod 700 /var/lib/mysql
```

---

## 🔧 Troubleshooting {#troubleshooting}

### Problème : VM ne peut pas joindre le routeur

```bash
# Vérifier enp0s8
ip addr show enp0s8
# Doit afficher: 192.168.10.100

# Vérifier que enp0s8 est en mode Bridge dans l'hyperviseur
# VirtualBox: Réseau → Mode d'accès réseau: Pont

# Redémarrer l'interface
sudo ifdown enp0s8 && sudo ifup enp0s8

ping 192.168.10.1
```

### Problème : apt-get ne fonctionne pas

```bash
# Vérifier enp0s3 (NAT)
ip addr show enp0s3
# Doit avoir une IP 10.0.2.x

# Tester Internet via enp0s3
ping -I enp0s3 8.8.8.8

# Si ça ne fonctionne pas, vérifier que enp0s3 est en NAT dans l'hyperviseur
```

### Problème : Clients WiFi ne s'authentifient pas

```bash
# Mode debug FreeRADIUS
sudo systemctl stop freeradius
sudo freeradius -X
# Observer les paquets RADIUS entrants

# Vérifier le secret RADIUS
grep "secret" /etc/freeradius/3.0/clients.conf
# Doit correspondre à la config du routeur (testing123)

# Vérifier le firewall
sudo ufw status | grep 1812
```

### Problème : Logs Wazuh vides

```bash
# Vérifier que Wazuh fonctionne
cd /opt/wazuh-docker/single-node
docker compose ps

# Exécuter manuellement l'export
sudo /usr/local/bin/export-wazuh-logs.sh

# Vérifier le fichier
cat /var/log/wazuh-export/alerts.json | head -10

# Vérifier le cron
crontab -l | grep export
```

---

## 📋 Checklist finale

- [ ] **VM configurée**
  - [ ] enp0s8 (Bridge): 192.168.10.100
  - [ ] enp0s3 (NAT): Internet fonctionnel
  - [ ] FreeRADIUS actif et testé
  - [ ] MySQL opérationnel
  - [ ] PHP-Admin accessible
  - [ ] Wazuh Docker UP
  - [ ] UFW activé
  - [ ] Cron export logs configuré

- [ ] **Routeur configuré**
  - [ ] IP: 192.168.10.1
  - [ ] RADIUS: 192.168.10.100:1812 configuré
  - [ ] SSID Fitness-Pro visible (WPA2-Enterprise)
  - [ ] SSID Fitness-Guest visible (WPA2-PSK)
  - [ ] AP Isolation activée sur Guest
  - [ ] Syslog vers 192.168.10.100:514

- [ ] **Tests réussis**
  - [ ] Authentification Fitness-Pro OK
  - [ ] Connexion Fitness-Guest OK
  - [ ] AP Isolation vérifiée
  - [ ] Logs RADIUS visibles
  - [ ] Wazuh reçoit les logs
  - [ ] Interface web Wazuh accessible

- [ ] **Sécurité appliquée**
  - [ ] SSH par clés uniquement
  - [ ] UFW actif
  - [ ] Permissions correctes

---

## 📚 Documentation

Consultez `docs/` pour plus de détails :

- `dossier-architecture.md` : Architecture technique détaillée
- `hardening-linux.md` : Sécurisation approfondie
- `wazuh-supervision.md` : Configuration Wazuh avancée
- `analyse-ebios.md` : Analyse de risques ANSSI

---

**🚀 Bon courage !**
