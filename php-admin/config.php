<?php
/**
 * config.php - Configuration de l'application PHP-Admin RADIUS
 *
 * Fichier: php-admin/config.php
 * Auteur: GroupeNani
 * Date: 4 janvier 2026
 *
 * Description:
 *   Configuration centralisée pour l'application de gestion des utilisateurs RADIUS.
 *   Contient les identifiants de connexion à la base de données MySQL.
 *
 * Utilisation:
 *   Inclus automatiquement par les autres fichiers PHP
 *   À protéger: chmod 640 + .htaccess
 *
 * Sécurité:
 *   - Ne JAMAIS commiter avec vrais identifiants en production
 *   - Utiliser variables d'environnement en production
 *   - Protéger ce fichier avec .htaccess
 */

// ============================================
// CONFIGURATION BASE DE DONNÉES RADIUS
// ============================================

// Serveur MySQL
define('DB_HOST', 'localhost');

// Port MySQL (3306 par défaut)
define('DB_PORT', 3306);

// Base de données
define('DB_NAME', 'radius');

// Utilisateur MySQL (créé par init_appuser.sql)
define('DB_USER', 'radius_app');

// Mot de passe MySQL
define('DB_PASS', 'RadiusAppPass!2026');

// Charset
define('DB_CHARSET', 'utf8mb4');

// ============================================
// CONFIGURATION APPLICATION
// ============================================

// Titre de l'application
define('APP_TITLE', 'SAE 5.01 - Gestionnaire Utilisateurs RADIUS');

// Version
define('APP_VERSION', '1.0');

// URL de base
define('APP_BASE_URL', 'http://192.168.10.254/php-admin/');

// Fuseau horaire
define('TIMEZONE', 'Europe/Paris');

// ============================================
// CONFIGURATION SÉCURITÉ
// ============================================

// Activer mode debug (false en production)
define('DEBUG_MODE', false);

// Longueur minimum mot de passe
define('MIN_PASSWORD_LENGTH', 8);

// Pattern validation email
define('EMAIL_PATTERN', '/^[a-zA-Z0-9._%+-]+@gym\.fr$/');

// Nombre d'utilisateurs par page (pagination)
define('USERS_PER_PAGE', 10);

// ============================================
// CONFIGURATION LOGGING
// ============================================

// Dossier logs
define('LOG_DIR', '/var/log/php-admin/');

// Activer logging
define('ENABLE_LOGGING', true);

// ============================================
// FONCTIONS UTILITAIRES
// ============================================

/**
 * Récupère la connexion à la base de données
 * @return PDO|null Connexion PDO ou null en cas d'erreur
 */
function get_db_connection() {
    try {
        $dsn = 'mysql:host=' . DB_HOST . ':' . DB_PORT . ';dbname=' . DB_NAME . ';charset=' . DB_CHARSET;
        $pdo = new PDO($dsn, DB_USER, DB_PASS);
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        return $pdo;
    } catch (PDOException $e) {
        log_error('Erreur connexion DB: ' . $e->getMessage());
        if (DEBUG_MODE) {
            die('Erreur connexion: ' . $e->getMessage());
        }
        die('Erreur de connexion à la base de données');
    }
}

/**
 * Enregistre un message dans les logs
 * @param string $level Niveau (ERROR, WARNING, INFO)
 * @param string $message Message à enregistrer
 */
function log_message($level, $message) {
    if (!ENABLE_LOGGING) return;
    
    if (!is_dir(LOG_DIR)) {
        mkdir(LOG_DIR, 0755, true);
    }
    
    $log_file = LOG_DIR . date('Y-m-d') . '.log';
    $timestamp = date('Y-m-d H:i:s');
    $log_entry = "[$timestamp] [$level] $message\n";
    
    file_put_contents($log_file, $log_entry, FILE_APPEND);
}

/**
 * Enregistre une erreur
 */
function log_error($message) {
    log_message('ERROR', $message);
}

/**
 * Enregistre un avertissement
 */
function log_warning($message) {
    log_message('WARNING', $message);
}

/**
 * Enregistre une info
 */
function log_info($message) {
    log_message('INFO', $message);
}

/**
 * Échappe une chaîne pour éviter injection HTML
 */
function escape_html($text) {
    return htmlspecialchars($text, ENT_QUOTES, 'UTF-8');
}

/**
 * Valide le format email RADIUS (username@gym.fr)
 */
function is_valid_email($email) {
    return preg_match(EMAIL_PATTERN, $email) === 1;
}

/**
 * Valide la force du mot de passe
 */
function is_valid_password($password) {
    return strlen($password) >= MIN_PASSWORD_LENGTH;
}

/**
 * Configure le fuseau horaire
 */
date_default_timezone_set(TIMEZONE);

// ============================================
// NOTES SÉCURITÉ
// ============================================

/*
 * EN PRODUCTION:
 * 1. Utiliser variables d'environnement:
 *    define('DB_USER', getenv('DB_USER'));
 *    define('DB_PASS', getenv('DB_PASS'));
 *
 * 2. Protéger ce fichier:
 *    chmod 640 /var/www/html/php-admin/config.php
 *
 * 3. Ajouter .htaccess:
 *    <Files "config.php">
 *        Order Allow,Deny
 *        Deny from all
 *    </Files>
 *
 * 4. HTTPS obligatoire
 *
 * 5. Authentification admin requise
 *
 * 6. Logs audit détaillés
 */

?>
