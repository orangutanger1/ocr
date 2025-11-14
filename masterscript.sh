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
    auditBinaryIntegrity
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

    echo "Removing insecure 'nullok' directives from PAM configuration files..."
    mapfile -t pam_files_with_nullok < <(grep -rl "nullok" /etc/pam.d 2>/dev/null || true)
    if (( ${#pam_files_with_nullok[@]} > 0 )); then
        for pam_file in "${pam_files_with_nullok[@]}"; do
            sudo sed -i 's/[[:space:]]*\<nullok\>//g' "$pam_file"
            echo "Removed 'nullok' from $pam_file"
        done
    else
        echo "No 'nullok' directives found in PAM configs."
    fi

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
    local login_defs="/etc/login.defs"
    declare -A login_def_updates=(
        [PASS_MAX_DAYS]=30
        [PASS_MIN_DAYS]=14
        [PASS_WARN_AGE]=7
        [ENCRYPT_METHOD]=SHA512
        [FAILLOG_ENAB]=yes
        [PASS_MAX_TRIES]=3
        [PASS_MIN_LEN]=12
    )

    for key in "${!login_def_updates[@]}"; do
        if grep -q "^${key}" "$login_defs"; then
            sudo sed -i "s/^${key}.*/${key}\t${login_def_updates[$key]}/" "$login_defs"
        else
            echo -e "${key}\t${login_def_updates[$key]}" | sudo tee -a "$login_defs" >/dev/null
        fi
    done

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

    prohibited_software=(
        4g8 42 acccheck adore adfind adm advancedipscanner advancedrun aircrack aircrack-ng airgraph-ng aide aidra aisleriot alaeda amap angryipscanner anydesk apache* apache2 apache2* armitage arches atera asyncrat autohotkey autopsy autofs backproxy badbunny bettercap bind9 binom bittorrent* bittornado* bliss bluemon boldmove bro* brundle brutespray bbqsql bukowski buildtorrent caveat cewl ccleaner cephei cheese cheese* cloudsnooper cobaltstrike coin connectwise crack crack-common cryptcat cutycapt cyphesis darkstat deluge deluge-gtk dmitry dirb dirbuster dirsearch discord dnstop dnsrecon driftnet dsniff ettercap ettercap* ettermap energymech enum4linux evilgnome evilginx2 ezuri effusion fcrackzip ffuf fingerd flowscan freeciv frostwire fwsnort gafgyt gameconqueror gkrellm gobuster goldeneye gonnacry havoc hashcat hashcat-data hasher handofthief heuristics hotrat hping httrack* hummingbad hydra* hydra-gtk icedid icecast icecast2 icefire icmp impacket-scripts iodine iodine_client iobitdriverbooster iobitunlocker john* john-data johnny jq kaiten keygen kismet kinsing kork kryptina lacrimae lazagne lcrack legion lightaidra lighttpd lilocked linuxdarlloz linuxencoder linuxlupper linuxlion linuxmillen linuxremaiten logkeys luabot macchanger* mahjongg* mallox manaplus masscan mayhem mdk3 medusa* megasync memcached metasploit-framework mighty minetest minetest* minetest-server mimikatz mirai mozi nast nc ncat ncrack ndiff nessus* netcat netcat-openbsd netcat-traditional netpass netsniff-ng newaidra ngrep nginx nikto nmap* nmap-common nfs nfstrace* nyadr-op nuxbee obsstudio odin openvas* ophcrack ophcrack-cli ostinato p0f pdqdeploy perfctl php phpggc pilot pigmygoat pixiewps pnscan podloso polenum pnetcat postfix processhacker proxychains* psexec pyrit pyxie qbittorrent qbittorrent-nox ramjet ramen ramenx ramenexx ramenex ramenexx ransomexx rclone reaver redis-cli redis-server regasm relx rexecd rexob rike rlogind rlogin rsh* rsh-client rsh-redone-client rshd rbootd rcmd rquotad rstatd rusersd rwalld rexd revouninstaller robotfindskitten rst samba* sendmail sbd scapy sharkdp sipcrack sipgrep slapper slubstick slowhttptest slurm smbmap snakso snmp snort* snort-common snort-common-libraries snort-doc snort-rules-default softflowd socat sock socket speakup sftpd sniffit ssh ssldump sslstrip staog streams sucrack suphp syslogk tcpdump tcpick tcpreplay tcpslice tcptraceroute tcpxtract teamviewer telnet theharvester thc-ipv6 tightvnc tightvncserver tftpd traceroute tsunami turla tshark tycoon unicornscan unworkable useradd utorrent utserver varnishd vatetloader veil vermilionstrike vit vncviewer vuze waterfall wesnoth wifite wifiphisher wireshark winux winter witvirus wordpress x11vnc xinetd xorddos xz-utils yersinia zeek zeitgeist zeitgeist-core zeitgeist-datahub zenmap zmap zipworm
    )

    installed_software=($(dpkg -l | awk '{print $2}'))

    for software in "${installed_software[@]}"; do
        if [[ " ${prohibited_software[@]} " =~ " ${software} " ]] && \
           ! [[ " ${valid_software[@]} " =~ " ${software} " ]]; then
            echo "Removing $software..."
            sudo apt remove --purge -y "$software"
        fi
    done

    sudo apt autoremove -y
    sudo apt autoclean -y
}


# Function to locate prohibited files in /home, including hidden files
locateProhibitedFiles() {
    echo "Scanning for prohibited or suspicious files..."

    local log_file="/var/prohibited.txt"
    : > "$log_file"

    local -a search_roots=("/")
    local -a exclude_paths=("/proc/*" "/sys/*" "/dev/*" "/run/*" "/var/lib/*" "/var/log/*" "/snap/*")

    local -a media_ext=("*.mp3" "*.mp4" "*.m4a" "*.wav" "*.wma" "*.aac" "*.flac" "*.mov" "*.avi" "*.mkv")
    local -a archive_exec_ext=("*.exe" "*.msi" "*.img" "*.iso" "*.bat" "*.cmd" "*.vbs" "*.scr")
    local -a script_ext=("*.py" "*.pyc" "*.pyo" "*.php" "*.pl" "*.pm" "*.rb" "*.sh")
    local -a doc_ext=("*.txt" "*.rtf" "*.doc" "*.docx" "*.xls" "*.xlsx" "*.ppt" "*.pptx")

    local so_system_regex='^/(lib|lib64|usr/lib|usr/local/lib|var/lib|snap|boot|opt/(microsoft|google|vmware)|sbin|bin)'
    local total_matches=0

    scan_category() {
        local category="$1"
        shift
        local -a patterns=("$@")
        local -a matches=()

        [[ ${#patterns[@]} -eq 0 ]] && return

        for root in "${search_roots[@]}"; do
            [[ -d "$root" ]] || continue

            local -a pattern_expr=("(")
            for idx in "${!patterns[@]}"; do
                [[ $idx -gt 0 ]] && pattern_expr+=(-o)
                pattern_expr+=(-iname "${patterns[$idx]}")
            done
            pattern_expr+=(")")

            local -a find_args=("$root" -type f)
            find_args+=("${pattern_expr[@]}")
            for excl in "${exclude_paths[@]}"; do
                find_args+=(-not -path "$excl")
            done

            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                if [[ "$category" == "Shared libraries" && "$file" =~ $so_system_regex ]]; then
                    continue
                fi
                matches+=("$file")
            done < <(find "${find_args[@]}" -print 2>/dev/null)
        done

        if (( ${#matches[@]} > 0 )); then
            total_matches=$((total_matches + ${#matches[@]}))
            {
                echo "### $category"
                for found in "${matches[@]}"; do
                    printf 'File: %s (Name: %s)\n' "$found" "$(basename "$found")"
                done
                echo
            } | tee -a "$log_file" >/dev/null
        fi
    }

    scan_category "Media files (audio/video)" "${media_ext[@]}"
    scan_category "Executable installers and disk images" "${archive_exec_ext[@]}"
    scan_category "Scripts (Python/Perl/PHP/Shell)" "${script_ext[@]}"
    scan_category "Documents/potential data leaks" "${doc_ext[@]}"
    scan_category "Shared libraries" "*.so"

    if (( total_matches == 0 )); then
        echo "No prohibited files detected in monitored locations."
    else
        echo "Detailed report saved to $log_file"
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

auditBinaryIntegrity() {
    echo "Auditing for poisoned binaries and misconfigured SUID/SGID bits..."

    local integrity_log="/var/binary_integrity_report.txt"
    local suid_log="/var/suid_audit_report.txt"
    local perm_log="/var/permission_anomalies.txt"
    : > "$integrity_log"
    : > "$suid_log"
    : > "$perm_log"

    if ! command -v debsums &> /dev/null; then
        echo "Installing debsums for binary verification..."
        sudo apt-get update -y && sudo apt-get install -y debsums
    fi

    if command -v debsums &> /dev/null; then
        echo "Running debsums integrity check (listing mismatches only)..."
        debsums -s | tee -a "$integrity_log"
    else
        echo "debsums not available. Skipping checksum verification." | tee -a "$integrity_log"
    fi

    local -a critical_packages=("coreutils" "passwd" "sudo" "util-linux" "openssh-client" "openssh-server" "shadow" "login" "bash")
    echo "Verifying critical package files via dpkg -V..." | tee -a "$integrity_log"
    for pkg in "${critical_packages[@]}"; do
        if dpkg -s "$pkg" &> /dev/null; then
            dpkg -V "$pkg" >> "$integrity_log"
        else
            echo "Package $pkg not installed; skipping." >> "$integrity_log"
        fi
    done

    declare -A suid_whitelist=(
        ["/usr/bin/sudo"]=1
        ["/bin/su"]=1
        ["/usr/bin/passwd"]=1
        ["/usr/bin/chsh"]=1
        ["/usr/bin/chfn"]=1
        ["/usr/bin/gpasswd"]=1
        ["/usr/bin/newgrp"]=1
        ["/usr/bin/pkexec"]=1
    )

    echo "Collecting SUID binaries (sudo find / -perm -4000 -type f)..." | tee -a "$suid_log"
    mapfile -t suid_files < <(sudo find / -perm -4000 -type f 2>/dev/null || true)
    echo "Collecting SGID binaries (sudo find / -perm -2000 -type f)..." | tee -a "$suid_log"
    mapfile -t sgid_files < <(sudo find / -perm -2000 -type f 2>/dev/null || true)

    local unexpected_count=0
    local -a non_root_suid=()
    local -a non_root_sgid=()

    for file in "${suid_files[@]}"; do
        [[ -e "$file" ]] || continue
        local owner="$(stat -c %U "$file" 2>/dev/null || echo unknown)"
        if [[ -z "${suid_whitelist[$file]}" ]]; then
            unexpected_count=$((unexpected_count + 1))
            ls -l "$file" >> "$suid_log"
        fi
        if [[ "$owner" != "root" ]]; then
            non_root_suid+=("$file (owner: $owner)")
        fi
    done

    if [[ $unexpected_count -eq 0 ]]; then
        echo "No unexpected SUID binaries detected outside whitelist." | tee -a "$suid_log"
    else
        echo "$unexpected_count unexpected SUID binary(s) detected. Details saved to $suid_log" | tee -a "$suid_log"
    fi

    local -a sgid_records=()
    for file in "${sgid_files[@]}"; do
        [[ -e "$file" ]] || continue
        local owner="$(stat -c %U "$file" 2>/dev/null || echo unknown)"
        local group="$(stat -c %G "$file" 2>/dev/null || echo unknown)"
        sgid_records+=("$(ls -l "$file" 2>/dev/null)")
        if [[ "$owner" != "root" ]]; then
            non_root_sgid+=("$file (owner: $owner:$group)")
        fi
    done

    if (( ${#sgid_records[@]} > 0 )); then
        printf '%s\n' "${sgid_records[@]}" >> "$suid_log"
    else
        echo "No SGID binaries discovered." >> "$suid_log"
    fi

    {
        echo
        echo "### Non-root owned SUID binaries"
        if (( ${#non_root_suid[@]} > 0 )); then
            printf '%s\n' "${non_root_suid[@]}"
        else
            echo "None detected."
        fi
        echo
        echo "### Non-root owned SGID binaries"
        if (( ${#non_root_sgid[@]} > 0 )); then
            printf '%s\n' "${non_root_sgid[@]}"
        else
            echo "None detected."
        fi
    } >> "$suid_log"

    echo "Scanning for world-writable directories without sticky bit..." | tee -a "$perm_log"
    mapfile -t ww_dirs_no_sticky < <(sudo find / -xdev -type d -perm -0002 ! -perm -1000 2>/dev/null || true)
    if (( ${#ww_dirs_no_sticky[@]} > 0 )); then
        printf '%s\n' "${ww_dirs_no_sticky[@]}" >> "$perm_log"
    else
        echo "No world-writable directories without sticky bit detected." >> "$perm_log"
    fi

    echo "Checking for writable files within PATH directories..." | tee -a "$perm_log"
    IFS=':' read -ra path_dirs <<< "$PATH"
    local -a writable_path_bins=()
    for dir in "${path_dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r file; do
            writable_path_bins+=("$file")
        done < <(find "$dir" -maxdepth 1 -type f -perm -0002 -print 2>/dev/null)
    done
    if (( ${#writable_path_bins[@]} > 0 )); then
        printf '%s\n' "${writable_path_bins[@]}" >> "$perm_log"
    else
        echo "No world-writable files detected within PATH directories." >> "$perm_log"
    fi

    echo "Looking for overly permissive scripts and binaries..." | tee -a "$perm_log"
    mapfile -t permissive_scripts < <(sudo find / -xdev \( -name '*.sh' -o -name '*.py' -o -name '*.pl' -o -name '*.rb' -o -name '*.php' \) -perm -0002 2>/dev/null || true)
    if (( ${#permissive_scripts[@]} > 0 )); then
        printf '%s\n' "${permissive_scripts[@]}" >> "$perm_log"
    else
        echo "No overly permissive scripts detected." >> "$perm_log"
    fi

    echo "Binary integrity report: $integrity_log"
    echo "SUID/SGID audit report: $suid_log"
    echo "Permission anomaly report: $perm_log"
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
