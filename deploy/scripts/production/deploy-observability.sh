#!/bin/bash
################################################################################
# CHOM Observability Stack - Production Deployment Script
#
# Purpose: Deploy Prometheus, Grafana, Loki, Alertmanager to production VPS
# Features: Armored, Safe, Idempotent
#
# Usage: ./deploy-observability.sh [--dry-run] [--rollback] [--force]
#
# Environment Variables:
#   DOMAIN               - Domain name (default: mentat.arewel.com)
#   SSL_EMAIL           - Email for Let's Encrypt (default: admin@arewel.com)
#   GRAFANA_ADMIN_PASS  - Grafana admin password (auto-generated if not set)
#   SKIP_BACKUPS        - Skip backup creation (default: false)
################################################################################

set -euo pipefail

################################################################################
# Configuration
################################################################################

# Script metadata
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly STATE_DIR="/var/lib/chom-deploy"
readonly STATE_FILE="${STATE_DIR}/observability-state.json"
readonly LOG_DIR="/var/log/chom-deploy"
readonly LOG_FILE="${LOG_DIR}/observability-$(date +%Y%m%d-%H%M%S).log"
readonly BACKUP_DIR="/var/backups/chom"

# Deployment configuration
readonly DOMAIN="${DOMAIN:-mentat.arewel.com}"
readonly SSL_EMAIL="${SSL_EMAIL:-admin@arewel.com}"
readonly SKIP_BACKUPS="${SKIP_BACKUPS:-false}"

# Service versions
readonly PROMETHEUS_VERSION="3.8.1"
readonly LOKI_VERSION="3.6.3"
readonly GRAFANA_VERSION="latest"
readonly ALERTMANAGER_VERSION="0.27.0"
readonly NODE_EXPORTER_VERSION="1.10.2"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Flags
DRY_RUN=false
ROLLBACK=false
FORCE=false

################################################################################
# Utility Functions
################################################################################

log_info() {
    local msg="$1"
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $msg" | tee -a "$LOG_FILE"
}

log_warn() {
    local msg="$1"
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $msg" | tee -a "$LOG_FILE"
}

log_error() {
    local msg="$1"
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $msg" | tee -a "$LOG_FILE"
}

log_debug() {
    local msg="$1"
    echo -e "${BLUE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $msg" >> "$LOG_FILE"
}

# Execute command with dry-run support
execute() {
    local cmd="$1"
    log_debug "Executing: $cmd"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would execute: $cmd"
        return 0
    fi

    if eval "$cmd"; then
        log_debug "Command succeeded: $cmd"
        return 0
    else
        local exit_code=$?
        log_error "Command failed (exit code $exit_code): $cmd"
        return $exit_code
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if service is running
service_running() {
    local service="$1"
    systemctl is-active --quiet "$service" 2>/dev/null
}

# Save deployment state
save_state() {
    local key="$1"
    local value="$2"

    if [ "$DRY_RUN" = true ]; then
        return 0
    fi

    mkdir -p "$STATE_DIR"

    # Initialize state file if it doesn't exist
    if [ ! -f "$STATE_FILE" ]; then
        echo '{}' > "$STATE_FILE"
    fi

    # Update state using jq
    local temp_file=$(mktemp)
    jq --arg key "$key" --arg value "$value" '.[$key] = $value' "$STATE_FILE" > "$temp_file"
    mv "$temp_file" "$STATE_FILE"

    log_debug "State saved: $key = $value"
}

# Get deployment state
get_state() {
    local key="$1"
    local default="${2:-}"

    if [ ! -f "$STATE_FILE" ]; then
        echo "$default"
        return
    fi

    local value=$(jq -r --arg key "$key" '.[$key] // empty' "$STATE_FILE")
    if [ -z "$value" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Check if step was completed
step_completed() {
    local step="$1"
    local completed=$(get_state "$step" "false")
    [ "$completed" = "true" ]
}

# Mark step as completed
mark_step_completed() {
    local step="$1"
    save_state "$step" "true"
    save_state "${step}_timestamp" "$(date -Iseconds)"
}

################################################################################
# Pre-flight Checks
################################################################################

preflight_checks() {
    log_info "Running pre-flight checks..."

    # Check if running as root
    if [ "$EUID" -ne 0 ] && [ "$DRY_RUN" = false ]; then
        log_error "This script must be run as root"
        return 1
    fi

    # Check OS version
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log_info "Detected OS: $PRETTY_NAME"

        if [[ "$ID" != "debian" ]]; then
            log_warn "This script is designed for Debian. Your OS: $ID"
            if [ "$FORCE" = false ]; then
                log_error "Use --force to proceed anyway"
                return 1
            fi
        fi
    fi

    # Check system resources
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    local total_disk=$(df -m / | awk 'NR==2 {print $4}')

    log_info "System resources: ${total_mem}MB RAM, ${total_disk}MB disk available"

    if [ "$total_mem" -lt 1800 ]; then
        log_warn "Low memory: ${total_mem}MB (minimum 2GB recommended)"
        if [ "$FORCE" = false ]; then
            log_error "Use --force to proceed anyway"
            return 1
        fi
    fi

    if [ "$total_disk" -lt 18000 ]; then
        log_warn "Low disk space: ${total_disk}MB (minimum 20GB recommended)"
        if [ "$FORCE" = false ]; then
            log_error "Use --force to proceed anyway"
            return 1
        fi
    fi

    # Check DNS resolution
    if ! host "$DOMAIN" >/dev/null 2>&1; then
        log_error "DNS resolution failed for $DOMAIN"
        log_error "Please configure DNS before deployment"
        return 1
    fi

    local resolved_ip=$(host "$DOMAIN" | awk '/has address/ {print $4}' | head -1)
    local server_ip=$(curl -s ifconfig.me)

    if [ "$resolved_ip" != "$server_ip" ]; then
        log_warn "DNS mismatch: $DOMAIN resolves to $resolved_ip, but server IP is $server_ip"
        if [ "$FORCE" = false ]; then
            log_error "Please fix DNS or use --force to proceed"
            return 1
        fi
    else
        log_info "DNS correctly configured: $DOMAIN → $server_ip"
    fi

    # Check required commands
    local required_commands=("systemctl" "curl" "wget" "tar" "jq")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            log_error "Required command not found: $cmd"
            return 1
        fi
    done

    # Check for port conflicts
    local required_ports=(80 443 9090 3000 3100 9093)
    for port in "${required_ports[@]}"; do
        if netstat -tuln | grep -q ":$port "; then
            log_warn "Port $port is already in use"
            if [ "$FORCE" = false ]; then
                log_error "Use --force to proceed anyway"
                return 1
            fi
        fi
    done

    log_info "Pre-flight checks passed ✓"
    return 0
}

################################################################################
# Backup Functions
################################################################################

create_backup() {
    if [ "$SKIP_BACKUPS" = "true" ]; then
        log_warn "Skipping backup creation (SKIP_BACKUPS=true)"
        return 0
    fi

    if step_completed "backup_created"; then
        log_info "Backup already created, skipping"
        return 0
    fi

    log_info "Creating system backup..."

    execute "mkdir -p $BACKUP_DIR"

    local backup_file="${BACKUP_DIR}/pre-deploy-$(date +%Y%m%d-%H%M%S).tar.gz"

    # Backup existing configurations if they exist
    local backup_paths=()
    [ -d /etc/prometheus ] && backup_paths+=("/etc/prometheus")
    [ -d /etc/grafana ] && backup_paths+=("/etc/grafana")
    [ -d /etc/loki ] && backup_paths+=("/etc/loki")
    [ -d /etc/alertmanager ] && backup_paths+=("/etc/alertmanager")
    [ -d /var/lib/grafana ] && backup_paths+=("/var/lib/grafana")

    if [ ${#backup_paths[@]} -gt 0 ]; then
        execute "tar -czf $backup_file ${backup_paths[*]}"
        log_info "Backup created: $backup_file"
        save_state "last_backup" "$backup_file"
    else
        log_info "No existing configurations to backup"
    fi

    mark_step_completed "backup_created"
    return 0
}

################################################################################
# Installation Functions
################################################################################

install_dependencies() {
    if step_completed "dependencies_installed"; then
        log_info "Dependencies already installed, skipping"
        return 0
    fi

    log_info "Installing system dependencies..."

    execute "apt-get update -qq"
    execute "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        curl wget tar gzip \
        apt-transport-https ca-certificates \
        gnupg lsb-release \
        jq \
        nginx certbot python3-certbot-nginx \
        ufw fail2ban \
        htop iotop \
        net-tools"

    mark_step_completed "dependencies_installed"
    log_info "Dependencies installed ✓"
    return 0
}

install_prometheus() {
    if step_completed "prometheus_installed"; then
        log_info "Prometheus already installed, skipping"
        return 0
    fi

    log_info "Installing Prometheus ${PROMETHEUS_VERSION}..."

    execute "useradd --system --no-create-home --shell /bin/false prometheus || true"
    execute "mkdir -p /etc/prometheus /var/lib/prometheus"

    local download_url="https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"

    execute "wget -q -O /tmp/prometheus.tar.gz $download_url"
    execute "tar -xzf /tmp/prometheus.tar.gz -C /tmp/"
    execute "cp /tmp/prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus /usr/local/bin/"
    execute "cp /tmp/prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool /usr/local/bin/"
    execute "cp -r /tmp/prometheus-${PROMETHEUS_VERSION}.linux-amd64/consoles /etc/prometheus/"
    execute "cp -r /tmp/prometheus-${PROMETHEUS_VERSION}.linux-amd64/console_libraries /etc/prometheus/"

    execute "chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus"
    execute "chmod -R 755 /etc/prometheus"

    # Create systemd service
    cat > /etc/systemd/system/prometheus.service <<'EOF'
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/prometheus/ \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --web.enable-lifecycle

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    execute "systemctl daemon-reload"

    mark_step_completed "prometheus_installed"
    log_info "Prometheus installed ✓"
    return 0
}

install_grafana() {
    if step_completed "grafana_installed"; then
        log_info "Grafana already installed, skipping"
        return 0
    fi

    log_info "Installing Grafana..."

    execute "wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key"
    execute "echo \"deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main\" | tee /etc/apt/sources.list.d/grafana.list"
    execute "apt-get update -qq"
    execute "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq grafana"

    mark_step_completed "grafana_installed"
    log_info "Grafana installed ✓"
    return 0
}

install_loki() {
    if step_completed "loki_installed"; then
        log_info "Loki already installed, skipping"
        return 0
    fi

    log_info "Installing Loki ${LOKI_VERSION}..."

    execute "useradd --system --no-create-home --shell /bin/false loki || true"
    execute "mkdir -p /etc/loki /var/lib/loki"

    local download_url="https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-amd64.zip"

    execute "wget -q -O /tmp/loki.zip $download_url"
    execute "unzip -q -o /tmp/loki.zip -d /tmp/"
    execute "cp /tmp/loki-linux-amd64 /usr/local/bin/loki"
    execute "chmod +x /usr/local/bin/loki"

    execute "chown -R loki:loki /etc/loki /var/lib/loki"

    # Create systemd service
    cat > /etc/systemd/system/loki.service <<'EOF'
[Unit]
Description=Loki
After=network.target

[Service]
User=loki
Group=loki
Type=simple
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki.yml

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    execute "systemctl daemon-reload"

    mark_step_completed "loki_installed"
    log_info "Loki installed ✓"
    return 0
}

install_alertmanager() {
    if step_completed "alertmanager_installed"; then
        log_info "Alertmanager already installed, skipping"
        return 0
    fi

    log_info "Installing Alertmanager ${ALERTMANAGER_VERSION}..."

    execute "useradd --system --no-create-home --shell /bin/false alertmanager || true"
    execute "mkdir -p /etc/alertmanager /var/lib/alertmanager"

    local download_url="https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"

    execute "wget -q -O /tmp/alertmanager.tar.gz $download_url"
    execute "tar -xzf /tmp/alertmanager.tar.gz -C /tmp/"
    execute "cp /tmp/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/alertmanager /usr/local/bin/"
    execute "cp /tmp/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/amtool /usr/local/bin/"

    execute "chown -R alertmanager:alertmanager /etc/alertmanager /var/lib/alertmanager"

    # Create systemd service
    cat > /etc/systemd/system/alertmanager.service <<'EOF'
[Unit]
Description=Alertmanager
After=network.target

[Service]
User=alertmanager
Group=alertmanager
Type=simple
ExecStart=/usr/local/bin/alertmanager \
    --config.file=/etc/alertmanager/alertmanager.yml \
    --storage.path=/var/lib/alertmanager/

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    execute "systemctl daemon-reload"

    mark_step_completed "alertmanager_installed"
    log_info "Alertmanager installed ✓"
    return 0
}

install_node_exporter() {
    if step_completed "node_exporter_installed"; then
        log_info "Node Exporter already installed, skipping"
        return 0
    fi

    log_info "Installing Node Exporter ${NODE_EXPORTER_VERSION}..."

    execute "useradd --system --no-create-home --shell /bin/false node_exporter || true"

    local download_url="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"

    execute "wget -q -O /tmp/node_exporter.tar.gz $download_url"
    execute "tar -xzf /tmp/node_exporter.tar.gz -C /tmp/"
    execute "cp /tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/"

    # Create systemd service
    cat > /etc/systemd/system/node_exporter.service <<'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    execute "systemctl daemon-reload"

    mark_step_completed "node_exporter_installed"
    log_info "Node Exporter installed ✓"
    return 0
}

################################################################################
# Configuration Functions
################################################################################

configure_prometheus() {
    if step_completed "prometheus_configured"; then
        log_info "Prometheus already configured, skipping"
        return 0
    fi

    log_info "Configuring Prometheus..."

    cat > /etc/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'production'
    replica: '1'

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']

rule_files:
  - "/etc/prometheus/rules/*.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'grafana'
    static_configs:
      - targets: ['localhost:3000']

  - job_name: 'loki'
    static_configs:
      - targets: ['localhost:3100']

  - job_name: 'alertmanager'
    static_configs:
      - targets: ['localhost:9093']
EOF

    execute "mkdir -p /etc/prometheus/rules"
    execute "chown -R prometheus:prometheus /etc/prometheus"

    mark_step_completed "prometheus_configured"
    log_info "Prometheus configured ✓"
    return 0
}

configure_grafana() {
    if step_completed "grafana_configured"; then
        log_info "Grafana already configured, skipping"
        return 0
    fi

    log_info "Configuring Grafana..."

    # Generate admin password if not provided
    if [ -z "${GRAFANA_ADMIN_PASS:-}" ]; then
        GRAFANA_ADMIN_PASS=$(openssl rand -base64 32)
        log_info "Generated Grafana admin password"
    fi

    # Save credentials
    cat > /root/.observability-credentials <<EOF
# Observability Stack Credentials
# Generated: $(date -Iseconds)

GRAFANA_URL=https://${DOMAIN}
GRAFANA_USERNAME=admin
GRAFANA_PASSWORD=${GRAFANA_ADMIN_PASS}

PROMETHEUS_URL=https://${DOMAIN}:9090
LOKI_URL=https://${DOMAIN}:3100
ALERTMANAGER_URL=https://${DOMAIN}:9093
EOF

    execute "chmod 600 /root/.observability-credentials"

    # Configure Grafana
    execute "sed -i 's/;admin_password =.*/admin_password = ${GRAFANA_ADMIN_PASS}/' /etc/grafana/grafana.ini"
    execute "sed -i 's/;domain =.*/domain = ${DOMAIN}/' /etc/grafana/grafana.ini"
    execute "sed -i 's/;root_url =.*/root_url = https:\/\/${DOMAIN}/' /etc/grafana/grafana.ini"

    mark_step_completed "grafana_configured"
    save_state "grafana_admin_pass" "$GRAFANA_ADMIN_PASS"
    log_info "Grafana configured ✓"
    return 0
}

configure_loki() {
    if step_completed "loki_configured"; then
        log_info "Loki already configured, skipping"
        return 0
    fi

    log_info "Configuring Loki..."

    cat > /etc/loki/loki.yml <<'EOF'
auth_enabled: false

server:
  http_listen_port: 3100

common:
  path_prefix: /var/lib/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/loki/chunks
      rules_directory: /var/lib/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

ruler:
  alertmanager_url: http://localhost:9093

limits_config:
  retention_period: 720h  # 30 days
EOF

    execute "chown -R loki:loki /etc/loki"

    mark_step_completed "loki_configured"
    log_info "Loki configured ✓"
    return 0
}

configure_alertmanager() {
    if step_completed "alertmanager_configured"; then
        log_info "Alertmanager already configured, skipping"
        return 0
    fi

    log_info "Configuring Alertmanager..."

    cat > /etc/alertmanager/alertmanager.yml <<EOF
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'cluster', 'severity']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'email-notifications'

receivers:
  - name: 'email-notifications'
    email_configs:
      - to: 'ops@arewel.com'
        from: 'alertmanager@${DOMAIN}'
        smarthost: 'smtp-relay.brevo.com:587'
        auth_username: '9e9603001@smtp-brevo.com'
        auth_password: ''  # Configure after deployment
        require_tls: true

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'cluster']
EOF

    execute "chown -R alertmanager:alertmanager /etc/alertmanager"

    mark_step_completed "alertmanager_configured"
    log_info "Alertmanager configured ✓"
    return 0
}

configure_firewall() {
    if step_completed "firewall_configured"; then
        log_info "Firewall already configured, skipping"
        return 0
    fi

    log_info "Configuring firewall..."

    execute "ufw --force reset"
    execute "ufw default deny incoming"
    execute "ufw default allow outgoing"

    # Allow SSH (important!)
    execute "ufw allow ssh"

    # Allow HTTP/HTTPS
    execute "ufw allow 80/tcp"
    execute "ufw allow 443/tcp"

    # Allow from CHOM server
    execute "ufw allow from 51.77.150.96 to any port 9090 proto tcp comment 'Prometheus from CHOM'"
    execute "ufw allow from 51.77.150.96 to any port 3100 proto tcp comment 'Loki from CHOM'"
    execute "ufw allow from 51.77.150.96 to any port 9093 proto tcp comment 'Alertmanager from CHOM'"

    execute "ufw --force enable"

    mark_step_completed "firewall_configured"
    log_info "Firewall configured ✓"
    return 0
}

configure_nginx() {
    if step_completed "nginx_configured"; then
        log_info "Nginx already configured, skipping"
        return 0
    fi

    log_info "Configuring Nginx..."

    cat > /etc/nginx/sites-available/observability <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location /prometheus/ {
        proxy_pass http://localhost:9090/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location /loki/ {
        proxy_pass http://localhost:3100/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

    execute "ln -sf /etc/nginx/sites-available/observability /etc/nginx/sites-enabled/"
    execute "rm -f /etc/nginx/sites-enabled/default"
    execute "nginx -t"
    execute "systemctl reload nginx"

    mark_step_completed "nginx_configured"
    log_info "Nginx configured ✓"
    return 0
}

setup_ssl() {
    if step_completed "ssl_configured"; then
        log_info "SSL already configured, skipping"
        return 0
    fi

    log_info "Setting up SSL with Let's Encrypt..."

    execute "certbot --nginx -d ${DOMAIN} --non-interactive --agree-tos --email ${SSL_EMAIL} --redirect"

    mark_step_completed "ssl_configured"
    log_info "SSL configured ✓"
    return 0
}

################################################################################
# Service Management
################################################################################

start_services() {
    log_info "Starting services..."

    local services=("prometheus" "grafana-server" "loki" "alertmanager" "node_exporter" "nginx")

    for service in "${services[@]}"; do
        if service_running "$service"; then
            log_info "Service $service already running"
        else
            log_info "Starting $service..."
            execute "systemctl enable $service"
            execute "systemctl start $service"

            # Wait for service to start
            sleep 2

            if service_running "$service"; then
                log_info "Service $service started ✓"
            else
                log_error "Service $service failed to start"
                execute "systemctl status $service"
                return 1
            fi
        fi
    done

    log_info "All services started ✓"
    return 0
}

################################################################################
# Verification Functions
################################################################################

verify_deployment() {
    log_info "Verifying deployment..."

    local failed=0

    # Check services
    local services=("prometheus" "grafana-server" "loki" "alertmanager" "node_exporter")
    for service in "${services[@]}"; do
        if service_running "$service"; then
            log_info "✓ Service $service is running"
        else
            log_error "✗ Service $service is not running"
            failed=$((failed + 1))
        fi
    done

    # Check HTTP endpoints
    local endpoints=(
        "http://localhost:9090/-/healthy:Prometheus"
        "http://localhost:3000/api/health:Grafana"
        "http://localhost:3100/ready:Loki"
        "http://localhost:9093/-/healthy:Alertmanager"
        "http://localhost:9100/metrics:Node Exporter"
    )

    for endpoint in "${endpoints[@]}"; do
        local url=$(echo "$endpoint" | cut -d: -f1-2)
        local name=$(echo "$endpoint" | cut -d: -f3)

        if curl -sf "$url" >/dev/null 2>&1; then
            log_info "✓ $name is healthy"
        else
            log_error "✗ $name health check failed"
            failed=$((failed + 1))
        fi
    done

    # Check HTTPS
    if curl -sf "https://${DOMAIN}" >/dev/null 2>&1; then
        log_info "✓ HTTPS is working"
    else
        log_warn "✗ HTTPS check failed (may take a few moments to propagate)"
    fi

    if [ $failed -eq 0 ]; then
        log_info "Deployment verification passed ✓"
        return 0
    else
        log_error "Deployment verification failed: $failed checks failed"
        return 1
    fi
}

################################################################################
# Rollback Functions
################################################################################

rollback_deployment() {
    log_warn "Rolling back deployment..."

    local backup_file=$(get_state "last_backup")

    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        log_error "No backup found to restore"
        return 1
    fi

    log_info "Restoring from backup: $backup_file"

    # Stop services
    local services=("prometheus" "grafana-server" "loki" "alertmanager" "node_exporter")
    for service in "${services[@]}"; do
        execute "systemctl stop $service || true"
    done

    # Restore backup
    execute "tar -xzf $backup_file -C /"

    # Restart services
    for service in "${services[@]}"; do
        execute "systemctl start $service || true"
    done

    # Clear deployment state
    execute "rm -f $STATE_FILE"

    log_info "Rollback completed"
    return 0
}

################################################################################
# Main Deployment Flow
################################################################################

deploy() {
    log_info "=========================================="
    log_info "CHOM Observability Stack Deployment"
    log_info "Version: $SCRIPT_VERSION"
    log_info "Domain: $DOMAIN"
    log_info "=========================================="

    # Pre-flight checks
    preflight_checks || return 1

    # Backup
    create_backup || return 1

    # Install
    install_dependencies || return 1
    install_prometheus || return 1
    install_grafana || return 1
    install_loki || return 1
    install_alertmanager || return 1
    install_node_exporter || return 1

    # Configure
    configure_prometheus || return 1
    configure_grafana || return 1
    configure_loki || return 1
    configure_alertmanager || return 1
    configure_firewall || return 1
    configure_nginx || return 1
    setup_ssl || return 1

    # Start services
    start_services || return 1

    # Verify
    verify_deployment || return 1

    # Save completion
    mark_step_completed "deployment_complete"
    save_state "deployment_version" "$SCRIPT_VERSION"
    save_state "deployment_timestamp" "$(date -Iseconds)"

    log_info "=========================================="
    log_info "Deployment completed successfully!"
    log_info "=========================================="
    log_info ""
    log_info "Access your services:"
    log_info "  Grafana:       https://${DOMAIN}"
    log_info "  Prometheus:    https://${DOMAIN}/prometheus"
    log_info "  Loki:          https://${DOMAIN}/loki"
    log_info ""
    log_info "Credentials saved to: /root/.observability-credentials"
    log_info "Log file: $LOG_FILE"
    log_info ""

    return 0
}

################################################################################
# Entry Point
################################################################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --rollback)
                ROLLBACK=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --help|-h)
                cat <<EOF
Usage: $0 [OPTIONS]

Options:
    --dry-run       Simulate deployment without making changes
    --rollback      Rollback to previous state
    --force         Force deployment even if checks fail
    --help, -h      Show this help message

Environment Variables:
    DOMAIN               Domain name (default: mentat.arewel.com)
    SSL_EMAIL           Email for Let's Encrypt (default: admin@arewel.com)
    GRAFANA_ADMIN_PASS  Grafana admin password (auto-generated if not set)
    SKIP_BACKUPS        Skip backup creation (default: false)

Examples:
    # Normal deployment
    ./deploy-observability.sh

    # Dry run
    ./deploy-observability.sh --dry-run

    # Force deployment
    DOMAIN=custom.domain.com ./deploy-observability.sh --force

    # Rollback
    ./deploy-observability.sh --rollback
EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Create log directory
    mkdir -p "$LOG_DIR"

    # Execute rollback or deployment
    if [ "$ROLLBACK" = true ]; then
        rollback_deployment
        exit $?
    else
        deploy
        exit $?
    fi
}

# Run main function
main "$@"
