--
-- create_tables.sql - Schéma COMPLET base de données RADIUS (AVEC GROUPES)
--
-- Version: 3 février 2026 - VERSION AVEC GROUPES ACTIVÉS
-- Auteur: GroupeNani - Corrigé par Perplexity
--
-- Description:
--   Crée un schéma complet pour FreeRADIUS avec MySQL.
--   AVEC système de groupes pour éliminer les warnings.
--
--   Tables activées:
--     - nas (clients RADIUS)
--     - radcheck (authentification utilisateurs)
--     - radreply (réponses utilisateurs)
--     - radusergroup (appartenance aux groupes) ✅
--     - radgroupcheck (attributs de groupe) ✅
--     - radgroupreply (réponses de groupe) ✅
--     - radacct (accounting/sessions)
--     - radpostauth (logs post-auth)
--
-- Utilisation:
--   $ sudo mysql -u root radius < radius/sql/create_tables.sql
--

USE radius;

-- ============================================
-- SUPPRIMER LES ANCIENNES TABLES
-- ============================================

DROP TABLE IF EXISTS radusergroup;
DROP TABLE IF EXISTS radgroupcheck;
DROP TABLE IF EXISTS radgroupreply;
DROP TABLE IF EXISTS radpostauth;
DROP TABLE IF EXISTS radacct;
DROP TABLE IF EXISTS radreply;
DROP TABLE IF EXISTS radcheck;
DROP TABLE IF EXISTS nas;
DROP VIEW IF EXISTS v_users_with_groups;
DROP VIEW IF EXISTS v_users_simple;
DROP VIEW IF EXISTS v_active_sessions;

-- ============================================
-- 0. TABLE: nas (CLIENTS RADIUS)
-- ============================================

CREATE TABLE nas (
  id int(11) unsigned NOT NULL auto_increment,
  nasname varchar(128) NOT NULL,
  shortname varchar(32) default NULL,
  type varchar(30) default 'other',
  ports int(5) default NULL,
  secret varchar(60) NOT NULL default 'secret',
  server varchar(64) default NULL,
  community varchar(50) default NULL,
  description varchar(200) default 'RADIUS Client',
  PRIMARY KEY (id),
  KEY nasname (nasname),
  KEY shortname (shortname)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Insérer le routeur TL-MR100
INSERT INTO nas (nasname, shortname, type, secret, description) VALUES
  ('192.168.10.1', 'TL-MR100', 'other', 'testing123', 'Routeur TP-Link TL-MR100');

-- ============================================
-- 1. TABLE: radcheck (AUTHENTIFICATION)
-- ============================================

CREATE TABLE radcheck (
  id int(11) unsigned NOT NULL auto_increment,
  username varchar(64) NOT NULL default '',
  attribute varchar(64) NOT NULL default '',
  op char(2) NOT NULL default ':=',
  value varchar(253) NOT NULL default '',
  PRIMARY KEY (id),
  KEY username (username),
  KEY attribute (attribute)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- 2. TABLE: radreply (RÉPONSES)
-- ============================================

CREATE TABLE radreply (
  id int(11) unsigned NOT NULL auto_increment,
  username varchar(64) NOT NULL default '',
  attribute varchar(64) NOT NULL default '',
  op char(2) NOT NULL default '=',
  value varchar(253) NOT NULL default '',
  PRIMARY KEY (id),
  KEY username (username),
  KEY attribute (attribute)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- 3. TABLE: radgroupcheck (ATTRIBUTS GROUPE) ✅
-- ============================================

CREATE TABLE radgroupcheck (
  id int(11) unsigned NOT NULL auto_increment,
  groupname varchar(64) NOT NULL default '',
  attribute varchar(64) NOT NULL default '',
  op char(2) NOT NULL default ':=',
  value varchar(253) NOT NULL default '',
  PRIMARY KEY (id),
  KEY groupname (groupname)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- 4. TABLE: radgroupreply (RÉPONSES GROUPE) ✅
-- ============================================

CREATE TABLE radgroupreply (
  id int(11) unsigned NOT NULL auto_increment,
  groupname varchar(64) NOT NULL default '',
  attribute varchar(64) NOT NULL default '',
  op char(2) NOT NULL default '=',
  value varchar(253) NOT NULL default '',
  PRIMARY KEY (id),
  KEY groupname (groupname)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- 5. TABLE: radusergroup (APPARTENANCE) ✅
-- ============================================

CREATE TABLE radusergroup (
  id int(11) unsigned NOT NULL auto_increment,
  username varchar(64) NOT NULL default '',
  groupname varchar(64) NOT NULL default '',
  priority int(11) NOT NULL default 0,
  PRIMARY KEY (id),
  KEY username (username),
  KEY groupname (groupname)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- 6. TABLE: radacct (ACCOUNTING/SESSIONS)
-- ============================================

CREATE TABLE radacct (
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
  PRIMARY KEY (radacctid),
  UNIQUE KEY acctuniqueid (acctuniqueid),
  KEY username (username),
  KEY framedipaddress (framedipaddress),
  KEY acctsessionid (acctsessionid),
  KEY acctstarttime (acctstarttime),
  KEY acctstoptime (acctstoptime),
  KEY nasipaddress (nasipaddress)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- 7. TABLE: radpostauth (LOGS POST-AUTH)
-- ============================================

CREATE TABLE radpostauth (
  id int(11) unsigned NOT NULL auto_increment,
  username varchar(64) NOT NULL default '',
  pass varchar(64) NOT NULL default '',
  reply varchar(32) NOT NULL default '',
  calledstationid varchar(50) NOT NULL default '',
  callingstationid varchar(50) NOT NULL default '',
  authdate timestamp NOT NULL default CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY username (username),
  KEY authdate (authdate)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- 8. DONNÉES INITIALES - GROUPES
-- ============================================

-- Créer les groupes
INSERT INTO radgroupcheck (groupname, attribute, op, value) VALUES
  ('staff', 'Auth-Type', ':=', 'Accept'),
  ('manager', 'Auth-Type', ':=', 'Accept'),
  ('guest', 'Auth-Type', ':=', 'Accept');

-- Attributs de réponse par groupe
INSERT INTO radgroupreply (groupname, attribute, op, value) VALUES
  ('staff', 'Session-Timeout', ':=', '28800'),
  ('staff', 'Idle-Timeout', ':=', '1800'),
  ('manager', 'Session-Timeout', ':=', '43200'),
  ('manager', 'Idle-Timeout', ':=', '3600'),
  ('guest', 'Session-Timeout', ':=', '7200'),
  ('guest', 'Idle-Timeout', ':=', '900');

-- ============================================
-- 9. DONNÉES INITIALES - UTILISATEURS
-- ============================================

-- Insérer les utilisateurs
INSERT INTO radcheck (username, attribute, op, value) VALUES
  ('alice@gym.fr', 'Cleartext-Password', ':=', 'Alice@123!'),
  ('bob@gym.fr', 'Cleartext-Password', ':=', 'Bob@456!'),
  ('charlie@gym.fr', 'Cleartext-Password', ':=', 'Charlie@789!'),
  ('david@gym.fr', 'Cleartext-Password', ':=', 'David@2026!'),
  ('emma@gym.fr', 'Cleartext-Password', ':=', 'Emma@2026!');

-- Ajouter messages de réponse personnalisés
INSERT INTO radreply (username, attribute, op, value) VALUES
  ('alice@gym.fr', 'Reply-Message', '=', 'Bienvenue Alice (Staff)'),
  ('bob@gym.fr', 'Reply-Message', '=', 'Bienvenue Bob (Staff)'),
  ('charlie@gym.fr', 'Reply-Message', '=', 'Bienvenue Charlie (Guest)'),
  ('david@gym.fr', 'Reply-Message', '=', 'Bienvenue David (Manager)'),
  ('emma@gym.fr', 'Reply-Message', '=', 'Bienvenue Emma (Staff)');

-- Associer utilisateurs aux groupes
INSERT INTO radusergroup (username, groupname, priority) VALUES
  ('alice@gym.fr', 'staff', 1),
  ('bob@gym.fr', 'staff', 1),
  ('charlie@gym.fr', 'guest', 1),
  ('david@gym.fr', 'manager', 1),
  ('emma@gym.fr', 'staff', 1);

-- ============================================
-- 10. VUES
-- ============================================

-- Vue: Utilisateurs avec leurs groupes
CREATE OR REPLACE VIEW v_users_with_groups AS
SELECT 
  rc.username,
  rug.groupname,
  rc.value as password,
  rr.value as reply_message
FROM radcheck rc
LEFT JOIN radusergroup rug ON rc.username = rug.username
LEFT JOIN radreply rr ON rc.username = rr.username
WHERE rc.attribute = 'Cleartext-Password'
ORDER BY rc.username;

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
-- NOTES
-- ============================================

-- ✅ VERSION COMPLÈTE AVEC GROUPES:
--   - Tables de groupes activées (radusergroup, radgroupcheck, radgroupreply)
--   - Authentification utilisateur + héritage attributs de groupe
--   - Plus de warnings "group_membership_query"
--
-- Flux authentification avec groupes:
--   1. Client envoie identifiants
--   2. FreeRADIUS cherche dans radcheck (utilisateur)
--   3. Vérifie mot de passe
--   4. Cherche groupe dans radusergroup
--   5. Applique attributs du groupe (radgroupreply)
--   6. Applique attributs utilisateur (radreply)
--   7. Retourne Access-Accept avec tous les attributs
--
