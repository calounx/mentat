#!/usr/bin/env bash
# Prepare mentat.arewel.com for observability stack deployment
# This script installs Docker and configures the system
# Usage: ./prepare-mentat.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utils/logging.sh"

# Configuration
DEPLOY_USER="${DEPLOY_USER:-stilgar}"
OBSERVABILITY_DIR="${OBSERVABILITY_DIR:-/opt/observability}"
DATA_DIR="${DATA_DIR:-/var/lib/observability}"

init_deployment_log "prepare-mentat-$(date +%Y%m%d_%H%M%S)"
log_section "Preparing mentat.arewel.com"

# Update system packages
update_system() {
    log_step "Updating system packages"

    sudo apt-get update
    sudo apt-get upgrade -y
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common \
        apt-transport-https \
        wget \
        git \
        unzip \
        htop \
        vim \
        net-tools \
        dnsutils \
        jq

    log_success "System packages updated"
}

# Install Docker
install_docker() {
    log_step "Installing Docker"

    if command -v docker &> /dev/null; then
        log_success "Docker is already installed"
        docker --version | tee -a "$LOG_FILE"
        return 0
    fi

    # Add Docker's official GPG key
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # Add Docker repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Enable and start Docker
    sudo systemctl enable docker
    sudo systemctl start docker

    log_success "Docker installed"
    docker --version | tee -a "$LOG_FILE"
}

# Configure Docker
configure_docker() {
    log_step "Configuring Docker"

    # Create Docker daemon configuration
    sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "metrics-addr": "127.0.0.1:9323",
    "experimental": false
}
EOF

    # Restart Docker to apply configuration
    sudo systemctl restart docker

    log_success "Docker configured"
}

# Create deployment user
create_deploy_user() {
    log_step "Creating deployment user: $DEPLOY_USER"

    if id "$DEPLOY_USER" &>/dev/null; then
        log_success "User $DEPLOY_USER already exists"
    else
        # Create user with home directory
        sudo useradd -m -s /bin/bash "$DEPLOY_USER"
        log_success "User $DEPLOY_USER created"
    fi

    # Add user to docker group
    sudo usermod -aG docker "$DEPLOY_USER"

    # Create .ssh directory
    sudo mkdir -p /home/${DEPLOY_USER}/.ssh
    sudo chown -R ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.ssh
    sudo chmod 700 /home/${DEPLOY_USER}/.ssh

    log_success "User $DEPLOY_USER configured for Docker access"
}

# Setup observability directories
setup_observability_directories() {
    log_step "Setting up observability directories"

    # Create main directory
    sudo mkdir -p "$OBSERVABILITY_DIR"
    sudo chown -R ${DEPLOY_USER}:${DEPLOY_USER} "$OBSERVABILITY_DIR"
    sudo chmod 755 "$OBSERVABILITY_DIR"

    # Create data directories
    sudo mkdir -p "${DATA_DIR}/prometheus"
    sudo mkdir -p "${DATA_DIR}/grafana"
    sudo mkdir -p "${DATA_DIR}/alertmanager"
    sudo mkdir -p "${DATA_DIR}/loki"

    # Set permissions (Prometheus runs as nobody:nobody, UID/GID 65534)
    sudo chown -R 65534:65534 "${DATA_DIR}/prometheus"
    sudo chown -R 472:472 "${DATA_DIR}/grafana"  # Grafana UID
    sudo chown -R 65534:65534 "${DATA_DIR}/alertmanager"
    sudo chown -R 10001:10001 "${DATA_DIR}/loki"  # Loki UID

    # Create configuration directory
    sudo mkdir -p "${OBSERVABILITY_DIR}/config"
    sudo chown -R ${DEPLOY_USER}:${DEPLOY_USER} "${OBSERVABILITY_DIR}/config"

    log_success "Observability directories configured"
}

# Install Docker Compose standalone (if needed)
install_docker_compose_standalone() {
    log_step "Checking Docker Compose"

    if docker compose version &> /dev/null; then
        log_success "Docker Compose (plugin) is available"
        docker compose version | tee -a "$LOG_FILE"
        return 0
    fi

    if command -v docker-compose &> /dev/null; then
        log_success "Docker Compose (standalone) is available"
        docker-compose --version | tee -a "$LOG_FILE"
        return 0
    fi

    log_info "Installing Docker Compose standalone"

    local compose_version="2.24.0"
    sudo curl -L "https://github.com/docker/compose/releases/download/v${compose_version}/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose

    log_success "Docker Compose installed"
    docker-compose --version | tee -a "$LOG_FILE"
}

# Install monitoring tools
install_monitoring() {
    log_step "Installing monitoring tools"

    # Install Node Exporter for Prometheus
    local node_exporter_version="1.7.0"
    local node_exporter_url="https://github.com/prometheus/node_exporter/releases/download/v${node_exporter_version}/node_exporter-${node_exporter_version}.linux-amd64.tar.gz"

    cd /tmp
    wget -q "$node_exporter_url"
    tar xzf "node_exporter-${node_exporter_version}.linux-amd64.tar.gz"
    sudo mv "node_exporter-${node_exporter_version}.linux-amd64/node_exporter" /usr/local/bin/
    rm -rf "node_exporter-${node_exporter_version}.linux-amd64"*

    # Create systemd service for node_exporter
    sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable node_exporter
    sudo systemctl start node_exporter

    log_success "Node Exporter installed and running"
}

# Configure system limits for containers
configure_system_limits() {
    log_step "Configuring system limits"

    # Increase file descriptor limits
    sudo tee -a /etc/security/limits.conf > /dev/null <<EOF

# Limits for observability stack
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
EOF

    # Configure sysctl for containers
    sudo tee /etc/sysctl.d/99-observability.conf > /dev/null <<EOF
# Increase connection tracking
net.netfilter.nf_conntrack_max = 262144

# Increase maximum number of memory map areas
vm.max_map_count = 262144

# Increase buffer sizes
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# Enable BBR congestion control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

    # Apply sysctl settings
    sudo sysctl -p /etc/sysctl.d/99-observability.conf

    log_success "System limits configured"
}

# Setup log rotation for Docker containers
setup_log_rotation() {
    log_step "Setting up log rotation for Docker"

    sudo tee /etc/logrotate.d/docker-containers > /dev/null <<EOF
/var/lib/docker/containers/*/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF

    log_success "Log rotation configured"
}

# Install utility tools
install_utilities() {
    log_step "Installing utility tools"

    # Install ctop for container monitoring
    sudo wget -q https://github.com/bcicen/ctop/releases/download/v0.7.7/ctop-0.7.7-linux-amd64 \
        -O /usr/local/bin/ctop
    sudo chmod +x /usr/local/bin/ctop

    # Install lazydocker for container management
    curl -sS https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash

    log_success "Utility tools installed"
}

# Harden system security
harden_security() {
    log_step "Hardening system security"

    # Disable root SSH login
    sudo sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

    # Disable password authentication (use SSH keys only)
    sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

    # Restart SSH
    sudo systemctl restart sshd

    # Configure automatic security updates
    sudo apt-get install -y unattended-upgrades
    sudo dpkg-reconfigure -plow unattended-upgrades

    log_success "Security hardening applied"
}

# Create systemd service for observability stack
create_systemd_service() {
    log_step "Creating systemd service for observability stack"

    sudo tee /etc/systemd/system/observability-stack.service > /dev/null <<EOF
[Unit]
Description=CHOM Observability Stack
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${OBSERVABILITY_DIR}
User=${DEPLOY_USER}
Group=${DEPLOY_USER}

# Start the stack
ExecStart=/usr/bin/docker compose -f ${OBSERVABILITY_DIR}/docker-compose.yml up -d

# Stop the stack
ExecStop=/usr/bin/docker compose -f ${OBSERVABILITY_DIR}/docker-compose.yml down

# Reload the stack
ExecReload=/usr/bin/docker compose -f ${OBSERVABILITY_DIR}/docker-compose.yml restart

Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload

    log_success "Systemd service created (will be enabled after stack deployment)"
}

# Main execution
main() {
    start_timer

    print_header "Preparing mentat.arewel.com for observability stack"

    update_system
    create_deploy_user
    install_docker
    configure_docker
    install_docker_compose_standalone
    setup_observability_directories
    install_monitoring
    configure_system_limits
    setup_log_rotation
    install_utilities
    harden_security
    create_systemd_service

    end_timer "Server preparation"

    print_header "Server Preparation Complete"
    log_success "mentat.arewel.com is ready for observability stack deployment"
    log_info "Next steps:"
    log_info "  1. Run setup-firewall.sh --server mentat"
    log_info "  2. Run setup-ssl.sh for Grafana domain (optional)"
    log_info "  3. Deploy observability stack with deploy-observability.sh"
    log_warning "Remember to logout and login again for docker group to take effect"
}

main
