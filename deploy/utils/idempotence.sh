#!/usr/bin/env bash
# Idempotence Helper Functions Library
# Provides reusable patterns for safe, re-runnable deployment operations
# Source this file in deployment scripts: source "${SCRIPT_DIR}/../utils/idempotence.sh"

# ============================================================================
# USER MANAGEMENT
# ============================================================================

# Create user only if it doesn't exist
# Usage: ensure_user_exists USERNAME [HOME_DIR] [SHELL]
ensure_user_exists() {
    local username="$1"
    local home_dir="${2:-}"
    local shell="${3:-/bin/bash}"

    if id "$username" &>/dev/null; then
        return 0  # User already exists
    fi

    if [[ -n "$home_dir" ]]; then
        sudo useradd -m -d "$home_dir" -s "$shell" "$username"
    else
        sudo useradd -m -s "$shell" "$username"
    fi
}

# Create system user only if it doesn't exist
# Usage: ensure_system_user_exists USERNAME
ensure_system_user_exists() {
    local username="$1"

    if id "$username" &>/dev/null; then
        return 0  # User already exists
    fi

    sudo useradd --system --no-create-home --shell /usr/sbin/nologin "$username"
}

# Add user to group (idempotent)
# Usage: ensure_user_in_group USERNAME GROUP
ensure_user_in_group() {
    local username="$1"
    local group="$2"

    if groups "$username" | grep -q "\b$group\b"; then
        return 0  # User already in group
    fi

    sudo usermod -aG "$group" "$username"
}

# ============================================================================
# PACKAGE MANAGEMENT
# ============================================================================

# Check if package is installed
# Usage: is_package_installed PACKAGE_NAME
is_package_installed() {
    local package="$1"
    dpkg -l "$package" 2>/dev/null | grep -q "^ii"
}

# Install package only if not already installed
# Usage: ensure_package_installed PACKAGE_NAME
ensure_package_installed() {
    local package="$1"

    if is_package_installed "$package"; then
        return 0  # Package already installed
    fi

    sudo apt-get install -y "$package"
}

# Install multiple packages (idempotent)
# Usage: ensure_packages_installed pkg1 pkg2 pkg3
ensure_packages_installed() {
    local packages_to_install=()

    for package in "$@"; do
        if ! is_package_installed "$package"; then
            packages_to_install+=("$package")
        fi
    done

    if [[ ${#packages_to_install[@]} -gt 0 ]]; then
        sudo apt-get install -y "${packages_to_install[@]}"
    fi
}

# ============================================================================
# SERVICE MANAGEMENT
# ============================================================================

# Enable service only if not already enabled
# Usage: ensure_service_enabled SERVICE_NAME
ensure_service_enabled() {
    local service="$1"

    if systemctl is-enabled --quiet "$service" 2>/dev/null; then
        return 0  # Service already enabled
    fi

    sudo systemctl enable "$service"
}

# Start service only if not already running
# Usage: ensure_service_started SERVICE_NAME
ensure_service_started() {
    local service="$1"

    if systemctl is-active --quiet "$service" 2>/dev/null; then
        return 0  # Service already running
    fi

    sudo systemctl start "$service"
}

# Ensure service is enabled and started
# Usage: ensure_service_running SERVICE_NAME
ensure_service_running() {
    local service="$1"

    ensure_service_enabled "$service"
    ensure_service_started "$service"
}

# Restart service (always safe)
# Usage: restart_service SERVICE_NAME
restart_service() {
    local service="$1"
    sudo systemctl restart "$service"
}

# Reload service configuration (always safe)
# Usage: reload_service SERVICE_NAME
reload_service() {
    local service="$1"
    sudo systemctl reload "$service" 2>/dev/null || sudo systemctl restart "$service"
}

# Reload systemd daemon (always safe, always idempotent)
# Usage: reload_systemd_daemon
reload_systemd_daemon() {
    sudo systemctl daemon-reload
}

# ============================================================================
# FILE AND DIRECTORY MANAGEMENT
# ============================================================================

# Create directory only if it doesn't exist (always use mkdir -p)
# Usage: ensure_directory_exists DIRECTORY [OWNER:GROUP] [PERMISSIONS]
ensure_directory_exists() {
    local directory="$1"
    local owner="${2:-}"
    local permissions="${3:-}"

    if [[ ! -d "$directory" ]]; then
        sudo mkdir -p "$directory"
    fi

    if [[ -n "$owner" ]]; then
        sudo chown "$owner" "$directory"
    fi

    if [[ -n "$permissions" ]]; then
        sudo chmod "$permissions" "$directory"
    fi
}

# Create file only if it doesn't exist
# Usage: ensure_file_exists FILE_PATH [OWNER:GROUP] [PERMISSIONS]
ensure_file_exists() {
    local file="$1"
    local owner="${2:-}"
    local permissions="${3:-}"

    if [[ ! -f "$file" ]]; then
        sudo touch "$file"
    fi

    if [[ -n "$owner" ]]; then
        sudo chown "$owner" "$file"
    fi

    if [[ -n "$permissions" ]]; then
        sudo chmod "$permissions" "$file"
    fi
}

# Create symbolic link (idempotent)
# Usage: ensure_symlink_exists TARGET LINK_NAME
ensure_symlink_exists() {
    local target="$1"
    local link_name="$2"

    if [[ -L "$link_name" ]]; then
        local current_target=$(readlink -f "$link_name")
        local desired_target=$(readlink -f "$target")

        if [[ "$current_target" == "$desired_target" ]]; then
            return 0  # Link already points to correct target
        fi

        # Remove incorrect link
        sudo rm -f "$link_name"
    fi

    sudo ln -sf "$target" "$link_name"
}

# Backup file before modification
# Usage: backup_file FILE_PATH
backup_file() {
    local file="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${file}.backup.${timestamp}"

    if [[ -f "$file" ]]; then
        sudo cp "$file" "$backup_path"
        echo "$backup_path"
    fi
}

# ============================================================================
# CONFIGURATION FILE MANAGEMENT
# ============================================================================

# Add line to file only if it doesn't exist
# Usage: ensure_line_in_file FILE_PATH LINE_CONTENT
ensure_line_in_file() {
    local file="$1"
    local line="$2"

    if [[ ! -f "$file" ]]; then
        echo "$line" | sudo tee "$file" > /dev/null
        return 0
    fi

    if grep -qF "$line" "$file"; then
        return 0  # Line already exists
    fi

    echo "$line" | sudo tee -a "$file" > /dev/null
}

# Replace or add configuration value (idempotent)
# Usage: ensure_config_value FILE_PATH KEY VALUE [SEPARATOR]
ensure_config_value() {
    local file="$1"
    local key="$2"
    local value="$3"
    local separator="${4:-=}"

    local line="${key}${separator}${value}"

    if [[ ! -f "$file" ]]; then
        echo "$line" | sudo tee "$file" > /dev/null
        return 0
    fi

    # Check if key exists
    if grep -q "^${key}${separator}" "$file"; then
        # Update existing value
        sudo sed -i "s|^${key}${separator}.*|${line}|" "$file"
    else
        # Add new value
        echo "$line" | sudo tee -a "$file" > /dev/null
    fi
}

# Uncomment line in configuration file (idempotent)
# Usage: ensure_line_uncommented FILE_PATH PATTERN
ensure_line_uncommented() {
    local file="$1"
    local pattern="$2"

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    # Remove leading # and optional space from matching lines
    sudo sed -i "s/^#\s*\(${pattern}\)/\1/" "$file"
}

# Comment line in configuration file (idempotent)
# Usage: ensure_line_commented FILE_PATH PATTERN
ensure_line_commented() {
    local file="$1"
    local pattern="$2"

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    # Add # to uncommented matching lines
    sudo sed -i "s/^\(${pattern}\)/#\1/" "$file"
}

# ============================================================================
# DOWNLOAD AND EXTRACTION
# ============================================================================

# Download file only if it doesn't exist
# Usage: ensure_file_downloaded URL DESTINATION
ensure_file_downloaded() {
    local url="$1"
    local destination="$2"

    if [[ -f "$destination" ]]; then
        return 0  # File already downloaded
    fi

    wget -q "$url" -O "$destination"
}

# Download and extract tarball only if not already extracted
# Usage: ensure_tarball_extracted URL EXTRACT_DIR EXPECTED_FILE
ensure_tarball_extracted() {
    local url="$1"
    local extract_dir="$2"
    local expected_file="$3"

    if [[ -f "$expected_file" ]]; then
        return 0  # Already extracted
    fi

    local temp_file=$(mktemp)
    wget -q "$url" -O "$temp_file"
    tar xzf "$temp_file" -C "$extract_dir"
    rm -f "$temp_file"
}

# ============================================================================
# APT REPOSITORY MANAGEMENT
# ============================================================================

# Add APT repository key (idempotent)
# Usage: ensure_apt_key_exists KEY_URL KEY_PATH
ensure_apt_key_exists() {
    local key_url="$1"
    local key_path="$2"

    if [[ -f "$key_path" ]]; then
        return 0  # Key already exists
    fi

    sudo mkdir -p "$(dirname "$key_path")"
    wget -qO - "$key_url" | sudo gpg --dearmor -o "$key_path"
}

# Add APT repository source (idempotent)
# Usage: ensure_apt_source_exists SOURCE_LINE SOURCE_FILE
ensure_apt_source_exists() {
    local source_line="$1"
    local source_file="$2"

    if [[ -f "$source_file" ]] && grep -qF "$source_line" "$source_file"; then
        return 0  # Source already exists
    fi

    echo "$source_line" | sudo tee "$source_file" > /dev/null
}

# ============================================================================
# DATABASE OPERATIONS
# ============================================================================

# Create PostgreSQL user only if it doesn't exist
# Usage: ensure_postgres_user_exists USERNAME PASSWORD
ensure_postgres_user_exists() {
    local username="$1"
    local password="$2"

    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$username'" | grep -q 1; then
        return 0  # User already exists
    fi

    sudo -u postgres psql -c "CREATE USER $username WITH ENCRYPTED PASSWORD '$password';"
}

# Create PostgreSQL database only if it doesn't exist
# Usage: ensure_postgres_database_exists DATABASE_NAME OWNER
ensure_postgres_database_exists() {
    local database="$1"
    local owner="$2"

    if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$database"; then
        return 0  # Database already exists
    fi

    sudo -u postgres psql -c "CREATE DATABASE $database OWNER $owner;"
}

# ============================================================================
# BINARY INSTALLATION
# ============================================================================

# Install binary to /usr/local/bin only if not present or outdated
# Usage: ensure_binary_installed SOURCE_PATH BINARY_NAME
ensure_binary_installed() {
    local source_path="$1"
    local binary_name="$2"
    local dest_path="/usr/local/bin/${binary_name}"

    # Check if binary exists and is identical
    if [[ -f "$dest_path" ]] && cmp -s "$source_path" "$dest_path"; then
        return 0  # Binary already installed and identical
    fi

    sudo cp "$source_path" "$dest_path"
    sudo chmod +x "$dest_path"
}

# ============================================================================
# FIREWALL OPERATIONS
# ============================================================================

# Add UFW rule only if it doesn't exist
# Usage: ensure_ufw_rule_exists RULE_SPEC
ensure_ufw_rule_exists() {
    local rule_spec="$1"

    if sudo ufw status | grep -q "$rule_spec"; then
        return 0  # Rule already exists
    fi

    sudo ufw "$rule_spec"
}

# ============================================================================
# SYSCTL CONFIGURATION
# ============================================================================

# Set sysctl parameter (idempotent)
# Usage: ensure_sysctl_value PARAMETER VALUE [CONFIG_FILE]
ensure_sysctl_value() {
    local parameter="$1"
    local value="$2"
    local config_file="${3:-/etc/sysctl.d/99-custom.conf}"

    local setting="${parameter} = ${value}"

    # Create config file if it doesn't exist
    if [[ ! -f "$config_file" ]]; then
        sudo touch "$config_file"
    fi

    # Check if parameter exists in file
    if grep -q "^${parameter}" "$config_file"; then
        # Update existing value
        sudo sed -i "s|^${parameter}.*|${setting}|" "$config_file"
    else
        # Add new value
        echo "$setting" | sudo tee -a "$config_file" > /dev/null
    fi

    # Apply the setting
    sudo sysctl -w "${parameter}=${value}" 2>/dev/null || true
}

# ============================================================================
# ERROR HANDLING AND ROLLBACK
# ============================================================================

# Create cleanup trap for script
# Usage: setup_cleanup_trap
setup_cleanup_trap() {
    trap cleanup_on_error EXIT ERR
}

# Default cleanup function (override in your script)
cleanup_on_error() {
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo "Error detected (exit code: $exit_code). Cleaning up..."
        # Add custom cleanup logic here
    fi
}

# ============================================================================
# VALIDATION HELPERS
# ============================================================================

# Check if command exists
# Usage: command_exists COMMAND_NAME
command_exists() {
    command -v "$1" &>/dev/null
}

# Check if port is available
# Usage: port_available PORT_NUMBER
port_available() {
    local port="$1"
    ! sudo netstat -tuln 2>/dev/null | grep -q ":${port} " && \
    ! sudo ss -tuln 2>/dev/null | grep -q ":${port} "
}

# Check if service is running
# Usage: service_running SERVICE_NAME
service_running() {
    local service="$1"
    systemctl is-active --quiet "$service" 2>/dev/null
}

# Check if user has sudo privileges
# Usage: has_sudo
has_sudo() {
    sudo -n true 2>/dev/null
}

# ============================================================================
# NETWORK OPERATIONS
# ============================================================================

# Wait for network connectivity
# Usage: wait_for_network [TIMEOUT_SECONDS]
wait_for_network() {
    local timeout="${1:-30}"
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if ping -c 1 8.8.8.8 &>/dev/null; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    return 1
}

# Wait for host to be reachable
# Usage: wait_for_host HOSTNAME [PORT] [TIMEOUT_SECONDS]
wait_for_host() {
    local hostname="$1"
    local port="${2:-80}"
    local timeout="${3:-30}"
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if nc -z -w 2 "$hostname" "$port" 2>/dev/null; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    return 1
}

# ============================================================================
# VARIABLE VALIDATION
# ============================================================================

# Require variable to be set
# Usage: require_variable VAR_NAME
require_variable() {
    local var_name="$1"
    local var_value="${!var_name:-}"

    if [[ -z "$var_value" ]]; then
        echo "ERROR: Required variable $var_name is not set" >&2
        return 1
    fi
}

# Require multiple variables
# Usage: require_variables VAR1 VAR2 VAR3
require_variables() {
    local missing=()

    for var_name in "$@"; do
        local var_value="${!var_name:-}"
        if [[ -z "$var_value" ]]; then
            missing+=("$var_name")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Required variables not set: ${missing[*]}" >&2
        return 1
    fi
}

# ============================================================================
# SYSTEM INFORMATION
# ============================================================================

# Get Debian codename
# Usage: get_debian_codename
get_debian_codename() {
    lsb_release -sc 2>/dev/null || echo "unknown"
}

# Get Debian version
# Usage: get_debian_version
get_debian_version() {
    lsb_release -sr 2>/dev/null || echo "unknown"
}

# Check if running as root
# Usage: is_root
is_root() {
    [[ $EUID -eq 0 ]]
}

# ============================================================================
# LOGGING HELPERS (if utils/logging.sh is not available)
# ============================================================================

# Log idempotent operation skip
# Usage: log_skip "Operation already completed"
log_skip() {
    echo "[SKIP] $*" >&2
}

# Log idempotent operation execution
# Usage: log_exec "Executing operation"
log_exec() {
    echo "[EXEC] $*" >&2
}

# ============================================================================
# EXPORT ALL FUNCTIONS
# ============================================================================

# Export all functions so they're available in subshells
export -f ensure_user_exists
export -f ensure_system_user_exists
export -f ensure_user_in_group
export -f is_package_installed
export -f ensure_package_installed
export -f ensure_packages_installed
export -f ensure_service_enabled
export -f ensure_service_started
export -f ensure_service_running
export -f restart_service
export -f reload_service
export -f reload_systemd_daemon
export -f ensure_directory_exists
export -f ensure_file_exists
export -f ensure_symlink_exists
export -f backup_file
export -f ensure_line_in_file
export -f ensure_config_value
export -f ensure_line_uncommented
export -f ensure_line_commented
export -f ensure_file_downloaded
export -f ensure_tarball_extracted
export -f ensure_apt_key_exists
export -f ensure_apt_source_exists
export -f ensure_postgres_user_exists
export -f ensure_postgres_database_exists
export -f ensure_binary_installed
export -f ensure_ufw_rule_exists
export -f ensure_sysctl_value
export -f setup_cleanup_trap
export -f cleanup_on_error
export -f command_exists
export -f port_available
export -f service_running
export -f has_sudo
export -f wait_for_network
export -f wait_for_host
export -f require_variable
export -f require_variables
export -f get_debian_codename
export -f get_debian_version
export -f is_root
export -f log_skip
export -f log_exec
