#!/bin/bash

# CIS Apache HTTP Server 2.4 Benchmark Configuration Script
# Version: 2.3.0
# Date: 09-23-2025
# Compatible with: Ubuntu and Linux Mint

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

# Detect distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
else
    print_error "Cannot detect distribution"
    exit 1
fi

if [[ "$DISTRO" != "ubuntu" && "$DISTRO" != "linuxmint" ]]; then
    print_error "This script is designed for Ubuntu and Linux Mint only"
    exit 1
fi

print_status "Detected distribution: $DISTRO"

# Update package lists
print_status "Updating package lists..."
apt-get update

# Install Apache2 if not already installed
if ! command -v apache2 &> /dev/null; then
    print_status "Installing Apache2..."
    apt-get install -y apache2 apache2-utils
else
    print_status "Apache2 is already installed"
fi

# Define paths based on distribution
if [[ "$DISTRO" == "ubuntu" || "$DISTRO" == "linuxmint" ]]; then
    APACHE_CONF_DIR="/etc/apache2"
    APACHE_CONF="$APACHE_CONF_DIR/apache2.conf"
    SITES_AVAILABLE="$APACHE_CONF_DIR/sites-available"
    SITES_ENABLED="$APACHE_CONF_DIR/sites-enabled"
    MODS_AVAILABLE="$APACHE_CONF_DIR/mods-available"
    MODS_ENABLED="$APACHE_CONF_DIR/mods-enabled"
    CONF_AVAILABLE="$APACHE_CONF_DIR/conf-available"
    CONF_ENABLED="$APACHE_CONF_DIR/conf-enabled"
    WWW_DIR="/var/www/html"
    LOG_DIR="/var/log/apache2"
    LOCK_FILE="/var/lock/apache2/accept.lock"
    PID_FILE="/var/run/apache2/apache2.pid"
    SCOREBOARD_FILE="/var/run/apache2/apache2.scoreboard"
    USER="www-data"
    GROUP="www-data"
fi

# Create backup directory
BACKUP_DIR="/root/apache2_backup_$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR"
print_status "Created backup directory: $BACKUP_DIR"

# Backup original configuration files
print_status "Backing up original configuration files..."
cp -r "$APACHE_CONF_DIR" "$BACKUP_DIR/"

# 1. Planning and Installation
print_status "Section 1: Planning and Installation"

# 1.1 Ensure the Pre-Installation Planning Checklist Has Been Implemented (Manual)
print_status "1.1 Pre-Installation Planning Checklist"
print_warning "Manual step: Review and implement the pre-installation planning checklist"
print_warning "- Reviewed and implemented company's security policies"
print_warning "- Implemented a secure network infrastructure"
print_warning "- Harden the underlying Operating System"
print_warning "- Implement central log monitoring processes"
print_warning "- Implemented a disk space monitoring process and log rotation mechanism"
print_warning "- Educate developers about secure applications"
print_warning "- Ensure WHOIS Domain information does not reveal sensitive information"
print_warning "- Ensure DNS servers are properly secured"
print_warning "- Implemented a Network Intrusion Detection System"

# 1.2 Ensure the Server Is Not a Multi-Use System (Manual)
print_status "1.2 Ensure the Server Is Not a Multi-Use System"
print_warning "Manual step: Review and disable unnecessary services"
print_status "Listing enabled services..."
systemctl list-unit-files --state enabled

# 1.3 Ensure Apache Is Installed From the Appropriate Binaries (Manual)
print_status "1.3 Ensure Apache Is Installed From the Appropriate Binaries"
print_status "Apache2 is installed from the distribution's package repository"

# 2. Minimize Apache Modules
print_status "Section 2: Minimize Apache Modules"

# 2.1 Ensure Only Necessary Authentication and Authorization Modules Are Enabled (Manual)
print_status "2.1 Ensure Only Necessary Authentication and Authorization Modules Are Enabled"
print_warning "Manual step: Review and disable unnecessary authentication and authorization modules"
print_status "Currently loaded authentication and authorization modules:"
apache2ctl -M | grep auth

# 2.2 Ensure the Log Config Module Is Enabled (Automated)
print_status "2.2 Ensure the Log Config Module Is Enabled"
if apache2ctl -M | grep -q "log_config_module"; then
    print_status "log_config_module is already enabled"
else
    print_status "Enabling log_config_module..."
    a2enmod log_config
fi

# 2.3 Ensure the WebDAV Modules Are Disabled (Automated)
print_status "2.3 Ensure the WebDAV Modules Are Disabled"
if apache2ctl -M | grep -q "dav_module"; then
    print_status "Disabling dav_module..."
    a2dismod dav
    a2dismod dav_fs
else
    print_status "WebDAV modules are already disabled"
fi

# 2.4 Ensure the Status Module Is Disabled (Automated)
print_status "2.4 Ensure the Status Module Is Disabled"
if apache2ctl -M | grep -q "status_module"; then
    print_status "Disabling status_module..."
    a2dismod status
else
    print_status "status_module is already disabled"
fi

# 2.5 Ensure the Autoindex Module Is Disabled (Automated)
print_status "2.5 Ensure the Autoindex Module Is Disabled"
if apache2ctl -M | grep -q "autoindex_module"; then
    print_status "Disabling autoindex_module..."
    a2dismod autoindex
else
    print_status "autoindex_module is already disabled"
fi

# 2.6 Ensure the Proxy Modules Are Disabled if not in use (Automated)
print_status "2.6 Ensure the Proxy Modules Are Disabled if not in use"
if apache2ctl -M | grep -q "proxy_module"; then
    print_status "Disabling proxy modules..."
    a2dismod proxy
    a2dismod proxy_http
    a2dismod proxy_ftp
else
    print_status "Proxy modules are already disabled"
fi

# 2.7 Ensure the User Directories Module Is Disabled (Automated)
print_status "2.7 Ensure the User Directories Module Is Disabled"
if apache2ctl -M | grep -q "userdir_module"; then
    print_status "Disabling userdir_module..."
    a2dismod userdir
else
    print_status "userdir_module is already disabled"
fi

# 2.8 Ensure the Info Module Is Disabled (Automated)
print_status "2.8 Ensure the Info Module Is Disabled"
if apache2ctl -M | grep -q "info_module"; then
    print_status "Disabling info_module..."
    a2dismod info
else
    print_status "info_module is already disabled"
fi

# 2.9 Ensure the Basic and Digest Authentication Modules are Disabled (Automated)
print_status "2.9 Ensure the Basic and Digest Authentication Modules are Disabled"
if apache2ctl -M | grep -q "auth_basic_module"; then
    print_status "Disabling auth_basic_module..."
    a2dismod auth_basic
fi

if apache2ctl -M | grep -q "auth_digest_module"; then
    print_status "Disabling auth_digest_module..."
    a2dismod auth_digest
else
    print_status "Basic and Digest authentication modules are already disabled"
fi

# 3. Principles, Permissions, and Ownership
print_status "Section 3: Principles, Permissions, and Ownership"

# 3.1 Ensure the Apache Web Server Runs As a Non-Root User (Automated)
print_status "3.1 Ensure the Apache Web Server Runs As a Non-Root User"
if grep -q "^User $USER" "$APACHE_CONF"; then
    print_status "Apache is already configured to run as non-root user: $USER"
else
    print_status "Configuring Apache to run as non-root user: $USER"
    sed -i "s/^User .*/User $USER/" "$APACHE_CONF"
fi

# 3.2 Ensure the Apache User Account Has an Invalid Shell (Automated)
print_status "3.2 Ensure the Apache User Account Has an Invalid Shell"
if getent passwd "$USER" | grep -q "/usr/sbin/nologin\|/bin/false"; then
    print_status "Apache user account already has an invalid shell"
else
    print_status "Setting invalid shell for Apache user account"
    usermod -s /usr/sbin/nologin "$USER"
fi

# 3.3 Ensure the Apache User Account Is Locked (Automated)
print_status "3.3 Ensure the Apache User Account Is Locked"
if passwd -S "$USER" | grep -q "L"; then
    print_status "Apache user account is already locked"
else
    print_status "Locking Apache user account"
    passwd -l "$USER"
fi

# 3.4 Ensure Apache Directories and Files Are Owned By Root (Automated)
print_status "3.4 Ensure Apache Directories and Files Are Owned By Root"
print_status "Setting ownership of Apache directories and files to root"
chown -R root:root "$APACHE_CONF_DIR"

# 3.5 Ensure the Group Is Set Correctly on Apache Directories and Files (Automated)
print_status "3.5 Ensure the Group Is Set Correctly on Apache Directories and Files"
print_status "Setting group ownership of Apache directories and files to $GROUP"
chown -R root:"$GROUP" "$APACHE_CONF_DIR"

# 3.6 Ensure Other Write Access on Apache Directories and Files Is Restricted (Automated)
print_status "3.6 Ensure Other Write Access on Apache Directories and Files Is Restricted"
print_status "Removing write permissions for others on Apache directories and files"
chmod -R o-w "$APACHE_CONF_DIR"

# 3.7 Ensure the Core Dump Directory Is Secured (Manual)
print_status "3.7 Ensure the Core Dump Directory Is Secured"
print_warning "Manual step: Ensure the CoreDumpDirectory is secured"
if grep -q "^CoreDumpDirectory" "$APACHE_CONF"; then
    CORE_DUMP_DIR=$(grep "^CoreDumpDirectory" "$APACHE_CONF" | awk '{print $2}')
    if [ -n "$CORE_DUMP_DIR" ]; then
        print_status "Securing core dump directory: $CORE_DUMP_DIR"
        mkdir -p "$CORE_DUMP_DIR"
        chown root:"$GROUP" "$CORE_DUMP_DIR"
        chmod 750 "$CORE_DUMP_DIR"
    fi
else
    print_status "CoreDumpDirectory not configured, adding configuration"
    echo "CoreDumpDirectory /var/log/apache2/core-dumps" >> "$APACHE_CONF"
    mkdir -p /var/log/apache2/core-dumps
    chown root:"$GROUP" /var/log/apache2/core-dumps
    chmod 750 /var/log/apache2/core-dumps
fi

# 3.8 Ensure the Lock File Is Secured (Manual)
print_status "3.8 Ensure the Lock File Is Secured"
print_warning "Manual step: Ensure the lock file is secured"
if [ -f "$LOCK_FILE" ]; then
    print_status "Securing lock file: $LOCK_FILE"
    chown root:"$GROUP" "$LOCK_FILE"
    chmod 640 "$LOCK_FILE"
else
    print_status "Lock file does not exist: $LOCK_FILE"
fi

# 3.9 Ensure the Pid File Is Secured (Manual)
print_status "3.9 Ensure the Pid File Is Secured"
print_warning "Manual step: Ensure the PID file is secured"
if [ -f "$PID_FILE" ]; then
    print_status "Securing PID file: $PID_FILE"
    chown root:"$GROUP" "$PID_FILE"
    chmod 640 "$PID_FILE"
else
    print_status "PID file does not exist: $PID_FILE"
fi

# 3.10 Ensure the ScoreBoard File Is Secured (Manual)
print_status "3.10 Ensure the ScoreBoard File Is Secured"
print_warning "Manual step: Ensure the scoreboard file is secured"
if [ -f "$SCOREBOARD_FILE" ]; then
    print_status "Securing scoreboard file: $SCOREBOARD_FILE"
    chown root:"$GROUP" "$SCOREBOARD_FILE"
    chmod 640 "$SCOREBOARD_FILE"
else
    print_status "Scoreboard file does not exist: $SCOREBOARD_FILE"
fi

# 3.11 Ensure Group Write Access for the Apache Directories and Files Is Properly Restricted (Manual)
print_status "3.11 Ensure Group Write Access for the Apache Directories and Files Is Properly Restricted"
print_warning "Manual step: Review and restrict group write access for Apache directories and files"
print_status "Current permissions on Apache configuration directories:"
find "$APACHE_CONF_DIR" -type d -exec ls -ld {} \;

# 3.12 Ensure Group Write Access for the Document Root Directories and Files Is Properly Restricted (Manual)
print_status "3.12 Ensure Group Write Access for the Document Root Directories and Files Is Properly Restricted"
print_warning "Manual step: Review and restrict group write access for document root directories and files"
print_status "Current permissions on document root directories:"
find "$WWW_DIR" -type d -exec ls -ld {} \;

# 3.13 Ensure Access to Special Purpose Application Writable Directories is Properly Restricted (Manual)
print_status "3.13 Ensure Access to Special Purpose Application Writable Directories is Properly Restricted"
print_warning "Manual step: Review and restrict access to special purpose application writable directories"

# 4. Apache Access Control
print_status "Section 4: Apache Access Control"

# 4.1 Ensure Access to OS Root Directory Is Denied By Default (Automated)
print_status "4.1 Ensure Access to OS Root Directory Is Denied By Default"
if grep -q "<Directory />" "$APACHE_CONF"; then
    if grep -A 5 "<Directory />" "$APACHE_CONF" | grep -q "Require all denied"; then
        print_status "Access to OS root directory is already denied by default"
    else
        print_status "Configuring access to OS root directory to be denied by default"
        sed -i '/<Directory \/>/,/<\/Directory>/ s/Require all granted/Require all denied/' "$APACHE_CONF"
    fi
else
    print_status "Adding directory configuration for OS root directory"
    cat >> "$APACHE_CONF" << EOF

<Directory />
    Options None
    AllowOverride None
    Require all denied
</Directory>
EOF
fi

# 4.2 Ensure Appropriate Access to Web Content Is Allowed (Manual)
print_status "4.2 Ensure Appropriate Access to Web Content Is Allowed"
print_warning "Manual step: Review and configure appropriate access to web content"
if grep -q "<Directory $WWW_DIR>" "$APACHE_CONF"; then
    print_status "Web content directory is already configured"
else
    print_status "Adding directory configuration for web content"
    cat >> "$APACHE_CONF" << EOF

<Directory $WWW_DIR>
    Options None
    AllowOverride None
    Require all granted
</Directory>
EOF
fi

# 4.3 Ensure OverRide Is Disabled for the OS Root Directory (Automated)
print_status "4.3 Ensure OverRide Is Disabled for the OS Root Directory"
if grep -A 5 "<Directory />" "$APACHE_CONF" | grep -q "AllowOverride None"; then
    print_status "Override is already disabled for the OS root directory"
else
    print_status "Disabling Override for the OS root directory"
    sed -i '/<Directory \/>/,/<\/Directory>/ s/AllowOverride .*/AllowOverride None/' "$APACHE_CONF"
fi

# 4.4 Ensure OverRide Is Disabled for All Directories (Automated)
print_status "4.4 Ensure OverRide Is Disabled for All Directories"
if grep -q "AllowOverride None" "$APACHE_CONF"; then
    print_status "Override is already disabled for all directories"
else
    print_status "Disabling Override for all directories"
    sed -i 's/AllowOverride .*/AllowOverride None/g' "$APACHE_CONF"
fi

# 5. Minimize Features, Content and Options
print_status "Section 5: Minimize Features, Content and Options"

# 5.1 Ensure Options for the OS Root Directory Are Restricted (Automated)
print_status "5.1 Ensure Options for the OS Root Directory Are Restricted"
if grep -A 5 "<Directory />" "$APACHE_CONF" | grep -q "Options None"; then
    print_status "Options for the OS root directory are already restricted"
else
    print_status "Restricting options for the OS root directory"
    sed -i '/<Directory \/>/,/<\/Directory>/ s/Options .*/Options None/' "$APACHE_CONF"
fi

# 5.2 Ensure Options for the Web Root Directory Are Restricted (Automated)
print_status "5.2 Ensure Options for the Web Root Directory Are Restricted"
if grep -A 5 "<Directory $WWW_DIR>" "$APACHE_CONF" | grep -q "Options None"; then
    print_status "Options for the web root directory are already restricted"
else
    print_status "Restricting options for the web root directory"
    sed -i "/<Directory $WWW_DIR>/,/<\/Directory>/ s/Options .*/Options None/" "$APACHE_CONF"
fi

# 5.3 Ensure Options for Other Directories Are Minimized (Automated)
print_status "5.3 Ensure Options for Other Directories Are Minimized"
print_warning "Manual step: Review and minimize options for other directories"
print_status "Current directory configurations:"
grep -n "<Directory" "$APACHE_CONF"

# 5.4 Ensure Default HTML Content Is Removed (Manual)
print_status "5.4 Ensure Default HTML Content Is Removed"
if [ -f "$WWW_DIR/index.html" ]; then
    print_status "Removing default HTML content"
    rm -f "$WWW_DIR/index.html"
else
    print_status "Default HTML content is already removed"
fi

# 5.5 Ensure the Default CGI Content printenv Script Is Removed (Manual)
print_status "5.5 Ensure the Default CGI Content printenv Script Is Removed"
if [ -f "/usr/lib/cgi-bin/printenv" ]; then
    print_status "Removing default CGI content printenv script"
    rm -f "/usr/lib/cgi-bin/printenv"
else
    print_status "Default CGI content printenv script is already removed"
fi

# 5.6 Ensure the Default CGI Content test-cgi Script Is Removed (Manual)
print_status "5.6 Ensure the Default CGI Content test-cgi Script Is Removed"
if [ -f "/usr/lib/cgi-bin/test-cgi" ]; then
    print_status "Removing default CGI content test-cgi script"
    rm -f "/usr/lib/cgi-bin/test-cgi"
else
    print_status "Default CGI content test-cgi script is already removed"
fi

# 5.7 Ensure HTTP Request Methods Are Restricted (Manual)
print_status "5.7 Ensure HTTP Request Methods Are Restricted"
print_warning "Manual step: Review and restrict HTTP request methods"
if grep -q "<LimitExcept GET POST HEAD>" "$APACHE_CONF"; then
    print_status "HTTP request methods are already restricted"
else
    print_status "Adding configuration to restrict HTTP request methods"
    cat >> "$APACHE_CONF" << EOF

<LimitExcept GET POST HEAD>
    Require all denied
</LimitExcept>
EOF
fi

# 5.8 Ensure the HTTP TRACE Method Is Disabled (Automated)
print_status "5.8 Ensure the HTTP TRACE Method Is Disabled"
if grep -q "TraceEnable Off" "$APACHE_CONF"; then
    print_status "HTTP TRACE method is already disabled"
else
    print_status "Disabling HTTP TRACE method"
    echo "TraceEnable Off" >> "$APACHE_CONF"
fi

# 5.9 Ensure Old HTTP Protocol Versions Are Disallowed (Automated)
print_status "5.9 Ensure Old HTTP Protocol Versions Are Disallowed"
if grep -q "Protocols" "$APACHE_CONF"; then
    print_status "HTTP protocol versions are already configured"
else
    print_status "Configuring HTTP protocol versions"
    echo "Protocols h2 h2c http/1.1" >> "$APACHE_CONF"
fi

# 5.10 Ensure Access to .ht* Files Is Restricted (Automated)
print_status "5.10 Ensure Access to .ht* Files Is Restricted"
if grep -q "<Files \"^.ht\">" "$APACHE_CONF"; then
    print_status "Access to .ht* files is already restricted"
else
    print_status "Restricting access to .ht* files"
    cat >> "$APACHE_CONF" << EOF

<Files "^\.ht">
    Require all denied
</Files>
EOF
fi

# 5.11 Ensure Access to .git Files Is Restricted (Manual)
print_status "5.11 Ensure Access to .git Files Is Restricted"
if grep -q "<DirectoryMatch \"\.git\">" "$APACHE_CONF"; then
    print_status "Access to .git files is already restricted"
else
    print_status "Restricting access to .git files"
    cat >> "$APACHE_CONF" << EOF

<DirectoryMatch "\.git">
    Require all denied
</DirectoryMatch>
EOF
fi

# 5.12 Ensure Access to .svn Files Is Restricted (Manual)
print_status "5.12 Ensure Access to .svn Files Is Restricted"
if grep -q "<DirectoryMatch \"\.svn\">" "$APACHE_CONF"; then
    print_status "Access to .svn files is already restricted"
else
    print_status "Restricting access to .svn files"
    cat >> "$APACHE_CONF" << EOF

<DirectoryMatch "\.svn">
    Require all denied
</DirectoryMatch>
EOF
fi

# 5.13 Ensure Access to Inappropriate File Extensions Is Restricted (Manual)
print_status "5.13 Ensure Access to Inappropriate File Extensions Is Restricted"
print_warning "Manual step: Review and restrict access to inappropriate file extensions"
if grep -q "<FilesMatch \"\.(bak|config|dist|fla|inc|ini|log|psd|sh|sql|swp)$\">" "$APACHE_CONF"; then
    print_status "Access to inappropriate file extensions is already restricted"
else
    print_status "Restricting access to inappropriate file extensions"
    cat >> "$APACHE_CONF" << EOF

<FilesMatch "\.(bak|config|dist|fla|inc|ini|log|psd|sh|sql|swp)$">
    Require all denied
</FilesMatch>
EOF
fi

# 5.14 Ensure IP Address Based Requests Are Disallowed (Automated)
print_status "5.14 Ensure IP Address Based Requests Are Disallowed"
if grep -q "UseCanonicalName On" "$APACHE_CONF"; then
    print_status "IP address based requests are already disallowed"
else
    print_status "Disallowing IP address based requests"
    echo "UseCanonicalName On" >> "$APACHE_CONF"
fi

# 5.15 Ensure the IP Addresses for Listening for Requests Are Specified (Automated)
print_status "5.15 Ensure the IP Addresses for Listening for Requests Are Specified"
if grep -q "Listen 80" "$APACHE_CONF_DIR/ports.conf"; then
    print_status "IP addresses for listening are already specified"
else
    print_status "Configuring IP addresses for listening"
    sed -i 's/Listen 80/Listen 0.0.0.0:80/' "$APACHE_CONF_DIR/ports.conf"
fi

# 5.16 Ensure Browser Framing Is Restricted (Automated)
print_status "5.16 Ensure Browser Framing Is Restricted"
if grep -q "Header always set X-Frame-Options" "$APACHE_CONF"; then
    print_status "Browser framing is already restricted"
else
    print_status "Restricting browser framing"
    echo "Header always set X-Frame-Options \"SAMEORIGIN\"" >> "$APACHE_CONF"
    a2enmod headers
fi

# 5.17 Ensure HTTP Header Referrer-Policy is set appropriately (Manual)
print_status "5.17 Ensure HTTP Header Referrer-Policy is set appropriately"
if grep -q "Header always set Referrer-Policy" "$APACHE_CONF"; then
    print_status "HTTP Header Referrer-Policy is already set"
else
    print_status "Setting HTTP Header Referrer-Policy"
    echo "Header always set Referrer-Policy \"strict-origin-when-cross-origin\"" >> "$APACHE_CONF"
    a2enmod headers
fi

# 5.18 Ensure HTTP Header Permissions-Policy is set appropriately (Manual)
print_status "5.18 Ensure HTTP Header Permissions-Policy is set appropriately"
if grep -q "Header always set Permissions-Policy" "$APACHE_CONF"; then
    print_status "HTTP Header Permissions-Policy is already set"
else
    print_status "Setting HTTP Header Permissions-Policy"
    echo "Header always set Permissions-Policy \"geolocation=(), microphone=(), camera=()\"" >> "$APACHE_CONF"
    a2enmod headers
fi

# 6. Operations - Logging, Monitoring and Maintenance
print_status "Section 6: Operations - Logging, Monitoring and Maintenance"

# 6.1 Ensure the Error Log Filename and Severity Level Are Configured Correctly (Automated)
print_status "6.1 Ensure the Error Log Filename and Severity Level Are Configured Correctly"
if grep -q "ErrorLog" "$APACHE_CONF"; then
    print_status "Error log is already configured"
else
    print_status "Configuring error log"
    echo "ErrorLog $LOG_DIR/error.log" >> "$APACHE_CONF"
fi

if grep -q "LogLevel" "$APACHE_CONF"; then
    print_status "Log level is already configured"
else
    print_status "Configuring log level"
    echo "LogLevel warn" >> "$APACHE_CONF"
fi

# 6.2 Ensure a Syslog Facility Is Configured for Error Logging (Manual)
print_status "6.2 Ensure a Syslog Facility Is Configured for Error Logging"
print_warning "Manual step: Configure a syslog facility for error logging"
if grep -q "ErrorLog syslog" "$APACHE_CONF"; then
    print_status "Syslog facility is already configured for error logging"
else
    print_status "Adding syslog facility configuration for error logging"
    echo "ErrorLog syslog:local7" >> "$APACHE_CONF"
fi

# 6.3 Ensure the Server Access Log Is Configured Correctly (Manual)
print_status "6.3 Ensure the Server Access Log Is Configured Correctly"
if grep -q "CustomLog" "$APACHE_CONF"; then
    print_status "Server access log is already configured"
else
    print_status "Configuring server access log"
    echo "CustomLog $LOG_DIR/access.log combined" >> "$APACHE_CONF"
fi

# 6.4 Ensure Log Storage and Rotation Is Configured Correctly (Manual)
print_status "6.4 Ensure Log Storage and Rotation Is Configured Correctly"
print_warning "Manual step: Configure log storage and rotation"
if [ -f "/etc/logrotate.d/apache2" ]; then
    print_status "Log rotation is already configured"
else
    print_status "Adding log rotation configuration"
    cat > "/etc/logrotate.d/apache2" << EOF
 $LOG_DIR/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 640 root adm
    sharedscripts
    postrotate
        if /etc/init.d/apache2 status > /dev/null 2>&1; then
            /etc/init.d/apache2 reload > /dev/null 2>&1;
        fi;
    endscript
}
EOF
fi

# 6.5 Ensure Applicable Patches Are Applied (Manual)
print_status "6.5 Ensure Applicable Patches Are Applied"
print_warning "Manual step: Ensure applicable patches are applied"
print_status "Updating Apache2 package..."
apt-get upgrade -y apache2

# 6.6 Ensure ModSecurity Is Installed and Enabled (Automated)
print_status "6.6 Ensure ModSecurity Is Installed and Enabled"
if ! dpkg -l | grep -q "libapache2-mod-security2"; then
    print_status "Installing ModSecurity..."
    apt-get install -y libapache2-mod-security2
else
    print_status "ModSecurity is already installed"
fi

if apache2ctl -M | grep -q "security2_module"; then
    print_status "ModSecurity is already enabled"
else
    print_status "Enabling ModSecurity..."
    a2enmod security2
fi

if [ -f "/etc/modsecurity/modsecurity.conf-recommended" ] && [ ! -f "/etc/modsecurity/modsecurity.conf" ]; then
    print_status "Configuring ModSecurity..."
    cp "/etc/modsecurity/modsecurity.conf-recommended" "/etc/modsecurity/modsecurity.conf"
    sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' "/etc/modsecurity/modsecurity.conf"
fi

# 6.7 Ensure the OWASP ModSecurity Core Rule Set Is Installed and Enabled (Manual)
print_status "6.7 Ensure the OWASP ModSecurity Core Rule Set Is Installed and Enabled"
if [ ! -d "/usr/share/modsecurity-crs" ]; then
    print_status "Installing OWASP ModSecurity Core Rule Set..."
    apt-get install -y modsecurity-crs
else
    print_status "OWASP ModSecurity Core Rule Set is already installed"
fi

if [ -f "/etc/modsecurity/crs/crs-setup.conf.example" ] && [ ! -f "/etc/modsecurity/crs/crs-setup.conf" ]; then
    print_status "Configuring OWASP ModSecurity Core Rule Set..."
    cp "/etc/modsecurity/crs/crs-setup.conf.example" "/etc/modsecurity/crs/crs-setup.conf"
fi

# 7. SSL/TLS Configuration
print_status "Section 7: SSL/TLS Configuration"

# 7.1 Ensure mod_ssl and/or mod_nss Is Installed (Automated)
print_status "7.1 Ensure mod_ssl Is Installed"
if ! dpkg -l | grep -q "ssl"; then
    print_status "Installing SSL module..."
    apt-get install -y ssl-cert
    a2enmod ssl
else
    print_status "SSL module is already installed"
fi

if apache2ctl -M | grep -q "ssl_module"; then
    print_status "SSL module is already enabled"
else
    print_status "Enabling SSL module..."
    a2enmod ssl
fi

# 7.2 Ensure a Valid Trusted Certificate Is Installed (Manual)
print_status "7.2 Ensure a Valid Trusted Certificate Is Installed"
print_warning "Manual step: Install a valid trusted certificate"
if [ -f "/etc/ssl/certs/ssl-cert-snakeoil.pem" ] && [ -f "/etc/ssl/private/ssl-cert-snakeoil.key" ]; then
    print_status "Default snakeoil certificate is available"
    print_warning "Replace with a valid trusted certificate in production"
else
    print_status "Creating default snakeoil certificate"
    make-ssl-cert generate-default-snakeoil --force-overwrite
fi

# 7.3 Ensure the Server's Private Key Is Protected (Manual)
print_status "7.3 Ensure the Server's Private Key Is Protected"
print_warning "Manual step: Ensure the server's private key is protected"
if [ -f "/etc/ssl/private/ssl-cert-snakeoil.key" ]; then
    print_status "Setting permissions on private key"
    chmod 600 "/etc/ssl/private/ssl-cert-snakeoil.key"
    chown root:root "/etc/ssl/private/ssl-cert-snakeoil.key"
fi

# 7.4 Ensure the TLSv1.0 and TLSv1.1 Protocols are Disabled (Manual)
print_status "7.4 Ensure the TLSv1.0 and TLSv1.1 Protocols are Disabled"
if grep -q "SSLProtocol" "$APACHE_CONF"; then
    print_status "SSL protocol is already configured"
else
    print_status "Configuring SSL protocol to disable TLSv1.0 and TLSv1.1"
    echo "SSLProtocol all -SSLv2 -SSLv3 -TLSv1 -TLSv1.1" >> "$APACHE_CONF"
fi

# 7.5 Ensure Weak SSL/TLS Ciphers Are Disabled (Manual)
print_status "7.5 Ensure Weak SSL/TLS Ciphers Are Disabled"
if grep -q "SSLCipherSuite" "$APACHE_CONF"; then
    print_status "SSL cipher suite is already configured"
else
    print_status "Configuring SSL cipher suite to disable weak ciphers"
    echo "SSLCipherSuite HIGH:!aNULL:!MD5:!3DES" >> "$APACHE_CONF"
fi

# 7.6 Ensure Insecure SSL Renegotiation Is Not Enabled (Manual)
print_status "7.6 Ensure Insecure SSL Renegotiation Is Not Enabled"
if grep -q "SSLInsecureRenegotiation" "$APACHE_CONF"; then
    print_status "SSL renegotiation is already configured"
else
    print_status "Configuring SSL renegotiation"
    echo "SSLInsecureRenegotiation off" >> "$APACHE_CONF"
fi

# 7.7 Ensure SSL Compression is not Enabled (Manual)
print_status "7.7 Ensure SSL Compression is not Enabled"
if grep -q "SSLCompression" "$APACHE_CONF"; then
    print_status "SSL compression is already configured"
else
    print_status "Configuring SSL compression"
    echo "SSLCompression off" >> "$APACHE_CONF"
fi

# 7.8 Ensure Medium Strength SSL/TLS Ciphers Are Disabled (Manual)
print_status "7.8 Ensure Medium Strength SSL/TLS Ciphers Are Disabled"
if grep -q "SSLCipherSuite" "$APACHE_CONF"; then
    print_status "SSL cipher suite is already configured"
else
    print_status "Configuring SSL cipher suite to disable medium strength ciphers"
    echo "SSLCipherSuite ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256" >> "$APACHE_CONF"
fi

# 7.9 Ensure All Web Content is Accessed via HTTPS (Manual)
print_status "7.9 Ensure All Web Content is Accessed via HTTPS"
print_warning "Manual step: Configure all web content to be accessed via HTTPS"
if [ -f "$SITES_AVAILABLE/default-ssl.conf" ]; then
    print_status "SSL site configuration is already available"
else
    print_status "Creating SSL site configuration"
    cp "$SITES_AVAILABLE/default-ssl.conf" "$SITES_AVAILABLE/default-ssl.conf.bak"
    cat > "$SITES_AVAILABLE/default-ssl.conf" << EOF
<IfModule mod_ssl.c>
    <VirtualHost _default_:443>
        ServerAdmin webmaster@localhost
        DocumentRoot $WWW_DIR

        ErrorLog $LOG_DIR/error.log
        CustomLog $LOG_DIR/access.log combined

        SSLEngine on
        SSLCertificateFile    /etc/ssl/certs/ssl-cert-snakeoil.pem
        SSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key

        <FilesMatch "\.(cgi|shtml|phtml|php)$">
            SSLOptions +StdEnvVars
        </FilesMatch>
        <Directory /usr/lib/cgi-bin>
            SSLOptions +StdEnvVars
        </Directory>

        BrowserMatch "MSIE [2-6]" \
            nokeepalive ssl-unclean-shutdown \
            downgrade-1.0 force-response-1.0
        BrowserMatch "MSIE [17-9]" ssl-unclean-shutdown
    </VirtualHost>
</IfModule>
EOF
fi

if [ ! -L "$SITES_ENABLED/default-ssl.conf" ]; then
    print_status "Enabling SSL site"
    a2ensite default-ssl
fi

# 7.10 Ensure OCSP Stapling Is Enabled (Manual)
print_status "7.10 Ensure OCSP Stapling Is Enabled"
if grep -q "SSLUseStapling" "$APACHE_CONF"; then
    print_status "OCSP stapling is already configured"
else
    print_status "Configuring OCSP stapling"
    echo "SSLUseStapling on" >> "$APACHE_CONF"
    echo "SSLStaplingCache \"shmcb:/var/run/ocsp(128000)\"" >> "$APACHE_CONF"
fi

# 7.11 Ensure HTTP Strict Transport Security Is Enabled (Manual)
print_status "7.11 Ensure HTTP Strict Transport Security Is Enabled"
if grep -q "Header always set Strict-Transport-Security" "$APACHE_CONF"; then
    print_status "HTTP Strict Transport Security is already enabled"
else
    print_status "Enabling HTTP Strict Transport Security"
    echo "Header always set Strict-Transport-Security \"max-age=63072000; includeSubDomains; preload\"" >> "$APACHE_CONF"
    a2enmod headers
fi

# 7.12 Ensure Only Cipher Suites That Provide Forward Secrecy Are Enabled (Manual)
print_status "7.12 Ensure Only Cipher Suites That Provide Forward Secrecy Are Enabled"
if grep -q "SSLCipherSuite" "$APACHE_CONF"; then
    print_status "SSL cipher suite is already configured"
else
    print_status "Configuring SSL cipher suite to only include cipher suites that provide forward secrecy"
    echo "SSLCipherSuite ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256" >> "$APACHE_CONF"
fi

# 8. Information Leakage
print_status "Section 8: Information Leakage"

# 8.1 Ensure ServerTokens is Set to 'Prod' or 'ProductOnly' (Automated)
print_status "8.1 Ensure ServerTokens is Set to 'Prod' or 'ProductOnly'"
if grep -q "ServerTokens Prod" "$APACHE_CONF"; then
    print_status "ServerTokens is already set to 'Prod'"
else
    print_status "Setting ServerTokens to 'Prod'"
    sed -i 's/#ServerTokens.*/ServerTokens Prod/' "$APACHE_CONF"
    if ! grep -q "ServerTokens" "$APACHE_CONF"; then
        echo "ServerTokens Prod" >> "$APACHE_CONF"
    fi
fi

# 8.2 Ensure ServerSignature Is Not Enabled (Automated)
print_status "8.2 Ensure ServerSignature Is Not Enabled"
if grep -q "ServerSignature Off" "$APACHE_CONF"; then
    print_status "ServerSignature is already set to 'Off'"
else
    print_status "Setting ServerSignature to 'Off'"
    sed -i 's/#ServerSignature.*/ServerSignature Off/' "$APACHE_CONF"
    if ! grep -q "ServerSignature" "$APACHE_CONF"; then
        echo "ServerSignature Off" >> "$APACHE_CONF"
    fi
fi

# 8.3 Ensure All Default Apache Content Is Removed (Manual)
print_status "8.3 Ensure All Default Apache Content Is Removed"
if [ -d "$WWW_DIR" ]; then
    print_status "Removing default Apache content"
    rm -rf "$WWW_DIR"/*
else
    print_status "Default Apache content is already removed"
fi

# 8.4 Ensure ETag Response Header Fields Do Not Include Inodes (Automated)
print_status "8.4 Ensure ETag Response Header Fields Do Not Include Inodes"
if grep -q "FileETag None" "$APACHE_CONF"; then
    print_status "ETag response header fields are already configured to not include inodes"
else
    print_status "Configuring ETag response header fields to not include inodes"
    echo "FileETag None" >> "$APACHE_CONF"
fi

# 9. Denial of Service Mitigations
print_status "Section 9: Denial of Service Mitigations"

# 9.1 Ensure the TimeOut Is Set to 10 or Less (Automated)
print_status "9.1 Ensure the TimeOut Is Set to 10 or Less"
if grep -q "TimeOut 10" "$APACHE_CONF"; then
    print_status "TimeOut is already set to 10"
else
    print_status "Setting TimeOut to 10"
    sed -i 's/TimeOut.*/TimeOut 10/' "$APACHE_CONF"
    if ! grep -q "TimeOut" "$APACHE_CONF"; then
        echo "TimeOut 10" >> "$APACHE_CONF"
    fi
fi

# 9.2 Ensure KeepAlive Is Enabled (Automated)
print_status "9.2 Ensure KeepAlive Is Enabled"
if grep -q "KeepAlive On" "$APACHE_CONF"; then
    print_status "KeepAlive is already enabled"
else
    print_status "Enabling KeepAlive"
    sed -i 's/#KeepAlive.*/KeepAlive On/' "$APACHE_CONF"
    if ! grep -q "KeepAlive" "$APACHE_CONF"; then
        echo "KeepAlive On" >> "$APACHE_CONF"
    fi
fi

# 9.3 Ensure MaxKeepAliveRequests is Set to a Value of 100 or Greater (Automated)
print_status "9.3 Ensure MaxKeepAliveRequests is Set to a Value of 100 or Greater"
if grep -q "MaxKeepAliveRequests 100" "$APACHE_CONF"; then
    print_status "MaxKeepAliveRequests is already set to 100"
else
    print_status "Setting MaxKeepAliveRequests to 100"
    sed -i 's/MaxKeepAliveRequests.*/MaxKeepAliveRequests 100/' "$APACHE_CONF"
    if ! grep -q "MaxKeepAliveRequests" "$APACHE_CONF"; then
        echo "MaxKeepAliveRequests 100" >> "$APACHE_CONF"
    fi
fi

# 9.4 Ensure KeepAliveTimeout is Set to a Value of 15 or Less (Automated)
print_status "9.4 Ensure KeepAliveTimeout is Set to a Value of 15 or Less"
if grep -q "KeepAliveTimeout 15" "$APACHE_CONF"; then
    print_status "KeepAliveTimeout is already set to 15"
else
    print_status "Setting KeepAliveTimeout to 15"
    sed -i 's/KeepAliveTimeout.*/KeepAliveTimeout 15/' "$APACHE_CONF"
    if ! grep -q "KeepAliveTimeout" "$APACHE_CONF"; then
        echo "KeepAliveTimeout 15" >> "$APACHE_CONF"
    fi
fi

# 9.5 Ensure the Timeout Limits for Request Headers is Set to 40 or Less (Manual)
print_status "9.5 Ensure the Timeout Limits for Request Headers is Set to 40 or Less"
if grep -q "RequestReadTimeout" "$APACHE_CONF"; then
    print_status "Request header timeout is already configured"
else
    print_status "Setting request header timeout to 40"
    echo "RequestReadTimeout header=40-40,MinRate=500 body=10,MinRate=500" >> "$APACHE_CONF"
    a2enmod reqtimeout
fi

# 9.6 Ensure Timeout Limits for the Request Body is Set to 20 or Less (Manual)
print_status "9.6 Ensure Timeout Limits for the Request Body is Set to 20 or Less"
if grep -q "RequestReadTimeout" "$APACHE_CONF"; then
    print_status "Request body timeout is already configured"
else
    print_status "Setting request body timeout to 20"
    echo "RequestReadTimeout header=40-40,MinRate=500 body=20,MinRate=500" >> "$APACHE_CONF"
    a2enmod reqtimeout
fi

# 10. Request Limits
print_status "Section 10: Request Limits"

# 10.1 Ensure the LimitRequestLine directive is Set to 8190 or less but not 0 (Automated)
print_status "10.1 Ensure the LimitRequestLine directive is Set to 8190 or less but not 0"
if grep -q "LimitRequestLine 8190" "$APACHE_CONF"; then
    print_status "LimitRequestLine is already set to 8190"
else
    print_status "Setting LimitRequestLine to 8190"
    sed -i 's/LimitRequestLine.*/LimitRequestLine 8190/' "$APACHE_CONF"
    if ! grep -q "LimitRequestLine" "$APACHE_CONF"; then
        echo "LimitRequestLine 8190" >> "$APACHE_CONF"
    fi
fi

# 10.2 Ensure the LimitRequestFields Directive is Set to 100 or Less but not 0 (Automated)
print_status "10.2 Ensure the LimitRequestFields Directive is Set to 100 or Less but not 0"
if grep -q "LimitRequestFields 100" "$APACHE_CONF"; then
    print_status "LimitRequestFields is already set to 100"
else
    print_status "Setting LimitRequestFields to 100"
    sed -i 's/LimitRequestFields.*/LimitRequestFields 100/' "$APACHE_CONF"
    if ! grep -q "LimitRequestFields" "$APACHE_CONF"; then
        echo "LimitRequestFields 100" >> "$APACHE_CONF"
    fi
fi

# 10.3 Ensure the LimitRequestFieldsize Directive is Set to 8190 or Less (Automated)
print_status "10.3 Ensure the LimitRequestFieldsize Directive is Set to 8190 or Less"
if grep -q "LimitRequestFieldSize 8190" "$APACHE_CONF"; then
    print_status "LimitRequestFieldSize is already set to 8190"
else
    print_status "Setting LimitRequestFieldSize to 8190"
    sed -i 's/LimitRequestFieldSize.*/LimitRequestFieldSize 8190/' "$APACHE_CONF"
    if ! grep -q "LimitRequestFieldSize" "$APACHE_CONF"; then
        echo "LimitRequestFieldSize 8190" >> "$APACHE_CONF"
    fi
fi

# 10.4 Ensure the LimitRequestBody Directive is Set to 102400 or Less but not 0 (Automated)
print_status "10.4 Ensure the LimitRequestBody Directive is Set to 102400 or Less but not 0"
if grep -q "LimitRequestBody 102400" "$APACHE_CONF"; then
    print_status "LimitRequestBody is already set to 102400"
else
    print_status "Setting LimitRequestBody to 102400"
    sed -i 's/LimitRequestBody.*/LimitRequestBody 102400/' "$APACHE_CONF"
    if ! grep -q "LimitRequestBody" "$APACHE_CONF"; then
        echo "LimitRequestBody 102400" >> "$APACHE_CONF"
    fi
fi

# 11. Enable SELinux to Restrict Apache Processes
print_status "Section 11: Enable SELinux to Restrict Apache Processes"

# 11.1 Ensure SELinux Is Enabled in Enforcing Mode (Automated)
print_status "11.1 Ensure SELinux Is Enabled in Enforcing Mode"
if command -v getenforce &> /dev/null; then
    if [ "$(getenforce)" = "Enforcing" ]; then
        print_status "SELinux is already enabled in enforcing mode"
    else
        print_warning "SELinux is not enabled in enforcing mode"
        print_warning "Manual step: Enable SELinux in enforcing mode"
    fi
else
    print_status "SELinux is not installed on this system"
fi

# 11.2 Ensure Apache Processes Run in the httpd_t Confined Context (Manual)
print_status "11.2 Ensure Apache Processes Run in the httpd_t Confined Context"
if command -v ps &> /dev/null && command -v grep &> /dev/null; then
    if ps -eZ | grep httpd_t; then
        print_status "Apache processes are already running in the httpd_t confined context"
    else
        print_warning "Apache processes are not running in the httpd_t confined context"
        print_warning "Manual step: Ensure Apache processes run in the httpd_t confined context"
    fi
else
    print_status "Cannot check Apache process context"
fi

# 11.3 Ensure the httpd_t Type is Not in Permissive Mode (Automated)
print_status "11.3 Ensure the httpd_t Type is Not in Permissive Mode"
if command -v sestatus &> /dev/null; then
    if sestatus | grep "httpd_t" | grep -q "permissive"; then
        print_warning "httpd_t type is in permissive mode"
        print_warning "Manual step: Ensure the httpd_t type is not in permissive mode"
    else
        print_status "httpd_t type is not in permissive mode"
    fi
else
    print_status "Cannot check httpd_t type mode"
fi

# 11.4 Ensure Only the Necessary SELinux Booleans are Enabled (Manual)
print_status "11.4 Ensure Only the Necessary SELinux Booleans are Enabled"
if command -v getsebool &> /dev/null; then
    print_status "Current SELinux booleans for Apache:"
    getsebool -a | grep httpd
    print_warning "Manual step: Review and disable unnecessary SELinux booleans for Apache"
else
    print_status "Cannot check SELinux booleans"
fi

# 12. Enable AppArmor to Restrict Apache Processes
print_status "Section 12: Enable AppArmor to Restrict Apache Processes"

# 12.1 Ensure the AppArmor Framework Is Enabled (Automated)
print_status "12.1 Ensure the AppArmor Framework Is Enabled"
if command -v aa-status &> /dev/null; then
    if aa-status | grep -q "apparmor"; then
        print_status "AppArmor framework is already enabled"
    else
        print_warning "AppArmor framework is not enabled"
        print_warning "Manual step: Enable AppArmor framework"
    fi
else
    print_status "AppArmor is not installed on this system"
fi

# 12.2 Ensure the Apache AppArmor Profile Is Configured Properly (Manual)
print_status "12.2 Ensure the Apache AppArmor Profile Is Configured Properly"
if [ -f "/etc/apparmor.d/usr.sbin.apache2" ]; then
    print_status "Apache AppArmor profile is already configured"
else
    print_warning "Apache AppArmor profile is not configured"
    print_warning "Manual step: Configure Apache AppArmor profile"
fi

# 12.3 Ensure Apache AppArmor Profile is in Enforce Mode (Automated)
print_status "12.3 Ensure Apache AppArmor Profile is in Enforce Mode"
if command -v aa-status &> /dev/null; then
    if aa-status | grep "usr.sbin.apache2" | grep -q "enforce"; then
        print_status "Apache AppArmor profile is already in enforce mode"
    else
        print_warning "Apache AppArmor profile is not in enforce mode"
        print_warning "Manual step: Put Apache AppArmor profile in enforce mode"
    fi
else
    print_status "Cannot check Apache AppArmor profile mode"
fi

# Allow Apache through UFW
print_status "Allowing Apache through UFW"
if command -v ufw &> /dev/null; then
    ufw allow 'Apache Full'
    print_status "Apache allowed through UFW"
else
    print_status "UFW is not installed or not in use"
fi

# Restart Apache service
print_status "Restarting Apache service"
systemctl restart apache2
if systemctl is-active --quiet apache2; then
    print_status "Apache service is running"
else
    print_error "Apache service failed to start"
    print_error "Check the error logs: $LOG_DIR/error.log"
fi

print_status "CIS Apache HTTP Server 2.4 Benchmark configuration completed"
print_status "Backup of original configuration files is available at: $BACKUP_DIR"
print_status "Please review the manual steps and configurations to ensure they meet your specific requirements"