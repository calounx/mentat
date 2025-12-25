#!/bin/bash
#===============================================================================
# Module Loader Library
# Functions for loading, validating, and managing exporter modules
#===============================================================================

# Guard against multiple sourcing
[[ -n "${MODULE_LOADER_LOADED:-}" ]] && return 0
MODULE_LOADER_LOADED=1

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Module directories
MODULES_CORE_DIR="$(get_modules_dir)/_core"
MODULES_AVAILABLE_DIR="$(get_modules_dir)/_available"
MODULES_CUSTOM_DIR="$(get_modules_dir)/_custom"

#===============================================================================
# MODULE DISCOVERY
#===============================================================================

# List all available modules (from all directories)
# Usage: list_all_modules
list_all_modules() {
    local modules=()

    for dir in "$MODULES_CORE_DIR" "$MODULES_AVAILABLE_DIR" "$MODULES_CUSTOM_DIR"; do
        if [[ -d "$dir" ]]; then
            for module_dir in "$dir"/*/; do
                if [[ -f "${module_dir}module.yaml" ]]; then
                    modules+=("$(basename "$module_dir")")
                fi
            done
        fi
    done

    printf '%s\n' "${modules[@]}" | sort -u
}

# List core modules only
# Usage: list_core_modules
list_core_modules() {
    if [[ -d "$MODULES_CORE_DIR" ]]; then
        for module_dir in "$MODULES_CORE_DIR"/*/; do
            if [[ -f "${module_dir}module.yaml" ]]; then
                basename "$module_dir"
            fi
        done
    fi
}

# List available (community) modules
# Usage: list_available_modules
list_available_modules() {
    if [[ -d "$MODULES_AVAILABLE_DIR" ]]; then
        for module_dir in "$MODULES_AVAILABLE_DIR"/*/; do
            if [[ -f "${module_dir}module.yaml" ]]; then
                basename "$module_dir"
            fi
        done
    fi
}

# List custom modules
# Usage: list_custom_modules
list_custom_modules() {
    if [[ -d "$MODULES_CUSTOM_DIR" ]]; then
        for module_dir in "$MODULES_CUSTOM_DIR"/*/; do
            if [[ -f "${module_dir}module.yaml" ]]; then
                basename "$module_dir"
            fi
        done
    fi
}

# Get the directory path for a module
# Usage: get_module_dir "module_name"
get_module_dir() {
    local module_name="$1"

    for dir in "$MODULES_CORE_DIR" "$MODULES_AVAILABLE_DIR" "$MODULES_CUSTOM_DIR"; do
        if [[ -f "$dir/$module_name/module.yaml" ]]; then
            echo "$dir/$module_name"
            return 0
        fi
    done

    return 1
}

# Get the manifest file path for a module
# Usage: get_module_manifest "module_name"
get_module_manifest() {
    local module_name="$1"
    local module_dir

    module_dir=$(get_module_dir "$module_name") || return 1
    echo "$module_dir/module.yaml"
}

# Check if a module exists
# Usage: module_exists "module_name"
module_exists() {
    local module_name="$1"
    get_module_dir "$module_name" >/dev/null 2>&1
}

#===============================================================================
# MODULE MANIFEST PARSING
#===============================================================================

# Get a value from a module manifest
# Usage: module_get "module_name" "key"
module_get() {
    local module_name="$1"
    local key="$2"
    local manifest

    manifest=$(get_module_manifest "$module_name") || return 1
    yaml_get "$manifest" "$key"
}

# Get a nested value from a module manifest
# Usage: module_get_nested "module_name" "parent" "child"
module_get_nested() {
    local module_name="$1"
    local parent="$2"
    local child="$3"
    local manifest

    manifest=$(get_module_manifest "$module_name") || return 1
    yaml_get_nested "$manifest" "$parent" "$child"
}

# Get a deeply nested value from a module manifest
# Usage: module_get_deep "module_name" "level1" "level2" "level3"
module_get_deep() {
    local module_name="$1"
    local level1="$2"
    local level2="$3"
    local level3="$4"
    local manifest

    manifest=$(get_module_manifest "$module_name") || return 1
    yaml_get_deep "$manifest" "$level1" "$level2" "$level3"
}

# Get module version
# Usage: module_version "module_name"
module_version() {
    local module_name="$1"
    module_get_nested "$module_name" "module" "version"
}

# Get module display name
# Usage: module_display_name "module_name"
module_display_name() {
    local module_name="$1"
    module_get_nested "$module_name" "module" "display_name"
}

# Get module port
# Usage: module_port "module_name"
module_port() {
    local module_name="$1"
    module_get_nested "$module_name" "exporter" "port"
}

# Get module category
# Usage: module_category "module_name"
module_category() {
    local module_name="$1"
    module_get_nested "$module_name" "module" "category"
}

# Get module description
# Usage: module_description "module_name"
module_description() {
    local module_name="$1"
    module_get_nested "$module_name" "module" "description"
}

#===============================================================================
# MODULE DETECTION
#===============================================================================

# Run detection rules for a module
# Returns confidence score (0-100) or empty if not detected
# Usage: module_detect "module_name"
module_detect() {
    local module_name="$1"
    local manifest
    local confidence=0
    local matches=0
    local total_checks=0

    manifest=$(get_module_manifest "$module_name") || return 1

    # Check commands
    while IFS= read -r cmd; do
        [[ -z "$cmd" ]] && continue
        ((total_checks++))
        if eval "$cmd" &>/dev/null; then
            ((matches++))
            log_debug "Module $module_name: command '$cmd' matched"
        fi
    done < <(yaml_get_array "$manifest" "detection.commands" 2>/dev/null)

    # Check systemd services
    while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue
        ((total_checks++))
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            ((matches+=2))  # Weight systemd higher
            log_debug "Module $module_name: service '$svc' is active"
        elif systemctl is-enabled --quiet "$svc" 2>/dev/null; then
            ((matches++))
            log_debug "Module $module_name: service '$svc' is enabled"
        fi
    done < <(yaml_get_array "$manifest" "detection.systemd_services" 2>/dev/null)

    # Check files
    while IFS= read -r filepath; do
        [[ -z "$filepath" ]] && continue
        ((total_checks++))
        if [[ -e "$filepath" ]]; then
            ((matches++))
            log_debug "Module $module_name: file '$filepath' exists"
        fi
    done < <(yaml_get_array "$manifest" "detection.files" 2>/dev/null)

    # Calculate confidence
    if [[ $total_checks -gt 0 ]]; then
        # Base confidence from matches
        local base_confidence=$((matches * 100 / total_checks))

        # Get the module's max confidence from manifest
        local max_confidence
        max_confidence=$(yaml_get_nested "$manifest" "detection" "confidence")
        max_confidence=${max_confidence:-100}

        # Scale to max confidence
        confidence=$((base_confidence * max_confidence / 100))

        if [[ $confidence -gt 0 ]]; then
            echo "$confidence"
            return 0
        fi
    fi

    return 1
}

# Auto-detect all applicable modules for current host
# Returns: "module_name:confidence" lines sorted by confidence
# Usage: detect_all_modules
detect_all_modules() {
    local results=()

    while IFS= read -r module; do
        local confidence
        if confidence=$(module_detect "$module" 2>/dev/null); then
            results+=("$module:$confidence")
        fi
    done < <(list_all_modules)

    # Sort by confidence descending
    printf '%s\n' "${results[@]}" | sort -t: -k2 -rn
}

#===============================================================================
# MODULE VALIDATION
#===============================================================================

# Validate a module's manifest
# Usage: validate_module "module_name"
validate_module() {
    local module_name="$1"
    local manifest
    local errors=()

    manifest=$(get_module_manifest "$module_name")
    if [[ $? -ne 0 ]]; then
        log_error "Module '$module_name' not found"
        return 1
    fi

    # Check required fields
    local name
    name=$(module_get_nested "$module_name" "module" "name")
    if [[ -z "$name" ]]; then
        errors+=("Missing required field: module.name")
    fi

    local version
    version=$(module_version "$module_name")
    if [[ -z "$version" ]]; then
        errors+=("Missing required field: module.version")
    fi

    local port
    port=$(module_port "$module_name")
    if [[ -z "$port" ]]; then
        errors+=("Missing required field: exporter.port")
    elif ! [[ "$port" =~ ^[0-9]+$ ]]; then
        errors+=("Invalid port: $port (must be numeric)")
    fi

    # Check for required files
    local module_dir
    module_dir=$(get_module_dir "$module_name")

    if [[ ! -f "$module_dir/install.sh" ]]; then
        errors+=("Missing required file: install.sh")
    fi

    # Report results
    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "Module '$module_name' validation failed:"
        for error in "${errors[@]}"; do
            echo "  - $error"
        done
        return 1
    fi

    log_success "Module '$module_name' is valid"
    return 0
}

# Validate all modules
# Usage: validate_all_modules
validate_all_modules() {
    local has_errors=false

    while IFS= read -r module; do
        if ! validate_module "$module"; then
            has_errors=true
        fi
    done < <(list_all_modules)

    if [[ "$has_errors" == "true" ]]; then
        return 1
    fi
    return 0
}

#===============================================================================
# HOST CONFIGURATION
#===============================================================================

# Get the configuration file path for a host
# Usage: get_host_config "hostname"
get_host_config() {
    local hostname="$1"
    echo "$(get_hosts_config_dir)/${hostname}.yaml"
}

# Check if a host has a configuration file
# Usage: host_config_exists "hostname"
host_config_exists() {
    local hostname="$1"
    [[ -f "$(get_host_config "$hostname")" ]]
}

# List all configured hosts
# Usage: list_configured_hosts
list_configured_hosts() {
    local hosts_dir
    hosts_dir=$(get_hosts_config_dir)

    if [[ -d "$hosts_dir" ]]; then
        for config in "$hosts_dir"/*.yaml; do
            if [[ -f "$config" ]]; then
                basename "$config" .yaml
            fi
        done
    fi
}

# Get a value from a host's configuration
# Usage: host_config_get "hostname" "key"
host_config_get() {
    local hostname="$1"
    local key="$2"
    local config

    config=$(get_host_config "$hostname")
    if [[ -f "$config" ]]; then
        yaml_get "$config" "$key"
    fi
}

# Get a nested value from a host's configuration
# Usage: host_config_get_nested "hostname" "parent" "child"
host_config_get_nested() {
    local hostname="$1"
    local parent="$2"
    local child="$3"
    local config

    config=$(get_host_config "$hostname")
    if [[ -f "$config" ]]; then
        yaml_get_nested "$config" "$parent" "$child"
    fi
}

# Check if a module is enabled for a host
# Usage: module_enabled_for_host "module_name" "hostname"
module_enabled_for_host() {
    local module_name="$1"
    local hostname="$2"
    local config

    config=$(get_host_config "$hostname")
    if [[ -f "$config" ]]; then
        local enabled
        enabled=$(yaml_get_deep "$config" "modules" "$module_name" "enabled")
        [[ "$enabled" == "true" ]]
    else
        return 1
    fi
}

# Get list of enabled modules for a host
# Usage: get_host_enabled_modules "hostname"
get_host_enabled_modules() {
    local hostname="$1"
    local config

    config=$(get_host_config "$hostname")
    if [[ ! -f "$config" ]]; then
        return 1
    fi

    # Parse modules section and filter by enabled: true
    awk '
        /^modules:/ { in_modules = 1; next }
        in_modules && /^[a-zA-Z_-]+:/ { in_modules = 0 }
        in_modules && /^  [a-zA-Z_-]+:/ {
            module = $1
            gsub(/:$/, "", module)
            current_module = module
        }
        in_modules && /^    enabled:/ {
            if ($2 == "true") {
                print current_module
            }
        }
    ' "$config"
}

# Get module configuration for a specific host
# Usage: get_host_module_config "hostname" "module_name" "config_key"
get_host_module_config() {
    local hostname="$1"
    local module_name="$2"
    local config_key="$3"
    local config

    config=$(get_host_config "$hostname")
    if [[ ! -f "$config" ]]; then
        return 1
    fi

    # This is a 4-level deep access: modules.<module_name>.config.<config_key>
    awk -v module="$module_name" -v key="$config_key" '
        BEGIN { in_module = 0; in_config = 0 }
        /^modules:/ { in_modules = 1; next }
        in_modules && /^  [a-zA-Z_-]+:/ {
            m = $1
            gsub(/:$/, "", m)
            in_module = (m == module)
            in_config = 0
        }
        in_module && /^    config:/ { in_config = 1; next }
        in_module && in_config && /^      [a-zA-Z_-]+:/ {
            k = $1
            gsub(/:$/, "", k)
            if (k == key) {
                sub(/^      [a-zA-Z_-]+:[[:space:]]*/, "")
                gsub(/^["'\''"]|["'\''"]$/, "")
                print
                exit
            }
        }
        in_module && /^    [a-zA-Z_-]+:/ && !/^    config:/ { in_config = 0 }
    ' "$config"
}

#===============================================================================
# MODULE INSTALLATION
#===============================================================================

# Run a module's installation script
# Usage: install_module "module_name" [extra_args...]
install_module() {
    local module_name="$1"
    shift
    local module_dir

    module_dir=$(get_module_dir "$module_name")
    if [[ $? -ne 0 ]]; then
        log_error "Module '$module_name' not found"
        return 1
    fi

    local install_script="$module_dir/install.sh"
    if [[ ! -f "$install_script" ]]; then
        log_error "Install script not found for module '$module_name'"
        return 1
    fi

    log_info "Installing module: $module_name"

    # Source the install script with module context
    export MODULE_NAME="$module_name"
    export MODULE_DIR="$module_dir"
    export MODULE_VERSION
    MODULE_VERSION=$(module_version "$module_name")
    export MODULE_PORT
    MODULE_PORT=$(module_port "$module_name")

    # Run the install script
    bash "$install_script" "$@"
}

# Uninstall a module
# Usage: uninstall_module "module_name" [--purge]
uninstall_module() {
    local module_name="$1"
    local purge="${2:-}"
    local module_dir

    module_dir=$(get_module_dir "$module_name")
    if [[ $? -ne 0 ]]; then
        log_error "Module '$module_name' not found"
        return 1
    fi

    local uninstall_script="$module_dir/uninstall.sh"
    if [[ -f "$uninstall_script" ]]; then
        log_info "Uninstalling module: $module_name"
        bash "$uninstall_script" "$purge"
    else
        log_warn "No uninstall script found for module '$module_name'"
        return 1
    fi
}

#===============================================================================
# MODULE INFORMATION DISPLAY
#===============================================================================

# Display detailed information about a module
# Usage: show_module_info "module_name"
show_module_info() {
    local module_name="$1"

    if ! module_exists "$module_name"; then
        log_error "Module '$module_name' not found"
        return 1
    fi

    local module_dir
    module_dir=$(get_module_dir "$module_name")
    local manifest="$module_dir/module.yaml"

    local display_name version description port category

    display_name=$(module_display_name "$module_name")
    version=$(module_version "$module_name")
    description=$(module_description "$module_name")
    port=$(module_port "$module_name")
    category=$(module_category "$module_name")

    echo ""
    echo "Module: $module_name"
    echo "========================================"
    echo "Display Name: ${display_name:-$module_name}"
    echo "Version:      $version"
    echo "Port:         $port"
    echo "Category:     ${category:-uncategorized}"
    echo "Description:  ${description:-No description}"
    echo ""
    echo "Location: $module_dir"
    echo ""
    echo "Files:"
    ls -la "$module_dir/" 2>/dev/null | tail -n +2
    echo ""

    # Check if has dashboard
    if [[ -f "$module_dir/dashboard.json" ]]; then
        echo "Dashboard:    Yes"
    else
        echo "Dashboard:    No"
    fi

    # Check if has alerts
    if [[ -f "$module_dir/alerts.yml" ]]; then
        echo "Alert Rules:  Yes"
    else
        echo "Alert Rules:  No"
    fi

    echo ""
}

# List modules with their status
# Usage: list_modules_status
list_modules_status() {
    echo ""
    printf "%-25s %-10s %-6s %-12s %s\n" "MODULE" "VERSION" "PORT" "CATEGORY" "DESCRIPTION"
    printf "%-25s %-10s %-6s %-12s %s\n" "-------------------------" "----------" "------" "------------" "--------------------"

    while IFS= read -r module; do
        local version port category description

        version=$(module_version "$module")
        port=$(module_port "$module")
        category=$(module_category "$module")
        description=$(module_description "$module")

        # Truncate description to 40 chars
        if [[ ${#description} -gt 40 ]]; then
            description="${description:0:37}..."
        fi

        printf "%-25s %-10s %-6s %-12s %s\n" \
            "$module" \
            "${version:-N/A}" \
            "${port:-N/A}" \
            "${category:-N/A}" \
            "${description:-N/A}"
    done < <(list_all_modules)

    echo ""
}
