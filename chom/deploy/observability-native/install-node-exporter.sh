#!/bin/bash

###############################################################################
# Native Node Exporter Installation for Debian 13
# NO DOCKER - Systemd service only
###############################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration
NODE_EXPORTER_VERSION="1.7.0"
NODE_EXPORTER_USER="node_exporter"
NODE_EXPORTER_GROUP="node_exporter"
NODE_EXPORTER_PORT=9100
DOWNLOAD_URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

create_user() {
    log_info "Creating Node Exporter user and group..."

    if ! getent group "$NODE_EXPORTER_GROUP" > /dev/null 2>&1; then
        groupadd --system "$NODE_EXPORTER_GROUP"
        log_success "Created group: $NODE_EXPORTER_GROUP"
    fi

    if ! getent passwd "$NODE_EXPORTER_USER" > /dev/null 2>&1; then
        useradd --system \
            --gid "$NODE_EXPORTER_GROUP" \
            --no-create-home \
            --shell /bin/false \
            "$NODE_EXPORTER_USER"
        log_success "Created user: $NODE_EXPORTER_USER"
    fi
}

download_node_exporter() {
    log_info "Downloading Node Exporter v${NODE_EXPORTER_VERSION}..."

    local temp_dir=$(mktemp -d)
    cd "$temp_dir"

    if ! wget -q --show-progress "$DOWNLOAD_URL"; then
        log_error "Failed to download Node Exporter"
        rm -rf "$temp_dir"
        exit 1
    fi

    log_info "Extracting Node Exporter..."
    tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"

    cd "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64"

    # Install binary
    cp node_exporter /usr/local/bin/

    # Set permissions
    chown "$NODE_EXPORTER_USER:$NODE_EXPORTER_GROUP" /usr/local/bin/node_exporter
    chmod 755 /usr/local/bin/node_exporter

    cd /
    rm -rf "$temp_dir"

    log_success "Node Exporter binary installed"
}

create_systemd_service() {
    log_info "Creating systemd service..."

    cat > /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Prometheus Node Exporter
Documentation=https://github.com/prometheus/node_exporter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$NODE_EXPORTER_USER
Group=$NODE_EXPORTER_GROUP

ExecStart=/usr/local/bin/node_exporter \\
    --web.listen-address=0.0.0.0:$NODE_EXPORTER_PORT \\
    --collector.textfile.directory=/var/lib/node_exporter/textfile_collector \\
    --collector.filesystem.mount-points-exclude='^/(dev|proc|sys|var/lib/docker/.+|var/lib/kubelet/.+)(\$|/)' \\
    --collector.filesystem.fs-types-exclude='^(autofs|binfmt_misc|bpf|cgroup2?|configfs|debugfs|devpts|devtmpfs|fusectl|hugetlbfs|iso9660|mqueue|nsfs|overlay|proc|procfs|pstore|rpc_pipefs|securityfs|selinuxfs|squashfs|sysfs|tracefs)$' \\
    --collector.netclass.ignored-devices='^(veth.*|docker.*|br-.*)\$' \\
    --collector.netdev.device-exclude='^(veth.*|docker.*|br-.*)\$' \\
    --collector.diskstats.ignored-devices='^(ram|loop|fd|(h|s|v|xv)d[a-z]|nvme\\d+n\\d+p)\\d+\$'

Restart=on-failure
RestartSec=5s

StandardOutput=journal
StandardError=journal
SyslogIdentifier=node_exporter

# Security settings
NoNewPrivileges=true
ProtectHome=true
PrivateTmp=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ReadOnlyPaths=/
ReadWritePaths=/var/lib/node_exporter

# Allow access to system metrics
CapabilityBoundingSet=
AmbientCapabilities=

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Systemd service created"
}

create_textfile_directory() {
    log_info "Creating textfile collector directory..."

    mkdir -p /var/lib/node_exporter/textfile_collector
    chown -R "$NODE_EXPORTER_USER:$NODE_EXPORTER_GROUP" /var/lib/node_exporter
    chmod 755 /var/lib/node_exporter
    chmod 755 /var/lib/node_exporter/textfile_collector

    log_success "Textfile collector directory created"
}

create_custom_metrics_example() {
    log_info "Creating custom metrics example..."

    cat > /usr/local/bin/generate-custom-metrics.sh <<'EOF'
#!/bin/bash
# Example script to generate custom metrics for Node Exporter
# This script can be run via cron to expose custom metrics

OUTPUT_FILE="/var/lib/node_exporter/textfile_collector/custom_metrics.prom"
TEMP_FILE="${OUTPUT_FILE}.$$"

# Generate metrics
cat > "$TEMP_FILE" <<METRICS
# HELP chom_deployment_info CHOM deployment information
# TYPE chom_deployment_info gauge
chom_deployment_info{version="1.0.0",environment="production"} 1

# HELP chom_last_backup_timestamp Last successful backup timestamp
# TYPE chom_last_backup_timestamp gauge
chom_last_backup_timestamp $(date +%s)

# HELP chom_disk_usage_percent Disk usage percentage for CHOM data
# TYPE chom_disk_usage_percent gauge
chom_disk_usage_percent $(df /var/www/chom | tail -1 | awk '{print $5}' | sed 's/%//')
METRICS

# Atomically move the file
mv "$TEMP_FILE" "$OUTPUT_FILE"
EOF

    chmod +x /usr/local/bin/generate-custom-metrics.sh
    chown root:root /usr/local/bin/generate-custom-metrics.sh

    # Generate initial metrics
    /usr/local/bin/generate-custom-metrics.sh 2>/dev/null || true

    log_success "Custom metrics example created"
}

configure_firewall() {
    log_info "Configuring firewall for Node Exporter..."

    if command -v ufw &> /dev/null; then
        ufw allow from 192.168.0.0/16 to any port "$NODE_EXPORTER_PORT" proto tcp comment "Node Exporter"
        log_success "UFW rule added for port $NODE_EXPORTER_PORT (limited to local network)"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=192.168.0.0/16 port port=$NODE_EXPORTER_PORT protocol=tcp accept"
        firewall-cmd --reload
        log_success "Firewalld rule added for port $NODE_EXPORTER_PORT (limited to local network)"
    else
        log_warning "No firewall detected. Consider restricting access to port $NODE_EXPORTER_PORT"
    fi
}

start_service() {
    log_info "Starting Node Exporter service..."

    systemctl enable node_exporter
    systemctl start node_exporter

    sleep 2

    if systemctl is-active --quiet node_exporter; then
        log_success "Node Exporter is running"

        # Test endpoint
        if curl -s http://localhost:$NODE_EXPORTER_PORT/metrics | head -5 | grep -q "# HELP"; then
            log_success "Node Exporter metrics accessible"
        else
            log_warning "Node Exporter started but metrics not accessible"
        fi
    else
        log_error "Failed to start Node Exporter"
        systemctl status node_exporter --no-pager
        exit 1
    fi
}

show_metrics_sample() {
    log_info "Sample metrics output:"
    curl -s http://localhost:$NODE_EXPORTER_PORT/metrics | head -20 || true
}

show_status() {
    echo ""
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN} Node Exporter Installation Complete${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "Version:        ${BOLD}$NODE_EXPORTER_VERSION${NC}"
    echo -e "Metrics URL:    ${BOLD}http://localhost:$NODE_EXPORTER_PORT/metrics${NC}"
    echo -e "Service:        ${BOLD}node_exporter.service${NC}"
    echo ""
    echo -e "${BOLD}Useful Commands:${NC}"
    echo "  systemctl status node_exporter      - Check service status"
    echo "  systemctl restart node_exporter     - Restart service"
    echo "  journalctl -u node_exporter -f      - View logs"
    echo "  curl http://localhost:$NODE_EXPORTER_PORT/metrics  - View all metrics"
    echo ""
    echo -e "${BOLD}Enabled Collectors:${NC}"
    echo "  - CPU metrics"
    echo "  - Memory metrics"
    echo "  - Disk I/O and usage"
    echo "  - Network statistics"
    echo "  - Filesystem metrics"
    echo "  - Load averages"
    echo "  - System uptime"
    echo "  - Textfile collector (custom metrics)"
    echo ""
    echo -e "${BOLD}Custom Metrics:${NC}"
    echo "  Directory: /var/lib/node_exporter/textfile_collector"
    echo "  Example script: /usr/local/bin/generate-custom-metrics.sh"
    echo ""
    echo -e "${BOLD}Add to Cron for Custom Metrics:${NC}"
    echo "  */5 * * * * /usr/local/bin/generate-custom-metrics.sh"
    echo ""
    echo -e "${BOLD}Key Metrics to Monitor:${NC}"
    echo "  node_cpu_seconds_total              - CPU usage"
    echo "  node_memory_MemAvailable_bytes      - Available memory"
    echo "  node_filesystem_avail_bytes         - Disk space"
    echo "  node_load1, node_load5, node_load15 - System load"
    echo "  node_network_receive_bytes_total    - Network traffic"
    echo ""
}

main() {
    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║     Native Node Exporter Installation - Debian 13         ║"
    echo "║     NO DOCKER - Systemd Service Only                      ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_root
    create_user
    download_node_exporter
    create_textfile_directory
    create_custom_metrics_example
    create_systemd_service
    configure_firewall
    start_service
    show_status
}

main "$@"
