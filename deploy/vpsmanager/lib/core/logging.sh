#!/usr/bin/env bash
# Logging utilities for vpsmanager

# Log directory
VPSMANAGER_LOG_DIR="${VPSMANAGER_ROOT}/var/log"
VPSMANAGER_LOG_FILE="${VPSMANAGER_LOG_DIR}/vpsmanager.log"

# Ensure log directory exists
ensure_log_dir() {
    if [[ ! -d "$VPSMANAGER_LOG_DIR" ]]; then
        mkdir -p "$VPSMANAGER_LOG_DIR" 2>/dev/null || true
    fi
}

# Log a message to the log file
# Usage: log_message "INFO" "message"
log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    ensure_log_dir

    echo "[${timestamp}] [${level}] ${message}" >> "$VPSMANAGER_LOG_FILE" 2>/dev/null || true
}

# Log info message
log_info() {
    log_message "INFO" "$1"
}

# Log warning message
log_warn() {
    log_message "WARN" "$1"
}

# Log error message
log_error() {
    log_message "ERROR" "$1"
}

# Log debug message (only if DEBUG=1)
log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        log_message "DEBUG" "$1"
    fi
}

# Log command execution
log_cmd() {
    local cmd="$1"
    local result="$2"
    local exit_code="$3"

    log_message "CMD" "Executed: ${cmd} (exit: ${exit_code})"
    if [[ -n "$result" && "${DEBUG:-0}" == "1" ]]; then
        log_message "CMD" "Output: ${result}"
    fi
}

# Rotate log file if it exceeds max size (10MB)
rotate_log() {
    local max_size=$((10 * 1024 * 1024))  # 10MB

    if [[ -f "$VPSMANAGER_LOG_FILE" ]]; then
        local size
        size=$(stat -f%z "$VPSMANAGER_LOG_FILE" 2>/dev/null || stat -c%s "$VPSMANAGER_LOG_FILE" 2>/dev/null || echo 0)

        if [[ "$size" -gt "$max_size" ]]; then
            mv "$VPSMANAGER_LOG_FILE" "${VPSMANAGER_LOG_FILE}.1"
            touch "$VPSMANAGER_LOG_FILE"
            log_info "Log file rotated"
        fi
    fi
}
