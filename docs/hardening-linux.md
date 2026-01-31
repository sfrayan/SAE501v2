# Durcissement Linux (Hardening) — SAE 5.01

## 1. Objectifs et Contexte ANSSI

Ce document détaille les mesures de sécurisation appliquées au serveur central Linux (Ubuntu/Debian) hébergeant les services critiques (FreeRADIUS, Wazuh, MariaDB). Ces mesures suivent les recommandations de l'**ANSSI** (Guide d'hygiène informatique et note technique BP-028) pour réduire la surface d'attaque.

**Objectifs :**
- Empêcher la prise de contrôle à distance (SSH sécurisé).
- Restreindre les flux réseaux au strict nécessaire (Pare-feu).
- Limiter les privilèges des services (Moindre privilège).
- Assurer la traçabilité des actions (Journalisation).

---

## 2. Sécurisation du service SSH

L'accès SSH est la porte d'entrée principale pour l'administration.

### 2.1 Configuration `/etc/ssh/sshd_config`

Les modifications suivantes sont impératives :

| Paramètre | Valeur | Justification |
| :--- | :--- | :--- |
| `PermitRootLogin` | **no** | Empêche la connexion directe en tant que root. |
| `PasswordAuthentication` | **no** | Désactive l'authentification par mot de passe (clés SSH obligatoires). |
| `PubkeyAuthentication` | **yes** | Active l'authentification par clé publique. |
| `Protocol` | **2** | Force l'utilisation du protocole SSH v2 (plus sûr). |
| `X11Forwarding` | **no** | Désactive le déport d'affichage graphique (inutile sur serveur). |
| `MaxAuthTries` | **3** | Limite les tentatives de connexion (anti-brute force). |

### 2.2 Mise en œuvre

```bash
# Génération de la paire de clés sur le poste client (si pas déjà fait)
ssh-keygen -t ed25519 -C "admin@sae501"

# Copie de la clé publique vers le serveur
ssh-copy-id user@192.168.10.254

# Application de la configuration (sur le serveur)
sudo nano /etc/ssh/sshd_config
# ... (modifier les lignes citées plus haut) ...

# Redémarrage du service
sudo systemctl restart sshd
```

---

## 3. Pare-feu (UFW)

Nous appliquons une politique de **"Refus par défaut"** (Deny All). Seuls les flux explicitement nécessaires au fonctionnement du SAE sont autorisés.

### 3.1 Politique et Règles

| Service | Port / Proto | Sens | Description |
| :--- | :--- | :--- | :--- |
| **Défaut** | - | IN | **DENY** (Tout bloquer entrant) |
| **Défaut** | - | OUT | **ALLOW** (Tout autoriser sortant) |
| **SSH** | 22 / TCP | IN | Administration serveur |
| **RADIUS** | 1812 / UDP | IN | Authentification (depuis routeurs) |
| **RADIUS** | 1813 / UDP | IN | Accounting (depuis routeurs) |
| **HTTP** | 80 / TCP | IN | Interface Web PHP (Redirection HTTPS prévue) |
| **HTTPS** | 443 / TCP | IN | Interface Web PHP + API Wazuh |
| **Syslog** | 514 / UDP | IN | Réception logs routeurs TL-MR100 |
| **Wazuh** | 1514 / TCP | IN | Communication Agents Wazuh (si agents distants) |
| **Wazuh** | 1515 / TCP | IN | Enrôlement Agents Wazuh |

### 3.2 Commandes d'application

```bash
# Installation (si nécessaire)
sudo apt install ufw

# 1. Reset configuration (Attention : être en console physique ou sûr de soi)
sudo ufw default deny incoming
sudo ufw default allow outgoing

# 2. Autoriser SSH (CRITIQUE : faire avant d'activer)
sudo ufw allow 22/tcp

# 3. Autoriser les services SAE
sudo ufw allow 1812/udp
sudo ufw allow 1813/udp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 514/udp
sudo ufw allow 1514/tcp
sudo ufw allow 1515/tcp

# 4. Activation
sudo ufw enable

# 5. Vérification
sudo ufw status verbose
```

---

## 4. Minimisation des services

Désactivation des services inutiles pour réduire la surface d'attaque et la consommation de ressources.

```bash
# Désactiver l'impression (inutile sur serveur)
sudo systemctl stop cups
sudo systemctl disable cups

# Désactiver le serveur mail (sauf si besoin d'alerting local)
sudo systemctl stop postfix
sudo systemctl disable postfix

# Désactiver Avahi (mDNS/Bonjour)
sudo systemctl stop avahi-daemon
sudo systemctl disable avahi-daemon

# Vérifier les ports en écoute après nettoyage
sudo ss -tulpn
```

---

## 5. Permissions et Propriétaires (Fichiers Critiques)

Protection des secrets (clés privées, mots de passe base de données, secrets RADIUS).

### 5.1 FreeRADIUS

Les fichiers de configuration contiennent le secret partagé (`clients.conf`) et les mots de passe SQL.

```bash
# Répertoire de configuration
sudo chown -R root:freerad /etc/freeradius/3.0/
sudo chmod 750 /etc/freeradius/3.0/

# Certificats (Clé privée serveur)
sudo chown root:freerad /etc/freeradius/3.0/certs/server.key
sudo chmod 640 /etc/freeradius/3.0/certs/server.key

# Fichier clients.conf (contient les secrets NAS)
sudo chown root:freerad /etc/freeradius/3.0/clients.conf
sudo chmod 640 /etc/freeradius/3.0/clients.conf
```

### 5.2 Interface PHP & Base de données

```bash
# Fichier de config DB (contient mot de passe SQL)
sudo chown root:www-data /var/www/html/php-admin/config.php
sudo chmod 640 /var/www/html/php-admin/config.php

# Empêcher l'écriture par le serveur web (sauf uploads si nécessaire)
sudo chown -R root:root /var/www/html/php-admin/
sudo chmod -R 755 /var/www/html/php-admin/
```

---

## 6. Durcissement Base de Données (MariaDB)

Sécurisation de l'installation par défaut.

1.  **Script de sécurisation :**
    Exécuter `sudo mysql_secure_installation` :
    - Set root password? **Y**
    - Remove anonymous users? **Y**
    - Disallow root login remotely? **Y**
    - Remove test database? **Y**
    - Reload privilege tables? **Y**

2.  **Utilisateur Dédié (Moindre Privilège) :**
    Ne jamais utiliser `root` pour l'application PHP ou FreeRADIUS.

    ```sql
    -- Création utilisateur restreint
    CREATE USER 'radius_app'@'localhost' IDENTIFIED BY 'StrongPassword!2026';
    
    -- Droits limités à la base radius uniquement
    GRANT SELECT, INSERT, UPDATE, DELETE ON radius.* TO 'radius_app'@'localhost';
    FLUSH PRIVILEGES;
    ```

3.  **Binding Local :**
    Vérifier que MariaDB n'écoute que sur localhost (fichier `/etc/mysql/mariadb.conf.d/50-server.cnf`).
    `bind-address = 127.0.0.1`

---

## 7. Journalisation et Audit

S'assurer que les actions sont tracées.

- **Syslog :** Vérifier que `rsyslog` est actif.
- **Auth.log :** Surveiller `/var/log/auth.log` pour les connexions SSH et sudo.
- **Wazuh :** L'agent Wazuh doit être configuré pour lire ces fichiers.

```bash
# Vérification statut rsyslog
systemctl status rsyslog

# Vérification présence logs
tail -f /var/log/auth.log
```

---

## 8. Script d'automatisation

Un script `scripts/hardening.sh` est disponible dans le dépôt pour appliquer ces mesures automatiquement sur une nouvelle installation.

> **Note :** Toujours tester le script sur une VM de test avant la production pour éviter de se verrouiller (notamment SSH).

---

**Document rédigé par :** GroupeNani  
**Date :** 4 janvier 2026  
**Version :** 1.0
