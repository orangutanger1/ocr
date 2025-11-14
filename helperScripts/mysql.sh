#!/bin/bash

# MySQL Install and Secure Installation Script
# This script installs MySQL (if not already installed) and secures it.

# Variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/password_utils.sh"
MYSQL_ROOT_PASSWORD="$(generate_service_password)"
MYSQL_SECURE_INSTALLATION="/usr/bin/mysql_secure_installation"
MYSQL_CREDENTIALS=(-u root "-p${MYSQL_ROOT_PASSWORD}")

run_mysql_root() {
  local query="$1"
  mysql "${MYSQL_CREDENTIALS[@]}" -e "$query"
}

# Function to install MySQL
install_mysql() {
  echo "MySQL is not installed. Installing MySQL..."
  apt-get update
  apt-get install -y mysql-server
  if [ $? -ne 0 ]; then
    echo "Failed to install MySQL. Please check your package manager."
    exit 1
  fi
  echo "MySQL installed successfully."
}

# Check if MySQL is installed
if ! command -v mysql &> /dev/null; then
  install_mysql
else
  echo "MySQL is already installed."
fi

# Check if mysql_secure_installation is available
if [ ! -f "$MYSQL_SECURE_INSTALLATION" ]; then
  echo "mysql_secure_installation not found. Please ensure MySQL is installed correctly."
  exit 1
fi

# Run mysql_secure_installation non-interactively
echo "Securing MySQL installation..."
expect <<EOF
spawn $MYSQL_SECURE_INSTALLATION
expect "Enter current password for root (enter for none):"
send "\r"
expect "Set root password?"
send "Y\r"
expect "New password:"
send "$MYSQL_ROOT_PASSWORD\r"
expect "Re-enter new password:"
send "$MYSQL_ROOT_PASSWORD\r"
expect "Remove anonymous users?"
send "Y\r"
expect "Disallow root login remotely?"
send "Y\r"
expect "Remove test database and access to it?"
send "Y\r"
expect "Reload privilege tables now?"
send "Y\r"
expect eof
EOF
store_service_password "mysql_root" "$MYSQL_ROOT_PASSWORD"

# Additional Security Measures

# 1. Disable MySQL command history
echo "Disabling MySQL command history..."
rm -f ~/.mysql_history
ln -s /dev/null ~/.mysql_history

# 2. Restrict MySQL to localhost (if not needed remotely)
echo "Restricting MySQL to localhost..."
sed -i 's/^bind-address\s*=\s*.*/bind-address = 127.0.0.1/' /etc/mysql/mysql.conf.d/mysqld.cnf

# 3. Remove default MySQL test database
echo "Removing default MySQL test database..."
run_mysql_root "DROP DATABASE IF EXISTS test;"

# 4. Remove anonymous users (if any remain)
echo "Removing anonymous users..."
run_mysql_root "DELETE FROM mysql.user WHERE User='';"

# 5. Remove remote root login
echo "Removing remote root login..."
run_mysql_root "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"

# 6. Flush privileges
echo "Flushing privileges..."
run_mysql_root "FLUSH PRIVILEGES;"

# 7. Enable MySQL SSL (if applicable)
echo "Enabling MySQL SSL..."
run_mysql_root "ALTER USER 'root'@'localhost' REQUIRE SSL;"

# 8. Restart MySQL service
echo "Restarting MySQL service..."
systemctl restart mysql

echo "MySQL has been installed and secured successfully!"
