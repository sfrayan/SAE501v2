<?php
/**
 * index.php - Page d'accueil gestionnaire RADIUS
 *
 * Fichier: php-admin/index.php
 * Auteur: GroupeNani
 * Date: 4 janvier 2026
 *
 * Description:
 *   Page d'accueil du gestionnaire d'utilisateurs RADIUS.
 *   Menu principal permettant d'accéder aux différentes fonctions.
 */

require_once 'config.php';

// Titre de la page
$page_title = 'Accueil';

?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo escape_html(APP_TITLE); ?> - Accueil</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        
        .container {
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 40px rgba(0, 0, 0, 0.2);
            max-width: 800px;
            width: 100%;
            padding: 40px;
        }
        
        .header {
            text-align: center;
            margin-bottom: 40px;
            border-bottom: 3px solid #667eea;
            padding-bottom: 20px;
        }
        
        .header h1 {
            color: #333;
            margin-bottom: 10px;
            font-size: 28px;
        }
        
        .header p {
            color: #666;
            font-size: 14px;
        }
        
        .version {
            display: inline-block;
            background: #667eea;
            color: white;
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 12px;
            margin-left: 10px;
        }
        
        .menu {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .menu-item {
            display: block;
            padding: 25px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            text-decoration: none;
            border-radius: 8px;
            transition: all 0.3s ease;
            text-align: center;
            box-shadow: 0 4px 15px rgba(102, 126, 234, 0.3);
        }
        
        .menu-item:hover {
            transform: translateY(-5px);
            box-shadow: 0 8px 25px rgba(102, 126, 234, 0.5);
        }
        
        .menu-item h3 {
            font-size: 18px;
            margin-bottom: 10px;
        }
        
        .menu-item p {
            font-size: 13px;
            opacity: 0.9;
        }
        
        .icon {
            font-size: 32px;
            margin-bottom: 10px;
        }
        
        .info-box {
            background: #f0f4ff;
            border-left: 4px solid #667eea;
            padding: 20px;
            border-radius: 5px;
            margin-bottom: 20px;
        }
        
        .info-box h3 {
            color: #667eea;
            margin-bottom: 10px;
        }
        
        .info-box p {
            color: #666;
            line-height: 1.6;
            font-size: 14px;
        }
        
        .info-box code {
            background: white;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: monospace;
            color: #e74c3c;
        }
        
        .footer {
            text-align: center;
            color: #999;
            font-size: 12px;
            border-top: 1px solid #eee;
            padding-top: 20px;
        }
        
        .status {
            display: flex;
            gap: 15px;
            margin-bottom: 20px;
            flex-wrap: wrap;
        }
        
        .status-item {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 8px 12px;
            background: #f5f5f5;
            border-radius: 5px;
            font-size: 13px;
        }
        
        .status-dot {
            width: 8px;
            height: 8px;
            border-radius: 50%;
            background: #27ae60;
        }
        
        @media (max-width: 600px) {
            .container {
                padding: 20px;
            }
            
            .header h1 {
                font-size: 22px;
            }
            
            .menu {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <!-- En-tête -->
        <div class="header">
            <h1>
                🔐 Gestionnaire RADIUS
                <span class="version">v<?php echo APP_VERSION; ?></span>
            </h1>
            <p><?php echo escape_html(APP_TITLE); ?></p>
        </div>
        
        <!-- Statut système -->
        <div class="status">
            <div class="status-item">
                <span class="status-dot"></span>
                <span><strong>Base de données:</strong> Connectée</span>
            </div>
            <div class="status-item">
                <span class="status-dot"></span>
                <span><strong>FreeRADIUS:</strong> Actif</span>
            </div>
            <div class="status-item">
                <span class="status-dot"></span>
                <span><strong>Interface:</strong> Prête</span>
            </div>
        </div>
        
        <!-- Boîte info -->
        <div class="info-box">
            <h3>📋 À propos</h3>
            <p>
                Bienvenue dans le gestionnaire d'utilisateurs RADIUS SAE 5.01.
                Cette application permet de gérer les utilisateurs d'authentification Wi-Fi Enterprise (802.1X).
                Utilisez les fonctions ci-dessous pour <strong>ajouter, supprimer ou lister</strong> les utilisateurs.
            </p>
        </div>
        
        <!-- Menu principal -->
        <div class="menu">
            <!-- Ajouter utilisateur -->
            <a href="add_user.php" class="menu-item">
                <div class="icon">➕</div>
                <h3>Ajouter Utilisateur</h3>
                <p>Créer un nouvel utilisateur RADIUS</p>
            </a>
            
            <!-- Lister utilisateurs -->
            <a href="list_users.php" class="menu-item">
                <div class="icon">📋</div>
                <h3>Lister Utilisateurs</h3>
                <p>Voir tous les utilisateurs créés</p>
            </a>
            
            <!-- Supprimer utilisateur -->
            <a href="delete_user.php" class="menu-item">
                <div class="icon">🗑️</div>
                <h3>Supprimer Utilisateur</h3>
                <p>Supprimer un utilisateur existant</p>
            </a>
        </div>
        
        <!-- Boîte informations -->
        <div class="info-box">
            <h3>ℹ️ Informations Techniques</h3>
            <p>
                <strong>Base données:</strong> <code><?php echo escape_html(DB_NAME); ?></code> sur <code><?php echo escape_html(DB_HOST); ?></code><br>
                <strong>Utilisateurs actifs:</strong> Voir dans "Lister Utilisateurs"<br>
                <strong>Format email:</strong> <code>username@gym.fr</code><br>
                <strong>Format mot de passe:</strong> Minimum <?php echo MIN_PASSWORD_LENGTH; ?> caractères
            </p>
        </div>
        
        <!-- Pied de page -->
        <div class="footer">
            <p>
                SAE 5.01 © 2026 GroupeNani | 
                <a href="#" style="color: #667eea; text-decoration: none;">Aide</a> | 
                <a href="#" style="color: #667eea; text-decoration: none;">Documentation</a>
            </p>
        </div>
    </div>
</body>
</html>
