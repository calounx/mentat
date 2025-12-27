#!/bin/bash
#===============================================================================
# Upgrade Orchestrator
# Part of the observability-stack upgrade orchestration system
#
# Main entry point for idempotent, safe component upgrades
#
# Features:
#   - Idempotent execution (safe to run multiple times)
#   - Crash recovery and resume support
#   - Phased upgrades with dependency handling
#   - Automatic backups and rollback
#   - Dry-run mode for testing
#   - State persistence
#
# Usage:
#   ./upgrade-orchestrator.sh [OPTIONS]
#
# Options:
#   --all                 Upgrade all components
#   --component <name>    Upgrade specific component
#   --phase <number>      Upgrade specific phase
#   --dry-run            Show what would be upgraded without making changes
#   --resume             Resume from last failure point
#   --rollback           Rollback last upgrade
#   --force              Force upgrade even if at target version
#   --status             Show current upgrade status
#   --mode <mode>        Upgrade mode: safe|standard|fast (default: standard)
#   --skip-backup        Skip backup creation (faster, riskier)
#   --yes                Skip confirmations (auto-yes)
#   --help               Show this help message
#
# Exit Codes:
#   0 - Success
#   1 - General failure
#   2 - Validation failed
#   3 - User canceled
#
#===============================================================================

set -euo pipefail

#===============================================================================
# SETUP
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source libraries
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/versions.sh"
source "$SCRIPT_DIR/lib/upgrade-state.sh"
source "$SCRIPT_DIR/lib/upgrade-manager.sh"

# Default configuration
UPGRADE_CONFIG_FILE="$STACK_ROOT/config/upgrade.yaml"
DRY_RUN=false
FORCE_MODE=false
# shellcheck disable=SC2034  # P1-1: Reserved for future use
RESUME_MODE=false
# shellcheck disable=SC2034  # P1-1: Reserved for future use
ROLLBACK_MODE=false
AUTO_YES=false
# shellcheck disable=SC2034  # P1-1: Reserved for future use
SKIP_BACKUP=false
UPGRADE_MODE="standard"
OPERATION=""
TARGET_COMPONENT=""
TARGET_PHASE=""

#===============================================================================
# COMMAND LINE PARSING
#===============================================================================

show_help() {
    cat << EOF
Upgrade Orchestrator - Idempotent observability stack upgrades

Usage: $0 [OPTIONS]

Operations (mutually exclusive):
  --all                 Upgrade all components in all phases
  --component <name>    Upgrade specific component only
  --phase <number>      Upgrade all components in specific phase
  --resume             Resume from last failure point
  --rollback           Rollback last upgrade
  --status             Show current upgrade status
  --verify             Verify upgrade state consistency

Options:
  --mode <mode>        Upgrade mode: safe|standard|fast (default: standard)
                       - safe: Maximum safety, manual confirmations
                       - standard: Balanced (default)
                       - fast: Minimal pauses, for CI/CD
  --dry-run           Show what would be upgraded without changes
  --force             Force upgrade even if at target version
  --skip-backup       Skip backup creation (faster, riskier)
  --yes               Auto-confirm all prompts
  --help              Show this help message

Examples:
  # Dry run to see what would be upgraded
  $0 --all --dry-run

  # Upgrade all low-risk exporters (phase 1)
  $0 --phase 1

  # Upgrade specific component
  $0 --component node_exporter

  # Resume after failure
  $0 --resume

  # Force re-upgrade with safe mode
  $0 --component prometheus --force --mode safe

  # Show current status
  $0 --status

EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            OPERATION="all"
            shift
            ;;
        --component)
            OPERATION="component"
            TARGET_COMPONENT="$2"
            shift 2
            ;;
        --phase)
            OPERATION="phase"
            TARGET_PHASE="$2"
            shift 2
            ;;
        --resume)
            OPERATION="resume"
            # shellcheck disable=SC2034  # P1-1: Reserved for future use
            RESUME_MODE=true
            shift
            ;;
        --rollback)
            OPERATION="rollback"
            # shellcheck disable=SC2034  # P1-1: Reserved for future use
            ROLLBACK_MODE=true
            shift
            ;;
        --status)
            OPERATION="status"
            shift
            ;;
        --verify)
            OPERATION="verify"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_MODE=true
            shift
            ;;
        --mode)
            UPGRADE_MODE="$2"
            shift 2
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        --yes|-y)
            AUTO_YES=true
            shift
            ;;
        --help|-h)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate operation specified
if [[ -z "$OPERATION" ]]; then
    log_error "No operation specified"
    echo "Use --help for usage information"
    exit 1
fi

#===============================================================================
# DEPENDENCY CHECKS
#===============================================================================

# P0-2: Check for required external dependencies
# Verifies that jq, curl, and python3 are available before proceeding
check_dependencies() {
    local missing=()
    for cmd in jq curl python3; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_fatal "Missing required dependencies: ${missing[*]}"
    fi
}

#===============================================================================
# INITIALIZATION
#===============================================================================

log_info "Observability Stack Upgrade Orchestrator"
log_info "========================================"
log_info ""

# Check root permissions
check_root

# P0-2: Verify required dependencies are available
check_dependencies

# Validate config file exists
if [[ ! -f "$UPGRADE_CONFIG_FILE" ]]; then
    log_fatal "Upgrade configuration not found: $UPGRADE_CONFIG_FILE"
fi

# P0-6: Validate configuration file structure
if ! validate_upgrade_config "$UPGRADE_CONFIG_FILE"; then
    log_fatal "Invalid upgrade configuration"
fi

# Initialize state management
state_init

# Apply mode-specific settings
case "$UPGRADE_MODE" in
    safe)
        log_info "Mode: SAFE (maximum safety, manual confirmations)"
        AUTO_YES=false
        # shellcheck disable=SC2034  # P1-1: Reserved for future use
        SKIP_BACKUP=false
        ;;
    standard)
        log_info "Mode: STANDARD (balanced safety and automation)"
        ;;
    fast)
        log_info "Mode: FAST (minimal pauses, for CI/CD)"
        # Keep user settings for AUTO_YES and SKIP_BACKUP
        ;;
    dry_run)
        log_info "Mode: DRY-RUN (simulation only)"
        DRY_RUN=true
        ;;
    *)
        log_error "Invalid mode: $UPGRADE_MODE"
        exit 1
        ;;
esac

if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "DRY-RUN MODE: No actual changes will be made"
fi

#===============================================================================
# OPERATION HANDLERS
#===============================================================================

# Show current status
show_status() {
    log_info "Current Upgrade Status"
    log_info "======================"
    echo ""

    state_summary
    echo ""

    # Show upgrade history
    echo ""
    state_list_history 5
}

# Verify state consistency
verify_state() {
    log_info "Verifying upgrade state consistency..."
    if state_verify; then
        log_success "State verification passed"
        exit 0
    else
        log_error "State verification failed"
        exit 1
    fi
}

# Perform rollback
perform_rollback() {
    log_warn "=== ROLLBACK MODE ==="
    log_warn "This will attempt to rollback the last upgrade"
    echo ""

    if [[ "$AUTO_YES" != "true" ]]; then
        read -p "Are you sure you want to rollback? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Rollback canceled"
            exit 3
        fi
    fi

    # Get components from state
    local components
    components=$(state_read "components" | jq -r 'keys[]')

    if [[ -z "$components" ]]; then
        log_error "No components to rollback"
        exit 1
    fi

    local rollback_count=0
    local failed_count=0

    for component in $components; do
        local status
        status=$(state_get_component_status "$component")

        if [[ "$status" == "completed" ]]; then
            log_info "Rolling back: $component"

            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY-RUN] Would rollback $component"
                ((rollback_count++))
            else
                if rollback_component "$component"; then
                    ((rollback_count++))
                else
                    ((failed_count++))
                fi
            fi
        fi
    done

    echo ""
    log_info "Rollback Summary:"
    log_info "  Rolled back: $rollback_count"
    log_info "  Failed: $failed_count"

    if [[ $failed_count -eq 0 ]]; then
        log_success "Rollback completed successfully"
        exit 0
    else
        log_error "Rollback completed with failures"
        exit 1
    fi
}

# Confirm before destructive operations
confirm_operation() {
    local message="$1"

    if [[ "$AUTO_YES" == "true" ]]; then
        return 0
    fi

    echo ""
    read -p "$message [y/N] " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation canceled by user"
        exit 3
    fi
}

#===============================================================================
# UPGRADE EXECUTION
#===============================================================================

# Upgrade a single component
upgrade_single_component() {
    local component="$1"
    local force="${2:-$FORCE_MODE}"

    log_info ""
    log_info "=========================================="
    log_info "Component: $component"
    log_info "=========================================="

    # Get target version
    local target_version
    target_version=$(get_target_version "$component")

    if [[ -z "$target_version" ]]; then
        log_error "No target version defined for $component"
        return 1
    fi

    # Check if already upgraded (idempotency)
    if ! state_component_needs_upgrade "$component" && [[ "$force" != "true" ]]; then
        log_skip "Component $component already upgraded"
        return 0
    fi

    # Get risk level
    local risk_level
    risk_level=$(get_risk_level "$component")

    log_info "Target version: $target_version"
    log_info "Risk level: $risk_level"

    # Confirm for high-risk components
    if [[ "$risk_level" == "high" && "$AUTO_YES" != "true" ]]; then
        confirm_operation "Proceed with HIGH-RISK upgrade of $component?"
    fi

    # Dry-run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would upgrade $component to $target_version"
        return 0
    fi

    # Execute upgrade
    if upgrade_component "$component" "$target_version" "$force"; then
        log_success "Component $component upgraded successfully"
        return 0
    else
        log_error "Component $component upgrade failed"
        return 1
    fi
}

# Upgrade components in a phase
upgrade_phase() {
    local phase="$1"

    log_info ""
    log_info "=========================================="
    log_info "Phase $phase Upgrade"
    log_info "=========================================="

    # Get components for this phase
    local components
    components=$(get_components_by_phase "$phase")

    if [[ -z "$components" ]]; then
        log_warn "No components found for phase $phase"
        return 0
    fi

    log_info "Components in phase $phase:"
    while read -r component; do
        log_info "  - $component"
    done <<< "$components"

    confirm_operation "Proceed with phase $phase upgrade?"

    # Update state - P0-5: Add error handling for state updates
    if ! state_set_phase "$phase"; then
        log_error "Failed to update state for phase $phase"
        return 1
    fi

    local success_count=0
    local fail_count=0
    # shellcheck disable=SC2034  # P1-1: Reserved for future skip tracking
    local skip_count=0

    # Upgrade each component
    while read -r component; do
        if upgrade_single_component "$component"; then
            ((success_count++))
        else
            ((fail_count++))

            # Stop on first failure for high-risk phases
            if [[ $phase -eq 2 ]]; then
                log_error "Stopping phase $phase due to failure (high-risk phase)"
                break
            fi
        fi

        # Pause between components
        if [[ "$UPGRADE_MODE" == "safe" ]]; then
            sleep 30
        elif [[ "$UPGRADE_MODE" == "standard" ]]; then
            sleep 10
        fi
    done <<< "$components"

    echo ""
    log_info "Phase $phase Summary:"
    log_info "  Succeeded: $success_count"
    log_info "  Failed: $fail_count"

    if [[ $fail_count -eq 0 ]]; then
        log_success "Phase $phase completed successfully"
        return 0
    else
        log_error "Phase $phase completed with failures"
        return 1
    fi
}

# Upgrade all components
upgrade_all() {
    log_info "=== UPGRADING ALL COMPONENTS ==="
    echo ""

    # Show upgrade plan
    log_info "Upgrade Plan:"
    log_info "============="

    for phase in 1 2 3; do
        local components
        components=$(get_components_by_phase "$phase")

        if [[ -n "$components" ]]; then
            log_info ""
            log_info "Phase $phase:"
            while read -r component; do
                local target_version
                target_version=$(get_target_version "$component")
                local current_version
                current_version=$(detect_installed_version "$component" || echo "not_installed")

                log_info "  $component: $current_version -> $target_version"
            done <<< "$components"
        fi
    done

    echo ""
    confirm_operation "Proceed with full upgrade?"

    # Begin upgrade session
    if [[ "$DRY_RUN" != "true" ]]; then
        # P0-5: Add error handling for state updates
        if ! state_begin_upgrade "$UPGRADE_MODE"; then
            log_error "Failed to initialize upgrade state"
            exit 1
        fi
    fi

    local total_success=0
    local total_fail=0

    # Execute phases
    for phase in 1 2 3; do
        if upgrade_phase "$phase"; then
            ((total_success++))
        else
            ((total_fail++))

            if [[ $phase -eq 2 ]]; then
                log_error "Critical phase failed, stopping upgrade"
                break
            fi
        fi
    done

    echo ""
    log_info "Overall Summary:"
    log_info "  Phases succeeded: $total_success"
    log_info "  Phases failed: $total_fail"

    if [[ $total_fail -eq 0 ]]; then
        if [[ "$DRY_RUN" != "true" ]]; then
            # P0-5: Add error handling for state updates
            if ! state_complete_upgrade; then
                log_error "Failed to update completion state"
                exit 1
            fi
        fi
        log_success "=== ALL UPGRADES COMPLETED SUCCESSFULLY ==="
        exit 0
    else
        if [[ "$DRY_RUN" != "true" ]]; then
            # P0-5: Add error handling for state updates
            if ! state_fail_upgrade "Phase upgrades failed"; then
                log_error "Failed to update failure state"
            fi
        fi
        log_error "=== UPGRADE COMPLETED WITH FAILURES ==="
        exit 1
    fi
}

# Resume from failure
resume_upgrade() {
    log_info "=== RESUMING UPGRADE ==="

    if ! state_is_resumable; then
        log_error "No resumable upgrade found"
        log_info "Current status: $(state_get_status)"
        exit 1
    fi

    local upgrade_id
    upgrade_id=$(state_get_upgrade_id)
    log_info "Resuming upgrade: $upgrade_id"

    # Get current phase
    local current_phase
    current_phase=$(state_read "current_phase")

    if [[ -z "$current_phase" || "$current_phase" == "null" ]]; then
        current_phase=1
    fi

    log_info "Resuming from phase: $current_phase"

    # Get components
    local components
    components=$(state_read "components" | jq -r 'to_entries[] | select(.value.status == "pending" or .value.status == "failed" or .value.status == "in_progress") | .key')

    if [[ -z "$components" ]]; then
        log_info "All components already completed"
        # P0-5: Add error handling for state updates
        if ! state_complete_upgrade; then
            log_error "Failed to update completion state"
            exit 1
        fi
        exit 0
    fi

    log_info "Components to upgrade:"
    while read -r component; do
        log_info "  - $component"
    done <<< "$components"

    confirm_operation "Resume upgrade?"

    local success_count=0
    local fail_count=0

    while read -r component; do
        if upgrade_single_component "$component"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done <<< "$components"

    echo ""
    log_info "Resume Summary:"
    log_info "  Succeeded: $success_count"
    log_info "  Failed: $fail_count"

    if [[ $fail_count -eq 0 ]]; then
        # P0-5: Add error handling for state updates
        if ! state_complete_upgrade; then
            log_error "Failed to update completion state"
            exit 1
        fi
        log_success "Resume completed successfully"
        exit 0
    else
        # P0-5: Add error handling for state updates
        if ! state_fail_upgrade "Resume completed with failures"; then
            log_error "Failed to update failure state"
        fi
        log_error "Resume completed with failures"
        exit 1
    fi
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

case "$OPERATION" in
    status)
        show_status
        exit 0
        ;;

    verify)
        verify_state
        ;;

    rollback)
        perform_rollback
        ;;

    resume)
        resume_upgrade
        ;;

    component)
        if [[ -z "$TARGET_COMPONENT" ]]; then
            log_error "Component name required"
            exit 1
        fi

        if [[ "$DRY_RUN" != "true" ]]; then
            # P0-5: Add error handling for state updates
            if ! state_begin_upgrade "$UPGRADE_MODE"; then
                log_error "Failed to initialize upgrade state"
                exit 1
            fi
        fi

        if upgrade_single_component "$TARGET_COMPONENT" "$FORCE_MODE"; then
            if [[ "$DRY_RUN" != "true" ]]; then
                # P0-5: Add error handling for state updates
                if ! state_complete_upgrade; then
                    log_error "Failed to update completion state"
                    exit 1
                fi
            fi
            log_success "Component upgrade completed"
            exit 0
        else
            if [[ "$DRY_RUN" != "true" ]]; then
                # P0-5: Add error handling for state updates
                if ! state_fail_upgrade "Component upgrade failed"; then
                    log_error "Failed to update failure state"
                fi
            fi
            log_error "Component upgrade failed"
            exit 1
        fi
        ;;

    phase)
        if [[ -z "$TARGET_PHASE" ]]; then
            log_error "Phase number required"
            exit 1
        fi

        if [[ "$DRY_RUN" != "true" ]]; then
            # P0-5: Add error handling for state updates
            if ! state_begin_upgrade "$UPGRADE_MODE"; then
                log_error "Failed to initialize upgrade state"
                exit 1
            fi
        fi

        if upgrade_phase "$TARGET_PHASE"; then
            if [[ "$DRY_RUN" != "true" ]]; then
                # P0-5: Add error handling for state updates
                if ! state_complete_upgrade; then
                    log_error "Failed to update completion state"
                    exit 1
                fi
            fi
            log_success "Phase upgrade completed"
            exit 0
        else
            if [[ "$DRY_RUN" != "true" ]]; then
                # P0-5: Add error handling for state updates
                if ! state_fail_upgrade "Phase upgrade failed"; then
                    log_error "Failed to update failure state"
                fi
            fi
            log_error "Phase upgrade failed"
            exit 1
        fi
        ;;

    all)
        upgrade_all
        ;;

    *)
        log_error "Unknown operation: $OPERATION"
        exit 1
        ;;
esac
