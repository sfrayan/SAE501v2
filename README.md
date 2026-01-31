# 🏋️ SAE 5.01 - Architecture Wi-Fi Sécurisée Entreprise

![Version](https://img.shields.io/badge/version-1.0-blue)
![Status](https://img.shields.io/badge/status-stable-green)
![License](https://img.shields.io/badge/license-MIT-green)
![Last Update](https://img.shields.io/badge/last%20update-2026--01--04-lightgrey)

**Projet académique SAE 5.01 - Déploiement infrastructure Wi-Fi 802.1X sécurisée avec FreeRADIUS, Wazuh et isolation VLAN.**

---

## 📋 Table des Matières

- [Vue d'ensemble](#vue-densemble)
- [Architecture](#architecture)
- [Prérequis](#prérequis)
- [Installation](#installation)
- [Configuration](#configuration)
- [Tests](#tests)
- [Documentation](#documentation)
- [Dépannage](#dépannage)
- [Équipe](#équipe)

---

## 🎯 Vue d'ensemble

Ce projet implémente une **infrastructure Wi-Fi Enterprise sécurisée** pour une salle de sport (scenario SAE 5.01):

### Fonctionnalités principales

✅ **Authentification Wi-Fi 802.1X**
- Protocole PEAP-MSCHAPv2 (Enterprise)
- Base de données MySQL/MariaDB
- Support multi-groupes (Staff, Guests, Managers)

✅ **Serveur RADIUS FreeRADIUS**
- Configuration clients NAS (routeur TL-MR100)
- Module SQL pour gestion utilisateurs
- Certificats TLS auto-signés
- Support authentification par groupes

✅ **Isolation VLAN par rôle**
- VLAN 10: Staff (192.168.10.0/24)
- VLAN 20: Guests (192.168.20.0/24)
- VLAN 30: Managers (192.168.30.0/24)
- Segmentation réseau automatique par groupe

✅ **Surveillance Sécurité (Wazuh)**
- Détection intrusions & bruteforce
- Monitoring FreeRADIUS en temps réel
- Collecte logs routeur TL-MR100 (syslog)
- Alertes incidents sécurité

✅ **Interface d'Administration (PHP-Admin)**
- Gestion utilisateurs RADIUS
- Interface web intuitive
- Création/modification/suppression utilisateurs
- Consultation groupes

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   RÉSEAU INFRASTRUCTURE                      │
└─────────────────────────────────────────────────────────────┘

                         Internet
                            ↓
                    ┌───────────────┐
                    │  TL-MR100     │ WiFi Router
                    │  (Gateway)    │ - 3 SSIDs (PEAP 802.1X)
                    │ 192.168.10.1  │ - 3 VLANs (10, 20, 30)
                    └───────┬───────┘
                            │
        ┌───────────────────┼───────────────────┐
        ↓                   ↓                   ↓
    ┌────────────┐   ┌────────────┐   ┌────────────┐
    │ VLAN 10    │   │ VLAN 20    │   │ VLAN 30    │
    │ Staff      │   │ Guests     │   │ Managers   │
    │ 192.168.10 │   │ 192.168.20 │   │ 192.168.30 │
    └────────────┘   └────────────┘   └────────────┘
            ↓               ↓               ↓
            └───────────────┼───────────────┘
                            │
                ┌───────────┴───────────┐
                ↓                       ↓
        ┌──────────────────┐   ┌──────────────────┐
        │ FreeRADIUS       │   │ MySQL/MariaDB    │
        │ (Port 1812 UDP)  │   │ (Port 3306 TCP)  │
        │ PEAP-MSCHAPv2    │←→ │ Base: radius     │
        │ 192.168.10.254   │   │ User: radius_app │
        └──────────────────┘   └──────────────────┘
                ↓                       ↑
                └───────────────────────┘
            Authentification & Assignation VLAN

        ┌──────────────────┐
        │ Wazuh Manager    │← Syslog (514 UDP)
        │ (Surveillance)   │← Logs FreeRADIUS
        │ 192.168.10.254   │← Logs systèmes
        └──────────────────┘

        ┌──────────────────┐
        │ PHP-Admin        │← Web (Apache/PHP)
        │ (Gestion Users)  │   Port 80/443
        │ 192.168.10.254   │
        └──────────────────┘
```

### Flux d'authentification

```
1. Client WiFi
        ↓
2. Scanne SSID Fitness-Pro (PEAP 802.1X)
        ↓
3. Envoie credentials: alice@gym.fr / Alice@123!
        ↓
4. TL-MR100 → FreeRADIUS (port 1812 UDP)
        ↓
5. FreeRADIUS → MySQL: Cherche alice@gym.fr
        ↓
6. FreeRADIUS → MySQL: Vérifie password
        ↓
7. FreeRADIUS → MySQL: Cherche groupe (staff)
        ↓
8. FreeRADIUS → MySQL: Cherche Tunnel-Private-Group-ID (VLAN 10)
        ↓
9. FreeRADIUS → TL-MR100: Access-Accept + VLAN 10
        ↓
10. TL-MR100: Assigne IP 192.168.10.x (DHCP VLAN 10)
        ↓
11. Client: Connecté au VLAN 10 avec accès complet
        ↓
12. Wazuh: Log authentification réussie
```

---

## 📦 Prérequis

### Matériel
- Serveur Linux: Debian 11+ ou Ubuntu 20.04+
- RAM: 4GB minimum
- Disque: 20GB minimum
- Routeur: TP-Link TL-MR100

### Logiciels
- **FreeRADIUS 3.x** avec module SQL
- **MySQL 5.7+ ou MariaDB 10.3+**
- **Wazuh Manager 4.x** (optionnel mais recommandé)
- **Apache 2.4** + PHP 7.4+ (pour PHP-Admin)
- **Git** pour versioning

### Accès réseau
- Port 1812-1813 UDP (RADIUS)
- Port 3306 TCP (MySQL)
- Port 514 UDP (Syslog)
- Port 80/443 TCP (Web Admin)

---

## ⚡ Installation Rapide

### 1️⃣ Cloner le repository

```bash
git clone https://gitlab.sorbonne-paris-nord.fr/11915801/sae501-2026-groupenani.git
cd sae501-2026-groupenani
```

### 2️⃣ Installation FreeRADIUS (5-10 min)

```bash
# Installation automatisée
sudo bash scripts/install_radius.sh

# Ou manuel (étapes complètes dans radius/README.md)
sudo mysql -u root -p < radius/sql/init_appuser.sql
sudo mysql -u root -p radius < radius/sql/create_tables.sql
sudo cp radius/clients.conf /etc/freeradius/3.0/
sudo cp radius/users.txt /etc/freeradius/3.0/
sudo systemctl restart freeradius
```

### 3️⃣ Installation Wazuh (5-10 min)

```bash
# Installation automatisée
sudo bash scripts/install_wazuh.sh

# Ou manuel
# Ajouter repository Wazuh + installer
# Configurer règles personnalisées
# Redémarrer Wazuh
```

### 4️⃣ Configuration PHP-Admin

```bash
# Copier vers web root
sudo cp -r php-admin /var/www/html/

# Permissions
sudo chown -R www-data:www-data /var/www/html/php-admin
sudo chmod 755 /var/www/html/php-admin

# Accès: http://192.168.10.254/php-admin/
```

### 5️⃣ Diagnostic système

```bash
bash scripts/diagnostics.sh
```

---

## 🔧 Configuration

### Configuration Routeur TL-MR100

```
1. Admin Web: https://192.168.10.1
   User: admin / Password: admin
   
2. Network → VLAN
   - Activer VLAN support
   - VLAN 10: Staff (WiFi SSID: Fitness-Pro)
   - VLAN 20: Guests (WiFi SSID: Fitness-Guest)
   - VLAN 30: Managers (WiFi SSID: Fitness-Corp)
   
3. WiFi → Security → RADIUS
   Server IP: 192.168.10.254
   Port: 1812
   Secret: Pj8K2qL9xR5wM3nP7dF4vB6tH1sQ9cZ2
   
4. System → Logs → Syslog
   Server IP: 192.168.10.254
   Port: 514
   Enable: Yes
   
5. Reboot routeur
```

### Utilisateurs de Test

| Email | Password | Groupe | VLAN |
|-------|----------|--------|------|
| alice@gym.fr | Alice@123! | staff | 10 |
| bob@gym.fr | Bob@456! | staff | 10 |
| charlie@gym.fr | Charlie@789! | guests | 20 |
| david@gym.fr | David@2026! | managers | 30 |
| emma@gym.fr | Emma@2026! | staff | 10 |

---

## 🧪 Tests

### Test Authentification PEAP

```bash
# Test Cleartext (radtest)
sudo bash tests/test_peap.sh alice@gym.fr Alice@123! 127.0.0.1

# Test avec client WiFi réel
# Connecter client à SSID Fitness-Pro
# Entrer alice@gym.fr / Alice@123!
# Vérifier: IP 192.168.10.x obtenue
```

### Test Isolement VLAN

```bash
# Test isolement inter-VLAN
sudo bash tests/test_isolement.sh 192.168.10.1

# Vérifications:
# - Client Staff (VLAN 10) ↔ Client Guest (VLAN 20): BLOQUÉ
# - Client Staff (VLAN 10) ↔ Gateway 192.168.10.1: OK
# - AP Isolation activée: Clients même SSID ne se voient pas
```

### Test Surveillance Wazuh

```bash
# Test réception logs TL-MR100
sudo bash tests/test_syslog_mr100.sh 192.168.10.1

# Vérifications:
# - Logs syslog reçus sur port 514
# - Règles personnalisées chargées
# - Alertes WiFi générées
# - Détection bruteforce active
```

---

## 📚 Documentation

### Fichiers de configuration

| Fichier | Description |
|---------|-------------|
| **radius/clients.conf** | Configuration clients NAS (routeurs) |
| **radius/users.txt** | Utilisateurs test (format FreeRADIUS) |
| **radius/sql/init_appuser.sql** | Création utilisateur MySQL |
| **radius/sql/create_tables.sql** | Schéma base de données RADIUS |
| **wazuh/manager.conf** | Configuration Wazuh Manager |
| **wazuh/local_rules.xml** | Règles personnalisées SAE 5.01 |
| **wazuh/syslog-tlmr100.conf** | Décodeurs logs TL-MR100 |
| **php-admin/config.php** | Configuration PHP-Admin |

### Scripts utiles

| Script | Description |
|--------|-------------|
| **scripts/install_radius.sh** | Installation FreeRADIUS automatisée |
| **scripts/install_wazuh.sh** | Installation Wazuh automatisée |
| **scripts/diagnostics.sh** | Diagnostic système complet |
| **tests/test_peap.sh** | Test authentification PEAP |
| **tests/test_isolement.sh** | Test isolement VLAN |
| **tests/test_syslog_mr100.sh** | Test réception logs Wazuh |

---

## 🐛 Dépannage

### FreeRADIUS

**Problème: Service FreeRADIUS n'a pas démarré**
```bash
# Vérifier syntaxe
sudo freeradius -XC

# Voir erreurs détaillées
sudo systemctl status freeradius
sudo journalctl -u freeradius -n 50
```

**Problème: Access-Reject après authentification**
```bash
# Vérifier utilisateur en base
mysql -u radius_app -p radius
SELECT * FROM radcheck WHERE username='alice@gym.fr';

# Tester radtest
radtest alice@gym.fr Alice@123! 127.0.0.1 1812 testing123
```

**Problème: Port 1812 UDP n'écoute pas**
```bash
# Vérifier écoute
sudo netstat -un | grep 1812

# Vérifier firewall UFW
sudo ufw allow 1812/udp
sudo ufw allow 1813/udp
```

### Wazuh

**Problème: Logs TL-MR100 non reçus**
```bash
# Vérifier réception syslog
sudo tail -f /var/log/syslog | grep TL-MR100

# Vérifier configuration rsyslog
cat /etc/rsyslog.d/10-wazuh.conf

# Redémarrer rsyslog
sudo systemctl restart rsyslog
```

**Problème: Wazuh ne démarre pas**
```bash
# Vérifier syntaxe config
/var/ossec/bin/wazuh-control verify-configuration

# Voir erreurs
sudo tail -f /var/ossec/logs/ossec.log
```

### Wi-Fi / Routeur TL-MR100

**Problème: Authentification Wi-Fi échoue**
```bash
# Vérifier secret RADIUS identique
# TL-MR100 Admin: System → RADIUS → Secret
# Serveur: /etc/freeradius/3.0/clients.conf

# Vérifier certificats
openssl x509 -in /etc/freeradius/3.0/certs/server.pem -text -noout
```

**Problème: VLAN mal configuré (client reçoit IP 192.168.1.x au lieu de 192.168.10.x)**
```bash
# Vérifier assignation VLAN en base
mysql -u radius_app -p radius
SELECT * FROM radreply WHERE attribute='Tunnel-Private-Group-ID';

# Vérifier réponse RADIUS
radtest -x alice@gym.fr Alice@123! 127.0.0.1 1812 testing123
```

---

## 📊 Architecture fichiers

```
sae501-2026-groupenani/
├── README.md (ce fichier)
├── .gitignore
│
├── radius/
│   ├── clients.conf                    # Config clients NAS
│   ├── users                           # Utilisateurs test
│   └── sql/
│       ├── init_appuser.sql            # Création user MySQL
│       └── create_tables.sql           # Schéma BD RADIUS
│
├── wazuh/
│   ├── manager.conf                    # Config Wazuh Manager
│   ├── local_rules.xml                 # Règles personnalisées
│   └── syslog-tlmr100.conf            # Décodeurs TL-MR100
│
├── php-admin/
│   ├── config.php                      # Configuration
│   ├── index.php                       # Page d'accueil
│   ├── add_user.php                    # Ajouter utilisateur
│   ├── list_users.php                  # Lister utilisateurs
│   └── delete_user.php                 # Supprimer utilisateur
│
├── scripts/
│   ├── install_radius.sh               # Installation FreeRADIUS
│   ├── install_wazuh.sh                # Installation Wazuh
│   └── diagnostics.sh                  # Diagnostic système
│
└── tests/
    ├── test_peap.sh                    # Test PEAP-MSCHAPv2
    ├── test_isolement.sh               # Test isolement VLAN
    └── test_syslog_mr100.sh            # Test logs Wazuh
```

---

## 🔐 Sécurité - Checklist

- [ ] Secret RADIUS ≥ 32 caractères (actuellement: 32)
- [ ] Certificats générés et valides
- [ ] MySQL: Utilisateur radius_app avec password fort
- [ ] Permissions fichiers: 640 (clients.conf, users)
- [ ] Ports fermés par défaut (UFW)
- [ ] Port 1812-1813 UDP: Ouvert au routeur TL-MR100 SEULEMENT
- [ ] SSH: Désactiver root login
- [ ] Wazuh: Monitoring actif pour alertes critiques
- [ ] Backups BD RADIUS réguliers
- [ ] Logs: Archivage en /var/log avec rotation

**En production:**
- [ ] Certificats signés par CA (pas auto-signés)
- [ ] MySQL: Backups quotidiens chiffré
- [ ] Wazuh: Intégration SIEM (Splunk/ELK)
- [ ] VPN pour administration distante
- [ ] Audit complet: qui, quand, quoi

---

## 📞 Support & Contribution

### Signaler un bug

```bash
# Générer diagnostic complet
bash scripts/diagnostics.sh

# Joindre le rapport:
# /tmp/diag_YYYYMMDD_HHMMSS.log
```

### Contribuer

1. Fork le repository
2. Créer une branche feature (`git checkout -b feature/AmazingFeature`)
3. Commit changes (`git commit -m 'feat(module): Add AmazingFeature'`)
4. Push to branch (`git push origin feature/AmazingFeature`)
5. Ouvrir une Pull Request

---

## 👥 Équipe

**GroupeNani** - SAE 5.01 (Janvier 2026)

- **Rayan** - Lead Infrastructure (FreeRADIUS, RADIUS)
- **Supapriyan** - Lead Sécurité (Wazuh, monitoring)
- **Hamza** - Lead Web (PHP-Admin, interface)

**Encadrants:**
- Professeur Infrastructure Réseau

---

## 📄 Licence

Ce projet est sous licence **MIT** - voir le fichier `LICENSE` pour les détails.

```
Copyright (c) 2026 GroupeNani

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
```

---

## 🔗 Ressources Utiles

- [FreeRADIUS Official](https://freeradius.org/)
- [Wazuh Documentation](https://documentation.wazuh.com/)
- [IEEE 802.1X Standard](https://en.wikipedia.org/wiki/IEEE_802.1X)
- [PEAP Protocol](https://en.wikipedia.org/wiki/Protected_Extensible_Authentication_Protocol)
- [VLAN Basics](https://en.wikipedia.org/wiki/Virtual_LAN)

---

## 📝 Changelog

### v1.0 (2026-01-04)
- ✅ Installation FreeRADIUS automatisée
- ✅ Configuration Wazuh Manager
- ✅ Interface PHP-Admin complète
- ✅ Isolation VLAN par groupe
- ✅ Collecte logs syslog TL-MR100
- ✅ Suite de tests complète
- ✅ Documentation complète

---

**Dernière mise à jour:** 4 janvier 2026 - 13:00 CET

**Questions?** Consulter la [FAQ](docs/FAQ.md) ou contacter rayan.saidfarah@edu.univ-paris13.fr
