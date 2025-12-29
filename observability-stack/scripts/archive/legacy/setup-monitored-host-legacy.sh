#!/bin/bash
#===============================================================================
# ARCHIVED/LEGACY: Monitored Host Agent Setup Script
# Installs: node_exporter, nginx-prometheus-exporter, mysqld_exporter,
#           php-fpm_exporter, fail2ban-prometheus-exporter, promtail
#
# This script is IDEMPOTENT - safe to run multiple times.
#
# WARNING: This is an archived/legacy version. Please use the latest version
#          from the main scripts directory if available.
#
# Usage:
#   ./setup-monitored-host.sh <OBSERVABILITY_VPS_IP> <LOKI_URL> <LOKI_USER> <LOKI_PASS>
#   ./setup-monitored-host.sh --uninstall [--purge]
#
# Example:
#   ./setup-monitored-host.sh 10.0.0.5 https://mentat.arewel.com loki mypassword
#===============================================================================

set -euo pipefail

# Mode flags
FORCE_MODE=false
UNINSTALL_MODE=false
PURGE_DATA=false

# Colors
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

# Versions
NODE_EXPORTER_VERSION="1.7.0"
NGINX_EXPORTER_VERSION="1.1.0"
MYSQLD_EXPORTER_VERSION="0.15.1"
PHPFPM_EXPORTER_VERSION="2.2.0"
FAIL2BAN_EXPORTER_VERSION="0.10.3"
PROMTAIL_VERSION="2.9.3"

# Script arguments (parse flags from any position)
OBSERVABILITY_IP=""
LOKI_URL=""
LOKI_USER=""
LOKI_PASS=""

for arg in "$@"; do
    case "$arg" in
        --force|-f)
            FORCE_MODE=true
            ;;
        --uninstall|--rollback)
            UNINSTALL_MODE=true
            ;;
        --purge)
            PURGE_DATA=true
            ;;
        --help|-h)
            echo "Usage: $0 <OBSERVABILITY_VPS_IP> <LOKI_URL> <LOKI_USER> <LOKI_PASS> [OPTIONS]"
            echo "       $0 --uninstall [--purge]"
            echo ""
            echo "Arguments:"
            echo "  OBSERVABILITY_VPS_IP  - IP address of the observability server"
            echo "  LOKI_URL              - URL for Loki (e.g., https://mentat.arewel.com)"
            echo "  LOKI_USER             - Loki basic auth username"
            echo "  LOKI_PASS             - Loki basic auth password"
            echo ""
            echo "Options:"
            echo "  --force, -f           - Force reinstall everything from scratch"
            echo "  --uninstall           - Remove all monitoring agents"
            echo "  --purge               - Used with --uninstall to remove configs too"
            echo "  --help, -h            - Show this help message"
            exit 0
            ;;
        *)
            # Assign positional arguments
            if [[ -z "$OBSERVABILITY_IP" ]]; then
                OBSERVABILITY_IP="$arg"
            elif [[ -z "$LOKI_URL" ]]; then
                LOKI_URL="$arg"
            elif [[ -z "$LOKI_USER" ]]; then
                LOKI_USER="$arg"
            elif [[ -z "$LOKI_PASS" ]]; then
                LOKI_PASS="$arg"
            fi
            ;;
    esac
done

#===============================================================================
# UTILITY FUNCTIONS
#===============================================================================

log_info() {
    echo "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo "${GREEN}[SUCCESS]${NC} $1"
}

log_skip() {
    echo "${GREEN}[SKIP]${NC} $1"
}

log_warn() {
    echo "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo "${RED}[ERROR]${NC} $1"
    exit 1
}

# Stop service and verify binary is not in use before replacement
# Usage: stop_and_verify_service "service_name" "binary_path"
stop_and_verify_service() {
    local service_name="$1"
    local binary_path="$2"
    local max_attempts=10
    local attempt=0

    log_info "Stopping $service_name and verifying binary can be replaced..."

    # Stop the service
    systemctl stop "$service_name" 2>/dev/null || true
    sleep 2

    # Wait for binary to be released
    while [[ $attempt -lt $max_attempts ]]; do
        if ! lsof "$binary_path" >/dev/null 2>&1; then
            log_info "Binary $binary_path is not in use, safe to replace"
            return 0
        fi

        log_warn "Binary still in use, waiting... (attempt $((attempt + 1))/$max_attempts)"
        sleep 2
        attempt=$((attempt + 1))
    done

    log_error "Failed to release $binary_path after $max_attempts attempts. Please check running processes."
    return 1
}

# Check config file differences and prompt for overwrite
# Usage: check_config_diff "existing_file" "new_content" "description"
# Returns: 0 if should overwrite, 1 if should skip
check_config_diff() {
    local existing_file="$1"
    local new_content="$2"
    local description="$3"

    # If file doesn't exist, proceed with creation
    if [[ ! -f "$existing_file" ]]; then
        log_info "$description: file does not exist, will create"
        return 0
    fi

    # Create temp file with new content (use printf to preserve content)
    local temp_file=$(mktemp)
    printf '%s\n' "$new_content" > "$temp_file"

    # Check if files are different
    if diff -q "$existing_file" "$temp_file" > /dev/null 2>&1; then
        log_skip "$description - no changes needed"
        rm -f "$temp_file"
        return 1
    fi

    # Files are different - show diff and prompt
    echo ""
    log_warn "$description has changes:"
    echo "${YELLOW}--- Current (deployed)${NC}"
    echo "${GREEN}+++ New (from script)${NC}"
    diff --color=always -u "$existing_file" "$temp_file" 2>/dev/null || diff -u "$existing_file" "$temp_file"
    echo ""

    rm -f "$temp_file"

    # In force mode, always overwrite
    if [[ "$FORCE_MODE" == "true" ]]; then
        log_info "Force mode: overwriting $description"
        return 0
    fi

    # Prompt user
    read -p "Overwrite $description? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_skip "Keeping existing $description"
        return 1
    fi

    return 0
}

# Write config only if user approves (or force mode)
# Usage: write_config_with_check "file_path" "content" "description"
write_config_with_check() {
    local file_path="$1"
    local content="$2"
    local description="$3"

    if check_config_diff "$file_path" "$content" "$description"; then
        printf '%s\n' "$content" > "$file_path"
        log_success "Updated $description"
        return 0
    fi
    return 1
}

#===============================================================================
# VERSION CHECK FUNCTIONS
#===============================================================================

check_binary_version() {
    local binary="$1"
    local expected_version="$2"
    local version_flag="${3:---version}"

    if [[ "$FORCE_MODE" == "true" ]]; then
        return 1
    fi

    if [[ ! -x "$binary" ]]; then
        return 1
    fi

    local current_version
    current_version=$("$binary" "$version_flag" 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

    if [[ "$current_version" == "$expected_version" ]]; then
        return 0
    fi
    return 1
}

is_node_exporter_installed() {
    check_binary_version "/usr/local/bin/node_exporter" "$NODE_EXPORTER_VERSION"
}

is_nginx_exporter_installed() {
    check_binary_version "/usr/local/bin/nginx-prometheus-exporter" "$NGINX_EXPORTER_VERSION"
}

is_mysqld_exporter_installed() {
    check_binary_version "/usr/local/bin/mysqld_exporter" "$MYSQLD_EXPORTER_VERSION"
}

is_phpfpm_exporter_installed() {
    check_binary_version "/usr/local/bin/php-fpm_exporter" "$PHPFPM_EXPORTER_VERSION"
}

is_fail2ban_exporter_installed() {
    check_binary_version "/usr/local/bin/fail2ban-prometheus-exporter" "$FAIL2BAN_EXPORTER_VERSION"
}

is_promtail_installed() {
    check_binary_version "/usr/local/bin/promtail" "$PROMTAIL_VERSION" "-version"
}

#===============================================================================
# UNINSTALL FUNCTIONS
#===============================================================================

uninstall_node_exporter() {
    log_info "Uninstalling Node Exporter..."

    systemctl stop node_exporter 2>/dev/null || true
    systemctl disable node_exporter 2>/dev/null || true

    rm -f /etc/systemd/system/node_exporter.service
    rm -f /usr/local/bin/node_exporter

    userdel node_exporter 2>/dev/null || true
    groupdel node_exporter 2>/dev/null || true

    log_success "Node Exporter uninstalled"
}

uninstall_nginx_exporter() {
    log_info "Uninstalling Nginx Exporter..."

    systemctl stop nginx_exporter 2>/dev/null || true
    systemctl disable nginx_exporter 2>/dev/null || true

    rm -f /etc/systemd/system/nginx_exporter.service
    rm -f /usr/local/bin/nginx-prometheus-exporter

    if [[ "$PURGE_DATA" == "true" ]]; then
        rm -f /etc/nginx/conf.d/stub_status.conf
        nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true
    fi

    userdel nginx_exporter 2>/dev/null || true
    groupdel nginx_exporter 2>/dev/null || true

    log_success "Nginx Exporter uninstalled"
}

uninstall_mysqld_exporter() {
    log_info "Uninstalling MySQL Exporter..."

    systemctl stop mysqld_exporter 2>/dev/null || true
    systemctl disable mysqld_exporter 2>/dev/null || true

    rm -f /etc/systemd/system/mysqld_exporter.service
    rm -f /usr/local/bin/mysqld_exporter

    if [[ "$PURGE_DATA" == "true" ]]; then
        rm -rf /etc/mysqld_exporter
    fi

    userdel mysqld_exporter 2>/dev/null || true
    groupdel mysqld_exporter 2>/dev/null || true

    log_success "MySQL Exporter uninstalled"
}

uninstall_phpfpm_exporter() {
    log_info "Uninstalling PHP-FPM Exporter..."

    systemctl stop phpfpm_exporter 2>/dev/null || true
    systemctl disable phpfpm_exporter 2>/dev/null || true

    rm -f /etc/systemd/system/phpfpm_exporter.service
    rm -f /usr/local/bin/php-fpm_exporter

    userdel phpfpm_exporter 2>/dev/null || true
    groupdel phpfpm_exporter 2>/dev/null || true

    log_success "PHP-FPM Exporter uninstalled"
}

uninstall_fail2ban_exporter() {
    log_info "Uninstalling Fail2ban Exporter..."

    systemctl stop fail2ban_exporter 2>/dev/null || true
    systemctl disable fail2ban_exporter 2>/dev/null || true

    rm -f /etc/systemd/system/fail2ban_exporter.service
    rm -f /usr/local/bin/fail2ban-prometheus-exporter

    userdel fail2ban_exporter 2>/dev/null || true
    groupdel fail2ban_exporter 2>/dev/null || true

    log_success "Fail2ban Exporter uninstalled"
}

uninstall_promtail() {
    log_info "Uninstalling Promtail..."

    systemctl stop promtail 2>/dev/null || true
    systemctl disable promtail 2>/dev/null || true

    rm -f /etc/systemd/system/promtail.service
    rm -f /usr/local/bin/promtail

    if [[ "$PURGE_DATA" == "true" ]]; then
        rm -rf /etc/promtail
        rm -rf /var/lib/promtail
    fi

    userdel promtail 2>/dev/null || true
    groupdel promtail 2>/dev/null || true

    log_success "Promtail uninstalled"
}

remove_firewall_rules() {
    log_info "Removing firewall rules for exporters..."

    # Remove rules for exporter ports
    for port in 9100 9113 9104 9253 9191; do
        ufw delete allow from any to any port "$port" proto tcp 2>/dev/null || true
    done

    log_success "Firewall rules removed"
}

run_uninstall() {
    echo ""
    echo "=========================================="
    echo "${RED}Uninstalling Monitoring Agents${NC}"
    echo "=========================================="
    if [[ "$PURGE_DATA" == "true" ]]; then
        echo "${RED}>>> PURGE MODE: Configs will be deleted! <<<${NC}"
    else
        echo "${YELLOW}>>> Configs will be preserved <<<${NC}"
    fi
    echo ""

    check_root

    uninstall_promtail
    uninstall_fail2ban_exporter
    uninstall_phpfpm_exporter
    uninstall_mysqld_exporter
    uninstall_nginx_exporter
    uninstall_node_exporter
    remove_firewall_rules

    systemctl daemon-reload

    echo ""
    echo "=========================================="
    echo "${GREEN}Uninstallation Complete${NC}"
    echo "=========================================="
    if [[ "$PURGE_DATA" != "true" ]]; then
        echo ""
        echo "Configuration preserved:"
        echo "  /etc/promtail/         - Promtail config"
        echo "  /etc/mysqld_exporter/  - MySQL exporter credentials"
        echo ""
        echo "To completely remove configs, run:"
        echo "  $0 --uninstall --purge"
    fi
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
    fi
}

check_args() {
    if [[ -z "$OBSERVABILITY_IP" ]]; then
        echo "Usage: $0 <OBSERVABILITY_VPS_IP> <LOKI_URL> <LOKI_USER> <LOKI_PASS>"
        echo ""
        echo "Arguments:"
        echo "  OBSERVABILITY_VPS_IP  - IP address of the observability server"
        echo "  LOKI_URL              - URL for Loki (e.g., https://mentat.arewel.com)"
        echo "  LOKI_USER             - Loki basic auth username"
        echo "  LOKI_PASS             - Loki basic auth password"
        exit 1
    fi
}

get_hostname() {
    HOSTNAME=$(hostname -f 2>/dev/null || hostname)
    log_info "Hostname: $HOSTNAME"
}

#===============================================================================
# SYSTEM PREPARATION
#===============================================================================

prepare_system() {
    log_info "Preparing system..."

    apt-get update -qq
    apt-get install -y -qq wget curl unzip ufw

    log_success "System packages verified/installed"
}

configure_firewall() {
    log_info "Configuring firewall..."

    # Force mode resets firewall - but preserve essential ports
    if [[ "$FORCE_MODE" == "true" ]]; then
        log_info "Force mode: resetting firewall..."
        ufw --force reset
    fi

    # Allow essential ports (idempotent - ufw handles duplicates)
    ufw allow 22/tcp    # SSH
    ufw allow 80/tcp    # HTTP
    ufw allow 443/tcp   # HTTPS

    # Allow Prometheus scraping from observability VPS
    # Check if rules already exist to avoid duplicate warnings
    if ! ufw status | grep -q "$OBSERVABILITY_IP.*9100"; then
        ufw allow from "$OBSERVABILITY_IP" to any port 9100 proto tcp  # node_exporter
    fi
    if ! ufw status | grep -q "$OBSERVABILITY_IP.*9113"; then
        ufw allow from "$OBSERVABILITY_IP" to any port 9113 proto tcp  # nginx_exporter
    fi
    if ! ufw status | grep -q "$OBSERVABILITY_IP.*9104"; then
        ufw allow from "$OBSERVABILITY_IP" to any port 9104 proto tcp  # mysqld_exporter
    fi
    if ! ufw status | grep -q "$OBSERVABILITY_IP.*9253"; then
        ufw allow from "$OBSERVABILITY_IP" to any port 9253 proto tcp  # phpfpm_exporter
    fi
    if ! ufw status | grep -q "$OBSERVABILITY_IP.*9191"; then
        ufw allow from "$OBSERVABILITY_IP" to any port 9191 proto tcp  # fail2ban_exporter
    fi

    # Enable firewall if not already enabled
    ufw --force enable

    log_success "Firewall configured"
}

#===============================================================================
# NODE EXPORTER
#===============================================================================

install_node_exporter() {
    local skip_binary=false

    if is_node_exporter_installed; then
        log_skip "Node Exporter ${NODE_EXPORTER_VERSION} already installed"
        skip_binary=true
    fi

    # Always stop service and kill process before installation/update (especially in force mode)
    systemctl stop node_exporter 2>/dev/null || true
    sleep 1
    pkill -f "/usr/local/bin/node_exporter" 2>/dev/null || true
    sleep 1

    # Ensure user exists
    useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null || true

    # Install binary if needed
    if [[ "$skip_binary" == "false" ]]; then
        log_info "Installing Node Exporter ${NODE_EXPORTER_VERSION}..."

        cd /tmp
        wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
        tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"

        # Stop service and verify binary can be replaced
        stop_and_verify_service "node_exporter" "/usr/local/bin/node_exporter"

        cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
        chown node_exporter:node_exporter /usr/local/bin/node_exporter

        rm -rf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64" "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"

        log_success "Node Exporter binary installed"
    fi

    # Always ensure service file exists
    if [[ ! -f /etc/systemd/system/node_exporter.service ]] || [[ "$FORCE_MODE" == "true" ]]; then
        log_info "Creating Node Exporter service file..."
        cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter \
    --collector.systemd \
    --collector.processes

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
    fi

    systemctl enable node_exporter
    systemctl start node_exporter

    log_success "Node Exporter running (port 9100)"
}

#===============================================================================
# NGINX EXPORTER
#===============================================================================

# Detect existing stub_status configuration and return the URL
# Returns: the stub_status URL (e.g., http://127.0.0.1:80/nginx_status)
detect_stub_status_url() {
    local stub_port=""
    local stub_path=""

    # Check for existing stub_status configs in common locations
    for conf_file in /etc/nginx/conf.d/*.conf /etc/nginx/sites-enabled/*; do
        if [[ -f "$conf_file" ]] && grep -q "stub_status" "$conf_file" 2>/dev/null; then
            # Extract port from listen directive in the same server block
            # Handle formats: listen 127.0.0.1:80; or listen 8080; or listen 80;
            local listen_line
            listen_line=$(grep -B20 "stub_status" "$conf_file" | grep "listen" | tail -1)

            if [[ -n "$listen_line" ]]; then
                # Extract port - handle various formats
                if echo "$listen_line" | grep -qE ":[0-9]+"; then
                    # Format: listen 127.0.0.1:80;
                    stub_port=$(echo "$listen_line" | grep -oE ":[0-9]+" | tr -d ':')
                else
                    # Format: listen 80; or listen 8080;
                    stub_port=$(echo "$listen_line" | grep -oE "[0-9]+" | head -1)
                fi
            fi

            # Extract the location path for stub_status
            stub_path=$(grep -E "location.*(stub_status|nginx_status)" "$conf_file" | grep -oE "/[a-z_]+" | head -1)
            [[ -z "$stub_path" ]] && stub_path="/nginx_status"

            if [[ -n "$stub_port" ]]; then
                log_info "Detected existing stub_status in $conf_file (port $stub_port, path $stub_path)"
                echo "http://127.0.0.1:${stub_port}${stub_path}"
                return 0
            fi
        fi
    done

    # No existing config found
    return 1
}

install_nginx_exporter() {
    # Check if nginx is installed
    if ! command -v nginx &> /dev/null; then
        log_warn "Nginx not found, skipping nginx_exporter"
        return
    fi

    local skip_binary=false

    if is_nginx_exporter_installed; then
        log_skip "Nginx Exporter ${NGINX_EXPORTER_VERSION} already installed"
        skip_binary=true
    fi

    # Always stop service and kill process before installation/update (especially in force mode)
    systemctl stop nginx_exporter 2>/dev/null || true
    sleep 1
    pkill -f "nginx-prometheus-exporter" 2>/dev/null || true
    sleep 1

    # Ensure user exists
    useradd --no-create-home --shell /bin/false nginx_exporter 2>/dev/null || true

    # Install binary if needed
    if [[ "$skip_binary" == "false" ]]; then
        log_info "Installing Nginx Prometheus Exporter ${NGINX_EXPORTER_VERSION}..."

        cd /tmp
        wget -q "https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v${NGINX_EXPORTER_VERSION}/nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz"
        tar xzf "nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz"

        # Stop service and verify binary can be replaced
        stop_and_verify_service "nginx_exporter" "/usr/local/bin/nginx-prometheus-exporter"

        cp nginx-prometheus-exporter /usr/local/bin/
        chown nginx_exporter:nginx_exporter /usr/local/bin/nginx-prometheus-exporter

        rm -rf nginx-prometheus-exporter "nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz"

        log_success "Nginx Exporter binary installed"
    fi

    # Detect existing stub_status config OR create our own
    local STUB_STATUS_URL
    if STUB_STATUS_URL=$(detect_stub_status_url); then
        log_info "Using existing stub_status at: $STUB_STATUS_URL"
    else
        # No existing config, create our own on port 8080
        log_info "No existing stub_status found, creating one on port 8080..."
        cat > /etc/nginx/conf.d/stub_status.conf << 'EOF'
server {
    listen 127.0.0.1:8080;
    server_name localhost;

    location /nginx_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        deny all;
    }
}
EOF
        nginx -t && systemctl reload nginx
        STUB_STATUS_URL="http://127.0.0.1:8080/nginx_status"
    fi

    # Verify the stub_status endpoint is reachable
    if ! curl -s --max-time 2 "$STUB_STATUS_URL" | grep -q "Active connections"; then
        log_warn "stub_status endpoint at $STUB_STATUS_URL is not responding correctly"
    fi

    # Always ensure service file exists or update if stub_status URL changed
    local current_url=""
    if [[ -f /etc/systemd/system/nginx_exporter.service ]]; then
        current_url=$(grep "nginx.scrape-uri" /etc/systemd/system/nginx_exporter.service | grep -oE "http://[^ ]+" | tr -d '"')
    fi

    if [[ ! -f /etc/systemd/system/nginx_exporter.service ]] || [[ "$FORCE_MODE" == "true" ]] || [[ "$current_url" != "$STUB_STATUS_URL" ]]; then
        if [[ -n "$current_url" ]] && [[ "$current_url" != "$STUB_STATUS_URL" ]]; then
            log_info "Updating nginx_exporter to use $STUB_STATUS_URL (was $current_url)"
        fi
        log_info "Creating Nginx Exporter service file..."
        cat > /etc/systemd/system/nginx_exporter.service << EOF
[Unit]
Description=Nginx Prometheus Exporter
Wants=network-online.target
After=network-online.target nginx.service

[Service]
User=nginx_exporter
Group=nginx_exporter
Type=simple
ExecStart=/usr/local/bin/nginx-prometheus-exporter \\
    --nginx.scrape-uri=${STUB_STATUS_URL}

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
    fi

    systemctl enable nginx_exporter
    systemctl start nginx_exporter

    log_success "Nginx Exporter running (port 9113, scraping $STUB_STATUS_URL)"
}

#===============================================================================
# MYSQL EXPORTER
#===============================================================================

install_mysqld_exporter() {
    # Check if MySQL/MariaDB is installed
    if ! command -v mysql &> /dev/null && ! command -v mariadb &> /dev/null; then
        log_warn "MySQL/MariaDB not found, skipping mysqld_exporter"
        return
    fi

    local skip_binary=false

    if is_mysqld_exporter_installed; then
        log_skip "MySQL Exporter ${MYSQLD_EXPORTER_VERSION} already installed"
        skip_binary=true
    fi

    # Always stop service and kill process before installation/update (especially in force mode)
    systemctl stop mysqld_exporter 2>/dev/null || true
    sleep 1
    pkill -f "/usr/local/bin/mysqld_exporter" 2>/dev/null || true
    sleep 1

    # Ensure user exists
    useradd --no-create-home --shell /bin/false mysqld_exporter 2>/dev/null || true

    # Ensure directories exist
    mkdir -p /etc/mysqld_exporter

    # Install binary if needed
    if [[ "$skip_binary" == "false" ]]; then
        log_info "Installing MySQL Exporter ${MYSQLD_EXPORTER_VERSION}..."

        cd /tmp
        wget -q "https://github.com/prometheus/mysqld_exporter/releases/download/v${MYSQLD_EXPORTER_VERSION}/mysqld_exporter-${MYSQLD_EXPORTER_VERSION}.linux-amd64.tar.gz"
        tar xzf "mysqld_exporter-${MYSQLD_EXPORTER_VERSION}.linux-amd64.tar.gz"

        # Stop service and verify binary can be replaced
        stop_and_verify_service "mysqld_exporter" "/usr/local/bin/mysqld_exporter"

        cp "mysqld_exporter-${MYSQLD_EXPORTER_VERSION}.linux-amd64/mysqld_exporter" /usr/local/bin/
        chown mysqld_exporter:mysqld_exporter /usr/local/bin/mysqld_exporter

        rm -rf "mysqld_exporter-${MYSQLD_EXPORTER_VERSION}.linux-amd64" "mysqld_exporter-${MYSQLD_EXPORTER_VERSION}.linux-amd64.tar.gz"

        log_success "MySQL Exporter binary installed"
    fi

    # Create credentials file only if it doesn't exist (never overwrite user credentials)
    if [[ ! -f /etc/mysqld_exporter/.my.cnf ]]; then
        cat > /etc/mysqld_exporter/.my.cnf << 'EOF'
[client]
user=exporter
password=CHANGE_ME_EXPORTER_PASSWORD
host=localhost
EOF
        chmod 600 /etc/mysqld_exporter/.my.cnf
        chown mysqld_exporter:mysqld_exporter /etc/mysqld_exporter/.my.cnf
    fi

    # Always ensure service file exists
    if [[ ! -f /etc/systemd/system/mysqld_exporter.service ]] || [[ "$FORCE_MODE" == "true" ]]; then
        log_info "Creating MySQL Exporter service file..."
        cat > /etc/systemd/system/mysqld_exporter.service << 'EOF'
[Unit]
Description=MySQL Exporter
Wants=network-online.target
After=network-online.target mysql.service mariadb.service

[Service]
User=mysqld_exporter
Group=mysqld_exporter
Type=simple
ExecStart=/usr/local/bin/mysqld_exporter \
    --config.my-cnf=/etc/mysqld_exporter/.my.cnf \
    --collect.global_status \
    --collect.info_schema.innodb_metrics \
    --collect.auto_increment.columns \
    --collect.info_schema.processlist \
    --collect.binlog_size \
    --collect.info_schema.tablestats \
    --collect.global_variables \
    --collect.info_schema.query_response_time \
    --collect.info_schema.userstats \
    --collect.info_schema.tables \
    --collect.perf_schema.tablelocks \
    --collect.perf_schema.file_events \
    --collect.perf_schema.eventswaits \
    --collect.perf_schema.indexiowaits \
    --collect.perf_schema.tableiowaits

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
    fi

    systemctl enable mysqld_exporter

    # Only show setup instructions if credentials file has placeholder
    if grep -q "CHANGE_ME_EXPORTER_PASSWORD" /etc/mysqld_exporter/.my.cnf 2>/dev/null; then
        log_warn "MySQL Exporter installed but NOT started"
        log_warn "Please create the MySQL user and update /etc/mysqld_exporter/.my.cnf"
        log_warn "Then run: systemctl start mysqld_exporter"

        echo ""
        echo "MySQL commands to run as root:"
        echo "  CREATE USER IF NOT EXISTS 'exporter'@'localhost' IDENTIFIED BY 'YOUR_PASSWORD';"
        echo "  GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';"
        echo "  FLUSH PRIVILEGES;"
        echo ""
    else
        # Credentials configured, try to start
        systemctl start mysqld_exporter || log_warn "MySQL Exporter failed to start - check credentials"
        log_success "MySQL Exporter running (port 9104)"
    fi
}

#===============================================================================
# PHP-FPM EXPORTER
#===============================================================================

install_phpfpm_exporter() {
    # Check if PHP-FPM is installed
    if ! systemctl list-units --type=service | grep -q "php.*fpm"; then
        log_warn "PHP-FPM not found, skipping phpfpm_exporter"
        return
    fi

    local skip_binary=false

    if is_phpfpm_exporter_installed; then
        log_skip "PHP-FPM Exporter ${PHPFPM_EXPORTER_VERSION} already installed"
        skip_binary=true
    fi

    # Always stop service and kill process before installation/update (especially in force mode)
    systemctl stop phpfpm_exporter 2>/dev/null || true
    sleep 1
    pkill -f "/usr/local/bin/php-fpm_exporter" 2>/dev/null || true
    sleep 1

    # Ensure user exists
    useradd --no-create-home --shell /bin/false phpfpm_exporter 2>/dev/null || true

    # Install binary if needed
    if [[ "$skip_binary" == "false" ]]; then
        log_info "Installing PHP-FPM Exporter ${PHPFPM_EXPORTER_VERSION}..."

        cd /tmp
        wget -q "https://github.com/hipages/php-fpm_exporter/releases/download/v${PHPFPM_EXPORTER_VERSION}/php-fpm_exporter_${PHPFPM_EXPORTER_VERSION}_linux_amd64"

        # Stop service and verify binary can be replaced
        stop_and_verify_service "phpfpm_exporter" "/usr/local/bin/php-fpm_exporter"

        mv "php-fpm_exporter_${PHPFPM_EXPORTER_VERSION}_linux_amd64" /usr/local/bin/php-fpm_exporter
        chmod +x /usr/local/bin/php-fpm_exporter
        chown phpfpm_exporter:phpfpm_exporter /usr/local/bin/php-fpm_exporter

        log_success "PHP-FPM Exporter binary installed"
    fi

    # Find PHP-FPM socket or configure status page
    PHP_FPM_SOCKET=""
    PHP_FPM_STATUS=""

    # Try to find the socket
    for sock in /run/php/php*-fpm.sock /var/run/php*-fpm.sock /run/php-fpm/*.sock; do
        if [[ -S "$sock" ]]; then
            PHP_FPM_SOCKET="$sock"
            break
        fi
    done

    if [[ -n "$PHP_FPM_SOCKET" ]]; then
        log_info "Found PHP-FPM socket: $PHP_FPM_SOCKET"
        # Enable status page in PHP-FPM pool
        PHP_FPM_CONF=$(find /etc/php -name "www.conf" 2>/dev/null | head -1)
        if [[ -n "$PHP_FPM_CONF" ]]; then
            if ! grep -q "^pm.status_path" "$PHP_FPM_CONF"; then
                log_info "Enabling PHP-FPM status page..."
                echo "pm.status_path = /status" >> "$PHP_FPM_CONF"
                systemctl restart "$(systemctl list-units --type=service | grep "php.*fpm" | awk '{print $1}')"
            fi
        fi
        PHP_FPM_STATUS="unix://${PHP_FPM_SOCKET};/status"
    else
        # Try TCP
        PHP_FPM_STATUS="tcp://127.0.0.1:9000/status"
    fi

    # Add phpfpm_exporter to www-data group to access socket
    usermod -a -G www-data phpfpm_exporter 2>/dev/null || true

    # Always ensure service file exists
    if [[ ! -f /etc/systemd/system/phpfpm_exporter.service ]] || [[ "$FORCE_MODE" == "true" ]]; then
        log_info "Creating PHP-FPM Exporter service file..."
        cat > /etc/systemd/system/phpfpm_exporter.service << EOF
[Unit]
Description=PHP-FPM Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=phpfpm_exporter
Group=phpfpm_exporter
Type=simple
ExecStart=/usr/local/bin/php-fpm_exporter server \\
    --phpfpm.scrape-uri="${PHP_FPM_STATUS}" \\
    --web.listen-address=":9253"

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
    fi

    systemctl enable phpfpm_exporter
    systemctl start phpfpm_exporter

    log_success "PHP-FPM Exporter running (port 9253)"
}

#===============================================================================
# FAIL2BAN EXPORTER
#===============================================================================

install_fail2ban_exporter() {
    # Check if fail2ban is installed
    if ! command -v fail2ban-client &> /dev/null; then
        log_warn "Fail2ban not found, skipping fail2ban_exporter"
        return
    fi

    local skip_binary=false

    if is_fail2ban_exporter_installed; then
        log_skip "Fail2ban Exporter ${FAIL2BAN_EXPORTER_VERSION} already installed"
        skip_binary=true
    fi

    # Always stop service and kill process before installation/update (especially in force mode)
    systemctl stop fail2ban_exporter 2>/dev/null || true
    sleep 1
    pkill -f "fail2ban-prometheus-exporter" 2>/dev/null || true
    sleep 1

    # Ensure user exists
    useradd --no-create-home --shell /bin/false fail2ban_exporter 2>/dev/null || true

    # Install binary if needed
    if [[ "$skip_binary" == "false" ]]; then
        log_info "Installing Fail2ban Exporter ${FAIL2BAN_EXPORTER_VERSION}..."

        cd /tmp
        wget -q "https://gitlab.com/hctrdev/fail2ban-prometheus-exporter/-/releases/v${FAIL2BAN_EXPORTER_VERSION}/downloads/fail2ban_exporter_${FAIL2BAN_EXPORTER_VERSION}_linux_amd64.tar.gz"
        tar xzf "fail2ban_exporter_${FAIL2BAN_EXPORTER_VERSION}_linux_amd64.tar.gz"

        # Stop service and verify binary can be replaced
        stop_and_verify_service "fail2ban_exporter" "/usr/local/bin/fail2ban-prometheus-exporter"

        cp fail2ban_exporter /usr/local/bin/fail2ban-prometheus-exporter
        chmod +x /usr/local/bin/fail2ban-prometheus-exporter
        chown fail2ban_exporter:fail2ban_exporter /usr/local/bin/fail2ban-prometheus-exporter

        rm -rf "fail2ban_exporter_${FAIL2BAN_EXPORTER_VERSION}_linux_amd64.tar.gz" fail2ban_exporter LICENSE README.md

        log_success "Fail2ban Exporter binary installed"
    fi

    # Always ensure service file exists
    if [[ ! -f /etc/systemd/system/fail2ban_exporter.service ]] || [[ "$FORCE_MODE" == "true" ]]; then
        log_info "Creating Fail2ban Exporter service file..."
        cat > /etc/systemd/system/fail2ban_exporter.service << 'EOF'
[Unit]
Description=Fail2ban Prometheus Exporter
Wants=network-online.target
After=network-online.target fail2ban.service

[Service]
User=fail2ban_exporter
Group=fail2ban_exporter
Type=simple
ExecStart=/usr/local/bin/fail2ban-prometheus-exporter \
    --web.listen-address=":9191"

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
    fi

    # Add fail2ban_exporter user to fail2ban group to access socket
    # fail2ban socket is typically at /var/run/fail2ban/fail2ban.sock
    if getent group fail2ban > /dev/null 2>&1; then
        usermod -a -G fail2ban fail2ban_exporter 2>/dev/null || true
    fi

    # Ensure fail2ban socket is accessible
    if [[ -S /var/run/fail2ban/fail2ban.sock ]]; then
        chmod g+rw /var/run/fail2ban/fail2ban.sock 2>/dev/null || true
    fi

    systemctl enable fail2ban_exporter
    systemctl start fail2ban_exporter

    log_success "Fail2ban Exporter running (port 9191)"
}

#===============================================================================
# PROMTAIL (Log Shipper)
#===============================================================================

install_promtail() {
    if [[ -z "$LOKI_URL" ]]; then
        log_warn "LOKI_URL not provided, skipping Promtail"
        return
    fi

    # Normalize LOKI_URL - remove trailing /loki if present (we add it ourselves)
    LOKI_URL="${LOKI_URL%/}"          # Remove trailing slash
    LOKI_URL="${LOKI_URL%/loki}"      # Remove trailing /loki if present
    LOKI_URL="${LOKI_URL%/}"          # Remove any trailing slash again

    local skip_binary=false

    if is_promtail_installed; then
        log_skip "Promtail ${PROMTAIL_VERSION} already installed"
        skip_binary=true
    fi

    # Always stop service and kill process before installation/update (especially in force mode)
    systemctl stop promtail 2>/dev/null || true
    sleep 1
    pkill -f "/usr/local/bin/promtail" 2>/dev/null || true
    sleep 1

    # Ensure user exists
    useradd --no-create-home --shell /bin/false promtail 2>/dev/null || true

    # Ensure directories exist
    mkdir -p /etc/promtail
    mkdir -p /var/lib/promtail

    # Install binary if needed
    if [[ "$skip_binary" == "false" ]]; then
        log_info "Installing Promtail ${PROMTAIL_VERSION}..."

        cd /tmp
        wget -q "https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip"
        unzip -o promtail-linux-amd64.zip
        chmod +x promtail-linux-amd64

        # Stop service and verify binary can be replaced
        stop_and_verify_service "promtail" "/usr/local/bin/promtail"

        mv promtail-linux-amd64 /usr/local/bin/promtail

        rm -f promtail-linux-amd64.zip

        log_success "Promtail binary installed"
    fi

    # Create Promtail configuration
    cat > /etc/promtail/promtail.yaml << EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: ${LOKI_URL}/loki/api/v1/push
    basic_auth:
      username: ${LOKI_USER}
      password: ${LOKI_PASS}

scrape_configs:
  # Nginx access logs
  - job_name: nginx_access
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx_access
          host: ${HOSTNAME}
          __path__: /var/log/nginx/access.log

  # Nginx error logs
  - job_name: nginx_error
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx_error
          host: ${HOSTNAME}
          __path__: /var/log/nginx/error.log

  # PHP error logs
  - job_name: php_error
    static_configs:
      - targets:
          - localhost
        labels:
          job: php_error
          host: ${HOSTNAME}
          __path__: /var/log/php*-fpm.log

  # MySQL slow query log
  - job_name: mysql_slow
    static_configs:
      - targets:
          - localhost
        labels:
          job: mysql_slow
          host: ${HOSTNAME}
          __path__: /var/log/mysql/mysql-slow.log
    pipeline_stages:
      - multiline:
          firstline: '^# Time:'
          max_wait_time: 3s

  # Syslog
  - job_name: syslog
    static_configs:
      - targets:
          - localhost
        labels:
          job: syslog
          host: ${HOSTNAME}
          __path__: /var/log/syslog

  # Auth log
  - job_name: auth
    static_configs:
      - targets:
          - localhost
        labels:
          job: auth
          host: ${HOSTNAME}
          __path__: /var/log/auth.log

  # WordPress debug logs (common paths)
  - job_name: wordpress
    static_configs:
      - targets:
          - localhost
        labels:
          job: wordpress
          host: ${HOSTNAME}
          __path__: /var/www/*/wp-content/debug.log
EOF

    # Add promtail to adm group to read logs
    usermod -a -G adm promtail
    usermod -a -G www-data promtail 2>/dev/null || true

    chown -R promtail:promtail /etc/promtail /var/lib/promtail

    # Always ensure service file exists
    if [[ ! -f /etc/systemd/system/promtail.service ]] || [[ "$FORCE_MODE" == "true" ]]; then
        log_info "Creating Promtail service file..."
        cat > /etc/systemd/system/promtail.service << 'EOF'
[Unit]
Description=Promtail
Wants=network-online.target
After=network-online.target

[Service]
User=promtail
Group=promtail
Type=simple
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail.yaml

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
    fi

    systemctl enable promtail
    systemctl start promtail

    log_success "Promtail running (log shipping to Loki)"
}

#===============================================================================
# SUMMARY
#===============================================================================

print_summary() {
    # Get host IP for mentat commands
    local HOST_IP
    HOST_IP=$(hostname -I | awk '{print $1}')

    echo ""
    echo "=========================================="
    echo "${GREEN}Monitored Host Setup Complete!${NC}"
    echo "=========================================="
    echo ""
    echo "Host: $HOSTNAME"
    echo "IP:   $HOST_IP"
    echo ""
    echo "Installed exporters:"

    local HAS_NODE=false HAS_NGINX=false HAS_MYSQL=false HAS_PHPFPM=false HAS_FAIL2BAN=false HAS_PROMTAIL=false
    local MYSQL_NEEDS_SETUP=false

    if systemctl is-active --quiet node_exporter; then
        echo "  ${GREEN}✓${NC} Node Exporter      (port 9100)"
        HAS_NODE=true
    fi

    if systemctl is-active --quiet nginx_exporter; then
        echo "  ${GREEN}✓${NC} Nginx Exporter     (port 9113)"
        HAS_NGINX=true
    fi

    if systemctl is-enabled --quiet mysqld_exporter 2>/dev/null; then
        if systemctl is-active --quiet mysqld_exporter; then
            # Check if mysql_up is 1
            local mysql_up
            mysql_up=$(curl -s http://localhost:9104/metrics 2>/dev/null | grep "^mysql_up " | awk '{print $2}')
            if [[ "$mysql_up" == "1" ]]; then
                echo "  ${GREEN}✓${NC} MySQL Exporter     (port 9104)"
            else
                echo "  ${YELLOW}!${NC} MySQL Exporter     (port 9104) - running but mysql_up=0"
                MYSQL_NEEDS_SETUP=true
            fi
            HAS_MYSQL=true
        else
            echo "  ${YELLOW}!${NC} MySQL Exporter     (port 9104) - needs configuration"
            MYSQL_NEEDS_SETUP=true
            HAS_MYSQL=true
        fi
    fi

    if systemctl is-active --quiet phpfpm_exporter; then
        echo "  ${GREEN}✓${NC} PHP-FPM Exporter   (port 9253)"
        HAS_PHPFPM=true
    fi

    if systemctl is-active --quiet fail2ban_exporter; then
        echo "  ${GREEN}✓${NC} Fail2ban Exporter  (port 9191)"
        HAS_FAIL2BAN=true
    fi

    if systemctl is-active --quiet promtail; then
        echo "  ${GREEN}✓${NC} Promtail           (log shipping)"
        HAS_PROMTAIL=true
    fi

    echo ""
    echo "Firewall:"
    echo "  Allowed connections from: $OBSERVABILITY_IP"

    # MySQL setup instructions
    if [[ "$MYSQL_NEEDS_SETUP" == "true" ]]; then
        echo ""
        echo "=========================================="
        echo "${YELLOW}ACTION REQUIRED: MySQL Exporter Setup${NC}"
        echo "=========================================="
        echo ""
        echo "1. Create MySQL user (run as root on this host):"
        echo ""
        echo "${BLUE}sudo mysql <<'EOF'"
        echo "CREATE USER IF NOT EXISTS 'exporter'@'localhost' IDENTIFIED BY 'CHANGE_ME_SECURE_PASSWORD';"
        echo "CREATE USER IF NOT EXISTS 'exporter'@'127.0.0.1' IDENTIFIED BY 'CHANGE_ME_SECURE_PASSWORD';"
        echo "GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';"
        echo "GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'127.0.0.1';"
        echo "FLUSH PRIVILEGES;"
        echo "EOF${NC}"
        echo ""
        echo "2. Update exporter config with the password:"
        echo ""
        echo "${BLUE}sudo tee /etc/mysqld_exporter/.my.cnf > /dev/null <<'EOF'"
        echo "[client]"
        echo "user=exporter"
        echo "password=CHANGE_ME_SECURE_PASSWORD"
        echo "host=127.0.0.1"
        echo "EOF${NC}"
        echo ""
        echo "3. Restart the exporter:"
        echo ""
        echo "${BLUE}sudo systemctl restart mysqld_exporter${NC}"
        echo ""
        echo "4. Verify it works:"
        echo ""
        echo "${BLUE}curl -s http://localhost:9104/metrics | grep mysql_up${NC}"
        echo "# Should show: mysql_up 1"
    fi

    # Mentat commands
    echo ""
    echo "=========================================="
    echo "${GREEN}COMMANDS TO RUN ON MENTAT${NC}"
    echo "=========================================="
    echo ""
    echo "Option 1: Use the helper script:"
    echo ""
    echo "${BLUE}sudo ~/repo/mentat/observability-stack/scripts/add-monitored-host.sh \\"
    echo "  --name \"$(echo $HOSTNAME | cut -d. -f1)\" \\"
    echo "  --ip \"$HOST_IP\" \\"
    echo "  --description \"$(echo $HOSTNAME)\"${NC}"
    echo ""
    echo "Option 2: Manual setup:"
    echo ""
    echo "a) Add to global.yaml:"
    echo ""
    echo "${BLUE}cat >> ~/repo/mentat/observability-stack/config/global.yaml <<'EOF'"
    echo ""
    echo "  - name: \"$(echo $HOSTNAME | cut -d. -f1)\""
    echo "    ip: \"$HOST_IP\""
    echo "    description: \"$HOSTNAME\""
    echo "    exporters:"
    [[ "$HAS_NODE" == "true" ]] && echo "      - node_exporter"
    [[ "$HAS_NGINX" == "true" ]] && echo "      - nginx_exporter"
    [[ "$HAS_MYSQL" == "true" ]] && echo "      - mysqld_exporter"
    [[ "$HAS_PHPFPM" == "true" ]] && echo "      - phpfpm_exporter"
    [[ "$HAS_FAIL2BAN" == "true" ]] && echo "      - fail2ban_exporter"
    echo "EOF${NC}"
    echo ""
    echo "b) Regenerate Prometheus config and reload:"
    echo ""
    echo "${BLUE}cd ~/repo/mentat/observability-stack/scripts"
    echo "sudo ./setup-observability.sh${NC}"
    echo ""
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    # Handle uninstall mode
    if [[ "$UNINSTALL_MODE" == "true" ]]; then
        run_uninstall
        exit 0
    fi

    echo ""
    echo "=========================================="
    echo "Monitored Host Agent Setup"
    echo "=========================================="
    if [[ "$FORCE_MODE" == "true" ]]; then
        echo "${YELLOW}>>> FORCE MODE: Reinstalling everything from scratch <<<${NC}"
    fi
    echo ""

    check_root
    check_args
    get_hostname
    prepare_system
    configure_firewall

    install_node_exporter
    install_nginx_exporter
    install_mysqld_exporter
    install_phpfpm_exporter
    install_fail2ban_exporter
    install_promtail

    print_summary
}

main "$@"
