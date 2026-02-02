<?php
/**
 * wazuh_logs.php - Visualisation des logs Wazuh
 *
 * Fichier: php-admin/wazuh_logs.php
 * Auteur: GroupeNani
 * Date: 2 février 2026
 */

require_once 'config.php';

$page_title = 'Logs Wazuh';
$log_file = '/var/log/wazuh-export/alerts.json';
$alerts = [];
$error = null;

// Lecture des logs
if (file_exists($log_file)) {
    $content = file_get_contents($log_file);
    if (!empty($content)) {
        $lines = explode("\n", trim($content));
        foreach (array_reverse($lines) as $line) {
            if (!empty(trim($line))) {
                $decoded = json_decode($line, true);
                if ($decoded && is_array($decoded)) {
                    $alerts[] = $decoded;
                }
                if (count($alerts) >= 100) break;
            }
        }
    }
} else {
    $error = "Fichier de logs non trouvé. Vérifiez que Wazuh est installé et que le cron d'export est actif.";
}

// Filtrage
$filter_level = $_GET['level'] ?? 'all';
$filter_search = $_GET['search'] ?? '';

if ($filter_level !== 'all') {
    $alerts = array_filter($alerts, function($a) use ($filter_level) {
        $level = $a['rule']['level'] ?? 0;
        if ($filter_level === 'high') return $level >= 10;
        if ($filter_level === 'medium') return $level >= 5 && $level < 10;
        if ($filter_level === 'low') return $level < 5;
        return true;
    });
}

if (!empty($filter_search)) {
    $alerts = array_filter($alerts, function($a) use ($filter_search) {
        $json = json_encode($a);
        return stripos($json, $filter_search) !== false;
    });
}

?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo escape_html(APP_TITLE); ?> - Logs Wazuh</title>
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
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 40px rgba(0, 0, 0, 0.2);
            max-width: 1400px;
            margin: 0 auto;
            padding: 30px;
        }
        
        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 30px;
            padding-bottom: 20px;
            border-bottom: 3px solid #667eea;
        }
        
        .header h1 {
            color: #333;
            font-size: 24px;
        }
        
        .back-btn {
            background: #667eea;
            color: white;
            padding: 10px 20px;
            border-radius: 5px;
            text-decoration: none;
            transition: background 0.3s;
        }
        
        .back-btn:hover {
            background: #5568d3;
        }
        
        .filters {
            background: #f5f5f5;
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 20px;
            display: flex;
            gap: 15px;
            flex-wrap: wrap;
            align-items: center;
        }
        
        .filter-group {
            display: flex;
            gap: 8px;
            align-items: center;
        }
        
        .filter-group label {
            font-weight: 500;
            font-size: 14px;
        }
        
        .filter-group select,
        .filter-group input {
            padding: 8px 12px;
            border: 1px solid #ddd;
            border-radius: 5px;
            font-size: 14px;
        }
        
        .filter-group input {
            width: 250px;
        }
        
        .stats {
            display: flex;
            gap: 15px;
            margin-bottom: 20px;
            flex-wrap: wrap;
        }
        
        .stat-card {
            flex: 1;
            min-width: 200px;
            padding: 15px;
            border-radius: 8px;
            color: white;
            text-align: center;
        }
        
        .stat-high { background: linear-gradient(135deg, #e74c3c, #c0392b); }
        .stat-medium { background: linear-gradient(135deg, #f39c12, #e67e22); }
        .stat-low { background: linear-gradient(135deg, #3498db, #2980b9); }
        .stat-total { background: linear-gradient(135deg, #667eea, #764ba2); }
        
        .stat-card h3 {
            font-size: 14px;
            margin-bottom: 8px;
            opacity: 0.9;
        }
        
        .stat-card .number {
            font-size: 32px;
            font-weight: bold;
        }
        
        .alert-list {
            max-height: 600px;
            overflow-y: auto;
        }
        
        .alert-item {
            background: #f9f9f9;
            border-left: 4px solid #667eea;
            padding: 15px;
            margin-bottom: 12px;
            border-radius: 5px;
            transition: all 0.2s;
        }
        
        .alert-item:hover {
            background: #f0f4ff;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }
        
        .alert-item.high { border-left-color: #e74c3c; }
        .alert-item.medium { border-left-color: #f39c12; }
        .alert-item.low { border-left-color: #3498db; }
        
        .alert-header {
            display: flex;
            justify-content: space-between;
            align-items: start;
            margin-bottom: 10px;
        }
        
        .alert-title {
            font-weight: 600;
            color: #333;
            font-size: 15px;
        }
        
        .alert-level {
            display: inline-block;
            padding: 4px 10px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: 600;
            color: white;
        }
        
        .level-high { background: #e74c3c; }
        .level-medium { background: #f39c12; }
        .level-low { background: #3498db; }
        
        .alert-time {
            font-size: 12px;
            color: #999;
            margin-top: 5px;
        }
        
        .alert-details {
            font-size: 13px;
            color: #666;
            line-height: 1.5;
        }
        
        .alert-details code {
            background: white;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: monospace;
            font-size: 12px;
        }
        
        .no-alerts {
            text-align: center;
            padding: 60px 20px;
            color: #999;
        }
        
        .error-box {
            background: #fee;
            border: 1px solid #fcc;
            padding: 20px;
            border-radius: 8px;
            color: #c33;
            margin-bottom: 20px;
        }
        
        .refresh-info {
            background: #e3f2fd;
            border-left: 4px solid #2196F3;
            padding: 12px;
            border-radius: 5px;
            font-size: 13px;
            color: #0d47a1;
            margin-bottom: 20px;
        }
        
        @media (max-width: 768px) {
            .filters {
                flex-direction: column;
                align-items: stretch;
            }
            
            .filter-group {
                flex-direction: column;
                align-items: stretch;
            }
            
            .filter-group input {
                width: 100%;
            }
        }
    </style>
    <script>
        // Auto-refresh toutes les 60 secondes
        setTimeout(() => {
            location.reload();
        }, 60000);
    </script>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📊 Logs Wazuh Manager</h1>
            <a href="index.php" class="back-btn">← Retour</a>
        </div>
        
        <?php if ($error): ?>
            <div class="error-box">
                <strong>⚠️ Erreur:</strong> <?php echo escape_html($error); ?>
            </div>
        <?php else: ?>
            <div class="refresh-info">
                🔄 Logs mis à jour toutes les 2 minutes | Auto-refresh dans 60s | Affichage des 100 dernières alertes
            </div>
            
            <?php
            $total = count($alerts);
            $high = count(array_filter($alerts, fn($a) => ($a['rule']['level'] ?? 0) >= 10));
            $medium = count(array_filter($alerts, fn($a) => ($a['rule']['level'] ?? 0) >= 5 && ($a['rule']['level'] ?? 0) < 10));
            $low = count(array_filter($alerts, fn($a) => ($a['rule']['level'] ?? 0) < 5));
            ?>
            
            <div class="stats">
                <div class="stat-card stat-total">
                    <h3>Total Alertes</h3>
                    <div class="number"><?php echo $total; ?></div>
                </div>
                <div class="stat-card stat-high">
                    <h3>Niveau Élevé (≥10)</h3>
                    <div class="number"><?php echo $high; ?></div>
                </div>
                <div class="stat-card stat-medium">
                    <h3>Niveau Moyen (5-9)</h3>
                    <div class="number"><?php echo $medium; ?></div>
                </div>
                <div class="stat-card stat-low">
                    <h3>Niveau Faible (<5)</h3>
                    <div class="number"><?php echo $low; ?></div>
                </div>
            </div>
            
            <form method="get" class="filters">
                <div class="filter-group">
                    <label for="level">Niveau:</label>
                    <select name="level" id="level" onchange="this.form.submit()">
                        <option value="all" <?php echo $filter_level === 'all' ? 'selected' : ''; ?>>Tous</option>
                        <option value="high" <?php echo $filter_level === 'high' ? 'selected' : ''; ?>>Élevé (≥10)</option>
                        <option value="medium" <?php echo $filter_level === 'medium' ? 'selected' : ''; ?>>Moyen (5-9)</option>
                        <option value="low" <?php echo $filter_level === 'low' ? 'selected' : ''; ?>>Faible (<5)</option>
                    </select>
                </div>
                
                <div class="filter-group">
                    <label for="search">Recherche:</label>
                    <input type="text" name="search" id="search" value="<?php echo escape_html($filter_search); ?>" placeholder="Rechercher...">
                </div>
                
                <button type="submit" class="back-btn" style="padding: 8px 16px;">🔍 Filtrer</button>
                <?php if ($filter_level !== 'all' || !empty($filter_search)): ?>
                    <a href="wazuh_logs.php" class="back-btn" style="padding: 8px 16px; background: #95a5a6;">❌ Réinitialiser</a>
                <?php endif; ?>
            </form>
            
            <div class="alert-list">
                <?php if (empty($alerts)): ?>
                    <div class="no-alerts">
                        <h3>📦 Aucune alerte trouvée</h3>
                        <p>Aucune alerte ne correspond aux filtres sélectionnés.</p>
                    </div>
                <?php else: ?>
                    <?php foreach ($alerts as $alert): 
                        $level = $alert['rule']['level'] ?? 0;
                        $level_class = $level >= 10 ? 'high' : ($level >= 5 ? 'medium' : 'low');
                        $timestamp = $alert['timestamp'] ?? 'N/A';
                        $rule_desc = $alert['rule']['description'] ?? 'N/A';
                        $rule_id = $alert['rule']['id'] ?? 'N/A';
                        $agent_name = $alert['agent']['name'] ?? 'N/A';
                        $agent_ip = $alert['agent']['ip'] ?? 'N/A';
                    ?>
                        <div class="alert-item <?php echo $level_class; ?>">
                            <div class="alert-header">
                                <div>
                                    <div class="alert-title"><?php echo escape_html($rule_desc); ?></div>
                                    <div class="alert-time">
                                        🕒 <?php echo escape_html($timestamp); ?> | 
                                        💻 Agent: <?php echo escape_html($agent_name); ?> (<?php echo escape_html($agent_ip); ?>) |
                                        🎯 Règle: <?php echo escape_html($rule_id); ?>
                                    </div>
                                </div>
                                <span class="alert-level level-<?php echo $level_class; ?>">
                                    Niveau <?php echo $level; ?>
                                </span>
                            </div>
                            
                            <div class="alert-details">
                                <?php if (isset($alert['data'])): ?>
                                    <strong>Détails:</strong> <?php echo escape_html(json_encode($alert['data'], JSON_UNESCAPED_UNICODE)); ?>
                                <?php endif; ?>
                                
                                <?php if (isset($alert['full_log'])): ?>
                                    <br><strong>Log complet:</strong> <code><?php echo escape_html(substr($alert['full_log'], 0, 200)); ?><?php echo strlen($alert['full_log']) > 200 ? '...' : ''; ?></code>
                                <?php endif; ?>
                            </div>
                        </div>
                    <?php endforeach; ?>
                <?php endif; ?>
            </div>
        <?php endif; ?>
    </div>
</body>
</html>
