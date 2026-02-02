<?php
/**
 * view_logs.php - Interface de visualisation des logs
 * SAE 5.01 - Fitness WiFi Management
 */

require_once 'config.php';

// Headers pour la page
header('Content-Type: text/html; charset=utf-8');
?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Logs - Fitness WiFi</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            min-height: 100vh;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            border-radius: 15px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            padding: 30px;
        }
        h1 {
            color: #667eea;
            margin-bottom: 10px;
            font-size: 28px;
        }
        .subtitle {
            color: #666;
            margin-bottom: 30px;
            font-size: 14px;
        }
        .tabs {
            display: flex;
            gap: 10px;
            margin-bottom: 20px;
            border-bottom: 2px solid #eee;
        }
        .tab {
            padding: 12px 24px;
            background: none;
            border: none;
            cursor: pointer;
            font-size: 16px;
            color: #666;
            border-bottom: 3px solid transparent;
            transition: all 0.3s;
        }
        .tab:hover {
            color: #667eea;
        }
        .tab.active {
            color: #667eea;
            border-bottom-color: #667eea;
            font-weight: 600;
        }
        .tab-content {
            display: none;
        }
        .tab-content.active {
            display: block;
        }
        .log-box {
            background: #f8f9fa;
            border: 1px solid #dee2e6;
            border-radius: 8px;
            padding: 15px;
            font-family: 'Courier New', monospace;
            font-size: 13px;
            max-height: 600px;
            overflow-y: auto;
            white-space: pre-wrap;
            word-wrap: break-word;
        }
        .log-line {
            padding: 5px;
            margin: 2px 0;
            border-radius: 3px;
        }
        .log-line.success {
            background: #d4edda;
            color: #155724;
        }
        .log-line.error {
            background: #f8d7da;
            color: #721c24;
        }
        .log-line.info {
            background: #d1ecf1;
            color: #0c5460;
        }
        .controls {
            display: flex;
            gap: 10px;
            margin-bottom: 15px;
            flex-wrap: wrap;
        }
        .btn {
            padding: 10px 20px;
            border: none;
            border-radius: 6px;
            cursor: pointer;
            font-size: 14px;
            transition: all 0.3s;
            text-decoration: none;
            display: inline-block;
        }
        .btn-primary {
            background: #667eea;
            color: white;
        }
        .btn-primary:hover {
            background: #5568d3;
        }
        .btn-secondary {
            background: #6c757d;
            color: white;
        }
        .btn-secondary:hover {
            background: #5a6268;
        }
        input[type="text"] {
            padding: 10px;
            border: 1px solid #ddd;
            border-radius: 6px;
            font-size: 14px;
            width: 250px;
        }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 20px;
        }
        .stat-card {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 10px;
            text-align: center;
        }
        .stat-number {
            font-size: 32px;
            font-weight: bold;
            margin-bottom: 5px;
        }
        .stat-label {
            font-size: 14px;
            opacity: 0.9;
        }
        .back-link {
            display: inline-block;
            margin-bottom: 20px;
            color: #667eea;
            text-decoration: none;
            font-weight: 600;
        }
        .back-link:hover {
            text-decoration: underline;
        }
    </style>
</head>
<body>
    <div class="container">
        <a href="index.php" class="back-link">← Retour au tableau de bord</a>
        
        <h1>📊 Logs de Connectivité</h1>
        <p class="subtitle">Surveillance des authentifications WiFi et actions administratives</p>

        <?php
        // Statistiques RADIUS
        $radius_log = '/var/log/freeradius/radius.log';
        $success_count = 0;
        $failed_count = 0;
        $total_count = 0;

        if (file_exists($radius_log)) {
            $lines = file($radius_log);
            $total_count = count($lines);
            foreach ($lines as $line) {
                if (stripos($line, 'Access-Accept') !== false || stripos($line, 'Login OK') !== false) {
                    $success_count++;
                }
                if (stripos($line, 'Access-Reject') !== false || stripos($line, 'Login incorrect') !== false) {
                    $failed_count++;
                }
            }
        }
        ?>

        <div class="stats">
            <div class="stat-card">
                <div class="stat-number"><?php echo $success_count; ?></div>
                <div class="stat-label">✅ Connexions réussies</div>
            </div>
            <div class="stat-card" style="background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);">
                <div class="stat-number"><?php echo $failed_count; ?></div>
                <div class="stat-label">❌ Tentatives échouées</div>
            </div>
            <div class="stat-card" style="background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);">
                <div class="stat-number"><?php echo $total_count; ?></div>
                <div class="stat-label">📄 Total entrées</div>
            </div>
        </div>

        <div class="tabs">
            <button class="tab active" onclick="showTab('radius')">RADIUS (Authentifications)</button>
            <button class="tab" onclick="showTab('syslog')">Syslog (Réseau)</button>
            <button class="tab" onclick="showTab('wazuh')">Wazuh (Supervision)</button>
        </div>

        <!-- Tab RADIUS -->
        <div id="radius" class="tab-content active">
            <div class="controls">
                <input type="text" id="search-radius" placeholder="Rechercher (ex: alice@gym.fr)">
                <button class="btn btn-primary" onclick="searchLogs('radius')">Rechercher</button>
                <button class="btn btn-secondary" onclick="refreshLogs('radius')">Actualiser</button>
            </div>
            <div class="log-box" id="radius-logs">
                <?php
                if (file_exists($radius_log)) {
                    $lines = array_slice(file($radius_log), -100); // Dernières 100 lignes
                    foreach (array_reverse($lines) as $line) {
                        $class = '';
                        if (stripos($line, 'Access-Accept') !== false || stripos($line, 'Login OK') !== false) {
                            $class = 'success';
                        } elseif (stripos($line, 'Access-Reject') !== false || stripos($line, 'Login incorrect') !== false) {
                            $class = 'error';
                        } else {
                            $class = 'info';
                        }
                        echo '<div class="log-line ' . $class . '">' . htmlspecialchars($line) . '</div>';
                    }
                } else {
                    echo '<div class="log-line error">❌ Fichier de log RADIUS introuvable</div>';
                }
                ?>
            </div>
        </div>

        <!-- Tab Syslog -->
        <div id="syslog" class="tab-content">
            <div class="controls">
                <input type="text" id="search-syslog" placeholder="Rechercher (ex: 192.168.10.1)">
                <button class="btn btn-primary" onclick="searchLogs('syslog')">Rechercher</button>
                <button class="btn btn-secondary" onclick="refreshLogs('syslog')">Actualiser</button>
            </div>
            <div class="log-box" id="syslog-logs">
                <?php
                $syslog = '/var/log/syslog';
                if (file_exists($syslog)) {
                    $lines = array_slice(file($syslog), -100);
                    foreach (array_reverse($lines) as $line) {
                        // Filtrer les lignes pertinentes (RADIUS, DHCP, routeur)
                        if (stripos($line, 'radius') !== false || 
                            stripos($line, 'dhcp') !== false || 
                            stripos($line, '192.168.10.1') !== false) {
                            echo '<div class="log-line info">' . htmlspecialchars($line) . '</div>';
                        }
                    }
                } else {
                    echo '<div class="log-line error">❌ Fichier syslog introuvable</div>';
                }
                ?>
            </div>
        </div>

        <!-- Tab Wazuh -->
        <div id="wazuh" class="tab-content">
            <div class="controls">
                <button class="btn btn-secondary" onclick="refreshLogs('wazuh')">Actualiser</button>
                <a href="https://192.168.10.100:443" target="_blank" class="btn btn-primary">Ouvrir Dashboard Wazuh</a>
            </div>
            <div class="log-box" id="wazuh-logs">
                <?php
                $wazuh_log = '/var/log/wazuh-export/alerts.json';
                if (file_exists($wazuh_log)) {
                    $content = file_get_contents($wazuh_log);
                    if (!empty($content)) {
                        echo '<pre>' . htmlspecialchars($content) . '</pre>';
                    } else {
                        echo '<div class="log-line info">ℹ Aucune alerte Wazuh pour le moment</div>';
                    }
                } else {
                    echo '<div class="log-line error">❌ Fichier d\'export Wazuh introuvable</div>';
                }
                ?>
            </div>
        </div>
    </div>

    <script>
        function showTab(tabName) {
            // Masquer tous les contenus
            document.querySelectorAll('.tab-content').forEach(content => {
                content.classList.remove('active');
            });
            document.querySelectorAll('.tab').forEach(tab => {
                tab.classList.remove('active');
            });

            // Afficher le contenu sélectionné
            document.getElementById(tabName).classList.add('active');
            event.target.classList.add('active');
        }

        function searchLogs(logType) {
            const searchInput = document.getElementById('search-' + logType).value.toLowerCase();
            const logBox = document.getElementById(logType + '-logs');
            const lines = logBox.querySelectorAll('.log-line');

            lines.forEach(line => {
                if (line.textContent.toLowerCase().includes(searchInput)) {
                    line.style.display = 'block';
                    line.style.fontWeight = 'bold';
                } else {
                    line.style.display = 'none';
                }
            });
        }

        function refreshLogs(logType) {
            location.reload();
        }

        // Auto-refresh toutes les 30 secondes
        setInterval(() => {
            location.reload();
        }, 30000);
    </script>
</body>
</html>
