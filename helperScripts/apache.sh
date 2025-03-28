#!/bin/bash

# #############################################################################
# Apache HTTP Server Hardening Script based on CIS Benchmark v2.2.0
#
# WARNING: This script modifies Apache configuration files.
#          BACK UP YOUR CONFIGURATION BEFORE RUNNING.
#          Review the script carefully and test in a non-production environment.
#          Run this script as root or with sudo.
#
# Usage: sudo ./apache_harden_cis.sh
# #############################################################################

# --- Configuration ---
BACKUP_DIR="/opt/apache_cis_backups_$(date +%Y%m%d_%H%M%S)"
APACHE_CONF_DIR=""
APACHE_CONF_FILE=""
APACHE_SERVICE=""
APACHE_USER=""
APACHE_GROUP=""
APACHE_DOC_ROOT="" # Will attempt to detect
APACHE_MODULE_UTIL="" # a2enmod/a2dismod or manual
APACHE_MODULE_DIR=""
DISTRO=""

# --- Helper Functions ---

log_info() {
    echo "[INFO] $1"
}

log_warn() {
    echo "[WARN] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script must be run as root or with sudo."
        exit 1
    fi
}

detect_distro() {
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        ID_LIKE=${ID_LIKE:-$ID} # Use ID if ID_LIKE is not set
        if [[ "$ID" == "ubuntu" || "$ID" == "debian" || "$ID_LIKE" == "debian" ]]; then
            DISTRO="debian"
            APACHE_CONF_DIR="/etc/apache2"
            APACHE_CONF_FILE="/etc/apache2/apache2.conf"
            APACHE_SERVICE="apache2"
            APACHE_USER="www-data"
            APACHE_GROUP="www-data"
            APACHE_MODULE_UTIL="a2" # Indicates a2enmod/a2dismod
            APACHE_MODULE_DIR="/etc/apache2/mods-available"
            log_info "Detected Debian/Ubuntu distribution."
        elif [[ "$ID" == "centos" || "$ID" == "rhel" || "$ID" == "fedora" || "$ID" == "rocky" || "$ID" == "almalinux" || "$ID_LIKE" == *"fedora"* ]]; then
            DISTRO="rhel"
            APACHE_CONF_DIR="/etc/httpd"
            APACHE_CONF_FILE="/etc/httpd/conf/httpd.conf"
            APACHE_SERVICE="httpd"
            APACHE_USER="apache"
            APACHE_GROUP="apache"
            APACHE_MODULE_UTIL="manual" # Indicates manual LoadModule editing
            APACHE_MODULE_DIR="/etc/httpd/conf.modules.d"
            log_info "Detected RHEL/CentOS/Fedora distribution."
        else
            log_error "Unsupported distribution: $ID"
            exit 1
        fi
    else
        log_error "/etc/os-release not found. Cannot detect distribution."
        exit 1
    fi

    # Attempt to detect DocumentRoot (basic guess)
    APACHE_DOC_ROOT=$(grep -i '^\s*DocumentRoot' "$APACHE_CONF_DIR"/*conf* "$APACHE_CONF_DIR"/sites-enabled/* "$APACHE_CONF_DIR"/conf.d/* 2>/dev/null | sed -n 's/^[ \t]*DocumentRoot[ \t]*"\?\([^"]*\)"\?/\1/p' | tail -n 1)
    if [[ -z "$APACHE_DOC_ROOT" ]]; then
        if [[ "$DISTRO" == "debian" ]]; then APACHE_DOC_ROOT="/var/www/html"; fi
        if [[ "$DISTRO" == "rhel" ]]; then APACHE_DOC_ROOT="/var/www/html"; fi
        log_warn "Could not reliably detect DocumentRoot, assuming $APACHE_DOC_ROOT"
    else
        log_info "Detected DocumentRoot: $APACHE_DOC_ROOT"
    fi

    # Ensure critical variables are set
     if [[ -z "$APACHE_CONF_DIR" || -z "$APACHE_CONF_FILE" || -z "$APACHE_SERVICE" || -z "$APACHE_USER" || -z "$APACHE_GROUP" ]]; then
         log_error "Critical Apache configuration variables could not be determined."
         exit 1
     fi
}

backup_config() {
    local file_to_backup="$1"
    if [[ ! -f "$file_to_backup" ]]; then
        log_warn "File not found, skipping backup: $file_to_backup"
        return
    fi
    local backup_path="$BACKUP_DIR$(dirname "$file_to_backup")"
    mkdir -p "$backup_path"
    cp -a "$file_to_backup" "$backup_path/"
    log_info "Backed up $file_to_backup to $backup_path/"
}

# Finds relevant config files (main + includes)
get_config_files() {
    find "$APACHE_CONF_DIR" -type f \( -name "*.conf" -o -name ".htaccess" \) -print0 | xargs -0 grep -l ""
    # This is a basic find, might need refinement for complex include structures
}

# Add or modify a directive in a specific file
# Usage: set_directive "DirectiveName" "DirectiveValue" "ConfigFile" ["ScopeRegex"]
# ScopeRegex is optional, used to add within a specific block like <Directory />
set_directive() {
    local directive="$1"
    local value="$2"
    local config_file="$3"
    local scope_regex="${4:-}"
    local full_directive="$directive $value"

    if [[ ! -f "$config_file" ]]; then
        log_warn "Config file not found for setting directive '$directive': $config_file"
        return
    fi

    backup_config "$config_file"

    # Check if directive exists with the correct value globally or within scope
    if [[ -n "$scope_regex" ]]; then
        # Complex scope checking is hard, this is a simplified check
        # It doesn't guarantee placement *within* the block, just checks if the directive exists somewhere
        if awk -v dir="$directive" -v val="$value" -v scope_start="$scope_regex" '
            BEGIN { found_scope=0; found_directive=0 }
            $0 ~ scope_start { found_scope=1 }
            found_scope && $1 == dir {
                line = $0; sub(/^[^ ]+ /, "", line);
                if (line == val) { found_directive=1; exit 0 }
            }
            found_scope && $0 ~ /<\// { found_scope=0 } # Basic end scope detection
            END { exit found_directive == 0 }
        ' "$config_file"; then
             log_info "'$directive $value' appears correctly set in/after scope '$scope_regex' in $config_file."
             return
        fi
    elif grep -q "^\s*${directive}\s\+${value}\s*$" "$config_file"; then
        log_info "'$directive $value' already correctly set in $config_file."
        return
    fi

    # Check if directive exists with a different value and modify it
    if grep -q "^\s*${directive}\s\+" "$config_file"; then
        log_info "Modifying '$directive' to '$value' in $config_file."
        # Use '#' as sed delimiter assuming paths don't contain it commonly
        sed -i "s#^\s*${directive}\s\+.*#${full_directive}#" "$config_file"
    else
        # Add the directive
        log_info "Adding '$directive $value' to $config_file."
        if [[ -n "$scope_regex" ]]; then
             # Attempt to add within scope - might need manual adjustment
             log_warn "Attempting to add '$full_directive' within scope '$scope_regex'. Verify placement in $config_file."
             sed -i "/${scope_regex}/a ${full_directive}" "$config_file"
        else
             # Add globally at the end (or choose a better location like security.conf if applicable)
             echo "$full_directive" >> "$config_file"
        fi
    fi
}

# Comment out a directive
# Usage: comment_directive "DirectiveRegex" "ConfigFile"
comment_directive() {
    local directive_regex="$1"
    local config_file="$2"

     if [[ ! -f "$config_file" ]]; then
        log_warn "Config file not found for commenting directive matching '$directive_regex': $config_file"
        return
    fi

    if grep -q "^\s*#\+\s*${directive_regex}" "$config_file"; then
        log_info "Directive matching '$directive_regex' already commented out in $config_file."
        return
    fi

    if grep -q "^\s*${directive_regex}" "$config_file"; then
        backup_config "$config_file"
        log_info "Commenting out directive matching '$directive_regex' in $config_file."
        sed -i "s#^\(\s*\)\(${directive_regex}\)#\1# \2#" "$config_file"
    else
        log_info "Directive matching '$directive_regex' not found in $config_file."
    fi
}

# Manage Apache modules
# Usage: manage_module "module_name" "enable|disable"
manage_module() {
    local module_name="$1"
    local action="$2" # "enable" or "disable"
    local module_file_name="mod_${module_name}.so"
    local loadmodule_line="LoadModule ${module_name}_module" # Regex part

    if [[ "$APACHE_MODULE_UTIL" == "a2" ]]; then
        # Debian/Ubuntu using a2enmod/a2dismod
        if [[ "$action" == "enable" ]]; then
            if [[ -L "$APACHE_CONF_DIR/mods-enabled/${module_name}.load" ]]; then
                 log_info "Module '$module_name' already enabled."
            else
                 if [[ -f "$APACHE_CONF_DIR/mods-available/${module_name}.load" ]]; then
                    log_info "Enabling module '$module_name'."
                    a2enmod "$module_name" || log_error "Failed to enable module '$module_name'."
                 else
                    log_warn "Module '$module_name' not available to enable."
                 fi
            fi
        elif [[ "$action" == "disable" ]]; then
             if [[ ! -L "$APACHE_CONF_DIR/mods-enabled/${module_name}.load" ]]; then
                 log_info "Module '$module_name' already disabled."
             else
                 log_info "Disabling module '$module_name'."
                 a2dismod "$module_name" || log_error "Failed to disable module '$module_name'."
             fi
        fi
    else
        # RHEL/Manual - Comment/Uncomment LoadModule lines
        local found_in_files=()
        # Check in main module dir and conf.d
        while IFS= read -r -d $'\0' file; do
            if grep -q "^\s*LoadModule\s\+${module_name}_module" "$file"; then
                 found_in_files+=("$file")
            fi
        done < <(find "$APACHE_MODULE_DIR" "$APACHE_CONF_DIR/conf.d" -maxdepth 1 -name "*.conf" -print0 2>/dev/null)

         if [[ ${#found_in_files[@]} -eq 0 ]]; then
             if [[ "$action" == "enable" ]]; then
                 log_warn "Could not find LoadModule line for '$module_name' to enable it. Manual check needed."
             else
                 log_info "Module '$module_name' not found (or already effectively disabled)."
             fi
             return
         fi

         for config_file in "${found_in_files[@]}"; do
             backup_config "$config_file"
             if [[ "$action" == "enable" ]]; then
                 # Uncomment
                 if grep -q "^\s*#\+\s*LoadModule\s\+${module_name}_module" "$config_file"; then
                     log_info "Enabling (uncommenting) module '$module_name' in $config_file."
                     sed -i "s#^\s*#\+\(\s*LoadModule\s\+${module_name}_module.*\)#\1#" "$config_file"
                 else
                     log_info "Module '$module_name' already enabled (uncommented) in $config_file."
                 fi
             elif [[ "$action" == "disable" ]]; then
                 # Comment out
                 if grep -q "^\s*LoadModule\s\+${module_name}_module" "$config_file"; then
                      log_info "Disabling (commenting) module '$module_name' in $config_file."
                      sed -i "s#^\(\s*LoadModule\s\+${module_name}_module.*\)## \1#" "$config_file"
                 else
                      log_info "Module '$module_name' already disabled (commented) in $config_file."
                 fi
             fi
         done
    fi
}

# Find and configure a block like <Directory /path> ... </Directory>
# Usage: configure_block "<Directory /path>" "Directive" "Value"
# NOTE: This is simplified. Adds directive *after* the opening tag. May not be ideal placement.
configure_block() {
    local block_start_regex="$1"
    local directive="$2"
    local value="$3"
    local files_to_check

    files_to_check=$(get_config_files)

    local found_block=0
    local file_containing_block=""

    # Try to find the block
    for f in $files_to_check; do
        if grep -q "$block_start_regex" "$f"; then
            file_containing_block="$f"
            found_block=1
            break
        fi
    done

    if [[ $found_block -eq 0 ]]; then
        log_warn "Could not find block '$block_start_regex'. Manual configuration needed for '$directive'."
        # Optionally: Create the block in a default/security config file
        # config_file="/etc/apache2/conf-available/security-cis.conf" or similar
        # echo "$block_start_regex" >> "$config_file"
        # echo "    $directive $value" >> "$config_file"
        # echo "</${block_start_regex#<}>" >> "$config_file"
        # manage_conf "security-cis" "enable" # If using conf-available
        return
    fi

    backup_config "$file_containing_block"

    # Check if directive exists with correct value within the block
    if awk -v block_start="$block_start_regex" -v dir="$directive" -v val="$value" '
        BEGIN { in_block=0; found_correct=0 }
        $0 ~ block_start { in_block=1 }
        in_block && $1 == dir {
            line = $0; sub(/^[^ ]+ /, "", line);
            if (line == val) { found_correct=1; exit 0 } # Exit awk successfully
        }
        in_block && $0 ~ /<\// { in_block=0 } # Basic end block detection
        END { exit found_correct == 0 } # Exit awk with 1 if not found correct
    ' "$file_containing_block"; then
         log_info "'$directive $value' already correctly set in block '$block_start_regex' in $file_containing_block."
    else
         # Check if directive exists with different value and modify it (within block - complex with sed)
         # Simplified: Check globally first, then attempt to add within block
         if grep -q "^\s*${directive}\s\+" "$file_containing_block"; then
             log_warn "Directive '$directive' exists globally or in another block in $file_containing_block. Attempting modification - review required."
             sed -i "s#^\s*${directive}\s\+.*#    $directive $value#" "$file_containing_block" # Risky - might modify wrong instance
         else
             # Add directive after the block start line
             log_info "Adding '$directive $value' to block '$block_start_regex' in $file_containing_block."
             # Use awk for safer insertion after the block start line
             awk -v block_start="$block_start_regex" -v new_line="    $directive $value" '
             1; $0 ~ block_start { print new_line }
             ' "$file_containing_block" > temp_$$ && mv temp_$$ "$file_containing_block"
         fi
    fi
}

# Manage Apache conf snippets (Debian/Ubuntu specific)
# Usage: manage_conf "conf_name" "enable|disable"
manage_conf() {
     if [[ "$DISTRO" != "debian" ]]; then return; fi
     local conf_name="$1"
     local action="$2"

     if [[ "$action" == "enable" ]]; then
         if [[ -L "$APACHE_CONF_DIR/conf-enabled/${conf_name}.conf" ]]; then
             log_info "Conf snippet '$conf_name' already enabled."
         else
             if [[ -f "$APACHE_CONF_DIR/conf-available/${conf_name}.conf" ]]; then
                 log_info "Enabling conf snippet '$conf_name'."
                 a2enconf "$conf_name" || log_error "Failed to enable conf '$conf_name'."
             else
                 log_warn "Conf snippet '$conf_name' not available to enable."
             fi
         fi
     elif [[ "$action" == "disable" ]]; then
         if [[ ! -L "$APACHE_CONF_DIR/conf-enabled/${conf_name}.conf" ]]; then
             log_info "Conf snippet '$conf_name' already disabled."
         else
             log_info "Disabling conf snippet '$conf_name'."
             a2disconf "$conf_name" || log_error "Failed to disable conf '$conf_name'."
         fi
     fi
}

# Find the primary config file for global settings or create one
find_primary_config() {
    if [[ "$DISTRO" == "debian" ]]; then
        # Use a dedicated conf snippet for CIS settings
        local cis_conf="/etc/apache2/conf-available/security-cis.conf"
        if [[ ! -f "$cis_conf" ]]; then
            log_info "Creating dedicated CIS config snippet: $cis_conf"
            echo "# CIS Benchmark Hardening Settings" > "$cis_conf"
            echo "# Managed by hardening script" >> "$cis_conf"
        fi
        manage_conf "security-cis" "enable"
        echo "$cis_conf"
    elif [[ "$DISTRO" == "rhel" ]]; then
         # Use a file in conf.d
         local cis_conf="/etc/httpd/conf.d/security-cis.conf"
         if [[ ! -f "$cis_conf" ]]; then
             log_info "Creating dedicated CIS config file: $cis_conf"
             echo "# CIS Benchmark Hardening Settings" > "$cis_conf"
             echo "# Managed by hardening script" >> "$cis_conf"
         fi
         echo "$cis_conf"
    else
        # Fallback to main config file
        echo "$APACHE_CONF_FILE"
    fi
}

# --- Main Script ---

check_root
detect_distro # Detect OS and set paths/variables

mkdir -p "$BACKUP_DIR"
log_info "Configuration backups will be stored in $BACKUP_DIR"

PRIMARY_CONF_FILE=$(find_primary_config)
log_info "Primary configuration file for global settings: $PRIMARY_CONF_FILE"

# --- Section 1: Planning and Installation (Manual) ---
log_info "CIS 1.1: Ensure Pre-Installation Planning Checklist (Manual)"
log_info "CIS 1.2: Ensure Server Is Not Multi-Use (Manual)"
log_info "CIS 1.3: Ensure Apache Is Installed From Appropriate Binaries (Manual)"

# --- Section 2: Minimize Apache Modules ---
log_info "CIS Section 2: Minimizing Apache Modules"
# 2.1 Manual - User must determine necessary auth modules
log_info "CIS 2.1: Ensure Only Necessary Authentication/Authorization Modules (Manual Review Required)"
log_warn "Review your authentication needs. Disabling common potentially unneeded modules below."

manage_module "authn_dbm" "disable"
manage_module "authn_anon" "disable"
manage_module "authn_dbd" "disable"
manage_module "authn_socache" "disable" # Often needed by ssl, check usage
manage_module "authz_dbm" "disable"
manage_module "authz_owner" "disable"
manage_module "authz_ldap" "disable" # If LDAP not used
manage_module "authz_dbd" "disable"

# 2.2 Ensure log_config is enabled (Usually built-in or enabled by default)
log_info "CIS 2.2: Ensuring log_config module is effectively enabled (Usually core)"
# manage_module "log_config" "enable" # Generally not needed to explicitly enable

# 2.3 Disable WebDAV
log_info "CIS 2.3: Disabling WebDAV modules"
manage_module "dav" "disable"
manage_module "dav_fs" "disable"
manage_module "dav_lock" "disable"

# 2.4 Disable Status module
log_info "CIS 2.4: Disabling status module"
manage_module "status" "disable"

# 2.5 Disable Autoindex module
log_info "CIS 2.5: Disabling autoindex module"
manage_module "autoindex" "disable"

# 2.6 Disable Proxy modules (if not used)
log_info "CIS 2.6: Disabling proxy modules (Re-enable if Apache is used as a proxy)"
manage_module "proxy" "disable"
manage_module "proxy_http" "disable"
manage_module "proxy_ftp" "disable"
manage_module "proxy_connect" "disable"
manage_module "proxy_ajp" "disable"
manage_module "proxy_balancer" "disable"
manage_module "proxy_express" "disable"
manage_module "proxy_fcgi" "disable"
manage_module "proxy_scgi" "disable"
manage_module "proxy_wstunnel" "disable"
manage_module "proxy_hcheck" "disable"

# 2.7 Disable User Directories module
log_info "CIS 2.7: Disabling userdir module"
manage_module "userdir" "disable"

# 2.8 Disable Info module
log_info "CIS 2.8: Disabling info module"
manage_module "info" "disable"

# 2.9 Disable Basic/Digest Auth modules (Use alternative auth if needed)
log_info "CIS 2.9: Disabling Basic and Digest authentication modules"
manage_module "auth_basic" "disable"
manage_module "auth_digest" "disable"

# --- Section 3: Principles, Permissions, and Ownership ---
log_info "CIS Section 3: Principles, Permissions, and Ownership"

# 3.1 Check User/Group are not root
log_info "CIS 3.1: Ensure Apache runs as non-root user"
if grep -qi '^\s*User\s\+root' "$APACHE_CONF_FILE" $(get_config_files); then
    log_error "Apache User directive is set to 'root'. This is insecure. Manually change to '$APACHE_USER' or similar."
else
    log_info "Apache User directive appears non-root."
    # Optionally ensure it's set to the expected user
    # set_directive "User" "$APACHE_USER" "$APACHE_CONF_FILE"
fi
if grep -qi '^\s*Group\s\+root' "$APACHE_CONF_FILE" $(get_config_files); then
     log_warn "Apache Group directive is set to 'root'. Consider changing to '$APACHE_GROUP'."
else
     log_info "Apache Group directive appears non-root."
     # Optionally ensure it's set to the expected group
     # set_directive "Group" "$APACHE_GROUP" "$APACHE_CONF_FILE"
fi

# 3.2 Ensure Apache user has invalid shell
log_info "CIS 3.2: Ensure Apache user account ($APACHE_USER) has invalid shell"
apache_shell=$(grep "^${APACHE_USER}:" /etc/passwd | cut -d: -f7)
invalid_shells=("/sbin/nologin" "/usr/sbin/nologin" "/bin/false")
is_invalid=0
for shell in "${invalid_shells[@]}"; do
    if [[ "$apache_shell" == "$shell" ]]; then
        is_invalid=1
        break
    fi
done
if [[ $is_invalid -eq 1 ]]; then
    log_info "Apache user shell is '$apache_shell' (considered invalid)."
else
    log_warn "Apache user shell is '$apache_shell'. Setting to /sbin/nologin (or /usr/sbin/nologin)."
    if command -v usermod > /dev/null; then
        if [[ -e /sbin/nologin ]]; then
             usermod -s /sbin/nologin "$APACHE_USER" || log_error "Failed to set shell for $APACHE_USER"
        elif [[ -e /usr/sbin/nologin ]]; then
             usermod -s /usr/sbin/nologin "$APACHE_USER" || log_error "Failed to set shell for $APACHE_USER"
        else
             usermod -s /bin/false "$APACHE_USER" || log_error "Failed to set shell for $APACHE_USER"
        fi
    else
        log_warn "usermod command not found. Manually set shell for $APACHE_USER."
    fi
fi

# 3.3 Ensure Apache user account is locked
log_info "CIS 3.3: Ensure Apache user account ($APACHE_USER) is locked"
if command -v passwd > /dev/null; then
    passwd_status=$(passwd -S "$APACHE_USER" 2>/dev/null | awk '{print $2}')
    if [[ "$passwd_status" == "L" || "$passwd_status" == "LK" ]]; then
        log_info "Apache user account is locked."
    elif [[ "$passwd_status" == "NP" ]]; then
         log_info "Apache user account has no password set."
    elif [[ "$passwd_status" == "P" || "$passwd_status" == "PS" ]]; then
        log_warn "Apache user account has a password set. Locking account."
        passwd -l "$APACHE_USER" || log_error "Failed to lock account $APACHE_USER."
    else
        log_warn "Could not reliably determine lock status for $APACHE_USER (Status: $passwd_status). Manual check recommended."
    fi
else
     log_warn "passwd command not found. Manually verify $APACHE_USER account is locked."
fi

# 3.4, 3.5 Ownership (Manual Check Recommended)
log_info "CIS 3.4, 3.5: Ensure Apache directories/files owned by root:root (Manual Check Recommended)"
log_warn "Checking ownership of config directories. Files not owned by root:root will be listed."
find "$APACHE_CONF_DIR" \( \! -user root -o \! -group root \) -ls
log_warn "Review listed files. Run 'chown -R root:root /path/to/apache/config' if appropriate."

# 3.6 Restrict 'Other' Write Access on Apache Dirs/Files
log_info "CIS 3.6: Restricting 'Other' write access on Apache config/binary directories"
# Be careful not to change permissions on DocRoot here
find "$APACHE_CONF_DIR" -type f -perm /o=w -print -exec chmod o-w {} \;
find "$APACHE_CONF_DIR" -type d -perm /o=w -print -exec chmod o-w {} \;
# Also check common binary locations if known
if [[ -d /usr/sbin/ ]]; then
     find /usr/sbin/ -name "apache*" -o -name "httpd*" -perm /o=w -print -exec chmod o-w {} \;
fi

# 3.7 CoreDumpDirectory (Check if set, ensure disabled or secure)
log_info "CIS 3.7: Secure Core Dump Directory (Ensuring disabled if possible)"
# Core dumps usually disabled by default when switching to non-root user.
# Check if explicitly enabled and secure if so.
coredump_dir=$(grep -ihr '^\s*CoreDumpDirectory' "$APACHE_CONF_DIR" | awk '{print $2}')
if [[ -n "$coredump_dir" ]]; then
    log_warn "CoreDumpDirectory is set to '$coredump_dir'. Ensure this directory is secured (root owned, not world readable/writable). CIS recommends disabling."
    # Consider commenting it out:
    # find "$APACHE_CONF_DIR" -type f -name "*.conf" -print0 | xargs -0 sed -i 's/^\s*CoreDumpDirectory/#&/'
else
    log_info "CoreDumpDirectory not explicitly set (or commented out)."
fi

# 3.8, 3.9, 3.10 LockFile, PidFile, ScoreBoardFile (Secure Directories)
log_info "CIS 3.8, 3.9, 3.10: Secure LockFile, PidFile, ScoreBoardFile directories"
# Check common runtime directories like /run/apache2 or /run/httpd
RUNTIME_DIR="/run/${APACHE_SERVICE}"
if [[ -d "$RUNTIME_DIR" ]]; then
     log_info "Checking permissions for runtime directory: $RUNTIME_DIR"
     ls -ld "$RUNTIME_DIR"
     if ! stat -c "%U:%G %a" "$RUNTIME_DIR" | grep -q "root:root 755"; then # Or stricter like 700 if group doesn't need access
         log_warn "Permissions for $RUNTIME_DIR are not ideal (expected root:root 755 or similar). Review manually."
         # Consider: chmod 755 "$RUNTIME_DIR"; chown root:root "$RUNTIME_DIR"
     fi
     find "$RUNTIME_DIR" -type f \( -perm /g=w -o -perm /o=w \) -ls # Files inside should not be group/other writable
     # Consider: find "$RUNTIME_DIR" -type f -exec chmod go-w {} \;
else
     log_warn "Could not find common runtime directory $RUNTIME_DIR. Manual check for PidFile/LockFile paths needed."
fi
# Check Log directory permissions if Mutex file:/ Scoreboard file: used there
LOG_DIR=$(grep -ih '^\s*ErrorLog' "$APACHE_CONF_DIR"/*conf* "$APACHE_CONF_DIR"/sites-enabled/* "$APACHE_CONF_DIR"/conf.d/* 2>/dev/null | sed -n 's#^[ \t]*ErrorLog[ \t]*"\?\([^/][^"]*\)"\?#logs/\1#p; s#^[ \t]*ErrorLog[ \t]*"\?\(/[^"]*\)"\?#\1#p' | xargs dirname | sort -u | head -n 1)
if [[ -n "$LOG_DIR" && -d "$LOG_DIR" ]]; then
    log_info "Checking log directory permissions ($LOG_DIR) relevant for potential Mutex/Scoreboard files."
    ls -ld "$LOG_DIR"
    # Log dir often needs write access for apache group, but 'other' should be restricted
    find "$LOG_DIR" -maxdepth 0 -perm /o=wx -print -exec chmod o-wx {} \; # Restrict 'other' execute needed to enter dir
fi

# 3.11 Restrict Group Write on Apache Dirs/Files
log_info "CIS 3.11: Restricting Group write access on Apache config/binary directories"
find "$APACHE_CONF_DIR" -type f -perm /g=w -print -exec chmod g-w {} \;
find "$APACHE_CONF_DIR" -type d -perm /g=w -print -exec chmod g-w {} \;
if [[ -d /usr/sbin/ ]]; then
     find /usr/sbin/ -name "apache*" -o -name "httpd*" -perm /g=w -print -exec chmod g-w {} \;
fi

# 3.12 Restrict Group Write for Apache *RUNTIME* Group on DocRoot
log_info "CIS 3.12: Restricting Group write access for '$APACHE_GROUP' on DocumentRoot '$APACHE_DOC_ROOT'"
if [[ -d "$APACHE_DOC_ROOT" ]]; then
    log_info "Files/Dirs in DocumentRoot writable by group '$APACHE_GROUP':"
    find "$APACHE_DOC_ROOT" -group "$APACHE_GROUP" -perm /g=w -ls
    log_info "Applying chmod g-w to files/dirs in DocumentRoot owned by group '$APACHE_GROUP'."
    find "$APACHE_DOC_ROOT" -group "$APACHE_GROUP" -perm /g=w -exec chmod g-w {} \;
else
    log_warn "DocumentRoot '$APACHE_DOC_ROOT' not found. Skipping check 3.12."
fi

# 3.13 Special Purpose Writable Dirs (Manual)
log_info "CIS 3.13: Ensure Special Purpose Application Writable Dirs Restricted (Manual)"
log_warn "If applications need writable directories, ensure they are OUTSIDE DocumentRoot, single-purpose, root owned, and not world-writable."

# --- Section 4: Apache Access Control ---
log_info "CIS Section 4: Apache Access Control"

# 4.1 Deny OS Root Directory Access
log_info "CIS 4.1: Denying access to OS Root Directory ('<Directory />')"
# Ensure <Directory /> block exists and has Require all denied
# We add this to the main config file for simplicity, might exist elsewhere
backup_config "$APACHE_CONF_FILE"
if ! grep -q '^\s*<Directory\s*/\s*>' "$APACHE_CONF_FILE"; then
    log_info "Adding '<Directory />' block to $APACHE_CONF_FILE"
    cat << EOF >> "$APACHE_CONF_FILE"

<Directory />
    AllowOverride None
    Require all denied
</Directory>
EOF
else
    log_info "Configuring '<Directory />' block in $APACHE_CONF_FILE"
    # Use awk to ensure directives are inside the block
    awk '
    BEGIN { in_block=0; printed_req=0; printed_ao=0 }
    /^\s*<Directory\s*\/\s*>/ { print; in_block=1; next }
    in_block && /^\s*Require\s+all\s+denied/ { print; printed_req=1; next }
    in_block && /^\s*AllowOverride\s+None/ { print; printed_ao=1; next }
    in_block && /^\s*AllowOverrideList\s+None/ { print; printed_ao=1; next } # Alternative
    in_block && /^\s*Order\s+/ { next } # Remove deprecated Order
    in_block && /^\s*Deny\s+/ { next } # Remove deprecated Deny
    in_block && /^\s*Allow\s+/ { next } # Remove deprecated Allow
    in_block && /^\s*Require\s+/ { next } # Remove other Require directives
    in_block && /^\s*AllowOverride\s+/ { next } # Remove other AllowOverride
    in_block && /^\s*AllowOverrideList\s+/ { next } # Remove other AllowOverrideList
    /^\s*<\/Directory\s*>/ && in_block {
        if (!printed_ao) print "    AllowOverride None";
        if (!printed_req) print "    Require all denied";
        print;
        in_block=0; printed_req=0; printed_ao=0;
        next;
    }
    { print }
    ' "$APACHE_CONF_FILE" > temp_$$ && mv temp_$$ "$APACHE_CONF_FILE"
fi

# 4.2 Allow Web Content Access (Manual) - Must be configured by user based on DocRoot
log_info "CIS 4.2: Ensure Appropriate Access to Web Content Is Allowed (Manual)"
log_warn "You MUST configure appropriate '<Directory $APACHE_DOC_ROOT>' or similar blocks with 'Require' directives to allow access to your web content."
# Example (Needs manual confirmation/adjustment):
# configure_block "<Directory \"${APACHE_DOC_ROOT}\">" "Require" "all granted"

# 4.3 Disable OverRide for OS Root Directory
log_info "CIS 4.3: Ensure AllowOverride is None for OS Root Directory ('<Directory />')"
# Handled by the awk script in 4.1

# 4.4 Disable OverRide for All Directories (Check only, modification complex)
log_info "CIS 4.4: Ensure AllowOverride is None for All Directories (Checking for non-None values)"
override_issues=$(get_config_files | xargs grep -Ei '^\s*AllowOverride(List)?\s+(?!None)')
if [[ -n "$override_issues" ]]; then
    log_warn "Found AllowOverride directives not set to 'None'. Review these:"
    echo "$override_issues"
else
    log_info "No AllowOverride directives found that are not 'None' (excluding OS root handled above)."
fi

# --- Section 5: Minimize Features, Content and Options ---
log_info "CIS Section 5: Minimizing Features, Content, Options"

# 5.1 Restrict Options for OS Root Directory
log_info "CIS 5.1: Restricting Options for OS Root Directory ('<Directory />')"
configure_block '<Directory\s*/\s*>' "Options" "None"

# 5.2 Restrict Options for Web Root Directory
log_info "CIS 5.2: Restricting Options for Web Root Directory ('<Directory $APACHE_DOC_ROOT>')"
# Common safe default allows following symlinks if needed, disallows Indexes, CGI, SSI
# Adjust if FollowSymLinks is not needed or MultiViews is required.
configure_block "<Directory \"${APACHE_DOC_ROOT}\">" "Options" "FollowSymLinks"
# Or stricter: configure_block "<Directory \"${APACHE_DOC_ROOT}\">" "Options" "None"

# 5.3 Minimize Options for Other Directories (Check only)
log_info "CIS 5.3: Minimizing Options for Other Directories (Checking for Includes, ExecCGI)"
options_includes=$(get_config_files | xargs grep -Ei '^\s*Options\s+.*\bIncludes\b')
options_execcgi=$(get_config_files | xargs grep -Ei '^\s*Options\s+.*\bExecCGI\b')
if [[ -n "$options_includes" ]]; then log_warn "Found 'Options Includes'. Review if needed for SSI: $options_includes"; fi
if [[ -n "$options_execcgi" ]]; then log_warn "Found 'Options ExecCGI'. Review if needed for CGI execution: $options_execcgi"; fi

# 5.4, 5.5, 5.6 Remove Default Content/CGIs (Manual)
log_info "CIS 5.4: Ensure Default HTML Content Is Removed (Manual)"
log_info "CIS 5.5: Ensure Default CGI 'printenv' Script Is Removed (Manual)"
log_info "CIS 5.6: Ensure Default CGI 'test-cgi' Script Is Removed (Manual)"
log_warn "Manually remove default welcome pages, icons, manuals, and CGI scripts."

# 5.7 Restrict HTTP Request Methods
log_info "CIS 5.7: Restricting HTTP Request Methods (Applying to DocRoot)"
# Apply to DocumentRoot block. Assumes $APACHE_DOC_ROOT is set.
if [[ -d "$APACHE_DOC_ROOT" ]]; then
    # Find the config file containing the DocRoot Directory block
     docroot_conf=$(get_config_files | xargs grep -l "<Directory \"${APACHE_DOC_ROOT}\">" | head -n 1)
     if [[ -n "$docroot_conf" ]]; then
         backup_config "$docroot_conf"
         log_info "Adding LimitExcept to block '<Directory \"${APACHE_DOC_ROOT}\">' in $docroot_conf"
         # Use awk to add the block after the Directory opening tag
         awk -v block_start="<Directory \"${APACHE_DOC_ROOT}\">" '
         1;
         $0 ~ block_start {
             print "    <LimitExcept GET POST OPTIONS HEAD>";
             print "        Require all denied";
             print "    </LimitExcept>";
         }
         ' "$docroot_conf" > temp_$$ && mv temp_$$ "$docroot_conf"
     else
        log_warn "Could not find config file for DocumentRoot block. Manual LimitExcept needed."
     fi
else
    log_warn "DocumentRoot '$APACHE_DOC_ROOT' not found. Skipping method restriction 5.7."
fi

# 5.8 Disable TRACE Method
log_info "CIS 5.8: Disabling HTTP TRACE method"
set_directive "TraceEnable" "Off" "$PRIMARY_CONF_FILE"

# 5.9 Disallow Old HTTP Protocol Versions
log_info "CIS 5.9: Disallowing old HTTP protocol versions (Requires mod_rewrite)"
manage_module "rewrite" "enable"
backup_config "$PRIMARY_CONF_FILE"
# Add rewrite rules if not present
if ! grep -q 'RewriteCond %{THE_REQUEST} !(HTTP/1\.1|HTTP/2\.0)$' "$PRIMARY_CONF_FILE"; then
    log_info "Adding mod_rewrite rules to disallow old HTTP protocols in $PRIMARY_CONF_FILE"
    cat << EOF >> "$PRIMARY_CONF_FILE"

RewriteEngine On
RewriteCond %{THE_REQUEST} !(HTTP/1\.1|HTTP/2\.0)$
RewriteRule .* - [F]
EOF
else
    log_info "mod_rewrite rules for HTTP protocol check seem present in $PRIMARY_CONF_FILE."
    set_directive "RewriteEngine" "On" "$PRIMARY_CONF_FILE" # Ensure it's On
fi

# 5.10 Restrict Access to .ht* files
log_info "CIS 5.10: Restricting access to .ht* files"
backup_config "$PRIMARY_CONF_FILE"
if ! grep -q '<FilesMatch "\^\\.ht">' "$PRIMARY_CONF_FILE"; then
    log_info "Adding FilesMatch for .ht* files to $PRIMARY_CONF_FILE"
    cat << EOF >> "$PRIMARY_CONF_FILE"

<FilesMatch "^\\.ht">
    Require all denied
</FilesMatch>
EOF
else
    log_info "FilesMatch for .ht* seems present in $PRIMARY_CONF_FILE."
    # Could verify Require all denied inside block here if needed
fi

# 5.11 Restrict Access to .git files/directories
log_info "CIS 5.11: Restricting access to .git files/directories"
backup_config "$PRIMARY_CONF_FILE"
if ! grep -q '<DirectoryMatch "/\\.git">' "$PRIMARY_CONF_FILE"; then
     log_info "Adding DirectoryMatch for .git to $PRIMARY_CONF_FILE"
    cat << EOF >> "$PRIMARY_CONF_FILE"

<DirectoryMatch "/\\.git">
    Require all denied
</DirectoryMatch>
EOF
else
    log_info "DirectoryMatch for .git seems present in $PRIMARY_CONF_FILE."
fi

# 5.12 Restrict Access to .svn files/directories
log_info "CIS 5.12: Restricting access to .svn files/directories"
backup_config "$PRIMARY_CONF_FILE"
if ! grep -q '<DirectoryMatch "/\\.svn">' "$PRIMARY_CONF_FILE"; then
    log_info "Adding DirectoryMatch for .svn to $PRIMARY_CONF_FILE"
    cat << EOF >> "$PRIMARY_CONF_FILE"

<DirectoryMatch "/\\.svn">
    Require all denied
</DirectoryMatch>
EOF
else
     log_info "DirectoryMatch for .svn seems present in $PRIMARY_CONF_FILE."
fi

# 5.13 Restrict Inappropriate File Extensions (Level 2 - Manual)
log_info "CIS 5.13: Restrict Inappropriate File Extensions (Level 2 - Manual)"
log_warn "Define allowed extensions using FilesMatch. Requires analysis of site content."
# Example (Add to $PRIMARY_CONF_FILE):
# <FilesMatch "\.(?!(html|htm|css|js|png|jpe?g|gif|pdf)$)">  # Adjust extensions
#    Require all denied
# </FilesMatch>

# 5.14 Disallow IP Address Based Requests (Level 2 - Requires mod_rewrite)
log_info "CIS 5.14: Disallowing IP address based requests (Level 2 - Requires mod_rewrite)"
manage_module "rewrite" "enable"
backup_config "$PRIMARY_CONF_FILE"
if ! grep -q 'RewriteCond %{HTTP_HOST} ^[0-9]' "$PRIMARY_CONF_FILE"; then # Basic check for IP host
    log_info "Adding mod_rewrite rule to disallow IP-based Host headers in $PRIMARY_CONF_FILE"
    cat << EOF >> "$PRIMARY_CONF_FILE"

RewriteCond %{HTTP_HOST} ^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$
RewriteRule ^(.*)$ - [F,L]
EOF
    set_directive "RewriteEngine" "On" "$PRIMARY_CONF_FILE" # Ensure it's On
else
    log_info "mod_rewrite rule for IP Host check seems present in $PRIMARY_CONF_FILE."
fi

# 5.15 Specify Listen IPs (Level 2 - Check only)
log_info "CIS 5.15: Ensure specific IP Addresses are used for Listen (Level 2 - Check only)"
listen_any=$(get_config_files | xargs grep -Ei '^\s*Listen\s+(80|443|0\.0\.0\.0:|\[::\]:)')
if [[ -n "$listen_any" ]]; then
    log_warn "Found Listen directives that might bind to all interfaces. Review and specify IPs if needed:"
    echo "$listen_any"
else
    log_info "Listen directives appear to use specific IPs or non-standard ports (manual review still recommended)."
fi

# 5.16 Restrict Browser Framing (Clickjacking) (Level 2 - Requires mod_headers)
log_info "CIS 5.16: Restricting browser framing (Clickjacking) (Level 2 - Requires mod_headers)"
manage_module "headers" "enable"
# Using Content-Security-Policy is preferred
set_directive "Header always set" "Content-Security-Policy \"frame-ancestors 'self'\"" "$PRIMARY_CONF_FILE"
# Fallback: set_directive "Header always set" "X-Frame-Options SAMEORIGIN" "$PRIMARY_CONF_FILE"

# 5.17 Set Referrer-Policy (Level 2/Manual - Requires mod_headers)
log_info "CIS 5.17: Set HTTP Header Referrer-Policy appropriately (Level 2/Manual - Requires mod_headers)"
manage_module "headers" "enable"
log_warn "Setting Referrer-Policy to 'strict-origin-when-cross-origin'. Review if this policy is appropriate for your site."
set_directive "Header always set" "Referrer-Policy \"strict-origin-when-cross-origin\"" "$PRIMARY_CONF_FILE"

# 5.18 Set Permissions-Policy (Level 2/Manual - Requires mod_headers)
log_info "CIS 5.18: Set HTTP Header Permissions-Policy appropriately (Level 2/Manual - Requires mod_headers)"
manage_module "headers" "enable"
log_warn "Setting a restrictive Permissions-Policy example. Review features needed by your site."
set_directive "Header always set" "Permissions-Policy \"geolocation=(), microphone=(), camera=(), usb=()\"" "$PRIMARY_CONF_FILE"

# --- Section 6: Operations - Logging, Monitoring, Maintenance ---
log_info "CIS Section 6: Operations"

# 6.1 Configure Error Log Filename and Severity Level
log_info "CIS 6.1: Configuring ErrorLog filename and LogLevel"
# Ensure ErrorLog is set (adjust path/syslog as needed)
set_directive "ErrorLog" "logs/error_log" "$APACHE_CONF_FILE" # Or use $PRIMARY_CONF_FILE or syslog:local1 for 6.2
set_directive "LogLevel" "notice core:info" "$PRIMARY_CONF_FILE"

# 6.2 Configure Syslog Facility (Level 2)
log_info "CIS 6.2: Configure Syslog Facility for Error Logging (Level 2)"
log_warn "Consider changing ErrorLog to use syslog (e.g., 'ErrorLog syslog:local1'). Applying this now."
set_directive "ErrorLog" "syslog:local1" "$APACHE_CONF_FILE" # Adjust facility if needed

# 6.3 Configure Server Access Log
log_info "CIS 6.3: Configuring Access Log (CustomLog)"
# Define combined log format if not present
backup_config "$PRIMARY_CONF_FILE"
if ! grep -q 'LogFormat.*combined' "$PRIMARY_CONF_FILE"; then
    log_info "Defining 'combined' LogFormat in $PRIMARY_CONF_FILE"
    # Insert LogFormat definition near potential other LogFormat lines or globally
     sed -i '/LogLevel/a LogFormat "%h %l %u %t \\"%r\\" %>s %b \\"%{Referer}i\\" \\"%{User-agent}i\\"" combined' "$PRIMARY_CONF_FILE"
fi
# Ensure CustomLog uses combined format (adjust path as needed)
set_directive "CustomLog" "logs/access_log combined" "$APACHE_CONF_FILE" # Or $PRIMARY_CONF_FILE

# 6.4 Log Storage/Rotation (Manual)
log_info "CIS 6.4: Ensure Log Storage and Rotation (Manual)"
log_warn "Configure log rotation (e.g., using logrotate or rotatelogs piped logging) to retain logs for >= 3 months and prevent disk exhaustion."

# 6.5 Apply Patches (Manual)
log_info "CIS 6.5: Ensure Applicable Patches Are Applied (Manual)"
log_warn "Regularly update Apache and OS packages."

# 6.6 ModSecurity Installed (Level 2 - Check only)
log_info "CIS 6.6: Ensure ModSecurity Is Installed (Level 2 - Check only)"
if apachectl -M 2>/dev/null | grep -q 'security2_module'; then
    log_info "ModSecurity (security2_module) appears to be loaded."
else
    log_warn "ModSecurity (security2_module) does not appear to be loaded. Install if required."
fi

# 6.7 OWASP ModSecurity CRS Enabled (Level 2 - Manual)
log_info "CIS 6.7: Ensure OWASP ModSecurity Core Rule Set Is Installed/Enabled (Level 2 - Manual)"
log_warn "Manual installation and tuning of OWASP CRS is required if using ModSecurity."

# --- Section 7: SSL/TLS Configuration ---
log_info "CIS Section 7: SSL/TLS Configuration (Requires mod_ssl)"

# 7.1 Ensure mod_ssl installed/enabled
log_info "CIS 7.1: Ensuring mod_ssl is enabled"
manage_module "ssl" "enable"
# Check if module is actually loaded after trying to enable
if ! apachectl -M 2>/dev/null | grep -q 'ssl_module'; then
    log_error "mod_ssl is required for TLS/SSL settings but could not be verified as loaded. Aborting TLS section."
    # Exit or skip SSL section? Skipping for now.
    SKIP_SSL=1
else
    SKIP_SSL=0
fi

if [[ "$SKIP_SSL" -eq 0 ]]; then
    # Find primary SSL config file or add to default virtual host / primary conf
    SSL_CONF_FILE=$(find "$APACHE_CONF_DIR" -type f -name "ssl.conf" -o -name "*-ssl.conf" -o -name "default-ssl.conf" | head -n 1)
    if [[ -z "$SSL_CONF_FILE" ]]; then
        log_warn "Could not find a dedicated SSL config file. Applying SSL settings to $PRIMARY_CONF_FILE. Consider using a dedicated file or VirtualHost."
        SSL_CONF_FILE="$PRIMARY_CONF_FILE"
    else
         log_info "Applying SSL settings primarily to $SSL_CONF_FILE"
    fi

    # 7.2 Valid Certificate (Manual)
    log_info "CIS 7.2: Ensure Valid Trusted Certificate Installed (Manual)"
    log_warn "Manually obtain and configure a valid, trusted TLS certificate (SSLCertificateFile, SSLCertificateKeyFile)."

    # 7.3 Private Key Protection (Check only)
    log_info "CIS 7.3: Ensure Private Key Is Protected (Check only)"
    key_files=$(get_config_files | xargs grep -ih '^\s*SSLCertificateKeyFile' | awk '{print $2}' | sed 's/"//g')
    if [[ -n "$key_files" ]]; then
        log_info "Checking ownership and permissions for potential private key files:"
        for kf in $key_files; do
             if [[ -f "$kf" ]]; then
                 ls -l "$kf"
                 owner_group=$(stat -c "%U:%G" "$kf")
                 perms=$(stat -c "%a" "$kf")
                 if [[ "$owner_group" != "root:root" || "$perms" != "400" ]]; then
                     log_warn "Key file $kf has incorrect ownership/permissions (Expected root:root 400). Run: chown root:root '$kf'; chmod 400 '$kf'"
                 fi
             else
                 log_warn "Key file path not found: $kf"
             fi
        done
    else
        log_warn "Could not find SSLCertificateKeyFile directive to check."
    fi

    # 7.4 Disable TLSv1.0, TLSv1.1
    log_info "CIS 7.4: Disabling TLSv1.0 and TLSv1.1"
    set_directive "SSLProtocol" "all -SSLv3 -TLSv1 -TLSv1.1" "$SSL_CONF_FILE"

    # 7.5, 7.8 Disable Weak/Medium Ciphers (Use combined strong suite)
    log_info "CIS 7.5, 7.8: Disabling Weak and Medium strength ciphers"
    # Example strong suite (Check compatibility with clients, OpenSSL version matters)
    # This is a common strong suite favouring GCM and Forward Secrecy
    CIPHER_SUITE="EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH:!SHA1:!SHA256:!SHA384:!aNULL:!eNULL:!EXP:!DES:!RC4:!MD5:!PSK:!SRP:!CAMELLIA:!3DES:!IDEA"
    set_directive "SSLCipherSuite" "\"${CIPHER_SUITE}\"" "$SSL_CONF_FILE" # Quote if using newer Apache
    set_directive "SSLHonorCipherOrder" "on" "$SSL_CONF_FILE" # Check older Apache might use 'On'

    # 7.6 Disable Insecure SSL Renegotiation
    log_info "CIS 7.6: Ensuring Insecure SSL Renegotiation is disabled"
    # Default is off, so only ensure it's not explicitly 'on'
    comment_directive "SSLInsecureRenegotiation\s+on" "$SSL_CONF_FILE"
    # Or explicitly set off: set_directive "SSLInsecureRenegotiation" "off" "$SSL_CONF_FILE"

    # 7.7 Disable SSL Compression
    log_info "CIS 7.7: Disabling SSL Compression"
    set_directive "SSLCompression" "off" "$SSL_CONF_FILE" # Check older Apache might use 'Off'

    # 7.9 All Content via HTTPS (Manual)
    log_info "CIS 7.9: Ensure All Web Content Accessed via HTTPS (Manual)"
    log_warn "Configure redirects from HTTP to HTTPS if needed (e.g., using mod_rewrite in HTTP vhost)."

    # 7.10 Enable OCSP Stapling (Level 2)
    log_info "CIS 7.10: Enabling OCSP Stapling (Level 2)"
    set_directive "SSLUseStapling" "on" "$SSL_CONF_FILE" # Check older Apache might use 'On'
    # Define cache (shmcb preferred if available)
    set_directive "SSLStaplingCache" "\"shmcb:logs/ssl_stapling(32768)\"" "$SSL_CONF_FILE"

    # 7.11 Enable HTTP Strict Transport Security (HSTS) (Level 2 - Requires mod_headers)
    log_info "CIS 7.11: Enabling HSTS (Level 2 - Requires mod_headers)"
    manage_module "headers" "enable"
    # Start with a short max-age for testing (e.g., 300 seconds = 5 mins)
    # Increase gradually to e.g., 31536000 (1 year) once confirmed working.
    # Add 'includeSubDomains' carefully after verifying all subdomains support HTTPS.
    log_warn "Setting HSTS max-age to 600 seconds (10 minutes). Increase after testing."
    set_directive "Header always set" "Strict-Transport-Security \"max-age=600\"" "$SSL_CONF_FILE"

    # 7.12 Ensure Forward Secrecy (Level 2)
    log_info "CIS 7.12: Ensure Only Cipher Suites Providing Forward Secrecy (Level 2)"
    log_info "This is covered by the SSLCipherSuite setting in 7.5/7.8 which prioritizes EECDH/EDH."

fi # End SSL Skipped section

# --- Section 8: Information Leakage ---
log_info "CIS Section 8: Information Leakage"

# 8.1 Set ServerTokens to Prod
log_info "CIS 8.1: Setting ServerTokens to Prod"
set_directive "ServerTokens" "Prod" "$PRIMARY_CONF_FILE"

# 8.2 Set ServerSignature to Off
log_info "CIS 8.2: Setting ServerSignature to Off"
set_directive "ServerSignature" "Off" "$PRIMARY_CONF_FILE"

# 8.3 Remove All Default Apache Content (Manual)
log_info "CIS 8.3: Ensure All Default Apache Content Is Removed (Manual)"
log_warn "Manually remove default welcome pages, icons, manuals, etc. (See also 5.4-5.6)"

# 8.4 Configure ETag Header (Level 2)
log_info "CIS 8.4: Configuring ETag response header (Level 2)"
set_directive "FileETag" "MTime Size" "$PRIMARY_CONF_FILE"

# --- Section 9: Denial of Service Mitigations ---
log_info "CIS Section 9: Denial of Service Mitigations"

# 9.1 Set TimeOut
log_info "CIS 9.1: Setting Timeout to 10"
set_directive "Timeout" "10" "$PRIMARY_CONF_FILE"

# 9.2 Enable KeepAlive
log_info "CIS 9.2: Enabling KeepAlive"
set_directive "KeepAlive" "On" "$PRIMARY_CONF_FILE"

# 9.3 Set MaxKeepAliveRequests
log_info "CIS 9.3: Setting MaxKeepAliveRequests to 100"
set_directive "MaxKeepAliveRequests" "100" "$PRIMARY_CONF_FILE"

# 9.4 Set KeepAliveTimeout
log_info "CIS 9.4: Setting KeepAliveTimeout to 15"
set_directive "KeepAliveTimeout" "15" "$PRIMARY_CONF_FILE"

# 9.5, 9.6 Set Timeout Limits for Request Headers/Body (Requires mod_reqtimeout)
log_info "CIS 9.5, 9.6: Setting RequestReadTimeout (Requires mod_reqtimeout)"
manage_module "reqtimeout" "enable"
if apachectl -M 2>/dev/null | grep -q 'reqtimeout_module'; then
    set_directive "RequestReadTimeout" "header=20-40,MinRate=500 body=20,MinRate=500" "$PRIMARY_CONF_FILE"
else
    log_warn "mod_reqtimeout not loaded. Cannot set RequestReadTimeout."
fi

# --- Section 10: Request Limits (Level 2) ---
log_info "CIS Section 10: Request Limits (Level 2)"

# 10.1 Set LimitRequestLine
log_info "CIS 10.1: Setting LimitRequestLine to 8190 (Level 2)"
set_directive "LimitRequestLine" "8190" "$PRIMARY_CONF_FILE"

# 10.2 Set LimitRequestFields
log_info "CIS 10.2: Setting LimitRequestFields to 100 (Level 2)"
set_directive "LimitRequestFields" "100" "$PRIMARY_CONF_FILE"

# 10.3 Set LimitRequestFieldsize
log_info "CIS 10.3: Setting LimitRequestFieldsize to 1024 (Level 2)"
set_directive "LimitRequestFieldsize" "1024" "$PRIMARY_CONF_FILE"

# 10.4 Set LimitRequestBody
log_info "CIS 10.4: Setting LimitRequestBody to 102400 (100k) (Level 2)"
log_warn "Setting LimitRequestBody to 100k. Test file uploads if used!"
set_directive "LimitRequestBody" "102400" "$PRIMARY_CONF_FILE" # Apply globally, can override per-directory

# --- Section 11: SELinux (Level 2 - RHEL specific, Check only/Manual) ---
log_info "CIS Section 11: Enable SELinux (Level 2 - RHEL specific)"
if [[ "$DISTRO" == "rhel" ]] && command -v sestatus > /dev/null; then
    log_info "CIS 11.1: Checking SELinux enforcing mode"
    sestatus | grep "Current mode"
    sestatus | grep "Mode from config file"
    if ! sestatus | grep -q "Current mode:\s*enforcing"; then log_warn "SELinux not currently enforcing. Run 'setenforce 1'."; fi
    if ! grep -q 'SELINUX=enforcing' /etc/selinux/config; then log_warn "SELinux not set to enforcing in /etc/selinux/config."; fi

    log_info "CIS 11.2: Checking Apache process context (Should be httpd_t)"
    ps -eZ | grep "$APACHE_SERVICE" | head -n 5 # Show sample
    if ! ps -eZ | grep "$APACHE_SERVICE" | grep -q ':httpd_t:'; then log_warn "Apache processes not running in httpd_t context."; fi

    log_info "CIS 11.3: Checking if httpd_t type is permissive"
    if command -v semanage > /dev/null; then
        if semanage permissive -l | grep -q 'httpd_t'; then log_warn "httpd_t is in permissive mode. Run 'semanage permissive -d httpd_t'."; fi
    else
        log_warn "semanage command not found. Cannot check permissive types."
    fi

    log_info "CIS 11.4: Check Necessary SELinux Booleans (Manual)"
    log_warn "Review SELinux booleans needed for Apache functionality (e.g., httpd_can_network_connect, httpd_enable_cgi) using 'getsebool -a | grep httpd'. Enable only required booleans with 'setsebool -P boolean_name on'."
else
    log_info "SELinux checks skipped (Not RHEL or sestatus not found)."
fi

# --- Section 12: AppArmor (Level 2 - Debian specific, Check only/Manual) ---
log_info "CIS Section 12: Enable AppArmor (Level 2 - Debian/Ubuntu specific)"
if [[ "$DISTRO" == "debian" ]] && command -v aa-status > /dev/null; then
     log_info "CIS 12.1: Checking AppArmor status"
     aa-status --enabled && log_info "AppArmor framework is enabled." || log_warn "AppArmor framework is NOT enabled."

     log_info "CIS 12.2: Check Apache AppArmor Profile Configured Properly (Manual)"
     log_warn "Review AppArmor profile for apache2 (e.g., /etc/apparmor.d/usr.sbin.apache2) for least privilege."

     log_info "CIS 12.3: Checking Apache AppArmor profile mode"
     aa-status | grep apache2
     if ! aa-status | grep -q '/usr/sbin/apache2 (.*) enforce'; then log_warn "Apache AppArmor profile is not in enforce mode. Use 'aa-enforce /usr/sbin/apache2'."; fi
else
     log_info "AppArmor checks skipped (Not Debian/Ubuntu or aa-status not found)."
fi


# --- Completion ---
log_info "----------------------------------------------------------------------"
log_info "CIS Benchmark Hardening Script completed."
log_info "Backups of modified files are in: $BACKUP_DIR"
log_warn "Review all changes made, especially WARN and ERROR messages."
log_warn "Test your Apache configuration using 'apachectl configtest' (Debian/Ubuntu) or 'httpd -t' (RHEL)."
log_warn "Restart Apache for changes to take effect: 'systemctl restart $APACHE_SERVICE'"
log_warn "Thoroughly test your website/application functionality after restarting."
log_info "----------------------------------------------------------------------"

exit 0
