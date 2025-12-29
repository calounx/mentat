#!/bin/bash
#===============================================================================
# Observability Stack Setup Wizard
# Interactive setup for first-time installation
#
# Usage:
#   ./setup-wizard.sh
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${BASE_DIR}/config/global.yaml"

# Colors
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD='\033[1m'
NC=$'\033[0m'

# Configuration values
VPS_IP=""
DOMAIN=""
EMAIL=""
SMTP_HOST="smtp-relay.brevo.com"
SMTP_PORT="587"
SMTP_USER=""
SMTP_PASS=""
SMTP_FROM=""
GRAFANA_PASS=""
PROM_PASS=""
LOKI_PASS=""

#===============================================================================
# HELPER FUNCTIONS
#===============================================================================

print_header() {
    echo ""
    echo "${BOLD}${BLUE}=========================================="
    echo -e "$1"
    echo "==========================================${NC}"
    echo ""
}

print_step() {
    echo "${CYAN}[$1]${NC} $2"
}

print_success() {
    echo "${GREEN}✓${NC} $1"
}

print_warn() {
    echo "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo "${RED}✗${NC} $1"
}

prompt() {
    local var_name="$1"
    local prompt_text="$2"
    local default="${3:-}"
    local secret="${4:-false}"

    if [[ -n "$default" ]]; then
        if [[ "$secret" == "true" ]]; then
            read -sp "$prompt_text [$default]: " value
        else
            read -p "$prompt_text [$default]: " value
        fi
        echo
        value="${value:-$default}"
    else
        if [[ "$secret" == "true" ]]; then
            read -sp "$prompt_text: " value
            echo
        else
            read -p "$prompt_text: " value
        fi
    fi

    # SECURITY: Use printf -v instead of eval for variable assignment
    # Prevents code injection if var_name contains malicious code
    printf -v "$var_name" '%s' "$value"
}

confirm() {
    local prompt="$1"
    local default="${2:-y}"

    if [[ "$default" == "y" ]]; then
        read -p "$prompt [Y/n]: " -n 1 -r
    else
        read -p "$prompt [y/N]: " -n 1 -r
    fi
    echo

    if [[ -z "$REPLY" ]]; then
        [[ "$default" == "y" ]]
    else
        [[ $REPLY =~ ^[Yy]$ ]]
    fi
}

validate_ip() {
    local ip="$1"
    [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
}

validate_email() {
    local email="$1"
    [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

validate_domain() {
    local domain="$1"
    [[ "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\.[a-zA-Z]{2,}$ ]]
}

generate_password() {
    openssl rand -base64 24 | tr -d "=+/" | cut -c1-20
}

test_connectivity() {
    local host="$1"
    local port="$2"
    timeout 3 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null
}

#===============================================================================
# WIZARD STEPS
#===============================================================================

step_welcome() {
    clear
    print_header "Observability Stack Setup Wizard"

    cat << 'EOF'
This wizard will guide you through setting up your observability stack.

What you'll need:
  1. A domain name pointing to this server
  2. SMTP credentials for email alerts (e.g., Brevo, SendGrid)
  3. About 10-15 minutes

What will be installed:
  • Prometheus - Metrics collection and alerting
  • Loki - Log aggregation
  • Grafana - Visualization dashboards
  • Alertmanager - Alert routing
  • Nginx - Reverse proxy with SSL

Press Enter to continue or Ctrl+C to exit
EOF

    read -r
}

step_prerequisites() {
    print_header "Step 1/7: Prerequisites Check"

    local all_ok=true

    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        print_success "Running as root"
    else
        print_error "Not running as root"
        echo "  Run: sudo $0"
        all_ok=false
    fi

    # Check internet connectivity
    if ping -c 1 8.8.8.8 &>/dev/null; then
        print_success "Internet connectivity available"
    else
        print_warn "Cannot reach 8.8.8.8 - internet may be unavailable"
        echo "  Some features may not work"
    fi

    # Check disk space (need at least 5GB)
    local available
    available=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    if [[ "$available" -gt 5 ]]; then
        print_success "Sufficient disk space (${available}GB available)"
    else
        print_warn "Low disk space (${available}GB available, recommended: 5GB+)"
    fi

    # Check if ports are available
    local ports=(80 443 3000 3100 9090 9093)
    local ports_ok=true
    for port in "${ports[@]}"; do
        if ss -tulpn | grep -q ":${port} "; then
            print_warn "Port $port is already in use"
            ports_ok=false
        fi
    done
    if [[ "$ports_ok" == "true" ]]; then
        print_success "Required ports are available"
    fi

    # Check required commands
    local cmds=(wget curl systemctl)
    for cmd in "${cmds[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            print_success "Found command: $cmd"
        else
            print_error "Missing command: $cmd"
            all_ok=false
        fi
    done

    if [[ "$all_ok" == "false" ]]; then
        echo ""
        print_error "Prerequisites not met. Please fix the errors above."
        exit 1
    fi

    echo ""
    print_success "All prerequisites OK"
    sleep 2
}

step_network_config() {
    print_header "Step 2/7: Network Configuration"

    # Get VPS IP
    local detected_ip
    detected_ip=$(hostname -I | awk '{print $1}')
    echo "Detected IP: ${CYAN}$detected_ip${NC}"
    echo ""

    while true; do
        prompt VPS_IP "Observability server IP address" "$detected_ip"
        if validate_ip "$VPS_IP"; then
            break
        else
            print_error "Invalid IP address format"
        fi
    done

    echo ""

    # Get domain
    echo "Enter the domain name for Grafana access (must have DNS A record)"
    echo "Example: monitoring.example.com"
    echo ""

    while true; do
        prompt DOMAIN "Domain name"
        if validate_domain "$DOMAIN"; then
            # Test DNS resolution
            print_step "..." "Testing DNS resolution"
            if host "$DOMAIN" &>/dev/null; then
                local resolved_ip
                resolved_ip=$(host "$DOMAIN" | grep "has address" | awk '{print $4}' | head -1)
                if [[ "$resolved_ip" == "$VPS_IP" ]]; then
                    print_success "DNS correctly points to $VPS_IP"
                else
                    print_warn "DNS points to $resolved_ip (not $VPS_IP)"
                    echo "  You may need to update your DNS A record"
                    if ! confirm "Continue anyway?"; then
                        continue
                    fi
                fi
            else
                print_warn "Cannot resolve $DOMAIN"
                echo "  Make sure your DNS A record is configured"
                if ! confirm "Continue anyway?"; then
                    continue
                fi
            fi
            break
        else
            print_error "Invalid domain name format"
        fi
    done

    echo ""

    # Get email
    while true; do
        prompt EMAIL "Email for Let's Encrypt SSL notifications"
        if validate_email "$EMAIL"; then
            break
        else
            print_error "Invalid email address format"
        fi
    done

    echo ""
    print_success "Network configuration complete"
    sleep 1
}

step_smtp_config() {
    print_header "Step 3/7: SMTP Configuration (Email Alerts)"

    echo "Configure SMTP for sending alert emails"
    echo ""
    echo "Popular providers:"
    echo "  1. Brevo (smtp-relay.brevo.com:587) - Recommended, free tier available"
    echo "  2. SendGrid (smtp.sendgrid.net:587)"
    echo "  3. Amazon SES (email-smtp.REGION.amazonaws.com:587)"
    echo "  4. Custom SMTP server"
    echo ""

    if confirm "Use Brevo (recommended)?"; then
        SMTP_HOST="smtp-relay.brevo.com"
        SMTP_PORT="587"
        echo ""
        echo "Get your Brevo SMTP credentials:"
        echo "  1. Sign up at: https://www.brevo.com"
        echo "  2. Go to: Settings > SMTP & API > SMTP"
        echo "  3. Create an SMTP key"
        echo ""
    else
        prompt SMTP_HOST "SMTP server hostname" "$SMTP_HOST"
        prompt SMTP_PORT "SMTP port" "$SMTP_PORT"
    fi

    echo ""
    prompt SMTP_USER "SMTP username/login email"
    prompt SMTP_PASS "SMTP password/key" "" "true"
    echo ""
    prompt SMTP_FROM "From email address" "$EMAIL"

    # Test SMTP connectivity
    echo ""
    print_step "..." "Testing SMTP server connectivity"
    if test_connectivity "$SMTP_HOST" "$SMTP_PORT"; then
        print_success "SMTP server is reachable"
    else
        print_warn "Cannot connect to $SMTP_HOST:$SMTP_PORT"
        echo "  This may be normal if your firewall blocks outbound SMTP"
        echo "  Alerts will fail if SMTP is not accessible"
        confirm "Continue anyway?" || exit 1
    fi

    echo ""
    print_success "SMTP configuration complete"
    sleep 1
}

step_passwords() {
    print_header "Step 4/7: Security Configuration"

    echo "Set passwords for services"
    echo ""
    echo "You can:"
    echo "  1. Enter custom passwords (minimum 16 characters recommended)"
    echo "  2. Auto-generate strong passwords"
    echo ""

    if confirm "Auto-generate strong passwords?"; then
        GRAFANA_PASS=$(generate_password)
        PROM_PASS=$(generate_password)
        LOKI_PASS=$(generate_password)

        echo ""
        print_success "Generated strong passwords"
        echo ""
        echo "${BOLD}Save these passwords securely:${NC}"
        echo ""
        echo "Grafana admin password:  ${CYAN}$GRAFANA_PASS${NC}"
        echo "Prometheus password:     ${CYAN}$PROM_PASS${NC}"
        echo "Loki password:           ${CYAN}$LOKI_PASS${NC}"
        echo ""
        echo "Press Enter after you've saved these passwords"
        read -r
    else
        echo ""
        while true; do
            prompt GRAFANA_PASS "Grafana admin password" "" "true"
            echo ""
            if [[ ${#GRAFANA_PASS} -lt 16 ]]; then
                print_warn "Password is shorter than recommended 16 characters"
                confirm "Use this password anyway?" || continue
            fi
            break
        done

        prompt PROM_PASS "Prometheus password" "" "true"
        echo ""
        prompt LOKI_PASS "Loki password" "" "true"
        echo ""
    fi

    print_success "Passwords configured"
    sleep 1
}

step_monitored_hosts() {
    print_header "Step 5/7: Monitored Hosts (Optional)"

    echo "You can add monitored hosts now or later"
    echo ""

    if ! confirm "Add monitored hosts now?" n; then
        echo ""
        echo "You can add hosts later with:"
        echo "  ./scripts/add-monitored-host.sh --name HOSTNAME --ip IP"
        sleep 2
        return
    fi

    # Will be added to global.yaml
    MONITORED_HOSTS=()

    while true; do
        echo ""
        local host_name host_ip

        prompt host_name "Hostname (e.g., webserver1)"
        prompt host_ip "IP address"

        if ! validate_ip "$host_ip"; then
            print_error "Invalid IP address"
            continue
        fi

        MONITORED_HOSTS+=("$host_name:$host_ip")
        print_success "Added $host_name ($host_ip)"

        if ! confirm "Add another host?" n; then
            break
        fi
    done
}

step_review() {
    print_header "Step 6/7: Review Configuration"

    echo "${BOLD}Please review your configuration:${NC}"
    echo ""
    echo "Network:"
    echo "  Server IP:    $VPS_IP"
    echo "  Domain:       $DOMAIN"
    echo "  Email:        $EMAIL"
    echo ""
    echo "SMTP:"
    echo "  Server:       $SMTP_HOST:$SMTP_PORT"
    echo "  Username:     $SMTP_USER"
    echo "  From:         $SMTP_FROM"
    echo ""
    echo "Monitored Hosts: ${#MONITORED_HOSTS[@]}"
    for host in "${MONITORED_HOSTS[@]}"; do
        echo "  - ${host%%:*} (${host#*:})"
    done
    echo ""

    if ! confirm "Is this correct?"; then
        echo ""
        print_error "Configuration cancelled"
        echo "Run the wizard again to reconfigure"
        exit 1
    fi
}

step_install() {
    print_header "Step 7/7: Installation"

    # Create config file
    print_step "1/4" "Generating configuration file"

    cat > "$CONFIG_FILE" << EOF
# Observability Stack Global Configuration
# Generated by setup wizard on $(date)

network:
  observability_vps_ip: "$VPS_IP"
  grafana_domain: "$DOMAIN"
  letsencrypt_email: "$EMAIL"

monitored_hosts:
EOF

    if [[ ${#MONITORED_HOSTS[@]} -eq 0 ]]; then
        cat >> "$CONFIG_FILE" << 'EOF'
  # Add monitored hosts here, or use:
  # ./scripts/add-monitored-host.sh --name HOSTNAME --ip IP
  []
EOF
    else
        for host in "${MONITORED_HOSTS[@]}"; do
            local name="${host%%:*}"
            local ip="${host#*:}"
            cat >> "$CONFIG_FILE" << EOF
  - name: "$name"
    ip: "$ip"
    description: "$name"
    exporters:
      - node_exporter
      - nginx_exporter
      - mysqld_exporter
      - phpfpm_exporter
      - fail2ban_exporter
EOF
        done
    fi

    cat >> "$CONFIG_FILE" << EOF

smtp:
  enabled: true
  host: "$SMTP_HOST"
  port: $SMTP_PORT
  username: "$SMTP_USER"
  password: "$SMTP_PASS"
  from_address: "$SMTP_FROM"
  to_addresses:
    - "$EMAIL"
  starttls: true

retention:
  metrics_days: 15
  logs_days: 15

grafana:
  admin_password: "$GRAFANA_PASS"
  anonymous_access: false

security:
  prometheus_basic_auth_user: "prometheus"
  prometheus_basic_auth_password: "$PROM_PASS"
  loki_basic_auth_user: "loki"
  loki_basic_auth_password: "$LOKI_PASS"

ports:
  prometheus: 9090
  loki: 3100
  grafana: 3000
  alertmanager: 9093
  node_exporter: 9100
  nginx_exporter: 9113
  mysqld_exporter: 9104
  phpfpm_exporter: 9253
  fail2ban_exporter: 9191
EOF

    chmod 600 "$CONFIG_FILE"
    print_success "Configuration saved to $CONFIG_FILE"
    sleep 1

    # Validate config
    echo ""
    print_step "2/4" "Validating configuration"
    if "$SCRIPT_DIR/validate-config.sh" --config "$CONFIG_FILE" > /dev/null 2>&1; then
        print_success "Configuration validated"
    else
        print_warn "Configuration validation had warnings"
        echo "  Run: ./scripts/validate-config.sh for details"
    fi
    sleep 1

    # Ask to install
    echo ""
    print_step "3/4" "Ready to install"
    echo ""
    echo "The following will be installed:"
    echo "  • Prometheus (metrics)"
    echo "  • Loki (logs)"
    echo "  • Grafana (dashboards)"
    echo "  • Alertmanager (alerts)"
    echo "  • Nginx (reverse proxy + SSL)"
    echo ""
    echo "This will take 5-10 minutes."
    echo ""

    if ! confirm "Start installation now?"; then
        echo ""
        echo "Configuration saved. To install later, run:"
        echo "  sudo ./scripts/setup-observability.sh"
        exit 0
    fi

    # Run installation
    echo ""
    print_step "4/4" "Installing observability stack"
    echo ""

    if "$SCRIPT_DIR/setup-observability.sh"; then
        print_success "Installation completed successfully!"
    else
        print_error "Installation failed"
        echo "  Check the logs above for errors"
        echo "  You can retry with: sudo ./scripts/setup-observability.sh"
        exit 1
    fi
}

step_completion() {
    print_header "Setup Complete!"

    echo "${GREEN}${BOLD}Your observability stack is ready!${NC}"
    echo ""
    echo "${BOLD}Access URLs:${NC}"
    echo "  Grafana:        ${CYAN}https://$DOMAIN/${NC}"
    echo "  Prometheus:     ${CYAN}https://$DOMAIN/prometheus/${NC}"
    echo "  Loki:           ${CYAN}https://$DOMAIN/loki/${NC}"
    echo "  Alertmanager:   ${CYAN}https://$DOMAIN/alertmanager/${NC}"
    echo ""
    echo "${BOLD}Grafana Login:${NC}"
    echo "  Username: admin"
    echo "  Password: ${CYAN}$GRAFANA_PASS${NC}"
    echo ""
    echo "${BOLD}Next Steps:${NC}"
    echo "  1. Login to Grafana and change the admin password"
    echo "  2. Install monitoring agents on your servers:"
    echo "     sudo ./scripts/setup-monitored-host.sh $VPS_IP"
    echo "  3. Add more hosts:"
    echo "     ./scripts/add-monitored-host.sh --name HOST --ip IP"
    echo "  4. Run health check:"
    echo "     ./scripts/health-check.sh"
    echo ""
    echo "${BOLD}Quick Reference:${NC}"
    echo "  See QUICKREF.md for common commands and troubleshooting"
    echo ""
    echo "${BOLD}Configuration:${NC}"
    echo "  $CONFIG_FILE"
    echo ""
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    step_welcome
    step_prerequisites
    step_network_config
    step_smtp_config
    step_passwords
    step_monitored_hosts
    step_review
    step_install
    step_completion
}

main "$@"
