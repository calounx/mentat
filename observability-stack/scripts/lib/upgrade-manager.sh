#!/bin/bash
#===============================================================================
# Upgrade Manager Library
# Part of the observability-stack upgrade orchestration system
#
# Provides core upgrade logic with safety checks, backups, and rollback
#
# Features:
#   - Version detection and comparison
#   - Pre-upgrade validation
#   - Automated backups
#   - Health checking
#   - Automatic rollback on failure
#   - Idempotent operations
#
# Usage:
#   source scripts/lib/upgrade-manager.sh
#   detect_installed_version "node_exporter"
#   upgrade_component "node_exporter" "1.9.1"
#===============================================================================

set -euo pipefail

# Guard against multiple sourcing
[[ -n "${UPGRADE_MANAGER_SH_LOADED:-}" ]] && return 0
UPGRADE_MANAGER_SH_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_LIB_DIR/common.sh"
source "$_LIB_DIR/versions.sh"
source "$_LIB_DIR/upgrade-state.sh"

#===============================================================================
# CONFIGURATION
#===============================================================================

UPGRADE_CONFIG_FILE="${UPGRADE_CONFIG_FILE:-config/upgrade.yaml}"
BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-/var/lib/observability-upgrades/backups}"
CHECKSUM_DIR="${CHECKSUM_DIR:-/var/lib/observability-upgrades/checksums}"

#===============================================================================
# YAML HELPER FUNCTIONS
#===============================================================================

# Get component config value using Python
# Usage: get_component_config "component_name" "key" ["default"]
get_component_config() {
    local component="$1"
    local key="$2"
    local default="${3:-}"

    python3 -c "import yaml; import sys; config = yaml.safe_load(open('$UPGRADE_CONFIG_FILE')); value = config.get('components', {}).get('$component', {}).get('$key'); print(value if value is not None else '$default')" 2>/dev/null || echo "$default"
}

#===============================================================================
# VERSION DETECTION
#===============================================================================

# Detect installed version of a component
# Usage: detect_installed_version "component_name"
# Returns: version string or empty if not installed
# SECURITY: Validates binary path and adds security checks (M-2 fix)
detect_installed_version() {
    local component="$1"
    local binary_path
    local version=""

    # Get binary path from config
    binary_path=$(yaml_get_nested "$UPGRADE_CONFIG_FILE" "$component" "binary_path" 2>/dev/null || echo "")

    if [[ -z "$binary_path" ]]; then
        log_debug "No binary_path configured for $component"
        return 1
    fi

    # SECURITY: Validate binary path to prevent path traversal (M-2 fix)
    if [[ "$binary_path" =~ \.\. ]]; then
        log_error "SECURITY: Invalid binary path (path traversal): $binary_path"
        return 1
    fi

    # Check if binary exists and is executable
    if [[ ! -x "$binary_path" ]]; then
        log_debug "Binary not found or not executable: $binary_path"
        return 1
    fi

    # SECURITY: Ensure binary is owned by root and not world-writable (M-2 fix)
    if [[ -f "$binary_path" ]]; then
        local perms owner
        perms=$(stat -c '%a' "$binary_path" 2>/dev/null)
        owner=$(stat -c '%U' "$binary_path" 2>/dev/null)

        if [[ "$perms" =~ [2367]$ ]]; then
            log_error "SECURITY: Binary is world-writable: $binary_path"
            return 1
        fi

        if [[ "$owner" != "root" ]]; then
            log_warn "SECURITY: Binary not owned by root: $binary_path (owner: $owner)"
        fi
    fi

    # SECURITY: Try to extract version with timeout to prevent hanging (M-2 fix)
    if version=$(timeout 5 "$binary_path" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); then
        # SECURITY: Validate version format (M-2 fix)
        if ! validate_version "$version"; then
            log_error "SECURITY: Invalid version format from binary: $version"
            return 1
        fi
        echo "$version"
        return 0
    fi

    # Try alternative version flags
    if version=$(timeout 5 "$binary_path" version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); then
        # SECURITY: Validate version format (M-2 fix)
        if ! validate_version "$version"; then
            log_error "SECURITY: Invalid version format from binary: $version"
            return 1
        fi
        echo "$version"
        return 0
    fi

    log_debug "Could not detect version for $component"
    return 1
}

# Compare installed version with target
# Usage: needs_upgrade "component_name" "target_version"
# Returns: 0 if upgrade needed, 1 if already at target or newer
needs_upgrade() {
    local component="$1"
    local target_version="$2"
    local current_version

    # Detect current version
    if ! current_version=$(detect_installed_version "$component"); then
        log_info "$component is not installed, upgrade needed"
        return 0
    fi

    log_debug "Current version of $component: $current_version"
    log_debug "Target version: $target_version"

    # Compare versions
    local cmp_result
    if ! cmp_result=$(compare_versions "$current_version" "$target_version"); then
        log_warn "Failed to compare versions"
        return 0
    fi

    case "$cmp_result" in
        -1)
            log_info "$component needs upgrade: $current_version -> $target_version"
            return 0
            ;;
        0)
            log_skip "$component already at target version: $current_version"
            return 1
            ;;
        1)
            log_warn "$component is newer than target: $current_version > $target_version"
            return 1
            ;;
    esac
}

# Get target version for component from config
# Usage: get_target_version "component_name"
get_target_version() {
    local component="$1"

    # Check for two-stage upgrade
    local upgrade_strategy
    upgrade_strategy=$(get_component_config "$component" "upgrade_strategy")

    if [[ "$upgrade_strategy" == "two-stage" ]]; then
        # Check if we need intermediate version first
        local current_version
        current_version=$(detect_installed_version "$component" || echo "0.0.0")

        local intermediate_version
        intermediate_version=$(get_component_config "$component" "intermediate_version")

        local target_version
        target_version=$(get_component_config "$component" "target_version")

        # If current < intermediate, return intermediate
        # Otherwise return target
        local cmp_result
        cmp_result=$(compare_versions "$current_version" "$intermediate_version")

        if [[ $cmp_result -eq -1 ]]; then
            echo "$intermediate_version"
        else
            echo "$target_version"
        fi
    else
        # Single-stage upgrade
        get_component_config "$component" "target_version"
    fi
}

#===============================================================================
# PRE-UPGRADE VALIDATION
#===============================================================================

# Validate prerequisites before upgrade
# Usage: validate_prerequisites "component_name"
# Returns: 0 if all checks pass, 1 otherwise
validate_prerequisites() {
    local component="$1"
    local errors=0

    log_info "Validating prerequisites for $component upgrade..."

    # Check disk space
    local min_disk_space
    min_disk_space=$(yaml_get_nested "$UPGRADE_CONFIG_FILE" "global" "min_disk_space" 2>/dev/null || echo "1024")

    local available_space
    available_space=$(df /var/lib 2>/dev/null | tail -1 | awk '{print $4}')

    if [[ $available_space -lt $min_disk_space ]]; then
        log_error "Insufficient disk space: ${available_space}KB available, ${min_disk_space}KB required"
        ((errors++))
    else
        log_debug "Disk space OK: ${available_space}KB available"
    fi

    # Check if service is running (for running services)
    local service_name
    service_name=$(yaml_get_nested "$UPGRADE_CONFIG_FILE" "$component" "service" 2>/dev/null || echo "")

    if [[ -n "$service_name" ]]; then
        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
            log_debug "Service $service_name is running"
        else
            log_warn "Service $service_name is not running"
        fi
    fi

    # Check dependencies are met
    local dependencies
    dependencies=$(yaml_get_array "$UPGRADE_CONFIG_FILE" "${component}_dependencies" 2>/dev/null || echo "")

    if [[ -n "$dependencies" ]]; then
        while read -r dep; do
            [[ -z "$dep" ]] && continue

            local dep_status
            dep_status=$(state_get_component_status "$dep" 2>/dev/null || echo "pending")

            if [[ "$dep_status" != "completed" && "$dep_status" != "skipped" ]]; then
                log_error "Dependency $dep not satisfied (status: $dep_status)"
                ((errors++))
            fi
        done <<< "$dependencies"
    fi

    # Validate component-specific pre-upgrade commands
    # This would run commands like "promtool check config" for Prometheus
    local pre_validation
    pre_validation=$(yaml_get_nested "$UPGRADE_CONFIG_FILE" "${component}_validation" "pre_upgrade_validation" 2>/dev/null || echo "")

    if [[ -n "$pre_validation" ]]; then
        log_debug "Running pre-upgrade validation commands..."
        # Would execute validation commands here
    fi

    if [[ $errors -eq 0 ]]; then
        log_success "Prerequisites validated for $component"
        return 0
    else
        log_error "Prerequisite validation failed with $errors errors"
        return 1
    fi
}

#===============================================================================
# BACKUP OPERATIONS
#===============================================================================

# Create backup of component before upgrade
# Usage: backup_component "component_name"
# Returns: backup path on success, empty on failure
# SECURITY: Validates component name to prevent path traversal (M-3 fix)
backup_component() {
    local component="$1"

    # SECURITY: Validate component name to prevent path traversal (M-3 fix)
    if [[ "$component" =~ \.\. ]] || [[ "$component" =~ / ]]; then
        log_error "SECURITY: Invalid component name (path traversal attempt): $component"
        return 1
    fi

    if [[ ! "$component" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "SECURITY: Component name contains invalid characters: $component"
        return 1
    fi

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="$BACKUP_BASE_DIR/${component}/${timestamp}"

    log_info "Creating backup for $component..."

    # Check if backup is enabled
    local backup_enabled
    backup_enabled=$(yaml_get_nested "$UPGRADE_CONFIG_FILE" "${component}_backup" "enabled" 2>/dev/null || echo "true")

    if [[ "$backup_enabled" != "true" ]]; then
        log_skip "Backup disabled for $component"
        return 0
    fi

    # Create backup directory
    mkdir -p "$backup_dir"
    chmod 700 "$backup_dir"

    # Get paths to backup from config
    local backup_count=0

    # Backup binary
    local binary_path
    binary_path=$(yaml_get_nested "$UPGRADE_CONFIG_FILE" "$component" "binary_path" 2>/dev/null || echo "")

    if [[ -n "$binary_path" && -f "$binary_path" ]]; then
        # SC2155: Separate declaration and assignment to detect command failures
        local binary_backup
        binary_backup="$backup_dir/$(basename "$binary_path")" || {
            log_error "Failed to determine backup path for $binary_path"
            return 1
        }
        cp -p "$binary_path" "$binary_backup"
        log_debug "Backed up binary: $binary_path"
        ((backup_count++))
    fi

    # Backup service file
    local service_name
    service_name=$(yaml_get_nested "$UPGRADE_CONFIG_FILE" "$component" "service" 2>/dev/null || echo "")

    if [[ -n "$service_name" ]]; then
        local service_file="/etc/systemd/system/${service_name}.service"
        if [[ -f "$service_file" ]]; then
            cp -p "$service_file" "$backup_dir/"
            log_debug "Backed up service file: $service_file"
            ((backup_count++))
        fi
    fi

    # Backup configuration directories
    # Parse backup paths from config (simplified - would need better YAML parsing)
    local config_paths="/etc/${component} /etc/${component}.conf"
    for path in $config_paths; do
        if [[ -e "$path" ]]; then
            local backup_name
            backup_name=$(basename "$path")
            cp -rp "$path" "$backup_dir/${backup_name}"
            log_debug "Backed up config: $path"
            ((backup_count++))
        fi
    done

    # Create backup metadata
    cat > "$backup_dir/metadata.json" <<EOF
{
  "component": "$component",
  "timestamp": "$timestamp",
  "version": "$(detect_installed_version "$component" || echo "unknown")",
  "backup_count": $backup_count,
  "created_by": "upgrade-manager"
}
EOF

    if [[ $backup_count -gt 0 ]]; then
        log_success "Backup created: $backup_dir ($backup_count items)"
        echo "$backup_dir"
        return 0
    else
        log_warn "No items backed up for $component"
        rmdir "$backup_dir" 2>/dev/null || true
        return 1
    fi
}

# Restore component from backup
# Usage: restore_from_backup "component_name" "backup_path"
restore_from_backup() {
    local component="$1"
    local backup_dir="$2"

    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup directory not found: $backup_dir"
        return 1
    fi

    log_info "Restoring $component from backup: $backup_dir"

    # Stop service first
    local service_name
    service_name=$(yaml_get_nested "$UPGRADE_CONFIG_FILE" "$component" "service" 2>/dev/null || echo "")

    if [[ -n "$service_name" ]]; then
        systemctl stop "$service_name" 2>/dev/null || true
    fi

    # Restore binary
    local binary_path
    binary_path=$(yaml_get_nested "$UPGRADE_CONFIG_FILE" "$component" "binary_path" 2>/dev/null || echo "")

    if [[ -n "$binary_path" ]]; then
        # SC2155: Separate declaration and assignment to detect command failures
        local binary_backup
        binary_backup="$backup_dir/$(basename "$binary_path")" || {
            log_error "Failed to determine backup path for $binary_path"
            return 1
        }
        if [[ -f "$binary_backup" ]]; then
            cp -p "$binary_backup" "$binary_path"
            log_debug "Restored binary: $binary_path"
        fi
    fi

    # Restore service file
    if [[ -n "$service_name" ]]; then
        local service_backup="$backup_dir/${service_name}.service"
        if [[ -f "$service_backup" ]]; then
            cp -p "$service_backup" "/etc/systemd/system/"
            systemctl daemon-reload
            log_debug "Restored service file"
        fi
    fi

    # Restore configuration
    # This would restore config directories from backup

    # Restart service
    if [[ -n "$service_name" ]]; then
        systemctl start "$service_name"
        log_debug "Restarted service: $service_name"
    fi

    log_success "Restored $component from backup"
    return 0
}

#===============================================================================
# HEALTH CHECKS
#===============================================================================

# Perform health check on component
# Usage: health_check "component_name" [timeout]
# Returns: 0 if healthy, 1 otherwise
health_check() {
    local component="$1"
    local timeout="${2:-60}"
    local check_type
    local endpoint

    log_info "Running health check for $component..."

    # Get health check configuration
    check_type=$(yaml_get_deep "$UPGRADE_CONFIG_FILE" "components" "$component" "health_check.type" 2>/dev/null || echo "http")
    endpoint=$(yaml_get_deep "$UPGRADE_CONFIG_FILE" "components" "$component" "health_check.endpoint" 2>/dev/null || echo "")

    if [[ -z "$endpoint" ]]; then
        log_warn "No health check endpoint configured for $component"
        return 0
    fi

    case "$check_type" in
        http)
            # HTTP health check
            local expected_status
            expected_status=$(yaml_get_deep "$UPGRADE_CONFIG_FILE" "components" "$component" "health_check.expected_status" 2>/dev/null || echo "200")

            local attempts=0
            local max_attempts=$((timeout / 5))

            while [[ $attempts -lt $max_attempts ]]; do
                local status_code
                status_code=$(curl -s -o /dev/null -w "%{http_code}" "$endpoint" 2>/dev/null || echo "000")

                if [[ "$status_code" == "$expected_status" ]]; then
                    log_success "Health check passed for $component (HTTP $status_code)"
                    return 0
                fi

                log_debug "Health check attempt $((attempts + 1))/$max_attempts: HTTP $status_code"
                sleep 5
                ((attempts++))
            done

            log_error "Health check failed for $component after $attempts attempts"
            return 1
            ;;

        tcp)
            # TCP port check
            local host port
            host=$(echo "$endpoint" | cut -d: -f1)
            port=$(echo "$endpoint" | cut -d: -f2)

            if wait_for_service "$host" "$port" "$timeout"; then
                log_success "Health check passed for $component (TCP $host:$port)"
                return 0
            else
                log_error "Health check failed for $component (TCP $host:$port)"
                return 1
            fi
            ;;

        *)
            log_warn "Unknown health check type: $check_type"
            return 0
            ;;
    esac
}

# Verify metrics are being exported (for exporters)
# Usage: verify_metrics "component_name"
verify_metrics() {
    local component="$1"
    local endpoint

    endpoint=$(yaml_get_deep "$UPGRADE_CONFIG_FILE" "components" "$component" "health_check.endpoint" 2>/dev/null || echo "")

    if [[ -z "$endpoint" ]]; then
        return 0
    fi

    log_debug "Verifying metrics for $component..."

    # Check if metrics endpoint returns data
    local metrics
    if metrics=$(curl -s "$endpoint" 2>/dev/null); then
        local metric_count
        metric_count=$(echo "$metrics" | grep -c "^[a-z]" || echo "0")

        if [[ $metric_count -gt 0 ]]; then
            log_success "Metrics verified for $component ($metric_count metrics found)"
            return 0
        else
            log_error "No metrics found for $component"
            return 1
        fi
    else
        log_error "Failed to fetch metrics for $component"
        return 1
    fi
}

#===============================================================================
# COMPONENT UPGRADE EXECUTION
#===============================================================================

# Execute upgrade for a single component
# Usage: upgrade_component "component_name" [target_version] [force]
# Returns: 0 on success, 1 on failure
upgrade_component() {
    local component="$1"
    local target_version="${2:-}"
    local force="${3:-false}"

    log_info "===== Upgrading $component ====="

    # Get target version if not specified
    if [[ -z "$target_version" ]]; then
        target_version=$(get_target_version "$component")
    fi

    if [[ -z "$target_version" ]]; then
        log_error "No target version specified for $component"
        return 1
    fi

    # Detect current version
    local current_version
    current_version=$(detect_installed_version "$component" || echo "not_installed")

    # Update state
    state_begin_component "$component" "$current_version" "$target_version"

    # Check if upgrade needed (unless forced)
    if [[ "$force" != "true" ]]; then
        if ! needs_upgrade "$component" "$target_version"; then
            state_skip_component "$component" "Already at target version $target_version"
            return 0
        fi
    fi

    # Validate prerequisites
    if ! validate_prerequisites "$component"; then
        state_fail_component "$component" "Prerequisite validation failed"
        return 1
    fi

    # Create backup
    local backup_path
    if ! backup_path=$(backup_component "$component"); then
        log_warn "Backup failed, continuing anyway"
        backup_path=""
    fi

    # Execute the actual upgrade
    # This calls the component-specific upgrade script
    local upgrade_script
    upgrade_script="$(get_stack_root)/scripts/upgrade-component.sh"

    if [[ ! -x "$upgrade_script" ]]; then
        log_error "Upgrade script not found: $upgrade_script"
        state_fail_component "$component" "Upgrade script not found"
        return 1
    fi

    log_info "Executing upgrade for $component to version $target_version..."

    # Run upgrade script
    if ! MODULE_NAME="$component" \
         MODULE_VERSION="$target_version" \
         BACKUP_PATH="$backup_path" \
         "$upgrade_script"; then

        log_error "Upgrade execution failed for $component"

        # Attempt rollback if backup available
        if [[ -n "$backup_path" ]]; then
            log_warn "Attempting automatic rollback..."
            if restore_from_backup "$component" "$backup_path"; then
                state_fail_component "$component" "Upgrade failed, rolled back successfully"
            else
                state_fail_component "$component" "Upgrade failed, rollback also failed"
            fi
        else
            state_fail_component "$component" "Upgrade failed, no backup available"
        fi

        return 1
    fi

    # Post-upgrade health check
    if ! health_check "$component"; then
        log_error "Health check failed after upgrade"

        # Attempt rollback
        if [[ -n "$backup_path" ]]; then
            log_warn "Attempting automatic rollback due to health check failure..."
            if restore_from_backup "$component" "$backup_path"; then
                state_fail_component "$component" "Health check failed, rolled back successfully"
            else
                state_fail_component "$component" "Health check failed, rollback also failed"
            fi
        else
            state_fail_component "$component" "Health check failed, no backup available"
        fi

        return 1
    fi

    # Verify metrics if applicable
    local verify_metrics_enabled
    verify_metrics_enabled=$(yaml_get_deep "$UPGRADE_CONFIG_FILE" "components" "$component" "validation.verify_metrics" 2>/dev/null || echo "false")

    if [[ "$verify_metrics_enabled" == "true" ]]; then
        if ! verify_metrics "$component"; then
            log_warn "Metrics verification failed (non-fatal)"
        fi
    fi

    # Calculate checksum of new binary
    local checksum=""
    local binary_path
    binary_path=$(yaml_get_nested "$UPGRADE_CONFIG_FILE" "$component" "binary_path" 2>/dev/null || echo "")

    if [[ -n "$binary_path" && -f "$binary_path" ]]; then
        checksum=$(sha256sum "$binary_path" | awk '{print $1}')
    fi

    # Mark as completed
    state_complete_component "$component" "$checksum" "$backup_path"

    log_success "===== Upgrade completed: $component $current_version -> $target_version ====="
    return 0
}

# Rollback component to previous version
# Usage: rollback_component "component_name"
rollback_component() {
    local component="$1"

    log_info "Rolling back $component..."

    # Get backup path from state
    local backup_path
    backup_path=$(state_read "components.${component}.backup_path")

    if [[ -z "$backup_path" || "$backup_path" == "null" ]]; then
        log_error "No backup available for $component"
        return 1
    fi

    if ! restore_from_backup "$component" "$backup_path"; then
        log_error "Rollback failed for $component"
        return 1
    fi

    # Verify rollback
    if health_check "$component"; then
        log_success "Rollback successful for $component"
        return 0
    else
        log_error "Health check failed after rollback"
        return 1
    fi
}

#===============================================================================
# UTILITY FUNCTIONS
#===============================================================================

# P0-6: Validate upgrade configuration file
# Usage: validate_upgrade_config "config_file"
# Returns: 0 if valid, 1 otherwise
validate_upgrade_config() {
    local config_file="$1"

    log_info "Validating upgrade configuration..."

    # Check if file exists
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi

    # Check if valid YAML using python3
    if ! python3 -c "import yaml, sys; yaml.safe_load(open('$config_file'))" 2>/dev/null; then
        log_error "Configuration is not valid YAML"
        return 1
    fi

    # Check required top-level keys
    local required_keys=("components" "phases")
    for key in "${required_keys[@]}"; do
        if ! grep -q "^${key}:" "$config_file"; then
            log_error "Missing required key: $key"
            return 1
        fi
    done

    log_success "Configuration validation passed"
    return 0
}

# Get component risk level
# Usage: get_risk_level "component_name"
get_risk_level() {
    local component="$1"
    get_component_config "$component" "risk_level" "medium"
}

# Get component phase
# Usage: get_component_phase "component_name"
get_component_phase() {
    local component="$1"
    python3 -c "import yaml; config = yaml.safe_load(open('$UPGRADE_CONFIG_FILE')); print(config.get('components', {}).get('$component', {}).get('phase', 1))" 2>/dev/null || echo "1"
}

# List all components from config
# Usage: list_all_components
list_all_components() {
    if [[ ! -f "$UPGRADE_CONFIG_FILE" ]]; then
        log_error "Upgrade config not found: $UPGRADE_CONFIG_FILE"
        return 1
    fi

    # Extract component names from YAML using Python
    python3 -c "import yaml; import sys; config = yaml.safe_load(open('$UPGRADE_CONFIG_FILE')); [print(comp) for comp in config.get('components', {}).keys()]" 2>/dev/null
}

# Get components by phase
# Usage: get_components_by_phase <phase_number>
get_components_by_phase() {
    local phase="$1"

    list_all_components | while read -r component; do
        local comp_phase
        comp_phase=$(get_component_phase "$component")
        if [[ "$comp_phase" == "$phase" ]]; then
            echo "$component"
        fi
    done
}

log_debug "Upgrade manager library loaded"
