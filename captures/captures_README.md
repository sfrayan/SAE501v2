# 📸 Dossier de Preuves - SAE 5.01

Ce dossier contient les preuves de fonctionnement de l'infrastructure, organisées par thématique.

---

## 1. 📡 Authentification Wi-Fi (802.1X)

### Test `radtest` local
**Fichier :** `wifi/radtest_success.png`
> Description : Preuve que le serveur FreeRADIUS accepte les identifiants d'Alice.
> Commande : `radtest alice@gym.fr Alice@123! 127.0.0.1 1812 testing123`

![Radtest Success](wifi/radtest_success.png)

### Connexion Client Windows/Smartphone
**Fichier :** `wifi/client_connect.png`
> Description : Capture d'écran d'un smartphone connecté au SSID "Fitness-Pro" avec obtention d'adresse IP dans le VLAN 10.

![Client Connect](wifi/client_connect.png)

---

## 2. 🛡️ Surveillance & Sécurité (Wazuh)

### Dashboard Wazuh
**Fichier :** `wazuh/dashboard_overview.png`
> Description : Vue d'ensemble du manager Wazuh montrant les agents connectés.

![Dashboard](wazuh/dashboard_overview.png)

### Alerte Bruteforce SSH
**Fichier :** `wazuh/ssh_bruteforce.png`
> Description : Preuve de détection d'une attaque bruteforce (Règle ID 5050).

![SSH Bruteforce](wazuh/ssh_bruteforce.png)

### Alerte Logs Routeur (Syslog)
**Fichier :** `wazuh/router_logs.png`
> Description : Réception et décodage d'un log venant du TL-MR100.

![Router Logs](wazuh/router_logs.png)

---

## 3. 🕸️ Réseau & Isolement VLAN

### Test Ping Inter-VLAN (Échec attendu)
**Fichier :** `network/ping_vlan_fail.png`
> Description : Tentative de ping entre le VLAN Staff (10) et Guests (20). Le ping échoue, prouvant l'isolation.

![Ping Fail](network/ping_vlan_fail.png)

### Capture Wireshark (Handshake EAP)
**Fichier :** `network/eap_handshake.pcapng`
> Description : Capture des paquets montrant l'échange de certificats TLS lors de la connexion PEAP.
> [Télécharger le fichier PCAP](network/eap_handshake.pcapng)

---

## 4. 🖥️ Administration & Gestion

### Interface PHP-Admin
**Fichier :** `admin/php_user_list.png`
> Description : Interface web montrant la liste des utilisateurs créés en base de données.

![PHP Admin](admin/php_user_list.png)

### Configuration Routeur (VLANs)
**Fichier :** `admin/router_vlan_config.png`
> Description : Page de configuration du TL-MR100 montrant les 3 VLANs actifs.

![Router Config](admin/router_vlan_config.png)
