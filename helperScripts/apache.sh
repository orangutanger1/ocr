#!/bin/bash

# Apache Install and Hardened Configuration Script
# This script installs the latest version of Apache, ensures it's running, and applies secure and hardened settings.

# Install Apache (if not already installed)
echo "Installing or updating Apache..."
apt-get update
apt-get install -y apache2
if [ $? -ne 0 ]; then
  echo "Failed to install Apache. Please check your package manager."
  exit 1
fi

# Ensure Apache is running
echo "Starting Apache service..."
systemctl start apache2
systemctl enable apache2

# Backup the original Apache configuration file
echo "Backing up the original Apache configuration..."
cp /etc/apache2/apache2.conf /etc/apache2/apache2.conf.bak

# Apply secure and hardened Apache configuration
echo "Applying secure and hardened Apache configuration..."
cat <<EOF > /etc/apache2/apache2.conf
# Secure and Hardened Apache Configuration

# ServerRoot: The top of the directory tree under which the server's configuration, error, and log files are kept.
ServerRoot "/etc/apache2"

# Timeout: The number of seconds before receives and sends time out.
Timeout 60

# KeepAlive: Allow persistent connections (more than one request per connection).
KeepAlive On

# MaxKeepAliveRequests: The maximum number of requests allowed per connection.
MaxKeepAliveRequests 100

# KeepAliveTimeout: Number of seconds to wait for the next request from the same client.
KeepAliveTimeout 5

# User/Group: The name of the user/group to run httpd as.
User www-data
Group www-data

# ServerAdmin: Your address, where problems with the server should be e-mailed.
ServerAdmin admin@example.com

# ServerName: Hostname and port that the server uses to identify itself.
ServerName localhost

# DocumentRoot: The directory out of which you will serve your documents.
DocumentRoot /var/www/html

# Directory settings for DocumentRoot
<Directory /var/www/html>
    Options -Indexes -FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

# Logging
ErrorLog \${APACHE_LOG_DIR}/error.log
LogLevel warn
CustomLog \${APACHE_LOG_DIR}/access.log combined

# Disable server signature and tokens
ServerSignature Off
ServerTokens Prod

# Disable ETag (reduce fingerprinting)
FileETag None

# Disable TRACE and TRACK methods (prevent XST attacks)
TraceEnable Off

# Limit request size to prevent buffer overflow attacks
LimitRequestBody 10485760

# Secure SSL/TLS configuration (if SSL is enabled)
<IfModule mod_ssl.c>
    SSLProtocol all -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite HIGH:!aNULL:!MD5:!RC4
    SSLHonorCipherOrder on
    SSLCompression off
    SSLSessionTickets off
</IfModule>

# Disable unnecessary modules
<IfModule mod_autoindex.c>
    IndexOptions IgnoreCase FancyIndexing FoldersFirst
</IfModule>

# Disable directory listing
Options -Indexes

# Prevent clickjacking attacks
Header always append X-Frame-Options SAMEORIGIN

# Enable XSS protection
Header set X-XSS-Protection "1; mode=block"

# Prevent MIME type sniffing
Header set X-Content-Type-Options "nosniff"

# Enable HSTS (Strict-Transport-Security)
Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"

# Disable CGI execution (if not needed)
<Directory "/var/www/html">
    Options -ExecCGI
    RemoveHandler .cgi .pl .py .pyc .pyo
</Directory>

# Disable .htaccess overrides (if not needed)
<Directory "/var/www/html">
    AllowOverride None
</Directory>

# Disable server-side includes (SSI)
<Directory "/var/www/html">
    Options -Includes
</Directory>

# Disable PHP execution in uploads directory (if PHP is installed)
<Directory "/var/www/html/uploads">
    php_flag engine off
</Directory>
EOF

# Enable necessary Apache modules
echo "Enabling necessary Apache modules..."
a2enmod headers
a2enmod ssl
a2enmod rewrite

# Disable unnecessary Apache modules
echo "Disabling unnecessary Apache modules..."
a2dismod autoindex
a2dismod status
a2dismod userdir

# Restart Apache to apply changes
echo "Restarting Apache service..."
systemctl restart apache2

# Allow Apache through UFW (if UFW is enabled)
echo "Allowing Apache through UFW..."
ufw allow 'Apache Full'

echo "Apache has been installed and secured successfully!"
