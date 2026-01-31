<?php
/**
 * delete_user.php - Supprimer utilisateur RADIUS
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
    syslog(LOG_WARNING, $message);
    closelog();
}

$error = '';
$success = '';

if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    $username = $_POST['username'] ?? '';
    $confirm = $_POST['confirm'] ?? '';
    
    // Vérifier la confirmation
    if ($confirm != 'yes') {
        $error = 'Veuillez confirmer la suppression';
        log_to_wazuh('DELETE_USER_FAILED', $username, 'NO_CONFIRMATION', $error);
    } else if (empty($username)) {
        $error = 'Nom d\'utilisateur requis';
        log_to_wazuh('DELETE_USER_FAILED', $username, 'EMPTY_USERNAME', $error);
    } else {
        // Connexion MySQL
        $conn = new mysqli(DB_HOST, DB_USER, DB_PASS, DB_NAME);
        if ($conn->connect_error) {
            $error = 'Erreur de connexion: ' . $conn->connect_error;
            log_to_wazuh('DELETE_USER_FAILED', $username, 'DB_ERROR', $error);
        } else {
            // Vérifier l'existence
            $sql_check = "SELECT id FROM radcheck WHERE username = ?";
            $stmt = $conn->prepare($sql_check);
            $stmt->bind_param('s', $username);
            $stmt->execute();
            if ($stmt->get_result()->num_rows == 0) {
                $error = 'Utilisateur non trouvé';
                log_to_wazuh('DELETE_USER_FAILED', $username, 'NOT_FOUND', $error);
            } else {
                // Supprimer l'utilisateur
                $sql_delete = "DELETE FROM radcheck WHERE username = ?";
                $stmt = $conn->prepare($sql_delete);
                $stmt->bind_param('s', $username);
                
                if ($stmt->execute()) {
                    $success = 'Utilisateur supprimé avec succès';
                    log_to_wazuh('DELETE_USER_SUCCESS', $username, 'DELETED', "Lignes affectées: " . $stmt->affected_rows);
                    
                    // Supprimer aussi de radacct si existe
                    $sql_acct = "DELETE FROM radacct WHERE username = ?";
                    $stmt = $conn->prepare($sql_acct);
                    $stmt->bind_param('s', $username);
                    $stmt->execute();
                } else {
                    $error = 'Erreur lors de la suppression: ' . $stmt->error;
                    log_to_wazuh('DELETE_USER_FAILED', $username, 'DELETE_ERROR', $error);
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
    <title>Supprimer Utilisateur - PHP-Admin SAE 5.01</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 600px; margin: auto; background: white; padding: 20px; border-radius: 5px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        h1 { color: #d32f2f; border-bottom: 3px solid #d32f2f; padding-bottom: 10px; }
        .form-group { margin: 15px 0; }
        label { display: block; font-weight: bold; margin-bottom: 5px; color: #333; }
        input[type="text"] { width: 100%; padding: 8px; border: 1px solid #ddd; border-radius: 3px; box-sizing: border-box; }
        input[type="checkbox"] { margin-right: 5px; }
        input[type="submit"] { background: #d32f2f; color: white; padding: 10px 20px; border: none; border-radius: 3px; cursor: pointer; font-weight: bold; }
        input[type="submit"]:hover { background: #b71c1c; }
        .success { color: green; padding: 10px; background: #e8f5e9; border: 1px solid #4caf50; border-radius: 3px; margin: 10px 0; }
        .error { color: red; padding: 10px; background: #ffebee; border: 1px solid #f44336; border-radius: 3px; margin: 10px 0; }
        .warning { color: #f57f17; padding: 15px; background: #fff3e0; border: 2px solid #ff9800; border-radius: 3px; margin: 15px 0; font-weight: bold; }
        a { color: #0066cc; text-decoration: none; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="container">
        <h1>⚠️ Supprimer Utilisateur</h1>
        
        <div class="warning">⚠️ ATTENTION: Cette action est irréversible !</div>
        
        <?php if ($error): ?>
            <div class="error">❌ <?php echo htmlspecialchars($error); ?></div>
        <?php endif; ?>
        
        <?php if ($success): ?>
            <div class="success">✅ <?php echo htmlspecialchars($success); ?></div>
        <?php endif; ?>
        
        <form method="POST">
            <div class="form-group">
                <label>Nom d'utilisateur à supprimer:</label>
                <input type="text" name="username" required placeholder="alice@gym.fr">
            </div>
            
            <div class="form-group">
                <label>
                    <input type="checkbox" name="confirm" value="yes" required>
                    Je confirme la suppression définitive de cet utilisateur
                </label>
            </div>
            
            <input type="submit" value="Supprimer l'Utilisateur">
        </form>
        
        <hr>
        <p><a href="index.php">← Retour</a> | <a href="list_users.php">Voir les utilisateurs →</a></p>
    </div>
</body>
</html>