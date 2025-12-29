#!/bin/bash
#===============================================================================
# Observability Stack Interactive Installer
#
# Handles three deployment roles:
# - Observability VPS: Full monitoring stack (Prometheus, Loki, Grafana, etc.)
# - VPSManager: Laravel application + LEMP stack + monitoring
# - Monitored Host: Exporters only (for existing servers)
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(dirname "$SCRIPT_DIR")"

# Source shared libraries
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/config.sh"

#===============================================================================
# Load Previous Installation Values
#===============================================================================

load_previous_config() {
    local install_file="${STACK_DIR}/.installation"

    if [[ -f "$install_file" ]]; then
        log_info "Found previous installation, loading values..."
        # Source the file to load variables
        source "$install_file"
        return 0
    fi

    return 1
}

#===============================================================================
# Role Selection
#===============================================================================

select_role() {
    echo
    echo "${CYAN}===============================================================${NC}"
    echo "${CYAN}  Select Installation Role${NC}"
    echo "${CYAN}===============================================================${NC}"
    echo
    echo "  1) ${GREEN}Observability VPS${NC}"
    echo "     - Prometheus, Loki, Tempo, Grafana, Alertmanager"
    echo "     - Central monitoring for all your servers"
    echo "     - Recommended: 1-2 vCPU, 2GB RAM, 20GB disk"
    echo
    echo "  2) ${BLUE}VPSManager${NC} (Laravel Application)"
    echo "     - Full LEMP stack: Nginx, PHP-FPM, MariaDB, Redis"
    echo "     - Laravel application deployment"
    echo "     - All monitoring exporters + Promtail"
    echo "     - Recommended: 2+ vCPU, 4GB RAM, 40GB disk"
    echo
    echo "  3) ${YELLOW}Monitored Host${NC} (Exporters only)"
    echo "     - For existing servers with apps already installed"
    echo "     - Node exporter, Promtail, service exporters"
    echo
    echo "  4) ${RED}Exit${NC}"
    echo

    local choice
    while true; do
        read -p "Select role [1-4]: " choice
        case $choice in
            1)
                ROLE="observability"
                break
                ;;
            2)
                ROLE="vpsmanager"
                break
                ;;
            3)
                ROLE="monitored"
                break
                ;;
            4)
                log_info "Installation cancelled"
                exit 0
                ;;
            *)
                log_error "Invalid choice. Please enter 1, 2, 3, or 4"
                ;;
        esac
    done
}

#===============================================================================
# Configuration Collection
#===============================================================================

collect_observability_config() {
    echo
    echo "${CYAN}===============================================================${NC}"
    echo "${CYAN}  Observability VPS Configuration${NC}"
    echo "${CYAN}===============================================================${NC}"
    echo

    # Get public IP (use previous value as fallback)
    local detected_ip
    detected_ip=$(curl -s -4 ifconfig.me 2>/dev/null || curl -s -4 icanhazip.com 2>/dev/null || echo "")
    local default_ip="${OBSERVABILITY_IP:-$detected_ip}"

    echo "Detected public IP: ${GREEN}${detected_ip:-not detected}${NC}"
    if [[ -n "${OBSERVABILITY_IP:-}" ]] && [[ "$OBSERVABILITY_IP" != "$detected_ip" ]]; then
        echo "Previous value: ${YELLOW}${OBSERVABILITY_IP}${NC}"
    fi
    read -p "Observability VPS IP [$default_ip]: " input_ip
    OBSERVABILITY_IP="${input_ip:-$default_ip}"

    if [[ -z "$OBSERVABILITY_IP" ]]; then
        log_error "IP address is required"
        exit 1
    fi

    # Domain for Grafana
    echo
    local domain_prompt="Domain for Grafana"
    if [[ -n "${GRAFANA_DOMAIN:-}" ]]; then
        domain_prompt="$domain_prompt [${GRAFANA_DOMAIN}]"
    else
        domain_prompt="$domain_prompt (e.g., grafana.example.com)"
    fi
    read -p "$domain_prompt: " input_domain
    GRAFANA_DOMAIN="${input_domain:-${GRAFANA_DOMAIN:-}}"

    if [[ -z "$GRAFANA_DOMAIN" ]]; then
        log_warn "No domain provided - will use IP access only (no SSL)"
        GRAFANA_DOMAIN=""
        USE_SSL=false
    else
        USE_SSL=true
        local default_email="${LETSENCRYPT_EMAIL:-}"
        read -p "Email for Let's Encrypt SSL${default_email:+ [$default_email]}: " input_email
        LETSENCRYPT_EMAIL="${input_email:-$default_email}"
    fi

    # Grafana admin password
    echo
    local default_pass
    default_pass=$(generate_password)
    echo "Generated admin password: ${YELLOW}$default_pass${NC}"
    read -p "Grafana admin password [$default_pass]: " GRAFANA_PASSWORD
    GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-$default_pass}"

    # Retention settings
    echo
    echo "Data retention (based on disk space):"
    local default_metrics_retention="${METRICS_RETENTION_DAYS:-15}"
    local default_logs_retention="${LOGS_RETENTION_DAYS:-7}"

    read -p "Metrics retention days [$default_metrics_retention]: " input_metrics
    METRICS_RETENTION_DAYS="${input_metrics:-$default_metrics_retention}"

    read -p "Logs retention days [$default_logs_retention]: " input_logs
    LOGS_RETENTION_DAYS="${input_logs:-$default_logs_retention}"

    # Alert configuration (optional)
    echo
    read -p "Configure email alerts? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "SMTP host (e.g., smtp.gmail.com): " SMTP_HOST
        read -p "SMTP port [587]: " SMTP_PORT
        SMTP_PORT="${SMTP_PORT:-587}"
        read -p "SMTP username: " SMTP_USER
        read -s -p "SMTP password: " SMTP_PASS
        echo
        read -p "From address: " ALERT_FROM
        read -p "To address: " ALERT_TO
        CONFIGURE_SMTP=true
    else
        CONFIGURE_SMTP=false
    fi

    # IPv6 configuration
    echo
    read -p "Disable IPv6 for observability services? [Y/n]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        DISABLE_IPV6=true
        log_info "IPv6 will be disabled for all services"
    else
        DISABLE_IPV6=false
        log_info "IPv6 will remain enabled"
    fi

    # Summary
    show_observability_summary

    read -p "Proceed with installation? [Y/n]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_info "Installation cancelled"
        exit 0
    fi

    # Export configuration
    export OBSERVABILITY_IP GRAFANA_DOMAIN USE_SSL LETSENCRYPT_EMAIL
    export GRAFANA_PASSWORD METRICS_RETENTION_DAYS LOGS_RETENTION_DAYS
    export CONFIGURE_SMTP SMTP_HOST SMTP_PORT SMTP_USER SMTP_PASS ALERT_FROM ALERT_TO
    export DISABLE_IPV6
}

collect_vpsmanager_config() {
    echo
    echo "${CYAN}===============================================================${NC}"
    echo "${CYAN}  VPSManager Configuration${NC}"
    echo "${CYAN}===============================================================${NC}"
    echo

    # Observability VPS IP
    read -p "Observability VPS IP address: " OBSERVABILITY_IP
    if [[ -z "$OBSERVABILITY_IP" ]]; then
        log_error "Observability VPS IP is required"
        exit 1
    fi

    # This host's IP
    local detected_ip
    detected_ip=$(curl -s -4 ifconfig.me 2>/dev/null || curl -s -4 icanhazip.com 2>/dev/null || echo "")

    echo "Detected this host's IP: ${GREEN}${detected_ip:-not detected}${NC}"
    read -p "This VPS IP [$detected_ip]: " HOST_IP
    HOST_IP="${HOST_IP:-$detected_ip}"

    # Host name/label
    local default_hostname
    default_hostname=$(hostname -f 2>/dev/null || hostname)
    read -p "Host name/label [$default_hostname]: " HOST_NAME
    HOST_NAME="${HOST_NAME:-$default_hostname}"

    # VPSManager repository
    echo
    echo "${CYAN}VPSManager Application:${NC}"
    read -p "GitHub repository URL (e.g., https://github.com/user/vpsmanager.git): " VPSMANAGER_REPO
    if [[ -z "$VPSMANAGER_REPO" ]]; then
        log_error "Repository URL is required"
        exit 1
    fi

    read -p "Branch [main]: " VPSMANAGER_BRANCH
    VPSMANAGER_BRANCH="${VPSMANAGER_BRANCH:-main}"

    # Domain
    echo
    read -p "Domain for VPSManager (e.g., vpsmanager.example.com): " VPSMANAGER_DOMAIN
    if [[ -z "$VPSMANAGER_DOMAIN" ]]; then
        log_error "Domain is required for VPSManager"
        exit 1
    fi

    read -p "Email for Let's Encrypt [$VPSMANAGER_DOMAIN admin]: " LETSENCRYPT_EMAIL
    LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-admin@${VPSMANAGER_DOMAIN}}"

    # PHP version
    echo
    read -p "PHP version [8.2]: " PHP_VERSION
    PHP_VERSION="${PHP_VERSION:-8.2}"

    # Summary
    show_vpsmanager_summary

    read -p "Proceed with installation? [Y/n]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_info "Installation cancelled"
        exit 0
    fi

    # Export configuration
    export OBSERVABILITY_IP HOST_IP HOST_NAME
    export VPSMANAGER_REPO VPSMANAGER_BRANCH VPSMANAGER_DOMAIN
    export LETSENCRYPT_EMAIL PHP_VERSION
}

collect_monitored_config() {
    echo
    echo "${CYAN}===============================================================${NC}"
    echo "${CYAN}  Monitored Host Configuration${NC}"
    echo "${CYAN}===============================================================${NC}"
    echo

    # Observability VPS IP
    read -p "Observability VPS IP address: " OBSERVABILITY_IP
    if [[ -z "$OBSERVABILITY_IP" ]]; then
        log_error "Observability VPS IP is required"
        exit 1
    fi

    # This host's IP
    local detected_ip
    detected_ip=$(curl -s -4 ifconfig.me 2>/dev/null || curl -s -4 icanhazip.com 2>/dev/null || echo "")

    echo "Detected this host's IP: ${GREEN}${detected_ip:-not detected}${NC}"
    read -p "This host's IP [$detected_ip]: " HOST_IP
    HOST_IP="${HOST_IP:-$detected_ip}"

    # Host name/label
    local default_hostname
    default_hostname=$(hostname -f 2>/dev/null || hostname)
    read -p "Host name/label [$default_hostname]: " HOST_NAME
    HOST_NAME="${HOST_NAME:-$default_hostname}"

    # Auto-detect services
    echo
    log_step "Auto-detecting services..."
    detect_services

    # Summary
    show_monitored_summary

    read -p "Proceed with installation? [Y/n]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_info "Installation cancelled"
        exit 0
    fi

    # Export configuration
    export OBSERVABILITY_IP HOST_IP HOST_NAME
    export DETECTED_SERVICES
}

detect_services() {
    DETECTED_SERVICES=()

    # Always include node_exporter
    DETECTED_SERVICES+=("node_exporter")

    # Nginx
    if systemctl is-active --quiet nginx 2>/dev/null || [[ -f /etc/nginx/nginx.conf ]]; then
        DETECTED_SERVICES+=("nginx_exporter")
        log_info "  Detected: Nginx"
    fi

    # MySQL/MariaDB
    if systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mariadb 2>/dev/null; then
        DETECTED_SERVICES+=("mysqld_exporter")
        log_info "  Detected: MySQL/MariaDB"
    fi

    # PHP-FPM
    if ls /run/php/php*-fpm.sock 2>/dev/null | head -1 &>/dev/null; then
        DETECTED_SERVICES+=("phpfpm_exporter")
        log_info "  Detected: PHP-FPM"
    fi

    # Fail2ban
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        DETECTED_SERVICES+=("fail2ban_exporter")
        log_info "  Detected: Fail2ban"
    fi

    # Always include promtail for logs
    DETECTED_SERVICES+=("promtail")

    if [[ ${#DETECTED_SERVICES[@]} -eq 2 ]]; then
        log_info "  No additional services detected (will install node_exporter + promtail)"
    fi
}

#===============================================================================
# Summary Display
#===============================================================================

show_observability_summary() {
    echo
    echo "${CYAN}===============================================================${NC}"
    echo "${CYAN}  Configuration Summary${NC}"
    echo "${CYAN}===============================================================${NC}"
    echo
    echo "  Role:              Observability VPS"
    echo "  IP Address:        $OBSERVABILITY_IP"
    echo "  Domain:            ${GRAFANA_DOMAIN:-None (IP access)}"
    echo "  SSL:               ${USE_SSL}"
    echo "  Metrics Retention: ${METRICS_RETENTION_DAYS} days"
    echo "  Logs Retention:    ${LOGS_RETENTION_DAYS} days"
    echo "  Email Alerts:      ${CONFIGURE_SMTP}"
    echo
    echo "  Components:"
    echo "    - Prometheus (metrics)"
    echo "    - Loki (logs)"
    echo "    - Tempo (traces)"
    echo "    - Grafana (visualization)"
    echo "    - Alertmanager (alerts)"
    echo
}

show_vpsmanager_summary() {
    echo
    echo "${CYAN}===============================================================${NC}"
    echo "${CYAN}  Configuration Summary${NC}"
    echo "${CYAN}===============================================================${NC}"
    echo
    echo "  Role:              VPSManager (Laravel Application)"
    echo "  Host Name:         $HOST_NAME"
    echo "  Host IP:           $HOST_IP"
    echo "  Observability VPS: $OBSERVABILITY_IP"
    echo
    echo "  Application:"
    echo "    - Repository: $VPSMANAGER_REPO"
    echo "    - Branch:     $VPSMANAGER_BRANCH"
    echo "    - Domain:     $VPSMANAGER_DOMAIN"
    echo
    echo "  Stack:"
    echo "    - Nginx"
    echo "    - PHP ${PHP_VERSION}-FPM"
    echo "    - MariaDB"
    echo "    - Redis"
    echo "    - Supervisor (queues)"
    echo "    - Let's Encrypt SSL"
    echo
    echo "  Monitoring:"
    echo "    - node_exporter"
    echo "    - nginx_exporter"
    echo "    - mysqld_exporter"
    echo "    - phpfpm_exporter"
    echo "    - promtail (logs)"
    echo
}

show_monitored_summary() {
    echo
    echo "${CYAN}===============================================================${NC}"
    echo "${CYAN}  Configuration Summary${NC}"
    echo "${CYAN}===============================================================${NC}"
    echo
    echo "  Role:              Monitored Host (Exporters Only)"
    echo "  Host Name:         $HOST_NAME"
    echo "  Host IP:           $HOST_IP"
    echo "  Observability VPS: $OBSERVABILITY_IP"
    echo "  Detected Services: ${DETECTED_SERVICES[*]}"
    echo
}

#===============================================================================
# Installation Execution
#===============================================================================

run_role_installer() {
    case "$ROLE" in
        observability)
            log_step "Installing Observability Stack..."
            source "$SCRIPT_DIR/roles/observability.sh"
            install_observability_stack
            ;;
        vpsmanager)
            log_step "Installing VPSManager..."
            source "$SCRIPT_DIR/roles/vpsmanager.sh"
            install_vpsmanager
            ;;
        monitored)
            log_step "Installing Monitored Host..."
            source "$SCRIPT_DIR/roles/monitored.sh"
            install_monitored_host
            ;;
    esac
}

show_completion() {
    echo
    echo "${GREEN}===============================================================${NC}"
    echo "${GREEN}  Installation Complete!${NC}"
    echo "${GREEN}===============================================================${NC}"
    echo

    case "$ROLE" in
        observability)
            echo "  Grafana URL:"
            # Check if SSL is actually configured with valid certificates
            if [[ "${USE_SSL:-false}" == "true" ]] && [[ -n "${GRAFANA_DOMAIN:-}" ]]; then
                if [[ -f "/etc/letsencrypt/live/${GRAFANA_DOMAIN}/fullchain.pem" ]]; then
                    echo "    ${CYAN}https://${GRAFANA_DOMAIN}${NC}"
                else
                    echo "    ${CYAN}http://${GRAFANA_DOMAIN}${NC} ${YELLOW}(SSL setup failed)${NC}"
                fi
            elif [[ -n "${GRAFANA_DOMAIN:-}" ]]; then
                echo "    ${CYAN}http://${GRAFANA_DOMAIN}${NC}"
            else
                echo "    ${CYAN}http://${OBSERVABILITY_IP}${NC} (nginx proxy on port 80)"
                echo "    ${CYAN}http://${OBSERVABILITY_IP}:3000${NC} (direct Grafana access)"
            fi
            echo
            echo "  Grafana Credentials:"
            echo "    Username: admin"
            echo "    Password: $GRAFANA_PASSWORD"
            echo
            if [[ -n "${PROMETHEUS_AUTH_PASSWORD:-}" ]]; then
                echo "  Prometheus/Alertmanager HTTP Basic Auth:"
                echo "    Username: admin"
                echo "    Password: $PROMETHEUS_AUTH_PASSWORD"
                echo
            fi
            echo "  Services:"
            echo "    - Prometheus:    http://localhost:9090"
            echo "    - Loki:          http://localhost:3100"
            echo "    - Tempo:         http://localhost:3200"
            echo "    - Alertmanager:  http://localhost:9093"
            echo
            echo "  Next Steps:"
            echo "    1. Access Grafana and change the admin password"
            echo "    2. Run the installer on VPSManager VPS (option 2)"
            echo "    3. Import dashboards from grafana/dashboards/library/"
            ;;

        vpsmanager)
            echo "  VPSManager URL:"
            echo "    ${CYAN}https://${VPSMANAGER_DOMAIN}${NC}"
            echo
            echo "  Database Credentials:"
            echo "    Saved to: /root/.credentials/mysql"
            echo
            echo "  Services Running:"
            echo "    - Nginx + PHP-FPM"
            echo "    - MariaDB"
            echo "    - Redis"
            echo "    - Supervisor (queue workers)"
            echo
            echo "  Monitoring:"
            echo "    - Metrics → Prometheus at $OBSERVABILITY_IP"
            echo "    - Logs → Loki at $OBSERVABILITY_IP"
            echo
            echo "  Next Steps:"
            echo "    1. Copy target file to Observability VPS:"
            echo "       scp /tmp/${HOST_NAME}-targets.yaml root@${OBSERVABILITY_IP}:/etc/prometheus/targets/"
            echo "    2. Configure .env file if needed: ${VPSMANAGER_PATH:-/var/www/vpsmanager}/.env"
            echo "    3. Check application in browser"
            ;;

        monitored)
            echo "  Installed exporters:"
            for svc in "${DETECTED_SERVICES[@]}"; do
                echo "    - $svc"
            done
            echo
            echo "  This host is now sending:"
            echo "    - Metrics → Prometheus at $OBSERVABILITY_IP"
            echo "    - Logs → Loki at $OBSERVABILITY_IP"
            echo
            echo "  Next Steps:"
            echo "    1. Copy target file to Observability VPS:"
            echo "       scp /tmp/${HOST_NAME}-targets.yaml root@${OBSERVABILITY_IP}:/etc/prometheus/targets/"
            echo "    2. Verify in Grafana Prometheus targets"
            ;;
    esac

    echo
    echo "${CYAN}Documentation: $STACK_DIR/deploy/README.md${NC}"
    echo
}

#===============================================================================
# Pre-flight Validation
#===============================================================================

run_preflight_checks() {
    local config_file="$STACK_DIR/config/global.yaml"

    echo
    log_step "Running pre-flight checks..."

    # Check root privileges
    if [[ $EUID -ne 0 ]]; then
        log_error "This installer must be run as root (use sudo)"
        exit 1
    fi

    # Check internet connectivity
    if ! curl -s --connect-timeout 5 https://github.com >/dev/null 2>&1; then
        log_error "No internet connectivity (cannot reach github.com)"
        exit 1
    fi

    # Check disk space (minimum 5GB free)
    local free_space
    free_space=$(df / --output=avail -B1G 2>/dev/null | tail -1 | tr -d ' ' || echo "0")
    if [[ "$free_space" -lt 5 ]]; then
        log_error "Insufficient disk space: ${free_space}GB free, need at least 5GB"
        exit 1
    fi

    # Validate config has no placeholders (optional - only if config exists)
    if [[ -f "$config_file" ]]; then
        if ! validate_config_no_placeholders "$config_file"; then
            echo
            log_warn "Configuration has placeholder values."
            log_warn "The installer will collect these values interactively."
            echo
        fi
    fi

    log_success "Pre-flight checks passed"
}

#===============================================================================
# Main
#===============================================================================

main() {
    print_banner

    # Run pre-flight checks before anything else
    run_preflight_checks

    # Load previous installation values if available
    load_previous_config || true

    select_role

    case "$ROLE" in
        observability)
            collect_observability_config
            ;;
        vpsmanager)
            collect_vpsmanager_config
            ;;
        monitored)
            collect_monitored_config
            ;;
    esac

    run_role_installer
    show_completion
}

main "$@"
