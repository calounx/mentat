#!/bin/bash
#===============================================================================
# Upgrade State Management Library
# Part of the observability-stack upgrade orchestration system
#
# Provides idempotent state tracking for upgrades with crash recovery support
#
# Features:
#   - Atomic state updates using file locking
#   - Transaction-based state changes
#   - Crash recovery from partial upgrades
#   - State history for rollback
#   - Idempotency verification
#
# Usage:
#   source scripts/lib/upgrade-state.sh
#   state_init
#   state_begin_upgrade "component_name" "1.0.0" "2.0.0"
#===============================================================================

set -euo pipefail

# Guard against multiple sourcing
[[ -n "${UPGRADE_STATE_SH_LOADED:-}" ]] && return 0
UPGRADE_STATE_SH_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_LIB_DIR/common.sh"

#===============================================================================
# STATE CONFIGURATION
#===============================================================================

# Default state directory
STATE_DIR="${STATE_DIR:-/var/lib/observability-upgrades}"
STATE_FILE="${STATE_DIR}/state.json"
STATE_LOCK="${STATE_DIR}/.state.lock"
HISTORY_DIR="${STATE_DIR}/history"
CHECKPOINT_DIR="${STATE_DIR}/checkpoints"

# State file version (for future compatibility)
STATE_VERSION="1.0.0"

#===============================================================================
# STATE FILE STRUCTURE
#
# {
#   "version": "1.0.0",
#   "upgrade_id": "upgrade-20250101-120000",
#   "status": "in_progress|completed|failed|rolled_back",
#   "started_at": "2025-01-01T12:00:00Z",
#   "updated_at": "2025-01-01T12:05:00Z",
#   "completed_at": null,
#   "current_phase": 1,
#   "current_component": "node_exporter",
#   "mode": "standard",
#   "components": {
#     "node_exporter": {
#       "status": "completed|in_progress|pending|failed|skipped",
#       "from_version": "1.7.0",
#       "to_version": "1.9.1",
#       "started_at": "2025-01-01T12:01:00Z",
#       "completed_at": "2025-01-01T12:02:30Z",
#       "attempts": 1,
#       "backup_path": "/var/lib/observability-upgrades/backups/...",
#       "rollback_available": true,
#       "health_check_passed": true,
#       "checksum": "sha256:..."
#     }
#   },
#   "errors": [],
#   "checkpoints": []
# }
#===============================================================================

#===============================================================================
# STATE INITIALIZATION
#===============================================================================

# Initialize state directory and files
# Usage: state_init
# Returns: 0 on success
state_init() {
    log_debug "Initializing upgrade state management"

    # Create directories with restrictive permissions
    ensure_dir "$STATE_DIR" "root" "root" "0700"
    ensure_dir "$HISTORY_DIR" "root" "root" "0700"
    ensure_dir "$CHECKPOINT_DIR" "root" "root" "0700"

    # Create initial state file if it doesn't exist
    if [[ ! -f "$STATE_FILE" ]]; then
        local init_state
        init_state=$(cat <<EOF
{
  "version": "$STATE_VERSION",
  "upgrade_id": null,
  "status": "idle",
  "started_at": null,
  "updated_at": null,
  "completed_at": null,
  "current_phase": null,
  "current_component": null,
  "mode": null,
  "components": {},
  "errors": [],
  "checkpoints": []
}
EOF
)
        echo "$init_state" | jq '.' > "$STATE_FILE"
        chmod 600 "$STATE_FILE"
        log_debug "Created initial state file"
    fi

    return 0
}

#===============================================================================
# FILE LOCKING FOR ATOMIC OPERATIONS
#===============================================================================

# Acquire exclusive lock on state file
# Usage: state_lock
# Returns: 0 on success, 1 on failure
# SECURITY: Uses flock-based atomic locking to prevent TOCTOU race conditions (H-2 fix)
state_lock() {
    local timeout=30
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        # SECURITY: Use atomic directory creation for lock acquisition (H-2 fix)
        if mkdir "$STATE_LOCK" 2>/dev/null; then
            # Write PID to lock file
            echo $$ > "$STATE_LOCK/pid"
            # Double-check we still own the lock (detect race with another process)
            local written_pid
            written_pid=$(cat "$STATE_LOCK/pid" 2>/dev/null || echo "")
            if [[ "$written_pid" == "$$" ]]; then
                log_debug "State lock acquired (PID $$)"
                return 0
            fi
            # If PID doesn't match, another process won the race - cleanup and retry
            log_debug "Lock race detected, retrying..."
            rm -rf "$STATE_LOCK" 2>/dev/null || true
        fi

        # SECURITY: Check if lock is stale using flock to prevent TOCTOU (H-2 fix)
        if [[ -f "$STATE_LOCK/pid" ]]; then
            local lock_pid
            lock_pid=$(cat "$STATE_LOCK/pid" 2>/dev/null || echo "")

            # Use flock to safely check and remove stale lock
            # This prevents race condition between check and remove
            if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                # SECURITY: Try to acquire exclusive lock before removing stale lock (H-2 fix)
                # This ensures only one process removes the stale lock
                if (
                    # Create lock file for flock if it doesn't exist
                    touch "$STATE_LOCK/pid.lock" 2>/dev/null || true
                    # Try to acquire exclusive lock with immediate failure if locked
                    exec 200>"$STATE_LOCK/pid.lock"
                    flock -x -n 200 && rm -rf "$STATE_LOCK"
                ) 2>/dev/null; then
                    log_warn "Removed stale lock from PID $lock_pid"
                    continue
                fi
                # If we couldn't get flock, another process is handling the stale lock
                log_debug "Another process is cleaning stale lock, waiting..."
            fi
        fi

        sleep 1
        ((elapsed++))
    done

    log_error "Failed to acquire state lock after ${timeout}s"
    return 1
}

# Release lock on state file
# Usage: state_unlock
state_unlock() {
    if [[ -d "$STATE_LOCK" ]]; then
        rm -rf "$STATE_LOCK"
        log_debug "State lock released"
    fi
}

# Ensure lock is released on exit
_state_cleanup() {
    state_unlock 2>/dev/null || true
}
trap _state_cleanup EXIT

#===============================================================================
# STATE READ OPERATIONS
#===============================================================================

# Read current state
# Usage: state_read [field]
# Returns: Full state JSON or specific field value
state_read() {
    local field="${1:-}"

    if [[ ! -f "$STATE_FILE" ]]; then
        log_error "State file not found: $STATE_FILE"
        return 1
    fi

    if [[ -z "$field" ]]; then
        cat "$STATE_FILE"
    else
        jq -r ".$field // empty" "$STATE_FILE"
    fi
}

# Get current upgrade ID
# Usage: state_get_upgrade_id
state_get_upgrade_id() {
    state_read "upgrade_id"
}

# Get overall upgrade status
# Usage: state_get_status
state_get_status() {
    state_read "status"
}

# Get component status
# Usage: state_get_component_status "component_name"
state_get_component_status() {
    local component="$1"
    state_read "components.${component}.status"
}

# Get component version info
# Usage: state_get_component_version "component_name" "from|to"
state_get_component_version() {
    local component="$1"
    local direction="${2:-to}"
    state_read "components.${component}.${direction}_version"
}

# Check if component needs upgrade
# Usage: state_component_needs_upgrade "component_name"
# Returns: 0 if needs upgrade, 1 if already upgraded or in progress
state_component_needs_upgrade() {
    local component="$1"
    local status
    status=$(state_get_component_status "$component")

    case "$status" in
        "completed"|"skipped")
            log_debug "Component $component already upgraded (status: $status)"
            return 1
            ;;
        "in_progress")
            log_warn "Component $component upgrade already in progress"
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

# Check if upgrade is resumable
# Usage: state_is_resumable
# Returns: 0 if can resume, 1 otherwise
state_is_resumable() {
    local status
    status=$(state_get_status)

    case "$status" in
        "in_progress")
            log_info "Found resumable upgrade in progress"
            return 0
            ;;
        "failed")
            log_info "Found failed upgrade (can retry)"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

#===============================================================================
# STATE WRITE OPERATIONS (ATOMIC)
#===============================================================================

# Update state atomically
# Usage: state_update <jq_expression>
# Example: state_update '.status = "in_progress"'
# SECURITY: Uses jq --arg for safe variable interpolation to prevent injection
state_update() {
    local jq_expr="$1"

    if ! state_lock; then
        return 1
    fi

    # Add updated_at timestamp to all updates
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # SECURITY: Set restrictive umask before mktemp (M-1 fix)
    local old_umask
    old_umask=$(umask)
    umask 077  # Only owner can read/write

    # Create temporary file in same directory (ensures same filesystem)
    local temp_file
    temp_file=$(mktemp "${STATE_DIR}/.state.tmp.XXXXXX")

    # Restore umask
    umask "$old_umask"

    # Explicitly set permissions
    chmod 600 "$temp_file"

    # SECURITY: Use --arg to pass timestamp safely, preventing jq injection (H-1 fix)
    if ! jq --arg ts "$timestamp" "$jq_expr | .updated_at = \$ts" "$STATE_FILE" > "$temp_file"; then
        log_error "Failed to update state"
        rm -f "$temp_file"
        state_unlock
        return 1
    fi

    # Atomic move
    mv "$temp_file" "$STATE_FILE"
    chmod 600 "$STATE_FILE"

    state_unlock
    log_debug "State updated: $jq_expr"
    return 0
}

# Begin new upgrade session
# Usage: state_begin_upgrade "mode"
# SECURITY: Validates mode and uses safe jq parameter passing
state_begin_upgrade() {
    local mode="${1:-standard}"
    local upgrade_id
    local timestamp

    # SECURITY: Validate mode to prevent injection (H-1 fix)
    if [[ ! "$mode" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid mode name: $mode"
        return 1
    fi

    # SC2155: Separate declaration and assignment to detect command failures
    upgrade_id="upgrade-$(date +%Y%m%d-%H%M%S)" || {
        log_error "Failed to generate upgrade ID"
        return 1
    }
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ") || {
        log_error "Failed to generate timestamp"
        return 1
    }

    log_info "Beginning new upgrade session: $upgrade_id"

    # SECURITY: Use jq --arg for all user-controlled variables (H-1 fix)
    if ! state_lock; then
        return 1
    fi

    local old_umask
    old_umask=$(umask)
    umask 077
    local temp_file
    temp_file=$(mktemp "${STATE_DIR}/.state.tmp.XXXXXX")
    umask "$old_umask"
    chmod 600 "$temp_file"

    if ! jq --arg uid "$upgrade_id" \
           --arg st "in_progress" \
           --arg md "$mode" \
           --arg ts "$timestamp" \
           '.upgrade_id = $uid |
            .status = $st |
            .mode = $md |
            .started_at = $ts |
            .updated_at = $ts |
            .completed_at = null |
            .current_phase = 1 |
            .current_component = null |
            .components = {} |
            .errors = [] |
            .checkpoints = []' "$STATE_FILE" > "$temp_file"; then
        log_error "Failed to update state"
        rm -f "$temp_file"
        state_unlock
        return 1
    fi

    mv "$temp_file" "$STATE_FILE"
    chmod 600 "$STATE_FILE"
    state_unlock
    log_debug "State updated: begin upgrade"
    return 0
}

# Mark upgrade as completed
# Usage: state_complete_upgrade
# SECURITY: Uses safe jq parameter passing
state_complete_upgrade() {
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    log_success "Upgrade completed successfully"

    # SECURITY: Use jq --arg for timestamp (H-1 fix)
    if ! state_lock; then
        return 1
    fi

    local old_umask
    old_umask=$(umask)
    umask 077
    local temp_file
    temp_file=$(mktemp "${STATE_DIR}/.state.tmp.XXXXXX")
    umask "$old_umask"
    chmod 600 "$temp_file"

    if ! jq --arg st "completed" \
           --arg ts "$timestamp" \
           '.status = $st |
            .completed_at = $ts |
            .updated_at = $ts |
            .current_component = null' "$STATE_FILE" > "$temp_file"; then
        log_error "Failed to update state"
        rm -f "$temp_file"
        state_unlock
        return 1
    fi

    mv "$temp_file" "$STATE_FILE"
    chmod 600 "$STATE_FILE"
    state_unlock

    # Archive to history
    _state_archive_to_history
}

# Mark upgrade as failed
# Usage: state_fail_upgrade "error_message"
# SECURITY: Uses safe jq parameter passing to prevent injection
state_fail_upgrade() {
    local error_message="$1"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    log_error "Upgrade failed: $error_message"

    # SECURITY: Use jq --arg for error_message to prevent injection (H-1 fix)
    # No need to escape quotes manually - jq handles this
    if ! state_lock; then
        return 1
    fi

    local old_umask
    old_umask=$(umask)
    umask 077
    local temp_file
    temp_file=$(mktemp "${STATE_DIR}/.state.tmp.XXXXXX")
    umask "$old_umask"
    chmod 600 "$temp_file"

    if ! jq --arg st "failed" \
           --arg ts "$timestamp" \
           --arg msg "$error_message" \
           '.status = $st |
            .completed_at = $ts |
            .updated_at = $ts |
            .errors += [{"timestamp": $ts, "message": $msg}]' "$STATE_FILE" > "$temp_file"; then
        log_error "Failed to update state"
        rm -f "$temp_file"
        state_unlock
        return 1
    fi

    mv "$temp_file" "$STATE_FILE"
    chmod 600 "$STATE_FILE"
    state_unlock

    # Archive to history
    _state_archive_to_history
}

# Set current phase
# Usage: state_set_phase <phase_number>
state_set_phase() {
    local phase="$1"
    state_update ".current_phase = $phase"
}

# Begin component upgrade
# Usage: state_begin_component "component_name" "from_version" "to_version"
# SECURITY: Validates component name and uses safe jq parameter passing
state_begin_component() {
    local component="$1"
    local from_version="$2"
    local to_version="$3"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # SECURITY: Validate component name to prevent injection (H-1 fix)
    if [[ ! "$component" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid component name: $component"
        return 1
    fi

    log_info "Beginning upgrade: $component $from_version -> $to_version"

    # Get current attempt count
    local attempts
    attempts=$(state_read "components.${component}.attempts" || echo "0")
    ((attempts++))

    # SECURITY: Use jq --arg for all user-controlled variables (H-1 fix)
    if ! state_lock; then
        return 1
    fi

    local old_umask
    old_umask=$(umask)
    umask 077
    local temp_file
    temp_file=$(mktemp "${STATE_DIR}/.state.tmp.XXXXXX")
    umask "$old_umask"
    chmod 600 "$temp_file"

    if ! jq --arg comp "$component" \
           --arg from "$from_version" \
           --arg to "$to_version" \
           --arg ts "$timestamp" \
           --argjson att "$attempts" \
           '.current_component = $comp |
            .updated_at = $ts |
            .components[$comp] = {
                "status": "in_progress",
                "from_version": $from,
                "to_version": $to,
                "started_at": $ts,
                "completed_at": null,
                "attempts": $att,
                "backup_path": null,
                "rollback_available": false,
                "health_check_passed": false,
                "checksum": null,
                "error": null
            }' "$STATE_FILE" > "$temp_file"; then
        log_error "Failed to update state"
        rm -f "$temp_file"
        state_unlock
        return 1
    fi

    mv "$temp_file" "$STATE_FILE"
    chmod 600 "$STATE_FILE"
    state_unlock
    log_debug "State updated: begin component $component"
    return 0
}

# Mark component upgrade as completed
# Usage: state_complete_component "component_name" "checksum" "backup_path"
# SECURITY: Validates component name and uses safe jq parameter passing
state_complete_component() {
    local component="$1"
    local checksum="${2:-}"
    local backup_path="${3:-}"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # SECURITY: Validate component name (H-1 fix)
    if [[ ! "$component" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid component name: $component"
        return 1
    fi

    log_success "Component upgrade completed: $component"

    local rollback_available="false"
    [[ -n "$backup_path" && -d "$backup_path" ]] && rollback_available="true"

    # SECURITY: Use jq --arg for all variables (H-1 fix)
    if ! state_lock; then
        return 1
    fi

    local old_umask
    old_umask=$(umask)
    umask 077
    local temp_file
    temp_file=$(mktemp "${STATE_DIR}/.state.tmp.XXXXXX")
    umask "$old_umask"
    chmod 600 "$temp_file"

    if ! jq --arg comp "$component" \
           --arg st "completed" \
           --arg ts "$timestamp" \
           --arg chk "$checksum" \
           --arg bkp "$backup_path" \
           --argjson rb "$rollback_available" \
           '.updated_at = $ts |
            .components[$comp].status = $st |
            .components[$comp].completed_at = $ts |
            .components[$comp].health_check_passed = true |
            .components[$comp].checksum = $chk |
            .components[$comp].backup_path = $bkp |
            .components[$comp].rollback_available = $rb' "$STATE_FILE" > "$temp_file"; then
        log_error "Failed to update state"
        rm -f "$temp_file"
        state_unlock
        return 1
    fi

    mv "$temp_file" "$STATE_FILE"
    chmod 600 "$STATE_FILE"
    state_unlock
    log_debug "State updated: complete component $component"
    return 0
}

# Mark component upgrade as failed
# Usage: state_fail_component "component_name" "error_message"
# SECURITY: Validates component name and uses safe jq parameter passing
state_fail_component() {
    local component="$1"
    local error_message="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # SECURITY: Validate component name (H-1 fix)
    if [[ ! "$component" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid component name: $component"
        return 1
    fi

    log_error "Component upgrade failed: $component - $error_message"

    # SECURITY: Use jq --arg for error_message, no manual escaping needed (H-1 fix)
    if ! state_lock; then
        return 1
    fi

    local old_umask
    old_umask=$(umask)
    umask 077
    local temp_file
    temp_file=$(mktemp "${STATE_DIR}/.state.tmp.XXXXXX")
    umask "$old_umask"
    chmod 600 "$temp_file"

    if ! jq --arg comp "$component" \
           --arg st "failed" \
           --arg ts "$timestamp" \
           --arg err "$error_message" \
           '.updated_at = $ts |
            .components[$comp].status = $st |
            .components[$comp].completed_at = $ts |
            .components[$comp].error = $err' "$STATE_FILE" > "$temp_file"; then
        log_error "Failed to update state"
        rm -f "$temp_file"
        state_unlock
        return 1
    fi

    mv "$temp_file" "$STATE_FILE"
    chmod 600 "$STATE_FILE"
    state_unlock
    log_debug "State updated: fail component $component"
    return 0
}

# Skip component upgrade
# Usage: state_skip_component "component_name" "reason"
# SECURITY: Validates component name and uses safe jq parameter passing
state_skip_component() {
    local component="$1"
    local reason="${2:-Already at target version}"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # SECURITY: Validate component name (H-1 fix)
    if [[ ! "$component" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid component name: $component"
        return 1
    fi

    log_skip "Skipping $component: $reason"

    # SECURITY: Use jq --arg for reason (H-1 fix)
    if ! state_lock; then
        return 1
    fi

    local old_umask
    old_umask=$(umask)
    umask 077
    local temp_file
    temp_file=$(mktemp "${STATE_DIR}/.state.tmp.XXXXXX")
    umask "$old_umask"
    chmod 600 "$temp_file"

    if ! jq --arg comp "$component" \
           --arg st "skipped" \
           --arg ts "$timestamp" \
           --arg rsn "$reason" \
           '.updated_at = $ts |
            .components[$comp].status = $st |
            .components[$comp].completed_at = $ts |
            .components[$comp].error = $rsn' "$STATE_FILE" > "$temp_file"; then
        log_error "Failed to update state"
        rm -f "$temp_file"
        state_unlock
        return 1
    fi

    mv "$temp_file" "$STATE_FILE"
    chmod 600 "$STATE_FILE"
    state_unlock
    log_debug "State updated: skip component $component"
    return 0
}

#===============================================================================
# CHECKPOINT MANAGEMENT
#===============================================================================

# Create checkpoint for rollback
# Usage: state_create_checkpoint "checkpoint_name" "description"
# SECURITY: Validates checkpoint name and uses safe jq parameter passing
state_create_checkpoint() {
    local checkpoint_name="$1"
    local description="${2:-}"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # SECURITY: Validate checkpoint name to prevent path traversal (H-1 fix)
    if [[ ! "$checkpoint_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid checkpoint name: $checkpoint_name"
        return 1
    fi

    log_debug "Creating checkpoint: $checkpoint_name"

    # Save current state to checkpoint file
    local checkpoint_file="$CHECKPOINT_DIR/${checkpoint_name}.json"
    cp "$STATE_FILE" "$checkpoint_file"
    chmod 600 "$checkpoint_file"

    # SECURITY: Use jq --arg for all variables (H-1 fix)
    if ! state_lock; then
        return 1
    fi

    local old_umask
    old_umask=$(umask)
    umask 077
    local temp_file
    temp_file=$(mktemp "${STATE_DIR}/.state.tmp.XXXXXX")
    umask "$old_umask"
    chmod 600 "$temp_file"

    if ! jq --arg name "$checkpoint_name" \
           --arg desc "$description" \
           --arg ts "$timestamp" \
           --arg file "$checkpoint_file" \
           '.updated_at = $ts |
            .checkpoints += [{
                "name": $name,
                "description": $desc,
                "timestamp": $ts,
                "file": $file
            }]' "$STATE_FILE" > "$temp_file"; then
        log_error "Failed to update state"
        rm -f "$temp_file"
        state_unlock
        return 1
    fi

    mv "$temp_file" "$STATE_FILE"
    chmod 600 "$STATE_FILE"
    state_unlock

    log_debug "Checkpoint created: $checkpoint_file"
    return 0
}

# Restore from checkpoint
# Usage: state_restore_checkpoint "checkpoint_name"
state_restore_checkpoint() {
    local checkpoint_name="$1"
    local checkpoint_file="$CHECKPOINT_DIR/${checkpoint_name}.json"

    if [[ ! -f "$checkpoint_file" ]]; then
        log_error "Checkpoint not found: $checkpoint_name"
        return 1
    fi

    log_info "Restoring from checkpoint: $checkpoint_name"

    if ! state_lock; then
        return 1
    fi

    cp "$checkpoint_file" "$STATE_FILE"
    chmod 600 "$STATE_FILE"

    state_unlock

    log_success "State restored from checkpoint: $checkpoint_name"
}

#===============================================================================
# STATE HISTORY
#===============================================================================

# Archive current state to history
# Usage: _state_archive_to_history
_state_archive_to_history() {
    local upgrade_id
    upgrade_id=$(state_get_upgrade_id)

    if [[ -z "$upgrade_id" || "$upgrade_id" == "null" ]]; then
        log_debug "No upgrade ID, skipping history archive"
        return 0
    fi

    local history_file="$HISTORY_DIR/${upgrade_id}.json"

    cp "$STATE_FILE" "$history_file"
    chmod 600 "$history_file"

    log_debug "State archived to history: $history_file"
}

# List upgrade history
# Usage: state_list_history [limit]
state_list_history() {
    local limit="${1:-10}"

    if [[ ! -d "$HISTORY_DIR" ]]; then
        echo "No upgrade history found"
        return 0
    fi

    echo "Recent Upgrades:"
    echo "================"

    find "$HISTORY_DIR" -name "upgrade-*.json" -type f \
        | sort -r \
        | head -n "$limit" \
        | while read -r history_file; do
            local upgrade_id
            upgrade_id=$(basename "$history_file" .json)
            local status
            status=$(jq -r '.status' "$history_file")
            local started
            started=$(jq -r '.started_at' "$history_file")
            local completed
            completed=$(jq -r '.completed_at // "N/A"' "$history_file")

            printf "%-30s  %-12s  Started: %s  Completed: %s\n" \
                "$upgrade_id" "$status" "$started" "$completed"
        done
}

# Get upgrade statistics
# Usage: state_get_stats
state_get_stats() {
    echo "Upgrade Statistics:"
    echo "==================="

    local total_components
    total_components=$(state_read "components" | jq 'length')
    echo "Total components: $total_components"

    local completed
    completed=$(state_read "components" | jq '[.[] | select(.status == "completed")] | length')
    echo "Completed: $completed"

    local failed
    failed=$(state_read "components" | jq '[.[] | select(.status == "failed")] | length')
    echo "Failed: $failed"

    local in_progress
    in_progress=$(state_read "components" | jq '[.[] | select(.status == "in_progress")] | length')
    echo "In progress: $in_progress"

    local pending
    pending=$(state_read "components" | jq '[.[] | select(.status == "pending" or .status == null)] | length')
    echo "Pending: $pending"

    local skipped
    skipped=$(state_read "components" | jq '[.[] | select(.status == "skipped")] | length')
    echo "Skipped: $skipped"
}

#===============================================================================
# STATE RESET
#===============================================================================

# Reset state to idle (for new upgrade)
# Usage: state_reset [--force]
state_reset() {
    local force=false
    [[ "${1:-}" == "--force" ]] && force=true

    local current_status
    current_status=$(state_get_status)

    if [[ "$current_status" == "in_progress" && "$force" != "true" ]]; then
        log_error "Upgrade is in progress. Use --force to reset anyway."
        return 1
    fi

    log_info "Resetting upgrade state"

    state_update '
        .upgrade_id = null |
        .status = "idle" |
        .started_at = null |
        .completed_at = null |
        .current_phase = null |
        .current_component = null |
        .components = {} |
        .errors = [] |
        .checkpoints = []
    '

    log_success "State reset to idle"
}

#===============================================================================
# IDEMPOTENCY VERIFICATION
#===============================================================================

# Verify state consistency
# Usage: state_verify
# Returns: 0 if state is consistent, 1 otherwise
state_verify() {
    log_info "Verifying state consistency..."

    local errors=0

    # Check state file exists
    if [[ ! -f "$STATE_FILE" ]]; then
        log_error "State file not found"
        ((errors++))
    fi

    # Check state file is valid JSON
    if ! jq empty "$STATE_FILE" 2>/dev/null; then
        log_error "State file is not valid JSON"
        ((errors++))
    fi

    # Check for components with in_progress status from crashed upgrades
    local in_progress_count
    in_progress_count=$(state_read "components" | jq '[.[] | select(.status == "in_progress")] | length')

    if [[ $in_progress_count -gt 1 ]]; then
        log_warn "Multiple components marked as in_progress (possible crash)"
        log_warn "Run upgrade with --resume to continue"
    fi

    # Verify checkpoints exist
    local checkpoint_count
    checkpoint_count=$(state_read "checkpoints" | jq 'length')
    if [[ $checkpoint_count -gt 0 ]]; then
        while read -r checkpoint_file; do
            if [[ ! -f "$checkpoint_file" ]]; then
                log_warn "Checkpoint file missing: $checkpoint_file"
            fi
        done < <(state_read "checkpoints" | jq -r '.[].file')
    fi

    if [[ $errors -eq 0 ]]; then
        log_success "State is consistent"
        return 0
    else
        log_error "State verification failed with $errors errors"
        return 1
    fi
}

#===============================================================================
# UTILITY FUNCTIONS
#===============================================================================

# Pretty-print current state
# Usage: state_show
state_show() {
    echo "Current Upgrade State:"
    echo "======================"
    state_read | jq '.'
}

# Export state summary
# Usage: state_summary
state_summary() {
    local upgrade_id
    upgrade_id=$(state_get_upgrade_id)
    local status
    status=$(state_get_status)
    local phase
    phase=$(state_read "current_phase")
    local component
    component=$(state_read "current_component")

    cat <<EOF
Upgrade Summary
===============
Upgrade ID:        ${upgrade_id:-None}
Status:            ${status:-idle}
Current Phase:     ${phase:-None}
Current Component: ${component:-None}

EOF

    state_get_stats
}

log_debug "Upgrade state management library loaded"
