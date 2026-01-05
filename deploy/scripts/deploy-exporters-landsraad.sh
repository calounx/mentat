#!/usr/bin/env bash
# Deploy monitoring exporters to landsraad.arewel.com
# Installs: postgres_exporter, redis_exporter, nginx_exporter, php-fpm_exporter, promtail
# Usage: ./deploy-exporters-landsraad.sh

set -euo pipefail

# Configuration
POSTGRES_EXPORTER_VERSION="0.15.0"
REDIS_EXPORTER_VERSION="1.62.0"
NGINX_EXPORTER_VERSION="1.3.0"
PHPFPM_EXPORTER_VERSION="2.2.0"
PROMTAIL_VERSION="3.2.1"

LOKI_URL="${LOKI_URL:-http://mentat.arewel.com:3100}"
POSTGRES_USER="${POSTGRES_USER:-postgres_exporter}"
POSTGRES_DB="${POSTGRES_DB:-chom}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

log_info "Starting exporter deployment on landsraad..."

# Create exporters user
if ! id -u exporters &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin exporters
    log_success "Created exporters user"
fi

# Create directories
mkdir -p /opt/exporters/bin
mkdir -p /etc/exporters
mkdir -p /var/lib/promtail

# =============================================================================
# POSTGRES EXPORTER
# =============================================================================

install_postgres_exporter() {
    log_info "Installing postgres_exporter ${POSTGRES_EXPORTER_VERSION}..."

    cd /tmp
    wget -q "https://github.com/prometheus-community/postgres_exporter/releases/download/v${POSTGRES_EXPORTER_VERSION}/postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64.tar.gz"
    tar xzf "postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64.tar.gz"
    cp "postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64/postgres_exporter" /opt/exporters/bin/
    chmod +x /opt/exporters/bin/postgres_exporter
    rm -rf "postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64"*

    # Create PostgreSQL monitoring user and grant permissions
    log_info "Setting up PostgreSQL monitoring user..."
    sudo -u postgres psql -c "CREATE USER ${POSTGRES_USER} WITH PASSWORD 'monitor_password_change_me';" 2>/dev/null || true
    sudo -u postgres psql -c "GRANT pg_monitor TO ${POSTGRES_USER};" 2>/dev/null || true
    sudo -u postgres psql -c "GRANT CONNECT ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_USER};" 2>/dev/null || true

    # Create environment file with connection string
    cat > /etc/exporters/postgres_exporter.env << EOF
DATA_SOURCE_NAME=postgresql://${POSTGRES_USER}:monitor_password_change_me@localhost:5432/${POSTGRES_DB}?sslmode=disable
EOF
    chmod 600 /etc/exporters/postgres_exporter.env

    # Create systemd service
    cat > /etc/systemd/system/postgres_exporter.service << 'EOF'
[Unit]
Description=Prometheus PostgreSQL Exporter
Wants=network-online.target
After=network-online.target postgresql.service

[Service]
User=exporters
Group=exporters
Type=simple
EnvironmentFile=/etc/exporters/postgres_exporter.env
ExecStart=/opt/exporters/bin/postgres_exporter \
    --web.listen-address=:9187 \
    --collector.database \
    --collector.locks \
    --collector.replication \
    --collector.stat_statements
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable postgres_exporter
    systemctl restart postgres_exporter
    log_success "postgres_exporter installed and started on port 9187"
}

# =============================================================================
# REDIS EXPORTER
# =============================================================================

install_redis_exporter() {
    log_info "Installing redis_exporter ${REDIS_EXPORTER_VERSION}..."

    cd /tmp
    wget -q "https://github.com/oliver006/redis_exporter/releases/download/v${REDIS_EXPORTER_VERSION}/redis_exporter-v${REDIS_EXPORTER_VERSION}.linux-amd64.tar.gz"
    tar xzf "redis_exporter-v${REDIS_EXPORTER_VERSION}.linux-amd64.tar.gz"
    cp "redis_exporter-v${REDIS_EXPORTER_VERSION}.linux-amd64/redis_exporter" /opt/exporters/bin/
    chmod +x /opt/exporters/bin/redis_exporter
    rm -rf "redis_exporter-v${REDIS_EXPORTER_VERSION}.linux-amd64"*

    # Get Redis password from Laravel .env if available
    REDIS_PASSWORD=""
    if [[ -f /var/www/chom/.env ]]; then
        REDIS_PASSWORD=$(grep -E "^REDIS_PASSWORD=" /var/www/chom/.env | cut -d'=' -f2 | tr -d '"' || true)
    fi

    # Create environment file
    cat > /etc/exporters/redis_exporter.env << EOF
REDIS_ADDR=redis://localhost:6379
REDIS_PASSWORD=${REDIS_PASSWORD}
EOF
    chmod 600 /etc/exporters/redis_exporter.env

    # Create systemd service
    cat > /etc/systemd/system/redis_exporter.service << 'EOF'
[Unit]
Description=Prometheus Redis Exporter
Wants=network-online.target
After=network-online.target redis-server.service

[Service]
User=exporters
Group=exporters
Type=simple
EnvironmentFile=/etc/exporters/redis_exporter.env
ExecStart=/opt/exporters/bin/redis_exporter \
    --web.listen-address=:9121 \
    --include-system-metrics
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable redis_exporter
    systemctl restart redis_exporter
    log_success "redis_exporter installed and started on port 9121"
}

# =============================================================================
# NGINX EXPORTER
# =============================================================================

install_nginx_exporter() {
    log_info "Installing nginx_exporter ${NGINX_EXPORTER_VERSION}..."

    cd /tmp
    wget -q "https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v${NGINX_EXPORTER_VERSION}/nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz"
    tar xzf "nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz"
    cp nginx-prometheus-exporter /opt/exporters/bin/
    chmod +x /opt/exporters/bin/nginx-prometheus-exporter
    rm -f nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz nginx-prometheus-exporter

    # Create systemd service
    cat > /etc/systemd/system/nginx_exporter.service << 'EOF'
[Unit]
Description=Prometheus Nginx Exporter
Wants=network-online.target
After=network-online.target nginx.service

[Service]
User=exporters
Group=exporters
Type=simple
ExecStart=/opt/exporters/bin/nginx-prometheus-exporter \
    --web.listen-address=:9113 \
    --nginx.scrape-uri=http://127.0.0.1:8080/nginx_status
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable nginx_exporter
    systemctl restart nginx_exporter
    log_success "nginx_exporter installed and started on port 9113"
}

# =============================================================================
# PHP-FPM EXPORTER
# =============================================================================

install_phpfpm_exporter() {
    log_info "Installing php-fpm_exporter ${PHPFPM_EXPORTER_VERSION}..."

    cd /tmp
    wget -q "https://github.com/hipages/php-fpm_exporter/releases/download/v${PHPFPM_EXPORTER_VERSION}/php-fpm_exporter_${PHPFPM_EXPORTER_VERSION}_linux_amd64.tar.gz"
    tar xzf "php-fpm_exporter_${PHPFPM_EXPORTER_VERSION}_linux_amd64.tar.gz"
    cp php-fpm_exporter /opt/exporters/bin/
    chmod +x /opt/exporters/bin/php-fpm_exporter
    rm -f php-fpm_exporter_${PHPFPM_EXPORTER_VERSION}_linux_amd64.tar.gz php-fpm_exporter

    # Create systemd service
    cat > /etc/systemd/system/phpfpm_exporter.service << 'EOF'
[Unit]
Description=Prometheus PHP-FPM Exporter
Wants=network-online.target
After=network-online.target php8.2-fpm.service

[Service]
User=exporters
Group=exporters
Type=simple
ExecStart=/opt/exporters/bin/php-fpm_exporter server \
    --web.listen-address=:9253 \
    --phpfpm.scrape-uri=tcp://127.0.0.1:9000/status
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable phpfpm_exporter
    systemctl restart phpfpm_exporter
    log_success "php-fpm_exporter installed and started on port 9253"
}

# =============================================================================
# PROMTAIL (Log shipping to Loki)
# =============================================================================

install_promtail() {
    log_info "Installing promtail ${PROMTAIL_VERSION}..."

    cd /tmp
    wget -q "https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip"
    unzip -qq "promtail-linux-amd64.zip"
    mv promtail-linux-amd64 /opt/exporters/bin/promtail
    chmod +x /opt/exporters/bin/promtail
    rm -f promtail-linux-amd64.zip

    # Create promtail config
    cat > /etc/exporters/promtail.yml << EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: ${LOKI_URL}/loki/api/v1/push
    tenant_id: landsraad

scrape_configs:
  # System logs
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: system
          host: landsraad
          __path__: /var/log/syslog
      - targets:
          - localhost
        labels:
          job: auth
          host: landsraad
          __path__: /var/log/auth.log

  # Nginx logs
  - job_name: nginx
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx
          host: landsraad
          __path__: /var/log/nginx/*.log
    pipeline_stages:
      - regex:
          expression: '^(?P<remote_addr>[\\d.]+) - (?P<remote_user>[^ ]*) \\[(?P<time_local>[^\\]]+)\\] "(?P<method>\\w+) (?P<request>[^"]*)" (?P<status>\\d+) (?P<body_bytes_sent>\\d+)'
      - labels:
          method:
          status:

  # PHP-FPM logs
  - job_name: php-fpm
    static_configs:
      - targets:
          - localhost
        labels:
          job: php-fpm
          host: landsraad
          __path__: /var/log/php8.2-fpm.log

  # Laravel application logs
  - job_name: laravel
    static_configs:
      - targets:
          - localhost
        labels:
          job: laravel
          host: landsraad
          app: chom
          __path__: /var/www/chom/storage/logs/*.log
    pipeline_stages:
      - multiline:
          firstline: '^\\[\\d{4}-\\d{2}-\\d{2}'
          max_wait_time: 3s
      - regex:
          expression: '^\\[(?P<timestamp>[^\\]]+)\\] (?P<environment>\\w+)\\.(?P<level>\\w+):'
      - labels:
          environment:
          level:

  # PostgreSQL logs
  - job_name: postgresql
    static_configs:
      - targets:
          - localhost
        labels:
          job: postgresql
          host: landsraad
          __path__: /var/log/postgresql/*.log
    pipeline_stages:
      - regex:
          expression: '^(?P<timestamp>[\\d-]+ [\\d:]+\\.[\\d]+) \\w+ \\[(?P<pid>\\d+)\\] (?P<user>[^@]*)@(?P<database>[^ ]*) (?P<level>\\w+):'
      - labels:
          level:
          database:

  # Redis logs
  - job_name: redis
    static_configs:
      - targets:
          - localhost
        labels:
          job: redis
          host: landsraad
          __path__: /var/log/redis/*.log

  # Fail2ban logs
  - job_name: fail2ban
    static_configs:
      - targets:
          - localhost
        labels:
          job: fail2ban
          host: landsraad
          __path__: /var/log/fail2ban.log
    pipeline_stages:
      - regex:
          expression: '(?P<timestamp>[\\d-]+ [\\d:,]+) fail2ban\\.(?P<component>\\w+)\\s+\\[(?P<pid>\\d+)\\]: (?P<level>\\w+)\\s+\\[(?P<jail>[^\\]]+)\\] (?P<action>\\w+) (?P<ip>[\\d.]+)'
      - labels:
          level:
          jail:
          action:
EOF

    # Create systemd service
    cat > /etc/systemd/system/promtail.service << 'EOF'
[Unit]
Description=Promtail Log Agent
Wants=network-online.target
After=network-online.target

[Service]
User=root
Group=root
Type=simple
ExecStart=/opt/exporters/bin/promtail -config.file=/etc/exporters/promtail.yml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable promtail
    systemctl restart promtail
    log_success "promtail installed and started on port 9080"
}

# =============================================================================
# CONFIGURE NGINX STUB STATUS
# =============================================================================

configure_nginx_status() {
    log_info "Configuring nginx stub_status..."

    # Create nginx status config
    cat > /etc/nginx/conf.d/status.conf << 'EOF'
# Nginx status endpoint for prometheus exporter
server {
    listen 8080;
    server_name localhost;

    location /nginx_status {
        stub_status on;
        allow 127.0.0.1;
        deny all;
    }
}
EOF

    # Test and reload nginx
    if nginx -t 2>&1; then
        systemctl reload nginx
        log_success "nginx stub_status configured on port 8080"
    else
        log_error "nginx configuration test failed"
        return 1
    fi
}

# =============================================================================
# CONFIGURE PHP-FPM STATUS
# =============================================================================

configure_phpfpm_status() {
    log_info "Configuring PHP-FPM status..."

    # Find the PHP-FPM pool config
    local pool_config="/etc/php/8.2/fpm/pool.d/www.conf"
    if [[ ! -f "$pool_config" ]]; then
        pool_config="/etc/php/8.2/fpm/pool.d/chom.conf"
    fi

    if [[ -f "$pool_config" ]]; then
        # Enable status page
        if ! grep -q "^pm.status_path" "$pool_config"; then
            echo "pm.status_path = /status" >> "$pool_config"
        else
            sed -i 's|^;*pm.status_path.*|pm.status_path = /status|' "$pool_config"
        fi

        # Enable ping page
        if ! grep -q "^ping.path" "$pool_config"; then
            echo "ping.path = /ping" >> "$pool_config"
        else
            sed -i 's|^;*ping.path.*|ping.path = /ping|' "$pool_config"
        fi

        # Set status listen (if using socket, add TCP for exporter)
        if grep -q "listen = /run/php" "$pool_config"; then
            # Pool uses socket, add TCP listener for status
            if ! grep -q "listen = 127.0.0.1:9000" "$pool_config"; then
                log_info "PHP-FPM uses socket. Creating separate status pool..."

                # Create a separate pool for status
                cat > /etc/php/8.2/fpm/pool.d/status.conf << 'EOF'
[status]
user = www-data
group = www-data
listen = 127.0.0.1:9000
listen.allowed_clients = 127.0.0.1
pm = static
pm.max_children = 1
pm.status_path = /status
ping.path = /ping
EOF
            fi
        fi

        systemctl restart php8.2-fpm
        log_success "PHP-FPM status configured"
    else
        log_warn "PHP-FPM pool config not found, status may not work"
    fi
}

# =============================================================================
# CONFIGURE FIREWALL
# =============================================================================

configure_firewall() {
    log_info "Configuring firewall rules..."

    # Allow Prometheus to scrape from mentat
    if command -v ufw &>/dev/null; then
        ufw allow from 51.254.139.78 to any port 9100 proto tcp comment "node_exporter from mentat"
        ufw allow from 51.254.139.78 to any port 9187 proto tcp comment "postgres_exporter from mentat"
        ufw allow from 51.254.139.78 to any port 9121 proto tcp comment "redis_exporter from mentat"
        ufw allow from 51.254.139.78 to any port 9113 proto tcp comment "nginx_exporter from mentat"
        ufw allow from 51.254.139.78 to any port 9253 proto tcp comment "phpfpm_exporter from mentat"
        log_success "Firewall rules configured for Prometheus scraping"
    else
        log_warn "UFW not found, please configure firewall manually"
    fi
}

# =============================================================================
# VERIFY SERVICES
# =============================================================================

verify_services() {
    log_info "Verifying exporter services..."

    local failed=0
    local services=("postgres_exporter" "redis_exporter" "nginx_exporter" "phpfpm_exporter" "promtail")

    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_success "$service is running"
        else
            log_error "$service failed to start"
            systemctl status "$service" --no-pager | tail -10
            failed=1
        fi
    done

    # Test endpoints
    echo ""
    log_info "Testing exporter endpoints..."

    sleep 2

    for port_name in "9187:postgres_exporter" "9121:redis_exporter" "9113:nginx_exporter" "9253:phpfpm_exporter" "9080:promtail"; do
        port="${port_name%%:*}"
        name="${port_name##*:}"
        if curl -sf "http://localhost:${port}/metrics" >/dev/null 2>&1; then
            log_success "${name} responding on port ${port}"
        else
            log_warn "${name} not responding on port ${port}"
        fi
    done

    return $failed
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo ""
    echo "==========================================="
    echo "  Exporter Deployment for Landsraad"
    echo "==========================================="
    echo ""

    # Check for required services
    if ! systemctl is-active --quiet postgresql; then
        log_warn "PostgreSQL not running - postgres_exporter may fail"
    fi

    if ! systemctl is-active --quiet redis-server; then
        log_warn "Redis not running - redis_exporter may fail"
    fi

    if ! systemctl is-active --quiet nginx; then
        log_warn "Nginx not running - nginx_exporter may fail"
    fi

    if ! systemctl is-active --quiet "php8.2-fpm"; then
        log_warn "PHP-FPM not running - phpfpm_exporter may fail"
    fi

    # Configure services first
    configure_nginx_status
    configure_phpfpm_status

    # Install exporters
    install_postgres_exporter
    install_redis_exporter
    install_nginx_exporter
    install_phpfpm_exporter
    install_promtail

    # Configure firewall
    configure_firewall

    # Verify installation
    echo ""
    verify_services

    echo ""
    echo "==========================================="
    echo "  Exporter Deployment Complete"
    echo "==========================================="
    echo ""
    echo "Exporters installed:"
    echo "  - postgres_exporter  :9187"
    echo "  - redis_exporter     :9121"
    echo "  - nginx_exporter     :9113"
    echo "  - phpfpm_exporter    :9253"
    echo "  - promtail           :9080 -> ${LOKI_URL}"
    echo ""
    echo "IMPORTANT: Update PostgreSQL password in:"
    echo "  /etc/exporters/postgres_exporter.env"
    echo ""
    echo "Prometheus on mentat should now be able to scrape:"
    echo "  - landsraad.arewel.com:9187 (PostgreSQL)"
    echo "  - landsraad.arewel.com:9121 (Redis)"
    echo "  - landsraad.arewel.com:9113 (Nginx)"
    echo "  - landsraad.arewel.com:9253 (PHP-FPM)"
    echo ""
}

main "$@"
