#!/bin/bash

# Script to install PHP, Apache, replace php.ini, and configure UFW

# Update and install PHP and Apache
echo "Updating package list and installing PHP and Apache..."
sudo apt update
sudo apt install -y php apache2 libapache2-mod-php

# Download the new php.ini file
echo "Downloading the new php.ini file..."
sudo wget -O /etc/php/$(php -v | head -n 1 | cut -d " " -f 2 | cut -d "." -f 1-2)/apache2/php.ini https://raw.githubusercontent.com/danvau7/very-secure-php-ini/refs/heads/master/7.1.0%2B/php.ini

# Remove deprecated lines from php.ini
echo "Removing deprecated lines from php.ini..."
DEPRECATED_LINES=(
    "allow_url_include"
    "assert.quiet_eval"
    "filter.default"
    "mbstring.http_input"
    "mbstring.http_output"
    "mbstring.internal_encoding"
    "mbstring.func_overload"
    "mysqlnd.fetch_data_copy"
    "oci8.old_oci_close_semantics"
    "opcache.fast_shutdown"
    "opcache.inherited_hack"
    "pdo_odbc.db2_instance_name"
    "sql.safe_mode"
    "track_errors"
)

for line in "${DEPRECATED_LINES[@]}"; do
    sudo sed -i "/^$line/d" /etc/php/$(php -v | head -n 1 | cut -d " " -f 2 | cut -d "." -f 1-2)/apache2/php.ini
done

# Restart Apache to apply the new PHP configuration
echo "Restarting Apache to apply the new PHP configuration..."
sudo systemctl restart apache2

# Allow Apache through UFW
echo "Allowing Apache through UFW..."
sudo ufw allow 'Apache Full'

# Verify the new PHP configuration
echo "Verifying the new PHP configuration..."
php -v
php -i | grep "Loaded Configuration File"

echo "PHP configuration replacement and setup complete!"
