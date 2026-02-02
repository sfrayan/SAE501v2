# Dossier RADIUS - SAE 5.01

## 📁 Structure

```
radius/
├── clients.conf           # Config clients NAS (Routeurs)
├── users.txt              # Utilisateurs de test (format FreeRADIUS)
└── sql/
    ├── init_appuser.sql   # Création utilisateur MySQL
    └── create_tables.sql  # Schéma base de données RADIUS
```

## 💻 Architecture Réseau

```
PC Portable (Hôte)
├─ WiFi (wlan0): Internet via Box
└─ LAN (eth0): 192.168.10.x → Routeur TP-Link
         │
         ▼
Routeur TP-Link TL-MR100
  IP: 192.168.10.1
  ├─ SSID: Fitness-Pro (WPA2-Enterprise)
  └─ SSID: Fitness-Guest (WPA2-PSK + AP Isolation)
         │
         ▼
VM Debian 11 (Serveur RADIUS)
  ├─ eth0 (Bridge): 192.168.10.100
  │  └─ Gateway: 192.168.10.1
  │  └─ Communication avec routeur
  │
  └─ eth1 (NAT): 10.0.2.15
     └─ Gateway: 10.0.2.2
     └─ Internet pour apt-get
```

**Réseau unique**: 192.168.10.0/24 (pas de VLAN)
**Isolation invités**: AP Isolation au niveau routeur

---

## 📄 Fichiers

### `clients.conf`
Configuration des clients RADIUS autorisés (Routeurs/NAS).

**Contenu:**
- **TL-MR100** (192.168.10.1) - Routeur principal
- **Secret partagé**: `Pj8K2qL9xR5wM3nP7dF4vB6tH1sQ9cZ2`
- **Tests locaux**: localhost + 127.0.0.1 (secret: `testing123`)

**À faire:**
```bash
# 1. Copier vers FreeRADIUS
sudo cp radius/clients.conf /etc/freeradius/3.0/

# 2. Configurer le routeur avec le MÊME secret
# Interface web TL-MR100 → RADIUS Settings
# IP: 192.168.10.100
# Port: 1812
# Secret: Pj8K2qL9xR5wM3nP7dF4vB6tH1sQ9cZ2

# 3. Vérifier les permissions
sudo chmod 640 /etc/freeradius/3.0/clients.conf
sudo chown root:freerad /etc/freeradius/3.0/clients.conf
```

**Sécurité:**
- Secret minimum 16 caractères (idéalement 32+)
- Doit être IDENTIQUE partout (routeur + serveur)
- Générer nouveau: `openssl rand -hex 16`

---

### `users.txt`
Fichier FreeRADIUS contenant les utilisateurs de test.

**Format:**
```
username Cleartext-Password := "password"
    Reply-Message := "Message"
```

**Utilisateurs pré-configurés:**
| Username | Password | Rôle |
| :--- | :--- | :--- |
| alice@gym.fr | Alice@123! | Staff |
| bob@gym.fr | Bob@456! | Staff |
| charlie@gym.fr | Charlie@789! | Guest |
| david@gym.fr | David@2026! | Manager |
| emma@gym.fr | Emma@2026! | Réception |

**À faire:**
```bash
# 1. Copier vers FreeRADIUS
sudo cp radius/users.txt /etc/freeradius/3.0/users

# 2. Permissions
sudo chmod 640 /etc/freeradius/3.0/users
sudo chown root:freerad /etc/freeradius/3.0/users
```

**Note Important:**
- ⚠️ En production, utiliser la base MySQL (`sql/create_tables.sql`)
- Cleartext-Password = mots de passe en CLAIR (tests seulement)
- Production = Stocker MD5 hash

---

### `sql/init_appuser.sql`
Script de création de l'utilisateur MySQL pour FreeRADIUS.

**Crée:**
- **Utilisateur**: `radius_app`
- **Password**: `RadiusAppPass!2026`
- **Base**: `radius`
- **Permissions**: SELECT, INSERT, UPDATE, DELETE, CREATE, INDEX, ALTER

**À exécuter AVANT `create_tables.sql`:**
```bash
sudo mysql -u root -p < radius/sql/init_appuser.sql
```

**Vérification:**
```bash
# Connecter avec nouvel utilisateur
mysql -u radius_app -p -h localhost radius
# Password: RadiusAppPass!2026
```

---

### `sql/create_tables.sql`
Schéma complet de la base de données RADIUS.

**Tables créées:**

| Table | Rôle |
| :--- | :--- |
| **radcheck** | Attributs authentification (User-Password, etc.) |
| **radreply** | Attributs de réponse (Reply-Message, Framed-Protocol) |
| **radusergroup** | Association utilisateurs → groupes |
| **radgroupcheck** | Attributs d'authentification des groupes |
| **radgroupreply** | Attributs de réponse des groupes |
| **radacct** | Enregistrement des sessions (Accounting) |
| **radpostauth** | Log post-authentification (succès/rejet) |
| **radaudit** | Audit des changements (INSERT/UPDATE/DELETE) |

**Données initiales:**
- ✅ 3 groupes: staff, guests, managers
- ✅ 5 utilisateurs: alice, bob, charlie, david, emma
- ✅ Associations groupe-utilisateurs
- ✅ 2 vues SQL utiles
- ✅ 3 triggers audit automatiques

**À exécuter APRÈS `init_appuser.sql`:**
```bash
sudo mysql -u root -p radius < radius/sql/create_tables.sql
```

---

## 🚀 Installation Complète (Ordre IMPORTANT)

### Étape 1️⃣: Créer l'utilisateur MySQL

```bash
sudo mysql -u root -p < radius/sql/init_appuser.sql
```

✅ Résultat attendu:
```
Query OK, 0 rows affected
User 'radius_app'@'localhost' created
Database 'radius' created
GRANT permissions applied
```

---

### Étape 2️⃣: Créer les tables et données

```bash
sudo mysql -u root -p radius < radius/sql/create_tables.sql
```

✅ Résultat attendu:
```
Query OK - 8 tables created
Vues créées
Triggers créés
Données initiales chargées
```

---

### Étape 3️⃣: Copier la configuration clients

```bash
# Copier clients.conf
sudo cp radius/clients.conf /etc/freeradius/3.0/
sudo chmod 640 /etc/freeradius/3.0/clients.conf
sudo chown root:freerad /etc/freeradius/3.0/clients.conf
```

---

### Étape 4️⃣: Copier le fichier utilisateurs (optionnel - tests)

```bash
# Copier users
sudo cp radius/users.txt /etc/freeradius/3.0/users
sudo chmod 640 /etc/freeradius/3.0/users
sudo chown root:freerad /etc/freeradius/3.0/users
```

---

### Étape 5️⃣: Configurer FreeRADIUS

```bash
# Permissions globales
sudo chown -R root:freerad /etc/freeradius/3.0/
sudo chmod -R 750 /etc/freeradius/3.0/

# Vérifier la configuration
sudo freeradius -XC

# Redémarrer le service
sudo systemctl restart freeradius

# Vérifier le statut
sudo systemctl status freeradius
```

---

### Étape 6️⃣: Tester l'authentification

```bash
# Test avec utilisateur alice@gym.fr
radtest alice@gym.fr Alice@123! 127.0.0.1 1812 testing123
```

✅ Résultat attendu:
```
Received Access-Accept
    Reply-Message = "Bienvenue Alice - Accès Staff autorisé"
```

---

## 🧪 Vérifications

### ✅ Vérifier les utilisateurs en base

```bash
mysql -u radius_app -p radius -e "SELECT username FROM radcheck GROUP BY username;"
# Password: RadiusAppPass!2026
```

Résultat attendu:
```
+----------------+
| username       |
+----------------+
| alice@gym.fr   |
| bob@gym.fr     |
| charlie@gym.fr |
| david@gym.fr   |
| emma@gym.fr    |
+----------------+
```

---

### ✅ Voir un utilisateur spécifique

```bash
mysql -u radius_app -p radius -e "SELECT * FROM radcheck WHERE username='alice@gym.fr';"
```

Résultat attendu:
```
+----+---------------+--------------------+-----+-------------+
| id | username      | attribute          | op  | value       |
+----+---------------+--------------------+-----+-------------+
|  1 | alice@gym.fr  | Cleartext-Password | :=  | Alice@123!  |
+----+---------------+--------------------+-----+-------------+
```

---

### ✅ Vérifier les groupes

```bash
mysql -u radius_app -p radius -e "SELECT * FROM radusergroup;"
```

Résultat attendu:
```
+---------------+-----------+----------+
| username      | groupname | priority |
+---------------+-----------+----------+
| alice@gym.fr  | staff     |        1 |
| bob@gym.fr    | staff     |        1 |
| charlie@gym.fr| guests    |        1 |
| david@gym.fr  | managers  |        1 |
| emma@gym.fr   | staff     |        1 |
+---------------+-----------+----------+
```

---

### ✅ Vérifier les logs FreeRADIUS

```bash
tail -f /var/log/freeradius/radius.log
```

Ou test complet:
```bash
sudo freeradius -X
# Puis dans autre terminal:
radtest alice@gym.fr Alice@123! 127.0.0.1 1812 testing123
```

---

## 🔐 Sécurité - Checklist

- [ ] Secret clients.conf (`Pj8K2qL9xR5wM3nP7dF4vB6tH1sQ9cZ2`) identique dans TL-MR100
- [ ] Routeur configuré: IP serveur 192.168.10.100, port 1812
- [ ] Permissions 640 sur clients.conf et users
- [ ] Utilisateur MySQL `radius_app` créé avec password fort
- [ ] Base de données `radius` créée
- [ ] 8 tables créées avec succès
- [ ] Données initiales (5 users + 3 groupes) chargées
- [ ] Port 1812-1813 UDP ouvert dans UFW
- [ ] Certificats générés (`/etc/freeradius/3.0/certs/`)
- [ ] Module SQL activé dans FreeRADIUS
- [ ] Tests authentification réussis (radtest)
- [ ] Logs FreeRADIUS accessibles
- [ ] Triggers audit fonctionnels

---

## 🔄 Relations Tables (Important!)

```
radcheck (attributs auth)
    ↓
radcheck.username → radusergroup.username
    ↓
radusergroup.groupname → radgroupcheck.groupname
    ↓
radgroupcheck (attributs groupe)
    ↓
radreply (réponses utilisateur)
    ↓
radgroupreply (réponses groupe)
```

**Exemple flux:**
```
1. Client WiFi: alice@gym.fr / Alice@123!
2. Routeur (192.168.10.1) → Serveur RADIUS (192.168.10.100:1812)
3. Cherche dans radcheck: Username=alice@gym.fr
4. Vérifie password dans radcheck: OK
5. Cherche radusergroup: alice@gym.fr → staff
6. Cherche radgroupcheck: staff → attributs
7. Cherche radreply: alice@gym.fr → attributs
8. Cherche radgroupreply: staff → attributs
9. Combine tout et retourne Access-Accept + attributs
10. Client connecté au réseau 192.168.10.0/24
```

---

## 🐛 Troubleshooting

| Problème | Cause Probable | Solution |
| :--- | :--- | :--- |
| **Unknown NAS** | Client pas dans clients.conf | Vérifier IP 192.168.10.1 dans clients.conf |
| **Bad authenticator** | Secret différent | Vérifier secret identique (routeur + serveur) |
| **No reply received** | Firewall bloque 1812/1813 | `sudo ufw allow 1812/udp` |
| **Access-Reject** | Utilisateur pas en DB ou password faux | Vérifier dans radcheck table |
| **TLS error** | Certificats corrompus | `cd /etc/freeradius/3.0/certs && sudo make` |
| **Connection refused** | FreeRADIUS pas démarré | `sudo systemctl start freeradius` |
| **Query failed** | Base données inexistante | Exécuter init_appuser.sql puis create_tables.sql |
| **Can't reach server** | Interface Bridge mal configurée | Vérifier eth0 = 192.168.10.100, ping 192.168.10.1 |

---

## 📊 Schéma SQL Quick Reference

**Ajouter un utilisateur:**
```sql
INSERT INTO radcheck (username, attribute, op, value)
VALUES ('john@gym.fr', 'Cleartext-Password', ':=', 'SecurePass123!');

INSERT INTO radusergroup (username, groupname, priority)
VALUES ('john@gym.fr', 'staff', 1);
```

**Modifier password:**
```sql
UPDATE radcheck 
SET value='NewPassword!456'
WHERE username='alice@gym.fr' AND attribute='Cleartext-Password';
```

**Supprimer utilisateur:**
```sql
DELETE FROM radcheck WHERE username='john@gym.fr';
DELETE FROM radusergroup WHERE username='john@gym.fr';
```

**Voir sessions actives:**
```sql
SELECT * FROM v_active_sessions;
```

**Voir audit:**
```sql
SELECT * FROM radaudit WHERE username='alice@gym.fr' ORDER BY change_date DESC;
```

---

## 📚 Attributs RADIUS Courants

```
Authentication:
  User-Password                 # Mot de passe
  Cleartext-Password            # Mot de passe clair (tests)
  Auth-Type                     # Local, LDAP, RADIUS, etc.

Response:
  Reply-Message                 # Message au client
  Session-Timeout               # Durée max session (secondes)
  Framed-Protocol               # PPP, SLIP, ARAP
  Framed-IP-Address             # IP fixe (optionnel)
  Framed-IP-Netmask             # Masque sous-réseau (optionnel)

Operators:
  :=  = Défini (remplace tous)
  =   = Ajouter à la liste
  ==  = Comparer (condition, pas attribution)
  !=  = Non égal (condition)
  >   = Supérieur à (condition)
  <   = Inférieur à (condition)
  >=  = Supérieur ou égal (condition)
  <=  = Inférieur ou égal (condition)
```

---

## 📦 Configuration Routeur TP-Link

**Menu** → **Wireless** → **RADIUS Settings**

```
Primary RADIUS Server:
  IP Address: 192.168.10.100
  Port: 1812
  Shared Secret: Pj8K2qL9xR5wM3nP7dF4vB6tH1sQ9cZ2

SSID Configuration:
  - Fitness-Pro: WPA2-Enterprise (RADIUS)
  - Fitness-Guest: WPA2-PSK (AP Isolation activée)
```

---

**Créé par**: GroupeNani  
**Date**: 2 février 2026  
**Version**: 2.1 - Architecture réelle
