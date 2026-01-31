<?php
/**
 * delete_user.php - Supprimer un utilisateur RADIUS
 *
 * Fichier: php-admin/delete_user.php
 * Auteur: GroupeNani
 * Date: 4 janvier 2026
 *
 * Description:
 *   Supprime un utilisateur RADIUS de la base de données.
 *   Supprime les entrées dans radcheck et radusergroup.
 */

require_once 'config.php';

$username = isset($_GET['username']) ? trim($_GET['username']) : '';
$message = '';
$error = '';
$success = false;
$user_exists = false;
$user_data = null;

// Récupérer les infos utilisateur
if (!empty($username)) {
    try {
        $pdo = get_db_connection();
        
        $stmt = $pdo->prepare('
            SELECT 
                rc.username,
                rug.groupname
            FROM radcheck rc
            LEFT JOIN radusergroup rug ON rc.username = rug.username
            WHERE rc.username = ? AND rc.attribute IN ("Cleartext-Password", "User-Password")
            LIMIT 1
        ');
        $stmt->execute([$username]);
        $user_data = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if ($user_data) {
            $user_exists = true;
        } else {
            $error = 'Utilisateur non trouvé';
        }
    } catch (PDOException $e) {
        $error = 'Erreur lors de la récupération: ' . $e->getMessage();
        log_error("Erreur delete_user GET: " . $e->getMessage());
    }
}

// Traitement de la suppression
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = trim($_POST['username'] ?? '');
    $confirm = isset($_POST['confirm']) ? true : false;
    
    if (empty($username)) {
        $error = 'Le nom d\'utilisateur est requis';
    } elseif (!$confirm) {
        $error = 'Vous devez confirmer la suppression';
    } else {
        try {
            $pdo = get_db_connection();
            
            // Vérifier que l'utilisateur existe
            $stmt = $pdo->prepare('SELECT id FROM radcheck WHERE username = ?');
            $stmt->execute([$username]);
            
            if ($stmt->rowCount() === 0) {
                $error = 'Utilisateur non trouvé';
            } else {
                // Supprimer de radusergroup
                $stmt = $pdo->prepare('DELETE FROM radusergroup WHERE username = ?');
                $stmt->execute([$username]);
                
                // Supprimer de radcheck
                $stmt = $pdo->prepare('DELETE FROM radcheck WHERE username = ?');
                $stmt->execute([$username]);
                
                // Supprimer de radreply (si existe)
                $stmt = $pdo->prepare('DELETE FROM radreply WHERE username = ?');
                $stmt->execute([$username]);
                
                $success = true;
                $message = "Utilisateur '$username' supprimé avec succès";
                log_info("Utilisateur supprimé: $username");
                $user_exists = false;
            }
        } catch (PDOException $e) {
            $error = 'Erreur lors de la suppression: ' . $e->getMessage();
            log_error("Erreur suppression utilisateur: " . $e->getMessage());
        }
    }
}

?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo escape_html(APP_TITLE); ?> - Supprimer Utilisateur</title>
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
            padding: 20px;
        }
        
        .container {
            max-width: 600px;
            margin: 40px auto;
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 40px rgba(0, 0, 0, 0.2);
            padding: 40px;
        }
        
        .header {
            margin-bottom: 30px;
            border-bottom: 3px solid #e74c3c;
            padding-bottom: 15px;
        }
        
        .header h1 {
            color: #333;
            font-size: 24px;
            margin-bottom: 5px;
        }
        
        .header p {
            color: #666;
            font-size: 14px;
        }
        
        .message {
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px;
            display: none;
        }
        
        .message.success {
            background: #d4edda;
            color: #155724;
            border: 1px solid #c3e6cb;
            display: block;
        }
        
        .message.error {
            background: #f8d7da;
            color: #721c24;
            border: 1px solid #f5c6cb;
            display: block;
        }
        
        .warning-box {
            background: #fff3cd;
            border: 1px solid #ffc107;
            color: #856404;
            padding: 20px;
            border-radius: 5px;
            margin-bottom: 20px;
        }
        
        .warning-box h3 {
            margin-bottom: 10px;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        
        .warning-box p {
            font-size: 13px;
            line-height: 1.6;
        }
        
        .user-info {
            background: #f5f5f5;
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px;
        }
        
        .user-info p {
            margin: 8px 0;
            font-size: 13px;
        }
        
        .user-info strong {
            color: #333;
        }
        
        .form-group {
            margin-bottom: 20px;
        }
        
        .checkbox {
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .checkbox input[type="checkbox"] {
            width: 18px;
            height: 18px;
            cursor: pointer;
        }
        
        .checkbox label {
            margin: 0;
            cursor: pointer;
            font-size: 14px;
        }
        
        .button-group {
            display: flex;
            gap: 10px;
            margin-top: 30px;
        }
        
        button,
        a.button {
            flex: 1;
            padding: 12px;
            border: none;
            border-radius: 5px;
            font-size: 14px;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.3s ease;
            text-decoration: none;
            display: inline-block;
            text-align: center;
        }
        
        .btn-danger {
            background: #e74c3c;
            color: white;
        }
        
        .btn-danger:hover:not(:disabled) {
            background: #c0392b;
            transform: translateY(-2px);
        }
        
        .btn-danger:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }
        
        .btn-secondary {
            background: #e9ecef;
            color: #333;
        }
        
        .btn-secondary:hover {
            background: #dee2e6;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🗑️ Supprimer Utilisateur</h1>
            <p>Suppression définitive d'un utilisateur RADIUS</p>
        </div>
        
        <?php if ($success): ?>
            <div class="message success">
                ✓ <?php echo escape_html($message); ?>
            </div>
            <div style="text-align: center; margin-top: 30px;">
                <a href="list_users.php" class="button" style="background: #667eea; color: white; text-decoration: none; padding: 12px 30px; border-radius: 5px;">
                    Retour à la liste
                </a>
            </div>
        <?php elseif (!$user_exists && $username): ?>
            <div class="message error">
                ✗ <?php echo escape_html($error); ?>
            </div>
            <div style="text-align: center; margin-top: 30px;">
                <a href="list_users.php" class="button" style="background: #667eea; color: white; text-decoration: none; padding: 12px 30px; border-radius: 5px;">
                    Voir les utilisateurs
                </a>
            </div>
        <?php else: ?>
            <?php if ($error): ?>
                <div class="message error">✗ <?php echo escape_html($error); ?></div>
            <?php endif; ?>
            
            <?php if ($user_exists && $user_data): ?>
                <div class="warning-box">
                    <h3>⚠️ Attention!</h3>
                    <p>
                        Vous êtes sur le point de <strong>supprimer définitivement</strong> cet utilisateur.
                        Cette action <strong>ne peut pas être annulée</strong>. L'utilisateur ne pourra plus
                        se connecter au Wi-Fi Enterprise.
                    </p>
                </div>
                
                <div class="user-info">
                    <p><strong>Utilisateur:</strong> <?php echo escape_html($user_data['username']); ?></p>
                    <p><strong>Groupe:</strong> <?php echo escape_html($user_data['groupname'] ?? 'N/A'); ?></p>
                </div>
                
                <form method="POST">
                    <input type="hidden" name="username" value="<?php echo escape_html($user_data['username']); ?>">
                    
                    <div class="form-group">
                        <div class="checkbox">
                            <input 
                                type="checkbox" 
                                id="confirm" 
                                name="confirm"
                                required
                            >
                            <label for="confirm">
                                Je confirme la suppression définitive de <strong><?php echo escape_html($user_data['username']); ?></strong>
                            </label>
                        </div>
                    </div>
                    
                    <div class="button-group">
                        <button type="submit" class="btn-danger">Supprimer Définitivement</button>
                        <a href="list_users.php" class="button btn-secondary">Annuler</a>
                    </div>
                </form>
            <?php else: ?>
                <div style="text-align: center; padding: 40px 0; color: #999;">
                    <p>Aucun utilisateur sélectionné</p>
                    <div style="margin-top: 20px;">
                        <a href="list_users.php" class="button" style="background: #667eea; color: white; text-decoration: none; padding: 12px 30px; border-radius: 5px; display: inline-block;">
                            Voir les utilisateurs
                        </a>
                    </div>
                </div>
            <?php endif; ?>
        <?php endif; ?>
    </div>
</body>
</html>
