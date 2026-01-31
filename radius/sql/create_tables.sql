--
-- create_tables.sql - Schéma complet base de données RADIUS
--
-- Fichier: radius/sql/create_tables.sql
-- Auteur: GroupeNani
-- Date: 4 janvier 2026
--
-- Description:
--   Crée le schéma complet pour FreeRADIUS avec MySQL.
--   Tables: radcheck, radreply, radusergroup, radgroupcheck, radgroupreply,
--           radacct, radpostauth, radaudit
--
-- Prérequis:
--   - Base de données 'radius' créée (voir init_appuser.sql)
--   - Utilisateur 'radius_app' avec permissions
--
-- Utilisation:
--   $ sudo mysql -u root -p radius < radius/sql/create_tables.sql
--

USE radius;

-- ============================================
-- 1. TABLE: radcheck
-- ============================================
-- Attributs d'authentification des utilisateurs
-- Exemple: User-Password, Cleartext-Password

CREATE TABLE IF NOT EXISTS radcheck (
  id int(11) unsigned NOT NULL auto_increment,
  username varchar(64) NOT NULL default '',
  attribute varchar(64) NOT NULL default '',
  op char(2) NOT NULL default ':=',
  value varchar(253) NOT NULL default '',
  PRIMARY KEY  (id),
  KEY username (username),
  KEY attribute (attribute)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- 2. TABLE: radreply
-- ============================================
-- Attributs de réponse pour les utilisateurs acceptés

CREATE TABLE IF NOT EXISTS radreply (
  id int(11) unsigned NOT NULL auto_increment,
  username varchar(64) NOT NULL default '',
  attribute varchar(64) NOT NULL default '',
  op char(2) NOT NULL default '=',
  value varchar(253) NOT NULL default '',
  PRIMARY KEY  (id),
  KEY username (username),
  KEY attribute (attribute)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- 3. TABLE: radusergroup
-- ============================================
-- Association utilisateurs → groupes

CREATE TABLE IF NOT EXISTS radusergroup (
  username varchar(64) NOT NULL default '',
  groupname varchar(64) NOT NULL default '',
  priority int(11) NOT NULL default '1',
  KEY username (username),
  KEY groupname (groupname)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- 4. TABLE: radgroupcheck
-- ============================================
-- Attributs d'authentification des groupes

CREATE TABLE IF NOT EXISTS radgroupcheck (
  id int(11) unsigned NOT NULL auto_increment,
  groupname varchar(64) NOT NULL default '',
  attribute varchar(64) NOT NULL default '',
  op char(2) NOT NULL default ':=',
  value varchar(253) NOT NULL default '',
  PRIMARY KEY  (id),
  KEY groupname (groupname),
  KEY attribute (attribute)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- 5. TABLE: radgroupreply
-- ============================================
-- Attributs de réponse des groupes

CREATE TABLE IF NOT EXISTS radgroupreply (
  id int(11) unsigned NOT NULL auto_increment,
  groupname varchar(64) NOT NULL default '',
  attribute varchar(64) NOT NULL default '',
  op char(2) NOT NULL default '=',
  value varchar(253) NOT NULL default '',
  PRIMARY KEY  (id),
  KEY groupname (groupname),
  KEY attribute (attribute)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- 6. TABLE: radacct
-- ============================================
-- Enregistrement des sessions (Accounting)

CREATE TABLE IF NOT EXISTS radacct (
  radacctid bigint(21) NOT NULL auto_increment,
  acctsessionid varchar(64) NOT NULL default '',
  acctuniqueid varchar(32) NOT NULL default '',
  username varchar(64) NOT NULL default '',
  realm varchar(64) default '',
  nasipaddress varchar(15) NOT NULL default '',
  nasportid varchar(15) default NULL,
  nasporttype varchar(32) default NULL,
  acctstarttime datetime NULL default NULL,
  acctstoptime datetime NULL default NULL,
  acctsessiontime int(12) unsigned default NULL,
  acctauthentic varchar(32) default NULL,
  connectinfo_start varchar(50) default NULL,
  connectinfo_stop varchar(50) default NULL,
  acctinputoctets bigint(20) default NULL,
  acctoutputoctets bigint(20) default NULL,
  calledstationid varchar(50) default NULL,
  callingstationid varchar(50) default NULL,
  acctterminatecause varchar(32) NOT NULL default '',
  servicetype varchar(32) default NULL,
  framedprotocol varchar(32) default NULL,
  framedipaddress varchar(15) NOT NULL default '',
  framedipv6address varchar(45) default NULL,
  framedipv6prefix varchar(45) default NULL,
  framedinterfaceid varchar(44) default NULL,
  delegatedipv6prefix varchar(45) default NULL,
  PRIMARY KEY  (radacctid),
  UNIQUE KEY acctuniqueid (acctuniqueid),
  KEY username (username),
  KEY framedipaddress (framedipaddress),
  KEY acctsessionid (acctsessionid),
  KEY acctstarttime (acctstarttime),
  KEY acctstoptime (acctstoptime),
  KEY nasipaddress (nasipaddress)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- 7. TABLE: radpostauth
-- ============================================
-- Log post-authentification (succès/rejet)

CREATE TABLE IF NOT EXISTS radpostauth (
  id int(11) unsigned NOT NULL auto_increment,
  username varchar(64) NOT NULL default '',
  pass varchar(64) NOT NULL default '',
  reply varchar(32) NOT NULL default '',
  calledstationid varchar(50) NOT NULL default '',
  callingstationid varchar(50) NOT NULL default '',
  authdate timestamp NOT NULL default CURRENT_TIMESTAMP,
  PRIMARY KEY  (id),
  KEY username (username),
  KEY authdate (authdate)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- 8. TABLE: radaudit (optionnel)
-- ============================================
-- Audit des changements (INSERT/UPDATE/DELETE)

CREATE TABLE IF NOT EXISTS radaudit (
  id int(11) unsigned NOT NULL auto_increment,
  username varchar(64) NOT NULL default '',
  table_name varchar(64) NOT NULL default '',
  operation varchar(8) NOT NULL default '',
  old_value varchar(253) default NULL,
  new_value varchar(253) default NULL,
  change_date timestamp NOT NULL default CURRENT_TIMESTAMP,
  PRIMARY KEY  (id),
  KEY username (username),
  KEY change_date (change_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- DONNÉES INITIALES - GROUPES
-- ============================================

INSERT INTO radgroupcheck (groupname, attribute, op, value) VALUES
  ('staff', 'Auth-Type', ':=', 'Local'),
  ('staff', 'Session-Timeout', ':=', '3600'),
  ('guests', 'Auth-Type', ':=', 'Local'),
  ('guests', 'Session-Timeout', ':=', '1800'),
  ('managers', 'Auth-Type', ':=', 'Local'),
  ('managers', 'Session-Timeout', ':=', '7200');

INSERT INTO radgroupreply (groupname, attribute, op, value) VALUES
  ('staff', 'Reply-Message', '=', 'Bienvenue Staff'),
  ('staff', 'Framed-Protocol', '=', 'PPP'),
  ('guests', 'Reply-Message', '=', 'Accès Guest'),
  ('guests', 'Framed-Protocol', '=', 'PPP'),
  ('managers', 'Reply-Message', '=', 'Bienvenue Manager'),
  ('managers', 'Framed-Protocol', '=', 'PPP');

-- ============================================
-- DONNÉES INITIALES - UTILISATEURS
-- ============================================

INSERT INTO radcheck (username, attribute, op, value) VALUES
  ('alice@gym.fr', 'Cleartext-Password', ':=', 'Alice@123!'),
  ('bob@gym.fr', 'Cleartext-Password', ':=', 'Bob@456!'),
  ('charlie@gym.fr', 'Cleartext-Password', ':=', 'Charlie@789!'),
  ('david@gym.fr', 'Cleartext-Password', ':=', 'David@2026!'),
  ('emma@gym.fr', 'Cleartext-Password', ':=', 'Emma@2026!');

INSERT INTO radusergroup (username, groupname, priority) VALUES
  ('alice@gym.fr', 'staff', 1),
  ('bob@gym.fr', 'staff', 1),
  ('charlie@gym.fr', 'guests', 1),
  ('david@gym.fr', 'managers', 1),
  ('emma@gym.fr', 'staff', 1);

-- ============================================
-- VUES UTILES
-- ============================================

-- Vue: Utilisateurs avec leurs groupes et attributs
CREATE OR REPLACE VIEW v_users_with_groups AS
SELECT DISTINCT
  rc.username,
  rc.attribute,
  rc.value as check_value,
  rug.groupname,
  rr.attribute as reply_attribute,
  rr.value as reply_value
FROM radcheck rc
LEFT JOIN radusergroup rug ON rc.username = rug.username
LEFT JOIN radreply rr ON rc.username = rr.username
ORDER BY rc.username, rug.groupname;

-- Vue: Sessions actives
CREATE OR REPLACE VIEW v_active_sessions AS
SELECT
  acctsessionid,
  username,
  nasipaddress,
  acctstarttime,
  framedipaddress,
  calledstationid,
  callingstationid,
  TIMESTAMPDIFF(SECOND, acctstarttime, NOW()) as session_duration_seconds
FROM radacct
WHERE acctstoptime IS NULL
ORDER BY acctstarttime DESC;

-- ============================================
-- TRIGGERS (Audit automatique)
-- ============================================

-- Trigger: Insert audit radcheck
DELIMITER //
CREATE TRIGGER tr_radcheck_insert AFTER INSERT ON radcheck
FOR EACH ROW
BEGIN
  INSERT INTO radaudit (username, table_name, operation, new_value)
  VALUES (NEW.username, 'radcheck', 'INSERT', CONCAT(NEW.attribute, '=', NEW.value));
END//
DELIMITER ;

-- Trigger: Update audit radcheck
DELIMITER //
CREATE TRIGGER tr_radcheck_update AFTER UPDATE ON radcheck
FOR EACH ROW
BEGIN
  INSERT INTO radaudit (username, table_name, operation, old_value, new_value)
  VALUES (NEW.username, 'radcheck', 'UPDATE', CONCAT(OLD.attribute, '=', OLD.value), CONCAT(NEW.attribute, '=', NEW.value));
END//
DELIMITER ;

-- Trigger: Delete audit radcheck
DELIMITER //
CREATE TRIGGER tr_radcheck_delete AFTER DELETE ON radcheck
FOR EACH ROW
BEGIN
  INSERT INTO radaudit (username, table_name, operation, old_value)
  VALUES (OLD.username, 'radcheck', 'DELETE', CONCAT(OLD.attribute, '=', OLD.value));
END//
DELIMITER ;

-- ============================================
-- NOTES
-- ============================================

-- Opérateurs (op):
--   :=  = Défini (remplace)
--   =   = Ajouter
--   ==  = Comparer (condition)
--   !=  = Différent de
--   >   = Supérieur à
--   <   = Inférieur à
--   >=  = Supérieur ou égal
--   <=  = Inférieur ou égal

-- Attributs courants:
--   User-Password: Mot de passe (MD5 hash en production)
--   Cleartext-Password: Mot de passe en clair (tests seulement)
--   Reply-Message: Message au client
--   Session-Timeout: Durée max session (sec)
--   Framed-Protocol: PPP, SLIP, ARAP
--   Auth-Type: Local, LDAP, RADIUS, etc.

-- Flux authentification:
--   1. Client envoie identifiants
--   2. FreeRADIUS cherche dans radcheck
--   3. Vérifie mot de passe
--   4. Si OK, cherche dans radreply
--   5. Si utilisateur dans groupe, ajoute attributs radgroupreply
--   6. Retourne Access-Accept avec attributs

-- Production:
--   - Stocker MD5 hash (not Cleartext-Password)
--   - Utiliser Cleartext-Password UNIQUEMENT pour tests
--   - Activer Message-Authenticator (RADIUS security)
--   - Archiver logs audit régulièrement
--
