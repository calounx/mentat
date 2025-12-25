#!/bin/bash
#===============================================================================
# Configuration Management Library
# Configuration loading, validation, merging, and template rendering
#===============================================================================

[[ -n "${CONFIG_SH_LOADED:-}" ]] && return 0
CONFIG_SH_LOADED=1

_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${COMMON_SH_LOADED:-}" ]] && source "$_CONFIG_DIR/common.sh"
[[ -z "${ERRORS_SH_LOADED:-}" ]] && source "$_CONFIG_DIR/errors.sh"
[[ -z "${VALIDATION_SH_LOADED:-}" ]] && source "$_CONFIG_DIR/validation.sh"

# Configuration cache
declare -gA CONFIG_CACHE=()
declare -g CONFIG_CACHE_ENABLED="${CONFIG_CACHE_ENABLED:-true}"

# Load configuration file with validation
# Usage: config_load "config_file"
config_load() {
    local config_file="$1"
    
    validate_file_exists "$config_file" "configuration file" || return 1
    validate_yaml_syntax "$config_file" || return 1
    
    # Cache the config file path
    CONFIG_CACHE["__loaded_file"]="$config_file"
    log_debug "Configuration loaded: $config_file"
    
    return 0
}

# Get a configuration value
# Usage: config_get "key" [default]
config_get() {
    local key="$1"
    local default="${2:-}"
    local config_file="${CONFIG_CACHE[__loaded_file]:-}"
    
    if [[ -z "$config_file" ]]; then
        error_report "No configuration loaded" "$E_CONFIG_ERROR"
        return 1
    fi
    
    # Check cache first
    if [[ "$CONFIG_CACHE_ENABLED" == "true" ]] && [[ -n "${CONFIG_CACHE[$key]:-}" ]]; then
        echo "${CONFIG_CACHE[$key]}"
        return 0
    fi
    
    local value
    value=$(yaml_get "$config_file" "$key")
    
    if [[ -z "$value" ]]; then
        if [[ -n "$default" ]]; then
            echo "$default"
        fi
        return 1
    fi
    
    # Cache the value
    [[ "$CONFIG_CACHE_ENABLED" == "true" ]] && CONFIG_CACHE["$key"]="$value"
    
    echo "$value"
    return 0
}

# Get nested configuration value
# Usage: config_get_nested "parent" "child" [default]
config_get_nested() {
    local parent="$1"
    local child="$2"
    local default="${3:-}"
    local config_file="${CONFIG_CACHE[__loaded_file]:-}"
    
    [[ -z "$config_file" ]] && return 1
    
    local cache_key="${parent}.${child}"
    if [[ "$CONFIG_CACHE_ENABLED" == "true" ]] && [[ -n "${CONFIG_CACHE[$cache_key]:-}" ]]; then
        echo "${CONFIG_CACHE[$cache_key]}"
        return 0
    fi
    
    local value
    value=$(yaml_get_nested "$config_file" "$parent" "$child")
    
    if [[ -z "$value" ]]; then
        [[ -n "$default" ]] && echo "$default"
        return 1
    fi
    
    [[ "$CONFIG_CACHE_ENABLED" == "true" ]] && CONFIG_CACHE["$cache_key"]="$value"
    echo "$value"
    return 0
}

# Merge two YAML configurations (base + override)
# Usage: config_merge "base_file" "override_file" "output_file"
config_merge() {
    local base="$1"
    local override="$2"
    local output="$3"
    
    validate_file_exists "$base" || return 1
    validate_file_exists "$override" || return 1
    
    # If yq available, use it for proper merging
    if command -v yq &>/dev/null; then
        yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$base" "$override" > "$output"
        return 0
    fi
    
    # Fallback: simple concatenation (not a true merge)
    log_warn "yq not available, using simple merge (may have conflicts)"
    cat "$base" "$override" > "$output"
}

# Validate configuration against schema
# Usage: config_validate "config_file" "required_key1" "required_key2" ...
config_validate() {
    local config_file="$1"
    shift
    local required_keys=("$@")
    
    validate_config_complete "$config_file" "${required_keys[@]}"
}

# Render configuration template
# Usage: config_render_template "template_file" "output_file" "VAR1=value1" "VAR2=value2" ...
config_render_template() {
    local template="$1"
    local output="$2"
    shift 2
    
    validate_file_exists "$template" || return 1
    
    local rendered
    rendered=$(template_render_file "$template" "$@")
    
    printf '%s\n' "$rendered" > "$output"
    log_success "Template rendered: $output"
}

# Check for configuration changes
# Usage: config_has_changed "config_file"
config_has_changed() {
    local config_file="$1"
    local cache_key="__mtime_${config_file}"
    
    if [[ ! -f "$config_file" ]]; then
        return 1
    fi
    
    local current_mtime
    current_mtime=$(stat -c%Y "$config_file" 2>/dev/null || stat -f%m "$config_file" 2>/dev/null)
    
    if [[ -n "${CONFIG_CACHE[$cache_key]:-}" ]]; then
        if [[ "$current_mtime" != "${CONFIG_CACHE[$cache_key]}" ]]; then
            CONFIG_CACHE["$cache_key"]="$current_mtime"
            return 0  # Changed
        fi
        return 1  # Not changed
    fi
    
    CONFIG_CACHE["$cache_key"]="$current_mtime"
    return 0  # First time, consider as changed
}

# Clear configuration cache
# Usage: config_clear_cache
config_clear_cache() {
    CONFIG_CACHE=()
    log_debug "Configuration cache cleared"
}

