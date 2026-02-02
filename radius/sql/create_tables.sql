--
-- create_tables.sql - Schéma SIMPLIFIÉ base de données RADIUS (SANS GROUPES)
--
-- Version: 2 février 2026 - VERSION SIMPLIFIÉE
-- Auteur: GroupeNani
--
-- Description:
--   Crée un schéma minimaliste pour FreeRADIUS avec MySQL.
--   SANS système de groupes pour éviter les warnings.
--
--   Tables activées:
--     - nas (clients RADIUS)
--     - radcheck (authentification utilisateurs)
--     - radreply (réponses utilisateurs)
--     - radacct (accounting/sessions)
--     - radpostauth (logs post-auth)
--
--   Tables DÉSACTIVÉES (plus de groupes):
--     ❌ radusergroup
--     ❌ radgroupcheck
--     ❌ radgroupreply
--
-- Utilisation:
--   $ sudo mysql -u root -p radius < radius/sql/create_tables.sql
--

USE radius;

-- ============================================
-- SUPPRIMER LES ANCIENNES TABLES DE GROUPES
-- ============================================

DROP TABLE IF EXISTS radusergroup;
DROP TABLE IF EXISTS radgroupcheck;
DROP TABLE IF EXISTS radgroupreply;
DROP VIEW IF EXISTS v_users_with_groups;

-- ============================================
-- 0. TABLE: nas (CLIENTS RADIUS)
-- ============================================

CREATE TABLE IF NOT EXISTS nas (
  id int(11) unsigned NOT NULL auto_increment,
  nasname varchar(128) NOT NULL default '',
  shortname varchar(32) default NULL,
  type varchar(30) default 'other',
  ports int(5) default NULL,
  secret varchar(60) NOT NULL default 'SECRET',
  server varchar(64) default NULL,
  community varchar(50) default NULL,
  description varchar(200) default 'RADIUS Client',
  PRIMARY KEY  (id),
  KEY nasname (nasname),
  KEY shortname (shortname)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Insérer le routeur TL-MR100
INSERT IGNORE INTO nas (nasname, shortname, type, secret, description) VALUES
  ('192.168.10.1', 'TL-MR100', 'other', 'testing123', 'Routeur TP-Link TL-MR100');

-- ============================================
-- 1. TABLE: radcheck (AUTHENTIFICATION)
-- ============================================

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
-- 2. TABLE: radreply (RÉPONSES)
-- ============================================

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
-- 3. TABLE: radacct (ACCOUNTING/SESSIONS)
-- ============================================

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
-- 4. TABLE: radpostauth (LOGS POST-AUTH)
-- ============================================

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
-- 5. DONNÉES INITIALES - UTILISATEURS
-- ============================================

-- Supprimer les utilisateurs existants
DELETE FROM radcheck WHERE username IN (
  'alice@gym.fr', 'bob@gym.fr', 'charlie@gym.fr', 'david@gym.fr', 'emma@gym.fr'
);

DELETE FROM radreply WHERE username IN (
  'alice@gym.fr', 'bob@gym.fr', 'charlie@gym.fr', 'david@gym.fr', 'emma@gym.fr'
);

-- Insérer les utilisateurs (authentification directe, SANS groupes)
INSERT INTO radcheck (username, attribute, op, value) VALUES
  ('alice@gym.fr', 'Cleartext-Password', ':=', 'Alice@123!'),
  ('bob@gym.fr', 'Cleartext-Password', ':=', 'Bob@456!'),
  ('charlie@gym.fr', 'Cleartext-Password', ':=', 'Charlie@789!'),
  ('david@gym.fr', 'Cleartext-Password', ':=', 'David@2026!'),
  ('emma@gym.fr', 'Cleartext-Password', ':=', 'Emma@2026!');

-- Ajouter des attributs de réponse pour chaque utilisateur (directement)
INSERT INTO radreply (username, attribute, op, value) VALUES
  ('alice@gym.fr', 'Reply-Message', '=', 'Bienvenue Alice (Staff)'),
  ('bob@gym.fr', 'Reply-Message', '=', 'Bienvenue Bob (Staff)'),
  ('charlie@gym.fr', 'Reply-Message', '=', 'Bienvenue Charlie (Guest)'),
  ('david@gym.fr', 'Reply-Message', '=', 'Bienvenue David (Manager)'),
  ('emma@gym.fr', 'Reply-Message', '=', 'Bienvenue Emma (Staff)');

-- ============================================
-- 6. VUE SIMPLIFIÉE
-- ============================================

-- Vue: Tous les utilisateurs avec leurs attributs
CREATE OR REPLACE VIEW v_users_simple AS
SELECT DISTINCT
  rc.username,
  rc.attribute as check_attribute,
  rc.value as check_value,
  rr.attribute as reply_attribute,
  rr.value as reply_value
FROM radcheck rc
LEFT JOIN radreply rr ON rc.username = rr.username
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

-- ✅ VERSION SIMPLIFIÉE:
--   - Pas de tables de groupes (radusergroup, radgroupcheck, radgroupreply)
--   - Authentification directe utilisateur via radcheck
--   - Réponses directes via radreply
--   - Plus de warnings "group_membership_query"
--
-- Opérateurs (op):
--   :=  = Défini (remplace)
--   =   = Ajouter
--   ==  = Comparer (condition)
--
-- Attributs courants:
--   Cleartext-Password: Mot de passe en clair (tests seulement)
--   Reply-Message: Message au client
--   Session-Timeout: Durée max session (sec)
--
-- Flux authentification:
--   1. Client envoie identifiants
--   2. FreeRADIUS cherche dans radcheck
--   3. Vérifie mot de passe
--   4. Si OK, cherche dans radreply
--   5. Retourne Access-Accept avec attributs
--
