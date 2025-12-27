#!/usr/bin/env bash
#
# Example: Upgrade with State Machine
#
# Demonstrates how to use the upgrade state machine for
# robust, idempotent, and resumable upgrades.
#
# Author: Observability Stack Team
# License: MIT

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/../scripts/lib"

# Use test directory if not running as root
if [[ $EUID -ne 0 ]] && [[ -z "${UPGRADE_STATE_DIR:-}" ]]; then
    export UPGRADE_STATE_DIR="/tmp/observability-upgrades-demo-$$"
    export UPGRADE_HISTORY_DIR="${UPGRADE_STATE_DIR}/history"
    export UPGRADE_BACKUPS_DIR="${UPGRADE_STATE_DIR}/backups"
    export UPGRADE_STATE_FILE="${UPGRADE_STATE_DIR}/state.json"
    export UPGRADE_LOCK_FILE="${UPGRADE_STATE_DIR}/upgrade.lock"
    export UPGRADE_TEMP_DIR="${UPGRADE_STATE_DIR}/tmp"

    echo "INFO: Running in demo mode with test directory: $UPGRADE_STATE_DIR"
fi

# Source required libraries
# shellcheck source=../scripts/lib/upgrade-state.sh
source "${LIB_DIR}/upgrade-state.sh"

# Component version mapping
declare -A COMPONENT_VERSIONS=(
    ["node_exporter"]="1.9.1"
    ["nginx_exporter"]="1.5.1"
    ["mysqld_exporter"]="0.16.1"
    ["phpfpm_exporter"]="2.3.1"
    ["fail2ban_exporter"]="0.4.1"
)

#######################################
# Log message with timestamp
# Arguments:
#   $1 - Log level (INFO, WARN, ERROR)
#   $2 - Message
#######################################
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}"
}

#######################################
# Simulate component version check
# Arguments:
#   $1 - Component name
# Outputs:
#   Current version
#######################################
get_current_version() {
    local component="$1"

    # This would normally check actual installed version
    # For demo, we'll use a fixed mapping
    case "$component" in
        node_exporter) echo "1.7.0" ;;
        nginx_exporter) echo "1.1.0" ;;
        mysqld_exporter) echo "0.14.0" ;;
        phpfpm_exporter) echo "2.2.0" ;;
        fail2ban_exporter) echo "0.3.0" ;;
        *) echo "0.0.0" ;;
    esac
}

#######################################
# Create component backup
# Arguments:
#   $1 - Component name
#   $2 - Backup path
# Returns:
#   0 on success, 1 on failure
#######################################
create_backup() {
    local component="$1"
    local backup_path="$2"

    log "INFO" "Creating backup for $component at $backup_path"

    # Simulate backup creation
    # In real implementation, this would:
    # - Stop the service
    # - Create tar archive of binaries, configs, etc.
    # - Store checksum for verification

    local backup_dir
    backup_dir=$(dirname "$backup_path")
    mkdir -p "$backup_dir"

    # Simulate backup file
    echo "Backup of $component $(date)" > "$backup_path"

    log "INFO" "Backup created successfully"
    return 0
}

#######################################
# Download component
# Arguments:
#   $1 - Component name
#   $2 - Version
# Returns:
#   0 on success, 1 on failure
#######################################
download_component() {
    local component="$1"
    local version="$2"

    log "INFO" "Downloading $component version $version"

    # Simulate download with progress
    local steps=10
    for i in $(seq 1 $steps); do
        sleep 0.1
        local percent=$((i * 100 / steps))
        printf "\rDownloading: %d%%" "$percent"
    done
    printf "\n"

    # Simulate occasional failure (for testing)
    if [[ -n "${SIMULATE_DOWNLOAD_FAILURE:-}" ]] && [[ "$component" == "$SIMULATE_DOWNLOAD_FAILURE" ]]; then
        log "ERROR" "Download failed (simulated)"
        return 1
    fi

    log "INFO" "Download completed"
    return 0
}

#######################################
# Install component
# Arguments:
#   $1 - Component name
#   $2 - Version
# Returns:
#   0 on success, 1 on failure
#######################################
install_component() {
    local component="$1"
    local version="$2"

    log "INFO" "Installing $component version $version"

    # Simulate installation
    sleep 0.5

    # Simulate occasional failure (for testing)
    if [[ -n "${SIMULATE_INSTALL_FAILURE:-}" ]] && [[ "$component" == "$SIMULATE_INSTALL_FAILURE" ]]; then
        log "ERROR" "Installation failed (simulated)"
        return 1
    fi

    log "INFO" "Installation completed"
    return 0
}

#######################################
# Validate component
# Arguments:
#   $1 - Component name
#   $2 - Expected version
# Returns:
#   0 on success, 1 on failure
#######################################
validate_component() {
    local component="$1"
    local expected_version="$2"

    log "INFO" "Validating $component version $expected_version"

    # Simulate validation
    sleep 0.2

    log "INFO" "Validation successful"
    return 0
}

#######################################
# Upgrade a single component
# Arguments:
#   $1 - Component name
# Returns:
#   0 on success, 1 on failure
#######################################
upgrade_component() {
    local component="$1"
    local from_version
    local to_version="${COMPONENT_VERSIONS[$component]}"

    # Get current version
    from_version=$(get_current_version "$component")

    log "INFO" "Processing $component: $from_version → $to_version"

    # Check if already upgraded (idempotency)
    if upgrade_component_is_upgraded "$component"; then
        log "INFO" "$component already upgraded to $to_version, skipping"
        return 0
    fi

    # Check if versions match (nothing to do)
    if [[ "$from_version" == "$to_version" ]]; then
        log "INFO" "$component already at target version $to_version"
        upgrade_component_start "$component" "$from_version" "$to_version"
        upgrade_component_complete "$component"
        return 0
    fi

    # Start component upgrade
    upgrade_component_start "$component" "$from_version" "$to_version"

    # Create backup
    local backup_path
    backup_path="${UPGRADE_BACKUPS_DIR}/${component}-${from_version}-$(date +%Y%m%d-%H%M%S).tar.gz"

    if ! create_backup "$component" "$backup_path"; then
        upgrade_component_fail "$component" "Backup creation failed"
        return 1
    fi

    # Mark rollback point
    upgrade_mark_rollback_point "$component" "$backup_path"

    # Download component
    if ! download_component "$component" "$to_version"; then
        upgrade_component_fail "$component" "Download failed"
        return 1
    fi

    # Install component
    if ! install_component "$component" "$to_version"; then
        upgrade_component_fail "$component" "Installation failed"
        return 1
    fi

    # Validate installation
    if ! validate_component "$component" "$to_version"; then
        upgrade_component_fail "$component" "Validation failed"
        return 1
    fi

    # Mark as complete
    upgrade_component_complete "$component"
    log "INFO" "$component upgrade completed successfully"

    return 0
}

#######################################
# Upgrade all exporters
# Returns:
#   0 on success, 1 on failure
#######################################
upgrade_exporters() {
    log "INFO" "Starting exporters upgrade phase"

    upgrade_phase_start "exporters"

    local failed=0
    local components=(
        "node_exporter"
        "nginx_exporter"
        "mysqld_exporter"
        "phpfpm_exporter"
        "fail2ban_exporter"
    )

    for component in "${components[@]}"; do
        if ! upgrade_component "$component"; then
            log "ERROR" "Failed to upgrade $component"
            failed=1
            break
        fi
    done

    if [[ $failed -eq 0 ]]; then
        upgrade_phase_complete "exporters"
        log "INFO" "Exporters upgrade phase completed"
        return 0
    else
        upgrade_phase_fail "exporters" "One or more component upgrades failed"
        log "ERROR" "Exporters upgrade phase failed"
        return 1
    fi
}

#######################################
# Run post-upgrade validation
# Returns:
#   0 on success, 1 on failure
#######################################
run_validation() {
    log "INFO" "Running post-upgrade validation"

    upgrade_state_set "VALIDATING"

    # Simulate validation checks
    local checks=(
        "Service health checks"
        "Metrics collection validation"
        "Configuration verification"
        "Integration tests"
    )

    for check in "${checks[@]}"; do
        log "INFO" "Running: $check"
        sleep 0.3
    done

    log "INFO" "All validation checks passed"
    return 0
}

#######################################
# Display upgrade progress
#######################################
show_progress() {
    local progress
    progress=$(upgrade_get_progress_percent)

    local current_state
    current_state=$(upgrade_state_get_current)

    local current_component
    current_component=$(upgrade_state_load | jq -r '.current_component // "None"')

    echo ""
    echo "==================================="
    echo "  Upgrade Progress"
    echo "==================================="
    echo "State: $current_state"
    echo "Component: $current_component"
    echo "Progress: ${progress}%"

    # Draw progress bar
    local bar_length=50
    local filled=$((progress * bar_length / 100))
    local empty=$((bar_length - filled))

    printf "["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "]\n"
    echo "==================================="
    echo ""
}

#######################################
# Main upgrade orchestration
#######################################
main() {
    log "INFO" "Starting observability stack upgrade"

    # Check if upgrade is already in progress
    if upgrade_is_in_progress; then
        log "WARN" "Upgrade already in progress"

        if upgrade_can_resume; then
            log "INFO" "Resuming previous upgrade"
            local resume_info
            resume_info=$(upgrade_get_resume_point)
            echo "$resume_info" | jq '.'

            if ! upgrade_resume; then
                log "ERROR" "Failed to resume upgrade"
                exit 1
            fi
        else
            log "ERROR" "Cannot resume upgrade, manual intervention required"
            exit 1
        fi
    else
        # Start new upgrade
        local upgrade_id
        if ! upgrade_id=$(upgrade_state_init); then
            log "ERROR" "Failed to initialize upgrade state"
            exit 1
        fi

        log "INFO" "Initialized upgrade: $upgrade_id"
    fi

    # Acquire lock
    if ! upgrade_lock_acquire; then
        log "ERROR" "Failed to acquire upgrade lock"
        log "ERROR" "Another upgrade may be in progress"
        exit 1
    fi

    # Ensure cleanup on exit
    trap 'upgrade_cleanup' EXIT

    # Planning phase
    log "INFO" "=== PLANNING PHASE ==="
    upgrade_state_set "PLANNING"

    log "INFO" "Analyzing components to upgrade:"
    for component in "${!COMPONENT_VERSIONS[@]}"; do
        local current_version
        current_version=$(get_current_version "$component")
        local target_version="${COMPONENT_VERSIONS[$component]}"
        log "INFO" "  - $component: $current_version → $target_version"
    done

    show_progress

    # Backing up phase
    log "INFO" "=== BACKING UP PHASE ==="
    upgrade_state_set "BACKING_UP"
    log "INFO" "Backup directory: $UPGRADE_BACKUPS_DIR"

    show_progress

    # Upgrading phase
    log "INFO" "=== UPGRADING PHASE ==="
    upgrade_state_set "UPGRADING"

    if ! upgrade_exporters; then
        log "ERROR" "Upgrade failed during exporters phase"
        upgrade_state_set "FAILED"
        exit 1
    fi

    show_progress

    # Validation phase
    log "INFO" "=== VALIDATION PHASE ==="
    if ! run_validation; then
        log "ERROR" "Validation failed"
        upgrade_state_set "FAILED"
        exit 1
    fi

    show_progress

    # Completion
    log "INFO" "=== COMPLETION ==="
    upgrade_state_set "COMPLETED"

    show_progress

    log "INFO" "Upgrade completed successfully!"

    # Show summary
    echo ""
    upgrade_get_summary

    # Show rollback information
    echo ""
    echo "Rollback information:"
    upgrade_get_rollback_info | jq '.'

    return 0
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
