#!/bin/bash
#===============================================================================
# Pre-flight Checks for Observability Stack
# Validates system requirements before installation
#
# Usage:
#   ./preflight-check.sh --observability-vps
#   ./preflight-check.sh --monitored-host
#   ./preflight-check.sh --observability-vps --fix
#===============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Check mode
MODE=""
FIX_MODE=false

# Requirements
MIN_DISK_GB_VPS=20
MIN_DISK_GB_HOST=5
MIN_MEMORY_MB_VPS=2048
MIN_MEMORY_MB_HOST=512

# Counters
CHECKS_TOTAL=0
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

#===============================================================================
# UTILITY FUNCTIONS
#===============================================================================

log_check() {
    echo -ne "${BLUE}[CHECK]${NC} $1 ... "
}

log_pass() {
    echo -e "${GREEN}PASS${NC}"
    ((CHECKS_PASSED++))
}

log_fail() {
    echo -e "${RED}FAIL${NC}"
    if [[ -n "${1:-}" ]]; then
        echo -e "        ${RED}Error:${NC} $1"
    fi
    if [[ -n "${2:-}" ]]; then
        echo -e "        ${YELLOW}Fix:${NC} $2"
    fi
    ((CHECKS_FAILED++))
}

log_warn() {
    echo -e "${YELLOW}WARN${NC}"
    if [[ -n "${1:-}" ]]; then
        echo -e "        ${YELLOW}Warning:${NC} $1"
    fi
    ((CHECKS_WARNING++))
}

show_help() {
    cat << 'EOF'
Pre-flight Checks - Validate system requirements

USAGE:
    ./preflight-check.sh --observability-vps [OPTIONS]
    ./preflight-check.sh --monitored-host [OPTIONS]

OPTIONS:
    --observability-vps     Check requirements for observability VPS
    --monitored-host        Check requirements for monitored host
    --fix                   Attempt to fix issues automatically
    --help, -h              Show this help

CHECKS:
    OS Compatibility        Debian 13 or similar
    Disk Space              20GB for VPS, 5GB for hosts
    Memory                  2GB for VPS, 512MB for hosts
    Port Availability       Required ports are free
    DNS Resolution          Domain resolves correctly (VPS only)
    Internet Access         Can reach GitHub and package repos
    System Architecture     x86_64 (amd64)

EXAMPLES:
    # Check VPS requirements
    ./preflight-check.sh --observability-vps

    # Check host requirements and fix issues
    ./preflight-check.sh --monitored-host --fix
EOF
}

#===============================================================================
# CHECK FUNCTIONS
#===============================================================================

check_root() {
    ((CHECKS_TOTAL++))
    log_check "Running as root"

    if [[ $EUID -eq 0 ]]; then
        log_pass
        return 0
    else
        log_fail "Must run as root" "Run with: sudo $0 $*"
        return 1
    fi
}

check_os() {
    ((CHECKS_TOTAL++))
    log_check "Operating system compatibility"

    if [[ ! -f /etc/os-release ]]; then
        log_fail "Cannot detect OS (missing /etc/os-release)" "Supported: Debian 13, Ubuntu 22.04+"
        return 1
    fi

    source /etc/os-release

    if [[ "$ID" == "debian" ]]; then
        local version_major="${VERSION_ID%%.*}"
        if [[ "$version_major" -ge 12 ]]; then
            log_pass
            return 0
        fi
    elif [[ "$ID" == "ubuntu" ]]; then
        local version="${VERSION_ID%.*}"
        if [[ "${version//./}" -ge 2204 ]]; then
            log_pass
            return 0
        fi
    fi

    log_warn "OS not tested: $PRETTY_NAME" "Recommended: Debian 13 or Ubuntu 22.04+"
    return 0
}

check_architecture() {
    ((CHECKS_TOTAL++))
    log_check "System architecture"

    local arch
    arch=$(uname -m)

    if [[ "$arch" == "x86_64" ]] || [[ "$arch" == "amd64" ]]; then
        log_pass
        return 0
    else
        log_fail "Unsupported architecture: $arch" "Only x86_64/amd64 is supported"
        return 1
    fi
}

check_disk_space() {
    ((CHECKS_TOTAL++))

    local required_gb
    if [[ "$MODE" == "observability-vps" ]]; then
        required_gb=$MIN_DISK_GB_VPS
    else
        required_gb=$MIN_DISK_GB_HOST
    fi

    log_check "Disk space (${required_gb}GB required)"

    local available_gb
    available_gb=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')

    if [[ "$available_gb" -ge "$required_gb" ]]; then
        log_pass
        return 0
    else
        log_fail "Only ${available_gb}GB available, need ${required_gb}GB" "Free up disk space with: apt-get clean && apt-get autoremove"
        return 1
    fi
}

check_memory() {
    ((CHECKS_TOTAL++))

    local required_mb
    if [[ "$MODE" == "observability-vps" ]]; then
        required_mb=$MIN_MEMORY_MB_VPS
    else
        required_mb=$MIN_MEMORY_MB_HOST
    fi

    log_check "Memory (${required_mb}MB required)"

    local total_mb
    total_mb=$(free -m | grep "Mem:" | awk '{print $2}')

    if [[ "$total_mb" -ge "$required_mb" ]]; then
        log_pass
        return 0
    else
        log_fail "Only ${total_mb}MB available, need ${required_mb}MB" "Upgrade to a larger instance"
        return 1
    fi
}

check_port() {
    local port=$1
    local service=$2

    ((CHECKS_TOTAL++))
    log_check "Port $port available ($service)"

    if ! command -v ss &>/dev/null && ! command -v netstat &>/dev/null; then
        log_warn "Cannot check (ss/netstat not installed)"
        return 0
    fi

    local in_use=false
    if command -v ss &>/dev/null; then
        if ss -tln | grep -q ":${port} "; then
            in_use=true
        fi
    elif command -v netstat &>/dev/null; then
        if netstat -tln | grep -q ":${port} "; then
            in_use=true
        fi
    fi

    if [[ "$in_use" == "false" ]]; then
        log_pass
        return 0
    else
        local process=""
        if command -v lsof &>/dev/null; then
            process=$(lsof -i ":${port}" -t 2>/dev/null | head -1 || echo "")
            if [[ -n "$process" ]]; then
                local pname
                pname=$(ps -p "$process" -o comm= 2>/dev/null || echo "unknown")
                process=" (PID $process: $pname)"
            fi
        fi

        log_fail "Port already in use${process}" "Stop the service using this port or choose a different port"
        return 1
    fi
}

check_ports_vps() {
    check_port 80 "HTTP"
    check_port 443 "HTTPS"
    check_port 3000 "Grafana"
    check_port 9090 "Prometheus"
    check_port 3100 "Loki"
    check_port 9093 "Alertmanager"
}

check_ports_host() {
    check_port 9100 "node_exporter"

    # Optional exporters - just warn if in use
    for port_service in "9113:nginx_exporter" "9104:mysqld_exporter" "9253:phpfpm_exporter" "9191:fail2ban_exporter"; do
        local port="${port_service%%:*}"
        local service="${port_service#*:}"

        ((CHECKS_TOTAL++))
        log_check "Port $port available ($service)"

        local in_use=false
        if command -v ss &>/dev/null; then
            if ss -tln | grep -q ":${port} "; then
                in_use=true
            fi
        fi

        if [[ "$in_use" == "false" ]]; then
            log_pass
        else
            log_warn "Port in use (optional exporter may fail to install)"
        fi
    done
}

check_dns() {
    if [[ "$MODE" != "observability-vps" ]]; then
        return 0
    fi

    ((CHECKS_TOTAL++))

    # Try to get domain from config
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local config_file="${script_dir}/../config/global.yaml"

    if [[ ! -f "$config_file" ]]; then
        log_check "DNS resolution"
        log_warn "Cannot check (config/global.yaml not found)"
        return 0
    fi

    local domain
    domain=$(grep "grafana_domain:" "$config_file" | head -1 | awk '{print $2}' | tr -d '"' || echo "")

    if [[ -z "$domain" ]] || [[ "$domain" == "mentat.arewel.com" ]] || [[ "$domain" == *"YOUR"* ]]; then
        log_check "DNS resolution"
        log_warn "Domain not configured yet in global.yaml"
        return 0
    fi

    log_check "DNS resolution for $domain"

    local resolved_ip
    resolved_ip=$(dig +short "$domain" 2>/dev/null | grep -E '^[0-9.]+$' | head -1 || echo "")

    if [[ -z "$resolved_ip" ]]; then
        log_fail "Domain does not resolve" "Create DNS A record for $domain pointing to this server's IP"
        return 1
    fi

    # Get server's public IP
    local server_ip
    server_ip=$(curl -s -4 ifconfig.me 2>/dev/null || curl -s -4 icanhazip.com 2>/dev/null || echo "")

    if [[ -n "$server_ip" ]] && [[ "$resolved_ip" != "$server_ip" ]]; then
        log_warn "Domain resolves to $resolved_ip but server IP is $server_ip"
    else
        log_pass
    fi

    return 0
}

check_internet() {
    ((CHECKS_TOTAL++))
    log_check "Internet connectivity"

    # Try multiple hosts
    local hosts=("github.com" "8.8.8.8" "1.1.1.1")
    local reachable=false

    for host in "${hosts[@]}"; do
        if ping -c 1 -W 2 "$host" &>/dev/null; then
            reachable=true
            break
        fi
    done

    if [[ "$reachable" == "true" ]]; then
        log_pass
        return 0
    else
        log_fail "Cannot reach internet" "Check network connection and firewall rules"
        return 1
    fi
}

check_github_access() {
    ((CHECKS_TOTAL++))
    log_check "GitHub releases access"

    if curl -s --max-time 5 -I https://github.com | grep -q "HTTP/2 200"; then
        log_pass
        return 0
    else
        log_warn "Cannot reach GitHub (may fail to download binaries)"
        return 0
    fi
}

check_package_repos() {
    ((CHECKS_TOTAL++))
    log_check "Package repositories access"

    if apt-get update -qq 2>&1 | grep -q "Err:"; then
        log_warn "Some package repositories unreachable"
        return 0
    else
        log_pass
        return 0
    fi
}

check_required_commands() {
    local commands=("wget" "curl" "systemctl")
    local missing=()

    for cmd in "${commands[@]}"; do
        ((CHECKS_TOTAL++))
        log_check "Command available: $cmd"

        if command -v "$cmd" &>/dev/null; then
            log_pass
        else
            log_fail "Command not found" "Install with: apt-get install $cmd"
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]] && [[ "$FIX_MODE" == "true" ]]; then
        echo ""
        echo -e "${CYAN}Attempting to install missing commands...${NC}"
        apt-get update -qq
        apt-get install -y -qq "${missing[@]}"
        echo -e "${GREEN}Installed: ${missing[*]}${NC}"
    fi
}

check_firewall() {
    ((CHECKS_TOTAL++))
    log_check "Firewall installed (ufw)"

    if command -v ufw &>/dev/null; then
        log_pass
        return 0
    else
        log_warn "UFW not installed (will be installed during setup)"
        if [[ "$FIX_MODE" == "true" ]]; then
            echo -e "${CYAN}Installing ufw...${NC}"
            apt-get install -y -qq ufw
            echo -e "${GREEN}Installed ufw${NC}"
        fi
        return 0
    fi
}

check_systemd() {
    ((CHECKS_TOTAL++))
    log_check "Systemd init system"

    if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
        log_pass
        return 0
    else
        log_fail "Systemd not detected" "This stack requires systemd"
        return 1
    fi
}

check_config_file() {
    if [[ "$MODE" != "observability-vps" ]]; then
        return 0
    fi

    ((CHECKS_TOTAL++))
    log_check "Configuration file exists"

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local config_file="${script_dir}/../config/global.yaml"

    if [[ -f "$config_file" ]]; then
        log_pass
    else
        log_fail "config/global.yaml not found" "Create configuration file from template"
        return 1
    fi
}

check_config_placeholders() {
    if [[ "$MODE" != "observability-vps" ]]; then
        return 0
    fi

    ((CHECKS_TOTAL++))
    log_check "Configuration has no placeholders"

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local config_file="${script_dir}/../config/global.yaml"

    if [[ ! -f "$config_file" ]]; then
        return 0
    fi

    local placeholders
    placeholders=$(grep -i "YOUR_\|CHANGE_ME\|MONITORED_HOST.*_IP" "$config_file" | grep -v "^#" || echo "")

    if [[ -z "$placeholders" ]]; then
        log_pass
        return 0
    else
        log_fail "Found placeholder values in config" "Edit config/global.yaml and replace all placeholder values"
        echo "$placeholders" | while read -r line; do
            echo -e "        ${YELLOW}$line${NC}"
        done
        return 1
    fi
}

#===============================================================================
# MAIN
#===============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --observability-vps)
                MODE="observability-vps"
                shift
                ;;
            --monitored-host)
                MODE="monitored-host"
                shift
                ;;
            --fix)
                FIX_MODE=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}Error: Unknown option: $1${NC}" >&2
                echo ""
                show_help
                exit 1
                ;;
        esac
    done

    if [[ -z "$MODE" ]]; then
        echo -e "${RED}Error: Must specify --observability-vps or --monitored-host${NC}" >&2
        echo ""
        show_help
        exit 1
    fi
}

run_checks() {
    echo ""
    echo "=========================================="
    if [[ "$MODE" == "observability-vps" ]]; then
        echo -e "${BOLD}Pre-flight Checks: Observability VPS${NC}"
    else
        echo -e "${BOLD}Pre-flight Checks: Monitored Host${NC}"
    fi
    echo "=========================================="
    echo ""

    # Common checks
    check_root || true
    check_os
    check_architecture
    check_systemd
    check_disk_space
    check_memory
    check_required_commands
    check_firewall
    check_internet
    check_github_access
    check_package_repos

    # Mode-specific checks
    if [[ "$MODE" == "observability-vps" ]]; then
        check_config_file
        check_config_placeholders
        check_ports_vps
        check_dns
    else
        check_ports_host
    fi

    # Summary
    echo ""
    echo "=========================================="
    echo -e "${BOLD}Summary${NC}"
    echo "=========================================="
    echo ""
    echo -e "Total checks:    $CHECKS_TOTAL"
    echo -e "${GREEN}Passed:${NC}          $CHECKS_PASSED"
    if [[ $CHECKS_WARNING -gt 0 ]]; then
        echo -e "${YELLOW}Warnings:${NC}        $CHECKS_WARNING"
    fi
    if [[ $CHECKS_FAILED -gt 0 ]]; then
        echo -e "${RED}Failed:${NC}          $CHECKS_FAILED"
    fi
    echo ""

    if [[ $CHECKS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}All critical checks passed!${NC}"
        echo ""
        if [[ "$MODE" == "observability-vps" ]]; then
            echo "Ready to run: ./scripts/setup-observability.sh"
        else
            echo "Ready to run: ./scripts/setup-monitored-host.sh <OBSERVABILITY_IP>"
        fi
        echo ""
        return 0
    else
        echo -e "${RED}${BOLD}Some checks failed!${NC}"
        echo ""
        echo "Please fix the issues above before proceeding."
        if [[ "$FIX_MODE" == "false" ]]; then
            echo "You can try running with --fix to auto-fix some issues."
        fi
        echo ""
        return 1
    fi
}

main() {
    parse_args "$@"
    run_checks
}

main "$@"
