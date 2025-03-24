#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Variables
MARIADB_CONFIG="/etc/mysql/mariadb.conf.d/50-server.cnf"
AUTHORIZED_USERS_FILE="authorizedusers.txt"
AUTHORIZED_SUDO_USERS_FILE="authorizedsudousers.txt"
MARIADB_ROOT_PASSWORD="GbgH8vV0s%B6A3Tu"  # Change this to a secure password
MARIADB_USER_PASSWORD="GbgH8vV0s%B6A3Tu"  # Change this to a secure password

# Install MariaDB if not already installed
if ! command -v mariadb &> /dev/null; then
  echo "MariaDB not found. Installing MariaDB..."
  apt-get update
  apt-get install -y mariadb-server
fi

# Secure the MariaDB installation
echo "Securing MariaDB installation..."
mysql_secure_installation <<EOF
y
$MARIADB_ROOT_PASSWORD
$MARIADB_ROOT_PASSWORD
y
y
y
y
y
EOF

# Backup the current MariaDB configuration
cp $MARIADB_CONFIG $MARIADB_CONFIG.bak

# Apply CIS Benchmark recommendations
echo "Applying CIS Benchmark recommendations..."

# 1.1 Place Databases on Non-System Partitions (Manual)
# Ensure the datadir is on a non-system partition
DATADIR="/var/lib/mysql"
if df -h $DATADIR | grep -qE '(/|/var|/usr)'; then
  echo "Warning: datadir is on a system partition. Consider moving it to a non-system partition."
fi

# 1.2 Use Dedicated Least Privileged Account for MariaDB Daemon/Service (Automated)
# Ensure MariaDB runs under a dedicated user
if ! grep -q "^mysql" /etc/passwd; then
  groupadd -r mysql
  useradd -r -g mysql -s /bin/false -d /var/lib/mysql mysql
fi

# 1.3 Disable MariaDB Command History (Automated)
echo "export MYSQL_HISTFILE=/dev/null" >> /etc/profile
echo "export MYSQL_HISTFILE=/dev/null" >> /etc/bash.bashrc

# 1.4 Verify That the MYSQL_PWD Environment Variable is Not in Use (Automated)
if grep -r "MYSQL_PWD" /etc/profile /etc/bash.bashrc /home/*/.bashrc /home/*/.profile; then
  echo "MYSQL_PWD environment variable is in use. Please remove it."
  exit 1
fi

# 1.5 Ensure Interactive Login is Disabled (Automated)
usermod -s /bin/false mysql

# 1.6 Verify That 'MYSQL_PWD' is Not Set in Users' Profiles (Automated)
if grep -r "MYSQL_PWD" /home/*/.bashrc /home/*/.profile; then
  echo "MYSQL_PWD is set in users' profiles. Please remove it."
  exit 1
fi

# 1.7 Ensure MariaDB is Run Under a Sandbox Environment (Manual)
# Consider using Docker or chroot for sandboxing

# 2.1 Backup and Disaster Recovery
# Ensure backups are configured (Manual)
echo "Backup policy should be implemented manually."

# 2.2 Dedicate the Machine Running MariaDB (Manual)
# Ensure MariaDB is running on a dedicated machine

# 2.3 Do Not Specify Passwords in the Command Line (Manual)
# Ensure passwords are not specified in the command line

# 2.4 Do Not Reuse Usernames (Manual)
# Ensure unique usernames are used

# 2.5 Ensure Non-Default, Unique Cryptographic Material is in Use (Manual)
# Generate unique SSL certificates and keys
openssl req -x509 -newkey rsa:2048 -keyout /etc/mysql/server-key.pem -out /etc/mysql/server-cert.pem -days 365 -nodes -subj "/CN=MariaDB Server"

# 2.6 Ensure 'password_lifetime' is Less Than or Equal to '365' (Automated)
mysql -u root -p$MARIADB_ROOT_PASSWORD -e "SET GLOBAL default_password_lifetime=365;"

# 2.7 Lock Out Accounts if Not Currently in Use (Manual)
# Lock unused accounts manually

# 2.8 Ensure Socket Peer-Credential Authentication is Used Appropriately (Manual)
# Configure unix_socket authentication if needed

# 2.9 Ensure MariaDB is Bound to One or More Specific IP Addresses (Automated)
sed -i 's/^bind-address.*/bind-address = 127.0.0.1/' $MARIADB_CONFIG

# 2.10 Limit Accepted Transport Layer Security (TLS) Versions (Automated)
sed -i 's/^tls_version.*/tls_version = TLSv1.2,TLSv1.3/' $MARIADB_CONFIG

# 2.11 Require Client-Side Certificates (X.509) (Automated)
# Configure client-side certificates manually

# 2.12 Ensure Only Approved Ciphers are Used (Automated)
sed -i 's/^ssl_cipher.*/ssl_cipher = ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256/' $MARIADB_CONFIG

# 3.1 Ensure 'datadir' Has Appropriate Permissions (Automated)
chmod 750 /var/lib/mysql
chown mysql:mysql /var/lib/mysql

# 3.2 Ensure 'log_bin_basename' Files Have Appropriate Permissions (Automated)
chmod 660 /var/log/mysql/mysql-bin.*
chown mysql:mysql /var/log/mysql/mysql-bin.*

# 3.3 Ensure 'log_error' Has Appropriate Permissions (Automated)
chmod 600 /var/log/mysql/error.log
chown mysql:mysql /var/log/mysql/error.log

# 3.4 Ensure 'slow_query_log' Has Appropriate Permissions (Automated)
chmod 660 /var/log/mysql/slow.log
chown mysql:mysql /var/log/mysql/slow.log

# 3.5 Ensure 'relay_log_basename' Files Have Appropriate Permissions (Automated)
chmod 660 /var/log/mysql/relay-bin.*
chown mysql:mysql /var/log/mysql/relay-bin.*

# 3.6 Ensure 'general_log_file' Has Appropriate Permissions (Automated)
chmod 660 /var/log/mysql/general.log
chown mysql:mysql /var/log/mysql/general.log

# 3.7 Ensure SSL Key Files Have Appropriate Permissions (Automated)
chmod 400 /etc/mysql/server-key.pem
chown mysql:mysql /etc/mysql/server-key.pem

# 3.8 Ensure Plugin Directory Has Appropriate Permissions (Automated)
chmod 550 /usr/lib/mysql/plugin
chown mysql:mysql /usr/lib/mysql/plugin

# 3.9 Ensure 'server_audit_file_path' Has Appropriate Permissions (Automated)
chmod 660 /var/log/mysql/audit.log
chown mysql:mysql /var/log/mysql/audit.log

# 3.10 Ensure File Key Management Encryption Plugin files have appropriate permissions (Automated)
chmod 750 /etc/mysql/encryption
chown mysql:mysql /etc/mysql/encryption

# 4.1 Ensure the Latest Security Patches are Applied (Manual)
# Ensure MariaDB is up to date
apt-get update
apt-get upgrade -y mariadb-server

# 4.2 Ensure Example or Test Databases are Not Installed on Production Servers (Automated)
mysql -u root -p$MARIADB_ROOT_PASSWORD -e "DROP DATABASE IF EXISTS test;"

# 4.3 Ensure 'allow-suspicious-udfs' is Set to 'OFF' (Automated)
sed -i 's/^allow-suspicious-udfs.*/allow-suspicious-udfs = OFF/' $MARIADB_CONFIG

# 4.4 Harden Usage for 'local_infile' on MariaDB Clients (Automated)
sed -i 's/^local-infile.*/local-infile = 0/' $MARIADB_CONFIG

# 4.5 Ensure mariadb is Not Started With 'skip-grant-tables' (Automated)
sed -i 's/^skip-grant-tables.*/#skip-grant-tables = FALSE/' $MARIADB_CONFIG

# 4.6 Ensure Symbolic Links are Disabled (Automated)
sed -i 's/^symbolic-links.*/symbolic-links = 0/' $MARIADB_CONFIG

# 4.7 Ensure the 'secure_file_priv' is Configured Correctly (Automated)
sed -i 's/^secure_file_priv.*/secure_file_priv = \/var\/lib\/mysql-files/' $MARIADB_CONFIG

# 4.8 Ensure 'sql_mode' Contains 'STRICT_ALL_TABLES' (Automated)
sed -i 's/^sql_mode.*/sql_mode = STRICT_ALL_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION/' $MARIADB_CONFIG

# 4.9 Enable data-at-rest encryption in MariaDB (Automated)
echo "plugin_load_add = file_key_management" >> $MARIADB_CONFIG
echo "file_key_management_filename = /etc/mysql/encryption/keyfile.enc" >> $MARIADB_CONFIG
echo "file_key_management_filekey = FILE:/etc/mysql/encryption/keyfile.key" >> $MARIADB_CONFIG
echo "encrypt_binlog = ON" >> $MARIADB_CONFIG
echo "innodb_encrypt_log = ON" >> $MARIADB_CONFIG
echo "encrypt_tmp_files = ON" >> $MARIADB_CONFIG
echo "innodb_encrypt_tables = ON" >> $MARIADB_CONFIG

# 5.1 Ensure Only Administrative Users Have Full Database Access (Manual)
# Revoke unnecessary privileges from non-administrative users

# 5.2 Ensure 'FILE' is Not Granted to Non-Administrative Users (Manual)
mysql -u root -p$MARIADB_ROOT_PASSWORD -e "REVOKE FILE ON *.* FROM 'nonadmin'@'localhost';"

# 5.3 Ensure 'PROCESS' is Not Granted to Non-Administrative Users (Manual)
mysql -u root -p$MARIADB_ROOT_PASSWORD -e "REVOKE PROCESS ON *.* FROM 'nonadmin'@'localhost';"

# 5.4 Ensure 'SUPER' is Not Granted to Non-Administrative Users (Manual)
mysql -u root -p$MARIADB_ROOT_PASSWORD -e "REVOKE SUPER ON *.* FROM 'nonadmin'@'localhost';"

# 5.5 Ensure 'SHUTDOWN' is Not Granted to Non-Administrative Users (Manual)
mysql -u root -p$MARIADB_ROOT_PASSWORD -e "REVOKE SHUTDOWN ON *.* FROM 'nonadmin'@'localhost';"

# 5.6 Ensure 'CREATE USER' is Not Granted to Non-Administrative Users (Manual)
mysql -u root -p$MARIADB_ROOT_PASSWORD -e "REVOKE CREATE USER ON *.* FROM 'nonadmin'@'localhost';"

# 5.7 Ensure 'GRANT OPTION' is Not Granted to Non-Administrative Users (Manual)
mysql -u root -p$MARIADB_ROOT_PASSWORD -e "REVOKE GRANT OPTION ON *.* FROM 'nonadmin'@'localhost';"

# 5.8 Ensure 'REPLICATION SLAVE' is Not Granted to Non-Administrative Users (Manual)
mysql -u root -p$MARIADB_ROOT_PASSWORD -e "REVOKE REPLICATION SLAVE ON *.* FROM 'nonadmin'@'localhost';"

# 5.9 Ensure DML/DDL Grants are Limited to Specific Databases and Users (Manual)
mysql -u root -p$MARIADB_ROOT_PASSWORD -e "REVOKE SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER ON *.* FROM 'nonadmin'@'localhost';"

# 5.10 Securely Define Stored Procedures and Functions DEFINER and INVOKER (Manual)
# Ensure stored procedures and functions are securely defined

# 6.1 Ensure 'log_error' is configured correctly (Automated)
sed -i 's/^log_error.*/log_error = /var/log/mysql/error.log/' $MARIADB_CONFIG

# 6.2 Ensure Log Files are Stored on a Non-System Partition (Automated)
# Ensure log files are stored on a non-system partition

# 6.3 Ensure 'log_warnings' is Set to '2' (Automated)
sed -i 's/^log_warnings.*/log_warnings = 2/' $MARIADB_CONFIG

# 6.4 Ensure Audit Logging Is Enabled (Automated)
echo "plugin_load_add = server_audit" >> $MARIADB_CONFIG
echo "server_audit_logging=ON" >> $MARIADB_CONFIG
echo "server_audit_events=CONNECT" >> $MARIADB_CONFIG

# 6.5 Ensure the Audit Plugin Can't be Unloaded (Automated)
echo "server_audit=FORCE_PLUS_PERMANENT" >> $MARIADB_CONFIG

# 6.6 Ensure Binary and Relay Logs are Encrypted (Automated)
echo "encrypt_binlog=ON" >> $MARIADB_CONFIG

# 7.1 Disable use of the mysql_old_password plugin (Automated)
mysql -u root -p$MARIADB_ROOT_PASSWORD -e "SET GLOBAL old_passwords=0;"
mysql -u root -p$MARIADB_ROOT_PASSWORD -e "SET GLOBAL secure_auth=ON;"

# 7.2 Ensure Passwords are Not Stored in the Global Configuration (Automated)
# Ensure passwords are not stored in the global configuration

# 7.3 Ensure strong authentication is utilized for all accounts (Automated)
mysql -u root -p$MARIADB_ROOT_PASSWORD -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket;"
mysql -u root -p$MARIADB_ROOT_PASSWORD -e "SET PASSWORD FOR 'mysql'@'localhost' = 'invalid';"
mysql -u root -p$MARIADB_ROOT_PASSWORD -e "SET PASSWORD FOR 'mariadb.sys'@'localhost' = 'invalid';"

# 7.4 Ensure Password Complexity Policies are in Place (Automated)
echo "plugin_load_add = simple_password_check" >> $MARIADB_CONFIG
echo "simple_password_check = FORCE_PLUS_PERMANENT" >> $MARIADB_CONFIG
echo "simple_password_check_minimal_length = 14" >> $MARIADB_CONFIG
echo "plugin_load_add = cracklib_password_check" >> $MARIADB_CONFIG
echo "cracklib_password_check = FORCE_PLUS_PERMANENT" >> $MARIADB_CONFIG
echo "strict_password_validation = ON" >> $MARIADB_CONFIG

# 7.5 Ensure No Users Have Wildcard Hostnames (Automated)
mysql -u root -p$MARIADB_ROOT_PASSWORD -e "DELETE FROM mysql.user WHERE host = '%';"

# 7.6 Ensure No Anonymous Accounts Exist (Automated)
mysql -u root -p$MARIADB_ROOT_PASSWORD -e "DELETE FROM mysql.user WHERE user = '';"

# 7.7 Prevent Password Reuse (Manual)
echo "plugin_load_add = password_reuse_check" >> $MARIADB_CONFIG
echo "password_reuse_check = FORCE_PLUS_PERMANENT" >> $MARIADB_CONFIG
echo "strict_password_validation = ON" >> $MARIADB_CONFIG

# 8.1 Ensure 'require_secure_transport' is Set to 'ON' and 'have_ssl' is Set to 'YES' (Automated)
sed -i 's/^require_secure_transport.*/require_secure_transport = ON/' $MARIADB_CONFIG
sed -i 's/^have_ssl.*/have_ssl = YES/' $MARIADB_CONFIG

# 8.2 Ensure 'ssl_type' is Set to 'ANY', 'X509', or 'SPECIFIED' for All Remote Users (Automated)
mysql -u root -p$MARIADB_ROOT_PASSWORD -e "ALTER USER 'remoteuser'@'%' REQUIRE SSL;"

# 8.3 Set Maximum Connection Limits for Server and per User (Manual)
sed -i 's/^max_connections.*/max_connections = 100/' $MARIADB_CONFIG
sed -i 's/^max_user_connections.*/max_user_connections = 10/' $MARIADB_CONFIG

# 9.1 Ensure Replication Traffic is Secured (Manual)
# Ensure replication traffic is secured using SSL/TLS

# 9.2 Ensure 'MASTER_SSL_VERIFY_SERVER_CERT' is enabled (Automated)
mysql -u root -p$MARIADB_ROOT_PASSWORD -e "CHANGE MASTER TO MASTER_SSL_VERIFY_SERVER_CERT=1;"

# 9.3 Ensure 'super_priv' is Not Set to 'Y' for Replication Users (Automated)
mysql -u root -p$MARIADB_ROOT_PASSWORD -e "REVOKE SUPER ON *.* FROM 'repl'@'%';"

# 9.4 Ensure only approved ciphers are used for Replication (Manual)
mysql -u root -p$MARIADB_ROOT_PASSWORD -e "CHANGE MASTER TO MASTER_SSL_CIPHER='ECDHE-ECDSA-AES128-GCM-SHA256';"

# 9.5 Ensure mutual TLS is enabled (Manual)
mysql -u root -p$MARIADB_ROOT_PASSWORD -e "CHANGE MASTER TO MASTER_SSL_CERT='/etc/mysql/server-cert.pem', MASTER_SSL_KEY='/etc/mysql/server-key.pem';"

# Restart MariaDB to apply changes
systemctl restart mariadb

echo "MariaDB configuration and hardening complete."
