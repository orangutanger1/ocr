#!/bin/bash

# Set permissions for /etc/passwd, /etc/group, /etc/shadow, .bash_history
echo "Securing file permissions..."

# Function to safely set permissions
safe_chmod() {
    if [ -e "$1" ]; then
        chmod "$2" "$1"
    else
        echo "Warning: $1 does not exist, skipping."
    fi
}

# Function to safely set ownership
safe_chown() {
    if [ -e "$1" ]; then
        chown "$2" "$1"
    else
        echo "Warning: $1 does not exist, skipping."
    fi
}

# Ensure directories exist before changing permissions
mkdir -p /etc/resolvconf/resolv.conf.d/
mkdir -p /etc/apt/apt.conf.d/
mkdir -p /etc/ufw/
mkdir -p /etc/sysctl.d/
mkdir -p /etc/ssh/
mkdir -p /etc/sudoers.d/
mkdir -p /etc/lightdm/
mkdir -p /etc/gdm3/
mkdir -p /var/log/
mkdir -p /var/spool/cron/crontabs/
mkdir -p /root/.ssh/
mkdir -p /root/.gnupg/private-keys-v1.d/

# Set permissions for files and directories
safe_chmod /etc/resolvconf/resolv.conf.d/ 755
safe_chmod /etc/resolvconf/resolv.conf.d/base 644
safe_chmod /etc/resolv.conf 644
safe_chmod /etc/hosts 644
safe_chmod /etc/host.conf 644
safe_chmod /etc/hosts.deny 644
safe_chmod /etc/apt/ 755
safe_chmod /etc/apt/apt.conf.d/ 755
safe_chmod /etc/apt/apt.conf.d/10periodic 644
safe_chmod /etc/apt/apt.conf.d/20auto-upgrades 644
safe_chmod /etc/apt/sources.list 664
safe_chmod /etc/default/ufw 644
safe_chmod /etc/ufw/ 755
safe_chmod /var/log/ufw.log 640
safe_chmod /var/log/*.log 640
safe_chmod /etc/ufw/sysctl.conf 644
safe_chmod /etc/sysctl.d/ 755
safe_chmod /etc/sysctl.conf 644
safe_chmod /etc/passwd 644
safe_chmod /etc/shadow 600
safe_chmod /etc/group 644
safe_chmod /etc/gshadow 640
safe_chmod /etc/sudoers.d/ 755
safe_chmod /etc/sudoers.d/* 440
safe_chmod /etc/deluser.conf 644
safe_chmod /etc/adduser.conf 644
safe_chmod /etc/login.defs 644
safe_chmod /etc/pam.d/common-auth 644
safe_chmod /etc/pam.d/common-password 644
safe_chmod /etc/ssh/sshd_config 600
safe_chmod ~/.ssh 700
safe_chmod ~/.ssh/authorized_keys 600
safe_chmod ~/.gnupg 700
safe_chmod ~/.gnupg/pubring.kbx 644
safe_chmod ~/.gnupg/private-keys-v1.d/* 600

safe_chmod /etc/rc.local 755
safe_chmod /etc/grub.d/ 600
safe_chmod /etc/securetty 600
safe_chmod /etc/security/limits.conf 644
safe_chmod /etc/fstab 664
safe_chmod /etc/updatedb.conf 644
safe_chmod /etc/modprobe.d/blacklist.conf 644
safe_chmod /etc/environment 644
safe_chmod /etc 755
safe_chmod /bin 755
safe_chmod /boot 755
safe_chmod /cdrom 755
safe_chmod /dev 755
safe_chmod /home 755
safe_chmod /lib 755
safe_chmod /media 755
safe_chmod /mnt 755
safe_chmod /opt 755
safe_chmod /proc/ 555
safe_chmod /root 700
safe_chmod /run 755
safe_chmod /sbin 755
safe_chmod /snap 755
safe_chmod /srv 755
safe_chmod /sys 555
safe_chmod /tmp 1755
safe_chmod /usr 755
safe_chmod /var/ 755
safe_chmod /var/www/html 755
safe_chmod /var/spool/cron/crontabs/* 600
safe_chmod /etc/cron.allow 600
safe_chmod /etc/cron.deny 600
safe_chmod /etc/at.allow 600
safe_chmod /etc/at.deny 600

# Set ownership for files and directories
safe_chown /etc/resolvconf/resolv.conf.d/ root:root
safe_chown /etc/resolvconf/resolv.conf.d/base root:root
safe_chown /etc/resolv.conf root:root
safe_chown /etc/hosts root:root
safe_chown /etc/host.conf root:root
safe_chown /etc/hosts.deny root:root
safe_chown /etc/apt/ root:root
safe_chown /etc/apt/apt.conf.d/ root:root
safe_chown /etc/apt/apt.conf.d/10periodic root:root
safe_chown /etc/apt/apt.conf.d/20auto-upgrades root:root
safe_chown /etc/apt/sources.list root:root
safe_chown /etc/default/ufw root:root
safe_chown /etc/ufw/ root:root
safe_chown /etc/ufw/sysctl.conf root:root
safe_chown /var/log/ufw.log root:root
safe_chown /var/log/*.log root:root
safe_chown /etc/sysctl.d/ root:root
safe_chown /etc/sysctl.conf root:root
safe_chown /etc/passwd root:root
safe_chown /etc/shadow root:shadow
safe_chown /etc/group root:root
safe_chown /etc/gshadow root:shadow
safe_chown /etc/ssh/sshd_config root:root
safe_chown /etc/sudoers.d/ root:root
safe_chown /etc/sudoers.d/* root:root
safe_chown /etc/sudoers root:root
safe_chown /etc/deluser.conf root:root
safe_chown /etc/adduser.conf root:root
safe_chown /etc/lightdm/lightdm.conf root:root
safe_chown /etc/login.defs root:root
safe_chown /etc/pam.d/common-auth root:root
safe_chown /etc/pam.d/common-password root:root
safe_chown /etc/rc.local root:root
safe_chown /etc/grub.d/ root:root
safe_chown /etc/securetty root:root
safe_chown /etc/security/limits.conf root:root
safe_chown /etc/fstab root:root
safe_chown /etc/updatedb.conf root:root
safe_chown /etc/modprobe.d/blacklist.conf root:root
safe_chown /etc/environment root:root
safe_chown /etc root:root
safe_chown /bin root:root
safe_chown /boot root:root
safe_chown /cdrom root:root
safe_chown /dev root:root
safe_chown /home root:root
safe_chown /lib root:root
safe_chown /media root:root
safe_chown /mnt root:root
safe_chown /opt root:root
safe_chown /proc/ root:root
safe_chown /root root:root
safe_chown /run root:root
safe_chown /sbin root:root
safe_chown /snap root:root
safe_chown /srv root:root
safe_chown /sys root:root
safe_chown /tmp root:root
safe_chown /usr root:root
safe_chown /var/ root:root

# Additional files and directories to secure
safe_chmod /etc/gshadow 600
safe_chmod /etc/lightdm/lightdm.conf 644
safe_chmod /etc/gdm3/custom.conf 644
safe_chmod /etc/hostname 644
safe_chmod /etc/ssh/ssh_host_*_key 600
safe_chmod /etc/ssh/ssh_host_*_key.pub 644
safe_chmod ~/.ssh/id_rsa 600
safe_chmod ~/.ssh/id_rsa.pub 644

# Secure sudoers file if it exists
if [ -f /etc/sudoers ]; then
    chmod 440 /etc/sudoers
fi

echo "File permissions secured."
