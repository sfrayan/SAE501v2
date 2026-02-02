#!/bin/bash
#
# install_php_admin.sh - Installation interface web PHP-Admin
# Version corrigée avec configuration Apache complète
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 Installation PHP-Admin Interface"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Vérifier root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ce script doit être exécuté en root (sudo)"
  exit 1
fi

# 1. Installation paquets
echo "[1/7] Installation Apache + PHP..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  apache2 \
  php \
  php-mysql \
  php-cli \
  php-common \
  php-json \
  libapache2-mod-php \
  > /dev/null 2>&1

# 2. Copie fichiers PHP
echo "[2/7] Copie fichiers application..."
if [ -d "$PROJECT_ROOT/php-admin" ]; then
  rm -rf /var/www/html/php-admin 2>/dev/null || true
  cp -r "$PROJECT_ROOT/php-admin" /var/www/html/
else
  echo "❌ Dossier php-admin introuvable"
  exit 1
fi

# 3. Configuration permissions
echo "[3/7] Configuration permissions..."
chown -R www-data:www-data /var/www/html/php-admin
find /var/www/html/php-admin -type d -exec chmod 755 {} \;
find /var/www/html/php-admin -type f -exec chmod 644 {} \;
chmod 640 /var/www/html/php-admin/config.php

# 4. Création dossier logs
echo "[4/7] Création dossier logs..."
mkdir -p /var/log/php-admin
chown www-data:www-data /var/log/php-admin
chmod 755 /var/log/php-admin
touch /var/log/php-admin/$(date +%Y-%m-%d).log
chown www-data:www-data /var/log/php-admin/*.log

# 5. Configuration Apache VirtualHost
echo "[5/7] Configuration Apache..."
cat > /etc/apache2/sites-available/php-admin.conf <<'EOF'
<VirtualHost *:80>
    ServerAdmin webmaster@gym.fr
    DocumentRoot /var/www/html/php-admin
    
    <Directory /var/www/html/php-admin>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
        
        # Sécurité: bloquer accès direct config.php
        <Files "config.php">
            Require all denied
        </Files>
    </Directory>
    
    ErrorLog ${APACHE_LOG_DIR}/php-admin-error.log
    CustomLog ${APACHE_LOG_DIR}/php-admin-access.log combined
    
    # Sécurité headers
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
</VirtualHost>
EOF

# Activer site et modules
a2enmod rewrite > /dev/null 2>&1
a2enmod headers > /dev/null 2>&1
a2ensite php-admin > /dev/null 2>&1

# 6. Test configuration PHP
echo "[6/7] Test configuration PHP..."
php -r "
\$pdo = new PDO('mysql:host=localhost;dbname=radius', 'radius_app', 'RadiusAppPass!2026');
echo 'Connexion MySQL: OK\n';
" 2>/dev/null || {
  echo "⚠️  Impossible de se connecter à MySQL"
}

# 7. Démarrage Apache
echo "[7/7] Démarrage Apache..."
systemctl enable apache2 > /dev/null 2>&1
systemctl restart apache2

# Configurer firewall
if command -v ufw >/dev/null 2>&1; then
  ufw allow 80/tcp comment 'Apache HTTP' > /dev/null 2>&1 || true
fi

# Obtenir l'IP
IP=$(hostname -I | awk '{print $1}')

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Installation PHP-Admin terminée"
echo ""
echo "🌐 Accès interface web:"
echo "  http://$IP/php-admin/"
echo "  http://localhost/php-admin/"
echo ""
echo "📂 Fichiers:"
echo "  /var/www/html/php-admin/"
echo "  /var/log/php-admin/"
echo ""
echo "📝 Pages disponibles:"
echo "  index.php       - Accueil"
echo "  list_users.php  - Liste utilisateurs"
echo "  add_user.php    - Ajouter utilisateur"
echo "  delete_user.php - Supprimer utilisateur"
echo ""
echo "🧪 Test:"
echo "  curl http://localhost/php-admin/list_users.php"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit 0
