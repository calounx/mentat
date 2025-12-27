#!/usr/bin/env bash
#
# Upgrade State Machine
#
# Tracks upgrade progress with full state persistence, idempotency,
# crash recovery, and concurrency safety.
#
# State Flow:
#   IDLE → PLANNING → BACKING_UP → UPGRADING → VALIDATING → COMPLETED
#                                      ↓
#                                ROLLING_BACK → ROLLED_BACK
#                                      ↓
#                                   FAILED
#
# Author: Observability Stack Team
# License: MIT

set -euo pipefail

# State directories (can be overridden via environment for testing)
: "${UPGRADE_STATE_DIR:=/var/lib/observability-upgrades}"
: "${UPGRADE_HISTORY_DIR:=${UPGRADE_STATE_DIR}/history}"
: "${UPGRADE_BACKUPS_DIR:=${UPGRADE_STATE_DIR}/backups}"
: "${UPGRADE_STATE_FILE:=${UPGRADE_STATE_DIR}/state.json}"
: "${UPGRADE_LOCK_FILE:=${UPGRADE_STATE_DIR}/upgrade.lock}"
: "${UPGRADE_TEMP_DIR:=${UPGRADE_STATE_DIR}/tmp}"

# State constants (declare as readonly only once to allow re-sourcing)
if [[ -z "${STATE_IDLE:-}" ]]; then
    readonly STATE_IDLE="IDLE"
    readonly STATE_PLANNING="PLANNING"
    readonly STATE_BACKING_UP="BACKING_UP"
    readonly STATE_UPGRADING="UPGRADING"
    readonly STATE_VALIDATING="VALIDATING"
    readonly STATE_COMPLETED="COMPLETED"
    readonly STATE_ROLLING_BACK="ROLLING_BACK"
    readonly STATE_ROLLED_BACK="ROLLED_BACK"
    readonly STATE_FAILED="FAILED"

    # Component states
    readonly COMP_STATE_PENDING="PENDING"
    readonly COMP_STATE_IN_PROGRESS="IN_PROGRESS"
    readonly COMP_STATE_COMPLETED="COMPLETED"
    readonly COMP_STATE_FAILED="FAILED"
    readonly COMP_STATE_SKIPPED="SKIPPED"
    readonly COMP_STATE_UPGRADING="UPGRADING"

    # Lock configuration
    readonly LOCK_TIMEOUT=14400  # 4 hours in seconds
    readonly LOCK_CHECK_INTERVAL=1
fi

# Valid state transitions
declare -A VALID_TRANSITIONS=(
    ["${STATE_IDLE},${STATE_PLANNING}"]="1"
    ["${STATE_PLANNING},${STATE_BACKING_UP}"]="1"
    ["${STATE_BACKING_UP},${STATE_UPGRADING}"]="1"
    ["${STATE_UPGRADING},${STATE_VALIDATING}"]="1"
    ["${STATE_VALIDATING},${STATE_COMPLETED}"]="1"
    ["${STATE_UPGRADING},${STATE_ROLLING_BACK}"]="1"
    ["${STATE_ROLLING_BACK},${STATE_ROLLED_BACK}"]="1"
    ["${STATE_UPGRADING},${STATE_FAILED}"]="1"
    ["${STATE_FAILED},${STATE_IDLE}"]="1"
    ["${STATE_COMPLETED},${STATE_IDLE}"]="1"
    ["${STATE_ROLLED_BACK},${STATE_IDLE}"]="1"
)

# Resumable states
declare -A RESUMABLE_STATES=(
    ["${STATE_PLANNING}"]="1"
    ["${STATE_BACKING_UP}"]="1"
    ["${STATE_UPGRADING}"]="1"
    ["${STATE_VALIDATING}"]="1"
    ["${STATE_ROLLING_BACK}"]="1"
)

#######################################
# Initialize upgrade state directories
# Globals:
#   UPGRADE_STATE_DIR
#   UPGRADE_HISTORY_DIR
#   UPGRADE_BACKUPS_DIR
#   UPGRADE_TEMP_DIR
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
upgrade_state_init_dirs() {
    local dirs=(
        "$UPGRADE_STATE_DIR"
        "$UPGRADE_HISTORY_DIR"
        "$UPGRADE_BACKUPS_DIR"
        "$UPGRADE_TEMP_DIR"
    )

    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            if ! mkdir -p "$dir" 2>/dev/null; then
                echo "ERROR: Failed to create directory: $dir" >&2
                return 1
            fi
            chmod 700 "$dir"
        fi
    done

    return 0
}

#######################################
# Get current timestamp in ISO 8601 format
# Arguments:
#   None
# Outputs:
#   ISO 8601 timestamp
#######################################
upgrade_get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

#######################################
# Generate unique upgrade ID
# Arguments:
#   None
# Outputs:
#   Upgrade ID in format: upgrade-YYYYMMDD-HHMMSS
#######################################
upgrade_generate_id() {
    echo "upgrade-$(date +%Y%m%d-%H%M%S)"
}

#######################################
# Atomically write state file
# Arguments:
#   $1 - JSON content to write
# Returns:
#   0 on success, 1 on failure
#######################################
upgrade_state_write_atomic() {
    local content="$1"
    local temp_file

    temp_file="${UPGRADE_TEMP_DIR}/state-$$.json"

    if ! echo "$content" | jq '.' > "$temp_file" 2>/dev/null; then
        echo "ERROR: Invalid JSON in state write" >&2
        rm -f "$temp_file"
        return 1
    fi

    if ! mv -f "$temp_file" "$UPGRADE_STATE_FILE"; then
        echo "ERROR: Failed to write state file" >&2
        rm -f "$temp_file"
        return 1
    fi

    chmod 600 "$UPGRADE_STATE_FILE"
    return 0
}

#######################################
# Initialize new upgrade state
# Arguments:
#   $1 - (Optional) Upgrade ID, auto-generated if not provided
# Returns:
#   0 on success, 1 on failure
# Outputs:
#   Upgrade ID
#######################################
upgrade_state_init() {
    local upgrade_id="${1:-$(upgrade_generate_id)}"
    local timestamp

    timestamp=$(upgrade_get_timestamp)

    if ! upgrade_state_init_dirs; then
        return 1
    fi

    local state_json
    state_json=$(jq -n \
        --arg id "$upgrade_id" \
        --arg state "$STATE_IDLE" \
        --arg started "$timestamp" \
        --arg updated "$timestamp" \
        '{
            upgrade_id: $id,
            current_state: $state,
            started_at: $started,
            updated_at: $updated,
            current_phase: null,
            current_component: null,
            phases: {},
            rollback_available: false,
            can_resume: true,
            metadata: {
                hostname: env.HOSTNAME,
                user: env.USER,
                pid: env.PPID
            }
        }')

    if ! upgrade_state_write_atomic "$state_json"; then
        return 1
    fi

    echo "$upgrade_id"
    return 0
}

#######################################
# Load current upgrade state
# Globals:
#   UPGRADE_STATE_FILE
# Arguments:
#   None
# Outputs:
#   JSON state content
# Returns:
#   0 on success, 1 if no state exists
#######################################
upgrade_state_load() {
    if [[ ! -f "$UPGRADE_STATE_FILE" ]]; then
        echo "ERROR: No state file exists" >&2
        return 1
    fi

    if ! jq '.' "$UPGRADE_STATE_FILE" 2>/dev/null; then
        echo "ERROR: Corrupted state file" >&2
        return 1
    fi

    return 0
}

#######################################
# Save/update state with changes
# Arguments:
#   $1 - JSON content to save
# Returns:
#   0 on success, 1 on failure
#######################################
upgrade_state_save() {
    local state_json="$1"
    local timestamp

    timestamp=$(upgrade_get_timestamp)

    # Update the updated_at timestamp
    state_json=$(echo "$state_json" | jq --arg ts "$timestamp" '.updated_at = $ts')

    if ! upgrade_state_write_atomic "$state_json"; then
        return 1
    fi

    return 0
}

#######################################
# Get current state
# Arguments:
#   None
# Outputs:
#   Current state name
# Returns:
#   0 on success, 1 on failure
#######################################
upgrade_state_get_current() {
    local state

    if ! state=$(upgrade_state_load); then
        return 1
    fi

    echo "$state" | jq -r '.current_state'
}

#######################################
# Validate state transition
# Arguments:
#   $1 - Current state
#   $2 - New state
# Returns:
#   0 if valid transition, 1 if invalid
#######################################
upgrade_state_validate_transition() {
    local current="$1"
    local new="$2"
    local key="${current},${new}"

    if [[ -n "${VALID_TRANSITIONS[$key]:-}" ]]; then
        return 0
    fi

    echo "ERROR: Invalid state transition: $current → $new" >&2
    return 1
}

#######################################
# Set upgrade state
# Arguments:
#   $1 - New state
# Returns:
#   0 on success, 1 on failure
#######################################
upgrade_state_set() {
    local new_state="$1"
    local current_state
    local state_json

    if ! state_json=$(upgrade_state_load); then
        return 1
    fi

    current_state=$(echo "$state_json" | jq -r '.current_state')

    # Allow same state (idempotent)
    if [[ "$current_state" == "$new_state" ]]; then
        return 0
    fi

    if ! upgrade_state_validate_transition "$current_state" "$new_state"; then
        return 1
    fi

    state_json=$(echo "$state_json" | jq --arg state "$new_state" '.current_state = $state')

    if ! upgrade_state_save "$state_json"; then
        return 1
    fi

    return 0
}

#######################################
# Start a new phase
# Arguments:
#   $1 - Phase name
# Returns:
#   0 on success, 1 on failure
#######################################
upgrade_phase_start() {
    local phase="$1"
    local state_json
    local timestamp

    timestamp=$(upgrade_get_timestamp)

    if ! state_json=$(upgrade_state_load); then
        return 1
    fi

    state_json=$(echo "$state_json" | jq \
        --arg phase "$phase" \
        --arg state "$COMP_STATE_IN_PROGRESS" \
        --arg ts "$timestamp" \
        '.current_phase = $phase |
         .phases[$phase] = {
             state: $state,
             started_at: $ts,
             components: {}
         }')

    if ! upgrade_state_save "$state_json"; then
        return 1
    fi

    return 0
}

#######################################
# Mark phase as complete
# Arguments:
#   $1 - Phase name
# Returns:
#   0 on success, 1 on failure
#######################################
upgrade_phase_complete() {
    local phase="$1"
    local state_json
    local timestamp

    timestamp=$(upgrade_get_timestamp)

    if ! state_json=$(upgrade_state_load); then
        return 1
    fi

    state_json=$(echo "$state_json" | jq \
        --arg phase "$phase" \
        --arg state "$COMP_STATE_COMPLETED" \
        --arg ts "$timestamp" \
        '.phases[$phase].state = $state |
         .phases[$phase].completed_at = $ts')

    if ! upgrade_state_save "$state_json"; then
        return 1
    fi

    return 0
}

#######################################
# Mark phase as failed
# Arguments:
#   $1 - Phase name
#   $2 - Error message
# Returns:
#   0 on success, 1 on failure
#######################################
upgrade_phase_fail() {
    local phase="$1"
    local error="${2:-Unknown error}"
    local state_json
    local timestamp

    timestamp=$(upgrade_get_timestamp)

    if ! state_json=$(upgrade_state_load); then
        return 1
    fi

    state_json=$(echo "$state_json" | jq \
        --arg phase "$phase" \
        --arg state "$COMP_STATE_FAILED" \
        --arg error "$error" \
        --arg ts "$timestamp" \
        '.phases[$phase].state = $state |
         .phases[$phase].failed_at = $ts |
         .phases[$phase].error = $error')

    if ! upgrade_state_save "$state_json"; then
        return 1
    fi

    return 0
}

#######################################
# Get next pending phase
# Arguments:
#   None
# Outputs:
#   Phase name or empty if none
# Returns:
#   0 on success
#######################################
upgrade_phase_get_next() {
    local state_json

    if ! state_json=$(upgrade_state_load); then
        return 1
    fi

    echo "$state_json" | jq -r '
        .phases | to_entries[] |
        select(.value.state == "PENDING") |
        .key' | head -n1
}

#######################################
# Start upgrading a component
# Arguments:
#   $1 - Component name
#   $2 - From version
#   $3 - To version
# Returns:
#   0 on success, 1 on failure
#######################################
upgrade_component_start() {
    local component="$1"
    local from_version="$2"
    local to_version="$3"
    local state_json
    local phase
    local timestamp

    timestamp=$(upgrade_get_timestamp)

    if ! state_json=$(upgrade_state_load); then
        return 1
    fi

    phase=$(echo "$state_json" | jq -r '.current_phase // empty')

    if [[ -z "$phase" ]]; then
        echo "ERROR: No active phase for component upgrade" >&2
        return 1
    fi

    state_json=$(echo "$state_json" | jq \
        --arg phase "$phase" \
        --arg comp "$component" \
        --arg state "$COMP_STATE_UPGRADING" \
        --arg from "$from_version" \
        --arg to "$to_version" \
        --arg ts "$timestamp" \
        '.current_component = $comp |
         .phases[$phase].components[$comp] = {
             state: $state,
             from_version: $from,
             to_version: $to,
             started_at: $ts,
             attempts: 1,
             last_error: null,
             backup_path: null
         }')

    if ! upgrade_state_save "$state_json"; then
        return 1
    fi

    return 0
}

#######################################
# Mark component upgrade as complete
# Arguments:
#   $1 - Component name
# Returns:
#   0 on success, 1 on failure
#######################################
upgrade_component_complete() {
    local component="$1"
    local state_json
    local phase
    local timestamp

    timestamp=$(upgrade_get_timestamp)

    if ! state_json=$(upgrade_state_load); then
        return 1
    fi

    phase=$(echo "$state_json" | jq -r '.current_phase // empty')

    if [[ -z "$phase" ]]; then
        echo "ERROR: No active phase for component" >&2
        return 1
    fi

    state_json=$(echo "$state_json" | jq \
        --arg phase "$phase" \
        --arg comp "$component" \
        --arg state "$COMP_STATE_COMPLETED" \
        --arg ts "$timestamp" \
        '.phases[$phase].components[$comp].state = $state |
         .phases[$phase].components[$comp].completed_at = $ts')

    if ! upgrade_state_save "$state_json"; then
        return 1
    fi

    return 0
}

#######################################
# Mark component upgrade as failed
# Arguments:
#   $1 - Component name
#   $2 - Error message
# Returns:
#   0 on success, 1 on failure
#######################################
upgrade_component_fail() {
    local component="$1"
    local error="${2:-Unknown error}"
    local state_json
    local phase
    local timestamp
    local attempts

    timestamp=$(upgrade_get_timestamp)

    if ! state_json=$(upgrade_state_load); then
        return 1
    fi

    phase=$(echo "$state_json" | jq -r '.current_phase // empty')

    if [[ -z "$phase" ]]; then
        echo "ERROR: No active phase for component" >&2
        return 1
    fi

    attempts=$(echo "$state_json" | jq -r \
        --arg phase "$phase" \
        --arg comp "$component" \
        '.phases[$phase].components[$comp].attempts // 0')
    attempts=$((attempts + 1))

    state_json=$(echo "$state_json" | jq \
        --arg phase "$phase" \
        --arg comp "$component" \
        --arg state "$COMP_STATE_FAILED" \
        --arg error "$error" \
        --arg ts "$timestamp" \
        --argjson attempts "$attempts" \
        '.phases[$phase].components[$comp].state = $state |
         .phases[$phase].components[$comp].failed_at = $ts |
         .phases[$phase].components[$comp].last_error = $error |
         .phases[$phase].components[$comp].attempts = $attempts')

    if ! upgrade_state_save "$state_json"; then
        return 1
    fi

    return 0
}

#######################################
# Check if component is already upgraded
# Arguments:
#   $1 - Component name
# Returns:
#   0 if upgraded, 1 if not
#######################################
upgrade_component_is_upgraded() {
    local component="$1"
    local state_json
    local phase
    local comp_state

    if ! state_json=$(upgrade_state_load); then
        return 1
    fi

    phase=$(echo "$state_json" | jq -r '.current_phase // empty')

    if [[ -z "$phase" ]]; then
        return 1
    fi

    comp_state=$(echo "$state_json" | jq -r \
        --arg phase "$phase" \
        --arg comp "$component" \
        '.phases[$phase].components[$comp].state // empty')

    if [[ "$comp_state" == "$COMP_STATE_COMPLETED" ]]; then
        return 0
    fi

    return 1
}

#######################################
# Get component status
# Arguments:
#   $1 - Component name
# Outputs:
#   JSON object with component status
# Returns:
#   0 on success, 1 on failure
#######################################
upgrade_component_get_status() {
    local component="$1"
    local state_json
    local phase

    if ! state_json=$(upgrade_state_load); then
        return 1
    fi

    phase=$(echo "$state_json" | jq -r '.current_phase // empty')

    if [[ -z "$phase" ]]; then
        echo "{}"
        return 0
    fi

    echo "$state_json" | jq \
        --arg phase "$phase" \
        --arg comp "$component" \
        '.phases[$phase].components[$comp] // {}'
}

#######################################
# Check if upgrade can be resumed
# Arguments:
#   None
# Returns:
#   0 if can resume, 1 if not
#######################################
upgrade_can_resume() {
    local state_json
    local current_state
    local can_resume

    if ! state_json=$(upgrade_state_load); then
        return 1
    fi

    current_state=$(echo "$state_json" | jq -r '.current_state')
    can_resume=$(echo "$state_json" | jq -r '.can_resume')

    if [[ "$can_resume" == "true" ]] && [[ -n "${RESUMABLE_STATES[$current_state]:-}" ]]; then
        return 0
    fi

    return 1
}

#######################################
# Get resume point information
# Arguments:
#   None
# Outputs:
#   JSON with resume information
# Returns:
#   0 on success
#######################################
upgrade_get_resume_point() {
    local state_json

    if ! state_json=$(upgrade_state_load); then
        return 1
    fi

    echo "$state_json" | jq '{
        state: .current_state,
        phase: .current_phase,
        component: .current_component,
        can_resume: .can_resume
    }'
}

#######################################
# Resume upgrade from last checkpoint
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
upgrade_resume() {
    local state_json
    local current_state

    if ! state_json=$(upgrade_state_load); then
        return 1
    fi

    current_state=$(echo "$state_json" | jq -r '.current_state')

    echo "INFO: Resuming upgrade from state: $current_state" >&2

    # Validate components in UPGRADING state
    local phase
    phase=$(echo "$state_json" | jq -r '.current_phase // empty')

    if [[ -n "$phase" ]]; then
        # Check for components stuck in UPGRADING state
        local stuck_components
        stuck_components=$(echo "$state_json" | jq -r \
            --arg phase "$phase" \
            --arg state "$COMP_STATE_UPGRADING" \
            '.phases[$phase].components | to_entries[] |
             select(.value.state == $state) |
             .key')

        if [[ -n "$stuck_components" ]]; then
            echo "INFO: Found components in UPGRADING state, will revalidate" >&2
        fi
    fi

    return 0
}

#######################################
# Mark rollback point for component
# Arguments:
#   $1 - Component name
#   $2 - Backup path
# Returns:
#   0 on success, 1 on failure
#######################################
upgrade_mark_rollback_point() {
    local component="$1"
    local backup_path="$2"
    local state_json
    local phase

    if ! state_json=$(upgrade_state_load); then
        return 1
    fi

    phase=$(echo "$state_json" | jq -r '.current_phase // empty')

    if [[ -z "$phase" ]]; then
        echo "ERROR: No active phase for rollback point" >&2
        return 1
    fi

    state_json=$(echo "$state_json" | jq \
        --arg phase "$phase" \
        --arg comp "$component" \
        --arg backup "$backup_path" \
        '.rollback_available = true |
         .phases[$phase].components[$comp].backup_path = $backup')

    if ! upgrade_state_save "$state_json"; then
        return 1
    fi

    return 0
}

#######################################
# Get rollback information
# Arguments:
#   None
# Outputs:
#   JSON with rollback data
# Returns:
#   0 on success
#######################################
upgrade_get_rollback_info() {
    local state_json

    if ! state_json=$(upgrade_state_load); then
        return 1
    fi

    echo "$state_json" | jq '{
        rollback_available: .rollback_available,
        components: [
            .phases[] | .components | to_entries[] |
            select(.value.backup_path != null) |
            {
                name: .key,
                backup_path: .value.backup_path,
                from_version: .value.from_version,
                to_version: .value.to_version
            }
        ]
    }'
}

#######################################
# Clear rollback points
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
upgrade_clear_rollback_point() {
    local state_json

    if ! state_json=$(upgrade_state_load); then
        return 1
    fi

    state_json=$(echo "$state_json" | jq '.rollback_available = false')

    if ! upgrade_state_save "$state_json"; then
        return 1
    fi

    return 0
}

#######################################
# Check if upgrade is in progress
# Arguments:
#   None
# Returns:
#   0 if in progress, 1 if not
#######################################
upgrade_is_in_progress() {
    local current_state

    if ! current_state=$(upgrade_state_get_current); then
        return 1
    fi

    case "$current_state" in
        "$STATE_PLANNING"|"$STATE_BACKING_UP"|"$STATE_UPGRADING"|"$STATE_VALIDATING"|"$STATE_ROLLING_BACK")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

#######################################
# Calculate upgrade progress percentage
# Arguments:
#   None
# Outputs:
#   Progress percentage (0-100)
# Returns:
#   0 on success
#######################################
upgrade_get_progress_percent() {
    local state_json
    local total_components=0
    local completed_components=0

    if ! state_json=$(upgrade_state_load); then
        echo "0"
        return 0
    fi

    # Count total and completed components across all phases
    while IFS= read -r count; do
        total_components=$((total_components + count))
    done < <(echo "$state_json" | jq '.phases[].components | length')

    while IFS= read -r count; do
        completed_components=$((completed_components + count))
    done < <(echo "$state_json" | jq \
        --arg state "$COMP_STATE_COMPLETED" \
        '.phases[].components | to_entries[] | select(.value.state == $state) | 1' | wc -l)

    if [[ $total_components -eq 0 ]]; then
        echo "0"
        return 0
    fi

    local percent=$((completed_components * 100 / total_components))
    echo "$percent"
}

#######################################
# Get upgrade summary
# Arguments:
#   None
# Outputs:
#   Human-readable upgrade summary
# Returns:
#   0 on success
#######################################
upgrade_get_summary() {
    local state_json

    if ! state_json=$(upgrade_state_load); then
        echo "No upgrade state found"
        return 1
    fi

    echo "$state_json" | jq -r '
        "Upgrade ID: \(.upgrade_id)",
        "State: \(.current_state)",
        "Started: \(.started_at)",
        "Updated: \(.updated_at)",
        "Current Phase: \(.current_phase // "None")",
        "Current Component: \(.current_component // "None")",
        "Rollback Available: \(.rollback_available)",
        "",
        "Phases:",
        (.phases | to_entries[] |
         "  \(.key): \(.value.state) (\(.value.components | length) components)")
    '
}

#######################################
# List upgrade history
# Arguments:
#   $1 - (Optional) Limit number of results
# Outputs:
#   List of historical upgrades
# Returns:
#   0 on success
#######################################
upgrade_list_history() {
    local limit="${1:-10}"
    local count=0

    if [[ ! -d "$UPGRADE_HISTORY_DIR" ]]; then
        echo "No upgrade history found"
        return 0
    fi

    # List history files sorted by modification time (newest first)
    while IFS= read -r file; do
        if [[ $count -ge $limit ]]; then
            break
        fi

        if [[ -f "$file" ]]; then
            jq -r '
                "\(.upgrade_id) | \(.current_state) | \(.started_at) → \(.updated_at)"
            ' "$file"
            count=$((count + 1))
        fi
    done < <(find "$UPGRADE_HISTORY_DIR" -name "upgrade-*.json" -type f -printf '%T@ %p\n' | sort -rn | cut -d' ' -f2-)
}

#######################################
# Save current state to history
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
upgrade_save_to_history() {
    local state_json
    local upgrade_id
    local history_file

    if ! state_json=$(upgrade_state_load); then
        return 1
    fi

    upgrade_id=$(echo "$state_json" | jq -r '.upgrade_id')
    history_file="${UPGRADE_HISTORY_DIR}/${upgrade_id}.json"

    if ! echo "$state_json" | jq '.' > "$history_file"; then
        echo "ERROR: Failed to save to history" >&2
        return 1
    fi

    chmod 600 "$history_file"
    return 0
}

#######################################
# Acquire upgrade lock
# Arguments:
#   None
# Returns:
#   0 on success, 1 if already locked
#######################################
upgrade_lock_acquire() {
    local lock_dir="${UPGRADE_LOCK_FILE}.d"
    local lock_file="${lock_dir}/lock.info"
    local pid=$BASHPID  # Use BASHPID instead of $$ to get actual process ID
    local timestamp

    timestamp=$(upgrade_get_timestamp)

    # Try to create lock directory atomically first
    # mkdir is atomic across processes - no race condition
    if mkdir "$lock_dir" 2>/dev/null; then
        # Successfully created lock directory
        echo "$pid|$timestamp|$HOSTNAME|$USER" > "$lock_file"
        chmod 700 "$lock_dir"
        chmod 600 "$lock_file"
        return 0
    fi

    # Lock directory exists - wait a moment for lock file to be written
    # (there's a tiny race window between mkdir and writing the file)
    local retries=0
    while [[ $retries -lt 10 ]]; do
        if [[ -f "$lock_file" ]]; then
            break
        fi
        sleep 0.01
        retries=$((retries + 1))
    done

    # Check if it's ours, stale, or held by another process
    if [[ -f "$lock_file" ]]; then
        local lock_pid
        lock_pid=$(cut -d'|' -f1 "$lock_file" 2>/dev/null || echo "")

        if [[ "$lock_pid" == "$pid" ]]; then
            # We already hold the lock
            return 0
        fi

        # Check if it's stale (process doesn't exist)
        if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
            echo "INFO: Removing stale lock (process $lock_pid no longer exists)" >&2
            rm -f "$lock_file"
            rmdir "$lock_dir" 2>/dev/null || true

            # Try to acquire again after cleanup
            if mkdir "$lock_dir" 2>/dev/null; then
                echo "$pid|$timestamp|$HOSTNAME|$USER" > "$lock_file"
                chmod 700 "$lock_dir"
                chmod 600 "$lock_file"
                return 0
            fi
        fi

        echo "ERROR: Upgrade lock held by PID $lock_pid" >&2
        return 1
    else
        # Lock directory exists but no file after retries
        echo "ERROR: Upgrade lock directory exists but no lock info" >&2
        return 1
    fi
}

#######################################
# Release upgrade lock
# Arguments:
#   None
# Returns:
#   0 on success
#######################################
upgrade_lock_release() {
    local lock_dir="${UPGRADE_LOCK_FILE}.d"
    local lock_file="${lock_dir}/lock.info"
    local pid=$BASHPID  # Use BASHPID instead of $$ to get actual process ID

    if [[ -f "$lock_file" ]]; then
        local lock_pid
        lock_pid=$(cut -d'|' -f1 "$lock_file" 2>/dev/null || echo "")

        # Only remove if we own it
        if [[ "$lock_pid" == "$pid" ]]; then
            rm -f "$lock_file"
            rmdir "$lock_dir" 2>/dev/null || true
        fi
    fi

    return 0
}

#######################################
# Check if lock is currently held
# Arguments:
#   None
# Returns:
#   0 if locked, 1 if not
#######################################
upgrade_lock_is_held() {
    local lock_dir="${UPGRADE_LOCK_FILE}.d"
    local lock_file="${lock_dir}/lock.info"

    if [[ -d "$lock_dir" ]] && [[ -f "$lock_file" ]]; then
        local lock_pid
        lock_pid=$(cut -d'|' -f1 "$lock_file" 2>/dev/null || echo "")

        # Check if process still exists
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

#######################################
# Check for and remove stale locks
# Arguments:
#   None
# Returns:
#   0 on success
#######################################
upgrade_lock_check_stale() {
    local lock_dir="${UPGRADE_LOCK_FILE}.d"
    local lock_file="${lock_dir}/lock.info"

    if [[ ! -d "$lock_dir" ]]; then
        return 0
    fi

    if [[ ! -f "$lock_file" ]]; then
        # Lock directory exists but no info file - remove it
        rmdir "$lock_dir" 2>/dev/null || true
        return 0
    fi

    local lock_info
    local lock_pid
    local lock_timestamp
    local current_timestamp
    local age

    lock_info=$(cat "$lock_file" 2>/dev/null || echo "")
    lock_pid=$(echo "$lock_info" | cut -d'|' -f1)
    lock_timestamp=$(echo "$lock_info" | cut -d'|' -f2)
    current_timestamp=$(date +%s)

    # Check if process exists
    if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
        echo "INFO: Removing stale lock (process $lock_pid no longer exists)" >&2
        rm -f "$lock_file"
        rmdir "$lock_dir" 2>/dev/null || true
        return 0
    fi

    # Check lock age
    if [[ -n "$lock_timestamp" ]]; then
        local lock_epoch
        lock_epoch=$(date -d "$lock_timestamp" +%s 2>/dev/null || echo "0")
        age=$((current_timestamp - lock_epoch))

        if [[ $age -gt $LOCK_TIMEOUT ]]; then
            echo "WARNING: Removing stale lock (age: ${age}s > ${LOCK_TIMEOUT}s)" >&2
            rm -f "$lock_file"
            rmdir "$lock_dir" 2>/dev/null || true
            return 0
        fi
    fi

    return 0
}

#######################################
# Cleanup upgrade state on completion
# Arguments:
#   None
# Returns:
#   0 on success
#######################################
upgrade_cleanup() {
    # Save to history before cleanup
    upgrade_save_to_history

    # Release lock
    upgrade_lock_release

    # Set state to IDLE
    upgrade_state_set "$STATE_IDLE"

    return 0
}

# Trap to ensure lock cleanup on exit
trap 'upgrade_lock_release' EXIT TERM INT

# Export functions for use in other scripts
export -f upgrade_state_init_dirs
export -f upgrade_get_timestamp
export -f upgrade_generate_id
export -f upgrade_state_write_atomic
export -f upgrade_state_init
export -f upgrade_state_load
export -f upgrade_state_save
export -f upgrade_state_get_current
export -f upgrade_state_validate_transition
export -f upgrade_state_set
export -f upgrade_phase_start
export -f upgrade_phase_complete
export -f upgrade_phase_fail
export -f upgrade_phase_get_next
export -f upgrade_component_start
export -f upgrade_component_complete
export -f upgrade_component_fail
export -f upgrade_component_is_upgraded
export -f upgrade_component_get_status
export -f upgrade_can_resume
export -f upgrade_get_resume_point
export -f upgrade_resume
export -f upgrade_mark_rollback_point
export -f upgrade_get_rollback_info
export -f upgrade_clear_rollback_point
export -f upgrade_is_in_progress
export -f upgrade_get_progress_percent
export -f upgrade_get_summary
export -f upgrade_list_history
export -f upgrade_save_to_history
export -f upgrade_lock_acquire
export -f upgrade_lock_release
export -f upgrade_lock_is_held
export -f upgrade_lock_check_stale
export -f upgrade_cleanup
