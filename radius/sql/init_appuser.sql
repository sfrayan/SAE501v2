--
-- init_appuser.sql - Création utilisateur application MySQL RADIUS
--
-- Fichier: radius/sql/init_appuser.sql
-- Auteur: GroupeNani
-- Date: 4 janvier 2026
--
-- Description:
--   Script SQL pour créer l'utilisateur MySQL dédié à l'application
--   FreeRADIUS. À exécuter AVANT create_tables.sql.
--
-- Utilisation:
--   $ sudo mysql -u root -p < radius/sql/init_appuser.sql
--

-- ============================================
-- UTILISATEUR APPLICATION
-- ============================================

-- Créer l'utilisateur MySQL pour FreeRADIUS
-- Format: username@hostname avec password fort
CREATE USER IF NOT EXISTS 'radius_app'@'localhost' IDENTIFIED BY 'RadiusAppPass!2026';

-- Créer la base de données RADIUS
CREATE DATABASE IF NOT EXISTS radius CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Accorder les permissions sur la base radius
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, INDEX, ALTER 
  ON radius.* 
  TO 'radius_app'@'localhost';

-- Accorder SELECT sur mysql.user pour vérification (optionnel)
-- GRANT SELECT ON mysql.* TO 'radius_app'@'localhost';

-- Appliquer les changements
FLUSH PRIVILEGES;

-- ============================================
-- VÉRIFICATION
-- ============================================

-- Afficher l'utilisateur créé
SELECT user, host, authentication_string FROM mysql.user WHERE user='radius_app';

-- Afficher les permissions
SHOW GRANTS FOR 'radius_app'@'localhost';

-- ============================================
-- NOTES
-- ============================================

-- Identifiants:
--   Utilisateur: radius_app
--   Mot de passe: RadiusAppPass!2026
--   Base: radius
--
-- À utiliser dans:
--   - Configuration FreeRADIUS (modules/sql)
--   - Application PHP pour gestion utilisateurs
--   - Scripts backup/restore
--
-- En cas de changement de password:
--   ALTER USER 'radius_app'@'localhost' IDENTIFIED BY 'NewPassword!';
--   FLUSH PRIVILEGES;
--
