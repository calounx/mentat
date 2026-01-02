#!/bin/bash

##############################################################################
# Firewall Configuration Setup for Observability Integration
# Configures UFW rules to enable secure communication between:
#   - mentat (51.254.139.78) - Observability stack
#   - landsraad (51.77.150.96) - CHOM application
#
# Usage: sudo ./setup-firewall.sh [--role mentat|landsraad] [--dry-run]
#
# This script implements the principle of least privilege by:
# 1. Allowing only necessary ports
# 2. Restricting to specific IP addresses
# 3. Denying all other traffic by default
##############################################################################

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
MENTAT_IP="51.254.139.78"
LANDSRAAD_IP="51.77.150.96"
ROLE=""
DRY_RUN=false

# Verify running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root (use sudo)${NC}"
    exit 1
fi

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
}

execute_or_simulate() {
    local cmd="$1"
    local description="$2"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] $description"
        log_info "Would execute: $cmd"
    else
        log_info "Executing: $description"
        eval "$cmd"
        log_success "Done: $description"
    fi
}

detect_role() {
    local hostname=$(hostname -f 2>/dev/null || hostname)

    if [[ "$hostname" == *"mentat"* ]]; then
        echo "mentat"
    elif [[ "$hostname" == *"landsraad"* ]]; then
        echo "landsraad"
    else
        echo ""
    fi
}

##############################################################################
# UFW Setup Functions
##############################################################################

setup_ufw_base() {
    log_section "UFW FIREWALL BASE CONFIGURATION"

    # Check if UFW is installed
    if ! command -v ufw &> /dev/null; then
        log_warn "UFW not installed. Installing..."
        execute_or_simulate "apt-get update && apt-get install -y ufw" "Install UFW"
    fi

    # Check current status
    local ufw_status=$(ufw status | head -1)
    log_info "Current UFW status: $ufw_status"

    if [ "$ufw_status" != "Status: active" ]; then
        log_warn "UFW is not active. Enabling..."
        execute_or_simulate "ufw --force enable" "Enable UFW"
    fi

    # Set default policies
    execute_or_simulate "ufw default deny incoming" "Set default incoming policy to DENY"
    execute_or_simulate "ufw default allow outgoing" "Set default outgoing policy to ALLOW"
    execute_or_simulate "ufw default allow routed" "Set default routed policy to ALLOW"

    log_success "UFW base configuration complete"
}

setup_ssh_access() {
    log_section "SSH ACCESS RULES"

    log_info "Configuring SSH access from any source (rate limited)..."

    # Allow SSH with rate limiting
    execute_or_simulate "ufw limit 22/tcp comment 'SSH with rate limit'" "Allow SSH on port 22 with rate limiting"

    log_success "SSH access configured"
}

setup_mentat_firewall() {
    log_section "MENTAT FIREWALL RULES"
    log_info "Configuring firewall for Observability Server (mentat)"

    # Prometheus
    log_info "Configuring Prometheus access..."
    execute_or_simulate "ufw allow from $LANDSRAAD_IP to any port 9090 proto tcp comment 'Prometheus API from CHOM'" "Allow Prometheus from CHOM"
    execute_or_simulate "ufw allow from $LANDSRAAD_IP to any port 9009 proto tcp comment 'Prometheus Remote Write from CHOM'" "Allow Prometheus Remote Write from CHOM"

    # Loki
    log_info "Configuring Loki log ingestion..."
    execute_or_simulate "ufw allow from $LANDSRAAD_IP to any port 3100 proto tcp comment 'Loki Log Ingestion from CHOM'" "Allow Loki from CHOM"

    # Grafana (optional - allow from anywhere for dashboard access)
    log_info "Configuring Grafana access..."
    execute_or_simulate "ufw allow 3000/tcp comment 'Grafana Web UI (public access)'" "Allow Grafana (public)"

    # Local monitoring
    execute_or_simulate "ufw allow from $LANDSRAAD_IP to any port 9100 proto tcp comment 'Node Exporter from CHOM'" "Allow Node Exporter from CHOM"

    log_success "Mentat firewall rules configured"
}

setup_landsraad_firewall() {
    log_section "LANDSRAAD FIREWALL RULES"
    log_info "Configuring firewall for CHOM Application Server (landsraad)"

    # Application HTTP/HTTPS
    log_info "Configuring application web access..."
    execute_or_simulate "ufw allow 80/tcp comment 'HTTP traffic'" "Allow HTTP"
    execute_or_simulate "ufw allow 443/tcp comment 'HTTPS traffic'" "Allow HTTPS"

    # Prometheus scraping from mentat
    log_info "Configuring Prometheus agent and exporters..."
    execute_or_simulate "ufw allow from $MENTAT_IP to any port 9100 proto tcp comment 'Node Exporter - Prometheus scrape'" "Allow Node Exporter from mentat"
    execute_or_simulate "ufw allow from $MENTAT_IP to any port 9253 proto tcp comment 'PHP-FPM Exporter - Prometheus scrape'" "Allow PHP-FPM Exporter from mentat"
    execute_or_simulate "ufw allow from $MENTAT_IP to any port 9113 proto tcp comment 'Nginx Exporter - Prometheus scrape'" "Allow Nginx Exporter from mentat"
    execute_or_simulate "ufw allow from $MENTAT_IP to any port 9121 proto tcp comment 'Redis Exporter - Prometheus scrape'" "Allow Redis Exporter from mentat"
    execute_or_simulate "ufw allow from $MENTAT_IP to any port 9104 proto tcp comment 'MySQL Exporter - Prometheus scrape'" "Allow MySQL Exporter from mentat"
    execute_or_simulate "ufw allow from $MENTAT_IP to any port 8080 proto tcp comment 'CHOM App Metrics - Prometheus scrape'" "Allow CHOM App Metrics from mentat"

    # Alloy/Promtail from local
    log_info "Configuring Alloy local exporters..."
    execute_or_simulate "ufw allow from 127.0.0.1 to any port 12345 proto tcp comment 'Alloy self-monitoring'" "Allow Alloy self-monitoring (localhost)"

    # Database and cache replication (if needed)
    log_info "Configuring database/cache access from mentat..."
    execute_or_simulate "ufw allow from $MENTAT_IP to any port 5432 proto tcp comment 'PostgreSQL from mentat (optional)'" "Allow PostgreSQL from mentat (optional)"
    execute_or_simulate "ufw allow from $MENTAT_IP to any port 3306 proto tcp comment 'MySQL from mentat (optional)'" "Allow MySQL from mentat (optional)"
    execute_or_simulate "ufw allow from $MENTAT_IP to any port 6379 proto tcp comment 'Redis from mentat (optional)'" "Allow Redis from mentat (optional)"

    log_success "Landsraad firewall rules configured"
}

view_current_rules() {
    log_section "CURRENT FIREWALL RULES"

    log_info "Numbered UFW rules:"
    ufw show numbered

    log_info ""
    log_info "UFW status:"
    ufw status

    log_info ""
    log_info "Active iptables rules:"
    iptables -L -n -v | head -50
}

##############################################################################
# Network Interface Configuration
##############################################################################

check_network_interfaces() {
    log_section "NETWORK INTERFACE STATUS"

    log_info "Network interfaces:"
    ip link show

    log_info ""
    log_info "IP addresses:"
    ip addr show

    log_info ""
    log_info "Active connections:"
    netstat -tlnp 2>/dev/null | grep LISTEN || ss -tlnp 2>/dev/null | grep LISTEN
}

##############################################################################
# Security Verification
##############################################################################

verify_firewall_security() {
    log_section "FIREWALL SECURITY VERIFICATION"

    log_info "Checking for common security issues..."

    # Check for open ports
    local open_ports=$(netstat -tlnp 2>/dev/null | grep LISTEN | awk '{print $4}' | cut -d: -f2 | sort -u)

    log_info "Listening ports:"
    echo "$open_ports" | while read -r port; do
        if [ -n "$port" ]; then
            echo "  Port $port"
        fi
    done

    # Check if default deny is set
    local default_incoming=$(ufw status | grep "Default:" | head -1)
    if echo "$default_incoming" | grep -q "deny"; then
        log_success "Default deny policy is set"
    else
        log_warn "Default deny policy may not be properly configured"
    fi
}

##############################################################################
# Configuration Report
##############################################################################

generate_firewall_report() {
    log_section "FIREWALL CONFIGURATION REPORT"

    local report_file="/tmp/firewall-config-report-$(date +%Y%m%d-%H%M%S).txt"

    {
        echo "Firewall Configuration Report"
        echo "Generated: $(date)"
        echo ""
        echo "Server Role: $ROLE"
        echo "Server IP: $(hostname -I | awk '{print $1}')"
        echo "Server Hostname: $(hostname -f)"
        echo ""
        echo "UFW Status:"
        ufw status
        echo ""
        echo "UFW Numbered Rules:"
        ufw show numbered
        echo ""
        echo "Network Interfaces:"
        ip addr show
        echo ""
        echo "Listening Ports:"
        netstat -tlnp 2>/dev/null || ss -tlnp 2>/dev/null
        echo ""
        echo "Routing Table:"
        ip route show
        echo ""
    } | tee "$report_file"

    log_success "Firewall report saved to: $report_file"
}

##############################################################################
# Main Execution
##############################################################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --role)
                ROLE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                echo "Usage: $0 [--role mentat|landsraad] [--dry-run]"
                exit 1
                ;;
        esac
    done

    # Auto-detect role if not specified
    if [ -z "$ROLE" ]; then
        log_info "Auto-detecting server role..."
        ROLE=$(detect_role)
        if [ -z "$ROLE" ]; then
            log_error "Could not auto-detect role. Please specify with --role flag."
            exit 1
        fi
        log_info "Detected role: $ROLE"
    fi

    # Validate role
    if [ "$ROLE" != "mentat" ] && [ "$ROLE" != "landsraad" ]; then
        log_error "Invalid role: $ROLE. Must be 'mentat' or 'landsraad'"
        exit 1
    fi

    log_section "FIREWALL CONFIGURATION FOR OBSERVABILITY INTEGRATION"

    if [ "$DRY_RUN" = true ]; then
        log_warn "Running in DRY-RUN mode. No changes will be made."
        log_warn "Remove --dry-run flag to apply changes."
    fi

    echo "Start Time: $(date)"
    echo ""

    # Common setup
    setup_ufw_base
    setup_ssh_access

    # Role-specific setup
    if [ "$ROLE" = "mentat" ]; then
        setup_mentat_firewall
    else
        setup_landsraad_firewall
    fi

    # Verification and reporting
    check_network_interfaces
    verify_firewall_security
    view_current_rules
    generate_firewall_report

    log_section "FIREWALL SETUP COMPLETE"
    echo "End Time: $(date)"

    if [ "$DRY_RUN" = true ]; then
        log_warn "This was a DRY-RUN. To apply changes, run without --dry-run flag."
    fi
}

# Execute main function
main "$@"
