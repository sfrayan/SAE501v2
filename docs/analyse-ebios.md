# Analyse de risques — EBIOS ANSSI (Simplifiée)

## 1. Contexte

Le projet SAE 5.01 met en place une infrastructure Wi-Fi centralisée et sécurisée pour une chaîne de salles de sport multi-sites. Cette analyse couvre les risques relatifs à :

- **Serveur central Linux** : FreeRADIUS, Wazuh, MariaDB (192.168.10.254)
- **Routeur TL-MR100** : Point d'accès Wi-Fi + accès Internet 4G
- **Wi-Fi Entreprise** : Authentification PEAP-MSCHAPv2
- **Wi-Fi Invités** : Réseau isolé
- **Infrastructure Réseau** : Segmentation VLAN, Firewall, Journalisation

---

## 2. Actifs essentiels

| Actif | Description | Criticité | Justification |
| :--- | :--- | :--- | :--- |
| **Identifiants RADIUS** | Comptes utilisateurs (personnel + staff) | ⭐⭐⭐ Élevée | Compromission = usurpation d'identité et accès non-autorisé au SI |
| **Serveur Linux Central** | FreeRADIUS, MariaDB, Wazuh, Interface PHP | ⭐⭐⭐ Élevée | Point névralgique : authentification, stockage données, supervision |
| **Base de données SQL** | Stockage des mots de passe, logs de connexion | ⭐⭐⭐ Élevée | Vol de données sensibles, usurpation d'identité |
| **Certificat Serveur RADIUS** | Clé privée + certificat (pour tunnel TLS) | ⭐⭐⭐ Élevée | Compromission = MITM possible sur authentifications |
| **Service RADIUS** | Processus FreeRADIUS | ⭐⭐⭐ Élevée | Indisponibilité = perte d'accès Wi-Fi Entreprise |
| **Routeur TL-MR100** | Point d'accès Wi-Fi et passerelle Internet | ⭐⭐⭐ Élevée | Compromission = accès au LAN et manipulation du trafic |
| **Logs Wazuh** | Journaux de sécurité et d'audit | ⭐⭐ Moyenne | Perte de traçabilité (légal) et capacité d'investigation post-incident |
| **Connexion Internet** | Liaison 4G/Fibre vers serveur central | ⭐⭐⭐ Élevée | Indisponibilité = perte d'authentification et supervision |
| **VLAN Invités** | Réseau Wi-Fi isolé (192.168.20.0/24) | ⭐⭐ Moyenne | Compromission = potentiel accès au SI (si isolation défaillante) |

---

## 3. Sources de menaces

### Menaces Externes

- **Attaquant via Wi-Fi Invité** : Tente d'accéder au réseau Entreprise ou au serveur.
- **Attaquant via Internet** : Tentative d'accès au serveur depuis l'extérieur (brute force, exploitation de vuln).
- **Intercepteur de trafic** : Écoute le lien WAN (4G) non chiffré.
- **Usurpateur d'identité** : Vol de credentials sur le Wi-Fi Invité ou par autre moyen.

### Menaces Internes

- **Utilisateur malveillant** : Staff compromis, ancien employé, administrateur malintentionné.
- **Erreur d'administration** : Misconfiguration (pare-feu ouvert, service vulnérable activé).
- **Incident physique** : Accès non-autorisé au serveur, au routeur (reset, remplacement).

### Menaces Techniques

- **Défaut de configuration** : Isolation VLAN mal configurée, secret RADIUS faible.
- **Absence de supervision** : Attaque non détectée car pas de monitoring actif.
- **Défaut de mise à jour** : Firmware/OS vulnérable du routeur ou serveur.

---

## 4. Scénarios de menace

### Scénario 1 : Brute Force sur RADIUS

**Description :** Un attaquant externe tente de deviner les mots de passe Wi-Fi Entreprise en envoyant des milliers de requêtes RADIUS.

| Point | Détail |
| :--- | :--- |
| **Vecteur d'attaque** | UDP 1812 depuis Internet vers le serveur (si pare-feu UFW non configuré) |
| **Impact** | Accès non-autorisé à un compte staff, usurpation d'identité |
| **Probabilité** | Moyenne (à moins que UFW soit bien configuré) |
| **Mesures** | ✓ UFW : Allow RADIUS seulement depuis IP clients autorisées<br>✓ Limite de tentatives MariaDB (compte lockout après 3 essais)<br>✓ Fail2ban sur le serveur<br>✓ Monitoring Wazuh des tentatives |
| **Résidu** | Très faible si mesures appliquées |

---

### Scénario 2 : Injection SQL via l'Interface PHP

**Description :** Un attaquant accède à l'interface Web d'administration et injecte du code SQL pour exfiltrer tous les mots de passe.

| Point | Détail |
| :--- | :--- |
| **Vecteur d'attaque** | Formulaire "Ajouter Utilisateur" → `' OR '1'='1` |
| **Impact** | Vol de tous les identifiants, compromission complète |
| **Probabilité** | Élevée (si prepared statements absent) |
| **Mesures** | ✓ Prepared Statements (PDO) obligatoires<br>✓ Validation & échappement des entrées<br>✓ Restriction accès Web (IP whitelist ou VPN)<br>✓ Logs Wazuh des requêtes suspectes |
| **Résidu** | Très faible si PDO utilisé correctement |

---

### Scénario 3 : Contournement de l'Isolation VLAN Invité

**Description :** Un client invité exploite une faille de l'isolation Guest Network du TL-MR100 pour accéder au réseau Entreprise (192.168.10.x) et faire du scan de ports vers le serveur.

| Point | Détail |
| :--- | :--- |
| **Vecteur d'attaque** | ARP Spoofing, malformation de trames pour bypasserClient Isolation |
| **Impact** | Accès au serveur central, reconnaissance de services, tentative d'exploitation |
| **Probabilité** | Faible à Moyenne (dépend firmware TL-MR100) |
| **Mesures** | ✓ Vérification régulière isolation (tcpdump, ping test)<br>✓ UFW strict sur serveur (refuse tout trafic depuis 192.168.20.x)<br>✓ Monitoring tcpdump de tentatives anormales<br>✓ Segmentation réseau physique (switch managé si possible) |
| **Résidu** | Faible (double pare-feu + tests réguliers) |

---

### Scénario 4 : Vol de Certificat Serveur RADIUS

**Description :** Un attaquant obtient accès à `/etc/freeradius/3.0/certs/server.key` et crée un serveur RADIUS malveillant (Evil Twin RADIUS) pour capturer les mots de passe.

| Point | Détail |
| :--- | :--- |
| **Vecteur d'attaque** | Compromission du serveur (SSH, exploit) ou accès physique |
| **Impact** | Capacité à capturer tous les identifiants Wi-Fi Entreprise |
| **Probabilité** | Faible (requiert compromission du serveur entier) |
| **Mesures** | ✓ Permissions strictes (chmod 600 sur clés privées)<br>✓ Ownership reroot/freerad uniquement<br>✓ Audit SELinux/AppArmor si déployé<br>✓ Sauvegarde chiffrée de la clé<br>✓ Alertes Wazuh sur accès aux fichiers sensibles |
| **Résidu** | Très faible si hardening appliqué |

---

### Scénario 5 : Indisponibilité du Serveur Central

**Description :** Le serveur Linux tombe en panne (disque plein, crash, attaque DoS) → Plus aucune authentification RADIUS possible → Perte complète du Wi-Fi Entreprise.

| Point | Détail |
| :--- | :--- |
| **Vecteur d'attaque** | Panne matérielle, attaque DoS ICMP/UDP flood, perte connexion WAN |
| **Impact** | Indisponibilité complète de l'authentification ; Wi-Fi Invité seul reste opérationnel |
| **Probabilité** | Moyenne (Internet 4G pas très fiable) |
| **Mesures** | ✓ Redondance serveur RADIUS (replica secondaire si possible)<br>✓ Watchdog/Monitoring scripts de disponibilité<br>✓ Cache locale sur TL-MR100 (non supporté par MR100)<br>✓ Documentation procédure failover<br>✓ UFW limite les DoS (rate limiting) |
| **Résidu** | Moyen (Single Point of Failure dans cette archi) |

---

## 5. Mesures de sécurité retenues

| Mesure | Domaine | Implémentation |
| :--- | :--- | :--- |
| **PEAP-MSCHAPv2** | Authentification | Tunnel TLS + hash MSCHAPv2 chiffré (vs mot de passe en clair) |
| **Prepared Statements (PDO)** | Application | Protection contre injection SQL dans interface PHP |
| **UFW - Pare-feu** | Réseau | Whitelist stricte des ports (1812/UDP, 80, 443, 514/UDP, SSH 22) |
| **SSH Clé + No Root** | Accès Admin | Élimination brute force et escalade rapide |
| **Permissions Strictes** | Fichiers | chmod 600 sur /etc/freeradius/3.0/certs, propriétaires root/freerad |
| **Wazuh Manager** | Supervision | Analyse corrélation logs, détection d'anomalies (tentatives auth échouées, scans) |
| **Syslog Centralisé** | Journalisation | Logs routeur + serveur consolidés → traçabilité et audit |
| **Isolation VLAN** | Segmentation | VLAN 20 invités isolé du VLAN 10 entreprise par pare-feu routeur |
| **MariaDB Dédié** | Base de Données | Utilisateur `radius_user` restreint (select/insert/update/delete seulement) |
| **Tests Réguliers** | Validation | tcpdump/nmap/ping pour vérifier isolation + Fail2ban simulations |

---

## 6. Conclusion

### Risque Résiduel Global

L'architecture mise en place offre un niveau de sécurité **acceptable pour un context PME/étudiant**, à condition que toutes les mesures soient appliquées.

### Forces de cette Architecture

- ✅ Authentification centralisée (plus de clés partagées statiques).
- ✅ Chiffrement des identifiants (tunnel TLS PEAP).
- ✅ Séparation strict invités/entreprise (pare-feu + VLAN).
- ✅ Supervision et détection d'attaques (Wazuh).
- ✅ Coût de déploiement très bas (open source).

### Faiblesses et Points d'Amélioration

- ⚠️ Single Point of Failure : Serveur central (pas de redondance).
- ⚠️ Certificat auto-signé (avertissement utilisateurs).
- ⚠️ Logs Syslog non chiffrés (recommandation : VPN/TLS wrapping).
- ⚠️ Dépendance à l'isolation matérielle du TL-MR100 (firmware propriétaire).

### Recommandations pour Production

1. **Haute Disponibilité :** Déployer un réplica RADIUS/MariaDB secondaire en standby actif.
2. **PKI :** Utiliser un certificat émis par une autorité reconnue (ex: Let's Encrypt pour le web).
3. **Tunneling :** Chiffrer le trafic Syslog et RADIUS entre sites via IPsec ou OpenVPN.
4. **Tests Réguliers :** Audit de pénétration semestriel sur l'isolation VLAN et les services.
5. **Monitoring Avancé :** Ajouter des alertes Wazuh pour détection intrusion (IDS).

---

**Document rédigé par :** GroupeNani  
**Date :** 4 janvier 2026  
**Version :** 1.0
