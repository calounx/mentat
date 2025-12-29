#!/bin/bash
#===============================================================================
# Common Functions for Deployment Scripts
#
# ARCHITECTURE:
# This library provides deployment-specific functions and sources shared
# utilities from scripts/lib via shared.sh. This design:
#   - Eliminates code duplication between deploy/ and scripts/
#   - Provides fallbacks when scripts/lib is unavailable
#   - Maintains a single source of truth for common functions
#
# Deployment-specific functions in this file:
#   - Firewall configuration (setup_firewall_*)
#   - Systemd service management (create_systemd_service, enable_and_start)
#   - GitHub release downloads with checksum verification
#   - Pre-flight validation and placeholder detection
#   - Version management for installations
#
# Shared utilities (from shared.sh):
#   - Logging (log_info, log_warn, log_error, etc.)
#   - Architecture detection (get_architecture)
#   - Service management (wait_for_service, check_port_available)
#   - Version comparison (version_compare)
#===============================================================================

# Guard against multiple sourcing
[[ -n "${DEPLOY_COMMON_LOADED:-}" ]] && return 0
DEPLOY_COMMON_LOADED=1

# Determine library directory
DEPLOY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared library (provides common utilities with fallbacks)
if [[ -f "$DEPLOY_LIB_DIR/shared.sh" ]]; then
    source "$DEPLOY_LIB_DIR/shared.sh"
fi

#===============================================================================
# COLORS AND LOGGING (fallbacks if shared.sh not loaded)
#===============================================================================

# Detect if terminal supports colors
supports_colors() {
    # Check if stdout is a terminal and supports colors
    if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
        local colors
        colors=$(tput colors 2>/dev/null || echo 0)
        [[ $colors -ge 8 ]]
    else
        return 1
    fi
}

# Only define colors if not already set (prevents readonly variable conflicts)
if [[ -z "${RED:-}" ]]; then
    if supports_colors; then
        RED='\033[0;31m'
    else
        RED=''
    fi
fi
if [[ -z "${GREEN:-}" ]]; then
    if supports_colors; then
        GREEN='\033[0;32m'
    else
        GREEN=''
    fi
fi
if [[ -z "${YELLOW:-}" ]]; then
    if supports_colors; then
        YELLOW='\033[1;33m'
    else
        YELLOW=''
    fi
fi
if [[ -z "${BLUE:-}" ]]; then
    if supports_colors; then
        BLUE='\033[0;34m'
    else
        BLUE=''
    fi
fi
if [[ -z "${CYAN:-}" ]]; then
    if supports_colors; then
        CYAN='\033[0;36m'
    else
        CYAN=''
    fi
fi
if [[ -z "${NC:-}" ]]; then
    if supports_colors; then
        NC='\033[0m'
    else
        NC=''
    fi
fi

# Logging functions (fallbacks if not provided by shared.sh)
if ! declare -f log_info >/dev/null 2>&1; then
    log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
    log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
    log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
    log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
fi

#===============================================================================
# DEPLOY-SPECIFIC: Banner
#===============================================================================

print_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
  ___  _                              _     _ _ _ _
 / _ \| |__  ___  ___ _ ____   ____ _| |__ (_) (_) |_ _   _
| | | | '_ \/ __|/ _ \ '__\ \ / / _` | '_ \| | | | __| | | |
| |_| | |_) \__ \  __/ |   \ V / (_| | |_) | | | | |_| |_| |
 \___/|_.__/|___/\___|_|    \_/ \__,_|_.__/|_|_|_|\__|\__, |
                                                      |___/
EOF
    echo -e "${NC}"
}

#===============================================================================
# SHARED UTILITIES (fallbacks if shared.sh not loaded)
#===============================================================================

# Architecture detection (fallback)
if ! declare -f get_architecture >/dev/null 2>&1; then
    get_architecture() {
        local arch
        arch=$(uname -m)
        case $arch in
            x86_64)  echo "amd64" ;;
            aarch64) echo "arm64" ;;
            armv7l)  echo "armv7" ;;
            *)       echo "$arch" ;;
        esac
    }
fi

# Legacy function - use ensure_system_user for idempotent version
create_system_user() {
    local user="$1"
    local group="${2:-$user}"

    if ! getent group "$group" >/dev/null 2>&1; then
        groupadd --system "$group"
    fi

    if ! id "$user" >/dev/null 2>&1; then
        useradd --system --no-create-home --shell /usr/sbin/nologin -g "$group" "$user"
    fi
}

# Service wait (fallback)
if ! declare -f wait_for_service >/dev/null 2>&1; then
    wait_for_service() {
        local service="$1"
        local max_wait="${2:-30}"
        local count=0

        while ! systemctl is-active --quiet "$service"; do
            sleep 1
            count=$((count + 1))
            if [[ $count -ge $max_wait ]]; then
                return 1
            fi
        done
        return 0
    }
fi

# Port check (fallback)
if ! declare -f check_port_available >/dev/null 2>&1; then
    check_port_available() {
        local port="$1"
        if ss -tlnp | grep -q ":${port} "; then
            return 1
        fi
        return 0
    }
fi

#===============================================================================
# Download Functions
#===============================================================================

# Download a file with optional checksum verification
# Usage: download_file "url" "dest" [max_time] [expected_checksum] [checksum_algo]
# Returns: 0 on success, 1 on failure
download_file() {
    local url="$1"
    local dest="$2"
    local max_time="${3:-300}"
    local expected_checksum="${4:-}"
    local checksum_algo="${5:-sha256}"

    # Security: Require HTTPS for non-localhost URLs
    if [[ ! "$url" =~ ^https:// ]] && [[ ! "$url" =~ ^http://localhost ]] && [[ ! "$url" =~ ^http://127\. ]]; then
        log_error "Security: Only HTTPS URLs are allowed (got: $url)"
        return 1
    fi

    if ! curl -fsSL --max-time "$max_time" -o "$dest" "$url"; then
        log_error "Failed to download: $url"
        return 1
    fi

    # Verify checksum if provided
    if [[ -n "$expected_checksum" ]]; then
        if ! verify_checksum "$dest" "$expected_checksum" "$checksum_algo"; then
            log_error "Checksum verification failed for: $dest"
            rm -f "$dest"
            return 1
        fi
        log_info "Checksum verified: $dest"
    fi

    return 0
}

# Verify file checksum
# Usage: verify_checksum "file" "expected_checksum" [algo]
# Returns: 0 if matches, 1 if not
verify_checksum() {
    local file="$1"
    local expected="$2"
    local algo="${3:-sha256}"

    if [[ ! -f "$file" ]]; then
        log_error "File not found for checksum: $file"
        return 1
    fi

    local actual=""
    case "$algo" in
        sha256)
            actual=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
            ;;
        sha512)
            actual=$(sha512sum "$file" 2>/dev/null | awk '{print $1}')
            ;;
        md5)
            actual=$(md5sum "$file" 2>/dev/null | awk '{print $1}')
            ;;
        *)
            log_error "Unsupported checksum algorithm: $algo"
            return 1
            ;;
    esac

    if [[ -z "$actual" ]]; then
        log_error "Failed to compute checksum for: $file"
        return 1
    fi

    # Case-insensitive comparison
    if [[ "${actual,,}" != "${expected,,}" ]]; then
        log_error "Checksum mismatch for $file"
        log_error "  Expected: $expected"
        log_error "  Actual:   $actual"
        return 1
    fi

    return 0
}

# Download and verify using checksums file from GitHub release
# Usage: download_and_verify_github "repo" "version" "asset" "dest" [checksums_file]
# Returns: 0 on success, 1 on failure
download_and_verify_github() {
    local repo="$1"
    local version="$2"
    local asset="$3"
    local dest="$4"
    local checksums_file="${5:-sha256sums.txt}"

    local base_url="https://github.com/${repo}/releases/download/v${version}"
    local asset_url="${base_url}/${asset}"
    local checksums_url="${base_url}/${checksums_file}"

    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf '$temp_dir'" RETURN

    local checksums_path="${temp_dir}/checksums.txt"

    # Download checksums file first
    log_info "Downloading checksums from: $checksums_url"
    if curl -fsSL --max-time 30 -o "$checksums_path" "$checksums_url" 2>/dev/null; then
        # Extract expected checksum for our asset
        local expected_checksum
        expected_checksum=$(grep -E "(^| )${asset}$" "$checksums_path" 2>/dev/null | awk '{print $1}' | head -1)

        if [[ -n "$expected_checksum" ]]; then
            log_info "Found checksum for ${asset}: ${expected_checksum:0:16}..."
            download_file "$asset_url" "$dest" 300 "$expected_checksum" "sha256"
            return $?
        else
            log_warn "No checksum found for $asset in checksums file"
        fi
    else
        log_warn "Checksums file not available: $checksums_url"
    fi

    # Fallback: download without checksum verification (with warning)
    log_warn "SECURITY WARNING: Downloading without checksum verification"
    download_file "$asset_url" "$dest" 300
}

download_github_release() {
    local repo="$1"
    local version="$2"
    local asset_pattern="$3"
    local dest="$4"

    # Try to download with checksum verification
    download_and_verify_github "$repo" "$version" "$asset_pattern" "$dest"
}

get_latest_github_release() {
    local repo="$1"

    curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" | \
        jq -r '.tag_name' | sed 's/^v//'
}

#===============================================================================
# Firewall Functions
#===============================================================================

setup_firewall_observability() {
    log_step "Configuring firewall for Observability VPS..."

    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing

    # SSH
    ufw allow 22/tcp comment 'SSH'

    # HTTP/HTTPS for Grafana
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'

    # Prometheus (internal, but allow for federation if needed)
    # ufw allow 9090/tcp comment 'Prometheus'

    # Loki push endpoint (from monitored hosts)
    ufw allow 3100/tcp comment 'Loki'

    # Tempo OTLP (from monitored hosts)
    ufw allow 4317/tcp comment 'OTLP gRPC'
    ufw allow 4318/tcp comment 'OTLP HTTP'

    ufw --force enable
    log_success "Firewall configured"
}

setup_firewall_monitored() {
    local observability_ip="$1"

    log_step "Configuring firewall for monitored host..."

    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing

    # SSH
    ufw allow 22/tcp comment 'SSH'

    # Allow metrics scraping from observability VPS only
    ufw allow from "$observability_ip" to any port 9100 proto tcp comment 'node_exporter'
    ufw allow from "$observability_ip" to any port 9113 proto tcp comment 'nginx_exporter'
    ufw allow from "$observability_ip" to any port 9104 proto tcp comment 'mysqld_exporter'
    ufw allow from "$observability_ip" to any port 9253 proto tcp comment 'phpfpm_exporter'
    ufw allow from "$observability_ip" to any port 9191 proto tcp comment 'fail2ban_exporter'

    ufw --force enable
    log_success "Firewall configured (metrics only from $observability_ip)"
}

#===============================================================================
# Service Functions
#===============================================================================

create_systemd_service() {
    local name="$1"
    local exec_start="$2"
    local user="${3:-root}"
    local description="${4:-$name service}"

    cat > "/etc/systemd/system/${name}.service" << EOF
[Unit]
Description=$description
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$user
ExecStart=$exec_start
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
}

enable_and_start() {
    local service="$1"

    systemctl enable "$service"
    systemctl start "$service"

    if wait_for_service "$service" 10; then
        log_success "$service started"
    else
        log_error "$service failed to start"
        journalctl -u "$service" --no-pager -n 20
        return 1
    fi
}

#===============================================================================
# Configuration Functions
#===============================================================================

backup_config() {
    local file="$1"
    if [[ -f "$file" ]]; then
        cp "$file" "${file}.backup.$(date +%Y%m%d%H%M%S)"
    fi
}

generate_password() {
    openssl rand -base64 16 2>/dev/null || head -c 16 /dev/urandom | base64
}

#===============================================================================
# Placeholder Detection & Pre-flight Validation
#===============================================================================

# SECURITY: Check if a value appears to be a placeholder that needs changing
# Usage: is_placeholder "value"
# Returns: 0 if it's a placeholder, 1 if it appears to be a real value
is_placeholder() {
    local value="$1"

    local -a PLACEHOLDER_PATTERNS=(
        "CHANGE_ME"
        "YOUR_"
        "EXAMPLE"
        "PLACEHOLDER"
        "REPLACE_"
        "TODO"
        "FIXME"
        "XXX"
        "_IP$"
    )

    for pattern in "${PLACEHOLDER_PATTERNS[@]}"; do
        if [[ "$value" =~ $pattern ]]; then
            return 0
        fi
    done

    return 1
}

# SECURITY: Validate global.yaml has no placeholder values for critical fields
# Usage: validate_config_no_placeholders "config_file"
# Returns: 0 if all good, 1 if placeholders found
validate_config_no_placeholders() {
    local config_file="${1:-}"
    local errors=()

    if [[ -z "$config_file" ]] || [[ ! -f "$config_file" ]]; then
        log_warn "Config file not found: $config_file"
        return 0  # Skip validation if no config file
    fi

    log_step "Validating configuration for placeholder values..."

    # Critical fields that must not contain placeholders
    local -a critical_fields=(
        "network.observability_vps_ip:Observability VPS IP"
        "smtp.password:SMTP password"
        "grafana.admin_password:Grafana admin password"
        "security.prometheus_basic_auth_password:Prometheus auth password"
        "security.loki_basic_auth_password:Loki auth password"
    )

    for field_spec in "${critical_fields[@]}"; do
        local field="${field_spec%%:*}"
        local description="${field_spec#*:}"

        # Extract value using grep/sed (works without yq)
        local value=""
        local key="${field##*.}"
        value=$(grep -E "^\s*${key}:" "$config_file" 2>/dev/null | head -1 | sed 's/.*:\s*//' | tr -d '"' | tr -d "'" || echo "")

        if [[ -n "$value" ]] && is_placeholder "$value"; then
            errors+=("$description contains placeholder: $value")
        fi
    done

    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "Configuration contains placeholder values that must be changed:"
        for err in "${errors[@]}"; do
            log_error "  - $err"
        done
        log_error ""
        log_error "Please edit config/global.yaml and replace all placeholder values"
        log_error "before running the installer."
        return 1
    fi

    log_success "Configuration validation passed"
    return 0
}

# Pre-flight check for deployment readiness
# Usage: preflight_check [config_file]
# Returns: 0 if ready, 1 if issues found
preflight_check() {
    local config_file="${1:-}"
    local errors=()

    log_step "Running pre-flight checks..."

    # Check root privileges
    if [[ $EUID -ne 0 ]]; then
        errors+=("Must run as root (use sudo)")
    fi

    # Check internet connectivity
    if ! curl -s --connect-timeout 5 https://github.com >/dev/null 2>&1; then
        errors+=("No internet connectivity (cannot reach github.com)")
    fi

    # Validate config has no placeholders (if config file provided)
    if [[ -n "$config_file" ]] && [[ -f "$config_file" ]]; then
        if ! validate_config_no_placeholders "$config_file"; then
            errors+=("Configuration contains placeholder values")
        fi
    fi

    # Check disk space (minimum 5GB free)
    local free_space
    free_space=$(df / --output=avail -B1G 2>/dev/null | tail -1 | tr -d ' ' || echo "0")
    if [[ "$free_space" -lt 5 ]]; then
        errors+=("Insufficient disk space: ${free_space}GB free, need at least 5GB")
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "Pre-flight checks failed:"
        for err in "${errors[@]}"; do
            log_error "  - $err"
        done
        return 1
    fi

    log_success "Pre-flight checks passed"
    return 0
}

#===============================================================================
# Version Management
#===============================================================================

# Get version from versions.yaml or use fallback
# Usage: get_component_version "component_name" "fallback_version"
# Returns: Version string
get_component_version() {
    local component="$1"
    local fallback="${2:-}"
    local versions_file="${STACK_DIR:-}/config/versions.yaml"

    # Check for environment override first
    local env_var="VERSION_OVERRIDE_${component^^}"
    env_var="${env_var//-/_}"
    if [[ -n "${!env_var:-}" ]]; then
        echo "${!env_var}"
        return 0
    fi

    # Try to read from versions.yaml
    if [[ -f "$versions_file" ]]; then
        local version
        version=$(grep -A5 "^  ${component}:" "$versions_file" 2>/dev/null | \
            grep "fallback_version:" | head -1 | \
            sed 's/.*fallback_version:\s*//' | tr -d '"' | tr -d "'" || echo "")
        if [[ -n "$version" ]]; then
            echo "$version"
            return 0
        fi
    fi

    # Use fallback
    echo "$fallback"
}

#===============================================================================
# Idempotency Helpers
#===============================================================================

# Check if a system user exists
# Usage: user_exists "username"
# Returns: 0 if exists, 1 if not
user_exists() {
    id "$1" >/dev/null 2>&1
}

# Check if a service exists
# Usage: service_exists "service_name"
# Returns: 0 if exists, 1 if not
service_exists() {
    systemctl list-unit-files "${1}.service" >/dev/null 2>&1
}

# Check if a binary is installed at expected location
# Usage: binary_installed "binary_path" [expected_version]
# Returns: 0 if installed (and version matches if provided), 1 otherwise
binary_installed() {
    local binary_path="$1"
    local expected_version="${2:-}"

    if [[ ! -x "$binary_path" ]]; then
        return 1
    fi

    if [[ -n "$expected_version" ]]; then
        local installed_version
        installed_version=$("$binary_path" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
        if [[ "$installed_version" != "$expected_version" ]]; then
            return 1
        fi
    fi

    return 0
}

# Idempotent system user creation
# Usage: ensure_system_user "user" [group]
ensure_system_user() {
    local user="$1"
    local group="${2:-$user}"

    if ! getent group "$group" >/dev/null 2>&1; then
        log_info "Creating group: $group"
        groupadd --system "$group"
    else
        log_info "Group already exists: $group"
    fi

    if ! id "$user" >/dev/null 2>&1; then
        log_info "Creating user: $user"
        useradd --system --no-create-home --shell /usr/sbin/nologin -g "$group" "$user"
    else
        log_info "User already exists: $user"
    fi
}

# Idempotent directory creation with ownership
# Usage: ensure_directory "path" [owner] [mode]
ensure_directory() {
    local path="$1"
    local owner="${2:-root:root}"
    local mode="${3:-755}"

    if [[ -d "$path" ]]; then
        log_info "Directory exists: $path"
    else
        log_info "Creating directory: $path"
        mkdir -p "$path"
    fi

    chown "$owner" "$path"
    chmod "$mode" "$path"
}
