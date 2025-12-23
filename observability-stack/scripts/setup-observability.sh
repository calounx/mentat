#!/bin/bash
#===============================================================================
# Observability Stack Setup Script for Debian 13
# Installs: Prometheus, Loki, Grafana, Alertmanager, Nginx (reverse proxy)
# All configuration is read from global.yaml
#
# This script is IDEMPOTENT - safe to run multiple times:
#   - Skips installation of already installed components (at correct version)
#   - Skips firewall configuration if already configured
#   - Renews SSL certificates only if expired or expiring within 7 days
#   - Creates backups before modifying configuration files
#   - Always updates configuration files to reflect latest settings
#
# Usage:
#   ./setup-observability.sh                    # Normal run (idempotent)
#   ./setup-observability.sh --force            # Force reinstall everything
#   ./setup-observability.sh --uninstall        # Remove all components
#   ./setup-observability.sh --uninstall --purge # Remove including data
#===============================================================================

set -euo pipefail

# Mode flags
FORCE_MODE=false
UNINSTALL_MODE=false
PURGE_DATA=false

# Backup directory
BACKUP_DIR="/var/backups/observability-stack"
BACKUP_TIMESTAMP=""

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                FORCE_MODE=true
                shift
                ;;
            --uninstall|--rollback)
                UNINSTALL_MODE=true
                shift
                ;;
            --purge)
                PURGE_DATA=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --force, -f        Force reinstall everything from scratch"
                echo "  --uninstall        Remove all observability components (keeps data)"
                echo "  --purge            Used with --uninstall to also remove all data"
                echo "  --help, -h         Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0                           # Install/update (idempotent)"
                echo "  $0 --force                   # Force complete reinstall"
                echo "  $0 --uninstall               # Uninstall, keep data for recovery"
                echo "  $0 --uninstall --purge       # Complete removal including data"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Parse arguments before anything else
parse_args "$@"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${BASE_DIR}/config/global.yaml"

# Versions (update as needed)
PROMETHEUS_VERSION="2.48.1"
ALERTMANAGER_VERSION="0.26.0"
LOKI_VERSION="2.9.3"
NODE_EXPORTER_VERSION="1.7.0"
NGINX_EXPORTER_VERSION="1.1.0"

#===============================================================================
# UTILITY FUNCTIONS
#===============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_skip() {
    echo -e "${GREEN}[SKIP]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Parse YAML value (basic parser - handles simple key: value)
yaml_get() {
    local file="$1"
    local key="$2"
    grep -E "^\s*${key}:" "$file" | head -1 | sed 's/.*:\s*//' | tr -d '"' | tr -d "'"
}

# Parse nested YAML value
yaml_get_nested() {
    local file="$1"
    local parent="$2"
    local key="$3"
    awk -v parent="$parent" -v key="$key" '
        $0 ~ "^"parent":" { in_section=1; next }
        in_section && /^[a-z]/ { in_section=0 }
        in_section && $0 ~ "^  "key":" { gsub(/.*: */, ""); gsub(/["'\'']/, ""); print; exit }
    ' "$file"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
    fi
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
    echo -e "${YELLOW}--- Current (deployed)${NC}"
    echo -e "${GREEN}+++ New (from script)${NC}"
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
# BACKUP FUNCTIONS
#===============================================================================

init_backup() {
    BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    mkdir -p "${BACKUP_DIR}/${BACKUP_TIMESTAMP}"
    log_info "Backup directory: ${BACKUP_DIR}/${BACKUP_TIMESTAMP}"
}

backup_file() {
    local src="$1"
    local name="${2:-$(basename "$src")}"

    if [[ -f "$src" ]]; then
        cp "$src" "${BACKUP_DIR}/${BACKUP_TIMESTAMP}/${name}"
        log_info "Backed up: $src"
    fi
}

backup_dir() {
    local src="$1"
    local name="${2:-$(basename "$src")}"

    if [[ -d "$src" ]]; then
        cp -r "$src" "${BACKUP_DIR}/${BACKUP_TIMESTAMP}/${name}"
        log_info "Backed up directory: $src"
    fi
}

create_backup() {
    log_info "Creating backup of existing configuration..."
    init_backup

    # Backup Prometheus configs
    backup_file "/etc/prometheus/prometheus.yml"
    backup_dir "/etc/prometheus/rules" "prometheus_rules"

    # Backup Alertmanager configs
    backup_file "/etc/alertmanager/alertmanager.yml"
    backup_dir "/etc/alertmanager/templates" "alertmanager_templates"

    # Backup Loki config
    backup_file "/etc/loki/loki-config.yaml"

    # Backup Grafana configs
    backup_file "/etc/grafana/grafana.ini"
    backup_dir "/etc/grafana/provisioning" "grafana_provisioning"
    backup_file "/etc/grafana/.secret_key" "grafana_secret_key"

    # Backup Nginx configs
    backup_file "/etc/nginx/sites-available/observability"
    backup_file "/etc/nginx/.htpasswd_prometheus"
    backup_file "/etc/nginx/.htpasswd_loki"

    # Backup systemd service files
    for service in prometheus node_exporter alertmanager loki; do
        backup_file "/etc/systemd/system/${service}.service"
    done

    log_success "Backup created at ${BACKUP_DIR}/${BACKUP_TIMESTAMP}"
}

list_backups() {
    echo "Available backups:"
    if [[ -d "$BACKUP_DIR" ]]; then
        ls -la "$BACKUP_DIR" 2>/dev/null || echo "  No backups found"
    else
        echo "  No backups found"
    fi
}

#===============================================================================
# UNINSTALL FUNCTIONS
#===============================================================================

uninstall_prometheus() {
    log_info "Uninstalling Prometheus..."

    systemctl stop prometheus 2>/dev/null || true
    systemctl disable prometheus 2>/dev/null || true

    rm -f /etc/systemd/system/prometheus.service
    rm -f /usr/local/bin/prometheus /usr/local/bin/promtool
    rm -rf /etc/prometheus

    if [[ "$PURGE_DATA" == "true" ]]; then
        rm -rf /var/lib/prometheus
        log_info "  Purged Prometheus data"
    fi

    userdel prometheus 2>/dev/null || true
    groupdel prometheus 2>/dev/null || true

    log_success "Prometheus uninstalled"
}

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

uninstall_alertmanager() {
    log_info "Uninstalling Alertmanager..."

    systemctl stop alertmanager 2>/dev/null || true
    systemctl disable alertmanager 2>/dev/null || true

    rm -f /etc/systemd/system/alertmanager.service
    rm -f /usr/local/bin/alertmanager /usr/local/bin/amtool
    rm -rf /etc/alertmanager

    if [[ "$PURGE_DATA" == "true" ]]; then
        rm -rf /var/lib/alertmanager
        log_info "  Purged Alertmanager data"
    fi

    userdel alertmanager 2>/dev/null || true
    groupdel alertmanager 2>/dev/null || true

    log_success "Alertmanager uninstalled"
}

uninstall_loki() {
    log_info "Uninstalling Loki..."

    systemctl stop loki 2>/dev/null || true
    systemctl disable loki 2>/dev/null || true

    rm -f /etc/systemd/system/loki.service
    rm -f /usr/local/bin/loki
    rm -rf /etc/loki

    if [[ "$PURGE_DATA" == "true" ]]; then
        rm -rf /var/lib/loki
        log_info "  Purged Loki data"
    fi

    userdel loki 2>/dev/null || true
    groupdel loki 2>/dev/null || true

    log_success "Loki uninstalled"
}

uninstall_grafana() {
    log_info "Uninstalling Grafana..."

    systemctl stop grafana-server 2>/dev/null || true
    systemctl disable grafana-server 2>/dev/null || true

    apt-get remove -y grafana 2>/dev/null || true

    if [[ "$PURGE_DATA" == "true" ]]; then
        apt-get purge -y grafana 2>/dev/null || true
        rm -rf /var/lib/grafana
        rm -rf /etc/grafana
        log_info "  Purged Grafana data"
    fi

    rm -f /etc/apt/sources.list.d/grafana.list
    rm -f /usr/share/keyrings/grafana.key

    log_success "Grafana uninstalled"
}

uninstall_nginx_config() {
    log_info "Removing Nginx observability configuration..."

    rm -f /etc/nginx/sites-enabled/observability
    rm -f /etc/nginx/sites-available/observability
    rm -f /etc/nginx/.htpasswd_prometheus
    rm -f /etc/nginx/.htpasswd_loki

    # Restore default site if it exists
    if [[ -f /etc/nginx/sites-available/default ]]; then
        ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
    fi

    nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true

    log_success "Nginx configuration removed"
}

uninstall_ssl() {
    log_info "Removing SSL certificates..."

    if [[ -n "${GRAFANA_DOMAIN:-}" ]]; then
        certbot delete --cert-name "${GRAFANA_DOMAIN}" --non-interactive 2>/dev/null || true
        log_info "  Removed certificate for ${GRAFANA_DOMAIN}"
    fi

    rm -rf /var/www/certbot

    log_success "SSL certificates removed"
}

run_uninstall() {
    echo ""
    echo "=========================================="
    echo -e "${RED}Uninstalling Observability Stack${NC}"
    echo "=========================================="
    if [[ "$PURGE_DATA" == "true" ]]; then
        echo -e "${RED}>>> PURGE MODE: All data will be deleted! <<<${NC}"
    else
        echo -e "${YELLOW}>>> Data will be preserved for potential recovery <<<${NC}"
    fi
    echo ""

    check_root

    # Try to parse config for domain name (for SSL removal)
    if [[ -f "$CONFIG_FILE" ]]; then
        GRAFANA_DOMAIN=$(yaml_get_nested "$CONFIG_FILE" "network" "grafana_domain") || true
    fi

    # Create backup before uninstall (unless purging)
    if [[ "$PURGE_DATA" != "true" ]]; then
        create_backup
    fi

    # Uninstall in reverse order of installation
    uninstall_ssl
    uninstall_nginx_config
    uninstall_grafana
    uninstall_loki
    uninstall_alertmanager
    uninstall_node_exporter
    uninstall_prometheus

    # Reload systemd
    systemctl daemon-reload

    echo ""
    echo "=========================================="
    echo -e "${GREEN}Uninstallation Complete${NC}"
    echo "=========================================="
    if [[ "$PURGE_DATA" != "true" ]]; then
        echo ""
        echo "Data directories preserved:"
        echo "  /var/lib/prometheus  - Prometheus metrics data"
        echo "  /var/lib/loki        - Loki log data"
        echo "  /var/lib/grafana     - Grafana dashboards and settings"
        echo "  /var/lib/alertmanager - Alertmanager state"
        echo ""
        echo "Backup location: ${BACKUP_DIR}/${BACKUP_TIMESTAMP}"
        echo ""
        echo "To completely remove all data, run:"
        echo "  $0 --uninstall --purge"
    fi
    echo ""
}

#===============================================================================
# VERSION CHECK FUNCTIONS
#===============================================================================

# Check if a binary exists and matches expected version
check_binary_version() {
    local binary="$1"
    local expected_version="$2"
    local version_flag="${3:---version}"

    # Force mode bypasses all checks
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

# Check if Prometheus is installed at correct version
is_prometheus_installed() {
    check_binary_version "/usr/local/bin/prometheus" "$PROMETHEUS_VERSION"
}

# Check if Node Exporter is installed at correct version
is_node_exporter_installed() {
    check_binary_version "/usr/local/bin/node_exporter" "$NODE_EXPORTER_VERSION"
}

# Check if Alertmanager is installed at correct version
is_alertmanager_installed() {
    check_binary_version "/usr/local/bin/alertmanager" "$ALERTMANAGER_VERSION"
}

# Check if Loki is installed at correct version
is_loki_installed() {
    check_binary_version "/usr/local/bin/loki" "$LOKI_VERSION" "-version"
}

# Check if Grafana is installed
is_grafana_installed() {
    # Force mode bypasses all checks
    if [[ "$FORCE_MODE" == "true" ]]; then
        return 1
    fi
    dpkg -l grafana &>/dev/null
}

# Check if SSL certificate exists and is valid (not expired within 7 days)
is_ssl_valid() {
    local domain="$1"
    local cert_file="/etc/letsencrypt/live/${domain}/fullchain.pem"

    # Force mode bypasses all checks
    if [[ "$FORCE_MODE" == "true" ]]; then
        return 1
    fi

    if [[ ! -f "$cert_file" ]]; then
        return 1
    fi

    # Check if certificate expires within 7 days
    if openssl x509 -checkend 604800 -noout -in "$cert_file" &>/dev/null; then
        return 0
    fi
    return 1
}

check_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
    fi
    log_info "Using configuration from: $CONFIG_FILE"
}

#===============================================================================
# CONFIGURATION PARSING
#===============================================================================

parse_config() {
    log_info "Parsing configuration..."

    # Network settings
    GRAFANA_DOMAIN=$(yaml_get_nested "$CONFIG_FILE" "network" "grafana_domain")
    LETSENCRYPT_EMAIL=$(yaml_get_nested "$CONFIG_FILE" "network" "letsencrypt_email")

    # SMTP settings
    SMTP_HOST=$(yaml_get_nested "$CONFIG_FILE" "smtp" "host")
    SMTP_PORT=$(yaml_get_nested "$CONFIG_FILE" "smtp" "port")
    SMTP_USERNAME=$(yaml_get_nested "$CONFIG_FILE" "smtp" "username")
    SMTP_PASSWORD=$(yaml_get_nested "$CONFIG_FILE" "smtp" "password")
    SMTP_FROM=$(yaml_get_nested "$CONFIG_FILE" "smtp" "from_address")
    SMTP_STARTTLS=$(yaml_get_nested "$CONFIG_FILE" "smtp" "starttls")

    # Get first email from to_addresses
    SMTP_TO=$(grep -A1 "to_addresses:" "$CONFIG_FILE" | tail -1 | sed 's/.*- *//' | tr -d '"')

    # Retention
    RETENTION_DAYS=$(yaml_get_nested "$CONFIG_FILE" "retention" "metrics_days")

    # Grafana
    GRAFANA_ADMIN_PASS=$(yaml_get_nested "$CONFIG_FILE" "grafana" "admin_password")

    # Security
    PROMETHEUS_USER=$(yaml_get_nested "$CONFIG_FILE" "security" "prometheus_basic_auth_user")
    PROMETHEUS_PASS=$(yaml_get_nested "$CONFIG_FILE" "security" "prometheus_basic_auth_password")
    LOKI_USER=$(yaml_get_nested "$CONFIG_FILE" "security" "loki_basic_auth_user")
    LOKI_PASS=$(yaml_get_nested "$CONFIG_FILE" "security" "loki_basic_auth_password")

    log_success "Configuration parsed successfully"
    log_info "  Domain: $GRAFANA_DOMAIN"
    log_info "  SMTP: $SMTP_HOST:$SMTP_PORT"
    log_info "  Retention: ${RETENTION_DAYS} days"
}

#===============================================================================
# SYSTEM PREPARATION
#===============================================================================

prepare_system() {
    log_info "Preparing system..."

    # Update package lists
    apt-get update -qq

    # Install required packages (apt-get install is idempotent)
    # Note: apt-transport-https and software-properties-common not needed on Debian 13+
    apt-get install -y -qq \
        wget \
        curl \
        gnupg \
        ufw \
        apache2-utils \
        nginx \
        certbot \
        python3-certbot-nginx \
        jq \
        unzip

    log_success "System packages verified/installed"
}

#===============================================================================
# FIREWALL CONFIGURATION
#===============================================================================

configure_firewall() {
    log_info "Configuring firewall..."

    # Check if firewall is already configured with required rules
    local needs_config=false

    # Force mode always reconfigures
    if [[ "$FORCE_MODE" == "true" ]]; then
        needs_config=true
        log_info "Force mode: resetting firewall..."
        ufw --force reset
    elif ! ufw status | grep -q "Status: active"; then
        needs_config=true
    elif ! ufw status | grep -qE "22/tcp.*ALLOW"; then
        needs_config=true
    elif ! ufw status | grep -qE "80/tcp.*ALLOW"; then
        needs_config=true
    elif ! ufw status | grep -qE "443/tcp.*ALLOW"; then
        needs_config=true
    fi

    if [[ "$needs_config" == "false" ]]; then
        log_skip "Firewall already configured"
        return
    fi

    # Default policies
    ufw default deny incoming
    ufw default allow outgoing

    # Allow SSH
    ufw allow 22/tcp

    # Allow HTTP/HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp

    # Enable firewall
    ufw --force enable

    log_success "Firewall configured"
}

#===============================================================================
# PROMETHEUS INSTALLATION
#===============================================================================

install_prometheus() {
    if is_prometheus_installed; then
        log_skip "Prometheus ${PROMETHEUS_VERSION} already installed"
        # Ensure directories and user exist
        useradd --no-create-home --shell /bin/false prometheus 2>/dev/null || true
        mkdir -p /etc/prometheus/rules /var/lib/prometheus
        return
    fi

    log_info "Installing Prometheus ${PROMETHEUS_VERSION}..."

    # Stop service if running (important for force mode reinstall)
    systemctl stop prometheus 2>/dev/null || true

    # Create user
    useradd --no-create-home --shell /bin/false prometheus 2>/dev/null || true

    # Create directories
    mkdir -p /etc/prometheus/rules
    mkdir -p /var/lib/prometheus

    # Download and extract
    cd /tmp
    wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
    tar xzf "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"

    # Install binaries
    cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus" /usr/local/bin/
    cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool" /usr/local/bin/

    # Copy console files
    cp -r "prometheus-${PROMETHEUS_VERSION}.linux-amd64/consoles" /etc/prometheus/
    cp -r "prometheus-${PROMETHEUS_VERSION}.linux-amd64/console_libraries" /etc/prometheus/

    # Cleanup
    rm -rf "prometheus-${PROMETHEUS_VERSION}.linux-amd64" "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"

    # Set ownership
    chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
    chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool

    log_success "Prometheus installed"
}

configure_prometheus() {
    log_info "Configuring Prometheus..."

    # Generate targets from global.yaml
    NODE_TARGETS=""
    NGINX_TARGETS=""
    MYSQL_TARGETS=""
    PHPFPM_TARGETS=""

    # Parse monitored hosts from config
    while IFS= read -r line; do
        if [[ "$line" =~ ip:\ *\"?([0-9.]+)\"? ]]; then
            IP="${BASH_REMATCH[1]}"
            if [[ -n "$IP" && "$IP" != "MONITORED_HOST"* ]]; then
                # Get the name from previous lines
                NAME=$(grep -B5 "ip: .*$IP" "$CONFIG_FILE" | grep "name:" | head -1 | sed 's/.*name: *//' | tr -d '"')
                if [[ -n "$NAME" ]]; then
                    NODE_TARGETS="${NODE_TARGETS}      - targets: ['${IP}:9100']\n        labels:\n          instance: '${NAME}'\n"
                    NGINX_TARGETS="${NGINX_TARGETS}      - targets: ['${IP}:9113']\n        labels:\n          instance: '${NAME}'\n"
                    MYSQL_TARGETS="${MYSQL_TARGETS}      - targets: ['${IP}:9104']\n        labels:\n          instance: '${NAME}'\n"
                    PHPFPM_TARGETS="${PHPFPM_TARGETS}      - targets: ['${IP}:9253']\n        labels:\n          instance: '${NAME}'\n"
                fi
            fi
        fi
    done < "$CONFIG_FILE"

    # Generate prometheus.yml content from template
    local prometheus_config
    prometheus_config=$(sed -e "s|{{NODE_EXPORTER_TARGETS}}|${NODE_TARGETS}|g" \
        -e "s|{{NGINX_EXPORTER_TARGETS}}|${NGINX_TARGETS}|g" \
        -e "s|{{MYSQL_EXPORTER_TARGETS}}|${MYSQL_TARGETS}|g" \
        -e "s|{{PHPFPM_EXPORTER_TARGETS}}|${PHPFPM_TARGETS}|g" \
        "${BASE_DIR}/prometheus/prometheus.yml.template")

    # Check and write prometheus.yml
    local config_changed=false
    if write_config_with_check "/etc/prometheus/prometheus.yml" "$prometheus_config" "Prometheus config (prometheus.yml)"; then
        config_changed=true
    fi

    # Copy alert rules
    cp "${BASE_DIR}/prometheus/rules/"*.yml /etc/prometheus/rules/

    # Set ownership
    chown -R prometheus:prometheus /etc/prometheus

    # Generate systemd service content
    local service_content
    read -r -d '' service_content << EOF || true
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \\
    --config.file=/etc/prometheus/prometheus.yml \\
    --storage.tsdb.path=/var/lib/prometheus/ \\
    --storage.tsdb.retention.time=${RETENTION_DAYS}d \\
    --web.console.templates=/etc/prometheus/consoles \\
    --web.console.libraries=/etc/prometheus/console_libraries \\
    --web.enable-lifecycle \\
    --web.enable-admin-api \\
    --web.external-url=https://${GRAFANA_DOMAIN}/prometheus/ \\
    --web.route-prefix=/

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Check and write systemd service
    if write_config_with_check "/etc/systemd/system/prometheus.service" "$service_content" "Prometheus service"; then
        config_changed=true
        systemctl daemon-reload
    fi

    systemctl enable prometheus
    systemctl restart prometheus

    log_success "Prometheus configured and started"
}

#===============================================================================
# NODE EXPORTER (for self-monitoring)
#===============================================================================

install_node_exporter() {
    if is_node_exporter_installed; then
        log_skip "Node Exporter ${NODE_EXPORTER_VERSION} already installed"
        # Ensure service is running
        systemctl is-active --quiet node_exporter || systemctl start node_exporter
        return
    fi

    log_info "Installing Node Exporter ${NODE_EXPORTER_VERSION}..."

    # Stop service if running (important for force mode reinstall)
    systemctl stop node_exporter 2>/dev/null || true

    useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null || true

    cd /tmp
    wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
    tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"

    cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
    chown node_exporter:node_exporter /usr/local/bin/node_exporter

    rm -rf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64" "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"

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
    systemctl enable node_exporter
    systemctl restart node_exporter

    log_success "Node Exporter installed and started"
}

#===============================================================================
# NGINX EXPORTER INSTALLATION
#===============================================================================

is_nginx_exporter_installed() {
    check_binary_version "/usr/local/bin/nginx-prometheus-exporter" "$NGINX_EXPORTER_VERSION"
}

install_nginx_exporter() {
    if is_nginx_exporter_installed; then
        log_skip "Nginx Exporter ${NGINX_EXPORTER_VERSION} already installed"
        systemctl is-active --quiet nginx_exporter || systemctl start nginx_exporter
        return
    fi

    log_info "Installing Nginx Exporter ${NGINX_EXPORTER_VERSION}..."

    systemctl stop nginx_exporter 2>/dev/null || true
    useradd --no-create-home --shell /bin/false nginx_exporter 2>/dev/null || true

    cd /tmp
    wget -q "https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v${NGINX_EXPORTER_VERSION}/nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz"
    tar xzf "nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz"

    cp nginx-prometheus-exporter /usr/local/bin/
    chown nginx_exporter:nginx_exporter /usr/local/bin/nginx-prometheus-exporter

    rm -rf nginx-prometheus-exporter "nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz"

    # Enable nginx stub_status if not already enabled
    if ! grep -q "stub_status" /etc/nginx/conf.d/* 2>/dev/null; then
        log_info "Enabling Nginx stub_status..."
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
    fi

    cat > /etc/systemd/system/nginx_exporter.service << 'EOF'
[Unit]
Description=Nginx Prometheus Exporter
Wants=network-online.target
After=network-online.target nginx.service

[Service]
User=nginx_exporter
Group=nginx_exporter
Type=simple
ExecStart=/usr/local/bin/nginx-prometheus-exporter \
    --nginx.scrape-uri=http://127.0.0.1:8080/nginx_status

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable nginx_exporter
    systemctl restart nginx_exporter

    log_success "Nginx Exporter installed (port 9113)"
}

#===============================================================================
# ALERTMANAGER INSTALLATION
#===============================================================================

install_alertmanager() {
    if is_alertmanager_installed; then
        log_skip "Alertmanager ${ALERTMANAGER_VERSION} already installed"
        # Ensure directories and user exist
        useradd --no-create-home --shell /bin/false alertmanager 2>/dev/null || true
        mkdir -p /etc/alertmanager/templates /var/lib/alertmanager
        return
    fi

    log_info "Installing Alertmanager ${ALERTMANAGER_VERSION}..."

    # Stop service if running (important for force mode reinstall)
    systemctl stop alertmanager 2>/dev/null || true

    useradd --no-create-home --shell /bin/false alertmanager 2>/dev/null || true

    mkdir -p /etc/alertmanager/templates
    mkdir -p /var/lib/alertmanager

    cd /tmp
    wget -q "https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"
    tar xzf "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"

    cp "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/alertmanager" /usr/local/bin/
    cp "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/amtool" /usr/local/bin/

    chown alertmanager:alertmanager /usr/local/bin/alertmanager /usr/local/bin/amtool

    rm -rf "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64" "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"

    log_success "Alertmanager installed"
}

configure_alertmanager() {
    log_info "Configuring Alertmanager..."

    # Convert starttls to boolean
    if [[ "$SMTP_STARTTLS" == "true" ]]; then
        SMTP_TLS="true"
    else
        SMTP_TLS="false"
    fi

    # Generate email-only alertmanager config
    local alertmanager_config
    read -r -d '' alertmanager_config << ALERTCFG || true
# Alertmanager Configuration
# Auto-generated from global.yaml

global:
  resolve_timeout: 5m
  smtp_smarthost: '${SMTP_HOST}:${SMTP_PORT}'
  smtp_from: '${SMTP_FROM}'
  smtp_auth_username: '${SMTP_USERNAME}'
  smtp_auth_password: '${SMTP_PASSWORD}'
  smtp_require_tls: ${SMTP_TLS}

templates:
  - '/etc/alertmanager/templates/*.tmpl'

route:
  receiver: 'email-alerts'
  group_by: ['alertname', 'instance', 'severity']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    - match:
        severity: critical
      receiver: 'critical-email'
      group_wait: 10s
      repeat_interval: 1h
    - match:
        severity: warning
      receiver: 'warning-email'
      group_wait: 1m
      repeat_interval: 4h

receivers:
  - name: 'email-alerts'
    email_configs:
      - to: '${SMTP_TO}'
        send_resolved: true
        headers:
          Subject: '[ALERT] {{ .Status | toUpper }} - {{ .CommonLabels.alertname }}'

  - name: 'critical-email'
    email_configs:
      - to: '${SMTP_TO}'
        send_resolved: true
        headers:
          Subject: '[CRITICAL] {{ .CommonLabels.alertname }} on {{ .CommonLabels.instance }}'

  - name: 'warning-email'
    email_configs:
      - to: '${SMTP_TO}'
        send_resolved: true
        headers:
          Subject: '[WARNING] {{ .CommonLabels.alertname }} on {{ .CommonLabels.instance }}'

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
ALERTCFG

    # Check and write alertmanager config
    write_config_with_check "/etc/alertmanager/alertmanager.yml" "$alertmanager_config" "Alertmanager config"

    # Copy email template
    sed "s|{{GRAFANA_DOMAIN}}|${GRAFANA_DOMAIN}|g" \
        "${BASE_DIR}/alertmanager/templates/email.tmpl" > /etc/alertmanager/templates/email.tmpl

    chown -R alertmanager:alertmanager /etc/alertmanager /var/lib/alertmanager

    # Generate systemd service
    local service_content
    read -r -d '' service_content << EOF || true
[Unit]
Description=Alertmanager
Wants=network-online.target
After=network-online.target

[Service]
User=alertmanager
Group=alertmanager
Type=simple
ExecStart=/usr/local/bin/alertmanager \\
    --config.file=/etc/alertmanager/alertmanager.yml \\
    --storage.path=/var/lib/alertmanager/ \\
    --web.external-url=https://${GRAFANA_DOMAIN}/alertmanager/

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    if write_config_with_check "/etc/systemd/system/alertmanager.service" "$service_content" "Alertmanager service"; then
        systemctl daemon-reload
    fi

    systemctl enable alertmanager
    systemctl restart alertmanager

    log_success "Alertmanager configured and started"
}

#===============================================================================
# LOKI INSTALLATION
#===============================================================================

install_loki() {
    if is_loki_installed; then
        log_skip "Loki ${LOKI_VERSION} already installed"
        # Ensure directories and user exist
        useradd --no-create-home --shell /bin/false loki 2>/dev/null || true
        mkdir -p /etc/loki /var/lib/loki/{chunks,rules,wal,tsdb-index,tsdb-cache,compactor}
        return
    fi

    log_info "Installing Loki ${LOKI_VERSION}..."

    # Stop service if running (important for force mode reinstall)
    systemctl stop loki 2>/dev/null || true

    useradd --no-create-home --shell /bin/false loki 2>/dev/null || true

    mkdir -p /etc/loki
    mkdir -p /var/lib/loki/{chunks,rules,wal,tsdb-index,tsdb-cache,compactor}

    cd /tmp
    wget -q "https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-amd64.zip"
    unzip -o loki-linux-amd64.zip
    chmod +x loki-linux-amd64
    mv loki-linux-amd64 /usr/local/bin/loki

    rm -f loki-linux-amd64.zip

    log_success "Loki installed"
}

configure_loki() {
    log_info "Configuring Loki..."

    # Update retention in config
    RETENTION_HOURS=$((RETENTION_DAYS * 24))
    local loki_config
    loki_config=$(sed "s/retention_period: 360h/retention_period: ${RETENTION_HOURS}h/g" \
        "${BASE_DIR}/loki/loki-config.yaml")

    # Check and write loki config
    write_config_with_check "/etc/loki/loki-config.yaml" "$loki_config" "Loki config"

    chown -R loki:loki /etc/loki /var/lib/loki

    local service_content
    read -r -d '' service_content << 'EOF' || true
[Unit]
Description=Loki
Wants=network-online.target
After=network-online.target

[Service]
User=loki
Group=loki
Type=simple
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki-config.yaml

Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    if write_config_with_check "/etc/systemd/system/loki.service" "$service_content" "Loki service"; then
        systemctl daemon-reload
    fi

    systemctl enable loki
    systemctl restart loki

    log_success "Loki configured and started"
}

#===============================================================================
# GRAFANA INSTALLATION
#===============================================================================

install_grafana() {
    if is_grafana_installed; then
        log_skip "Grafana already installed"
        return
    fi

    log_info "Installing Grafana..."

    # Add Grafana repository
    wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
    echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list

    apt-get update -qq

    # In force mode, reinstall even if already present
    if [[ "$FORCE_MODE" == "true" ]]; then
        apt-get install -y -qq --reinstall grafana
    else
        apt-get install -y -qq grafana
    fi

    log_success "Grafana installed"
}

configure_grafana() {
    log_info "Configuring Grafana..."

    # Generate secret key only once (preserve across reruns to keep sessions valid)
    local secret_key_file="/etc/grafana/.secret_key"
    if [[ ! -f "$secret_key_file" ]] || [[ "$FORCE_MODE" == "true" ]]; then
        openssl rand -hex 32 > "$secret_key_file"
        chmod 600 "$secret_key_file"
    fi
    local GRAFANA_SECRET_KEY
    GRAFANA_SECRET_KEY=$(cat "$secret_key_file")

    # Generate grafana.ini content
    local grafana_config
    read -r -d '' grafana_config << EOF || true
[server]
protocol = http
http_addr = 127.0.0.1
http_port = 3000
domain = ${GRAFANA_DOMAIN}
root_url = https://${GRAFANA_DOMAIN}/
serve_from_sub_path = false

[database]
type = sqlite3

[session]
provider = file

[security]
admin_user = admin
admin_password = ${GRAFANA_ADMIN_PASS}
secret_key = ${GRAFANA_SECRET_KEY}
disable_gravatar = true

[users]
allow_sign_up = false
allow_org_create = false
auto_assign_org = true
auto_assign_org_role = Viewer

[auth.anonymous]
enabled = false

[unified_alerting]
enabled = true

[smtp]
enabled = true
host = ${SMTP_HOST}:${SMTP_PORT}
user = ${SMTP_USERNAME}
password = ${SMTP_PASSWORD}
from_address = ${SMTP_FROM}
from_name = Grafana Alerts
startTLS_policy = MandatoryStartTLS

[log]
mode = console file
level = info

[log.file]
log_rotate = true
max_lines = 1000000
max_size_shift = 28
daily_rotate = true
max_days = 7
EOF

    # Check and write grafana.ini (note: contains credentials - diff will show them)
    write_config_with_check "/etc/grafana/grafana.ini" "$grafana_config" "Grafana config (grafana.ini)"

    # Copy provisioning files
    mkdir -p /etc/grafana/provisioning/datasources
    mkdir -p /etc/grafana/provisioning/dashboards
    mkdir -p /var/lib/grafana/dashboards

    # Check and copy datasources
    local datasources_content
    datasources_content=$(cat "${BASE_DIR}/grafana/provisioning/datasources/datasources.yaml")
    write_config_with_check "/etc/grafana/provisioning/datasources/datasources.yaml" "$datasources_content" "Grafana datasources"

    # Copy dashboards provisioning and dashboard files
    cp "${BASE_DIR}/grafana/provisioning/dashboards/dashboards.yaml" /etc/grafana/provisioning/dashboards/
    cp "${BASE_DIR}/grafana/dashboards/"*.json /var/lib/grafana/dashboards/

    chown -R grafana:grafana /etc/grafana /var/lib/grafana

    systemctl daemon-reload
    systemctl enable grafana-server
    systemctl restart grafana-server

    log_success "Grafana configured and started"
}

#===============================================================================
# NGINX CONFIGURATION
#===============================================================================

configure_nginx() {
    log_info "Configuring Nginx..."

    # Create/update htpasswd files (always update to reflect config changes)
    htpasswd -cb /etc/nginx/.htpasswd_prometheus "$PROMETHEUS_USER" "$PROMETHEUS_PASS" 2>/dev/null
    htpasswd -cb /etc/nginx/.htpasswd_loki "$LOKI_USER" "$LOKI_PASS" 2>/dev/null

    # Create certbot webroot
    mkdir -p /var/www/certbot

    # Only create initial HTTP config if SSL config doesn't exist yet or force mode
    # (setup_ssl will handle the full SSL config)
    if [[ "$FORCE_MODE" == "true" ]] || [[ ! -f "/etc/letsencrypt/live/${GRAFANA_DOMAIN}/fullchain.pem" ]]; then
        # Create initial nginx config (HTTP only for certbot)
        cat > /etc/nginx/sites-available/observability << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${GRAFANA_DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 200 'Waiting for SSL certificate...';
        add_header Content-Type text/plain;
    }
}
EOF
    fi

    ln -sf /etc/nginx/sites-available/observability /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    nginx -t && systemctl reload nginx

    log_success "Nginx initial configuration complete"
}

setup_ssl() {
    log_info "Setting up SSL certificate..."

    local need_cert=false
    local cert_file="/etc/letsencrypt/live/${GRAFANA_DOMAIN}/fullchain.pem"

    # Check if certificate exists and is valid
    if [[ ! -f "$cert_file" ]]; then
        log_info "SSL certificate not found, obtaining new certificate..."
        need_cert=true
    elif ! is_ssl_valid "$GRAFANA_DOMAIN"; then
        log_info "SSL certificate expired or expiring soon, renewing..."
        need_cert=true
    else
        log_skip "SSL certificate is valid"
    fi

    if [[ "$need_cert" == "true" ]]; then
        # Ensure nginx is serving HTTP for certbot challenge
        if ! grep -q "acme-challenge" /etc/nginx/sites-available/observability 2>/dev/null; then
            # Create temporary HTTP-only config for certbot
            cat > /etc/nginx/sites-available/observability << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${GRAFANA_DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 200 'Waiting for SSL certificate...';
        add_header Content-Type text/plain;
    }
}
EOF
            nginx -t && systemctl reload nginx
        fi

        # Get/renew certificate
        # Only use --force-renewal in force mode to avoid Let's Encrypt rate limits
        local certbot_args="--webroot -w /var/www/certbot -d ${GRAFANA_DOMAIN} --email ${LETSENCRYPT_EMAIL} --agree-tos --non-interactive --expand"
        if [[ "$FORCE_MODE" == "true" ]]; then
            certbot_args="$certbot_args --force-renewal"
        fi

        if ! certbot certonly $certbot_args; then
            log_warn "Failed to obtain SSL certificate. Continuing without HTTPS..."
            return
        fi
        log_success "SSL certificate obtained/renewed"
    fi

    # Install full nginx config with SSL (always update in case config changed)
    sed -e "s|{{GRAFANA_DOMAIN}}|${GRAFANA_DOMAIN}|g" \
        "${BASE_DIR}/nginx/observability.conf.template" > /etc/nginx/sites-available/observability

    nginx -t && systemctl reload nginx

    # Setup auto-renewal
    systemctl enable certbot.timer
    systemctl start certbot.timer

    log_success "SSL certificate configured"
}

#===============================================================================
# FINAL CONFIGURATION
#===============================================================================

final_setup() {
    log_info "Final setup..."

    # Wait for services to be ready
    sleep 5

    # Verify all services are running
    for service in prometheus node_exporter alertmanager loki grafana-server nginx; do
        if systemctl is-active --quiet "$service"; then
            log_success "$service is running"
        else
            log_warn "$service is not running"
        fi
    done

    # Print summary
    echo ""
    echo "=========================================="
    echo -e "${GREEN}Observability Stack Setup Complete!${NC}"
    echo "=========================================="
    echo ""
    echo "Access Grafana at: https://${GRAFANA_DOMAIN}"
    echo ""
    echo "Default Grafana login:"
    echo "  Username: admin"
    echo "  Password: ${GRAFANA_ADMIN_PASS}"
    echo ""
    echo "Protected endpoints (use configured basic auth):"
    echo "  Prometheus: https://${GRAFANA_DOMAIN}/prometheus/"
    echo "  Loki: https://${GRAFANA_DOMAIN}/loki/"
    echo "  Alertmanager: https://${GRAFANA_DOMAIN}/alertmanager/"
    echo ""
    echo "Important next steps:"
    echo "1. Change the Grafana admin password after first login"
    echo "2. Run the agent setup script on each monitored host"
    echo "3. Verify alerts are working by checking test notifications"
    echo ""
}

#===============================================================================
# MAIN
#===============================================================================

validate_config() {
    local missing=""

    [[ -z "${GRAFANA_DOMAIN:-}" ]] && missing="$missing GRAFANA_DOMAIN"
    [[ -z "${LETSENCRYPT_EMAIL:-}" ]] && missing="$missing LETSENCRYPT_EMAIL"
    [[ -z "${GRAFANA_ADMIN_PASS:-}" ]] && missing="$missing GRAFANA_ADMIN_PASS"
    [[ -z "${PROMETHEUS_USER:-}" ]] && missing="$missing PROMETHEUS_USER"
    [[ -z "${PROMETHEUS_PASS:-}" ]] && missing="$missing PROMETHEUS_PASS"

    if [[ -n "$missing" ]]; then
        log_error "Missing required configuration values:$missing"
    fi

    log_success "Configuration validated"
}

main() {
    # Handle uninstall mode
    if [[ "$UNINSTALL_MODE" == "true" ]]; then
        run_uninstall
        exit 0
    fi

    echo ""
    echo "=========================================="
    echo "Observability Stack Setup for Debian 13"
    echo "=========================================="
    if [[ "$FORCE_MODE" == "true" ]]; then
        echo -e "${YELLOW}>>> FORCE MODE: Reinstalling everything from scratch <<<${NC}"
    fi
    echo ""

    check_root
    check_config
    parse_config
    validate_config

    # Create backup before making changes (if configs exist)
    if [[ -f "/etc/prometheus/prometheus.yml" ]] || [[ -f "/etc/grafana/grafana.ini" ]]; then
        create_backup
    fi

    prepare_system
    configure_firewall

    install_prometheus
    install_node_exporter
    install_nginx_exporter
    install_alertmanager
    install_loki
    install_grafana

    configure_prometheus
    configure_alertmanager
    configure_loki
    configure_grafana
    configure_nginx
    setup_ssl

    final_setup
}

# Run main
main "$@"
