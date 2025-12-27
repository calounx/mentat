#!/bin/bash
#===============================================================================
# Service Management Library
# Safe service operations with health checking and dependency management
#===============================================================================

[[ -n "${SERVICE_SH_LOADED:-}" ]] && return 0
SERVICE_SH_LOADED=1

_SERVICE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${COMMON_SH_LOADED:-}" ]] && source "$_SERVICE_DIR/common.sh"
[[ -z "${ERRORS_SH_LOADED:-}" ]] && source "$_SERVICE_DIR/errors.sh"
[[ -z "${RETRY_SH_LOADED:-}" ]] && source "$_SERVICE_DIR/retry.sh"

# Service health check retries
readonly SERVICE_HEALTH_TIMEOUT="${SERVICE_HEALTH_TIMEOUT:-30}"
readonly SERVICE_HEALTH_INTERVAL="${SERVICE_HEALTH_INTERVAL:-2}"

# Safe service start with health check
# Usage: service_start "service_name" [health_check_command]
service_start() {
    local service="$1"
    local health_check="${2:-}"
    
    error_push_context "Start service: $service"
    
    if systemctl is-active --quiet "$service"; then
        log_info "Service already running: $service"
        error_pop_context
        return 0
    fi
    
    log_info "Starting service: $service"
    if ! systemctl start "$service"; then
        error_report "Failed to start service: $service" "$E_INSTALL_FAILED"
        error_pop_context
        return 1
    fi
    
    # Wait for service to be active
    sleep 2
    
    # Run health check if provided
    if [[ -n "$health_check" ]]; then
        if ! service_health_check "$service" "$health_check"; then
            systemctl stop "$service"
            error_report "Service health check failed: $service" "$E_INSTALL_FAILED"
            error_pop_context
            return 1
        fi
    fi
    
    error_pop_context
    log_success "Service started: $service"
    return 0
}

# Safe service stop with graceful degradation
# Usage: service_stop "service_name" [timeout]
service_stop() {
    local service="$1"
    local timeout="${2:-30}"
    
    error_push_context "Stop service: $service"
    
    if ! systemctl is-active --quiet "$service"; then
        log_info "Service already stopped: $service"
        error_pop_context
        return 0
    fi
    
    log_info "Stopping service: $service"
    systemctl stop "$service"
    
    # Wait for service to stop
    local elapsed=0
    while systemctl is-active --quiet "$service" && [[ $elapsed -lt $timeout ]]; do
        sleep 1
        ((elapsed++))
    done
    
    if systemctl is-active --quiet "$service"; then
        log_warn "Service did not stop gracefully, forcing: $service"
        systemctl kill "$service"
        sleep 2
    fi
    
    error_pop_context
    log_success "Service stopped: $service"
    return 0
}

# Safe service restart
# Usage: service_restart "service_name" [health_check]
service_restart() {
    local service="$1"
    local health_check="${2:-}"
    
    error_push_context "Restart service: $service"
    
    log_info "Restarting service: $service"
    if ! systemctl restart "$service"; then
        error_report "Failed to restart service: $service" "$E_INSTALL_FAILED"
        error_pop_context
        return 1
    fi
    
    sleep 2
    
    if [[ -n "$health_check" ]]; then
        if ! service_health_check "$service" "$health_check"; then
            error_report "Service health check failed after restart: $service" "$E_INSTALL_FAILED"
            error_pop_context
            return 1
        fi
    fi
    
    error_pop_context
    log_success "Service restarted: $service"
    return 0
}

# Service health check
# Usage: service_health_check "service_name" "check_command"
# SECURITY: Executes check_command via bash -c with validation
service_health_check() {
    local service="$1"
    local check_command="$2"

    # SECURITY: Validate that check_command doesn't contain dangerous patterns
    # Allow common health check patterns: curl, grep, test, systemctl, etc.
    if [[ "$check_command" =~ \$\(|\`|;\ *rm|;\ *dd|>\&|eval|exec ]]; then
        log_error "Unsafe command pattern detected in health check: $check_command"
        return 1
    fi

    log_debug "Running health check for: $service"

    # SECURITY: Use bash -c instead of eval for better isolation
    retry_until_timeout "Health check: $service" "$SERVICE_HEALTH_TIMEOUT" \
        bash -c "$check_command"
}

# Wait for service to be ready
# Usage: service_wait_ready "service_name" [timeout]
service_wait_ready() {
    local service="$1"
    local timeout="${2:-$SERVICE_HEALTH_TIMEOUT}"
    
    retry_until_timeout "Wait for service: $service" "$timeout" \
        systemctl is-active --quiet "$service"
}

# Enable service with validation
# Usage: service_enable "service_name"
service_enable() {
    local service="$1"
    
    if systemctl is-enabled --quiet "$service" 2>/dev/null; then
        log_debug "Service already enabled: $service"
        return 0
    fi
    
    log_info "Enabling service: $service"
    systemctl enable "$service"
    log_success "Service enabled: $service"
}

# Disable service
# Usage: service_disable "service_name"
service_disable() {
    local service="$1"
    
    if ! systemctl is-enabled --quiet "$service" 2>/dev/null; then
        log_debug "Service already disabled: $service"
        return 0
    fi
    
    log_info "Disabling service: $service"
    systemctl disable "$service"
    log_success "Service disabled: $service"
}

# Get service status
# Usage: service_status "service_name"
service_status() {
    local service="$1"
    
    echo "Service: $service"
    echo "  Active: $(systemctl is-active "$service" 2>/dev/null || echo "inactive")"
    echo "  Enabled: $(systemctl is-enabled "$service" 2>/dev/null || echo "disabled")"
    
    if systemctl is-active --quiet "$service"; then
        echo "  PID: $(systemctl show -p MainPID --value "$service")"
        echo "  Memory: $(systemctl show -p MemoryCurrent --value "$service" | numfmt --to=iec)"
    fi
}

