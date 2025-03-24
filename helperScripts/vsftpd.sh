#!/bin/bash

# Install vsftpd
apt install vsftpd -y

# Start and enable vsftpd service
systemctl start vsftpd
systemctl enable vsftpd

# Backup the default configuration file
echo "Backing up the default vsftpd.conf file..."
cp /etc/vsftpd.conf /etc/vsftpd.conf.bak

# Update vsftpd configuration
echo "Securing vsftpd configuration..."
vsftpd_conf="/etc/vsftpd.conf"

# Function to update or append a configuration line
update_or_append() {
    local key="$1"
    local value="$2"
    local file="$3"

    if grep -qE "^[#]*\s*$key=" "$file"; then
        sed -i "s|^[#]*\s*$key=.*|$key=$value|" "$file"
    else
        echo "$key=$value" >> "$file"
    fi
}

# MANUAL CONFIGURATIONS

# Disable anonymous access
update_or_append "anonymous_enable" "NO" "$vsftpd_conf"

# Enable local users
update_or_append "local_enable" "YES" "$vsftpd_conf"

# Disable write permissions for local users
update_or_append "write_enable" "NO" "$vsftpd_conf"

# Set local user umask
update_or_append "local_umask" "022" "$vsftpd_conf"

# Disable anonymous upload functionality
update_or_append "anon_upload_enable" "NO" "$vsftpd_conf"

# Comment out anon_root
update_or_append "anon_root" "/srv/ftp" "$vsftpd_conf"

# Disable chown uploads
update_or_append "chown_uploads" "NO" "$vsftpd_conf"

# Comment out chown_username
update_or_append "chown_username" "root" "$vsftpd_conf"

# Disable promiscuous port mode
update_or_append "port_promiscuous" "NO" "$vsftpd_conf"

# Set secure chroot directory
update_or_append "secure_chroot_dir" "/var/run/vsftpd/empty" "$vsftpd_conf"

# Enforce SSL encryption
update_or_append "ssl_enable" "YES" "$vsftpd_conf"

# Force SSL for data transfer
update_or_append "force_local_data_ssl" "YES" "$vsftpd_conf"

# Force SSL for local logins
update_or_append "force_local_logins_ssl" "YES" "$vsftpd_conf"

# Set SSL/TLS configuration
update_or_append "rsa_cert_file" "/etc/ssl/certs/vsftpd.pem" "$vsftpd_conf"
update_or_append "rsa_private_key_file" "/etc/ssl/private/vsftpd.key" "$vsftpd_conf"
update_or_append "ssl_ciphers" "HIGH:!ADH:!MD5:!RC4" "$vsftpd_conf"
update_or_append "ssl_tlsv1" "YES" "$vsftpd_conf"
update_or_append "ssl_sslv2" "NO" "$vsftpd_conf"
update_or_append "ssl_sslv3" "NO" "$vsftpd_conf"

# Restrict certain FTP commands
if ! grep -q "^cmds_allowed=" "$vsftpd_conf"; then
    echo "cmds_allowed=PASV, PORT, RETR, STOR, LIST, QUIT, DELE" >> "$vsftpd_conf"
fi

# Restart vsftpd service
echo "Restarting vsftpd service..."
systemctl reload vsftpd

# Configure firewall for passive ports
echo "Configuring firewall for FTP passive ports..."
ufw allow 40000:50000/tcp

# (Optional) Create ftpsecure user if needed
# sudo useradd -r -s /usr/sbin/nologin ftpsecure

echo "vsftpd secure configuration complete!"
