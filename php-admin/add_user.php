<?php
/**
 * add_user.php - Ajouter utilisateur RADIUS
 * Version: 2.0 (avec journalisation Wazuh)
 */

include 'config.php';

// Fonction de journalisation pour Wazuh
function log_to_wazuh($action, $user, $status, $details = '') {
    $message = "PHP-Admin: $action | User: $user | Status: $status";
    if ($details) {
        $message .= " | Details: $details";
    }
    openlog('php-admin', LOG_PID, LOG_LOCAL0);
    syslog(LOG_INFO, $message);
    closelog();
}

$error = '';
$success = '';

if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    $username = $_POST['username'] ?? '';
    $password = $_POST['password'] ?? '';
    $email = $_POST['email'] ?? '';
    
    // Validation
    if (empty($username) || empty($password)) {
        $error = 'Nom d\'utilisateur et mot de passe requis';
        log_to_wazuh('ADD_USER_FAILED', $username, 'VALIDATION_ERROR', $error);
    } else {
        // Connexion MySQL
        $conn = new mysqli(DB_HOST, DB_USER, DB_PASS, DB_NAME);
        if ($conn->connect_error) {
            $error = 'Erreur de connexion: ' . $conn->connect_error;
            log_to_wazuh('ADD_USER_FAILED', $username, 'DB_ERROR', $error);
        } else {
            // Vérifier l'existence
            $sql_check = "SELECT id FROM radcheck WHERE username = ?";
            $stmt = $conn->prepare($sql_check);
            $stmt->bind_param('s', $username);
            $stmt->execute();
            if ($stmt->get_result()->num_rows > 0) {
                $error = 'Utilisateur déjà existant';
                log_to_wazuh('ADD_USER_FAILED', $username, 'DUPLICATE', $error);
            } else {
                // Ajouter utilisateur
                $sql_insert = "INSERT INTO radcheck (username, attribute, op, value) VALUES (?, 'User-Password', ':=', ?)";
                $stmt = $conn->prepare($sql_insert);
                $stmt->bind_param('ss', $username, $password);
                
                if ($stmt->execute()) {
                    $success = 'Utilisateur ajouté avec succès';
                    log_to_wazuh('ADD_USER_SUCCESS', $username, 'SUCCESS', "Email: $email");
                    
                    // Ajouter email si fourni
                    if (!empty($email)) {
                        $sql_email = "INSERT INTO radcheck (username, attribute, op, value) VALUES (?, 'Email', ':=', ?)";
                        $stmt = $conn->prepare($sql_email);
                        $stmt->bind_param('ss', $username, $email);
                        $stmt->execute();
                    }
                } else {
                    $error = 'Erreur lors de l\'insertion: ' . $stmt->error;
                    log_to_wazuh('ADD_USER_FAILED', $username, 'INSERT_ERROR', $error);
                }
            }
            $conn->close();
        }
    }
}
?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Ajouter Utilisateur - PHP-Admin SAE 5.01</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 600px; margin: auto; background: white; padding: 20px; border-radius: 5px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #0066cc; padding-bottom: 10px; }
        .form-group { margin: 15px 0; }
        label { display: block; font-weight: bold; margin-bottom: 5px; color: #333; }
        input[type="text"], input[type="password"], input[type="email"] { width: 100%; padding: 8px; border: 1px solid #ddd; border-radius: 3px; box-sizing: border-box; }
        input[type="submit"] { background: #0066cc; color: white; padding: 10px 20px; border: none; border-radius: 3px; cursor: pointer; font-weight: bold; }
        input[type="submit"]:hover { background: #0052a3; }
        .success { color: green; padding: 10px; background: #e8f5e9; border: 1px solid #4caf50; border-radius: 3px; margin: 10px 0; }
        .error { color: red; padding: 10px; background: #ffebee; border: 1px solid #f44336; border-radius: 3px; margin: 10px 0; }
        a { color: #0066cc; text-decoration: none; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Ajouter Nouvel Utilisateur</h1>
        
        <?php if ($error): ?>
            <div class="error">❌ <?php echo htmlspecialchars($error); ?></div>
        <?php endif; ?>
        
        <?php if ($success): ?>
            <div class="success">✅ <?php echo htmlspecialchars($success); ?></div>
        <?php endif; ?>
        
        <form method="POST">
            <div class="form-group">
                <label>Nom d'utilisateur (email):</label>
                <input type="email" name="username" required placeholder="alice@gym.fr">
            </div>
            
            <div class="form-group">
                <label>Mot de passe:</label>
                <input type="password" name="password" required placeholder="Minimum 8 caractères">
            </div>
            
            <div class="form-group">
                <label>Email (optionnel):</label>
                <input type="email" name="email" placeholder="alice@example.com">
            </div>
            
            <input type="submit" value="Ajouter Utilisateur">
        </form>
        
        <hr>
        <p><a href="index.php">← Retour</a> | <a href="list_users.php">Voir les utilisateurs →</a></p>
    </div>
</body>
</html>