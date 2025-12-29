#!/bin/bash
#===============================================================================
# Observability Stack Upgrade Manager
#
# Provides idempotent, safe upgrades for observability stack components
#
# Features:
#   - Version checking and comparison
#   - Safe upgrades with automatic rollback on failure
#   - Backup management (keep N versions)
#   - Health validation
#   - Integration testing
#   - Notification support
#
# Usage:
#   observability-upgrade check                    # Check for updates
#   observability-upgrade plan                     # Show upgrade plan
#   observability-upgrade apply                    # Apply upgrades (interactive)
#   observability-upgrade apply --yes              # Auto-approve
#   observability-upgrade apply --component=NAME   # Upgrade specific component
#   observability-upgrade auto-enable              # Enable auto-upgrades
#   observability-upgrade auto-disable             # Disable auto-upgrades
#
#===============================================================================

set -euo pipefail

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
LIB_DIR="/usr/local/lib/observability"
STATE_DIR="/var/lib/observability"
BACKUP_DIR="/var/backups/observability"
CONFIG_DIR="/etc/observability"

# State files
VERSION_STATE_FILE="${STATE_DIR}/versions.state"
UPGRADE_HISTORY_DB="${STATE_DIR}/upgrade-history.db"

# Configuration
UPGRADE_POLICY_FILE="${CONFIG_DIR}/upgrade-policy.yaml"
COMPATIBILITY_MATRIX="${CONFIG_DIR}/compatibility-matrix.yaml"
NOTIFICATION_CONFIG="${CONFIG_DIR}/notifications.yaml"

# Defaults
BACKUP_RETENTION=5  # Keep last 5 backups
AUTO_APPROVE=false
DRY_RUN=false
SKIP_HEALTH_CHECKS=false
SPECIFIC_COMPONENT=""
CONTINUE_ON_FAILURE=false

# Colors
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

#===============================================================================
# UTILITY FUNCTIONS
#===============================================================================

log_info() {
    echo "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo "${RED}[ERROR]${NC} $1"
}

# Ensure required directories exist
init_directories() {
    mkdir -p "$STATE_DIR" "$BACKUP_DIR" "$CONFIG_DIR" "$LIB_DIR"
    mkdir -p "${BACKUP_DIR}/bin" "${BACKUP_DIR}/config" "${BACKUP_DIR}/systemd" "${BACKUP_DIR}/state"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Source upgrade library functions
source_lib() {
    if [[ -f "${LIB_DIR}/upgrade-lib.sh" ]]; then
        # shellcheck source=/dev/null
        source "${LIB_DIR}/upgrade-lib.sh"
    else
        log_error "Upgrade library not found: ${LIB_DIR}/upgrade-lib.sh"
        log_error "Run 'make install' to install required files"
        exit 1
    fi
}

#===============================================================================
# VERSION MANAGEMENT
#===============================================================================

# Initialize version state file
init_version_state() {
    if [[ ! -f "$VERSION_STATE_FILE" ]]; then
        log_info "Initializing version state file..."

        cat > "$VERSION_STATE_FILE" <<EOF
{
  "last_updated": "$(date -Iseconds)",
  "components": {},
  "upgrade_history": []
}
EOF
    fi
}

# Get current version of a component
get_current_version() {
    local component="$1"

    # Try to get from state file first
    if [[ -f "$VERSION_STATE_FILE" ]]; then
        local version
        version=$(jq -r ".components.\"${component}\".current_version // \"unknown\"" "$VERSION_STATE_FILE")
        if [[ "$version" != "unknown" && "$version" != "null" ]]; then
            echo "$version"
            return
        fi
    fi

    # Fallback: detect from binary
    case "$component" in
        prometheus|alertmanager|loki|promtail)
            local binary="/usr/local/bin/${component}"
            if [[ -x "$binary" ]]; then
                "$binary" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
            fi
            ;;
        node_exporter|nginx_exporter|phpfpm_exporter|fail2ban_exporter|mysqld_exporter)
            local binary_name="${component}"
            [[ "$component" == "nginx_exporter" ]] && binary_name="nginx-prometheus-exporter"
            [[ "$component" == "phpfpm_exporter" ]] && binary_name="php-fpm_exporter"
            [[ "$component" == "fail2ban_exporter" ]] && binary_name="fail2ban-prometheus-exporter"
            [[ "$component" == "mysqld_exporter" ]] && binary_name="mysqld_exporter"

            local binary="/usr/local/bin/${binary_name}"
            if [[ -x "$binary" ]]; then
                "$binary" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
            fi
            ;;
        grafana)
            if command -v grafana-server &>/dev/null; then
                grafana-server --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
            fi
            ;;
    esac
}

# Get latest available version from upstream
get_latest_version() {
    local component="$1"

    case "$component" in
        prometheus)
            curl -sf "https://api.github.com/repos/prometheus/prometheus/releases/latest" | jq -r '.tag_name' | sed 's/^v//'
            ;;
        alertmanager)
            curl -sf "https://api.github.com/repos/prometheus/alertmanager/releases/latest" | jq -r '.tag_name' | sed 's/^v//'
            ;;
        node_exporter)
            curl -sf "https://api.github.com/repos/prometheus/node_exporter/releases/latest" | jq -r '.tag_name' | sed 's/^v//'
            ;;
        nginx_exporter)
            curl -sf "https://api.github.com/repos/nginxinc/nginx-prometheus-exporter/releases/latest" | jq -r '.tag_name' | sed 's/^v//'
            ;;
        loki|promtail)
            curl -sf "https://api.github.com/repos/grafana/loki/releases/latest" | jq -r '.tag_name' | sed 's/^v//'
            ;;
        phpfpm_exporter)
            curl -sf "https://api.github.com/repos/hipages/php-fpm_exporter/releases/latest" | jq -r '.tag_name' | sed 's/^v//'
            ;;
        fail2ban_exporter)
            # GitLab API
            curl -sf "https://gitlab.com/api/v4/projects/hctrdev%2Ffail2ban-prometheus-exporter/releases" | jq -r '.[0].tag_name' | sed 's/^v//'
            ;;
        mysqld_exporter)
            curl -sf "https://api.github.com/repos/prometheus/mysqld_exporter/releases/latest" | jq -r '.tag_name' | sed 's/^v//'
            ;;
        grafana)
            curl -sf "https://api.github.com/repos/grafana/grafana/releases/latest" | jq -r '.tag_name' | sed 's/^v//'
            ;;
    esac
}

# Compare two semantic versions
# Returns: 0 if v1 == v2, 1 if v1 > v2, 2 if v1 < v2
version_compare() {
    local v1="$1"
    local v2="$2"

    # Split versions into major.minor.patch
    IFS='.' read -r -a v1_parts <<< "$v1"
    IFS='.' read -r -a v2_parts <<< "$v2"

    # Compare major
    if (( v1_parts[0] > v2_parts[0] )); then
        return 1
    elif (( v1_parts[0] < v2_parts[0] )); then
        return 2
    fi

    # Compare minor
    if (( v1_parts[1] > v2_parts[1] )); then
        return 1
    elif (( v1_parts[1] < v2_parts[1] )); then
        return 2
    fi

    # Compare patch
    if (( v1_parts[2] > v2_parts[2] )); then
        return 1
    elif (( v1_parts[2] < v2_parts[2] )); then
        return 2
    fi

    # Equal
    return 0
}

# Get version change type (major, minor, patch)
get_version_change_type() {
    local current="$1"
    local new="$2"

    IFS='.' read -r -a current_parts <<< "$current"
    IFS='.' read -r -a new_parts <<< "$new"

    if (( new_parts[0] > current_parts[0] )); then
        echo "major"
    elif (( new_parts[1] > current_parts[1] )); then
        echo "minor"
    else
        echo "patch"
    fi
}

#===============================================================================
# UPDATE CHECKING
#===============================================================================

# Check for available updates
cmd_check() {
    log_info "Checking for available updates..."

    # List of components to check
    local components=(
        "prometheus"
        "alertmanager"
        "loki"
        "promtail"
        "node_exporter"
        "nginx_exporter"
        "phpfpm_exporter"
        "fail2ban_exporter"
        "mysqld_exporter"
        "grafana"
    )

    local updates_available=false

    echo ""
    echo "Updates Available:"
    echo "=================="
    printf "%-20s %-15s %-15s %-10s %-15s\n" "Component" "Current" "Latest" "Type" "Release Date"
    echo "--------------------------------------------------------------------------------"

    for component in "${components[@]}"; do
        local current_version
        current_version=$(get_current_version "$component")

        if [[ -z "$current_version" || "$current_version" == "unknown" ]]; then
            # Component not installed, skip
            continue
        fi

        local latest_version
        latest_version=$(get_latest_version "$component")

        if [[ -z "$latest_version" ]]; then
            log_warn "Could not fetch latest version for $component"
            continue
        fi

        # Compare versions
        if version_compare "$current_version" "$latest_version"; then
            :  # Equal, no update needed
        else
            local change_type
            change_type=$(get_version_change_type "$current_version" "$latest_version")

            # Get release date (simplified - would fetch from API in real implementation)
            local release_date="N/A"

            printf "%-20s %-15s %-15s %-10s %-15s\n" \
                "$component" \
                "$current_version" \
                "$latest_version" \
                "$change_type" \
                "$release_date"

            updates_available=true
        fi
    done

    echo ""

    if [[ "$updates_available" == "false" ]]; then
        log_success "All components are up to date"
    else
        echo "Run 'observability-upgrade plan' to see upgrade plan"
        echo "Run 'observability-upgrade apply' to upgrade"
    fi
}

#===============================================================================
# UPGRADE PLANNING
#===============================================================================

cmd_plan() {
    log_info "Generating upgrade plan..."

    # This would generate detailed upgrade plan
    # For now, placeholder
    echo ""
    echo "Upgrade Plan:"
    echo "============="
    echo ""
    echo "This command will be implemented with full upgrade planning logic"
    echo ""
}

#===============================================================================
# APPLY UPGRADES
#===============================================================================

cmd_apply() {
    log_info "Starting upgrade process..."

    # This would apply upgrades
    # For now, placeholder
    echo ""
    echo "Upgrade Apply:"
    echo "=============="
    echo ""
    echo "This command will be implemented with full upgrade logic"
    echo ""
}

#===============================================================================
# AUTO-UPGRADE MANAGEMENT
#===============================================================================

cmd_auto_enable() {
    log_info "Enabling automatic upgrades..."

    # Enable systemd timer
    if systemctl enable observability-upgrade.timer 2>/dev/null; then
        systemctl start observability-upgrade.timer
        log_success "Automatic upgrades enabled"
    else
        log_error "Failed to enable automatic upgrades"
        log_error "Timer unit not found: observability-upgrade.timer"
        exit 1
    fi
}

cmd_auto_disable() {
    log_info "Disabling automatic upgrades..."

    systemctl stop observability-upgrade.timer 2>/dev/null || true
    systemctl disable observability-upgrade.timer 2>/dev/null || true

    log_success "Automatic upgrades disabled"
}

cmd_auto_status() {
    echo "Auto-Upgrade Status:"
    echo "==================="
    echo ""

    if systemctl is-enabled observability-upgrade.timer &>/dev/null; then
        echo "Status: ENABLED"

        if systemctl is-active observability-upgrade.timer &>/dev/null; then
            echo "Active: YES"
        else
            echo "Active: NO"
        fi

        echo ""
        echo "Next scheduled run:"
        systemctl list-timers observability-upgrade.timer --no-pager
    else
        echo "Status: DISABLED"
    fi
}

#===============================================================================
# COMMAND PARSING
#===============================================================================

usage() {
    cat <<EOF
Usage: observability-upgrade COMMAND [OPTIONS]

Commands:
  check                     Check for available updates
  plan                      Generate upgrade plan
  apply                     Apply upgrades (interactive)
  auto-enable               Enable automatic upgrades
  auto-disable              Disable automatic upgrades
  auto-status               Show auto-upgrade status

Options:
  --yes                     Auto-approve upgrades (non-interactive)
  --component=NAME          Upgrade specific component only
  --dry-run                 Simulate upgrade without applying
  --skip-health-checks      Skip health validation (dangerous!)
  --continue-on-failure     Continue upgrading other components if one fails

Examples:
  observability-upgrade check
  observability-upgrade apply --yes
  observability-upgrade apply --component=prometheus
  observability-upgrade auto-enable

See 'observability-rollback --help' for rollback options.
EOF
}

# Parse arguments
parse_args() {
    local command="${1:-}"

    if [[ -z "$command" ]]; then
        usage
        exit 1
    fi

    shift || true

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --yes|-y)
                AUTO_APPROVE=true
                shift
                ;;
            --component=*)
                SPECIFIC_COMPONENT="${1#*=}"
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-health-checks)
                SKIP_HEALTH_CHECKS=true
                shift
                ;;
            --continue-on-failure)
                CONTINUE_ON_FAILURE=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Execute command
    case "$command" in
        check)
            cmd_check
            ;;
        plan)
            cmd_plan
            ;;
        apply)
            cmd_apply
            ;;
        auto-enable)
            cmd_auto_enable
            ;;
        auto-disable)
            cmd_auto_disable
            ;;
        auto-status)
            cmd_auto_status
            ;;
        *)
            log_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    check_root
    init_directories
    init_version_state

    # Source library only for commands that need it
    # (check command works standalone)
    if [[ "${1:-}" != "check" ]] && [[ "${1:-}" != "auto-status" ]]; then
        source_lib
    fi

    parse_args "$@"
}

main "$@"
