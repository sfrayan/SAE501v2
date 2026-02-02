#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

[ "$EUID" -ne 0 ] && exit 1

apt-get update -qq >/dev/null 2>&1
apt-get install -y apache2 php php-mysql libapache2-mod-php >/dev/null 2>&1

cp -r "$PROJECT_ROOT/php-admin" /var/www/html/

chown -R www-data:www-data /var/www/html/php-admin
chmod -R 755 /var/www/html/php-admin
chmod 644 /var/www/html/php-admin/*.php
chmod 640 /var/www/html/php-admin/config.php

mkdir -p /var/log/php-admin
chown www-data:www-data /var/log/php-admin
chmod 755 /var/log/php-admin

systemctl enable apache2 >/dev/null 2>&1
systemctl restart apache2 >/dev/null 2>&1

if command -v ufw >/dev/null 2>&1; then
    ufw allow 80/tcp comment 'Apache HTTP' >/dev/null 2>&1
fi

exit 0
