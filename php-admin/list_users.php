<?php
/**
 * list_users.php - Lister tous les utilisateurs RADIUS
 *
 * Fichier: php-admin/list_users.php
 * Auteur: GroupeNani
 * Date: 4 janvier 2026
 *
 * Description:
 *   Affiche la liste de tous les utilisateurs RADIUS créés.
 *   Inclut les informations: utilisateur, groupe, mot de passe.
 */

require_once 'config.php';

$users = [];
$error = '';

try {
    $pdo = get_db_connection();
    
    // Récupérer les utilisateurs avec leurs groupes
    $stmt = $pdo->prepare('
        SELECT 
            rc.id,
            rc.username,
            rc.value as password,
            rug.groupname,
            rc.attribute
        FROM radcheck rc
        LEFT JOIN radusergroup rug ON rc.username = rug.username
        WHERE rc.attribute IN ("Cleartext-Password", "User-Password")
        ORDER BY rc.username ASC
    ');
    $stmt->execute();
    $users = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
} catch (PDOException $e) {
    $error = 'Erreur lors de la récupération des utilisateurs: ' . $e->getMessage();
    log_error("Erreur list_users: " . $e->getMessage());
}

?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo escape_html(APP_TITLE); ?> - Lister Utilisateurs</title>
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
            max-width: 900px;
            margin: 40px auto;
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 40px rgba(0, 0, 0, 0.2);
            padding: 40px;
        }
        
        .header {
            margin-bottom: 30px;
            border-bottom: 3px solid #667eea;
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
        
        .stats {
            background: #f0f4ff;
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px;
            border-left: 4px solid #667eea;
        }
        
        .stats p {
            color: #333;
            font-weight: 500;
        }
        
        .error {
            background: #f8d7da;
            color: #721c24;
            padding: 15px;
            border-radius: 5px;
            border: 1px solid #f5c6cb;
            margin-bottom: 20px;
        }
        
        .table-wrapper {
            overflow-x: auto;
            margin-bottom: 20px;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
        }
        
        thead {
            background: #f5f5f5;
            border-bottom: 2px solid #ddd;
        }
        
        th {
            padding: 12px;
            text-align: left;
            font-weight: 600;
            color: #333;
            font-size: 13px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        td {
            padding: 12px;
            border-bottom: 1px solid #eee;
            font-size: 13px;
        }
        
        tbody tr:hover {
            background: #f9f9f9;
        }
        
        .username {
            font-weight: 500;
            color: #667eea;
            font-family: monospace;
        }
        
        .group {
            display: inline-block;
            padding: 4px 8px;
            border-radius: 3px;
            font-size: 11px;
            font-weight: 600;
        }
        
        .group.staff {
            background: #d4edda;
            color: #155724;
        }
        
        .group.guests {
            background: #cce5ff;
            color: #004085;
        }
        
        .group.managers {
            background: #f8d7da;
            color: #721c24;
        }
        
        .empty {
            text-align: center;
            padding: 40px;
            color: #999;
        }
        
        .empty-icon {
            font-size: 48px;
            margin-bottom: 10px;
        }
        
        .button-group {
            display: flex;
            gap: 10px;
        }
        
        a.button {
            padding: 10px 15px;
            background: #667eea;
            color: white;
            text-decoration: none;
            border-radius: 5px;
            font-size: 13px;
            transition: all 0.3s ease;
        }
        
        a.button:hover {
            background: #5568d3;
            transform: translateY(-2px);
        }
        
        a.button.secondary {
            background: #e9ecef;
            color: #333;
        }
        
        a.button.secondary:hover {
            background: #dee2e6;
        }
        
        .footer {
            text-align: center;
            padding-top: 20px;
            border-top: 1px solid #eee;
            color: #999;
            font-size: 12px;
        }
        
        @media (max-width: 600px) {
            .container {
                padding: 20px;
            }
            
            th, td {
                padding: 8px;
                font-size: 12px;
            }
            
            .button-group {
                flex-direction: column;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📋 Lister Utilisateurs</h1>
            <p>Tous les utilisateurs RADIUS créés dans la base de données</p>
        </div>
        
        <?php if ($error): ?>
            <div class="error">✗ <?php echo escape_html($error); ?></div>
        <?php endif; ?>
        
        <div class="stats">
            <p>👥 Total utilisateurs: <strong><?php echo count($users); ?></strong></p>
        </div>
        
        <?php if (empty($users)): ?>
            <div class="empty">
                <div class="empty-icon">📭</div>
                <p>Aucun utilisateur créé</p>
                <p style="font-size: 12px; color: #ccc; margin-top: 10px;">
                    <a href="add_user.php" style="color: #667eea; text-decoration: none;">Ajouter le premier utilisateur</a>
                </p>
            </div>
        <?php else: ?>
            <div class="table-wrapper">
                <table>
                    <thead>
                        <tr>
                            <th>Utilisateur</th>
                            <th>Groupe</th>
                            <th>Mot de passe</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($users as $user): ?>
                            <tr>
                                <td class="username"><?php echo escape_html($user['username']); ?></td>
                                <td>
                                    <span class="group <?php echo escape_html($user['groupname'] ?? 'staff'); ?>">
                                        <?php echo escape_html($user['groupname'] ?? 'N/A'); ?>
                                    </span>
                                </td>
                                <td>
                                    <code style="background: #f5f5f5; padding: 2px 6px; border-radius: 3px;">
                                        <?php echo escape_html(substr($user['password'], 0, 8) . '****'); ?>
                                    </code>
                                </td>
                                <td>
                                    <a href="delete_user.php?username=<?php echo urlencode($user['username']); ?>" 
                                       style="color: #e74c3c; text-decoration: none; font-size: 12px;">
                                        Supprimer
                                    </a>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        <?php endif; ?>
        
        <div class="button-group">
            <a href="add_user.php" class="button">➕ Ajouter Utilisateur</a>
            <a href="index.php" class="button secondary">← Retour</a>
        </div>
        
        <div class="footer">
            <p>SAE 5.01 © 2026 | Les mots de passe affichés sont tronqués pour la sécurité</p>
        </div>
    </div>
</body>
</html>
