#!/usr/bin/env bash
# Setup UFW firewall for CHOM deployment servers
# Usage: ./setup-firewall.sh [--server mentat|landsraad|both]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utils/logging.sh"

# Default values
SERVER_TYPE="${SERVER_TYPE:-both}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --server)
            SERVER_TYPE="$2"
            shift 2
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

init_deployment_log "firewall-setup-$(date +%Y%m%d_%H%M%S)"
log_section "Firewall Setup"

# Check if UFW is installed
check_ufw_installed() {
    log_step "Checking if UFW is installed"

    if ! command -v ufw &> /dev/null; then
        log_info "UFW not found, installing..."
        sudo apt-get update
        sudo apt-get install -y ufw
        log_success "UFW installed"
    else
        log_success "UFW is already installed"
    fi
}

# Reset UFW to defaults
reset_ufw() {
    log_step "Resetting UFW to defaults"

    echo "y" | sudo ufw reset 2>&1 | tee -a "$LOG_FILE"
    log_success "UFW reset to defaults"
}

# Configure base firewall rules
configure_base_rules() {
    log_step "Configuring base firewall rules"

    # Default policies
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw default deny routed

    # Allow SSH (critical - do this first)
    sudo ufw allow 22/tcp comment 'SSH'

    # Allow SSH from specific IPs if configured
    if [[ -n "${ADMIN_IPS:-}" ]]; then
        for ip in $ADMIN_IPS; do
            sudo ufw allow from "$ip" to any port 22 proto tcp comment "SSH from admin IP"
        done
    fi

    log_success "Base firewall rules configured"
}

# Configure firewall for mentat (observability server)
configure_mentat_firewall() {
    log_section "Configuring firewall for mentat.arewel.com"

    configure_base_rules

    # Prometheus
    sudo ufw allow 9090/tcp comment 'Prometheus'

    # Grafana
    sudo ufw allow 3000/tcp comment 'Grafana'

    # Alert Manager
    sudo ufw allow 9093/tcp comment 'AlertManager'

    # Node Exporter (for self-monitoring)
    sudo ufw allow 9100/tcp comment 'Node Exporter'

    # Allow scraping from landsraad
    if [[ -n "${LANDSRAAD_IP:-}" ]]; then
        sudo ufw allow from "$LANDSRAAD_IP" to any port 9090 proto tcp comment "Prometheus from landsraad"
        sudo ufw allow from "$LANDSRAAD_IP" to any port 9093 proto tcp comment "AlertManager from landsraad"
    fi

    log_success "Mentat firewall rules configured"
}

# Configure firewall for landsraad (application server)
configure_landsraad_firewall() {
    log_section "Configuring firewall for landsraad.arewel.com"

    configure_base_rules

    # HTTP/HTTPS
    sudo ufw allow 80/tcp comment 'HTTP'
    sudo ufw allow 443/tcp comment 'HTTPS'

    # PostgreSQL (localhost only by default)
    # sudo ufw allow 5432/tcp comment 'PostgreSQL'

    # Redis (localhost only by default)
    # sudo ufw allow 6379/tcp comment 'Redis'

    # Node Exporter for Prometheus scraping
    sudo ufw allow 9100/tcp comment 'Node Exporter'

    # Laravel metrics endpoint (if using prometheus exporter)
    sudo ufw allow 9200/tcp comment 'Laravel Metrics'

    # Allow Prometheus scraping from mentat
    if [[ -n "${MENTAT_IP:-}" ]]; then
        sudo ufw allow from "$MENTAT_IP" to any port 9100 proto tcp comment "Node Exporter from mentat"
        sudo ufw allow from "$MENTAT_IP" to any port 9200 proto tcp comment "Laravel metrics from mentat"
    fi

    log_success "Landsraad firewall rules configured"
}

# Configure rate limiting for SSH
configure_ssh_rate_limiting() {
    log_step "Configuring SSH rate limiting"

    sudo ufw limit 22/tcp comment 'Rate limit SSH'

    log_success "SSH rate limiting configured"
}

# Configure logging
configure_ufw_logging() {
    log_step "Configuring UFW logging"

    sudo ufw logging low

    log_success "UFW logging configured"
}

# Enable UFW
enable_ufw() {
    log_step "Enabling UFW"

    echo "y" | sudo ufw enable 2>&1 | tee -a "$LOG_FILE"

    log_success "UFW enabled"
}

# Show UFW status
show_ufw_status() {
    log_step "Current UFW status"

    sudo ufw status verbose | tee -a "$LOG_FILE"

    log_success "UFW status displayed"
}

# Install and configure fail2ban
setup_fail2ban() {
    log_step "Setting up fail2ban for SSH protection"

    if ! command -v fail2ban-client &> /dev/null; then
        log_info "Installing fail2ban..."
        sudo apt-get update
        sudo apt-get install -y fail2ban
        log_success "fail2ban installed"
    else
        log_success "fail2ban is already installed"
    fi

    # Create local configuration
    sudo tee /etc/fail2ban/jail.local > /dev/null <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sendername = Fail2Ban
action = %(action_mwl)s

[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200
EOF

    # Restart fail2ban
    sudo systemctl restart fail2ban
    sudo systemctl enable fail2ban

    log_success "fail2ban configured and enabled"
}

# Main execution
main() {
    start_timer

    check_ufw_installed

    case "$SERVER_TYPE" in
        mentat)
            configure_mentat_firewall
            ;;
        landsraad)
            configure_landsraad_firewall
            ;;
        both)
            log_warning "Server type not specified, configuring base rules only"
            configure_base_rules
            ;;
        *)
            log_error "Invalid server type: $SERVER_TYPE"
            log_error "Valid options: mentat, landsraad, both"
            exit 1
            ;;
    esac

    configure_ssh_rate_limiting
    configure_ufw_logging
    setup_fail2ban
    enable_ufw
    show_ufw_status

    end_timer "Firewall setup"

    print_header "Firewall Setup Complete"
    log_success "UFW is enabled and configured"
    log_success "fail2ban is protecting SSH"
    log_warning "Make sure your current SSH connection is still working!"
    log_info "If you get locked out, you'll need console access to fix it"
}

main
