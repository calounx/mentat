#!/bin/bash
#===============================================================================
# Configuration Validator
# Validates global.yaml for common errors and missing values
#
# Usage:
#   ./validate-config.sh [--config FILE] [--strict]
#
# Exit codes:
#   0 - Configuration is valid
#   1 - Configuration has errors
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${BASE_DIR}/config/global.yaml"
STRICT_MODE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Validation results
ERRORS=()
WARNINGS=()
PASSED=0
FAILED=0

#===============================================================================
# ARGUMENT PARSING
#===============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --config=*)
            CONFIG_FILE="${1#*=}"
            shift
            ;;
        --strict)
            STRICT_MODE=true
            shift
            ;;
        --help|-h)
            cat << 'EOF'
Configuration Validator - Validate observability-stack configuration

Usage:
  ./validate-config.sh [OPTIONS]

Options:
  --config FILE    Path to global.yaml (default: ../config/global.yaml)
  --strict         Treat warnings as errors
  --help, -h       Show this help

Exit codes:
  0 - Configuration is valid
  1 - Configuration has errors

Examples:
  ./validate-config.sh
  ./validate-config.sh --config /path/to/config.yaml
  ./validate-config.sh --strict
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

#===============================================================================
# HELPER FUNCTIONS
#===============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED++))
    ERRORS+=("$1")
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    WARNINGS+=("$1")
    if [[ "$STRICT_MODE" == "true" ]]; then
        ((FAILED++))
    fi
}

yaml_get() {
    local key="$1"
    grep -E "^\s*${key}:" "$CONFIG_FILE" 2>/dev/null | head -1 | sed 's/.*:\s*//' | tr -d '"' | tr -d "'" || echo ""
}

yaml_get_nested() {
    local parent="$1"
    local key="$2"
    awk -v parent="$parent" -v key="$key" '
        $0 ~ "^"parent":" { in_section=1; next }
        in_section && /^[a-z]/ { in_section=0 }
        in_section && $0 ~ "^  "key":" {
            gsub(/.*: */, "");
            gsub(/["'\'']/, "");
            print;
            exit
        }
    ' "$CONFIG_FILE"
}

#===============================================================================
# VALIDATION TESTS
#===============================================================================

test_file_exists() {
    echo ""
    log_info "Checking if configuration file exists..."

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_fail "Configuration file not found: $CONFIG_FILE"
        echo ""
        echo "  To fix: Create config/global.yaml from the template"
        echo "  Example: cp config/global.yaml.example config/global.yaml"
        return 1
    fi

    log_pass "Configuration file exists: $CONFIG_FILE"
    return 0
}

test_yaml_syntax() {
    log_info "Checking YAML syntax..."

    # Basic YAML syntax check (without external dependencies)
    if ! grep -q '^network:' "$CONFIG_FILE"; then
        log_fail "Invalid YAML structure: missing 'network:' section"
        echo "  To fix: Ensure global.yaml has the correct structure"
        return 1
    fi

    log_pass "YAML structure appears valid"
    return 0
}

test_no_placeholders() {
    log_info "Checking for placeholder values..."

    local placeholders=()

    # Check for common placeholders
    if grep -qE '(YOUR_|CHANGE_ME|MONITORED_HOST_\d+_IP|YOUR_BREVO)' "$CONFIG_FILE"; then
        while IFS= read -r line; do
            placeholders+=("$line")
        done < <(grep -nE '(YOUR_|CHANGE_ME|MONITORED_HOST_\d+_IP|YOUR_BREVO)' "$CONFIG_FILE")

        log_fail "Found placeholder values in configuration:"
        for placeholder in "${placeholders[@]}"; do
            echo "    Line $placeholder"
        done
        echo ""
        echo "  To fix: Replace all placeholder values with actual configuration"
        echo "  Required fields:"
        echo "    - network.observability_vps_ip"
        echo "    - smtp.username (Brevo login email)"
        echo "    - smtp.password (Brevo SMTP key)"
        echo "    - grafana.admin_password"
        echo "    - security.prometheus_basic_auth_password"
        echo "    - security.loki_basic_auth_password"
        return 1
    fi

    log_pass "No placeholder values found"
    return 0
}

test_ip_addresses() {
    log_info "Validating IP addresses..."

    local ip_pattern='^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'
    local valid=true

    # Check observability VPS IP
    local obs_ip
    obs_ip=$(yaml_get_nested "network" "observability_vps_ip")

    if [[ -z "$obs_ip" ]]; then
        log_fail "network.observability_vps_ip is not set"
        echo "  To fix: Set observability_vps_ip to this server's public IP address"
        valid=false
    elif [[ ! "$obs_ip" =~ $ip_pattern ]]; then
        log_fail "Invalid IP address: $obs_ip"
        echo "  To fix: Set observability_vps_ip to a valid IPv4 address (e.g., 192.168.1.100)"
        valid=false
    else
        log_pass "Observability VPS IP is valid: $obs_ip"
    fi

    # Check monitored host IPs
    local host_ips
    host_ips=$(grep -E '^\s+ip:' "$CONFIG_FILE" | sed 's/.*:\s*//' | tr -d '"' | tr -d "'")

    while IFS= read -r ip; do
        [[ -z "$ip" ]] && continue
        if [[ ! "$ip" =~ $ip_pattern ]]; then
            log_warn "Invalid monitored host IP: $ip"
            echo "  To fix: Replace with valid IPv4 address or remove host entry"
            valid=false
        fi
    done <<< "$host_ips"

    if [[ "$valid" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

test_email_format() {
    log_info "Validating email addresses..."

    local email_pattern='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    local valid=true

    # Check Let's Encrypt email
    local le_email
    le_email=$(yaml_get_nested "network" "letsencrypt_email")

    if [[ -z "$le_email" ]]; then
        log_fail "network.letsencrypt_email is not set"
        echo "  To fix: Set letsencrypt_email to your email for SSL certificate notifications"
        valid=false
    elif [[ ! "$le_email" =~ $email_pattern ]]; then
        log_fail "Invalid email format: $le_email"
        echo "  To fix: Use a valid email address (e.g., admin@example.com)"
        valid=false
    else
        log_pass "Let's Encrypt email is valid: $le_email"
    fi

    # Check SMTP from address
    local smtp_from
    smtp_from=$(yaml_get_nested "smtp" "from_address")

    if [[ -z "$smtp_from" ]]; then
        log_warn "smtp.from_address is not set"
        echo "  To fix: Set from_address for alert emails"
        valid=false
    elif [[ ! "$smtp_from" =~ $email_pattern ]]; then
        log_warn "Invalid SMTP from address: $smtp_from"
        echo "  To fix: Use a valid email address"
        valid=false
    fi

    if [[ "$valid" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

test_smtp_server() {
    log_info "Testing SMTP server connectivity..."

    local smtp_host
    smtp_host=$(yaml_get_nested "smtp" "host")
    local smtp_port
    smtp_port=$(yaml_get_nested "smtp" "port")

    if [[ -z "$smtp_host" ]] || [[ -z "$smtp_port" ]]; then
        log_warn "SMTP host or port not configured"
        echo "  To fix: Configure smtp.host and smtp.port in global.yaml"
        return 1
    fi

    # Test connection (with timeout)
    if timeout 5 bash -c "echo >/dev/tcp/$smtp_host/$smtp_port" 2>/dev/null; then
        log_pass "SMTP server is reachable: $smtp_host:$smtp_port"
        return 0
    else
        log_warn "Cannot connect to SMTP server: $smtp_host:$smtp_port"
        echo "  This might be normal if:"
        echo "    - You're behind a firewall"
        echo "    - The SMTP server requires authentication first"
        echo "  Verify manually: telnet $smtp_host $smtp_port"
        return 1
    fi
}

test_dns_resolution() {
    log_info "Testing DNS resolution..."

    local domain
    domain=$(yaml_get_nested "network" "grafana_domain")

    if [[ -z "$domain" ]]; then
        log_fail "network.grafana_domain is not set"
        echo "  To fix: Set grafana_domain to your domain for Grafana access"
        return 1
    fi

    # Try to resolve domain
    if command -v host &>/dev/null; then
        if host "$domain" &>/dev/null; then
            local resolved_ip
            resolved_ip=$(host "$domain" | grep "has address" | awk '{print $4}' | head -1)
            log_pass "Domain resolves: $domain -> $resolved_ip"

            # Check if it matches observability IP
            local obs_ip
            obs_ip=$(yaml_get_nested "network" "observability_vps_ip")
            if [[ -n "$obs_ip" ]] && [[ "$resolved_ip" != "$obs_ip" ]]; then
                log_warn "Domain resolves to $resolved_ip but observability_vps_ip is $obs_ip"
                echo "  To fix: Update DNS A record for $domain to point to $obs_ip"
            fi
            return 0
        else
            log_warn "Cannot resolve domain: $domain"
            echo "  To fix: Create a DNS A record pointing $domain to your server IP"
            echo "  Or verify the domain name is correct"
            return 1
        fi
    else
        log_warn "Cannot test DNS (host command not available)"
        return 1
    fi
}

test_password_strength() {
    log_info "Validating password strength..."

    local valid=true

    # Check Grafana admin password
    local grafana_pass
    grafana_pass=$(yaml_get_nested "grafana" "admin_password")

    if [[ -z "$grafana_pass" ]] || [[ "$grafana_pass" == "CHANGE_ME_IMMEDIATELY" ]]; then
        log_fail "grafana.admin_password is not set or is default"
        echo "  To fix: Set a strong password (minimum 16 characters recommended)"
        valid=false
    elif [[ ${#grafana_pass} -lt 16 ]]; then
        log_warn "Grafana password is shorter than recommended 16 characters"
        echo "  To fix: Use a password with at least 16 characters for better security"
    else
        log_pass "Grafana password meets length requirements"
    fi

    # Check Prometheus password
    local prom_pass
    prom_pass=$(yaml_get_nested "security" "prometheus_basic_auth_password")

    if [[ -z "$prom_pass" ]] || [[ "$prom_pass" == "CHANGE_ME_PROMETHEUS" ]]; then
        log_fail "security.prometheus_basic_auth_password is not set or is default"
        echo "  To fix: Set a strong password (minimum 16 characters recommended)"
        valid=false
    elif [[ ${#prom_pass} -lt 16 ]]; then
        log_warn "Prometheus password is shorter than recommended 16 characters"
    fi

    # Check Loki password
    local loki_pass
    loki_pass=$(yaml_get_nested "security" "loki_basic_auth_password")

    if [[ -z "$loki_pass" ]] || [[ "$loki_pass" == "CHANGE_ME_LOKI" ]]; then
        log_fail "security.loki_basic_auth_password is not set or is default"
        echo "  To fix: Set a strong password (minimum 16 characters recommended)"
        valid=false
    elif [[ ${#loki_pass} -lt 16 ]]; then
        log_warn "Loki password is shorter than recommended 16 characters"
    fi

    if [[ "$valid" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

test_required_fields() {
    log_info "Checking required fields..."

    local required_fields=(
        "network:grafana_domain"
        "network:letsencrypt_email"
        "network:observability_vps_ip"
        "smtp:host"
        "smtp:port"
        "smtp:username"
        "smtp:password"
        "smtp:from_address"
        "grafana:admin_password"
        "security:prometheus_basic_auth_user"
        "security:prometheus_basic_auth_password"
        "security:loki_basic_auth_user"
        "security:loki_basic_auth_password"
    )

    local missing=()

    for field in "${required_fields[@]}"; do
        local parent="${field%%:*}"
        local key="${field#*:}"
        local value
        value=$(yaml_get_nested "$parent" "$key")

        if [[ -z "$value" ]]; then
            missing+=("$field")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_fail "Missing required fields:"
        for field in "${missing[@]}"; do
            echo "    - $field"
        done
        echo ""
        echo "  To fix: Add all required fields to global.yaml"
        return 1
    fi

    log_pass "All required fields are present"
    return 0
}

test_file_permissions() {
    log_info "Checking file permissions..."

    # Config should not be world-readable (contains passwords)
    local perms
    perms=$(stat -c '%a' "$CONFIG_FILE" 2>/dev/null || stat -f '%p' "$CONFIG_FILE" 2>/dev/null | tail -c 4)

    if [[ "$perms" == *"4" ]] || [[ "$perms" == *"6" ]] || [[ "$perms" == *"7" ]]; then
        log_warn "Config file is world-readable: $CONFIG_FILE (permissions: $perms)"
        echo "  To fix: chmod 600 $CONFIG_FILE"
        echo "  This file contains passwords and should not be readable by others"
        return 1
    fi

    log_pass "Config file permissions are acceptable"
    return 0
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    echo ""
    echo "=========================================="
    echo "Configuration Validator"
    echo "=========================================="
    echo ""
    echo "Config file: $CONFIG_FILE"
    if [[ "$STRICT_MODE" == "true" ]]; then
        echo -e "${YELLOW}Mode: STRICT (warnings = errors)${NC}"
    fi

    # Run all tests
    test_file_exists || exit 1
    test_yaml_syntax || exit 1
    test_required_fields
    test_no_placeholders
    test_ip_addresses
    test_email_format
    test_dns_resolution
    test_smtp_server
    test_password_strength
    test_file_permissions

    # Print summary
    echo ""
    echo "=========================================="
    echo "Validation Summary"
    echo "=========================================="
    echo ""
    echo -e "  ${GREEN}Passed:${NC}  $PASSED"
    echo -e "  ${RED}Failed:${NC}  $FAILED"
    echo -e "  ${YELLOW}Warnings:${NC} ${#WARNINGS[@]}"
    echo ""

    if [[ $FAILED -gt 0 ]]; then
        echo -e "${RED}Configuration validation FAILED${NC}"
        echo ""
        echo "Fix the errors above and run this script again."
        echo "For help, see: observability-stack/README.md"
        exit 1
    elif [[ ${#WARNINGS[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Configuration validation passed with WARNINGS${NC}"
        echo ""
        echo "Consider addressing the warnings above for better security and reliability."
        if [[ "$STRICT_MODE" == "true" ]]; then
            exit 1
        fi
        exit 0
    else
        echo -e "${GREEN}Configuration validation PASSED${NC}"
        echo ""
        echo "Your configuration looks good!"
        echo "Next steps:"
        echo "  1. Run setup-observability.sh to install the observability stack"
        echo "  2. Run setup-monitored-host.sh on each monitored host"
        exit 0
    fi
}

main "$@"
