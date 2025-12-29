#!/bin/bash
#===============================================================================
# Monitored Host Installation
#
# Installs: Node Exporter, Promtail, and detected service exporters
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
STACK_DIR="$(dirname "$DEPLOY_DIR")"

# Versions (can be overridden)
NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-1.7.0}"
PROMTAIL_VERSION="${PROMTAIL_VERSION:-3.0.0}"
NGINX_EXPORTER_VERSION="${NGINX_EXPORTER_VERSION:-1.1.0}"
MYSQLD_EXPORTER_VERSION="${MYSQLD_EXPORTER_VERSION:-0.15.1}"
PHPFPM_EXPORTER_VERSION="${PHPFPM_EXPORTER_VERSION:-0.6.0}"

#===============================================================================
# Main Installation Function
#===============================================================================

install_monitored_host() {
    log_step "Installing Monitored Host components..."

    install_system_packages

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
        esac
    done

    setup_firewall_monitored "$OBSERVABILITY_IP"
    register_with_observability
    start_all_exporters
    save_installation_info
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
    stop_and_verify_service "node_exporter" "/usr/local/bin/node_exporter" || {
        log_error "Failed to stop node_exporter safely"
        return 1
    }

    # Install binary
    cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}/node_exporter" /usr/local/bin/

    # Cleanup
    rm -rf "/tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}" "/tmp/${tarball}"

    # Create systemd service
    cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Node Exporter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter \\
    --collector.systemd \\
    --collector.processes
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Node Exporter installed"
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
    stop_and_verify_service "promtail" "/usr/local/bin/promtail" || {
        log_error "Failed to stop promtail safely"
        return 1
    }

    # Install binary
    chmod +x "${binary}"
    mv "${binary}" /usr/local/bin/promtail

    # Create directories
    mkdir -p /etc/promtail /var/lib/promtail
    chown -R promtail:promtail /var/lib/promtail

    # Create configuration
    cat > /etc/promtail/promtail.yaml << EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://${OBSERVABILITY_IP}:3100/loki/api/v1/push
    basic_auth:
      username: ${LOKI_USER:-promtail}
      password: ${LOKI_PASS:-}

scrape_configs:
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          host: ${HOST_NAME}
          __path__: /var/log/*.log

  - job_name: syslog
    static_configs:
      - targets:
          - localhost
        labels:
          job: syslog
          host: ${HOST_NAME}
          __path__: /var/log/syslog

  - job_name: auth
    static_configs:
      - targets:
          - localhost
        labels:
          job: auth
          host: ${HOST_NAME}
          __path__: /var/log/auth.log
EOF

    # Add nginx logs if nginx is installed
    if [[ " ${DETECTED_SERVICES[*]} " =~ " nginx_exporter " ]]; then
        cat >> /etc/promtail/promtail.yaml << EOF

  - job_name: nginx
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx
          host: ${HOST_NAME}
          __path__: /var/log/nginx/*.log
EOF
    fi

    # Add mysql logs if mysql is installed
    if [[ " ${DETECTED_SERVICES[*]} " =~ " mysqld_exporter " ]]; then
        cat >> /etc/promtail/promtail.yaml << EOF

  - job_name: mysql
    static_configs:
      - targets:
          - localhost
        labels:
          job: mysql
          host: ${HOST_NAME}
          __path__: /var/log/mysql/*.log
EOF
    fi

    chown -R promtail:promtail /etc/promtail
    chmod 600 /etc/promtail/promtail.yaml

    # Add promtail to adm group for log access
    usermod -a -G adm promtail

    # Cleanup
    rm -f /tmp/promtail.zip

    # Create systemd service
    cat > /etc/systemd/system/promtail.service << EOF
[Unit]
Description=Promtail
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=promtail
Group=promtail
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Promtail installed"
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
    stop_and_verify_service "nginx_exporter" "/usr/local/bin/nginx-prometheus-exporter" || {
        log_error "Failed to stop nginx_exporter safely"
        return 1
    }

    # Install binary
    cp nginx-prometheus-exporter /usr/local/bin/

    # Cleanup
    rm -f "/tmp/${tarball}" /tmp/nginx-prometheus-exporter

    # Configure nginx stub_status
    configure_nginx_stub_status

    # Create systemd service
    cat > /etc/systemd/system/nginx_exporter.service << EOF
[Unit]
Description=Nginx Exporter
After=network-online.target nginx.service
Wants=network-online.target

[Service]
Type=simple
User=nginx_exporter
Group=nginx_exporter
ExecStart=/usr/local/bin/nginx-prometheus-exporter \\
    --nginx.scrape-uri=http://127.0.0.1:8080/stub_status
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Nginx Exporter installed"
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

    nginx -t && systemctl reload nginx
    log_success "Nginx stub_status configured"
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
    stop_and_verify_service "mysqld_exporter" "/usr/local/bin/mysqld_exporter" || {
        log_error "Failed to stop mysqld_exporter safely"
        return 1
    }

    # Install binary
    cp "mysqld_exporter-${MYSQLD_EXPORTER_VERSION}.linux-${arch}/mysqld_exporter" /usr/local/bin/

    # Cleanup
    rm -rf "/tmp/mysqld_exporter-${MYSQLD_EXPORTER_VERSION}.linux-${arch}" "/tmp/${tarball}"

    # Create credentials file
    mkdir -p /etc/mysqld_exporter

    # Check if credentials were provided
    if [[ -z "${MYSQL_EXPORTER_USER:-}" ]]; then
        log_warn "MySQL exporter credentials not configured"
        log_info "Create MySQL user and update /etc/mysqld_exporter/.my.cnf:"
        echo "  CREATE USER 'exporter'@'localhost' IDENTIFIED BY 'password';"
        echo "  GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';"
        echo "  FLUSH PRIVILEGES;"

        cat > /etc/mysqld_exporter/.my.cnf << 'EOF'
[client]
user=exporter
password=CHANGE_ME
EOF
    else
        cat > /etc/mysqld_exporter/.my.cnf << EOF
[client]
user=${MYSQL_EXPORTER_USER}
password=${MYSQL_EXPORTER_PASS}
EOF
    fi

    chown -R mysqld_exporter:mysqld_exporter /etc/mysqld_exporter
    chmod 600 /etc/mysqld_exporter/.my.cnf

    # Create systemd service
    cat > /etc/systemd/system/mysqld_exporter.service << EOF
[Unit]
Description=MySQL Exporter
After=network-online.target mysql.service mariadb.service
Wants=network-online.target

[Service]
Type=simple
User=mysqld_exporter
Group=mysqld_exporter
ExecStart=/usr/local/bin/mysqld_exporter \\
    --config.my-cnf=/etc/mysqld_exporter/.my.cnf
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "MySQL Exporter installed"
}

#===============================================================================
# PHP-FPM Exporter
#===============================================================================

install_phpfpm_exporter() {
    log_step "Installing PHP-FPM Exporter..."

    # Find PHP-FPM socket
    local socket
    socket=$(ls /run/php/php*-fpm.sock 2>/dev/null | head -1)

    if [[ -z "$socket" ]]; then
        log_warn "PHP-FPM socket not found, skipping"
        return 0
    fi

    # Create user
    create_system_user phpfpm_exporter phpfpm_exporter
    usermod -a -G www-data phpfpm_exporter

    # Download binary (using go-based exporter)
    local arch
    arch=$(get_architecture)
    local url="https://github.com/hipages/php-fpm_exporter/releases/download/v${PHPFPM_EXPORTER_VERSION}/php-fpm_exporter_${PHPFPM_EXPORTER_VERSION}_linux_${arch}"

    download_file "$url" /usr/local/bin/phpfpm_exporter
    chmod +x /usr/local/bin/phpfpm_exporter

    # Create systemd service
    cat > /etc/systemd/system/phpfpm_exporter.service << EOF
[Unit]
Description=PHP-FPM Exporter
After=network-online.target

[Service]
Type=simple
User=phpfpm_exporter
Group=phpfpm_exporter
ExecStart=/usr/local/bin/phpfpm_exporter \\
    --phpfpm.socket-paths=${socket}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "PHP-FPM Exporter installed"
}

#===============================================================================
# Fail2ban Exporter
#===============================================================================

install_fail2ban_exporter() {
    log_step "Installing Fail2ban Exporter..."

    # Using Python-based exporter
    apt-get install -y -qq python3-pip python3-venv

    # Create virtual environment
    python3 -m venv /opt/fail2ban_exporter

    # Install exporter
    /opt/fail2ban_exporter/bin/pip install fail2ban-exporter

    # Create systemd service
    cat > /etc/systemd/system/fail2ban_exporter.service << 'EOF'
[Unit]
Description=Fail2ban Exporter
After=network-online.target fail2ban.service

[Service]
Type=simple
ExecStart=/opt/fail2ban_exporter/bin/fail2ban-exporter --port 9191
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Fail2ban Exporter installed"
}

#===============================================================================
# Register with Observability VPS
#===============================================================================

register_with_observability() {
    log_step "Registering with Observability VPS..."

    # Create target file for Prometheus file_sd
    local target_file="/tmp/${HOST_NAME}-targets.yaml"

    cat > "$target_file" << EOF
# Target configuration for ${HOST_NAME}
# Copy this to /etc/prometheus/targets/ on the Observability VPS

- targets:
    - ${HOST_IP}:9100
  labels:
    instance: ${HOST_NAME}
    job: node
EOF

    for svc in "${DETECTED_SERVICES[@]}"; do
        case "$svc" in
            nginx_exporter)
                cat >> "$target_file" << EOF

- targets:
    - ${HOST_IP}:9113
  labels:
    instance: ${HOST_NAME}
    job: nginx
EOF
                ;;
            mysqld_exporter)
                cat >> "$target_file" << EOF

- targets:
    - ${HOST_IP}:9104
  labels:
    instance: ${HOST_NAME}
    job: mysql
EOF
                ;;
            phpfpm_exporter)
                cat >> "$target_file" << EOF

- targets:
    - ${HOST_IP}:9253
  labels:
    instance: ${HOST_NAME}
    job: phpfpm
EOF
                ;;
            fail2ban_exporter)
                cat >> "$target_file" << EOF

- targets:
    - ${HOST_IP}:9191
  labels:
    instance: ${HOST_NAME}
    job: fail2ban
EOF
                ;;
        esac
    done

    echo
    log_info "Target configuration saved to: $target_file"
    log_info "Copy this file to the Observability VPS:"
    echo
    echo "  scp $target_file root@${OBSERVABILITY_IP}:/etc/prometheus/targets/"
    echo
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
            *)                 continue ;;
        esac

        enable_and_start "$service_name" || log_warn "Failed to start $service_name"
    done

    log_success "All exporters started"
}

#===============================================================================
# Save Installation Info
#===============================================================================

save_installation_info() {
    log_step "Saving installation info..."

    mkdir -p "$STACK_DIR"

    cat > "$STACK_DIR/.installation" << EOF
# Monitored Host Installation
# Generated: $(date -Iseconds)

ROLE=monitored
HOST_NAME=${HOST_NAME}
HOST_IP=${HOST_IP}
OBSERVABILITY_IP=${OBSERVABILITY_IP}

# Installed Services
DETECTED_SERVICES=(${DETECTED_SERVICES[*]})

# Versions
NODE_EXPORTER_VERSION=${NODE_EXPORTER_VERSION}
PROMTAIL_VERSION=${PROMTAIL_VERSION}
EOF

    chmod 600 "$STACK_DIR/.installation"
    log_success "Installation info saved"
}
