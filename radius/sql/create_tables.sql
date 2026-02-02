--
-- create_tables.sql - Schéma ULTRA-SIMPLE base de données RADIUS
--
-- Version: 3 février 2026 - SANS GROUPES (VERSION FINALE)
-- Auteur: GroupeNani - Optimisé par Perplexity
--
-- Description:
--   Schéma minimaliste pour authentification simple.
--   Tous les utilisateurs ont les MÊMES droits.
--   Pas besoin de groupes.
--
--   Tables utilisées:
--     - nas (clients RADIUS - routeur)
--     - radcheck (authentification utilisateurs)
--     - radreply (réponses utilisateurs - optionnel)
--     - radacct (comptabilité des sessions)
--     - radpostauth (logs d'authentification)
--
-- Utilisation:
--   $ sudo mysql -u root radius < radius/sql/create_tables.sql
--

USE radius;

-- ============================================
-- SUPPRESSION TOTALE DES TABLES DE GROUPES
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
-- 1. TABLE: nas (CLIENTS RADIUS)
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
  KEY nasname (nasname)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Routeur TP-Link
INSERT INTO nas (nasname, shortname, type, secret, description) VALUES
  ('192.168.10.1', 'TL-MR100', 'other', 'testing123', 'Routeur TP-Link TL-MR100');

-- ============================================
-- 2. TABLE: radcheck (AUTHENTIFICATION)
-- ============================================

CREATE TABLE radcheck (
  id int(11) unsigned NOT NULL auto_increment,
  username varchar(64) NOT NULL default '',
  attribute varchar(64) NOT NULL default '',
  op char(2) NOT NULL default ':=',
  value varchar(253) NOT NULL default '',
  PRIMARY KEY (id),
  KEY username (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- 3. TABLE: radreply (RÉPONSES - OPTIONNEL)
-- ============================================

CREATE TABLE radreply (
  id int(11) unsigned NOT NULL auto_increment,
  username varchar(64) NOT NULL default '',
  attribute varchar(64) NOT NULL default '',
  op char(2) NOT NULL default '=',
  value varchar(253) NOT NULL default '',
  PRIMARY KEY (id),
  KEY username (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- 4. TABLE: radacct (COMPTABILITÉ SESSIONS)
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
  PRIMARY KEY (radacctid),
  UNIQUE KEY acctuniqueid (acctuniqueid),
  KEY username (username),
  KEY acctsessionid (acctsessionid),
  KEY acctstarttime (acctstarttime),
  KEY nasipaddress (nasipaddress)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- 5. TABLE: radpostauth (LOGS)
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
-- 6. UTILISATEURS (TOUS LES MÊMES DROITS)
-- ============================================

-- Insérer les utilisateurs avec mot de passe
INSERT INTO radcheck (username, attribute, op, value) VALUES
  ('alice@gym.fr', 'Cleartext-Password', ':=', 'Alice@123!'),
  ('bob@gym.fr', 'Cleartext-Password', ':=', 'Bob@456!'),
  ('charlie@gym.fr', 'Cleartext-Password', ':=', 'Charlie@789!'),
  ('david@gym.fr', 'Cleartext-Password', ':=', 'David@2026!'),
  ('emma@gym.fr', 'Cleartext-Password', ':=', 'Emma@2026!');

-- Messages de bienvenue (optionnel)
INSERT INTO radreply (username, attribute, op, value) VALUES
  ('alice@gym.fr', 'Reply-Message', '=', 'Bienvenue Alice'),
  ('bob@gym.fr', 'Reply-Message', '=', 'Bienvenue Bob'),
  ('charlie@gym.fr', 'Reply-Message', '=', 'Bienvenue Charlie'),
  ('david@gym.fr', 'Reply-Message', '=', 'Bienvenue David'),
  ('emma@gym.fr', 'Reply-Message', '=', 'Bienvenue Emma');

-- ============================================
-- 7. VUE SIMPLE
-- ============================================

CREATE OR REPLACE VIEW v_users_simple AS
SELECT 
  rc.username,
  rc.value as password,
  rr.value as message
FROM radcheck rc
LEFT JOIN radreply rr ON rc.username = rr.username AND rr.attribute = 'Reply-Message'
WHERE rc.attribute = 'Cleartext-Password'
ORDER BY rc.username;

-- Vue sessions actives
CREATE OR REPLACE VIEW v_active_sessions AS
SELECT
  username,
  nasipaddress,
  acctstarttime,
  framedipaddress,
  callingstationid,
  TIMESTAMPDIFF(SECOND, acctstarttime, NOW()) as duration_seconds
FROM radacct
WHERE acctstoptime IS NULL
ORDER BY acctstarttime DESC;

-- ============================================
-- TERMINÉ
-- ============================================
-- Architecture:
--   - Fitness-Pro (WPA2-Enterprise) → Authentification via radcheck
--   - Fitness-Guest (WPA2-PSK) → Pas de RADIUS, mot de passe routeur
--
-- Flux:
--   1. Client WiFi → Routeur (192.168.10.1)
--   2. Routeur → RADIUS (192.168.10.100:1812)
--   3. RADIUS vérifie username/password dans radcheck
--   4. Si OK → Access-Accept
--   5. Tous les users ont les mêmes droits
--
