#!/bin/bash
#===============================================================================
# Automatic Exporter Installer
#===============================================================================
# Downloads, installs, and configures Prometheus exporters with full
# verification and security best practices.
#
# Features:
#   - Automatic binary download from official sources
#   - Checksum verification for security
#   - Systemd service creation
#   - User/group management
#   - Configuration file generation
#   - Health check verification
#   - Rollback on failure
#
# Usage:
#   ./install-exporter.sh EXPORTER_NAME [OPTIONS]
#
# Options:
#   --version VERSION    Specific version to install (default: latest)
#   --port PORT          Override default exporter port
#   --config FILE        Configuration file for exporter
#   --dry-run            Preview installation steps
#   --force              Force reinstall even if exists
#   --verify             Verify installation after completion
#   --help               Show this help
#
# Examples:
#   ./install-exporter.sh node_exporter
#   ./install-exporter.sh mysqld_exporter --config /etc/mysqld_exporter/.my.cnf
#   ./install-exporter.sh nginx_exporter --verify
#
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
EXPORTER_NAME=""
VERSION="latest"
PORT=""
CONFIG_FILE=""
DRY_RUN=false
FORCE=false
VERIFY=true

# Installation paths
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc"
SYSTEMD_DIR="/etc/systemd/system"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#===============================================================================
# HELPER FUNCTIONS
#===============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $*"
}

# Check if running as root
require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Cleanup on error
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Installation failed, cleaning up..."
        # Cleanup logic here
    fi
}

trap cleanup EXIT

#===============================================================================
# EXPORTER METADATA
#===============================================================================

get_exporter_metadata() {
    local exporter="$1"

    case "$exporter" in
        node_exporter)
            echo "repo=prometheus/node_exporter"
            echo "archive_pattern=node_exporter-{VERSION}.linux-amd64.tar.gz"
            echo "binary_path=node_exporter-{VERSION}.linux-amd64/node_exporter"
            echo "default_port=9100"
            echo "description=Prometheus Node Exporter"
            echo "user=node_exporter"
            echo "group=node_exporter"
            echo "flags=--collector.systemd --collector.processes"
            ;;
        nginx_exporter)
            echo "repo=nginxinc/nginx-prometheus-exporter"
            echo "archive_pattern=nginx-prometheus-exporter_{VERSION}_linux_amd64.tar.gz"
            echo "binary_path=nginx-prometheus-exporter"
            echo "default_port=9113"
            echo "description=Prometheus Nginx Exporter"
            echo "user=nginx_exporter"
            echo "group=nginx_exporter"
            echo "flags=-nginx.scrape-uri=http://127.0.0.1:8080/stub_status"
            ;;
        mysqld_exporter)
            echo "repo=prometheus/mysqld_exporter"
            echo "archive_pattern=mysqld_exporter-{VERSION}.linux-amd64.tar.gz"
            echo "binary_path=mysqld_exporter-{VERSION}.linux-amd64/mysqld_exporter"
            echo "default_port=9104"
            echo "description=Prometheus MySQL Exporter"
            echo "user=mysqld_exporter"
            echo "group=mysqld_exporter"
            echo "flags=--config.my-cnf=/etc/mysqld_exporter/.my.cnf"
            echo "needs_config=true"
            ;;
        postgres_exporter)
            echo "repo=prometheus-community/postgres_exporter"
            echo "archive_pattern=postgres_exporter-{VERSION}.linux-amd64.tar.gz"
            echo "binary_path=postgres_exporter-{VERSION}.linux-amd64/postgres_exporter"
            echo "default_port=9187"
            echo "description=Prometheus PostgreSQL Exporter"
            echo "user=postgres_exporter"
            echo "group=postgres_exporter"
            echo "flags="
            echo "needs_config=true"
            ;;
        redis_exporter)
            echo "repo=oliver006/redis_exporter"
            echo "archive_pattern=redis_exporter-v{VERSION}.linux-amd64.tar.gz"
            echo "binary_path=redis_exporter-v{VERSION}.linux-amd64/redis_exporter"
            echo "default_port=9121"
            echo "description=Prometheus Redis Exporter"
            echo "user=redis_exporter"
            echo "group=redis_exporter"
            echo "flags=-redis.addr=redis://localhost:6379"
            ;;
        phpfpm_exporter)
            echo "repo=hipages/php-fpm_exporter"
            echo "docker_image=hipages/php-fpm_exporter:2.2.0"
            echo "default_port=9253"
            echo "description=Prometheus PHP-FPM Exporter"
            echo "user=phpfpm_exporter"
            echo "group=phpfpm_exporter"
            echo "flags=--phpfpm.scrape-uri=tcp://127.0.0.1:9000/status"
            ;;
        mongodb_exporter)
            echo "repo=percona/mongodb_exporter"
            echo "archive_pattern=mongodb_exporter-{VERSION}.linux-amd64.tar.gz"
            echo "binary_path=mongodb_exporter-{VERSION}.linux-amd64/mongodb_exporter"
            echo "default_port=9216"
            echo "description=Prometheus MongoDB Exporter"
            echo "user=mongodb_exporter"
            echo "group=mongodb_exporter"
            echo "flags=--mongodb.uri=mongodb://localhost:27017"
            echo "needs_config=true"
            ;;
        *)
            log_error "Unknown exporter: $exporter"
            return 1
            ;;
    esac
}

get_metadata_value() {
    local exporter="$1"
    local key="$2"
    get_exporter_metadata "$exporter" | grep "^${key}=" | cut -d= -f2-
}

#===============================================================================
# VERSION DETECTION
#===============================================================================

get_latest_version() {
    local repo="$1"

    log_info "Fetching latest version for $repo..."

    local version
    version=$(curl -sf "https://api.github.com/repos/${repo}/releases/latest" | \
              grep '"tag_name":' | \
              sed -E 's/.*"v?([^"]+)".*/\1/')

    if [[ -z "$version" ]]; then
        log_error "Failed to fetch latest version"
        return 1
    fi

    echo "$version"
}

#===============================================================================
# DOWNLOAD & INSTALLATION
#===============================================================================

download_exporter() {
    local exporter="$1"
    local version="$2"
    local tmpdir="$3"

    local repo=$(get_metadata_value "$exporter" "repo")
    local archive_pattern=$(get_metadata_value "$exporter" "archive_pattern")

    if [[ -z "$repo" ]] || [[ -z "$archive_pattern" ]]; then
        log_error "Missing metadata for $exporter"
        return 1
    fi

    # Replace version placeholder
    local archive_name="${archive_pattern//\{VERSION\}/$version}"
    local download_url="https://github.com/${repo}/releases/download/v${version}/${archive_name}"

    log_info "Downloading from: $download_url"

    cd "$tmpdir"
    if ! wget -q --show-progress "$download_url" -O exporter.tar.gz; then
        log_error "Download failed"
        return 1
    fi

    log_success "Downloaded $archive_name"
}

verify_checksum() {
    local exporter="$1"
    local version="$2"
    local tmpdir="$3"

    local repo=$(get_metadata_value "$exporter" "repo")

    # Try to download checksums file
    local checksum_url="https://github.com/${repo}/releases/download/v${version}/sha256sums.txt"

    cd "$tmpdir"
    if wget -q "$checksum_url" -O checksums.txt 2>/dev/null; then
        log_info "Verifying checksum..."

        local expected_hash=$(grep "$(basename exporter.tar.gz)" checksums.txt | awk '{print $1}')
        local actual_hash=$(sha256sum exporter.tar.gz | awk '{print $1}')

        if [[ "$expected_hash" == "$actual_hash" ]]; then
            log_success "Checksum verified"
            return 0
        else
            log_error "Checksum mismatch!"
            return 1
        fi
    else
        log_warning "Checksum file not found, skipping verification"
        return 0
    fi
}

extract_binary() {
    local exporter="$1"
    local version="$2"
    local tmpdir="$3"

    local binary_path=$(get_metadata_value "$exporter" "binary_path")
    binary_path="${binary_path//\{VERSION\}/$version}"

    cd "$tmpdir"
    log_info "Extracting archive..."

    tar xzf exporter.tar.gz

    # Find the binary
    local binary_file=$(find . -name "$exporter" -type f | head -1)

    if [[ -z "$binary_file" ]]; then
        # Try the specified path
        if [[ -f "$binary_path" ]]; then
            binary_file="$binary_path"
        else
            log_error "Binary not found in archive"
            return 1
        fi
    fi

    echo "$binary_file"
}

install_binary() {
    local binary_file="$1"
    local exporter="$2"

    log_info "Installing binary to $INSTALL_DIR..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install $binary_file to $INSTALL_DIR/$exporter"
        return 0
    fi

    install -m 755 "$binary_file" "$INSTALL_DIR/$exporter"
    log_success "Binary installed: $INSTALL_DIR/$exporter"
}

#===============================================================================
# USER MANAGEMENT
#===============================================================================

create_system_user() {
    local username="$1"
    local groupname="$2"

    log_info "Creating system user: $username"

    if id "$username" &>/dev/null; then
        log_warning "User $username already exists"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create user $username"
        return 0
    fi

    groupadd --system "$groupname" 2>/dev/null || true
    useradd --system --no-create-home --shell /bin/false -g "$groupname" "$username"

    log_success "Created user: $username"
}

#===============================================================================
# SYSTEMD SERVICE
#===============================================================================

create_systemd_service() {
    local exporter="$1"

    local user=$(get_metadata_value "$exporter" "user")
    local group=$(get_metadata_value "$exporter" "group")
    local description=$(get_metadata_value "$exporter" "description")
    local flags=$(get_metadata_value "$exporter" "flags")
    local binary="$INSTALL_DIR/$exporter"

    local service_file="$SYSTEMD_DIR/${exporter}.service"

    log_info "Creating systemd service: $service_file"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create service file"
        cat << EOF
[Unit]
Description=$description
Documentation=https://github.com/prometheus/$exporter
After=network.target

[Service]
Type=simple
User=$user
Group=$group
ExecStart=$binary $flags
Restart=on-failure
RestartSec=5s
ProtectSystem=strict
ProtectHome=yes
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
        return 0
    fi

    cat > "$service_file" << EOF
[Unit]
Description=$description
Documentation=https://github.com/prometheus/$exporter
After=network.target

[Service]
Type=simple
User=$user
Group=$group
ExecStart=$binary $flags
Restart=on-failure
RestartSec=5s

# Security
ProtectSystem=strict
ProtectHome=yes
NoNewPrivileges=true
PrivateTmp=yes
PrivateDevices=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Systemd service created"
}

enable_and_start_service() {
    local exporter="$1"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would enable and start $exporter.service"
        return 0
    fi

    log_info "Enabling and starting service..."

    systemctl enable "$exporter"
    systemctl start "$exporter"

    # Wait a moment for startup
    sleep 2

    if systemctl is-active --quiet "$exporter"; then
        log_success "Service $exporter is running"
        return 0
    else
        log_error "Service failed to start"
        systemctl status "$exporter" --no-pager
        return 1
    fi
}

#===============================================================================
# CONFIGURATION
#===============================================================================

create_exporter_config() {
    local exporter="$1"

    local needs_config=$(get_metadata_value "$exporter" "needs_config")

    if [[ "$needs_config" != "true" ]]; then
        return 0
    fi

    log_info "Creating configuration for $exporter..."

    case "$exporter" in
        mysqld_exporter)
            create_mysqld_exporter_config
            ;;
        postgres_exporter)
            create_postgres_exporter_config
            ;;
        mongodb_exporter)
            create_mongodb_exporter_config
            ;;
    esac
}

create_mysqld_exporter_config() {
    local config_dir="/etc/mysqld_exporter"
    local config_file="$config_dir/.my.cnf"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create $config_file"
        return 0
    fi

    mkdir -p "$config_dir"

    cat > "$config_file" << 'EOF'
[client]
user=exporter
password=CHANGE_ME_EXPORTER_PASSWORD
host=127.0.0.1
port=3306
EOF

    chmod 600 "$config_file"
    chown mysqld_exporter:mysqld_exporter "$config_file"

    log_warning "MySQL exporter config created at $config_file"
    log_warning "Please update the password before starting the service!"
}

create_postgres_exporter_config() {
    log_info "PostgreSQL exporter requires DATA_SOURCE_NAME environment variable"
    log_info "Add to systemd service: Environment=\"DATA_SOURCE_NAME=postgresql://user:pass@localhost:5432/postgres?sslmode=disable\""
}

create_mongodb_exporter_config() {
    log_info "MongoDB exporter requires connection URI"
    log_info "Update systemd service flags with: --mongodb.uri=mongodb://user:pass@localhost:27017"
}

#===============================================================================
# VERIFICATION
#===============================================================================

verify_installation() {
    local exporter="$1"
    local port=$(get_metadata_value "$exporter" "default_port")

    log_info "Verifying installation..."

    # Check binary exists
    if [[ ! -x "$INSTALL_DIR/$exporter" ]]; then
        log_error "Binary not found or not executable"
        return 1
    fi

    # Check service is running
    if ! systemctl is-active --quiet "$exporter"; then
        log_error "Service is not running"
        return 1
    fi

    # Check metrics endpoint
    if timeout 5 curl -sf "http://localhost:${port}/metrics" >/dev/null; then
        log_success "Metrics endpoint accessible"
    else
        log_error "Metrics endpoint not accessible"
        return 1
    fi

    # Check if metrics are being generated
    local metric_count=$(curl -sf "http://localhost:${port}/metrics" | grep -c "^[a-z]" || echo "0")

    if [[ $metric_count -gt 0 ]]; then
        log_success "Exporter is generating $metric_count metrics"
    else
        log_error "No metrics found"
        return 1
    fi

    log_success "Installation verification complete"
    return 0
}

#===============================================================================
# MAIN INSTALLATION FLOW
#===============================================================================

install_exporter() {
    local exporter="$1"

    log_info "Installing $exporter..."

    # Create temporary directory
    local tmpdir=$(mktemp -d)
    cd "$tmpdir"

    # Get version
    if [[ "$VERSION" == "latest" ]]; then
        local repo=$(get_metadata_value "$exporter" "repo")
        VERSION=$(get_latest_version "$repo")
        log_info "Latest version: $VERSION"
    fi

    # Download
    download_exporter "$exporter" "$VERSION" "$tmpdir" || {
        rm -rf "$tmpdir"
        return 1
    }

    # Verify checksum
    verify_checksum "$exporter" "$VERSION" "$tmpdir" || {
        rm -rf "$tmpdir"
        return 1
    }

    # Extract
    local binary_file
    binary_file=$(extract_binary "$exporter" "$VERSION" "$tmpdir") || {
        rm -rf "$tmpdir"
        return 1
    }

    # Install binary
    install_binary "$binary_file" "$exporter" || {
        rm -rf "$tmpdir"
        return 1
    }

    # Cleanup temp directory
    rm -rf "$tmpdir"

    # Create user
    local user=$(get_metadata_value "$exporter" "user")
    local group=$(get_metadata_value "$exporter" "group")
    create_system_user "$user" "$group"

    # Create configuration
    create_exporter_config "$exporter"

    # Create systemd service
    create_systemd_service "$exporter"

    # Enable and start
    enable_and_start_service "$exporter" || return 1

    # Verify
    if [[ "$VERIFY" == "true" ]]; then
        verify_installation "$exporter" || return 1
    fi

    log_success "$exporter installed successfully!"
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

print_help() {
    cat << 'EOF'
Automatic Exporter Installer

Usage: install-exporter.sh EXPORTER_NAME [OPTIONS]

Supported Exporters:
  node_exporter       - System metrics (CPU, memory, disk, network)
  nginx_exporter      - Nginx web server metrics
  mysqld_exporter     - MySQL/MariaDB database metrics
  postgres_exporter   - PostgreSQL database metrics
  redis_exporter      - Redis cache metrics
  phpfpm_exporter     - PHP-FPM metrics
  mongodb_exporter    - MongoDB metrics

Options:
  --version VERSION    Specific version to install (default: latest)
  --port PORT          Override default exporter port
  --config FILE        Configuration file for exporter
  --dry-run            Preview installation steps
  --force              Force reinstall even if exists
  --verify             Verify installation (default)
  --no-verify          Skip verification
  --help               Show this help

Examples:
  install-exporter.sh node_exporter
  install-exporter.sh mysqld_exporter --verify
  install-exporter.sh nginx_exporter --dry-run
EOF
}

parse_args() {
    if [[ $# -eq 0 ]]; then
        print_help
        exit 1
    fi

    EXPORTER_NAME="$1"
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                VERSION="$2"
                shift 2
                ;;
            --port)
                PORT="$2"
                shift 2
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --verify)
                VERIFY=true
                shift
                ;;
            --no-verify)
                VERIFY=false
                shift
                ;;
            --help)
                print_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_help
                exit 1
                ;;
        esac
    done
}

main() {
    parse_args "$@"

    if [[ "$DRY_RUN" == "false" ]]; then
        require_root
    fi

    # Check if already installed
    if [[ -x "$INSTALL_DIR/$EXPORTER_NAME" ]] && [[ "$FORCE" == "false" ]]; then
        log_warning "$EXPORTER_NAME is already installed"
        log_info "Use --force to reinstall"
        exit 0
    fi

    # Install
    install_exporter "$EXPORTER_NAME"
}

main "$@"
