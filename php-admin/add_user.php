<?php
/**
 * add_user.php - Ajouter un nouvel utilisateur RADIUS
 *
 * Fichier: php-admin/add_user.php
 * Auteur: GroupeNani
 * Date: 4 janvier 2026
 *
 * Description:
 *   Formulaire pour ajouter un nouvel utilisateur dans la base RADIUS.
 *   Crée l'entrée dans la table radcheck et radusergroup.
 */

require_once 'config.php';

$message = '';
$error = '';
$success = false;

// Traitement du formulaire
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = trim($_POST['username'] ?? '');
    $password = trim($_POST['password'] ?? '');
    $password_confirm = trim($_POST['password_confirm'] ?? '');
    $groupname = trim($_POST['groupname'] ?? 'staff');
    
    // Validations
    if (empty($username)) {
        $error = 'Le nom d\'utilisateur est requis';
    } elseif (!is_valid_email($username)) {
        $error = 'Le nom d\'utilisateur doit être au format: username@gym.fr';
    } elseif (empty($password)) {
        $error = 'Le mot de passe est requis';
    } elseif (!is_valid_password($password)) {
        $error = 'Le mot de passe doit contenir au moins ' . MIN_PASSWORD_LENGTH . ' caractères';
    } elseif ($password !== $password_confirm) {
        $error = 'Les mots de passe ne correspondent pas';
    } else {
        try {
            $pdo = get_db_connection();
            
            // Vérifier si l'utilisateur existe déjà
            $stmt = $pdo->prepare('SELECT id FROM radcheck WHERE username = ?');
            $stmt->execute([$username]);
            
            if ($stmt->rowCount() > 0) {
                $error = 'Cet utilisateur existe déjà';
            } else {
                // Insérer dans radcheck
                $stmt = $pdo->prepare('
                    INSERT INTO radcheck (username, attribute, op, value)
                    VALUES (?, ?, ?, ?)
                ');
                $stmt->execute([
                    $username,
                    'Cleartext-Password',
                    ':=',
                    $password
                ]);
                
                // Insérer dans radusergroup
                $stmt = $pdo->prepare('
                    INSERT INTO radusergroup (username, groupname, priority)
                    VALUES (?, ?, ?)
                ');
                $stmt->execute([
                    $username,
                    $groupname,
                    1
                ]);
                
                $success = true;
                $message = "Utilisateur '$username' ajouté avec succès au groupe '$groupname'";
                log_info("Utilisateur ajouté: $username (groupe: $groupname)");
                
                // Réinitialiser le formulaire
                $username = '';
                $password = '';
                $password_confirm = '';
            }
        } catch (PDOException $e) {
            $error = 'Erreur lors de l\'ajout: ' . $e->getMessage();
            log_error("Erreur ajout utilisateur: " . $e->getMessage());
        }
    }
}

?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo escape_html(APP_TITLE); ?> - Ajouter Utilisateur</title>
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
        
        .form-group {
            margin-bottom: 20px;
        }
        
        label {
            display: block;
            margin-bottom: 8px;
            color: #333;
            font-weight: 500;
            font-size: 14px;
        }
        
        input[type="text"],
        input[type="password"],
        select {
            width: 100%;
            padding: 10px;
            border: 1px solid #ddd;
            border-radius: 5px;
            font-size: 14px;
            font-family: inherit;
        }
        
        input[type="text"]:focus,
        input[type="password"]:focus,
        select:focus {
            outline: none;
            border-color: #667eea;
            box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
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
        
        .btn-primary {
            background: #667eea;
            color: white;
        }
        
        .btn-primary:hover {
            background: #5568d3;
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(102, 126, 234, 0.3);
        }
        
        .btn-secondary {
            background: #e9ecef;
            color: #333;
        }
        
        .btn-secondary:hover {
            background: #dee2e6;
        }
        
        .form-hint {
            font-size: 12px;
            color: #666;
            margin-top: 5px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>➕ Ajouter Utilisateur</h1>
            <p>Créer un nouvel utilisateur RADIUS pour l'authentification Wi-Fi</p>
        </div>
        
        <?php if ($success): ?>
            <div class="message success">✓ <?php echo escape_html($message); ?></div>
        <?php elseif ($error): ?>
            <div class="message error">✗ <?php echo escape_html($error); ?></div>
        <?php endif; ?>
        
        <form method="POST">
            <!-- Utilisateur -->
            <div class="form-group">
                <label for="username">Nom d'utilisateur *</label>
                <input 
                    type="text" 
                    id="username" 
                    name="username" 
                    placeholder="alice@gym.fr"
                    value="<?php echo escape_html($username ?? ''); ?>"
                    required
                >
                <div class="form-hint">Format: username@gym.fr</div>
            </div>
            
            <!-- Mot de passe -->
            <div class="form-group">
                <label for="password">Mot de passe *</label>
                <input 
                    type="password" 
                    id="password" 
                    name="password" 
                    placeholder="••••••••"
                    required
                >
                <div class="form-hint">Minimum <?php echo MIN_PASSWORD_LENGTH; ?> caractères</div>
            </div>
            
            <!-- Confirmation mot de passe -->
            <div class="form-group">
                <label for="password_confirm">Confirmer mot de passe *</label>
                <input 
                    type="password" 
                    id="password_confirm" 
                    name="password_confirm" 
                    placeholder="••••••••"
                    required
                >
            </div>
            
            <!-- Groupe -->
            <div class="form-group">
                <label for="groupname">Groupe *</label>
                <select id="groupname" name="groupname" required>
                    <option value="staff">Staff (802.1X)</option>
                    <option value="guests">Guests (Invités)</option>
                    <option value="managers">Managers (Administrateurs)</option>
                </select>
                <div class="form-hint">Détermine les permissions d'accès Wi-Fi</div>
            </div>
            
            <!-- Boutons -->
            <div class="button-group">
                <button type="submit" class="btn-primary">Créer Utilisateur</button>
                <a href="index.php" class="button btn-secondary">Retour</a>
            </div>
        </form>
    </div>
</body>
</html>
