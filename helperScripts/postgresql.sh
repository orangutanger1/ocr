#!/bin/bash

# PostgreSQL Install and Aggressive Hardening Script
# This script installs the latest PostgreSQL version (if not already installed) and aggressively hardens it.

# Detect the latest PostgreSQL version
echo "Detecting the latest PostgreSQL version..."
POSTGRES_VERSION=$(apt-cache show postgresql | grep Version | awk '{print $2}' | sort -V | tail -n 1 | cut -d'.' -f1-2)
if [ -z "$POSTGRES_VERSION" ]; then
  echo "Failed to detect PostgreSQL version. Exiting."
  exit 1
fi
echo "Latest PostgreSQL version detected: $POSTGRES_VERSION"

# Variables
POSTGRES_DATA_DIR="/var/lib/postgresql/$POSTGRES_VERSION/main"
POSTGRES_CONF_DIR="/etc/postgresql/$POSTGRES_VERSION/main"
POSTGRES_HBA_CONF="$POSTGRES_CONF_DIR/pg_hba.conf"
POSTGRES_CONF="$POSTGRES_CONF_DIR/postgresql.conf"
POSTGRES_USER="postgres"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/password_utils.sh"
POSTGRES_PASSWORD="$(generate_service_password)"

# Function to install PostgreSQL
install_postgresql() {
  echo "PostgreSQL is not installed. Installing PostgreSQL $POSTGRES_VERSION..."
  apt-get update
  apt-get install -y postgresql postgresql-contrib  # Install the latest version
  if [ $? -ne 0 ]; then
    echo "Failed to install PostgreSQL. Please check your package manager."
    exit 1
  fi
  echo "PostgreSQL installed successfully."
}

# Check if PostgreSQL is installed
if ! command -v psql &> /dev/null; then
  install_postgresql
else
  echo "PostgreSQL is already installed."
fi

# Start PostgreSQL service
echo "Starting PostgreSQL service..."
systemctl start postgresql

# Set PostgreSQL superuser password
echo "Setting PostgreSQL superuser password..."
sudo -u $POSTGRES_USER psql -c "ALTER USER $POSTGRES_USER WITH PASSWORD '$POSTGRES_PASSWORD';"
store_service_password "postgres_superuser" "$POSTGRES_PASSWORD"

# Aggressive Hardening Steps

# 1. Restrict PostgreSQL to localhost
echo "Restricting PostgreSQL to localhost..."
sed -i "s/^#listen_addresses =.*/listen_addresses = 'localhost'/" $POSTGRES_CONF

# 2. Disable remote access in pg_hba.conf
echo "Disabling remote access in pg_hba.conf..."
cat <<EOF > $POSTGRES_HBA_CONF
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     peer
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256
EOF

# 3. Enable SSL for PostgreSQL
echo "Enabling SSL for PostgreSQL..."
openssl req -new -x509 -days 365 -nodes -text -out $POSTGRES_DATA_DIR/server.crt \
  -keyout $POSTGRES_DATA_DIR/server.key -subj "/CN=localhost"
chmod 600 $POSTGRES_DATA_DIR/server.key
chown $POSTGRES_USER:$POSTGRES_USER $POSTGRES_DATA_DIR/server.{crt,key}

sed -i "s/^#ssl =.*/ssl = on/" $POSTGRES_CONF
sed -i "s/^#ssl_cert_file =.*/ssl_cert_file = 'server.crt'/" $POSTGRES_CONF
sed -i "s/^#ssl_key_file =.*/ssl_key_file = 'server.key'/" $POSTGRES_CONF

# 4. Enable password encryption (scram-sha-256)
echo "Enabling password encryption (scram-sha-256)..."
sed -i "s/^#password_encryption =.*/password_encryption = scram-sha-256/" $POSTGRES_CONF

# 5. Remove default 'postgres' database (if not needed)
echo "Removing default 'postgres' database..."
sudo -u $POSTGRES_USER psql -c "DROP DATABASE IF EXISTS postgres;"

# 6. Remove default 'template1' database (if not needed)
echo "Removing default 'template1' database..."
sudo -u $POSTGRES_USER psql -c "DROP DATABASE IF EXISTS template1;"

# 7. Create a new secure template database
echo "Creating a new secure template database..."
sudo -u $POSTGRES_USER psql -c "CREATE DATABASE template_secure IS_TEMPLATE = true;"
sudo -u $POSTGRES_USER psql -d template_secure -c "REVOKE ALL ON SCHEMA public FROM PUBLIC;"
sudo -u $POSTGRES_USER psql -d template_secure -c "GRANT ALL ON SCHEMA public TO $POSTGRES_USER;"

# 8. Set connection limits
echo "Setting connection limits..."
sed -i "s/^#max_connections =.*/max_connections = 100/" $POSTGRES_CONF

# 9. Enable logging
echo "Enabling logging..."
sed -i "s/^#logging_collector =.*/logging_collector = on/" $POSTGRES_CONF
sed -i "s/^#log_directory =.*/log_directory = 'pg_log'/" $POSTGRES_CONF
sed -i "s/^#log_filename =.*/log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'/" $POSTGRES_CONF
sed -i "s/^#log_connections =.*/log_connections = on/" $POSTGRES_CONF
sed -i "s/^#log_disconnections =.*/log_disconnections = on/" $POSTGRES_CONF

# 10. Restart PostgreSQL service
echo "Restarting PostgreSQL service..."
systemctl restart postgresql

# 11. Allow PostgreSQL through UFW
echo "Allowing PostgreSQL through UFW..."
ufw allow 5432/tcp

echo "PostgreSQL has been installed and aggressively hardened successfully!"
echo "PostgreSQL superuser password: $POSTGRES_PASSWORD"
