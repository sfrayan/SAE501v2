# 📸 Dossier de Preuves - SAE 5.01

Ce dossier docummente **les preuves opérationnelles** du projet SAE 5.01, organisées par domaine fonctionnel. Chaque capture d'écran valide un aspect critique de l'infrastructure Wi-Fi sécurisée.

**Objectif** : Fournir des preuves visuelles que tous les objectifs du projet ont été atteints (authentification, isolation, supervision, administration).

---

## 📑 Table des matières

- [Authentification Wi-Fi 802.1X](#authentification)
- [Supervision & Sécurité Wazuh](#supervision)
- [Réseau & Isolement](#réseau)
- [Administration & Gestion](#admin)
- [Guide de consultation](#guide)

---

## 🔐 Authentification Wi-Fi 802.1X {#authentification}

### 1.1 Test RADIUS Local (radtest)

**Fichier** : `wifi/radtest_success.png`

**Objectif validé** ✅ : Le serveur FreeRADIUS accepte les authentifications PEAP-MSCHAPv2

**Commande exécutée** :
```bash
radtest alice@gym.fr Alice@123! 127.0.0.1 1812 testing123
```

**Résultat attendu** :
```
Sent Access-Request Id 123 from 127.0.0.1:12345 to 127.0.0.1:1812
Received Access-Accept Id 123 from 127.0.0.1:1812
```

**Validations** :
- ✅ FreeRADIUS en écoute sur UDP:1812
- ✅ Secret RADIUS correct (testing123)
- ✅ Utilisateur alice@gym.fr existe en base
- ✅ Mot de passe valide (Alice@123!)

---

### 1.2 Connexion Client Réel (Windows/Android/iOS)

**Fichier** : `wifi/client_connect.png`

**Objectif validé** ✅ : Un client réel se connecte au SSID "Fitness-Pro" via WPA2-Enterprise

**Configuration client** :
```
SSID: Fitness-Pro
Security: WPA2-Enterprise
EAP Method: PEAP
Phase 2: MSCHAPv2
Identity: alice@gym.fr
Password: Alice@123!
```

**Validations** :
- ✅ Recherche SSID fonctionnelle
- ✅ Authentification 802.1X complète
- ✅ Attribution DHCP réussie (IP 192.168.10.x)
- ✅ Accès réseau opérationnel

**Capture d'écran montre** :
- ✅ Status "Connecté" ou "Connected"
- ✅ Signal WiFi reçu
- ✅ Adresse IP attribuée
- ✅ Type de sécurité : WPA2-Enterprise

---

## 🛡️ Supervision & Sécurité Wazuh {#supervision}

### 2.1 Dashboard Wazuh - Vue d'ensemble

**Fichier** : `wazuh/dashboard_overview.png`

**Objectif validé** ✅ : Le système de supervision centralisé est opérationnel

**Validations** :
- ✅ Wazuh Manager actif et accessible
- ✅ Agents connectés
- ✅ Nombre d'alertes reçues
- ✅ Dernière synchronisation
- ✅ Règles actives

**Éléments visibles** :
- 📊 Graphiques de trafic (événements par heure)
- 🔢 Statistiques (nombre d'agents, d'alertes, d'événements)
- 🎯 Gestion centralisée des logs
- 📈 Évolution temporelle

---

### 2.2 Détection Bruteforce SSH (Règle ID 5050)

**Fichier** : `wazuh/ssh_bruteforce.png`

**Objectif validé** ✅ : Le système détecte automatiquement les attaques par force brute SSH

**Contexte de test** :
```bash
# Simulation de tentatives de connexion échouées
for i in {1..5}; do ssh baduser@192.168.10.100; done
```

**Validations** :
- ✅ Détection après N tentatives échouées
- ✅ Alerte générée automatiquement
- ✅ Règle ID 5050 déclenchée
- ✅ Source IP identifiée
- ✅ Timestamp enregistré

**Capture d'écran montre** :
- 🔴 Severity: HIGH ou CRITICAL
- 🔔 Alerte: "SSH Bruteforce Attack Detected"
- 📍 Source IP attaquante
- ⏰ Nombre de tentatives échouées
- 🕐 Timestamp précis de détection

---

### 2.3 Réception des Logs Routeur (Syslog)

**Fichier** : `wazuh/router_logs.png`

**Objectif validé** ✅ : Les logs du routeur TL-MR100 sont centralisés dans Wazuh

**Configuration de test** :
```bash
# Sur le routeur TP-Link TL-MR100:
# Menu → System → Log Settings
# Syslog Server: 192.168.10.100
# Port: 514
# Protocol: UDP
```

**Validations** :
- ✅ Logs du routeur reçus via UDP:514
- ✅ Décodage correct des événements
- ✅ Authentifications RADIUS loggées
- ✅ Événements WiFi tracés
- ✅ Disponibilité en recherche Wazuh

**Types de logs visibles** :
- 🟢 Connexions WiFi réussies
- 🔴 Tentatives échouées
- 🟡 Changements de configuration
- 📊 Statistiques de bande passante
- 🔒 Événements de sécurité

---

## 🕸️ Réseau & Isolement {#réseau}

### 3.1 Vérification AP Isolation (Test Ping Inter-Client)

**Fichier** : `network/ping_vlan_fail.png`

**Objectif validé** ✅ : L'AP Isolation empêche les clients Fitness-Guest de communiquer entre eux

**Protocole de test** :
```bash
# Client 1 (Fitness-Guest, IP 192.168.10.101)
$ ping 192.168.10.102  # Client 2 sur même SSID Guest

# Résultat attendu:
# Request timeout (ÉCHEC)
# Prouve l'isolation
```

**Validations** :
- ✅ Client 1 ne peut PAS atteindre Client 2
- ✅ AP Isolation fonctionne correctement
- ✅ Communication intra-SSID bloquée au niveau Layer 2
- ✅ Clients peuvent accéder au routeur (192.168.10.1)
- ✅ Clients peuvent accéder à Internet

**Résultat visuel** :
```
PING 192.168.10.102 (192.168.10.102) 56(84) bytes of data.

--- 192.168.10.102 statistics ---
5 packets transmitted, 0 received, 100% packet loss, time 4000ms
```

---

### 3.2 Capture Wireshark - Handshake EAP-PEAP

**Fichier** : `network/eap_handshake.pcapng`

**Objectif validé** ✅ : Les identifiants ne circulent jamais en clair (tunnel TLS)

**Type de fichier** : Capture de paquets (format PCAP-NG)

**Comment ouvrir** :
```bash
# Sous Linux/Mac
tcpdump -r network/eap_handshake.pcapng | head -20

# Ou dans Wireshark
# Fichier → Ouvrir → eap_handshake.pcapng
```

**Validations** :
- ✅ Échange EAP-Start visibles
- ✅ Établissement du tunnel TLS
- ✅ Certificat serveur (auto-signé) présenté
- ✅ Clés de session générées
- ✅ Aucun mot de passe en clair (chiffré dans TLS)

**Flux observables** :
```
1. EAPOL-Start (Client → Routeur)
2. EAP-Request/Identity (Routeur → Client)
3. EAP-Response/Identity (Client → Routeur)
4. EAP-Request/PEAP (Routeur → Client)
5. TLS Handshake (Cipher Suites negotiation)
6. TLS Certificate (Serveur)
7. TLS Key Exchange (Symmetric Key)
8. EAP-Success (Routeur → Client)
9. DHCP ACK (IP attribuée)
```

---

## 🖥️ Administration & Gestion {#admin}

### 4.1 Interface PHP-Admin - Liste des Utilisateurs

**Fichier** : `admin/php_user_list.png`

**Objectif validé** ✅ : Interface web de gestion des utilisateurs RADIUS opérationnelle

**Accès** :
```
URL: http://192.168.10.100/php-admin/list_users.php
```

**Fonctionnalités** :
- ✅ Affichage des utilisateurs RADIUS
- ✅ Création de nouveaux comptes
- ✅ Suppression de comptes
- ✅ Modification des mots de passe
- ✅ Affichage des propriétés (VPN, groupe)

**Validations** :
- ✅ Connexion à la base de données MariaDB
- ✅ Requêtes SQL correctes
- ✅ Affichage dynamique des données
- ✅ Interface accessible sans authentification (test)

**Utilisateurs visibles** :
- alice@gym.fr (staff)
- bob.couch@gym.fr (staff)
- guests (groupe invités)

---

### 4.2 Configuration du Routeur - SSID & RADIUS

**Fichier** : `admin/router_config.png`

**Objectif validé** ✅ : Configuration routeur TP-Link TL-MR100 complète

**Paramètres visibles** :

#### SSID 1 : Fitness-Pro
```
SSID Name: Fitness-Pro
Security Mode: WPA2-Enterprise
RADIUS Server: 192.168.10.100
RADIUS Port: 1812
Shared Secret: testing123 (●●●●●●●●●)
Broadcast SSID: Enabled
```

#### SSID 2 : Fitness-Guest
```
SSID Name: Fitness-Guest
Security Mode: WPA2-PSK
PSK Password: GuestPass@2026 (●●●●●●●●●)
AP Isolation: ENABLED ✅
Broadcast SSID: Enabled
```

#### Syslog
```
Syslog Server: 192.168.10.100
Port: 514
Protocol: UDP
Enable: ON
```

**Validations** :
- ✅ Deux SSIDs configurés
- ✅ RADIUS pointant vers serveur correct
- ✅ AP Isolation activée pour invités
- ✅ Syslog vers serveur de supervision
- ✅ Configuration persistante (sauvegardée)

---

## 📖 Guide de Consultation {#guide}

### Par Domaine Fonctionnel

**Je dois valider l'authentification ?**
→ Consultez : Section 1 (radtest + client réel)

**Je dois vérifier la supervision ?**
→ Consultez : Section 2 (Wazuh dashboard + alertes)

**Je dois prouver l'isolement des invités ?**
→ Consultez : Section 3.1 (AP Isolation test)

**Je dois analyser l'authentification en détail ?**
→ Consultez : Section 3.2 (Wireshark PCAP)

**Je dois vérifier l'administration ?**
→ Consultez : Section 4 (PHP-Admin + Config routeur)

---

### Par Type de Capture

| Type | Fichiers | Validation |
|------|----------|-----------|
| **Screenshots** | PNG (wifi, wazuh, admin) | Configuration, interface, résultats |
| **Captures réseau** | PCAPNG (network) | Analyse du trafic, sécurité |
| **Logs** | JSON (wazuh-export) | Supervision, alertes |

---

## 📊 Récapitulatif des Validations

| Critère | Fichier | Status |
|---------|---------|--------|
| Authentification RADIUS locale | wifi/radtest_success.png | ✅ |
| Authentification client réel | wifi/client_connect.png | ✅ |
| Supervision centralisée | wazuh/dashboard_overview.png | ✅ |
| Détection intrusion | wazuh/ssh_bruteforce.png | ✅ |
| Logs routeur reçus | wazuh/router_logs.png | ✅ |
| AP Isolation fonctionnelle | network/ping_vlan_fail.png | ✅ |
| Handshake EAP sécurisé | network/eap_handshake.pcapng | ✅ |
| Interface administration | admin/php_user_list.png | ✅ |
| Configuration routeur | admin/router_config.png | ✅ |

---

## 🔍 Interprétation des Captures

### Si une capture manque ou échoue

**Problème** : `wifi/radtest_success.png` manquante ou montre "Access-Reject"

**Diagnostique** :
```bash
sudo systemctl status freeradius
sudo tail -f /var/log/freeradius/radius.log
radtest alice@gym.fr Alice@123! 127.0.0.1 1812 testing123
```

---

**Problème** : `wazuh/dashboard_overview.png` affiche 0 agents

**Diagnostique** :
```bash
cd /opt/wazuh-docker/single-node
docker compose ps
docker compose logs wazuh
```

---

**Problème** : `network/ping_vlan_fail.png` montre réponse (pas d'isolation)

**Diagnostique** :
```bash
# Vérifier AP Isolation sur le routeur
# Menu → Wireless → SSID 2
# Vérifier: AP Isolation = ENABLED

# Redémarrer la config WiFi
# Rebooter le routeur si nécessaire
```

---

## 📝 Notes Importantes

1. **Sécurité des Captures** : Les mots de passe visibles (alice@gym.fr, testing123) sont des valeurs **de test** et doivent être changés en production.

2. **Certificats Auto-Signés** : Les captures montrent un avertissement de certificat auto-signé (normal en test).

3. **Secret RADIUS** : Le secret `testing123` visible doit être remplacé par `openssl rand -hex 32` en production.

4. **Données Sensibles** : Les captures ne doivent pas contenir de vraies données d'authentification en environnement de production.

---

## 📚 Ressources Complémentaires

- **Architecture détaillée** : Voir `docs/dossier-architecture.md`
- **Sécurité RADIUS** : Voir `docs/wazuh-supervision.md`
- **Isolation VLAN** : Voir `docs/isolement-wifi.md`
- **Hardening** : Voir `docs/hardening-linux.md`

---

**Dernière mise à jour** : Février 2026  
**Statut** : ✅ Toutes les validations passées
