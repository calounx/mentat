#!/bin/bash
#===============================================================================
# Lock Utilities - File locking to prevent concurrent executions
#===============================================================================

# Guard against multiple sourcing
[[ -n "${LOCK_UTILS_LOADED:-}" ]] && return 0
LOCK_UTILS_LOADED=1

# Source common if available
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/common.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
else
    # Minimal fallback logging
    log_debug() { [[ "${DEBUG:-false}" == "true" ]] && echo "[DEBUG] $1" >&2; }
    log_info() { echo "[INFO] $1" >&2; }
    log_warn() { echo "[WARN] $1" >&2; }
    log_error() { echo "[ERROR] $1" >&2; }
fi

#===============================================================================
# FILE LOCKING
#===============================================================================

# Global lock file variable
LOCK_FILE="${LOCK_FILE:-/var/lock/observability-setup.lock}"
LOCK_ACQUIRED=false

# Acquire an exclusive lock
# Usage: acquire_lock [lock_file] [timeout_seconds]
# Returns: 0 on success, 1 on failure
acquire_lock() {
    local lock_file="${1:-$LOCK_FILE}"
    local timeout="${2:-300}"  # 5 minutes default
    local waited=0

    # Create lock directory if needed
    mkdir -p "$(dirname "$lock_file")" 2>/dev/null || {
        log_error "Failed to create lock directory: $(dirname "$lock_file")"
        return 1
    }

    log_debug "Acquiring lock: $lock_file"

    # Try to acquire lock with timeout
    while (( waited < timeout )); do
        # Try to create lock file exclusively using flock if available
        if command -v flock &>/dev/null; then
            # Use flock for proper file locking
            exec 200>"$lock_file"
            if flock -n 200; then
                echo "$$" >&200
                LOCK_FILE="$lock_file"
                LOCK_ACQUIRED=true
                log_debug "Lock acquired using flock: $lock_file (PID $$)"
                trap 'release_lock' EXIT INT TERM
                return 0
            else
                # Lock held by another process
                local lock_pid
                lock_pid=$(cat "$lock_file" 2>/dev/null || echo "unknown")
                log_info "Waiting for lock (held by PID $lock_pid)..."
                sleep 2
                ((waited += 2))
                continue
            fi
        else
            # Fallback to simple file creation
            if ( set -o noclobber; echo "$$" > "$lock_file" ) 2>/dev/null; then
                # Lock acquired
                LOCK_FILE="$lock_file"
                LOCK_ACQUIRED=true
                log_debug "Lock acquired: $lock_file (PID $$)"
                trap 'release_lock' EXIT INT TERM
                return 0
            else
                # Check if lock holder is still alive
                if [[ -f "$lock_file" ]]; then
                    local lock_pid
                    lock_pid=$(cat "$lock_file" 2>/dev/null || echo "")

                    if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                        log_warn "Stale lock found (PID $lock_pid no longer exists), removing..."
                        rm -f "$lock_file"
                        continue
                    fi

                    log_info "Waiting for lock (held by PID $lock_pid)..."
                fi

                sleep 2
                ((waited += 2))
            fi
        fi
    done

    log_error "Failed to acquire lock after ${timeout}s timeout"
    return 1
}

# Release the lock
# Usage: release_lock [lock_file]
release_lock() {
    local lock_file="${1:-$LOCK_FILE}"

    if [[ "$LOCK_ACQUIRED" != "true" ]]; then
        return 0
    fi

    if [[ -f "$lock_file" ]]; then
        local lock_pid
        lock_pid=$(cat "$lock_file" 2>/dev/null || echo "")

        # Only remove if we own it
        if [[ "$lock_pid" == "$$" ]]; then
            rm -f "$lock_file"
            LOCK_ACQUIRED=false
            log_debug "Lock released: $lock_file"
        else
            log_debug "Not removing lock (owned by PID $lock_pid, we are $$)"
        fi
    fi

    # Close file descriptor if flock was used
    if command -v flock &>/dev/null; then
        exec 200>&-
    fi
}

# Check if a lock is currently held
# Usage: is_locked [lock_file]
# Returns: 0 if locked, 1 if not locked
is_locked() {
    local lock_file="${1:-$LOCK_FILE}"

    if [[ ! -f "$lock_file" ]]; then
        return 1
    fi

    local lock_pid
    lock_pid=$(cat "$lock_file" 2>/dev/null || echo "")

    if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
        return 0  # Lock is held by active process
    else
        return 1  # Lock is stale or doesn't exist
    fi
}
