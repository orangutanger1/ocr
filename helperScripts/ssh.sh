#!/bin/bash

echo "Configuring OpenSSH with enhanced security..."

# Install required packages
apt update
apt install -y ssh openssh-server

# Define configuration files
CONFIG_FILE="/etc/ssh/sshd_config"
BACKUP_FILE="/etc/ssh/sshd_config.bak.$(date +%F_%T)"
cp "$CONFIG_FILE" "$BACKUP_FILE"

# Update sshd_config with secure settings
cat > "$CONFIG_FILE" <<EOL
# Security-hardened SSH Configuration
Protocol 2
Port 22222                                    # Non-standard port
AddressFamily inet                            # IPv4 only
ListenAddress 0.0.0.0

# Authentication
PermitRootLogin no
MaxAuthTries 3
MaxSessions 2
MaxStartups 10:30:60
LoginGraceTime 20
PermitEmptyPasswords no
PasswordAuthentication yes
PubkeyAuthentication yes
AuthenticationMethods publickey
ChallengeResponseAuthentication no
UsePAM yes

# Disable unnecessary authentication methods
KerberosAuthentication no
GSSAPIAuthentication no
HostbasedAuthentication no
IgnoreRhosts yes

# Cryptography settings
Ciphers aes256-gcm@openssh.com,aes128-gcm@openssh.com
HostKeyAlgorithms rsa-sha2-512,rsa-sha2-256,ssh-ed25519
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
KexAlgorithms sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group18-sha512,diffie-hellman-group16-sha512
HostKey /etc/ssh/ssh_host_ed25519_key
#HostKey /etc/ssh/ssh_host_rsa_key

# Hardening
X11Forwarding no
PermitUserEnvironment no
AllowAgentForwarding no
AllowTcpForwarding no
AllowStreamLocalForwarding no
DisableForwarding yes
GatewayPorts no
PermitTunnel no
DebianBanner no
PrintMotd no
PrintLastLog yes
LogLevel VERBOSE
StrictModes yes
Compression no
TCPKeepAlive no
UseDNS no
ClientAliveInterval 300                       # 5 minutes
ClientAliveCountMax 3                         # Disconnect after 15 minutes of inactivity

# SFTP configuration
Subsystem sftp internal-sftp
EOL

# Set correct ownership and permissions for SSH
chown -R root:root /etc/ssh
chmod 700 /etc/ssh/
find /etc/ssh/ -type f -exec chmod 600 {} \;

# Generate new host keys with stronger algorithms
rm -f /etc/ssh/ssh_host_*
ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ""
ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""

# Configure Fail2Ban
cat > /etc/fail2ban/jail.local <<EOL
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
findtime = 300
bantime = 24h
EOL

# Start and enable fail2ban
systemctl enable fail2ban
systemctl restart fail2ban

# Configure UFW
ufw enable
ufw allow 22222/tcp comment "SSH on non-standard port"
ufw limit 22222/tcp

# Restart SSH service
systemctl enable ssh
systemctl restart ssh

echo "OpenSSH configuration is complete. SSH is now running on port 22222."
