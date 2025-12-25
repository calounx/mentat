#!/bin/bash
#===============================================================================
# Transaction Library
# Atomic operations with begin/commit/rollback semantics and automatic recovery
#===============================================================================

# Guard against multiple sourcing
[[ -n "${TRANSACTION_SH_LOADED:-}" ]] && return 0
TRANSACTION_SH_LOADED=1

# Source dependencies
_TRANSACTION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${COMMON_SH_LOADED:-}" ]]; then
    source "$_TRANSACTION_DIR/common.sh"
fi
if [[ -z "${ERRORS_SH_LOADED:-}" ]]; then
    source "$_TRANSACTION_DIR/errors.sh"
fi

#===============================================================================
# TRANSACTION STATE
#===============================================================================

# Transaction state tracking
declare -g TX_ACTIVE=false
declare -g TX_ID=""
declare -g TX_START_TIME=0
declare -g TX_LOG_FILE=""
declare -g TX_BACKUP_DIR=""

# Transaction operation log
declare -ga TX_FILE_OPERATIONS=()      # File changes
declare -ga TX_SERVICE_OPERATIONS=()   # Service changes
declare -ga TX_COMMAND_OPERATIONS=()   # Commands executed
declare -ga TX_ROLLBACK_HOOKS=()       # Custom rollback functions

# Transaction working directory
readonly TX_BASE_DIR="${TX_BASE_DIR:-/var/lib/observability-transactions}"

#===============================================================================
# TRANSACTION LIFECYCLE
#===============================================================================

# Begin a new transaction
# Usage: tx_begin ["transaction_name"]
tx_begin() {
    local tx_name="${1:-transaction}"

    if [[ "$TX_ACTIVE" == "true" ]]; then
        error_report "Transaction already active: $TX_ID" "$E_INVALID_STATE"
        return 1
    fi

    # Generate transaction ID
    TX_ID="${tx_name}_$(date +%Y%m%d_%H%M%S)_$$"
    TX_START_TIME=$(date +%s)
    TX_ACTIVE=true

    # Create transaction directory
    TX_BACKUP_DIR="${TX_BASE_DIR}/${TX_ID}"
    mkdir -p "$TX_BACKUP_DIR"

    # Create transaction log
    TX_LOG_FILE="${TX_BACKUP_DIR}/transaction.log"
    cat > "$TX_LOG_FILE" << EOF
Transaction: $TX_ID
Started: $(date -d "@$TX_START_TIME" '+%Y-%m-%d %H:%M:%S')
Name: $tx_name
PID: $$
---
EOF

    # Clear operation logs
    TX_FILE_OPERATIONS=()
    TX_SERVICE_OPERATIONS=()
    TX_COMMAND_OPERATIONS=()
    TX_ROLLBACK_HOOKS=()

    log_info "Transaction started: $TX_ID"
    log_debug "Transaction dir: $TX_BACKUP_DIR"

    return 0
}

# Commit transaction (finalize changes)
# Usage: tx_commit
tx_commit() {
    if [[ "$TX_ACTIVE" != "true" ]]; then
        error_report "No active transaction to commit" "$E_INVALID_STATE"
        return 1
    fi

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - TX_START_TIME))

    # Append to log
    cat >> "$TX_LOG_FILE" << EOF

Status: COMMITTED
Completed: $(date -d "@$end_time" '+%Y-%m-%d %H:%M:%S')
Duration: ${duration}s
Operations:
  Files: ${#TX_FILE_OPERATIONS[@]}
  Services: ${#TX_SERVICE_OPERATIONS[@]}
  Commands: ${#TX_COMMAND_OPERATIONS[@]}
  Rollback hooks: ${#TX_ROLLBACK_HOOKS[@]}
EOF

    log_success "Transaction committed: $TX_ID (${duration}s)"

    # Keep transaction backup for a while (for debugging)
    # Actual cleanup happens via tx_cleanup

    # Reset state
    TX_ACTIVE=false
    TX_ID=""
    TX_START_TIME=0

    return 0
}

# Rollback transaction (undo all changes)
# Usage: tx_rollback ["reason"]
tx_rollback() {
    local reason="${1:-Manual rollback}"

    if [[ "$TX_ACTIVE" != "true" ]]; then
        error_report "No active transaction to rollback" "$E_INVALID_STATE"
        return 1
    fi

    log_warn "Rolling back transaction: $TX_ID"
    log_warn "Reason: $reason"

    error_push_context "Transaction rollback: $TX_ID"

    local rollback_errors=0
    local end_time
    end_time=$(date +%s)

    # Append to log
    cat >> "$TX_LOG_FILE" << EOF

Status: ROLLED BACK
Reason: $reason
Rollback started: $(date -d "@$end_time" '+%Y-%m-%d %H:%M:%S')
---
Rollback operations:
EOF

    # Execute custom rollback hooks in reverse order
    local i
    for ((i=${#TX_ROLLBACK_HOOKS[@]}-1; i>=0; i--)); do
        local hook="${TX_ROLLBACK_HOOKS[$i]}"
        log_info "Executing rollback hook: $hook"
        echo "  - Rollback hook: $hook" >> "$TX_LOG_FILE"

        if eval "$hook"; then
            log_debug "Rollback hook succeeded: $hook"
        else
            log_error "Rollback hook failed: $hook"
            ((rollback_errors++))
        fi
    done

    # Restore files in reverse order
    for ((i=${#TX_FILE_OPERATIONS[@]}-1; i>=0; i--)); do
        local operation="${TX_FILE_OPERATIONS[$i]}"
        tx_rollback_file_operation "$operation"
        local result=$?
        if [[ $result -ne 0 ]]; then
            ((rollback_errors++))
        fi
    done

    # Restore services in reverse order
    for ((i=${#TX_SERVICE_OPERATIONS[@]}-1; i>=0; i--)); do
        local operation="${TX_SERVICE_OPERATIONS[$i]}"
        tx_rollback_service_operation "$operation"
        local result=$?
        if [[ $result -ne 0 ]]; then
            ((rollback_errors++))
        fi
    done

    # Log completion
    local complete_time
    complete_time=$(date +%s)
    local rollback_duration=$((complete_time - end_time))

    cat >> "$TX_LOG_FILE" << EOF

Rollback completed: $(date -d "@$complete_time" '+%Y-%m-%d %H:%M:%S')
Rollback duration: ${rollback_duration}s
Rollback errors: $rollback_errors
EOF

    # Reset state
    TX_ACTIVE=false

    error_pop_context

    if [[ $rollback_errors -gt 0 ]]; then
        error_report "Transaction rollback completed with $rollback_errors errors" "$E_ROLLBACK_FAILED"
        return 1
    else
        log_success "Transaction rolled back successfully: $TX_ID"
        return 0
    fi
}

# Rollback a file operation
# Usage: tx_rollback_file_operation "operation"
tx_rollback_file_operation() {
    local operation="$1"
    local op_type="${operation%%:*}"
    local file_info="${operation#*:}"

    case "$op_type" in
        CREATE)
            # Remove created file
            local file="$file_info"
            if [[ -f "$file" ]]; then
                log_info "Removing created file: $file"
                echo "  - Remove file: $file" >> "$TX_LOG_FILE"
                rm -f "$file"
            fi
            ;;
        MODIFY|REPLACE)
            # Restore from backup
            local file="${file_info%%|*}"
            local backup="${file_info#*|}"
            if [[ -f "$backup" ]]; then
                log_info "Restoring file from backup: $file"
                echo "  - Restore file: $file from $backup" >> "$TX_LOG_FILE"
                cp -f "$backup" "$file"
            fi
            ;;
        DELETE)
            # Restore deleted file from backup
            local backup="$file_info"
            local file="${backup##*/}"
            file="${file%.backup}"
            log_info "Restoring deleted file: $file"
            echo "  - Restore deleted file: $file from $backup" >> "$TX_LOG_FILE"
            cp -f "$backup" "$file"
            ;;
    esac
}

# Rollback a service operation
# Usage: tx_rollback_service_operation "operation"
tx_rollback_service_operation() {
    local operation="$1"
    local op_type="${operation%%:*}"
    local service="${operation#*:}"

    case "$op_type" in
        START)
            log_info "Stopping service: $service"
            echo "  - Stop service: $service" >> "$TX_LOG_FILE"
            systemctl stop "$service" 2>&1 | tee -a "$TX_LOG_FILE"
            ;;
        STOP)
            log_info "Starting service: $service"
            echo "  - Start service: $service" >> "$TX_LOG_FILE"
            systemctl start "$service" 2>&1 | tee -a "$TX_LOG_FILE"
            ;;
        RESTART)
            # Can't really undo a restart, just log it
            log_warn "Cannot undo service restart: $service"
            echo "  - Cannot undo restart: $service" >> "$TX_LOG_FILE"
            ;;
        ENABLE)
            log_info "Disabling service: $service"
            echo "  - Disable service: $service" >> "$TX_LOG_FILE"
            systemctl disable "$service" 2>&1 | tee -a "$TX_LOG_FILE"
            ;;
        DISABLE)
            log_info "Enabling service: $service"
            echo "  - Enable service: $service" >> "$TX_LOG_FILE"
            systemctl enable "$service" 2>&1 | tee -a "$TX_LOG_FILE"
            ;;
    esac
}

#===============================================================================
# FILE OPERATIONS
#===============================================================================

# Create a file within transaction
# Usage: tx_create_file "file_path" "content"
tx_create_file() {
    local file="$1"
    local content="$2"

    tx_assert_active || return 1

    # Check if file already exists
    if [[ -e "$file" ]]; then
        error_report "Cannot create file (already exists): $file" "$E_ALREADY_EXISTS"
        return 1
    fi

    # Create the file
    printf '%s\n' "$content" > "$file"

    # Log operation
    TX_FILE_OPERATIONS+=("CREATE:$file")
    echo "File created: $file" >> "$TX_LOG_FILE"

    log_debug "Transaction file created: $file"
    return 0
}

# Modify a file within transaction (backup first)
# Usage: tx_modify_file "file_path" "new_content"
tx_modify_file() {
    local file="$1"
    local content="$2"

    tx_assert_active || return 1

    # Backup existing file if it exists
    if [[ -f "$file" ]]; then
        local backup="${TX_BACKUP_DIR}/$(basename "$file").$(date +%s).backup"
        cp -f "$file" "$backup"
        TX_FILE_OPERATIONS+=("MODIFY:${file}|${backup}")
        echo "File modified (backed up to $backup): $file" >> "$TX_LOG_FILE"
    else
        # Treat as create
        TX_FILE_OPERATIONS+=("CREATE:$file")
        echo "File created (was missing): $file" >> "$TX_LOG_FILE"
    fi

    # Write new content
    printf '%s\n' "$content" > "$file"

    log_debug "Transaction file modified: $file"
    return 0
}

# Replace a file within transaction
# Usage: tx_replace_file "file_path" "source_file"
tx_replace_file() {
    local file="$1"
    local source="$2"

    tx_assert_active || return 1

    # Backup existing file if it exists
    if [[ -f "$file" ]]; then
        local backup="${TX_BACKUP_DIR}/$(basename "$file").$(date +%s).backup"
        cp -f "$file" "$backup"
        TX_FILE_OPERATIONS+=("REPLACE:${file}|${backup}")
        echo "File replaced (backed up to $backup): $file" >> "$TX_LOG_FILE"
    else
        TX_FILE_OPERATIONS+=("CREATE:$file")
        echo "File created from source: $file" >> "$TX_LOG_FILE"
    fi

    # Copy source to destination
    cp -f "$source" "$file"

    log_debug "Transaction file replaced: $file"
    return 0
}

# Delete a file within transaction
# Usage: tx_delete_file "file_path"
tx_delete_file() {
    local file="$1"

    tx_assert_active || return 1

    if [[ ! -f "$file" ]]; then
        log_warn "File to delete does not exist: $file"
        return 0
    fi

    # Backup before deleting
    local backup="${TX_BACKUP_DIR}/$(basename "$file").deleted.backup"
    cp -f "$file" "$backup"

    # Delete the file
    rm -f "$file"

    TX_FILE_OPERATIONS+=("DELETE:$backup")
    echo "File deleted (backed up to $backup): $file" >> "$TX_LOG_FILE"

    log_debug "Transaction file deleted: $file"
    return 0
}

#===============================================================================
# SERVICE OPERATIONS
#===============================================================================

# Start a service within transaction
# Usage: tx_service_start "service_name"
tx_service_start() {
    local service="$1"

    tx_assert_active || return 1

    if systemctl is-active --quiet "$service"; then
        log_debug "Service already running: $service"
        return 0
    fi

    systemctl start "$service"
    local result=$?

    if [[ $result -eq 0 ]]; then
        TX_SERVICE_OPERATIONS+=("START:$service")
        echo "Service started: $service" >> "$TX_LOG_FILE"
        log_debug "Transaction service started: $service"
    else
        error_report "Failed to start service: $service" "$E_INSTALL_FAILED"
    fi

    return $result
}

# Stop a service within transaction
# Usage: tx_service_stop "service_name"
tx_service_stop() {
    local service="$1"

    tx_assert_active || return 1

    if ! systemctl is-active --quiet "$service"; then
        log_debug "Service already stopped: $service"
        return 0
    fi

    systemctl stop "$service"
    local result=$?

    if [[ $result -eq 0 ]]; then
        TX_SERVICE_OPERATIONS+=("STOP:$service")
        echo "Service stopped: $service" >> "$TX_LOG_FILE"
        log_debug "Transaction service stopped: $service"
    else
        error_report "Failed to stop service: $service" "$E_INSTALL_FAILED"
    fi

    return $result
}

# Restart a service within transaction
# Usage: tx_service_restart "service_name"
tx_service_restart() {
    local service="$1"

    tx_assert_active || return 1

    systemctl restart "$service"
    local result=$?

    if [[ $result -eq 0 ]]; then
        TX_SERVICE_OPERATIONS+=("RESTART:$service")
        echo "Service restarted: $service" >> "$TX_LOG_FILE"
        log_debug "Transaction service restarted: $service"
    else
        error_report "Failed to restart service: $service" "$E_INSTALL_FAILED"
    fi

    return $result
}

# Enable a service within transaction
# Usage: tx_service_enable "service_name"
tx_service_enable() {
    local service="$1"

    tx_assert_active || return 1

    if systemctl is-enabled --quiet "$service"; then
        log_debug "Service already enabled: $service"
        return 0
    fi

    systemctl enable "$service"
    local result=$?

    if [[ $result -eq 0 ]]; then
        TX_SERVICE_OPERATIONS+=("ENABLE:$service")
        echo "Service enabled: $service" >> "$TX_LOG_FILE"
        log_debug "Transaction service enabled: $service"
    else
        error_report "Failed to enable service: $service" "$E_INSTALL_FAILED"
    fi

    return $result
}

# Disable a service within transaction
# Usage: tx_service_disable "service_name"
tx_service_disable() {
    local service="$1"

    tx_assert_active || return 1

    if ! systemctl is-enabled --quiet "$service"; then
        log_debug "Service already disabled: $service"
        return 0
    fi

    systemctl disable "$service"
    local result=$?

    if [[ $result -eq 0 ]]; then
        TX_SERVICE_OPERATIONS+=("DISABLE:$service")
        echo "Service disabled: $service" >> "$TX_LOG_FILE"
        log_debug "Transaction service disabled: $service"
    else
        error_report "Failed to disable service: $service" "$E_INSTALL_FAILED"
    fi

    return $result
}

#===============================================================================
# CUSTOM ROLLBACK HOOKS
#===============================================================================

# Register a custom rollback hook
# Usage: tx_register_rollback "command_or_function"
tx_register_rollback() {
    local hook="$1"

    tx_assert_active || return 1

    TX_ROLLBACK_HOOKS+=("$hook")
    echo "Rollback hook registered: $hook" >> "$TX_LOG_FILE"

    log_debug "Transaction rollback hook registered: $hook"
    return 0
}

#===============================================================================
# TRANSACTION UTILITIES
#===============================================================================

# Assert that a transaction is active
# Usage: tx_assert_active
tx_assert_active() {
    if [[ "$TX_ACTIVE" != "true" ]]; then
        error_report "No active transaction" "$E_INVALID_STATE"
        return 1
    fi
    return 0
}

# Check if transaction is active
# Usage: tx_is_active
tx_is_active() {
    [[ "$TX_ACTIVE" == "true" ]]
}

# Get current transaction ID
# Usage: tx_get_id
tx_get_id() {
    echo "$TX_ID"
}

# Get transaction duration
# Usage: tx_duration
tx_duration() {
    if [[ "$TX_ACTIVE" == "true" ]]; then
        echo $(($(date +%s) - TX_START_TIME))
    else
        echo 0
    fi
}

#===============================================================================
# TRANSACTION CLEANUP
#===============================================================================

# Clean up old transaction backups
# Usage: tx_cleanup [days_to_keep]
tx_cleanup() {
    local days="${1:-7}"

    if [[ ! -d "$TX_BASE_DIR" ]]; then
        return 0
    fi

    log_info "Cleaning up transaction backups older than $days days..."

    find "$TX_BASE_DIR" -maxdepth 1 -type d -mtime "+$days" -exec rm -rf {} \;

    log_success "Transaction cleanup complete"
}

# List all transaction backups
# Usage: tx_list
tx_list() {
    if [[ ! -d "$TX_BASE_DIR" ]]; then
        log_info "No transaction backups found"
        return 0
    fi

    echo "Transaction backups:"
    for tx_dir in "$TX_BASE_DIR"/*/; do
        if [[ -f "${tx_dir}transaction.log" ]]; then
            local tx_id
            tx_id=$(basename "$tx_dir")
            local status
            status=$(grep "^Status:" "${tx_dir}transaction.log" | tail -1 | cut -d: -f2- | xargs)
            local started
            started=$(grep "^Started:" "${tx_dir}transaction.log" | cut -d: -f2- | xargs)

            printf "  %s - %s (%s)\n" "$tx_id" "$status" "$started"
        fi
    done
}

#===============================================================================
# SAFE TRANSACTION WRAPPER
#===============================================================================

# Execute operations in a transaction with auto-rollback on error
# Usage: tx_safe "transaction_name" command_or_function
tx_safe() {
    local tx_name="$1"
    shift

    tx_begin "$tx_name" || return 1

    # Execute the command
    if "$@"; then
        tx_commit
        return 0
    else
        local code=$?
        tx_rollback "Operation failed with exit code $code"
        return "$code"
    fi
}

#===============================================================================
# INITIALIZATION
#===============================================================================

# Ensure transaction directory exists
mkdir -p "$TX_BASE_DIR" 2>/dev/null || true

#===============================================================================
# USAGE EXAMPLES
#===============================================================================

# Example 1: Manual transaction
# tx_begin "install_nginx_exporter"
# tx_create_file "/etc/systemd/system/nginx_exporter.service" "$SERVICE_CONTENT"
# tx_service_enable "nginx_exporter"
# tx_service_start "nginx_exporter"
# tx_commit

# Example 2: Transaction with auto-rollback
# install_operation() {
#     tx_create_file "/etc/myapp/config.yaml" "$CONFIG"
#     tx_service_start "myapp"
# }
# tx_safe "install_myapp" install_operation

# Example 3: Custom rollback hook
# tx_begin "complex_operation"
# tx_register_rollback "cleanup_temp_files"
# ... operations ...
# tx_commit

# Example 4: Manual rollback
# tx_begin "risky_operation"
# if ! some_operation; then
#     tx_rollback "Operation check failed"
#     exit 1
# fi
# tx_commit

# Example 5: List and cleanup transactions
# tx_list
# tx_cleanup 7  # Remove backups older than 7 days
