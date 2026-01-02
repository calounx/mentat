#!/bin/bash
#===============================================================================
# Monitored Host Installation
#
# Installs monitoring agents on existing servers:
# - Auto-detects installed services (nginx, mysql, php-fpm, fail2ban)
# - Installs appropriate exporters for detected services
# - Supports both Promtail and Grafana Alloy for log collection
# - Minimal footprint with complete monitoring coverage
#
# Exporter Ports (standard):
# - node_exporter:    9100
# - nginx_exporter:   9113
# - mysqld_exporter:  9104
# - phpfpm_exporter:  9253
# - fail2ban_exporter:9191
# - promtail:         9080 (if using Promtail)
# - alloy:            12345 (if using Alloy)
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
STACK_DIR="$(dirname "$DEPLOY_DIR")"

# Telemetry collector choice: alloy (recommended) or promtail (legacy)
# Alloy is the modern unified collector that replaces Promtail
# Set TELEMETRY_COLLECTOR=promtail to use the legacy log shipper
TELEMETRY_COLLECTOR="${TELEMETRY_COLLECTOR:-alloy}"

# Versions (can be overridden)
NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-1.7.0}"
PROMTAIL_VERSION="${PROMTAIL_VERSION:-3.0.0}"
ALLOY_VERSION="${ALLOY_VERSION:-1.5.1}"
NGINX_EXPORTER_VERSION="${NGINX_EXPORTER_VERSION:-1.1.0}"
MYSQLD_EXPORTER_VERSION="${MYSQLD_EXPORTER_VERSION:-0.15.1}"
PHPFPM_EXPORTER_VERSION="${PHPFPM_EXPORTER_VERSION:-0.6.0}"

# Standard exporter ports
readonly NODE_EXPORTER_PORT=9100
readonly NGINX_EXPORTER_PORT=9113
readonly MYSQLD_EXPORTER_PORT=9104
readonly PHPFPM_EXPORTER_PORT=9253
readonly FAIL2BAN_EXPORTER_PORT=9191
readonly PROMTAIL_PORT=9080
readonly ALLOY_PORT=12345

# Array to hold detected services
declare -a DETECTED_SERVICES=()

#===============================================================================
# Service Auto-Detection
#===============================================================================

detect_installed_services() {
    log_step "Auto-detecting installed services..."

    DETECTED_SERVICES=()

    # Always install node_exporter for system metrics
    DETECTED_SERVICES+=("node_exporter")
    log_info "  [+] node_exporter (always installed for system metrics)"

    # Check for Nginx
    if command -v nginx &>/dev/null || systemctl is-active --quiet nginx 2>/dev/null; then
        DETECTED_SERVICES+=("nginx_exporter")
        log_info "  [+] nginx_exporter (nginx detected)"
    fi

    # Check for MySQL/MariaDB
    if command -v mysql &>/dev/null || systemctl is-active --quiet mariadb 2>/dev/null || systemctl is-active --quiet mysql 2>/dev/null; then
        DETECTED_SERVICES+=("mysqld_exporter")
        log_info "  [+] mysqld_exporter (mysql/mariadb detected)"
    fi

    # Check for PHP-FPM
    if pgrep -x "php-fpm" &>/dev/null || ls /run/php/php*-fpm.sock 2>/dev/null | head -1 &>/dev/null; then
        DETECTED_SERVICES+=("phpfpm_exporter")
        log_info "  [+] phpfpm_exporter (php-fpm detected)"
    elif systemctl list-units --type=service --state=running 2>/dev/null | grep -q "php.*-fpm"; then
        DETECTED_SERVICES+=("phpfpm_exporter")
        log_info "  [+] phpfpm_exporter (php-fpm service detected)"
    fi

    # Check for Fail2ban
    if command -v fail2ban-client &>/dev/null || systemctl is-active --quiet fail2ban 2>/dev/null; then
        DETECTED_SERVICES+=("fail2ban_exporter")
        log_info "  [+] fail2ban_exporter (fail2ban detected)"
    fi

    # Always add telemetry collector
    case "${TELEMETRY_COLLECTOR,,}" in
        alloy)
            DETECTED_SERVICES+=("alloy")
            log_info "  [+] alloy (telemetry collector)"
            ;;
        *)
            DETECTED_SERVICES+=("promtail")
            log_info "  [+] promtail (log collector)"
            ;;
    esac

    log_success "Detected ${#DETECTED_SERVICES[@]} services to monitor"
    log_info "Services: ${DETECTED_SERVICES[*]}"
}

#===============================================================================
# Main Installation Function
#===============================================================================

install_monitored_host() {
    log_step "Installing Monitored Host components..."

    # Validate required configuration
    validate_monitored_config

    # Install system packages
    install_system_packages

    # Auto-detect services if not already done
    if [[ ${#DETECTED_SERVICES[@]} -eq 0 ]]; then
        detect_installed_services
    fi

    # Install based on detected services
    for svc in "${DETECTED_SERVICES[@]}"; do
        case "$svc" in
            node_exporter)
                install_node_exporter
                ;;
            nginx_exporter)
                install_nginx_exporter
                ;;
            mysqld_exporter)
                install_mysqld_exporter
                ;;
            phpfpm_exporter)
                install_phpfpm_exporter
                ;;
            fail2ban_exporter)
                install_fail2ban_exporter
                ;;
            promtail)
                install_promtail
                ;;
            alloy)
                install_alloy
                ;;
        esac
    done

    setup_firewall_monitored "$OBSERVABILITY_IP"
    start_all_exporters
    run_health_checks
    generate_prometheus_targets
    save_installation_info

    log_success "Monitored host installation complete"
}

#===============================================================================
# Configuration Validation
#===============================================================================

validate_monitored_config() {
    log_step "Validating configuration..."

    if [[ -z "${HOST_NAME:-}" ]]; then
        log_error "HOST_NAME is required"
        exit 1
    fi

    if [[ -z "${HOST_IP:-}" ]]; then
        log_error "HOST_IP is required"
        exit 1
    fi

    if [[ -z "${OBSERVABILITY_IP:-}" ]]; then
        log_error "OBSERVABILITY_IP is required"
        exit 1
    fi

    log_success "Configuration validated"
}

#===============================================================================
# System Packages
#===============================================================================

install_system_packages() {
    log_step "Installing system packages..."

    apt-get update -qq
    apt-get install -y -qq \
        curl \
        wget \
        unzip \
        jq

    log_success "System packages installed"
}

#===============================================================================
# Node Exporter
#===============================================================================

install_node_exporter() {
    log_step "Installing Node Exporter ${NODE_EXPORTER_VERSION}..."

    local arch
    arch=$(get_architecture)
    local tarball="node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}.tar.gz"
    local url="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/${tarball}"

    # Create user
    create_system_user node_exporter node_exporter

    # Download and extract
    cd /tmp
    download_file "$url" "$tarball"
    tar xzf "$tarball"

    # Stop service and verify before binary update
    stop_and_verify_service "node_exporter" "/usr/local/bin/node_exporter" || true

    # Install binary
    cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}/node_exporter" /usr/local/bin/
    chmod 755 /usr/local/bin/node_exporter

    # Cleanup
    rm -rf "/tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}" "/tmp/${tarball}"

    # Create systemd service with production hardening
    cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Prometheus Node Exporter
Documentation=https://github.com/prometheus/node_exporter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter \\
    --collector.systemd \\
    --collector.processes \\
    --collector.filesystem.mount-points-exclude='^/(sys|proc|dev|host|etc)(\$\$|/)' \\
    --web.listen-address=':${NODE_EXPORTER_PORT}' \\
    --web.telemetry-path='/metrics'
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
TimeoutStopSec=20

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadOnlyPaths=/

# Resource limits
MemoryMax=128M
CPUQuota=25%

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Node Exporter ${NODE_EXPORTER_VERSION} installed (port ${NODE_EXPORTER_PORT})"
}

#===============================================================================
# Nginx Exporter
#===============================================================================

install_nginx_exporter() {
    log_step "Installing Nginx Exporter ${NGINX_EXPORTER_VERSION}..."

    local arch
    arch=$(get_architecture)
    local tarball="nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_${arch}.tar.gz"
    local url="https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v${NGINX_EXPORTER_VERSION}/${tarball}"

    # Create user
    create_system_user nginx_exporter nginx_exporter

    # Download and extract
    cd /tmp
    download_file "$url" "$tarball"
    tar xzf "$tarball"

    # Stop service and verify before binary update
    stop_and_verify_service "nginx_exporter" "/usr/local/bin/nginx-prometheus-exporter" || true

    # Install binary
    cp nginx-prometheus-exporter /usr/local/bin/
    chmod 755 /usr/local/bin/nginx-prometheus-exporter

    # Cleanup
    rm -f "/tmp/${tarball}" /tmp/nginx-prometheus-exporter

    # Configure nginx stub_status
    configure_nginx_stub_status

    # Create systemd service with production hardening
    cat > /etc/systemd/system/nginx_exporter.service << EOF
[Unit]
Description=Prometheus Nginx Exporter
Documentation=https://github.com/nginxinc/nginx-prometheus-exporter
After=network-online.target nginx.service
Wants=network-online.target
BindsTo=nginx.service

[Service]
Type=simple
User=nginx_exporter
Group=nginx_exporter
ExecStart=/usr/local/bin/nginx-prometheus-exporter \\
    --nginx.scrape-uri='http://127.0.0.1:8080/stub_status' \\
    --web.listen-address=':${NGINX_EXPORTER_PORT}' \\
    --web.telemetry-path='/metrics'
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
TimeoutStopSec=20

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadOnlyPaths=/

# Resource limits
MemoryMax=64M
CPUQuota=10%

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Nginx Exporter ${NGINX_EXPORTER_VERSION} installed (port ${NGINX_EXPORTER_PORT})"
}

configure_nginx_stub_status() {
    log_step "Configuring Nginx stub_status..."

    # Check if stub_status already configured
    if nginx -T 2>/dev/null | grep -q stub_status; then
        log_info "Nginx stub_status already configured"
        return 0
    fi

    # Add stub_status configuration
    cat > /etc/nginx/conf.d/stub_status.conf << 'EOF'
# Nginx status endpoint for Prometheus exporter
server {
    listen 127.0.0.1:8080;
    server_name localhost;

    location /stub_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        deny all;
    }
}
EOF

    # Test and reload nginx
    if nginx -t 2>&1; then
        systemctl reload nginx
        log_success "Nginx stub_status configured"
    else
        log_error "Nginx configuration test failed"
        rm -f /etc/nginx/conf.d/stub_status.conf
        return 1
    fi
}

#===============================================================================
# MySQL Exporter
#===============================================================================

install_mysqld_exporter() {
    log_step "Installing MySQL Exporter ${MYSQLD_EXPORTER_VERSION}..."

    local arch
    arch=$(get_architecture)
    local tarball="mysqld_exporter-${MYSQLD_EXPORTER_VERSION}.linux-${arch}.tar.gz"
    local url="https://github.com/prometheus/mysqld_exporter/releases/download/v${MYSQLD_EXPORTER_VERSION}/${tarball}"

    # Create user
    create_system_user mysqld_exporter mysqld_exporter

    # Download and extract
    cd /tmp
    download_file "$url" "$tarball"
    tar xzf "$tarball"

    # Stop service and verify before binary update
    stop_and_verify_service "mysqld_exporter" "/usr/local/bin/mysqld_exporter" || true

    # Install binary
    cp "mysqld_exporter-${MYSQLD_EXPORTER_VERSION}.linux-${arch}/mysqld_exporter" /usr/local/bin/
    chmod 755 /usr/local/bin/mysqld_exporter

    # Cleanup
    rm -rf "/tmp/mysqld_exporter-${MYSQLD_EXPORTER_VERSION}.linux-${arch}" "/tmp/${tarball}"

    # Create credentials file
    mkdir -p /etc/mysqld_exporter

    # Check for existing credentials
    local exporter_user="${MYSQL_EXPORTER_USER:-exporter}"
    local exporter_pass="${MYSQL_EXPORTER_PASS:-}"

    if [[ -z "$exporter_pass" ]]; then
        # Check if credentials file exists from vpsmanager install
        if [[ -f /root/.credentials/mysql ]]; then
            source /root/.credentials/mysql
            exporter_pass="${MYSQL_EXPORTER_PASS:-}"
        fi
    fi

    if [[ -z "$exporter_pass" ]]; then
        log_warn "MySQL exporter credentials not configured"
        log_info "Create MySQL user and update /etc/mysqld_exporter/.my.cnf:"
        echo "  CREATE USER 'exporter'@'localhost' IDENTIFIED BY 'your_password';"
        echo "  GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';"
        echo "  FLUSH PRIVILEGES;"
        exporter_pass="CHANGE_ME"
    fi

    cat > /etc/mysqld_exporter/.my.cnf << EOF
[client]
user=${exporter_user}
password=${exporter_pass}
host=127.0.0.1
port=3306
EOF

    chown -R mysqld_exporter:mysqld_exporter /etc/mysqld_exporter
    chmod 600 /etc/mysqld_exporter/.my.cnf

    # Create systemd service with production hardening
    cat > /etc/systemd/system/mysqld_exporter.service << EOF
[Unit]
Description=Prometheus MySQL/MariaDB Exporter
Documentation=https://github.com/prometheus/mysqld_exporter
After=network-online.target mysql.service mariadb.service
Wants=network-online.target

[Service]
Type=simple
User=mysqld_exporter
Group=mysqld_exporter
ExecStart=/usr/local/bin/mysqld_exporter \\
    --config.my-cnf=/etc/mysqld_exporter/.my.cnf \\
    --web.listen-address=':${MYSQLD_EXPORTER_PORT}' \\
    --web.telemetry-path='/metrics' \\
    --collect.info_schema.tables \\
    --collect.info_schema.innodb_metrics \\
    --collect.global_status \\
    --collect.global_variables \\
    --collect.slave_status \\
    --collect.engine_innodb_status
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
TimeoutStopSec=20

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadOnlyPaths=/
ReadWritePaths=/etc/mysqld_exporter

# Resource limits
MemoryMax=64M
CPUQuota=10%

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "MySQL Exporter ${MYSQLD_EXPORTER_VERSION} installed (port ${MYSQLD_EXPORTER_PORT})"
}

#===============================================================================
# PHP-FPM Exporter
#===============================================================================

install_phpfpm_exporter() {
    log_step "Installing PHP-FPM Exporter ${PHPFPM_EXPORTER_VERSION}..."

    # Find PHP-FPM socket
    local socket
    socket=$(find /run/php/ -name "php*-fpm.sock" 2>/dev/null | head -1)

    if [[ -z "$socket" ]]; then
        log_warn "PHP-FPM socket not found, skipping exporter installation"
        log_info "If PHP-FPM is installed, ensure it's running and try again"
        return 0
    fi

    # Detect PHP version from socket name
    local php_version
    php_version=$(echo "$socket" | grep -oP 'php\K[0-9.]+' || echo "8.2")

    # Create user
    create_system_user phpfpm_exporter phpfpm_exporter
    usermod -a -G www-data phpfpm_exporter 2>/dev/null || true

    # Download binary (using go-based exporter)
    local arch
    arch=$(get_architecture)
    local url="https://github.com/hipages/php-fpm_exporter/releases/download/v${PHPFPM_EXPORTER_VERSION}/php-fpm_exporter_${PHPFPM_EXPORTER_VERSION}_linux_${arch}"

    # Stop service and verify before binary update
    stop_and_verify_service "phpfpm_exporter" "/usr/local/bin/phpfpm_exporter" || true

    download_file "$url" /usr/local/bin/phpfpm_exporter
    chmod 755 /usr/local/bin/phpfpm_exporter

    # Configure PHP-FPM status page if not already configured
    configure_phpfpm_status "$php_version"

    # Create systemd service with production hardening
    cat > /etc/systemd/system/phpfpm_exporter.service << EOF
[Unit]
Description=Prometheus PHP-FPM Exporter
Documentation=https://github.com/hipages/php-fpm_exporter
After=network-online.target php${php_version}-fpm.service
Wants=network-online.target
Requires=php${php_version}-fpm.service

[Service]
Type=simple
User=phpfpm_exporter
Group=phpfpm_exporter
# Use unix socket format: unix://<socket>;<status_path>
ExecStart=/usr/local/bin/phpfpm_exporter server \\
    --phpfpm.scrape-uri="unix://${socket};/fpm-status" \\
    --web.listen-address=":${PHPFPM_EXPORTER_PORT}" \\
    --web.telemetry-path="/metrics"
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
TimeoutStopSec=20

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadOnlyPaths=/

# Resource limits
MemoryMax=64M
CPUQuota=10%

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "PHP-FPM Exporter ${PHPFPM_EXPORTER_VERSION} installed (port ${PHPFPM_EXPORTER_PORT}, socket: ${socket})"
}

configure_phpfpm_status() {
    local php_version="${1:-8.2}"
    local fpm_conf="/etc/php/${php_version}/fpm/pool.d/www.conf"

    if [[ ! -f "$fpm_conf" ]]; then
        log_warn "PHP-FPM pool config not found at $fpm_conf"
        return 1
    fi

    log_step "Configuring PHP-FPM status page..."

    local needs_restart=false

    # Enable status page for monitoring
    if grep -q "^;pm.status_path" "$fpm_conf"; then
        sed -i 's/^;pm.status_path.*/pm.status_path = \/fpm-status/' "$fpm_conf"
        needs_restart=true
        log_info "Enabled pm.status_path"
    elif ! grep -q "^pm.status_path" "$fpm_conf"; then
        echo "pm.status_path = /fpm-status" >> "$fpm_conf"
        needs_restart=true
        log_info "Added pm.status_path"
    fi

    # Enable ping path
    if grep -q "^;ping.path" "$fpm_conf"; then
        sed -i 's/^;ping.path.*/ping.path = \/fpm-ping/' "$fpm_conf"
        needs_restart=true
        log_info "Enabled ping.path"
    elif ! grep -q "^ping.path" "$fpm_conf"; then
        echo "ping.path = /fpm-ping" >> "$fpm_conf"
        needs_restart=true
        log_info "Added ping.path"
    fi

    if $needs_restart; then
        systemctl reload "php${php_version}-fpm" 2>/dev/null || \
            systemctl restart "php${php_version}-fpm" 2>/dev/null || true
        log_success "PHP-FPM status page configured"
    else
        log_info "PHP-FPM status page already configured"
    fi
}

#===============================================================================
# Fail2ban Exporter
#===============================================================================

install_fail2ban_exporter() {
    log_step "Installing Fail2ban Exporter..."

    # Using Python-based exporter
    apt-get install -y -qq python3-pip python3-venv

    # Create virtual environment
    if [[ ! -d /opt/fail2ban_exporter ]]; then
        python3 -m venv /opt/fail2ban_exporter
    fi

    # Install exporter
    /opt/fail2ban_exporter/bin/pip install --upgrade fail2ban-exporter

    # Create systemd service
    cat > /etc/systemd/system/fail2ban_exporter.service << EOF
[Unit]
Description=Fail2ban Exporter for Prometheus
Documentation=https://github.com/jangrewe/prometheus-fail2ban-exporter
After=network-online.target fail2ban.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/fail2ban_exporter/bin/fail2ban-exporter --port ${FAIL2BAN_EXPORTER_PORT}
Restart=always
RestartSec=5
TimeoutStopSec=20

# Resource limits
MemoryMax=64M
CPUQuota=10%

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Fail2ban Exporter installed (port ${FAIL2BAN_EXPORTER_PORT})"
}

#===============================================================================
# Promtail
#===============================================================================

install_promtail() {
    log_step "Installing Promtail ${PROMTAIL_VERSION}..."

    local arch
    arch=$(get_architecture)
    local binary="promtail-linux-${arch}"
    local url="https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/${binary}.zip"

    # Create user
    create_system_user promtail promtail

    # Download and extract
    cd /tmp
    download_file "$url" "promtail.zip"
    unzip -o promtail.zip

    # Stop service and verify before binary update
    stop_and_verify_service "promtail" "/usr/local/bin/promtail" || true

    # Install binary
    chmod +x "${binary}"
    mv "${binary}" /usr/local/bin/promtail

    # Create directories
    mkdir -p /etc/promtail /var/lib/promtail
    chown -R promtail:promtail /var/lib/promtail

    # Add promtail to adm group for log access
    usermod -a -G adm promtail

    # Add to www-data if php-fpm is detected
    if [[ " ${DETECTED_SERVICES[*]} " =~ " phpfpm_exporter " ]]; then
        usermod -a -G www-data promtail 2>/dev/null || true
    fi

    # Determine environment
    local app_env="${APP_ENV:-production}"
    if [[ "${HOST_NAME}" == *"_tst"* ]] || [[ "${HOST_NAME}" == *"-tst"* ]]; then
        app_env="test"
    fi

    # Determine app name from detected services
    local app_name="server"
    if [[ " ${DETECTED_SERVICES[*]} " =~ " phpfpm_exporter " ]]; then
        app_name="php-app"
    fi

    # Create configuration with proper labels
    cat > /etc/promtail/promtail.yaml << EOF
# Promtail Configuration for ${HOST_NAME}
# Environment: ${app_env}
# Generated: $(date -Iseconds)

server:
  http_listen_port: ${PROMTAIL_PORT}
  grpc_listen_port: 0
  log_level: info

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://${OBSERVABILITY_IP}:3100/loki/api/v1/push
    tenant_id: ${HOST_NAME}
    batchwait: 1s
    batchsize: 1048576
    external_labels:
      host: ${HOST_NAME}
      env: ${app_env}
      app: ${app_name}

scrape_configs:
  # System logs
  - job_name: system
    static_configs:
      - targets: [localhost]
        labels:
          job: system
          host: ${HOST_NAME}
          env: ${app_env}
          __path__: /var/log/*.log
    pipeline_stages:
      - match:
          selector: '{job="system"}'
          stages:
            - regex:
                expression: '.*'

  # Syslog
  - job_name: syslog
    static_configs:
      - targets: [localhost]
        labels:
          job: syslog
          host: ${HOST_NAME}
          env: ${app_env}
          __path__: /var/log/syslog

  # Auth logs (security monitoring)
  - job_name: auth
    static_configs:
      - targets: [localhost]
        labels:
          job: auth
          host: ${HOST_NAME}
          env: ${app_env}
          __path__: /var/log/auth.log
EOF

    # Add nginx logs if nginx is installed
    if [[ " ${DETECTED_SERVICES[*]} " =~ " nginx_exporter " ]]; then
        cat >> /etc/promtail/promtail.yaml << EOF

  # Nginx Access Logs
  - job_name: nginx-access
    static_configs:
      - targets: [localhost]
        labels:
          job: monitored-nginx
          log_type: access
          host: ${HOST_NAME}
          env: ${app_env}
          __path__: /var/log/nginx/access.log
    pipeline_stages:
      - regex:
          expression: '^(?P<remote_addr>[\w\.]+) - (?P<remote_user>\S+) \[(?P<time_local>[^\]]+)\] "(?P<method>\S+) (?P<request_uri>\S+) (?P<protocol>\S+)" (?P<status>\d+) (?P<body_bytes_sent>\d+)'
      - labels:
          method:
          status:

  # Nginx Error Logs
  - job_name: nginx-error
    static_configs:
      - targets: [localhost]
        labels:
          job: monitored-nginx
          log_type: error
          host: ${HOST_NAME}
          env: ${app_env}
          __path__: /var/log/nginx/error.log
    pipeline_stages:
      - regex:
          expression: '^\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2} \[(?P<level>\w+)\]'
      - labels:
          level:
EOF
    fi

    # Add mysql logs if mysql is installed
    if [[ " ${DETECTED_SERVICES[*]} " =~ " mysqld_exporter " ]]; then
        cat >> /etc/promtail/promtail.yaml << EOF

  # MySQL/MariaDB Logs
  - job_name: mysql
    static_configs:
      - targets: [localhost]
        labels:
          job: monitored-mysql
          host: ${HOST_NAME}
          env: ${app_env}
          __path__: /var/log/mysql/*.log

  # MySQL Slow Query Log
  - job_name: mysql-slow
    static_configs:
      - targets: [localhost]
        labels:
          job: monitored-mysql
          log_type: slow-query
          host: ${HOST_NAME}
          env: ${app_env}
          __path__: /var/log/mysql/mysql-slow.log
    pipeline_stages:
      - multiline:
          firstline: '^# Time:'
          max_wait_time: 3s
EOF
    fi

    # Add PHP-FPM logs if detected
    if [[ " ${DETECTED_SERVICES[*]} " =~ " phpfpm_exporter " ]]; then
        local php_version
        php_version=$(ls /run/php/php*-fpm.sock 2>/dev/null | head -1 | grep -oP 'php\K[0-9.]+' || echo "8.2")
        cat >> /etc/promtail/promtail.yaml << EOF

  # PHP-FPM Logs
  - job_name: php-fpm
    static_configs:
      - targets: [localhost]
        labels:
          job: monitored-phpfpm
          host: ${HOST_NAME}
          env: ${app_env}
          __path__: /var/log/php${php_version}-fpm.log
    pipeline_stages:
      - regex:
          expression: '^\[(?P<timestamp>[^\]]+)\] (?P<level>\w+): (?P<message>.*)'
      - labels:
          level:
EOF
    fi

    chown -R promtail:promtail /etc/promtail
    chmod 600 /etc/promtail/promtail.yaml

    # Cleanup
    rm -f /tmp/promtail.zip

    # Create systemd service with production hardening
    cat > /etc/systemd/system/promtail.service << EOF
[Unit]
Description=Promtail Log Collector
Documentation=https://grafana.com/docs/loki/latest/clients/promtail/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=promtail
Group=promtail
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail.yaml
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
TimeoutStopSec=30

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=/var/lib/promtail
ReadOnlyPaths=/etc/promtail /var/log

# Resource limits
MemoryMax=256M
CPUQuota=50%

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Promtail ${PROMTAIL_VERSION} installed (port ${PROMTAIL_PORT})"
}

#===============================================================================
# Grafana Alloy
#===============================================================================

install_alloy() {
    log_step "Installing Grafana Alloy ${ALLOY_VERSION}..."

    local arch
    arch=$(get_architecture)

    # Map architecture for Alloy download
    local alloy_arch="$arch"
    case "$arch" in
        amd64) alloy_arch="linux-amd64" ;;
        arm64) alloy_arch="linux-arm64" ;;
    esac

    local binary="alloy-${alloy_arch}"
    local url="https://github.com/grafana/alloy/releases/download/v${ALLOY_VERSION}/${binary}.zip"

    # Create user
    create_system_user alloy alloy
    usermod -a -G adm alloy

    # Add to www-data if php-fpm is detected
    if [[ " ${DETECTED_SERVICES[*]} " =~ " phpfpm_exporter " ]]; then
        usermod -a -G www-data alloy 2>/dev/null || true
    fi

    # Download and extract
    cd /tmp
    download_file "$url" "alloy.zip"
    unzip -o alloy.zip

    # Stop service and verify before binary update
    stop_and_verify_service "alloy" "/usr/local/bin/alloy" || true

    # Install binary
    chmod +x "${binary}"
    mv "${binary}" /usr/local/bin/alloy

    # Create directories
    mkdir -p /etc/alloy /var/lib/alloy
    chown -R alloy:alloy /var/lib/alloy

    # Cleanup
    rm -f /tmp/alloy.zip

    # Determine environment
    local app_env="${APP_ENV:-production}"
    if [[ "${HOST_NAME}" == *"_tst"* ]] || [[ "${HOST_NAME}" == *"-tst"* ]]; then
        app_env="test"
    fi

    # Determine app name from detected services
    local app_name="server"
    if [[ " ${DETECTED_SERVICES[*]} " =~ " phpfpm_exporter " ]]; then
        app_name="php-app"
    fi

    # Build log sources based on detected services
    local nginx_config=""
    local mysql_config=""
    local phpfpm_config=""

    if [[ " ${DETECTED_SERVICES[*]} " =~ " nginx_exporter " ]]; then
        nginx_config='
// Nginx Logs
loki.source.file "nginx" {
    targets = [
        {__path__ = "/var/log/nginx/access.log", job = "monitored-nginx", log_type = "access"},
        {__path__ = "/var/log/nginx/error.log", job = "monitored-nginx", log_type = "error"},
    ]
    forward_to = [loki.write.default.receiver]
}'
    fi

    if [[ " ${DETECTED_SERVICES[*]} " =~ " mysqld_exporter " ]]; then
        mysql_config='
// MySQL/MariaDB Logs
loki.source.file "mysql" {
    targets = [
        {__path__ = "/var/log/mysql/*.log", job = "monitored-mysql"},
    ]
    forward_to = [loki.write.default.receiver]
}'
    fi

    if [[ " ${DETECTED_SERVICES[*]} " =~ " phpfpm_exporter " ]]; then
        local php_version
        php_version=$(ls /run/php/php*-fpm.sock 2>/dev/null | head -1 | grep -oP 'php\K[0-9.]+' || echo "8.2")
        phpfpm_config="
// PHP-FPM Logs
loki.source.file \"phpfpm\" {
    targets = [
        {__path__ = \"/var/log/php${php_version}-fpm.log\", job = \"monitored-phpfpm\"},
    ]
    forward_to = [loki.write.default.receiver]
}"
    fi

    # Create Alloy configuration (River format)
    cat > /etc/alloy/config.alloy << EOF
// Grafana Alloy Configuration for ${HOST_NAME}
// Environment: ${app_env}
// Generated: $(date -Iseconds)

// HTTP server configuration
server {
    http_listen_addr = "0.0.0.0:${ALLOY_PORT}"
    log_level        = "info"
}

// Loki destination
loki.write "default" {
    endpoint {
        url        = "http://${OBSERVABILITY_IP}:3100/loki/api/v1/push"
        tenant_id  = "${HOST_NAME}"
    }
    external_labels = {
        host = "${HOST_NAME}",
        env  = "${app_env}",
        app  = "${app_name}",
    }
}

// System Logs
loki.source.file "system" {
    targets = [
        {__path__ = "/var/log/syslog", job = "syslog"},
        {__path__ = "/var/log/auth.log", job = "auth"},
    ]
    forward_to = [loki.write.default.receiver]
}
${nginx_config}
${mysql_config}
${phpfpm_config}
EOF

    chown -R alloy:alloy /etc/alloy
    chmod 600 /etc/alloy/config.alloy

    # Create systemd service with production hardening
    cat > /etc/systemd/system/alloy.service << EOF
[Unit]
Description=Grafana Alloy Telemetry Collector
Documentation=https://grafana.com/docs/alloy/latest/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=alloy
Group=alloy
ExecStart=/usr/local/bin/alloy run /etc/alloy/config.alloy --storage.path=/var/lib/alloy
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
TimeoutStopSec=30

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=/var/lib/alloy
ReadOnlyPaths=/etc/alloy /var/log

# Resource limits
MemoryMax=256M
CPUQuota=50%

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Grafana Alloy ${ALLOY_VERSION} installed (port ${ALLOY_PORT})"
}

#===============================================================================
# Firewall Configuration
#===============================================================================

setup_firewall_monitored() {
    local observability_ip="$1"

    log_step "Configuring firewall for monitored host..."

    # Check if ufw is available
    if ! command -v ufw &>/dev/null; then
        log_warn "UFW not installed, skipping firewall configuration"
        return 0
    fi

    ufw --force reset 2>/dev/null || true
    ufw default deny incoming 2>/dev/null || true
    ufw default allow outgoing 2>/dev/null || true

    # SSH
    ufw allow 22/tcp comment 'SSH' 2>/dev/null || true

    # Allow metrics scraping from observability VPS only
    for svc in "${DETECTED_SERVICES[@]}"; do
        case "$svc" in
            node_exporter)
                ufw allow from "$observability_ip" to any port ${NODE_EXPORTER_PORT} proto tcp comment 'node_exporter' 2>/dev/null || true
                ;;
            nginx_exporter)
                ufw allow from "$observability_ip" to any port ${NGINX_EXPORTER_PORT} proto tcp comment 'nginx_exporter' 2>/dev/null || true
                ;;
            mysqld_exporter)
                ufw allow from "$observability_ip" to any port ${MYSQLD_EXPORTER_PORT} proto tcp comment 'mysqld_exporter' 2>/dev/null || true
                ;;
            phpfpm_exporter)
                ufw allow from "$observability_ip" to any port ${PHPFPM_EXPORTER_PORT} proto tcp comment 'phpfpm_exporter' 2>/dev/null || true
                ;;
            fail2ban_exporter)
                ufw allow from "$observability_ip" to any port ${FAIL2BAN_EXPORTER_PORT} proto tcp comment 'fail2ban_exporter' 2>/dev/null || true
                ;;
        esac
    done

    ufw --force enable 2>/dev/null || log_warn "Could not enable UFW"
    log_success "Firewall configured (metrics only from $observability_ip)"
}

#===============================================================================
# Start Exporters
#===============================================================================

start_all_exporters() {
    log_step "Starting all exporters..."

    for svc in "${DETECTED_SERVICES[@]}"; do
        local service_name="${svc}"

        # Map service to systemd unit name
        case "$svc" in
            node_exporter)     service_name="node_exporter" ;;
            nginx_exporter)    service_name="nginx_exporter" ;;
            mysqld_exporter)   service_name="mysqld_exporter" ;;
            phpfpm_exporter)   service_name="phpfpm_exporter" ;;
            fail2ban_exporter) service_name="fail2ban_exporter" ;;
            promtail)          service_name="promtail" ;;
            alloy)             service_name="alloy" ;;
            *)                 continue ;;
        esac

        enable_and_start "$service_name" || log_warn "Failed to start $service_name"
    done

    log_success "All exporters started"
}

#===============================================================================
# Health Checks
#===============================================================================

run_health_checks() {
    log_step "Running health checks..."

    local failed_checks=0

    for svc in "${DETECTED_SERVICES[@]}"; do
        local service_name=""
        local port=""

        case "$svc" in
            node_exporter)
                service_name="node_exporter"
                port="${NODE_EXPORTER_PORT}"
                ;;
            nginx_exporter)
                service_name="nginx_exporter"
                port="${NGINX_EXPORTER_PORT}"
                ;;
            mysqld_exporter)
                service_name="mysqld_exporter"
                port="${MYSQLD_EXPORTER_PORT}"
                ;;
            phpfpm_exporter)
                service_name="phpfpm_exporter"
                port="${PHPFPM_EXPORTER_PORT}"
                ;;
            fail2ban_exporter)
                service_name="fail2ban_exporter"
                port="${FAIL2BAN_EXPORTER_PORT}"
                ;;
            promtail)
                service_name="promtail"
                port="${PROMTAIL_PORT}"
                ;;
            alloy)
                service_name="alloy"
                port="${ALLOY_PORT}"
                ;;
            *)
                continue
                ;;
        esac

        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
            if [[ -n "$port" ]] && curl -s --connect-timeout 2 "http://localhost:${port}/metrics" 2>/dev/null | grep -q "^# "; then
                log_success "[OK] ${service_name} responding (port ${port})"
            elif [[ -n "$port" ]]; then
                log_warn "[WARN] ${service_name} running but metrics endpoint not responding on port ${port}"
            else
                log_success "[OK] ${service_name} running"
            fi
        else
            log_error "[FAIL] ${service_name} not running"
            ((failed_checks++))
        fi
    done

    echo ""
    if [[ $failed_checks -eq 0 ]]; then
        log_success "All health checks passed"
    else
        log_warn "$failed_checks service(s) failed health check"
    fi

    return $failed_checks
}

#===============================================================================
# Generate Prometheus Targets
#===============================================================================

generate_prometheus_targets() {
    log_step "Generating Prometheus targets file..."

    # Determine environment
    local app_env="${APP_ENV:-production}"
    if [[ "${HOST_NAME}" == *"_tst"* ]] || [[ "${HOST_NAME}" == *"-tst"* ]]; then
        app_env="test"
    fi

    # Determine app name from detected services
    local app_name="server"
    if [[ " ${DETECTED_SERVICES[*]} " =~ " phpfpm_exporter " ]]; then
        app_name="php-app"
    fi

    # Create target file for Prometheus file_sd
    local target_file="/tmp/${HOST_NAME}-targets.yaml"

    cat > "$target_file" << EOF
# Prometheus Scrape Targets for ${HOST_NAME}
# Environment: ${app_env}
# Generated: $(date -Iseconds)
#
# Instructions:
# Copy this file to /etc/prometheus/targets/ on the Observability VPS:
#   scp ${target_file} root@${OBSERVABILITY_IP}:/etc/prometheus/targets/
#
# Prometheus will automatically discover these targets via file_sd_configs
# Job naming convention: monitored-{exporter_type}

# Node Exporter - System metrics
- targets:
    - '${HOST_IP}:${NODE_EXPORTER_PORT}'
  labels:
    instance: '${HOST_NAME}'
    job: 'monitored-node'
    app: '${app_name}'
    env: '${app_env}'
    role: 'monitored'
EOF

    for svc in "${DETECTED_SERVICES[@]}"; do
        case "$svc" in
            nginx_exporter)
                cat >> "$target_file" << EOF

# Nginx Exporter - Web server metrics
- targets:
    - '${HOST_IP}:${NGINX_EXPORTER_PORT}'
  labels:
    instance: '${HOST_NAME}'
    job: 'monitored-nginx'
    app: '${app_name}'
    env: '${app_env}'
    role: 'monitored'
EOF
                ;;
            mysqld_exporter)
                cat >> "$target_file" << EOF

# MySQL Exporter - Database metrics
- targets:
    - '${HOST_IP}:${MYSQLD_EXPORTER_PORT}'
  labels:
    instance: '${HOST_NAME}'
    job: 'monitored-mysql'
    app: '${app_name}'
    env: '${app_env}'
    role: 'monitored'
EOF
                ;;
            phpfpm_exporter)
                cat >> "$target_file" << EOF

# PHP-FPM Exporter - Application runtime metrics
- targets:
    - '${HOST_IP}:${PHPFPM_EXPORTER_PORT}'
  labels:
    instance: '${HOST_NAME}'
    job: 'monitored-phpfpm'
    app: '${app_name}'
    env: '${app_env}'
    role: 'monitored'
EOF
                ;;
            fail2ban_exporter)
                cat >> "$target_file" << EOF

# Fail2ban Exporter - Security metrics
- targets:
    - '${HOST_IP}:${FAIL2BAN_EXPORTER_PORT}'
  labels:
    instance: '${HOST_NAME}'
    job: 'monitored-fail2ban'
    app: '${app_name}'
    env: '${app_env}'
    role: 'monitored'
EOF
                ;;
        esac
    done

    # Save locally for reference
    mkdir -p /etc/prometheus-client
    cp "$target_file" /etc/prometheus-client/
    chmod 644 /etc/prometheus-client/*.yaml

    echo ""
    log_info "Prometheus targets file created: $target_file"
    log_info "Copy to Observability VPS:"
    echo ""
    echo "  scp $target_file root@${OBSERVABILITY_IP}:/etc/prometheus/targets/"
    echo ""

    log_success "Prometheus targets generated with monitored-* job naming"
}

#===============================================================================
# Save Installation Info
#===============================================================================

save_installation_info() {
    log_step "Saving installation info..."

    mkdir -p "$STACK_DIR"

    # Determine environment
    local app_env="${APP_ENV:-production}"
    if [[ "${HOST_NAME}" == *"_tst"* ]] || [[ "${HOST_NAME}" == *"-tst"* ]]; then
        app_env="test"
    fi

    cat > "$STACK_DIR/.installation" << EOF
# Monitored Host Installation
# Generated: $(date -Iseconds)

ROLE=monitored
HOST_NAME=${HOST_NAME}
HOST_IP=${HOST_IP}
OBSERVABILITY_IP=${OBSERVABILITY_IP}
APP_ENV=${app_env}
TELEMETRY_COLLECTOR=${TELEMETRY_COLLECTOR}

# Installed Services
DETECTED_SERVICES=(${DETECTED_SERVICES[*]})

# Versions
NODE_EXPORTER_VERSION=${NODE_EXPORTER_VERSION}
PROMTAIL_VERSION=${PROMTAIL_VERSION}
ALLOY_VERSION=${ALLOY_VERSION}

# Exporter ports (standard)
NODE_EXPORTER_PORT=${NODE_EXPORTER_PORT}
NGINX_EXPORTER_PORT=${NGINX_EXPORTER_PORT}
MYSQLD_EXPORTER_PORT=${MYSQLD_EXPORTER_PORT}
PHPFPM_EXPORTER_PORT=${PHPFPM_EXPORTER_PORT}
FAIL2BAN_EXPORTER_PORT=${FAIL2BAN_EXPORTER_PORT}
PROMTAIL_PORT=${PROMTAIL_PORT}
ALLOY_PORT=${ALLOY_PORT}
EOF

    chmod 600 "$STACK_DIR/.installation"
    log_success "Installation info saved to $STACK_DIR/.installation"
}
