#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/password_utils.sh"
AUTHORIZED_USERS_FILE="$SCRIPT_DIR/authorizedusers.txt"
AUTHORIZED_SUDO_USERS_FILE="$SCRIPT_DIR/authorizedsudousers.txt"

set -e

apt-get update
apt-get install -y samba samba-common-bin acl attr libpam-winbind libnss-winbind krb5-config winbind

SMB_CONF="/etc/samba/smb.conf"
BACKUP_FILE="/etc/samba/smb.conf.bak.$(date +%F_%T)"

if [ -f "$SMB_CONF" ]; then
    cp "$SMB_CONF" "$BACKUP_FILE"
fi

mkdir -p /samba/public /samba/private /samba/admin
chmod 0755 /samba
chmod 0770 /samba/private /samba/admin
chmod 0775 /samba/public

cat > "$SMB_CONF" <<EOL
[global]
workgroup = WORKGROUP
netbios name = SECURESAMBA
server string = Secure Samba Server
server role = standalone server

disable netbios = yes
smb ports = 445
dns proxy = no
hosts allow = 127.0.0.1 192.168.1.0/24
hosts deny = 0.0.0.0/0
interfaces = lo eth0
bind interfaces only = yes

security = user
passdb backend = tdbsam
map to guest = never
guest ok = no
guest account = nobody
restrict anonymous = 2

min protocol = SMB3_11
server min protocol = SMB3_11
client min protocol = SMB3_11
server signing = mandatory
client signing = mandatory
smb encrypt = mandatory
ntlm auth = no

obey pam restrictions = yes
pam password change = yes
unix password sync = yes

load printers = no
printing = bsd
printcap name = /dev/null
vfs objects = full_audit

log level = 1
log file = /var/log/samba/log.%m
max log size = 50

use sendfile = yes
aio read size = 1
aio write size = 1

[public]
    path = /samba/public
    browseable = yes
    read only = yes
    writeable = no
    guest ok = no
    create mask = 0775
    directory mask = 0775
    valid users = @smbgroup
    force group = smbgroup
    vfs objects = full_audit

[private]
    path = /samba/private
    browseable = no
    read only = no
    guest ok = no
    create mask = 0770
    directory mask = 0770
    valid users = @smbadmin
    force group = smbadmin
    vfs objects = full_audit

[admin]
    path = /samba/admin
    browseable = no
    read only = no
    guest ok = no
    create mask = 0770
    directory mask = 0770
    valid users = @smbadmin
    force group = smbadmin
    vfs objects = full_audit
EOL

echo "local5.*  /var/log/samba/audit.log" > /etc/rsyslog.d/samba.conf
systemctl restart rsyslog
mkdir -p /var/log/samba
chmod 700 /var/log/samba

groupadd -f smbgroup
groupadd -f smbadmin

chown root:smbgroup /samba/public
chown root:smbadmin /samba/private
chown root:smbadmin /samba/admin

if [ -f "$AUTHORIZED_USERS_FILE" ]; then
    while IFS= read -r user || [ -n "$user" ]; do
        [ -z "$user" ] && continue
        if ! id "$user" >/dev/null 2>&1; then
            useradd -m -s /sbin/nologin "$user"
        fi
        user_password="$(generate_service_password)"
        printf "%s\n%s\n" "$user_password" "$user_password" | smbpasswd -a "$user"
        smbpasswd -e "$user"
        usermod -aG smbgroup "$user"
        store_service_password "samba:${user}" "$user_password"
    done < "$AUTHORIZED_USERS_FILE"
else
    echo "No authorized users file found for Samba at $AUTHORIZED_USERS_FILE"
fi

if [ -f "$AUTHORIZED_SUDO_USERS_FILE" ]; then
    while IFS= read -r admin || [ -n "$admin" ]; do
        [ -z "$admin" ] && continue
        if ! id "$admin" >/dev/null 2>&1; then
            useradd -m -s /sbin/nologin "$admin"
        fi
        admin_password="$(generate_service_password)"
        printf "%s\n%s\n" "$admin_password" "$admin_password" | smbpasswd -a "$admin"
        smbpasswd -e "$admin"
        usermod -aG smbadmin "$admin"
        store_service_password "samba:${admin}" "$admin_password"
    done < "$AUTHORIZED_SUDO_USERS_FILE"
else
    echo "No authorized sudo users file found for Samba at $AUTHORIZED_SUDO_USERS_FILE"
fi

if command -v semanage >/dev/null 2>&1; then
    semanage fcontext -a -t samba_share_t "/samba(/.*)?"
    restorecon -R /samba
fi

if command -v ufw >/dev/null 2>&1; then
    ufw allow from 192.168.1.0/24 to any port 445 proto tcp
elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --zone=internal --add-service=samba
    firewall-cmd --reload
fi

systemctl restart smbd
systemctl enable smbd

testparm -s
systemctl enable smbd
systemctl restart smbd
systemctl status smbd
