#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FR_CONF="/etc/freeradius/3.0"

apt-get update -qq >/dev/null 2>&1
apt-get install -y freeradius freeradius-mysql freeradius-utils >/dev/null 2>&1

mysql -u root < "$PROJECT_ROOT/radius/sql/init_appuser.sql" >/dev/null 2>&1
mysql -u root radius < "$PROJECT_ROOT/radius/sql/create_tables.sql" >/dev/null 2>&1

rm -f "$FR_CONF/clients.conf" 2>/dev/null || true
rm -f "$FR_CONF/users" 2>/dev/null || true

cp "$PROJECT_ROOT/radius/clients.conf" "$FR_CONF/clients.conf"
cp "$PROJECT_ROOT/radius/users.txt" "$FR_CONF/users"

cd "$FR_CONF/certs" && make >/dev/null 2>&1 && cd - >/dev/null

ln -sf ../mods-available/sql "$FR_CONF/mods-enabled/sql" 2>/dev/null
ln -sf ../mods-available/eap "$FR_CONF/mods-enabled/eap" 2>/dev/null

chown -R root:freerad "$FR_CONF"
chmod -R 750 "$FR_CONF"
chmod 640 "$FR_CONF/clients.conf"

systemctl enable freeradius >/dev/null 2>&1
systemctl restart freeradius >/dev/null 2>&1
