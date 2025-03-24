#!/bin/bash

# to add:
# gdm3 config
# more service configurations ( better vsftpd, better apache, mariadb, mysql, postgresql, etc)
# better hosts config

main(){
    checkPrivilege
    initializeScript
    setupFirewall
    configureApparmor
    criticalServices
    removeProhibitedSoftware
    configureSudousers
    removeUnauthorizedUsers
    setUserPasswords
    configureSysctl
    configurePam
    configure_audit
    configure_fstab
    filePriviledges
    locateProhibitedFiles
    updateSystem
}
# Checks for root priviledges
checkPrivilege() {
    if [[ $EUID -ne 0 ]]; then
      echo "This script must be run as root."
      exit 1
    fi
}

# Generates password for all Users
generatePassword() {
    local password=$(tr -dc 'A-Za-z0-9!@#$%^&*()_+=' </dev/urandom | head -c 16)
    echo "$password"
}

# Function to initialize the script and perform setup checks
initializeScript() {
    echo "Initializing script..."
    sudo chmod +x /usr/bin/*
    sudo chmod +r /usr/bin/*
    
    #[[ -f /etc/rc.local ]] && cat /etc/rc.local || { echo "Error: /etc/rc.local not found."; exit 1; }
    #[[ -f /tmp/rc_local_copy ]] && read -p "Replace existing copy? (y/n): " response && [[ "$response" != "y" ]] && exit 0
    
    #cp /etc/rc.local /tmp/rc_local_copy && echo "Copy created at /tmp/rc_local_copy."
    sudo apt install apparmor-profiles apparmor-utils auditd libpam-pwquality libpam-modules fail2ban wget -y
    systemctl enable apparmor
    systemctl start apparmor
    echo "System initialized."
}

# Function to set up a firewall for critical services
setupFirewall() {
    echo "Setting up firewall..."
    if ! command -v ufw &> /dev/null; then
        echo "ufw not found, installing ufw..."
        sudo apt-get install ufw -y
    fi
    sudo ufw reset
    sudo ufw enable
    sudo ufw logging full
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    for service in "${critical_services[@]}"; do
        sudo ufw allow "$service"
    done
    sudo ufw reload
}

# Critical Services Configurations
criticalServices() {
    echo "Configuring critical services..."
    for service in "${critical_services[@]}"; do
        if [[ "$service" == "ssh" ]]; then
            bash helperScripts/ssh.sh
        elif [[ "$service" == "samba" ]]; then
            bash helperScripts/samba.sh
        elif [[ "$service" == "vsftpd" ]]; then
            bash helperScripts/vsftpd.sh
        elif [[ "$service" == "apache" ]]; then
            bash helperScripts/apache.sh
        elif [[ "$service" == "mysql-server" ]]; then
            bash helperScripts/mysql.sh
        elif [[ "$service" == "mariadb-server" ]]; then
            bash helperScripts/mariaDB.sh
        elif [[ "$service" == "postgresql" ]]; then
            bash helperScripts/postgresql.sh
        else
            echo "No specific configuration set for $service."
        fi
    done
}


# Function to configure sysctl. Based on klaver and other sources
configureSysctl() {
    echo "Configuring sysctl for system and network tuning..."
    # Backup the current sysctl.conf
    cp /etc/sysctl.conf /etc/sysctl.conf.bak
    wget -qO- https://raw.githubusercontent.com/klaver/sysctl/refs/heads/master/sysctl.conf > /etc/sysctl.conf
    cat helperScripts/additionalsysctlconfigs.txt >> /etc/sysctl.conf
    sysctl -p /etc/sysctl.conf
}



# Function to configure PAM password settings
configurePam() {
    echo "Configuring PAM for password complexity and account lock..."

    # /etc/pam.d/common-auth: Configure account lockout policy
    if ! grep -q "pam_faillock.so" /etc/pam.d/common-auth; then
        echo "Adding faillock configuration to common-auth..."
        echo -e "auth\trequisite\tpam_faillock.so preauth silent audit deny=5 unlock_time=900 even_deny_root root_unlock_time=900 authfail" | sudo tee -a /etc/pam.d/common-auth
    fi

    # /etc/pam.d/common-password: Configure password complexity
    if grep -q "pam_pwquality.so" /etc/pam.d/common-password; then
        echo "Updating existing pam_pwquality.so configuration..."
        sudo sed -i \
            '/pam_pwquality.so/ s/$/ retry=3 minlen=14 difok=3 dcredit=-1 ucredit=-1 lcredit=-1 ocredit=-1 minclass=3 maxrepeat=2 maxsequence=3 maxclassrepeat=4 dictcheck enforcing usercheck enforce_for_root/' \
            /etc/pam.d/common-password
    else
        echo "Adding pam_pwquality.so configuration to common-password..."
        echo -e "password\trequisite\tpam_pwquality.so retry=3 minlen=14 difok=3 dcredit=-1 ucredit=-1 lcredit=-1 ocredit=-1 minclass=3 maxrepeat=2 maxsequence=3 maxclassrepeat=4 dictcheck enforcing usercheck enforce_for_root" | sudo tee -a /etc/pam.d/common-password
    fi

    # /etc/pam.d/common-password: Configure password storage and history
    if grep -q "pam_unix.so" /etc/pam.d/common-password; then
        echo "Updating existing pam_unix.so configuration..."
        sudo sed -i \
            '/pam_unix.so/ s/$/ obscure use_authtok sha512 rounds=800000 shadow remember=7/' \
            /etc/pam.d/common-password
    else
        echo "Adding pam_unix.so configuration to common-password..."
        echo -e "password\tsufficient\tpam_unix.so obscure use_authtok sha512 rounds=800000 shadow remember=7" | sudo tee -a /etc/pam.d/common-password
    fi

    # /etc/login.defs: Configure global password policies
    echo "Updating /etc/login.defs for password policies..."
    sudo sed -i \
        -e 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS\t14/' \
        -e 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS\t7/' \
        -e 's/^PASS_WARN_AGE.*/PASS_WARN_AGE\t7/' \
        -e 's/^ENCRYPT_METHOD.*/ENCRYPT_METHOD\tSHA512/' \
        -e 's/^FAILLOG_ENAB.*/FAILLOG_ENAB\tyes/' \
        -e 's/^PASS_MAX_TRIES.*/PASS_MAX_TRIES\t3/' \
        -e 's/^PASS_MIN_LEN.*/PASS_MIN_LEN\t12/' \
        /etc/login.defs

    echo "PAM configuration completed successfully."
}

#######################################################
#######################################################
configure_audit() {
    local TEMP_DIR="/tmp/auditd_config"
    local AUDIT_DIR="/etc/audit"
    local SERVICE_FILE="/usr/lib/systemd/system/auditd.service"
    
    # Download and extract new config
    mkdir -p $TEMP_DIR
    wget -qO "$TEMP_DIR/config.zip" "https://github.com/steveandreassend/linux_auditd/archive/refs/heads/main.zip"
    unzip -q "$TEMP_DIR/config.zip" -d $TEMP_DIR
    
    # Backup and replace audit directory
    cp -a $AUDIT_DIR "${AUDIT_DIR}_bak_$(date +%Y%m%d%H%M%S)"
    mv "$AUDIT_DIR/plugins.d" "$TEMP_DIR/plugins.d_backup"
    rm -rf $AUDIT_DIR
    cp -a "$TEMP_DIR/linux_auditd-main/RHEL/etc/audit" $AUDIT_DIR
    mv "$TEMP_DIR/plugins.d_backup" "$AUDIT_DIR/plugins.d"
    chmod -R 600 $AUDIT_DIR && chmod 700 $AUDIT_DIR
    
    # Configure service file
    sed -i -E '
        /^[[:space:]]*ExecStartPost=-\/sbin\/augenrules --load/d
        /^[[:space:]]*ExecStartPost=-\/sbin\/auditctl -R \/etc\/audit\/audit.rules/d
        /^\[Service\]/a\ExecStartPost=-/sbin/augenrules --load\nExecStartPost=-/sbin/auditctl -R /etc/audit/audit.rules
    ' $SERVICE_FILE
    ############################ - https://www.ncsc.gov.uk/
    echo -e "${HIGHLIGHT}Configuring system auditing...${NC}"
    if [ ! -f /etc/audit/rules.d/tmp-monitor.rules ]; then
    echo "# Monitor changes and executions within /tmp
    -w /tmp/ -p wa -k tmp_write
    -w /tmp/ -p x -k tmp_exec" > /etc/audit/rules.d/tmp-monitor.rules
    fi
    
    if [ ! -f /etc/audit/rules.d/admin-home-watch.rules ]; then
    echo "# Monitor administrator access to /home directories
    -a always,exit -F dir=/home/ -F uid=0 -C auid!=obj_uid -k admin_home_user" > /etc/audit/rules.d/admin-home-watch.rules
    fi    
    ############################
    # Reload configuration
    systemctl daemon-reload
    augenrules
    systemctl restart auditd
    
    # Cleanup
    rm -rf $TEMP_DIR
    
    systemctl is-active --quiet auditd && echo "Audit configuration updated successfully." || echo "Error: Failed to reload auditd."
}

configureApparmor() {
    # Set some AppArmor profiles to enforce mode.
    echo -e "${HIGHLIGHT}Configuring apparmor...${NC}"
    aa-enforce /etc/apparmor.d/usr.bin.firefox
    aa-enforce /etc/apparmor.d/usr.bin.chromium-browser
    aa-enforce /etc/apparmor.d/usr.bin.google-chrome
    aa-enforce /etc/apparmor.d/usr.sbin.avahi-daemon
    aa-enforce /etc/apparmor.d/usr.sbin.dnsmasq
    aa-enforce /etc/apparmor.d/bin.ping
    aa-enforce /etc/apparmor.d/usr.sbin.rsyslogd    
}

#!/bin/bash

# Function to configure /etc/fstab
configure_fstab() {
    # Backup /etc/fstab before making changes
    sudo cp /etc/fstab /etc/fstab.bak
    echo "Backup of /etc/fstab created at /etc/fstab.bak."

    # Modify /home entry in /etc/fstab (if it exists)
    if grep -q '\s/home\s' /etc/fstab; then
        echo "Modifying /home entry in /etc/fstab..."
        sudo sed -i -e '/\s\/home\s/ s/defaults/defaults,noexec,nosuid,nodev/' /etc/fstab
    else
        echo "No /home entry found in /etc/fstab, skipping modification."
    fi

    # Define the new entries to add
    declare -A entries=(
        ["/run/shm"]="none /run/shm tmpfs rw,noexec,nosuid,nodev 0 0"
        ["/tmp"]="none /tmp tmpfs rw,noexec,nosuid,nodev 0 0"
        ["/var/tmp"]="/tmp /var/tmp none bind 0 0"
    )

    # Loop through each entry
    for mount_point in "${!entries[@]}"; do
        # Check if the entry already exists in /etc/fstab
        if ! grep -q "^${entries[$mount_point]}" /etc/fstab; then
            echo "Adding entry for $mount_point to /etc/fstab..."
            echo "${entries[$mount_point]}" | sudo tee -a /etc/fstab > /dev/null
        else
            echo "Entry for $mount_point already exists in /etc/fstab, skipping."
        fi
    done

    echo "/etc/fstab configuration complete."
}

#######################################################
#######################################################

# Function to remove unauthorized users
removeUnauthorizedUsers() {
    echo "Checking and removing unauthorized users..."
    authorized_uids=($(awk -F':' '{ if ($3 >= 1000) print $1 }' /etc/passwd))
    for user in "${authorized_uids[@]}"; do
        if ! [[ "${valid_users[@]}" =~ "$user" ]]; then
            echo "Removing unauthorized user: $user"
            sudo userdel -r "$user"
        fi
    done
}

# Function to configure sudo access based on valid sudo users
configureSudousers() {
    echo "Configuring sudo users..."
    for user in "${valid_sudo_users[@]}"; do
        if ! groups "$user" | grep -q sudo; then
            echo "Adding $user to sudo group"
            sudo usermod -aG sudo "$user"
        fi
    done

    # Remove users who shouldn't have sudo
    current_sudousers=($(getent group sudo | awk -F: '{print $4}' | tr ',' ' '))
    for sudoer in "${current_sudousers[@]}"; do
        if ! [[ "${valid_sudo_users[@]}" =~ "$sudoer" ]]; then
            echo "Removing $sudoer from sudo group"
            sudo deluser "$sudoer" sudo
        fi
    done
}

# Function to update and upgrade the system
updateSystem() {
    echo "Updating and upgrading the system..."
    sudo apt-get update -y && sudo apt-get upgrade -y && sudo apt-get dist-upgrade -y
    read -p "Do you want to reboot the system to apply kernel updates? (y/n): " answer
    if [[ "$answer" == "y" ]]; then
        echo "Rebooting the system..."
        sudo reboot
    elif [[ "$answer" == "n" ]]; then
        echo "No reboot will be performed. Exiting script."
        exit 0
    else
        echo "Invalid input. Please answer with 'yes' or 'no'."
        exit 1
    fi    
    
}

# Function to remove prohibited software and services
removeProhibitedSoftware() {
    echo "Removing prohibited or unnecessary software..."
    prohibited_software=(john* john-data *nmap* nmap-common ndiff vuze frostwire aircrack-ng airgraph-ng fcrackzip lcrack kismet freeciv minetest minetest-server *medusa* hydra* hydra-gtk truecrack ophcrack ophcrack-cli pdfcrack sipcrack irpas zeitgeist-core zeitgeist-datahub python-zeitgeist rhythmbox-plugin-zeitgeist zeitgeist nikto cryptcat nc netcat tightvncserver x11vnc nfs xinetd telnet rlogind rshd rsh* rcmd rexecd rbootd rquotad rstatd rusersd rwalld rexd fingerd tftpd snmp python-samba samba* sftpd vsftpd apache* apache2* ftp ssh php pop3 icmp sendmail dovecot bind9 nginx netcat-traditional netcat-openbsd ncat pnetcat socat sock socket sbd tcpdump lighttpd zenmap wireshark crack crack-common cyphesis aisleriot wesnoth wordpress gameconqueror qbittorrent qbittorrent-nox utorrent utserver metasploit-framework *deluge* ettercap* hashcat hashcat-data autopsy sqlmap postfix wifite wifiphisher spiderfoot ffuf tcpdump reaver impacket-scripts dnsrecon phpggc p0f ncrack masscan bloodhound cewl johnny eyewitness driftnet evilginx2 yersinia theharvester armitage veil polenum bettercap dirsearch dirbuster legion cutycapt rsh-redone-client gobuster havoc rsh-client vncviewer enum4linux dmitry snort* snort-common snort-common-libraries snort-doc snort-rules-default fwsnort *nessus* *macchanger* pixiewps bbqsql proxychains* whatweb dirb traceroute *httrack* *openvas* 4g8 acccheck bittorrent* bittornado* bluemon btscanner buildtorrent brutespray dsniff hunt nast netsniff-ng python-scapy sipgrep sniffit tcpick tcpreplay tcpslice tcptraceroute tcpxtract mdk3 slowhttptest ssldump sslstrip thc-ipv6 bro* darkstat dnstop flowscan nfstrace* streams ntopng* ostinato softflowd tshark wfuzz minetest* squid mahjongg* cheese*)
    installed_software=($(dpkg -l | awk '{print $2}'))

    for software in "${installed_software[@]}"; do
        if [[ " ${prohibited_software[@]} " =~ " ${software} " ]] && ! [[ " ${valid_software[@]} " =~ " ${software} " ]]; then
            echo "Removing $software..."
            sudo apt-get remove --purge -y "$software"
        fi
    done
    sudo apt autoremove -y
    sudo apt autoclean -y
}

# Function to locate prohibited files in /home, including hidden files
locateProhibitedFiles() {
    echo "Locating prohibited files in /home directory..."
    # Search for specific file types, including hidden files
    prohibited_files=$(find / -type f \( \
        -name "*.mp3" -o -name "*.txt" -o -name "*.wav" -o -name "*.wma" -o \
        -name "*.aac" -o -name "*.mp4" -o -name "*.mov" -o -name "*.avi" -o \
        -name "*.gif" -o -name "*.jpg" -o -name "*.png" -o -name "*.bmp" -o \
        -name "*.img" -o -name "*.exe" -o -name "*.msi" -o -name "*.bat" -o \
        -name "*.sh" -o -name ".*.mp3" -o -name ".*.txt" -o -name ".*.wav" -o \
        -name ".*.wma" -o -name ".*.aac" -o -name ".*.mp4" -o -name ".*.mov" -o \
        -name ".*.avi" -o -name ".*.gif" -o -name ".*.jpg" -o -name ".*.png" -o \
        -name ".*.bmp" -o -name ".*.img" -o -name ".*.exe" -o -name ".*.msi" -o \
        -name ".*.bat" -o -name ".*.sh" -o -name ".*.so" -o -name "*.php" -o \
        -name ".*.php" -o -name "*.py" -o -name ".*.py" -o -name "*.so" -o \
        -name ".*.so" \) 2>/dev/null)
    
    echo "$prohibited_files" >> /var/prohibited.txt
    
    if [ -n "$prohibited_files" ]; then
        echo "Prohibited files found:"
        echo "$prohibited_files"
    else
        echo "No prohibited files found in / directory."
    fi
}

# Function to set passwords for authorized users
setUserPasswords() {
    echo "Setting passwords for authorized users..."
    for user in "${valid_users[@]}"; do
        local new_password=$(generatePassword)
        echo "Setting password for $user"
        echo "$user:$new_password" | sudo chpasswd
        echo "User: $user, New Password: $new_password" >> /var/passwords.txt
    done
}

# Checks for the correct file permissions of default files
filePriviledges(){
    df --local -P | awk {'if (NR!=1) print $6'} | xargs -I '{}' find '{}' -xdev -type d -perm -0002 2>/dev/null | xargs chmod a+t
    bash helperScripts/permissions.sh
}

# Read the contents of the files into arrays
critical_services=($(<helperScripts/criticalservices.txt))
valid_users=($(<helperScripts/authorizedusers.txt))
valid_sudo_users=($(<helperScripts/authorizedsudousers.txt))

# Define valid software (critical services)
valid_software=("${critical_services[@]}")

# Main script
main

echo "$password"

echo "All tasks completed."
echo "Passwords have been saved to /var/passwords.txt."
echo "Prohibited files saved to /var/prohibited.txt"
