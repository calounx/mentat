#!/bin/bash
#===============================================================================
# Observability Stack Rollback Manager
#
# Provides safe rollback capabilities for observability stack components
#
# Features:
#   - List available backups
#   - Rollback to specific backup timestamp
#   - Rollback specific components
#   - Verify rollback success
#
# Usage:
#   observability-rollback --list                  # List available backups
#   observability-rollback --to=TIMESTAMP          # Rollback to backup
#   observability-rollback --to=TIMESTAMP --component=NAME
#   observability-rollback --previous              # Rollback to previous version
#
#===============================================================================

set -euo pipefail

# Directories
BACKUP_DIR="/var/backups/observability"
STATE_DIR="/var/lib/observability"
VERSION_STATE_FILE="${STATE_DIR}/versions.state"

# Options
BACKUP_TIMESTAMP=""
SPECIFIC_COMPONENT=""
FORCE_MODE=false

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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

#===============================================================================
# BACKUP LISTING
#===============================================================================

list_backups() {
    echo "Available Backups:"
    echo "=================="
    echo ""

    if [[ ! -d "$BACKUP_DIR" ]]; then
        echo "No backups found"
        return
    fi

    # Find all backup directories (format: YYYYMMDD_HHMMSS)
    local backups=()
    while IFS= read -r -d '' backup_dir; do
        backups+=("$(basename "$backup_dir")")
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type d -name "20*_*" -print0 | sort -rz)

    if [[ ${#backups[@]} -eq 0 ]]; then
        echo "No backups found"
        return
    fi

    printf "%-20s %-15s %-30s\n" "Timestamp" "Size" "Components"
    echo "------------------------------------------------------------------------"

    for backup in "${backups[@]}"; do
        local backup_path="${BACKUP_DIR}/${backup}"
        local size
        size=$(du -sh "$backup_path" 2>/dev/null | awk '{print $1}')

        local components=""
        if [[ -d "${backup_path}/bin" ]]; then
            components=$(ls "${backup_path}/bin" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
        fi

        printf "%-20s %-15s %-30s\n" "$backup" "$size" "$components"
    done

    echo ""
    echo "Use: observability-rollback --to=TIMESTAMP to rollback"
}

#===============================================================================
# ROLLBACK FUNCTIONS
#===============================================================================

get_version_from_backup() {
    local backup_timestamp="$1"
    local component="$2"
    local backup_dir="${BACKUP_DIR}/${backup_timestamp}"
    local plan_file="${backup_dir}/upgrade-plan.json"

    if [[ -f "$plan_file" ]]; then
        jq -r ".components.\"${component}\".old_version // \"unknown\"" "$plan_file"
    else
        echo "unknown"
    fi
}

get_current_version() {
    local component="$1"

    if [[ -f "$VERSION_STATE_FILE" ]]; then
        jq -r ".components.\"${component}\".current_version // \"unknown\"" "$VERSION_STATE_FILE"
    else
        echo "unknown"
    fi
}

rollback_component() {
    local component="$1"
    local backup_timestamp="$2"
    local backup_dir="${BACKUP_DIR}/${backup_timestamp}"

    log_info "Rolling back ${component}..."

    # 1. Validate backup exists
    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup directory not found: $backup_dir"
        return 1
    fi

    if [[ ! -f "${backup_dir}/bin/${component}" ]]; then
        log_error "Backup binary not found for ${component}"
        return 1
    fi

    # 2. Stop service
    log_info "Stopping ${component} service..."
    systemctl stop "${component}" 2>/dev/null || true
    sleep 2

    # Kill any lingering processes
    case "$component" in
        prometheus|alertmanager|loki|promtail)
            pkill -9 -f "/usr/local/bin/${component}" 2>/dev/null || true
            ;;
        node_exporter)
            pkill -9 -f "/usr/local/bin/node_exporter" 2>/dev/null || true
            ;;
        nginx_exporter)
            pkill -9 -f "nginx-prometheus-exporter" 2>/dev/null || true
            ;;
        phpfpm_exporter)
            pkill -9 -f "php-fpm_exporter" 2>/dev/null || true
            ;;
        fail2ban_exporter)
            pkill -9 -f "fail2ban-prometheus-exporter" 2>/dev/null || true
            ;;
        mysqld_exporter)
            pkill -9 -f "mysqld_exporter" 2>/dev/null || true
            ;;
    esac

    sleep 1

    # 3. Restore binary
    log_info "Restoring binary from backup..."

    local target_binary=""
    case "$component" in
        nginx_exporter)
            target_binary="/usr/local/bin/nginx-prometheus-exporter"
            ;;
        phpfpm_exporter)
            target_binary="/usr/local/bin/php-fpm_exporter"
            ;;
        fail2ban_exporter)
            target_binary="/usr/local/bin/fail2ban-prometheus-exporter"
            ;;
        mysqld_exporter)
            target_binary="/usr/local/bin/mysqld_exporter"
            ;;
        *)
            target_binary="/usr/local/bin/${component}"
            ;;
    esac

    cp "${backup_dir}/bin/${component}" "$target_binary"
    chmod 755 "$target_binary"
    chown root:root "$target_binary"

    # 4. Restore config (if exists in backup)
    if [[ -d "${backup_dir}/config/${component}" ]]; then
        log_info "Restoring configuration from backup..."
        cp -r "${backup_dir}/config/${component}"/* "/etc/${component}/" 2>/dev/null || true
    fi

    # 5. Restore systemd unit (if exists in backup)
    if [[ -f "${backup_dir}/systemd/${component}.service" ]]; then
        log_info "Restoring systemd unit from backup..."
        cp "${backup_dir}/systemd/${component}.service" "/etc/systemd/system/${component}.service"
        systemctl daemon-reload
    fi

    # 6. Start service
    log_info "Starting ${component} service..."
    systemctl start "${component}"
    sleep 3

    # 7. Verify service is running
    if ! systemctl is-active --quiet "${component}"; then
        log_error "Service failed to start after rollback"
        return 1
    fi

    # 8. Basic health check
    local health_passed=true
    case "$component" in
        prometheus)
            if ! curl -sf "http://localhost:9090/api/v1/status/config" >/dev/null 2>&1; then
                health_passed=false
            fi
            ;;
        loki)
            if ! curl -sf "http://localhost:3100/ready" >/dev/null 2>&1; then
                health_passed=false
            fi
            ;;
        node_exporter)
            if ! curl -sf "http://localhost:9100/metrics" >/dev/null 2>&1; then
                health_passed=false
            fi
            ;;
    esac

    if [[ "$health_passed" == "false" ]]; then
        log_warn "Health check failed after rollback"
    fi

    # 9. Update version state
    if [[ -f "$VERSION_STATE_FILE" ]]; then
        local rolled_back_version
        rolled_back_version=$(get_version_from_backup "$backup_timestamp" "$component")

        if [[ "$rolled_back_version" != "unknown" ]]; then
            local temp_file
            temp_file=$(mktemp)
            jq ".components.\"${component}\".current_version = \"${rolled_back_version}\"" \
                "$VERSION_STATE_FILE" > "$temp_file"
            mv "$temp_file" "$VERSION_STATE_FILE"
        fi
    fi

    log_success "Rollback completed for ${component}"
    return 0
}

rollback_to_backup() {
    local backup_timestamp="$1"
    local specific_component="$2"

    local backup_dir="${BACKUP_DIR}/${backup_timestamp}"
    local plan_file="${backup_dir}/upgrade-plan.json"

    # 1. Validate backup exists
    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup not found: $backup_dir"
        list_backups
        exit 1
    fi

    # 2. Determine components to rollback
    local components=()
    if [[ -n "$specific_component" ]]; then
        components=("$specific_component")
    else
        # Get all components from backup
        if [[ -d "${backup_dir}/bin" ]]; then
            while IFS= read -r comp; do
                components+=("$comp")
            done < <(ls "${backup_dir}/bin")
        fi
    fi

    if [[ ${#components[@]} -eq 0 ]]; then
        log_error "No components found in backup"
        exit 1
    fi

    # 3. Display rollback plan
    echo ""
    echo "Rollback Plan:"
    echo "=============="
    echo "Backup: $backup_timestamp"
    echo ""
    printf "%-20s %-15s %-15s\n" "Component" "Current" "Target"
    echo "--------------------------------------------------------"

    for comp in "${components[@]}"; do
        local current_ver
        current_ver=$(get_current_version "$comp")
        local target_ver
        target_ver=$(get_version_from_backup "$backup_timestamp" "$comp")
        printf "%-20s %-15s %-15s\n" "$comp" "$current_ver" "$target_ver"
    done

    echo ""

    # 4. Confirm rollback
    if [[ "$FORCE_MODE" != "true" ]]; then
        read -p "Proceed with rollback? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Rollback cancelled"
            exit 0
        fi
    fi

    # 5. Execute rollback
    local failed=()
    for comp in "${components[@]}"; do
        if ! rollback_component "$comp" "$backup_timestamp"; then
            failed+=("$comp")
        fi
    done

    # 6. Report results
    echo ""
    if [[ ${#failed[@]} -eq 0 ]]; then
        log_success "Rollback completed successfully"
        echo ""
        echo "All components have been rolled back to backup: $backup_timestamp"
    else
        log_error "Rollback failed for: ${failed[*]}"
        echo ""
        echo "Check service status: systemctl status <service-name>"
        echo "Check logs: journalctl -u <service-name> -n 100"
        exit 1
    fi
}

#===============================================================================
# COMMAND PARSING
#===============================================================================

usage() {
    cat <<EOF
Usage: observability-rollback [OPTIONS]

Options:
  --list                    List available backups
  --to=TIMESTAMP            Rollback to specific backup (format: YYYYMMDD_HHMMSS)
  --component=NAME          Rollback specific component only
  --previous                Rollback to most recent backup
  --force                   Skip confirmation prompts

Examples:
  observability-rollback --list
  observability-rollback --to=20241227_030000
  observability-rollback --to=20241227_030000 --component=prometheus
  observability-rollback --previous --force

EOF
}

parse_args() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --list)
                list_backups
                exit 0
                ;;
            --to=*)
                BACKUP_TIMESTAMP="${1#*=}"
                shift
                ;;
            --component=*)
                SPECIFIC_COMPONENT="${1#*=}"
                shift
                ;;
            --previous)
                # Get most recent backup
                BACKUP_TIMESTAMP=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "20*_*" -printf "%f\n" | sort -r | head -1)
                if [[ -z "$BACKUP_TIMESTAMP" ]]; then
                    log_error "No backups found"
                    exit 1
                fi
                shift
                ;;
            --force)
                FORCE_MODE=true
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

    # Execute rollback if timestamp specified
    if [[ -n "$BACKUP_TIMESTAMP" ]]; then
        rollback_to_backup "$BACKUP_TIMESTAMP" "$SPECIFIC_COMPONENT"
    else
        log_error "No action specified. Use --list or --to=TIMESTAMP"
        usage
        exit 1
    fi
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    check_root
    parse_args "$@"
}

main "$@"
