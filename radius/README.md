# Dossier RADIUS - SAE 5.01

## 📁 Structure

```
radius/
├── clients.conf           # Config clients NAS (Routeurs)
├── users                  # Utilisateurs de test (format FreeRADIUS)
└── sql/
    ├── init_appuser.sql   # Création utilisateur MySQL
    └── create_tables.sql  # Schéma base de données RADIUS
```

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
# Interface web TL-MR100 → Config RADIUS → Secret = Pj8K2qL9xR5wM3nP7dF4vB6tH1sQ9cZ2

# 3. Vérifier les permissions
sudo chmod 640 /etc/freeradius/3.0/clients.conf
```

**Sécurité:**
- Secret minimum 16 caractères (idéalement 32+)
- Doit être IDENTIQUE partout (routeur + serveur)
- Générer nouveau: `openssl rand -hex 16`

---

### `users`
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
sudo cp radius/users /etc/freeradius/3.0/

# 2. Permissions
sudo chmod 640 /etc/freeradius/3.0/users
```

**Note Important:**
- ⚠️ En production, utiliser la base MySQL (`sql/create_tables.sql`)
- Cleartext-Password = mots de passe en CLAIR (tests seulement)
- Production = Stocker MD5 hash

**Format FreeRADIUS:**
```
:=  = Remplacer (défaut)
=   = Ajouter
==  = Comparer (condition)
!=  = Non égal
```

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

**Commandes SQL incluses:**
```sql
CREATE USER 'radius_app'@'localhost' IDENTIFIED BY 'RadiusAppPass!2026';
CREATE DATABASE radius CHARACTER SET utf8mb4;
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, INDEX, ALTER ON radius.* TO 'radius_app'@'localhost';
FLUSH PRIVILEGES;
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
- ✅ 5 groupes: staff, guests, managers
- ✅ 5 utilisateurs: alice, bob, charlie, david, emma
- ✅ Associations groupe-utilisateurs
- ✅ 3 vues SQL utiles
- ✅ 3 triggers audit automatiques

**À exécuter APRÈS `init_appuser.sql`:**
```bash
sudo mysql -u root -p radius < radius/sql/create_tables.sql
```

**Vues incluses:**
```sql
v_users_with_groups  -- Utilisateurs + groupes + attributs
v_active_sessions    -- Sessions Wi-Fi actives
```

**Triggers inclus:**
```sql
tr_radcheck_insert   -- Audit INSERT
tr_radcheck_update   -- Audit UPDATE
tr_radcheck_delete   -- Audit DELETE
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
sudo cp radius/users /etc/freeradius/3.0/
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
sudo radiusd -XC

# Redémarrer le service
sudo systemctl restart freeradius

# Vérifier le statut
sudo systemctl status freeradius
```

---

### Étape 6️⃣: Tester l'authentification

```bash
# Test avec utilisateur alice@gym.fr
sudo radtest alice@gym.fr Alice@123! 127.0.0.1 1812 testing123
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
sudo radiusd -X
# Puis dans autre terminal:
sudo radtest alice@gym.fr Alice@123! 127.0.0.1 1812 testing123
```

---

## 🔐 Sécurité - Checklist

- [ ] Secret clients.conf (`Pj8K2qL9xR5wM3nP7dF4vB6tH1sQ9cZ2`) identique dans TL-MR100
- [ ] Permissions 640 sur clients.conf et users
- [ ] Utilisateur MySQL `radius_app` créé avec password fort
- [ ] Base de données `radius` créée
- [ ] 8 tables créées avec succès
- [ ] Données initiales (5 users + 6 groupes) chargées
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
1. Client: alice@gym.fr / Alice@123!
2. Cherche dans radcheck: Username=alice@gym.fr
3. Vérifie password dans radcheck: OK
4. Cherche radusergroup: alice@gym.fr → staff
5. Cherche radgroupcheck: staff → attributs
6. Cherche radreply: alice@gym.fr → attributs
7. Cherche radgroupreply: staff → attributs
8. Combine tout et retourne Access-Accept + attributs
```

---

## 🐛 Troubleshooting

| Problème | Cause Probable | Solution |
| :--- | :--- | :--- |
| **Unknown NAS** | Client pas dans clients.conf | Ajouter IP routeur dans clients.conf |
| **Bad authenticator** | Secret différent | Vérifier secret identique partout |
| **No reply received** | Firewall bloque 1812/1813 | `ufw allow 1812/udp 1813/udp` |
| **Access-Reject** | Utilisateur pas en DB ou password faux | Vérifier dans radcheck table |
| **TLS error** | Certificats corrompus | `cd /etc/freeradius/3.0/certs && sudo make clean && sudo make` |
| **Connection refused** | FreeRADIUS pas démarré | `sudo systemctl start freeradius` |
| **Query failed** | Base données inexistante | Exécuter init_appuser.sql puis create_tables.sql |
| **Permission denied** | Permissions fichiers incorrectes | `sudo chmod 640` sur fichiers sensibles |

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

## 📞 Support

- **Projet**: SAE 5.01 - Architecture Wi-Fi Sécurisée
- **Équipe**: GroupeNani (Alice, Bob, Charlie)
- **Deadline**: 19 janvier 2026
- **Contact**: groupenani@sae501.fr

---

**Créé par**: GroupeNani  
**Date**: 4 janvier 2026  
**Version**: 1.0
