# 🏋️ SAE 5.01 - Architecture Wi-Fi Sécurisée Multi-Sites

**Projet académique SAE 5.01** - Déploiement d'une infrastructure Wi-Fi d'entreprise sécurisée avec authentification 802.1X, supervision centralisée et architecture multi-sites.

**Durée totale** : ~3 heures (VM : 30 min + Routeur : 1h + Tests/Hardening : 1.5h)

---

## 📋 Table des matières

1. [Objectifs du projet](#objectifs)
2. [Architecture globale](#architecture)
3. [Installation complète (guide étape par étape)](#installation)
4. [Configuration du routeur](#routeur)
5. [Tests et validation](#tests)
6. [Hardening du serveur](#hardening)
7. [Supervision avec Wazuh](#wazuh)
8. [Troubleshooting](#troubleshooting)
9. [Livrables et documentation](#livrables)

---

## 🎯 Objectifs

### Fonctionnels

- ✅ Déployer un **serveur RADIUS centralisé** (FreeRADIUS + MySQL)
- ✅ Configurer une **authentification 802.1X sécurisée** (PEAP-MSCHAPv2, sans certificat client)
- ✅ Mettre en place un **réseau Wi-Fi d'entreprise** sécurisé et un **réseau invité isolé**
- ✅ Implémenter une **interface de gestion** (PHP) pour ajouter/supprimer des utilisateurs
- ✅ Intégrer une **supervision centralisée** (Wazuh) avec détection d'intrusion
- ✅ Tester l'**isolement réseau** entre VLAN (staff/guests/managers)

### Sécurité

- ✅ **Authentification** : PEAP-MSCHAPv2 sans certificat client (facile à déployer)
- ✅ **Isolation** : Réseau invité isolé du réseau interne
- ✅ **Chiffrement** : TLS pour les échanges RADIUS
- ✅ **Hardening** : SSH sécurisé, firewall UFW, permissions restrictives
- ✅ **Audit** : Journalisation complète des authentifications et accès

### Pédagogiques

- ✅ Comprendre les protocoles **802.1X et EAP**
- ✅ Maîtriser **FreeRADIUS** et son intégration MySQL
- ✅ Configurer **Wazuh** pour la détection de menaces
- ✅ Analyser les risques **EBIOS ANSSI**
- ✅ Appliquer le **hardening Linux** en production

---

## 🏗️ Architecture

### Vue d'ensemble

```
┌─────────────────────────────────────────────────────────────────┐
│                    INFRASTRUCTURE SAE 5.01                       │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│                    SERVEUR CENTRALISÉ (Debian 11 VM)             │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  AUTHENTIFICATION & GESTION                              │   │
│  │  ┌──────────────────┐  ┌──────────────────────────────┐ │   │
│  │  │  FreeRADIUS      │  │  MariaDB/MySQL               │ │   │
│  │  │  Port: 1812 UDP  │  │  Port: 3306 TCP              │ │   │
│  │  │  PEAP-MSCHAPv2   │  │  DB: radius                  │ │   │
│  │  │  Certificat TLS  │  │  Tables: radcheck, radacct   │ │   │
│  │  └──────────────────┘  └──────────────────────────────┘ │   │
│  │          │                          │                      │   │
│  │          └──────────┬───────────────┘                      │   │
│  │                     │                                       │   │
│  │  ┌─────────────────────────────────────────────────────┐  │   │
│  │  │  PHP-Admin Interface (Web UI)                       │  │   │
│  │  │  - Ajouter/supprimer utilisateurs RADIUS            │  │   │
│  │  │  - Afficher les comptes actifs                      │  │   │
│  │  │  - Journaliser les actions                          │  │   │
│  │  │  Port: 80/443 (Apache + PHP)                       │  │   │
│  │  └─────────────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  SUPERVISION & SÉCURITÉ                                 │   │
│  │  ┌──────────────────┐  ┌──────────────────────────────┐ │   │
│  │  │  Wazuh Manager   │  │  rsyslog                     │ │   │
│  │  │  Port: 1514 UDP  │  │  Port: 514 UDP               │ │   │
│  │  │  - SIEM          │  │  Réception logs              │ │   │
│  │  │  - Alertes       │  │  - FreeRADIUS                │ │   │
│  │  │  - Détection     │  │  - Routeur TL-MR100         │ │   │
│  │  └──────────────────┘  └──────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  SÉCURITÉ SERVEUR                                       │   │
│  │  - SSH: Authentification par clés (pas root)            │   │
│  │  - UFW: Pare-feu configuré (ports min)                  │   │
│  │  - Permissions: 640 (config), 750 (répertoires)        │   │
│  │  - Audit: journalctl, auditctl                          │   │
│  └─────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
                             ▲
                    Ethernet / RJ45
                             │
┌──────────────────────────────────────────────────────────────────┐
│          ROUTEUR TP-LINK TL-MR100 (Point d'accès Wi-Fi)          │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  SSID "Fitness-Pro" (Entreprise)                          │ │
│  │  - WPA2-Enterprise                                         │ │
│  │  - Authentification PEAP-MSCHAPv2 via RADIUS              │ │
│  │  - VLAN 10 (Staff)                                         │ │
│  │  - IP: 192.168.10.x (/24)                                 │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  SSID "Fitness-Guest" (Invités)                           │ │
│  │  - WPA2-PSK (mot de passe partagé)                        │ │
│  │  - Isolement: AP Isolation activée                         │ │
│  │  - VLAN 20 (Guests)                                        │ │
│  │  - IP: 192.168.20.x (/24)                                 │ │
│  │  - Accès Internet seul (pas d'accès au réseau interne)   │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Configuration RADIUS                                      │ │
│  │  - Serveur: IP du serveur (ex: 192.168.10.100)           │ │
│  │  - Port: 1812 UDP                                         │ │
│  │  - Secret: Pj8K2qL9xR5wM3nP7dF4vB6tH1sQ9cZ2              │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Syslog vers Wazuh                                         │ │
│  │  - IP: 192.168.10.100                                     │ │
│  │  - Port: 514 UDP                                          │ │
│  │  - Pour supervision et audit                              │ │
│  └────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
                             ▲
                    Clients Wi-Fi (RJ45 ou USB)
                             │
┌──────────────────────────────────────────────────────────────────┐
│              CLIENTS Wi-Fi (Smartphones, laptops)                 │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  CLIENT STAFF (Entreprise)          CLIENT GUEST (Invités)      │
│  ┌────────────────────────┐        ┌────────────────────────┐   │
│  │ SSID: Fitness-Pro      │        │ SSID: Fitness-Guest    │   │
│  │ Auth: 802.1X (EAP)     │        │ Auth: WPA2-PSK         │   │
│  │ User: alice@gym.fr     │        │ Password: public       │   │
│  │ Pass: Alice@123!       │        │ VLAN: 20               │   │
│  │ VLAN: 10               │        │ Isolation: OUI         │   │
│  │ IP: 192.168.10.x       │        │ IP: 192.168.20.x       │   │
│  │ Accès: Réseau complet  │        │ Accès: Internet seul   │   │
│  └────────────────────────┘        └────────────────────────┘   │
│                                                                   │
│  FLOW D'AUTHENTIFICATION (PEAP-MSCHAPv2)                        │
│                                                                   │
│  Client              TL-MR100            FreeRADIUS/MySQL        │
│    │                    │                      │                │
│    ├─ Scan réseau ─────>│                      │                │
│    │                    │                      │                │
│    ├─ Association ─────>│                      │                │
│    │  (SSID+BSSID)      │                      │                │
│    │                    │                      │                │
│    ├─ EAP-Identity ────>│──────────────────────>│                │
│    │  (alice@gym.fr)    │                      │                │
│    │                    │                      ├─ Lookup BD     │
│    │                    │                      │                │
│    │<──────────────────────── EAP-Request ────|                │
│    │  (TLS, certificat  │                      │                │
│    │   serveur)         │                      │                │
│    │                    │                      │                │
│    ├──────────────────────────> EAP-Response ──>│                │
│    │  (mot de passe     │                      │                │
│    │   chiffré via TLS) │                      ├─ Vérification │
│    │                    │                      │                │
│    │<─────────────────────── EAP-Success ─────|                │
│    │                    │<─ Access-Accept ───|                │
│    │                    │                      │                │
│    ├─ DHCP Request ────>│                      │                │
│    │                    ├─ Assign VLAN 10    │                │
│    │<─ DHCP Lease ──────│ (staff)              │                │
│    │  (192.168.10.x)    │                      │                │
│    │                    │                      │                │
│    ├─ Accès réseau OK ──────────> ✅ CONNECTÉ                 │
│    │                    │                      │                │
└────────────────────────────────────────────────────────────────┘
```

---

## 🚀 Installation complète (du début à la fin)

### Phase 1 : Installation VM (30 min)

#### Étape 1.1 : Préparer la VM Debian 11

```bash
# Vérifier les prérequis
lsb_release -d        # Debian 11 ou Ubuntu 20.04+
free -h               # 4GB RAM
df -h /               # 20GB disque

# Mettre à jour le système
sudo apt update && sudo apt upgrade -y
```

#### Étape 1.2 : Cloner le projet

```bash
cd ~
git clone https://github.com/votre-username/SAE501.git
cd SAE501
chmod +x scripts/*.sh
```

#### Étape 1.3 : Installer FreeRADIUS

```bash
# Installation automatisée
sudo bash scripts/install_radius.sh

# Vérifier
systemctl status freeradius
radtest alice@gym.fr Alice@123! 127.0.0.1 1812 testing123
# Expected: Response code (2) = Access-Accept
```

#### Étape 1.4 : Installer PHP-Admin

```bash
sudo bash scripts/install_php_admin.sh

# Vérifier
curl http://localhost/php-admin/list_users.php
# Devrait afficher une liste HTML
```

#### Étape 1.5 : Installer Wazuh

```bash
sudo bash scripts/install_wazuh.sh

# Vérifier
systemctl status wazuh-manager
sudo tail -f /var/ossec/logs/ossec.log
```

#### Étape 1.6 : Diagnostic VM

```bash
sudo bash scripts/diagnostics.sh
# Score > 85% = OK ✓
```

---

### Phase 2 : Configuration du Routeur TL-MR100 (1 heure)

#### Étape 2.1 : Préparer le routeur

1. **Brancher le routeur** en RJ45 sur votre ordinateur portable
2. **Accéder à l'interface d'administration**
   ```
   URL: http://192.168.0.1
   Admin: admin
   Password: admin
   ```

#### Étape 2.2 : Configuration réseau

1. **Paramètres WAN** → Mode 4G (optionnel, on peut aussi utiliser Ethernet)
2. **Paramètres LAN** → Configurer IP statique
   ```
   IP LAN: 192.168.10.1
   Masque: 255.255.255.0
   DHCP: Activé (192.168.10.100 → 192.168.10.254)
   ```

#### Étape 2.3 : Configurer l'authentification RADIUS

Dans l'interface admin du routeur :

**Menu** → **System** → **RADIUS**

```
Primary RADIUS Server:
  IP Address: 192.168.10.100 (IP de votre VM)
  Port: 1812
  Secret: Pj8K2qL9xR5wM3nP7dF4vB6tH1sQ9cZ2
  
Secondary (optionnel):
  (laisser vide ou duplicata du primary)
```

#### Étape 2.4 : Configurer les SSID

**Menu** → **Wireless** → **Edit**

**SSID 1 - Entreprise (Fitness-Pro)**
```
SSID: Fitness-Pro
Channel: 6 (ou 1, 11 selon préférence)
Bandwidth: 20MHz
Transmit Power: High
Security:
  - Type: WPA2-Enterprise
  - RADIUS Server: Configuré ci-dessus
  - VLAN: Enabled (VLAN 10)
AP Isolation: Disabled (permet client-to-client)
```

**SSID 2 - Invités (Fitness-Guest)**
```
SSID: Fitness-Guest
Channel: 6 (ou autre)
Bandwidth: 20MHz
Transmit Power: High
Security:
  - Type: WPA2-PSK
  - Password: GuestPass@2026 (à changer)
  - VLAN: Enabled (VLAN 20)
AP Isolation: Enabled (isole les clients les uns des autres)
Bandwidth Limit: 10 Mbps (optionnel, pour limiter les invités)
```

#### Étape 2.5 : Configurer le Syslog vers Wazuh

**Menu** → **System** → **Syslog**

```
Syslog Server:
  IP Address: 192.168.10.100 (VM)
  Port: 514
  Protocol: UDP
  Enable: ON
```

#### Étape 2.6 : Vérifier la configuration

```bash
# Depuis votre ordinateur (ou une autre machine)
ping 192.168.10.1
# Doit répondre

# Scanner les SSID
nmcli dev wifi list
# Doit afficher:
#  Fitness-Pro
#  Fitness-Guest
```

---

### Phase 3 : Tests Wi-Fi et Validation (45 min)

#### Étape 3.1 : Test authentification PEAP sur client

**Depuis un client Linux :**

```bash
# Installer les tools
sudo apt install wpa-supplicant network-manager wpasupplicant

# Créer un profil de connexion
cat > ~/fitness-pro.conf << 'EOF'
network={
    ssid="Fitness-Pro"
    key_mgmt=WPA-EAP
    eap=PEAP
    phase1="peapver=auto"
    phase2="auth=MSCHAPV2"
    identity="alice@gym.fr"
    password="Alice@123!"
    ca_cert="/etc/ssl/certs/ca-certificates.crt"
    anonymous_identity="anonymous"
}
EOF

# Tester la connexion
sudo wpa_supplicant -i wlan0 -c ~/fitness-pro.conf -v
# Devrait afficher: "CONNECTED"
```

**Depuis Windows/Mac :**
1. Ouvrir paramètres Wi-Fi
2. Cliquer sur "Fitness-Pro" → Connecter
3. Sélectionner **PEAP**
4. Entrer : `alice@gym.fr` / `Alice@123!`

#### Étape 3.2 : Vérifier l'assignation VLAN

```bash
# Voir l'IP obtenue
ip addr show
# Doit être 192.168.10.x (VLAN 10 pour Entreprise)

# Ou pour Invités:
# Doit être 192.168.20.x (VLAN 20 pour Guests)
```

#### Étape 3.3 : Test isolement réseau (VLAN)

```bash
# Depuis un client STAFF (VLAN 10)
ping 192.168.10.254          # Gateway STAFF → OK
ping 8.8.8.8                 # Internet → OK

# Depuis un client GUEST (VLAN 20)
ping 192.168.20.254          # Gateway GUEST → OK
ping 192.168.10.1            # Routeur (autre VLAN) → BLOQUÉ ✓
ping 192.168.10.x (staff)    # Client STAFF → BLOQUÉ ✓
ping 8.8.8.8                 # Internet → OK
```

#### Étape 3.4 : Test avec tcpdump (preuve d'isolement)

```bash
# Sur la VM Debian
cd ~/SAE501

# Lancer le test d'isolement
sudo bash tests/test_isolement.sh 192.168.10.1

# Générer capture tcpdump
sudo tcpdump -i eth0 -w isolement.pcap port 1812 or port 514

# Analyser avec Wireshark
wireshark isolement.pcap &
```

#### Étape 3.5 : Vérifier la supervision Wazuh

```bash
# Sur la VM, vérifier que Wazuh reçoit les authentifications
sudo grep -i "radius\|authentication" /var/ossec/logs/alerts/alerts.json

# Vérifier les logs du routeur reçus
sudo tail -f /var/log/syslog | grep "TL-MR100\|radiusd"
```

---

### Phase 4 : Hardening du Serveur Linux (30 min)

#### Étape 4.1 : Sécuriser SSH

```bash
# Générer une paire de clés (locale)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_sae501

# Copier la clé publique sur la VM
ssh-copy-id -i ~/.ssh/id_rsa_sae501.pub user@vm-sae501

# Configuration SSH sécurisée (sur la VM)
sudo nano /etc/ssh/sshd_config

# Modifier:
PermitRootLogin no                    # Désactiver root
PubkeyAuthentication yes               # Clés SSH
PasswordAuthentication no              # Pas de password
X11Forwarding no                       # Pas de X11
MaxAuthTries 3                         # Limite tentatives
LoginGraceTime 30s                     # Timeout

# Redémarrer SSH
sudo systemctl restart ssh

# Vérifier
sudo systemctl status ssh
```

#### Étape 4.2 : Configurer le Firewall UFW

```bash
# Activer UFW
sudo ufw enable

# Autoriser SSH
sudo ufw allow 22/tcp

# Services essentiels
sudo ufw allow 1812/udp      # FreeRADIUS
sudo ufw allow 1813/udp      # FreeRADIUS acct
sudo ufw allow 1514/udp      # Wazuh syslog
sudo ufw allow 80/tcp        # Apache (PHP-Admin)
sudo ufw allow 443/tcp       # Apache HTTPS

# Vérifier la configuration
sudo ufw status verbose

# Par défaut: tous les ports fermés, sauf ceux autorisés ✓
```

#### Étape 4.3 : Permissions et propriétaires

```bash
# FreeRADIUS
sudo chown -R root:freerad /etc/freeradius/3.0
sudo chmod -R 750 /etc/freeradius/3.0
sudo chmod 640 /etc/freeradius/3.0/clients.conf

# MySQL/MariaDB
sudo chown -R mysql:mysql /var/lib/mysql
sudo chmod -R 750 /var/lib/mysql

# Wazuh
sudo chown -R root:wazuh /var/ossec/etc/
sudo chmod -R 750 /var/ossec/etc/

# Logs
sudo mkdir -p /var/log/freeradius
sudo chown freerad:freerad /var/log/freeradius
sudo chmod 750 /var/log/freeradius
```

#### Étape 4.4 : Journalisation centralisée

```bash
# Activer auditctl (audit du système)
sudo apt install auditd
sudo systemctl enable auditd
sudo systemctl start auditd

# Monitorer les actions sensibles
sudo auditctl -w /etc/freeradius/3.0/clients.conf -p wa -k radius_config
sudo auditctl -w /var/lib/mysql/radius -p wa -k radius_db

# Vérifier
sudo auditctl -l

# Voir les événements
sudo tail -f /var/log/audit/audit.log
```

#### Étape 4.5 : Hardening supplémentaire

```bash
# Désactiver services inutiles
sudo systemctl disable bluetooth avahi-daemon cups

# Mettre à jour régulièrement
sudo apt update && sudo apt upgrade -y

# Vérifier les ports ouverts
sudo ss -lun
# Doit afficher SEULEMENT:
#  Port 22 (SSH)
#  Port 80 (Apache)
#  Port 1812 (RADIUS)
#  Port 1514 (Wazuh syslog)
```

---

### Phase 5 : Tests de sécurité (15 min)

#### Étape 5.1 : Test Access-Reject (brute-force)

```bash
# Générer 100 tentatives d'authentification échouées
for i in {1..100}; do
  radtest fake$i@gym.fr FakePass123! 127.0.0.1 1812 testing123 2>/dev/null &
done

# Vérifier que Wazuh détecte le brute-force
sudo grep -i "brute\|failed" /var/ossec/logs/alerts/alerts.json
# Devrait afficher des alertes
```

#### Étape 5.2 : Vérifier l'isolement invités

```bash
# Client STAFF (VLAN 10) tente d'accéder à Client GUEST (VLAN 20)
ping 192.168.20.x
# BLOQUÉ ✓ (timeout)

# Vérifier avec tcpdump
sudo tcpdump -i eth0 "icmp and src 192.168.10.0/24"
# Les paquets ICMP entre VLANs ne doivent pas être relayés
```

#### Étape 5.3 : Test de performance Wazuh

```bash
# Générer du trafic RADIUS
for i in {1..50}; do
  radtest user$i@gym.fr Pass$i 127.0.0.1 1812 testing123 &
done

# Monitorer les alertes Wazuh
watch 'grep -c "^20" /var/ossec/logs/alerts/alerts.json'
```

---

## 🔧 Dépannage avancé

### Problèmes FreeRADIUS

```bash
# Vérifier syntaxe
sudo freeradius -XC

# Mode debug (très verbeux)
sudo freeradius -X

# Redémarrer proprement
sudo systemctl restart freeradius

# Voir les erreurs
sudo journalctl -u freeradius -n 100
```

### Problèmes routeur

```bash
# Vérifier connectivité VM ↔ Routeur
ping 192.168.10.1

# Vérifier que RADIUS est reçu (sur routeur)
# Menu → System → Status → Statistics

# Réinitialiser routeur
# Menu → System → Reboot
# (OU: maintenir le bouton reset 10 secondes)
```

### Problèmes réseau Wi-Fi

```bash
# Scanner pour voir les SSID
sudo iw dev wlan0 scan | grep "SSID:"

# Test connectivité ESSID
sudo nmcli dev wifi connect Fitness-Pro password Alice@123!

# Vérifier la qualité du signal
nmcli -f SSID,SIGNAL,SECURITY dev wifi list
```

---

## 📚 Documentation complémentaire

Consultez les fichiers dans `docs/` :

- **dossier-architecture.md** : Architecture complète, explications techniques
- **hardening-linux.md** : Détails sécurité, commandes par catégorie
- **wazuh-supervision.md** : Configuration avancée Wazuh, règles personnalisées
- **isolement-wifi.md** : Tests d'isolement détaillés, captures Wireshark
- **analyse-ebios.md** : Analyse de risques ANSSI, matrice menaces/mesures
- **journal-de-bord.md** : Suivi du projet, jalons, leçons apprises

---

## 📋 Checklist finale d'installation

- [ ] **Phase 1 (VM)** - 30 min
  - [ ] FreeRADIUS installé et testé
  - [ ] MySQL opérationnel
  - [ ] PHP-Admin accessible
  - [ ] Wazuh Manager actif
  - [ ] Diagnostic: Score > 85%

- [ ] **Phase 2 (Routeur)** - 1h
  - [ ] Routeur accessible (192.168.10.1)
  - [ ] RADIUS configuré
  - [ ] SSID "Fitness-Pro" visible
  - [ ] SSID "Fitness-Guest" visible
  - [ ] Syslog vers Wazuh configuré

- [ ] **Phase 3 (Tests)** - 45 min
  - [ ] Client STAFF se connecte (Fitness-Pro)
  - [ ] Client STAFF obtient IP 192.168.10.x
  - [ ] Client GUEST se connecte (Fitness-Guest)
  - [ ] Client GUEST obtient IP 192.168.20.x
  - [ ] VLAN 10 ↔ VLAN 20 : Isolé ✓
  - [ ] Wazuh reçoit les logs

- [ ] **Phase 4 (Hardening)** - 30 min
  - [ ] SSH sans password, root désactivé
  - [ ] UFW actif, ports minimaux ouverts
  - [ ] Permissions fichiers restrictives
  - [ ] Auditctl monitore les actions sensibles
  - [ ] Services inutiles désactivés

- [ ] **Phase 5 (Tests sécurité)** - 15 min
  - [ ] Brute-force détecté par Wazuh
  - [ ] Isolement VLAN validé (tcpdump)
  - [ ] Wazuh gère la charge (50+ auth/s)

---

## 🎯 Livrables GitLab/GitHub

Votre dépôt **DOIT** contenir :

```
SAE501/
├── README.md (ce fichier - vue complète du projet)
├── SETUP.md (guide étape par étape)
│
├── docs/
│   ├── dossier-architecture.md
│   ├── hardening-linux.md
│   ├── wazuh-supervision.md
│   ├── isolement-wifi.md
│   ├── analyse-ebios.md
│   ├── journal-de-bord.md
│   └── diagramme-gantt.md
│
├── scripts/
│   ├── install_radius.sh
│   ├── install_php_admin.sh
│   ├── install_wazuh.sh
│   └── diagnostics.sh
│
├── tests/
│   ├── test_peap.sh
│   ├── test_isolement.sh
│   └── test_syslog_mr100.sh
│
├── radius/
│   ├── clients.conf
│   ├── users.txt
│   └── sql/
│       ├── create_tables.sql
│       └── init_appuser.sql
│
├── php-admin/
│   ├── index.php
│   ├── add_user.php
│   ├── list_users.php
│   ├── delete_user.php
│   └── config.php
│
├── wazuh/
│   ├── manager.conf
│   ├── local_rules.xml
│   └── syslog-tlmr100.conf
│
└── captures/
    ├── vm-installation.png
    ├── router-config.png
    ├── wifi-connection.png
    ├── wazuh-dashboard.png
    └── isolation-tcpdump.pcap
```

---

## ⏱️ Récapitulatif des durées

| Phase | Tâche | Durée | Total |
|-------|-------|-------|-------|
| 1 | Clone + RADIUS | 10 min | 30 min |
| 1 | PHP-Admin | 5 min |  |
| 1 | Wazuh | 10 min |  |
| 1 | Diagnostic | 5 min |  |
| 2 | Config routeur | 45 min | 1h |
| 2 | Configuration SSID + Syslog | 15 min |  |
| 3 | Tests client Wi-Fi | 20 min | 45 min |
| 3 | Tests isolement VLAN | 15 min |  |
| 3 | Supervision Wazuh | 10 min |  |
| 4 | Hardening SSH/UFW | 15 min | 30 min |
| 4 | Permissions/Audit | 15 min |  |
| 5 | Tests sécurité | 15 min | 15 min |
| **TOTAL** | **Du clone au projet complet** | | **~2h30** |

---

## 💡 Conseils importants

### ✅ Bonnes pratiques

1. **Documentez au fur et à mesure** (journal-de-bord.md)
2. **Commitez régulièrement** sur GitHub/GitLab
3. **Testez après chaque phase** (ne pas laisser traîner les bugs)
4. **Sauvegardez les configurations** (copies locales)
5. **Gardez les logs** (ils servent pour le troubleshooting)

### 🔒 Sécurité

1. **Ne JAMAIS partager le secret RADIUS en public**
2. **Changer les passwords de test avant de présenter**
3. **Activer le firewall AVANT de connecter au routeur**
4. **Auditer régulièrement les authentifications**
5. **Archiver les logs (au moins 30 jours)**

### 📊 Préparation examen

- Comprendre le **flow PEAP-MSCHAPv2** (diagramme ci-dessus)
- Maîtriser les **commandes clés** (radtest, tcpdump, journalctl)
- Savoir **diagnostiquer un Access-Reject**
- Connaître l'**architecture multi-sites** (pourquoi RADIUS centralisé)
- Expliquer l'**isolement VLAN** (why/how)

---

## 📞 Support

Pour toute question :
1. Consultez les fichiers `docs/`
2. Lancez `sudo bash scripts/diagnostics.sh`
3. Vérifiez les logs : `sudo journalctl -u freeradius -u wazuh-manager -n 50`
4. Posez vos questions à l'enseignant en TP

---

## 🏆 Critères d'évaluation

Votre projet sera évalué sur :

1. **Architecture** (10 pts) : Conception robuste et justifiée
2. **Implémentation** (15 pts) : Tous les services opérationnels
3. **Sécurité** (15 pts) : Hardening appliqué, PEAP-MSCHAPv2 correct
4. **Tests** (10 pts) : Preuves d'isolement, supervision fonctionnelle
5. **Documentation** (10 pts) : README/SETUP/docs complets
6. **GitLab** (7 pts) : Commits réguliers, journal de bord à jour
7. **Contrôle écrit** (23 pts) : Questions sur architecture, protocoles, sécurité

**Note max : 100 pts / 7 = ~14,3/20 en examen**

---

**🚀 Bon courage !** Lancez l'installation : `cd SAE501 && cat SETUP.md`