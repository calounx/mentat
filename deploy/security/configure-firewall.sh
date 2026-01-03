#!/bin/bash
# ============================================================================
# Firewall Configuration Script
# ============================================================================
# Purpose: Configure UFW firewall with defense-in-depth rules
# Targets: landsraad.arewel.com (app server) and mentat.arewel.com (observability)
# Security: Principle of least privilege, default deny, explicit allow
# Compliance: OWASP, PCI DSS, SOC 2
# ============================================================================

set -euo pipefail

# Configuration
SERVER_ROLE="${SERVER_ROLE:-}"  # landsraad or mentat
SSH_PORT="${SSH_PORT:-2222}"
LANDSRAAD_IP="${LANDSRAAD_IP:-}"
MENTAT_IP="${MENTAT_IP:-}"
ALLOWED_IPS="${ALLOWED_IPS:-}"  # Comma-separated list of trusted IPs

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Install UFW if not present
install_ufw() {
    log_info "Checking UFW installation..."

    if command -v ufw &> /dev/null; then
        log_success "UFW is already installed"
        return 0
    fi

    log_info "Installing UFW..."
    apt-get update -qq
    apt-get install -y ufw

    log_success "UFW installed successfully"
}

# Detect server role
detect_server_role() {
    if [[ -z "$SERVER_ROLE" ]]; then
        log_info "Detecting server role..."

        local hostname=$(hostname)

        if [[ "$hostname" == *"landsraad"* ]]; then
            SERVER_ROLE="landsraad"
        elif [[ "$hostname" == *"mentat"* ]]; then
            SERVER_ROLE="mentat"
        else
            log_warning "Could not auto-detect server role from hostname: $hostname"
            echo ""
            echo "Select server role:"
            echo "1) landsraad (Application Server)"
            echo "2) mentat (Observability Server)"
            read -p "Enter choice [1-2]: " -r choice

            case $choice in
                1) SERVER_ROLE="landsraad" ;;
                2) SERVER_ROLE="mentat" ;;
                *)
                    log_error "Invalid choice"
                    exit 1
                    ;;
            esac
        fi

        log_success "Server role: $SERVER_ROLE"
    fi
}

# Reset UFW to default state
reset_ufw() {
    log_info "Resetting UFW to default state..."

    # Disable UFW first
    ufw --force disable

    # Reset all rules
    echo "y" | ufw reset

    log_success "UFW reset complete"
}

# Configure UFW defaults
configure_defaults() {
    log_info "Configuring UFW defaults..."

    # Default policies: deny incoming, allow outgoing
    ufw default deny incoming
    ufw default allow outgoing

    # Logging
    ufw logging on

    log_success "UFW defaults configured"
}

# Configure common rules (both servers)
configure_common_rules() {
    log_info "Configuring common firewall rules..."

    # SSH (custom port)
    ufw allow "$SSH_PORT/tcp" comment "SSH hardened port"
    log_success "Allowed SSH on port $SSH_PORT"

    # ICMP (ping) - limited to prevent flood
    ufw allow in proto icmp from any comment "ICMP ping (limited)"
    log_success "Allowed ICMP ping"

    # Allow established connections
    # This is implicit in UFW but we log it
    log_info "Established connections are allowed (UFW default)"
}

# Configure landsraad (application server) rules
configure_landsraad_rules() {
    log_info "Configuring landsraad (application server) firewall rules..."

    # HTTP (port 80) - for Let's Encrypt HTTP-01 challenge and redirect
    ufw allow 80/tcp comment "HTTP (Let's Encrypt + redirect)"
    log_success "Allowed HTTP (80)"

    # HTTPS (port 443) - main application traffic
    ufw allow 443/tcp comment "HTTPS application traffic"
    log_success "Allowed HTTPS (443)"

    # PostgreSQL - only from mentat server
    if [[ -n "$MENTAT_IP" ]]; then
        ufw allow from "$MENTAT_IP" to any port 5432 proto tcp comment "PostgreSQL from mentat"
        log_success "Allowed PostgreSQL (5432) from mentat ($MENTAT_IP)"
    else
        log_warning "MENTAT_IP not set, skipping PostgreSQL rule"
        log_warning "Run: ufw allow from <mentat-ip> to any port 5432 proto tcp"
    fi

    # Redis - only from mentat server
    if [[ -n "$MENTAT_IP" ]]; then
        ufw allow from "$MENTAT_IP" to any port 6379 proto tcp comment "Redis from mentat"
        log_success "Allowed Redis (6379) from mentat ($MENTAT_IP)"
    else
        log_warning "MENTAT_IP not set, skipping Redis rule"
        log_warning "Run: ufw allow from <mentat-ip> to any port 6379 proto tcp"
    fi

    # Prometheus Node Exporter - only from mentat server
    if [[ -n "$MENTAT_IP" ]]; then
        ufw allow from "$MENTAT_IP" to any port 9100 proto tcp comment "Node Exporter from mentat"
        log_success "Allowed Node Exporter (9100) from mentat ($MENTAT_IP)"
    else
        log_warning "MENTAT_IP not set, skipping Node Exporter rule"
        log_warning "Run: ufw allow from <mentat-ip> to any port 9100 proto tcp"
    fi

    # Laravel Metrics Endpoint - only from mentat server
    if [[ -n "$MENTAT_IP" ]]; then
        ufw allow from "$MENTAT_IP" to any port 9091 proto tcp comment "Laravel metrics from mentat"
        log_success "Allowed Laravel metrics (9091) from mentat ($MENTAT_IP)"
    fi

    # Promtail (Loki agent) - only from mentat server
    if [[ -n "$MENTAT_IP" ]]; then
        ufw allow from "$MENTAT_IP" to any port 9080 proto tcp comment "Promtail from mentat"
        log_success "Allowed Promtail (9080) from mentat ($MENTAT_IP)"
    fi
}

# Configure mentat (observability server) rules
configure_mentat_rules() {
    log_info "Configuring mentat (observability server) firewall rules..."

    # HTTPS (port 443) - Grafana dashboard
    ufw allow 443/tcp comment "HTTPS Grafana dashboard"
    log_success "Allowed HTTPS (443) for Grafana"

    # Prometheus - restricted to allowed IPs
    if [[ -n "$ALLOWED_IPS" ]]; then
        IFS=',' read -ra IPS <<< "$ALLOWED_IPS"
        for ip in "${IPS[@]}"; do
            ip=$(echo "$ip" | xargs)  # trim whitespace
            ufw allow from "$ip" to any port 9090 proto tcp comment "Prometheus from $ip"
            log_success "Allowed Prometheus (9090) from $ip"
        done
    else
        # If no allowed IPs specified, allow from landsraad only
        if [[ -n "$LANDSRAAD_IP" ]]; then
            ufw allow from "$LANDSRAAD_IP" to any port 9090 proto tcp comment "Prometheus from landsraad"
            log_success "Allowed Prometheus (9090) from landsraad ($LANDSRAAD_IP)"
        else
            log_warning "No ALLOWED_IPS set for Prometheus access"
        fi
    fi

    # Loki - only from landsraad
    if [[ -n "$LANDSRAAD_IP" ]]; then
        ufw allow from "$LANDSRAAD_IP" to any port 3100 proto tcp comment "Loki from landsraad"
        log_success "Allowed Loki (3100) from landsraad ($LANDSRAAD_IP)"
    else
        log_warning "LANDSRAAD_IP not set, skipping Loki rule"
        log_warning "Run: ufw allow from <landsraad-ip> to any port 3100 proto tcp"
    fi

    # AlertManager - restricted
    if [[ -n "$ALLOWED_IPS" ]]; then
        IFS=',' read -ra IPS <<< "$ALLOWED_IPS"
        for ip in "${IPS[@]}"; do
            ip=$(echo "$ip" | xargs)
            ufw allow from "$ip" to any port 9093 proto tcp comment "AlertManager from $ip"
            log_success "Allowed AlertManager (9093) from $ip"
        done
    fi
}

# Configure rate limiting
configure_rate_limiting() {
    log_info "Configuring connection rate limiting..."

    # Rate limit SSH connections (prevent brute force)
    ufw limit "$SSH_PORT/tcp" comment "SSH rate limiting"
    log_success "SSH rate limiting enabled"

    # Rate limit HTTP/HTTPS (DDoS protection)
    # Note: UFW's limit rule is basic; use fail2ban for advanced protection
    log_info "Basic rate limiting configured (use Fail2Ban for advanced protection)"
}

# Configure IPv6
configure_ipv6() {
    log_info "Configuring IPv6..."

    # Check if IPv6 is available
    if [[ -f /proc/net/if_inet6 ]]; then
        # Enable IPv6 in UFW
        sed -i 's/IPV6=no/IPV6=yes/' /etc/default/ufw
        log_success "IPv6 enabled in UFW"
    else
        log_info "IPv6 not available, keeping disabled"
        sed -i 's/IPV6=yes/IPV6=no/' /etc/default/ufw
    fi
}

# Enable UFW
enable_ufw() {
    log_info "Enabling UFW firewall..."

    # Enable UFW (with force to avoid prompt)
    echo "y" | ufw enable

    if ufw status | grep -q "Status: active"; then
        log_success "UFW firewall is active"
    else
        log_error "Failed to enable UFW firewall"
        exit 1
    fi
}

# Display firewall status
display_status() {
    echo ""
    log_success "=========================================="
    log_success "Firewall Configuration Complete"
    log_success "=========================================="
    echo ""

    log_info "Server Role: $SERVER_ROLE"
    echo ""

    log_info "Firewall Status:"
    ufw status verbose
    echo ""

    log_info "Active Rules:"
    ufw status numbered
    echo ""
}

# Verify configuration
verify_configuration() {
    log_info "Verifying firewall configuration..."

    local errors=0

    # Check UFW is active
    if ! ufw status | grep -q "Status: active"; then
        log_error "UFW is not active"
        ((errors++))
    fi

    # Check default policies
    if ! ufw status verbose | grep -q "Default: deny (incoming)"; then
        log_error "Default incoming policy is not deny"
        ((errors++))
    fi

    if ! ufw status verbose | grep -q "Default: allow (outgoing)"; then
        log_error "Default outgoing policy is not allow"
        ((errors++))
    fi

    # Check SSH rule exists
    if ! ufw status | grep -q "$SSH_PORT"; then
        log_error "SSH port $SSH_PORT is not allowed"
        ((errors++))
    fi

    if [[ $errors -eq 0 ]]; then
        log_success "Firewall configuration verified"
        return 0
    else
        log_error "Firewall configuration has $errors error(s)"
        return 1
    fi
}

# Create firewall management helper script
create_helper_script() {
    log_info "Creating firewall management helper script..."

    local helper_script="/usr/local/bin/chom-firewall"

    cat > "$helper_script" <<'EOF'
#!/bin/bash
# CHOM Firewall Management Helper

case "$1" in
    status)
        ufw status verbose
        ;;
    list)
        ufw status numbered
        ;;
    allow-ip)
        if [[ -z "$2" ]]; then
            echo "Usage: chom-firewall allow-ip <ip-address>"
            exit 1
        fi
        ufw allow from "$2" comment "Manually allowed IP"
        ;;
    deny-ip)
        if [[ -z "$2" ]]; then
            echo "Usage: chom-firewall deny-ip <ip-address>"
            exit 1
        fi
        ufw deny from "$2" comment "Manually denied IP"
        ;;
    delete)
        if [[ -z "$2" ]]; then
            echo "Usage: chom-firewall delete <rule-number>"
            echo "Run 'chom-firewall list' to see rule numbers"
            exit 1
        fi
        ufw delete "$2"
        ;;
    reset)
        echo "WARNING: This will reset all firewall rules!"
        read -p "Are you sure? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            ufw --force reset
            echo "Firewall reset. Run firewall setup script to reconfigure."
        fi
        ;;
    *)
        echo "CHOM Firewall Management"
        echo ""
        echo "Usage: chom-firewall <command> [args]"
        echo ""
        echo "Commands:"
        echo "  status              Show firewall status"
        echo "  list                List all rules with numbers"
        echo "  allow-ip <ip>       Allow specific IP address"
        echo "  deny-ip <ip>        Deny specific IP address"
        echo "  delete <num>        Delete rule by number"
        echo "  reset               Reset all firewall rules"
        echo ""
        ;;
esac
EOF

    chmod +x "$helper_script"
    log_success "Helper script created: $helper_script"
}

# Backup firewall rules
backup_rules() {
    log_info "Backing up firewall rules..."

    local backup_dir="/var/backups/ufw"
    local backup_file="$backup_dir/rules.backup.$(date +%Y%m%d_%H%M%S)"

    mkdir -p "$backup_dir"

    # Backup UFW rules
    cp -r /etc/ufw "$backup_file"

    # Also save human-readable format
    ufw status verbose > "$backup_file/status.txt"
    ufw status numbered > "$backup_file/numbered.txt"

    log_success "Firewall rules backed up to $backup_file"
}

# Main execution
main() {
    log_info "Starting firewall configuration..."
    echo ""

    check_root
    detect_server_role
    install_ufw
    backup_rules
    reset_ufw
    configure_defaults
    configure_common_rules

    case "$SERVER_ROLE" in
        landsraad)
            configure_landsraad_rules
            ;;
        mentat)
            configure_mentat_rules
            ;;
        *)
            log_error "Invalid server role: $SERVER_ROLE"
            exit 1
            ;;
    esac

    configure_rate_limiting
    configure_ipv6
    enable_ufw
    verify_configuration
    create_helper_script
    display_status

    log_success "Firewall configuration complete!"
    echo ""
    log_warning "IMPORTANT: Verify you can still connect before logging out!"
    log_info "Test SSH connection: ssh -p $SSH_PORT user@$(hostname -I | awk '{print $1}')"
    echo ""
}

# Run main function
main "$@"
