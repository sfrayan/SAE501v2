# 🏋️ SAE 5.01 - Architecture Wi-Fi Sécurisée avec RADIUS

**Projet académique SAE 5.01** - Déploiement d'une infrastructure Wi-Fi sécurisée avec authentification 802.1X et supervision centralisée.

**Durée totale** : ~3 heures (VM : 30 min + Routeur : 1h + Tests/Hardening : 1.5h)

---

## 📋 Table des matières

1. [Objectifs du projet](#objectifs)
2. [Architecture globale](#architecture)
3. [Configuration réseau IMPORTANTE](#config-reseau)
4. [Installation complète](#installation)
5. [Configuration du routeur](#routeur)
6. [Tests et validation](#tests)
7. [Hardening du serveur](#hardening)
8. [Troubleshooting](#troubleshooting)

---

## 🎯 Objectifs

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

## 🏭 Architecture

### Schéma réseau

```
                    PC PORTABLE (Hôte)
                    ├─ WiFi (wlan0): Internet via Box
                    └─ LAN (eth0): Vers routeur TP-Link
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
          │  eth0 (Bridge): 192.168.10.100   │
          │  ├─ Gateway: 192.168.10.1          │
          │  └─ Communication avec routeur    │
          │                                    │
          │  eth1 (NAT): 10.0.2.15           │
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

#### Interface eth0 (Bridge LAN)

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

#### Interface eth1 (NAT)

**Rôle** : Accès Internet pour `apt-get`, `wget`, installations de paquets

**Configuration** `/etc/network/interfaces` :
```bash
auto eth1
iface eth1 inet dhcp
```

**Hyperviseur** : Mode NAT (VirtualBox/VMware)

#### Vérification de la configuration

```bash
# Vérifier les interfaces
ip addr show

# eth0 doit avoir: 192.168.10.100
# eth1 doit avoir: 10.0.2.15 (ou similaire)

# Vérifier la connectivité routeur
ping 192.168.10.1

# Vérifier l'accès Internet
ping -I eth1 8.8.8.8
apt update    # Doit fonctionner via eth1
```

---

## 🚀 Installation complète {#installation}

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

#### Étape 1.5 : Installer Wazuh (optionnel)

```bash
sudo bash scripts/install_wazuh.sh

# Vérifier
systemctl status wazuh-manager
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
  Shared Secret: Pj8K2qL9xR5wM3nP7dF4vB6tH1sQ9cZ2
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
sudo grep -i "radius\|authentication" /var/ossec/logs/alerts/alerts.json

# Vérifier réception logs routeur
sudo tail -f /var/log/syslog | grep "192.168.10.1"
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
# Activer UFW
sudo ufw enable

# Règles essentielles
sudo ufw allow from 192.168.10.0/24 to any port 22 proto tcp   # SSH
sudo ufw allow from 192.168.10.0/24 to any port 1812 proto udp # RADIUS
sudo ufw allow from 192.168.10.0/24 to any port 514 proto udp  # Syslog
sudo ufw allow from 192.168.10.0/24 to any port 80 proto tcp   # Web

# Bloquer tout le reste
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Vérifier
sudo ufw status verbose
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
# Vérifier eth0
ip addr show eth0
# Doit afficher: 192.168.10.100

# Vérifier que eth0 est en mode Bridge dans l'hyperviseur
# VirtualBox: Réseau → Mode d'accès réseau: Pont

# Redémarrer l'interface
sudo ifdown eth0 && sudo ifup eth0

ping 192.168.10.1
```

### Problème : apt-get ne fonctionne pas

```bash
# Vérifier eth1 (NAT)
ip addr show eth1
# Doit avoir une IP 10.0.2.x

# Tester Internet via eth1
ping -I eth1 8.8.8.8

# Si ça ne fonctionne pas, vérifier que eth1 est en NAT dans l'hyperviseur
```

### Problème : Clients WiFi ne s'authentifient pas

```bash
# Mode debug FreeRADIUS
sudo systemctl stop freeradius
sudo freeradius -X
# Observer les paquets RADIUS entrants

# Vérifier le secret RADIUS
grep "secret" /etc/freeradius/3.0/clients.conf
# Doit correspondre à la config du routeur

# Vérifier le firewall
sudo ufw status | grep 1812
```

### Problème : AP Isolation ne fonctionne pas

```bash
# Vérifier que l'AP Isolation est activée sur le routeur
# Menu → Wireless → Guest Network → Enable AP Isolation

# Tester depuis un client Guest
arp -a  # Voir les autres clients
ping <IP_autre_client>
# Doit échouer (Request timeout)
```

---

## 📋 Checklist finale

- [ ] **VM configurée**
  - [ ] eth0 (Bridge): 192.168.10.100
  - [ ] eth1 (NAT): Internet fonctionnel
  - [ ] FreeRADIUS actif et testé
  - [ ] MySQL opérationnel
  - [ ] PHP-Admin accessible

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
