# Dossier d'architecture

## 1. Contexte et objectifs

Le projet s'inscrit dans le cadre de la modernisation de l'infrastructure réseau de la chaîne de salles de sport **"Fitness Plus"**. L'objectif principal est de passer d'une gestion artisanale et disparate à une **architecture centralisée, sécurisée et supervisée**.

Les objectifs spécifiques sont :
- **Homogénéisation Multi-sites :** Déployer une configuration standardisée sur tous les sites, gérée depuis un point central.
- **Sécurisation du Wi-Fi :** Remplacer les clés partagées (PSK) statiques par une authentification **WPA2-Enterprise (802.1X)** pour le personnel.
- **Isolation des Invités :** Fournir un accès Internet aux clients via un réseau strictement isolé (AP Isolation).
- **Centralisation :** Héberger les services critiques (FreeRADIUS, MariaDB, Wazuh) sur un serveur Linux unique durci.

## 2. Périmètre technique

- **SSID « Entreprise » (WPA2-Enterprise) :** Sécurisé par **PEAP-MSCHAPv2** (Login/Mdp dans tunnel TLS).
- **SSID « Invités » (Isolé) :** Réseau avec WPA2-PSK et AP Isolation (Client Isolation) activée.
- **Supervision Wazuh :** Centralisation des logs (Syslog routeur + Logs RADIUS) et détection d'intrusions.
- **Durcissement Linux :** Application des recommandations ANSSI (SSH clés, UFW, permissions).
- **Gestion centralisée des comptes RADIUS :** Interface PHP + MariaDB pour l'administration.

## 3. Topologie et adressage

### Schéma d'Architecture

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
              │  - Auth RADIUS                │
              │  - Réseau: 192.168.10.0/24     │
              │                                │
              │  SSID: Fitness-Guest          │
              │  - WPA2-PSK                   │
              │  - AP Isolation activée       │
              │  - Réseau: 192.168.10.0/24     │
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
          │  - Gateway: 192.168.10.1          │
          │  - Communication avec routeur     │
          │                                    │
          │  eth1 (NAT): 10.0.2.15           │
          │  - Gateway: 10.0.2.2              │
          │  - Internet pour apt-get          │
          │                                    │
          │  Services:                        │
          │  - FreeRADIUS: 1812/UDP           │
          │  - MySQL: 3306/TCP (local only)   │
          │  - Apache/PHP: 80/TCP             │
          │  - Wazuh: 1514/UDP                │
          │  - rsyslog: 514/UDP               │
          └───────────────────────────────────┘
```

### Plan d'adressage

| Zone | Équipement | Interface | Adresse IP | Masque | Rôle |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Serveur** | VM Debian 11 | `eth0` (Bridge) | `192.168.10.100` | `/24` | Services centraux |
| **Serveur** | VM Debian 11 | `eth1` (NAT) | `10.0.2.15` | `/24` | Internet (apt-get) |
| **Salle** | Routeur MR100 | `LAN` | `192.168.10.1` | `/24` | Passerelle par défaut |
| **Salle** | Clients Staff | `WiFi` | `192.168.10.101-254` | `/24` | DHCP - Fitness-Pro |
| **Salle** | Clients Guests | `WiFi` | `192.168.10.101-254` | `/24` | DHCP - Fitness-Guest |

**Note importante** : Les deux SSIDs partagent le même subnet (192.168.10.0/24). L'isolation des invités est assurée par l'**AP Isolation** au niveau du routeur, qui empêche les clients Fitness-Guest de communiquer entre eux.

## 4. Chaîne d'authentification EAP (PEAP-MSCHAPv2)

L'authentification assure que les identifiants ne circulent jamais en clair.

### Flux d'authentification

```
1. Client WiFi → Routeur (192.168.10.1)
   - Requête EAPOL-Start
   - Identity: alice@gym.fr

2. Routeur → Serveur RADIUS (192.168.10.100:1812)
   - RADIUS Access-Request
   - Paquet UDP chiffré avec secret partagé

3. FreeRADIUS → MySQL (127.0.0.1:3306)
   - SELECT * FROM radcheck WHERE username='alice@gym.fr'
   - Vérification hash mot de passe

4. FreeRADIUS → Routeur
   - RADIUS Access-Accept (avec clés WPA)
   - OU Access-Reject

5. Routeur → Client
   - EAP-Success + attribution IP DHCP
   - Client connecté au réseau
```

## 5. Analyse du routeur TL-MR100

### Fonctionnalités d'isolation

- **AP Isolation (Client Isolation) :**
  - Activée sur le SSID Fitness-Guest
  - Empêche la communication de niveau 2 entre clients WiFi
  - Les clients Guest ne peuvent pas se voir mutuellement
  - Les clients Guest peuvent accéder au routeur (192.168.10.1) et Internet

### Limites et contraintes

- **Pas de VLAN Tagging** : Le routeur TL-MR100 ne supporte pas les VLANs 802.1Q
- **Même subnet** : Les deux SSIDs partagent 192.168.10.0/24
- **Syslog non chiffré** : Logs transmis en clair UDP (risque d'interception)
- **Pare-feu basique** : Pas de règles DPI ou stateful avancées

### Impacts sur l'architecture

- **Sécurité par isolation WiFi** : L'AP Isolation remplace la séparation VLAN
- **Durcissement serveur critique** : UFW doit compenser la faiblesse du routeur
- **Tests réguliers** : Validation périodique de l'isolation avec nmap/tcpdump

## 6. Architecture multi-sites (perspective future)

- **Identification des sites :** Utilisation du fichier `clients.conf` pour déclarer chaque routeur comme un client NAS unique (`client site_bordeaux { ipaddr=... secret=... }`).
- **Adressage unique :** Chaque futur site devra utiliser un sous-réseau LAN différent (ex: Site 2 en 192.168.11.0/24) pour éviter les conflits de routage VPN.
- **Base unique :** Les utilisateurs sont stockés une seule fois dans MariaDB et peuvent se connecter sur n'importe quel site (Roaming).

## 7. Choix de sécurité

### Authentification

- **PEAP-MSCHAPv2 :** Choisi pour sa compatibilité native avec Windows/Android/iOS sans nécessiter de déploiement de certificats clients (PKI lourde).
- **Certificat serveur auto-signé :** Avertissement de sécurité sur les postes clients à la première connexion (acceptable pour environnement de test).

### Isolation

- **AP Isolation** : Remplacement de la séparation VLAN traditionnelle
- **Avantages** :
  - Simple à configurer
  - Pas besoin de switch managé
  - Efficace pour petits déploiements
- **Inconvénients** :
  - Moins robuste qu'une séparation VLAN
  - Dépend du routeur
  - Même subnet pour tous

### Durcissement

- **SSH par clé uniquement** : Suppression des mots de passe pour l'administration serveur
- **UFW restrictif** : Seulement les ports essentiels ouverts
- **MySQL local** : Accessible uniquement via 127.0.0.1 (pas d'exposition réseau)
- **Wazuh** : Détection d'intrusion et alertes en temps réel

## 8. Points de vigilance et limitations

### Sécurité

- **Certificat Auto-signé :** Avertissement de sécurité sur les postes clients à la première connexion
- **Logs non chiffrés :** Le Syslog UDP transite en clair sur le réseau local
- **Secret RADIUS partagé :** Doit être changé en production (utiliser `openssl rand -hex 32`)

### Architecture

- **Pas de VLAN** : Séparation assurée uniquement par AP Isolation
- **Même subnet** : Clients Staff et Guest sur 192.168.10.0/24
- **SPOF (Single Point of Failure)** : Si le serveur RADIUS tombe, plus d'authentification Fitness-Pro
- **Dépendance Internet** : Si le lien WAN coupe, l'accès Fitness-Guest peut être impacté

### Tests critiques à réaliser

1. **AP Isolation** : Vérifier qu'un client Guest ne peut pas ping un autre client Guest
2. **Accès routeur** : Vérifier que les clients peuvent accéder à 192.168.10.1 (gateway)
3. **Authétection RADIUS** : Tester avec radtest + clients WiFi réels
4. **Logs Wazuh** : Vérifier la réception des authentifications

## 9. Améliorations futures

### Court terme

- Installer un certificat Let's Encrypt pour HTTPS (PHP-Admin)
- Implémenter rotation automatique des logs
- Ajouter monitoring Nagios/Prometheus

### Long terme

- Migrer vers switch managé avec VLAN 802.1Q
- Déployer une PKI interne pour certificats clients
- Implémenter authentification multi-facteurs (TOTP)
- Clustering FreeRADIUS pour haute disponibilité

## 10. Conformité et normes

- **ANSSI** : Application du guide de durcissement Linux
- **802.1X** : Standard IEEE pour authentification réseau
- **RADIUS** : RFC 2865, 2866 (Authentification et Accounting)
- **PEAP** : RFC 5281 (Protected EAP)
- **RGPD** : Logs d'authentification conservés selon durée légale
