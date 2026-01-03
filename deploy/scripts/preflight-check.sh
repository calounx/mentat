#!/usr/bin/env bash
# Pre-flight Checks for Deployment
# Validates environment before running deployment scripts
# Usage: ./preflight-check.sh [--server mentat|landsraad|both] [--skip-network]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utils/logging.sh"

# Configuration
SERVER_TYPE="${SERVER_TYPE:-local}"
SKIP_NETWORK=false
SKIP_CONNECTIVITY=false
STRICT_MODE=true

# Server IPs (override with environment variables)
MENTAT_IP="${MENTAT_IP:-}"
MENTAT_HOST="${MENTAT_HOST:-mentat.arewel.com}"
LANDSRAAD_IP="${LANDSRAAD_IP:-}"
LANDSRAAD_HOST="${LANDSRAAD_HOST:-landsraad.arewel.com}"

# Requirements
MIN_DISK_GB=20
MIN_MEMORY_GB=2
MIN_DEBIAN_VERSION=11

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --server)
            SERVER_TYPE="$2"
            shift 2
            ;;
        --skip-network)
            SKIP_NETWORK=true
            shift
            ;;
        --skip-connectivity)
            SKIP_CONNECTIVITY=true
            shift
            ;;
        --no-strict)
            STRICT_MODE=false
            shift
            ;;
        *)
            log_error "Unknown argument: $1"
            echo "Usage: $0 [--server mentat|landsraad|both] [--skip-network] [--skip-connectivity] [--no-strict]"
            exit 1
            ;;
    esac
done

init_deployment_log "preflight-check-$(date +%Y%m%d_%H%M%S)"

# Track failures
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# Helper function to record check result
record_check() {
    local result="$1"
    local message="$2"

    case "$result" in
        PASS)
            log_success "$message"
            CHECKS_PASSED=$((CHECKS_PASSED + 1))
            return 0
            ;;
        FAIL)
            log_error "$message"
            CHECKS_FAILED=$((CHECKS_FAILED + 1))
            return 1
            ;;
        WARN)
            log_warning "$message"
            CHECKS_WARNING=$((CHECKS_WARNING + 1))
            return 0
            ;;
    esac
}

# ============================================================================
# SYSTEM CHECKS
# ============================================================================

check_os_version() {
    log_section "Operating System Checks"

    # Check if running Linux
    if [[ "$(uname -s)" != "Linux" ]]; then
        record_check FAIL "Not running on Linux (detected: $(uname -s))"
        return 1
    fi
    record_check PASS "Running on Linux"

    # Check if Debian-based
    if [[ ! -f /etc/debian_version ]]; then
        record_check FAIL "Not running on Debian-based system"
        return 1
    fi
    record_check PASS "Running on Debian-based system"

    # Check Debian version
    if command -v lsb_release &>/dev/null; then
        local debian_version=$(lsb_release -sr 2>/dev/null | cut -d. -f1)
        local debian_codename=$(lsb_release -sc 2>/dev/null)

        log_info "Debian version: $debian_version ($debian_codename)"

        if [[ $debian_version -ge $MIN_DEBIAN_VERSION ]]; then
            record_check PASS "Debian version $debian_version meets minimum requirement ($MIN_DEBIAN_VERSION)"
        else
            record_check FAIL "Debian version $debian_version is below minimum ($MIN_DEBIAN_VERSION)"
            return 1
        fi
    else
        record_check WARN "Cannot determine Debian version (lsb_release not found)"
    fi

    # Check architecture
    local arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]]; then
        record_check PASS "Architecture: x86_64 (amd64)"
    else
        record_check WARN "Unexpected architecture: $arch (expected x86_64)"
    fi
}

check_system_resources() {
    log_section "System Resource Checks"

    # Check available memory
    local total_memory_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_memory_gb=$((total_memory_kb / 1024 / 1024))

    log_info "Total memory: ${total_memory_gb}GB"

    if [[ $total_memory_gb -ge $MIN_MEMORY_GB ]]; then
        record_check PASS "Memory: ${total_memory_gb}GB (minimum: ${MIN_MEMORY_GB}GB)"
    else
        record_check FAIL "Insufficient memory: ${total_memory_gb}GB (minimum: ${MIN_MEMORY_GB}GB)"
    fi

    # Check available disk space on root partition
    local root_available_gb=$(df / | tail -1 | awk '{print int($4/1024/1024)}')

    log_info "Root partition available space: ${root_available_gb}GB"

    if [[ $root_available_gb -ge $MIN_DISK_GB ]]; then
        record_check PASS "Disk space: ${root_available_gb}GB available (minimum: ${MIN_DISK_GB}GB)"
    else
        record_check FAIL "Insufficient disk space: ${root_available_gb}GB (minimum: ${MIN_DISK_GB}GB)"
    fi

    # Check CPU cores
    local cpu_cores=$(nproc)
    log_info "CPU cores: $cpu_cores"

    if [[ $cpu_cores -ge 2 ]]; then
        record_check PASS "CPU cores: $cpu_cores (recommended: 2+)"
    else
        record_check WARN "Limited CPU cores: $cpu_cores (recommended: 2+)"
    fi

    # Check load average
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk -F, '{print $1}' | tr -d ' ')
    log_info "Current load average (1min): $load_avg"

    if (( $(echo "$load_avg < $cpu_cores" | bc -l 2>/dev/null || echo 1) )); then
        record_check PASS "System load is reasonable"
    else
        record_check WARN "High system load: $load_avg (CPU cores: $cpu_cores)"
    fi
}

check_sudo_access() {
    log_section "Privilege Checks"

    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        record_check WARN "Running as root (recommended: use sudo instead)"
    else
        record_check PASS "Not running as root"
    fi

    # Check sudo access
    if sudo -n true 2>/dev/null; then
        record_check PASS "Passwordless sudo access available"
    else
        log_info "Testing sudo access (may prompt for password)..."
        if sudo true 2>/dev/null; then
            record_check PASS "Sudo access available (with password)"
        else
            record_check FAIL "No sudo access available"
            return 1
        fi
    fi
}

# ============================================================================
# NETWORK CHECKS
# ============================================================================

check_network_connectivity() {
    if [[ "$SKIP_NETWORK" == true ]]; then
        log_section "Network Checks (SKIPPED)"
        return 0
    fi

    log_section "Network Connectivity Checks"

    # Check internet connectivity
    if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        record_check PASS "Internet connectivity (ping to 8.8.8.8)"
    else
        record_check FAIL "No internet connectivity"
    fi

    # Check DNS resolution
    if host google.com &>/dev/null; then
        record_check PASS "DNS resolution working"
    else
        record_check FAIL "DNS resolution failed"
    fi

    # Check access to package repositories
    if curl -sf --max-time 5 http://deb.debian.org &>/dev/null; then
        record_check PASS "Access to Debian package repositories"
    else
        record_check WARN "Cannot reach Debian package repositories (may affect installation)"
    fi

    # Check GitHub access (for cloning repositories)
    if curl -sf --max-time 5 https://github.com &>/dev/null; then
        record_check PASS "Access to GitHub"
    else
        record_check WARN "Cannot reach GitHub (may affect repository cloning)"
    fi
}

check_server_connectivity() {
    if [[ "$SKIP_CONNECTIVITY" == true || "$SKIP_NETWORK" == true ]]; then
        log_section "Server Connectivity Checks (SKIPPED)"
        return 0
    fi

    log_section "Server Connectivity Checks"

    case "$SERVER_TYPE" in
        mentat)
            check_host_reachable "$MENTAT_HOST" "$MENTAT_IP" "Mentat"
            ;;
        landsraad)
            check_host_reachable "$LANDSRAAD_HOST" "$LANDSRAAD_IP" "Landsraad"
            ;;
        both)
            check_host_reachable "$MENTAT_HOST" "$MENTAT_IP" "Mentat"
            check_host_reachable "$LANDSRAAD_HOST" "$LANDSRAAD_IP" "Landsraad"
            ;;
        local)
            record_check PASS "Local deployment mode - no remote connectivity needed"
            ;;
    esac
}

check_host_reachable() {
    local hostname="$1"
    local ip="$2"
    local server_name="$3"

    log_info "Checking connectivity to $server_name ($hostname)..."

    # Try hostname resolution
    if host "$hostname" &>/dev/null; then
        record_check PASS "$server_name: DNS resolution for $hostname"
    else
        record_check WARN "$server_name: DNS resolution failed for $hostname"
    fi

    # Try ping
    if ping -c 1 -W 2 "$hostname" &>/dev/null; then
        record_check PASS "$server_name: Host is reachable (ping)"
    else
        record_check WARN "$server_name: Host not reachable via ping (may be firewalled)"
    fi

    # Try SSH (port 22)
    if nc -z -w 2 "$hostname" 22 2>/dev/null; then
        record_check PASS "$server_name: SSH port (22) is open"
    else
        record_check WARN "$server_name: SSH port (22) appears closed or firewalled"
    fi
}

# ============================================================================
# REQUIRED PACKAGES CHECKS
# ============================================================================

check_required_packages() {
    log_section "Required Package Checks"

    local essential_packages=(
        "curl"
        "wget"
        "git"
        "sudo"
        "systemctl"
    )

    local missing_packages=()

    for package in "${essential_packages[@]}"; do
        if command -v "$package" &>/dev/null; then
            record_check PASS "Command available: $package"
        else
            record_check FAIL "Missing command: $package"
            missing_packages+=("$package")
        fi
    done

    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        log_error "Missing packages: ${missing_packages[*]}"
        log_info "Install with: sudo apt-get install -y ${missing_packages[*]}"
        return 1
    fi
}

# ============================================================================
# PORT AVAILABILITY CHECKS
# ============================================================================

check_port_availability() {
    log_section "Port Availability Checks"

    local required_ports=()

    case "$SERVER_TYPE" in
        mentat)
            required_ports=(
                "9090:Prometheus"
                "3000:Grafana"
                "9093:AlertManager"
                "3100:Loki"
                "9100:Node Exporter"
            )
            ;;
        landsraad)
            required_ports=(
                "80:HTTP"
                "443:HTTPS"
                "9100:Node Exporter"
            )
            ;;
        both|local)
            log_info "Skipping port checks for local deployment"
            return 0
            ;;
    esac

    for port_spec in "${required_ports[@]}"; do
        local port="${port_spec%%:*}"
        local service="${port_spec#*:}"

        if ! sudo netstat -tuln 2>/dev/null | grep -q ":${port} " && \
           ! sudo ss -tuln 2>/dev/null | grep -q ":${port} "; then
            record_check PASS "Port $port available for $service"
        else
            record_check WARN "Port $port already in use (needed for $service)"
        fi
    done
}

# ============================================================================
# DIRECTORY AND PERMISSION CHECKS
# ============================================================================

check_filesystem_permissions() {
    log_section "Filesystem Permission Checks"

    local test_dir="/opt/preflight-test-$$"

    # Test write access to /opt
    if sudo mkdir -p "$test_dir" 2>/dev/null; then
        sudo rmdir "$test_dir"
        record_check PASS "Write access to /opt directory"
    else
        record_check FAIL "Cannot write to /opt directory"
    fi

    # Test write access to /etc
    local test_file="/etc/preflight-test-$$"
    if sudo touch "$test_file" 2>/dev/null; then
        sudo rm -f "$test_file"
        record_check PASS "Write access to /etc directory"
    else
        record_check FAIL "Cannot write to /etc directory"
    fi

    # Test write access to /var
    if sudo mkdir -p "/var/lib/preflight-test-$$" 2>/dev/null; then
        sudo rmdir "/var/lib/preflight-test-$$"
        record_check PASS "Write access to /var directory"
    else
        record_check FAIL "Cannot write to /var directory"
    fi
}

# ============================================================================
# SERVICE CHECKS
# ============================================================================

check_systemd() {
    log_section "Systemd Checks"

    # Check if systemd is running
    if pidof systemd &>/dev/null || pidof /lib/systemd/systemd &>/dev/null; then
        record_check PASS "Systemd is running"
    else
        record_check FAIL "Systemd is not running (required for service management)"
        return 1
    fi

    # Check systemctl command
    if command -v systemctl &>/dev/null; then
        record_check PASS "systemctl command available"
    else
        record_check FAIL "systemctl command not found"
        return 1
    fi

    # Check if we can list services
    if sudo systemctl list-units --type=service &>/dev/null; then
        record_check PASS "Can query systemd services"
    else
        record_check FAIL "Cannot query systemd services"
        return 1
    fi
}

# ============================================================================
# SECURITY CHECKS
# ============================================================================

check_security_settings() {
    log_section "Security Configuration Checks"

    # Check if firewall is installed
    if command -v ufw &>/dev/null; then
        record_check PASS "UFW firewall available"

        # Check firewall status
        if sudo ufw status 2>/dev/null | grep -q "Status: active"; then
            record_check PASS "UFW firewall is active"
        else
            record_check WARN "UFW firewall is installed but not active"
        fi
    else
        record_check WARN "UFW firewall not installed (will be installed during setup)"
    fi

    # Check SSH configuration
    if [[ -f /etc/ssh/sshd_config ]]; then
        record_check PASS "SSH configuration file exists"

        # Check if root login is disabled (best practice)
        if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
            record_check PASS "SSH: Root login is disabled (good)"
        else
            record_check WARN "SSH: Root login may be enabled (will be hardened during setup)"
        fi
    else
        record_check WARN "SSH configuration file not found"
    fi

    # Check for unattended-upgrades
    if dpkg -l unattended-upgrades 2>/dev/null | grep -q "^ii"; then
        record_check PASS "Automatic security updates configured"
    else
        record_check WARN "Automatic security updates not configured (will be set up)"
    fi
}

# ============================================================================
# ENVIRONMENT VARIABLE CHECKS
# ============================================================================

check_environment_variables() {
    log_section "Environment Variable Checks"

    # Check for required environment variables (optional for local deployment)
    local env_vars=(
        "PATH"
        "HOME"
        "USER"
    )

    for var in "${env_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            record_check PASS "Environment variable set: $var"
        else
            record_check WARN "Environment variable not set: $var"
        fi
    done

    # Check PATH includes common binary directories
    if echo "$PATH" | grep -q "/usr/local/bin"; then
        record_check PASS "/usr/local/bin is in PATH"
    else
        record_check WARN "/usr/local/bin is not in PATH (may cause issues)"
    fi
}

# ============================================================================
# TIME AND TIMEZONE CHECKS
# ============================================================================

check_time_configuration() {
    log_section "Time and Timezone Checks"

    # Check if timedatectl is available
    if command -v timedatectl &>/dev/null; then
        # Check NTP synchronization
        if timedatectl status 2>/dev/null | grep -q "synchronized: yes"; then
            record_check PASS "System time is synchronized via NTP"
        else
            record_check WARN "System time may not be synchronized (can cause certificate issues)"
        fi

        # Show timezone
        local timezone=$(timedatectl show -p Timezone --value 2>/dev/null || echo "unknown")
        log_info "Timezone: $timezone"
        record_check PASS "Timezone configured: $timezone"
    else
        record_check WARN "timedatectl not available (cannot verify time sync)"
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    start_timer

    print_header "Pre-flight Deployment Checks"
    log_info "Server type: $SERVER_TYPE"
    log_info "Strict mode: $STRICT_MODE"

    # Run all checks
    check_os_version
    check_system_resources
    check_sudo_access
    check_network_connectivity
    check_server_connectivity
    check_required_packages
    check_port_availability
    check_filesystem_permissions
    check_systemd
    check_security_settings
    check_environment_variables
    check_time_configuration

    end_timer "Pre-flight checks"

    # Summary
    print_header "Pre-flight Check Summary"
    log_info "Checks passed:  $CHECKS_PASSED"
    log_info "Checks warned:  $CHECKS_WARNING"
    log_info "Checks failed:  $CHECKS_FAILED"

    echo ""

    if [[ $CHECKS_FAILED -eq 0 ]]; then
        log_success "All critical pre-flight checks passed!"

        if [[ $CHECKS_WARNING -gt 0 ]]; then
            log_warning "There are $CHECKS_WARNING warnings - review before deployment"
            if [[ "$STRICT_MODE" == true ]]; then
                log_warning "Running in strict mode - warnings treated as failures"
                exit 1
            fi
        fi

        log_success "System is ready for deployment"
        exit 0
    else
        log_error "Pre-flight checks failed: $CHECKS_FAILED critical issue(s) found"
        log_error "Please resolve the issues above before proceeding with deployment"
        exit 1
    fi
}

main
