#!/bin/bash
#===============================================================================
# Module Registry Library
# Enhanced module management with caching, metadata indexing, and lifecycle hooks
#===============================================================================

[[ -n "${REGISTRY_SH_LOADED:-}" ]] && return 0
REGISTRY_SH_LOADED=1

_REGISTRY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${COMMON_SH_LOADED:-}" ]] && source "$_REGISTRY_DIR/common.sh"
[[ -z "${ERRORS_SH_LOADED:-}" ]] && source "$_REGISTRY_DIR/errors.sh"
[[ -z "${MODULE_LOADER_LOADED:-}" ]] && source "$_REGISTRY_DIR/module-loader.sh"

# Registry cache directory
readonly REGISTRY_CACHE_DIR="${REGISTRY_CACHE_DIR:-/var/cache/observability/registry}"
readonly REGISTRY_INDEX="${REGISTRY_CACHE_DIR}/index.json"

# Module lifecycle hooks
declare -gA REGISTRY_PRE_INSTALL_HOOKS=()
declare -gA REGISTRY_POST_INSTALL_HOOKS=()
declare -gA REGISTRY_PRE_UNINSTALL_HOOKS=()
declare -gA REGISTRY_POST_UNINSTALL_HOOKS=()

# Initialize registry
# Usage: registry_init
registry_init() {
    mkdir -p "$REGISTRY_CACHE_DIR"
    
    if [[ ! -f "$REGISTRY_INDEX" ]]; then
        echo '{"modules":{},"last_updated":0}' > "$REGISTRY_INDEX"
    fi
    
    log_debug "Registry initialized: $REGISTRY_CACHE_DIR"
}

# Build registry index
# Usage: registry_build_index
registry_build_index() {
    error_push_context "Building registry index"
    
    registry_init
    
    local modules_data="{"
    local first=true
    
    while IFS= read -r module; do
        [[ "$first" == "false" ]] && modules_data+=","
        first=false
        
        local version port category description
        version=$(module_version "$module" 2>/dev/null || echo "unknown")
        port=$(module_port "$module" 2>/dev/null || echo "0")
        category=$(module_category "$module" 2>/dev/null || echo "uncategorized")
        description=$(module_description "$module" 2>/dev/null || echo "")
        
        modules_data+="\"$module\":{\"version\":\"$version\",\"port\":$port,\"category\":\"$category\",\"description\":\"$description\"}"
    done < <(list_all_modules)
    
    modules_data+="}"
    
    local timestamp
    timestamp=$(date +%s)
    
    cat > "$REGISTRY_INDEX" << EOF
{
  "modules": $modules_data,
  "last_updated": $timestamp
}
EOF
    
    error_pop_context
    log_success "Registry index built: $REGISTRY_INDEX"
}

# Get module metadata from index
# Usage: registry_get_metadata "module_name" "field"
registry_get_metadata() {
    local module="$1"
    local field="$2"
    
    if [[ ! -f "$REGISTRY_INDEX" ]]; then
        registry_build_index
    fi
    
    if command -v jq &>/dev/null; then
        jq -r ".modules.\"$module\".\"$field\" // empty" "$REGISTRY_INDEX"
    else
        # Fallback without jq (less reliable)
        grep -A 5 "\"$module\"" "$REGISTRY_INDEX" | grep "\"$field\"" | cut -d: -f2 | tr -d '", '
    fi
}

# Check if registry index is stale
# Usage: registry_is_stale [max_age_seconds]
registry_is_stale() {
    local max_age="${1:-3600}"  # Default: 1 hour
    
    if [[ ! -f "$REGISTRY_INDEX" ]]; then
        return 0  # Stale (doesn't exist)
    fi
    
    local last_updated
    if command -v jq &>/dev/null; then
        last_updated=$(jq -r '.last_updated' "$REGISTRY_INDEX")
    else
        last_updated=$(grep last_updated "$REGISTRY_INDEX" | grep -o '[0-9]*')
    fi
    
    local now
    now=$(date +%s)
    local age=$((now - last_updated))
    
    [[ $age -gt $max_age ]]
}

# Refresh registry if stale
# Usage: registry_refresh_if_needed
registry_refresh_if_needed() {
    if registry_is_stale; then
        log_info "Registry index is stale, rebuilding..."
        registry_build_index
    fi
}

# Search modules by keyword
# Usage: registry_search "keyword"
registry_search() {
    local keyword="$1"
    
    registry_refresh_if_needed
    
    echo "Modules matching '$keyword':"
    while IFS= read -r module; do
        local description
        description=$(registry_get_metadata "$module" "description")
        if [[ "$module" =~ $keyword ]] || [[ "$description" =~ $keyword ]]; then
            echo "  - $module: $description"
        fi
    done < <(list_all_modules)
}

# Register lifecycle hook
# Usage: registry_register_hook "hook_type" "module_name" "function_name"
registry_register_hook() {
    local hook_type="$1"
    local module="$2"
    local func="$3"
    
    case "$hook_type" in
        pre_install)
            REGISTRY_PRE_INSTALL_HOOKS["$module"]="$func"
            ;;
        post_install)
            REGISTRY_POST_INSTALL_HOOKS["$module"]="$func"
            ;;
        pre_uninstall)
            REGISTRY_PRE_UNINSTALL_HOOKS["$module"]="$func"
            ;;
        post_uninstall)
            REGISTRY_POST_UNINSTALL_HOOKS["$module"]="$func"
            ;;
        *)
            error_report "Invalid hook type: $hook_type" "$E_VALIDATION_FAILED"
            return 1
            ;;
    esac
    
    log_debug "Registered $hook_type hook for $module: $func"
}

# Execute lifecycle hook
# Usage: registry_execute_hook "hook_type" "module_name"
registry_execute_hook() {
    local hook_type="$1"
    local module="$2"
    
    local hook=""
    case "$hook_type" in
        pre_install)
            hook="${REGISTRY_PRE_INSTALL_HOOKS[$module]:-}"
            ;;
        post_install)
            hook="${REGISTRY_POST_INSTALL_HOOKS[$module]:-}"
            ;;
        pre_uninstall)
            hook="${REGISTRY_PRE_UNINSTALL_HOOKS[$module]:-}"
            ;;
        post_uninstall)
            hook="${REGISTRY_POST_UNINSTALL_HOOKS[$module]:-}"
            ;;
    esac
    
    if [[ -n "$hook" ]]; then
        log_info "Executing $hook_type hook for $module..."
        if declare -f "$hook" &>/dev/null; then
            "$hook" "$module"
        else
            eval "$hook"
        fi
    fi
}

# Install module with lifecycle hooks
# Usage: registry_install_module "module_name"
registry_install_module() {
    local module="$1"
    
    error_push_context "Registry install: $module"
    
    registry_execute_hook "pre_install" "$module"
    
    if install_module "$module"; then
        registry_execute_hook "post_install" "$module"
        registry_build_index  # Refresh index
        error_pop_context
        return 0
    else
        error_pop_context
        return 1
    fi
}

# Uninstall module with lifecycle hooks
# Usage: registry_uninstall_module "module_name"
registry_uninstall_module() {
    local module="$1"
    
    error_push_context "Registry uninstall: $module"
    
    registry_execute_hook "pre_uninstall" "$module"
    
    if uninstall_module "$module"; then
        registry_execute_hook "post_uninstall" "$module"
        registry_build_index  # Refresh index
        error_pop_context
        return 0
    else
        error_pop_context
        return 1
    fi
}

# Get module dependencies (future enhancement)
# Usage: registry_get_dependencies "module_name"
registry_get_dependencies() {
    local module="$1"
    # TODO: Implement dependency resolution
    echo ""
}

# Check module compatibility
# Usage: registry_check_compatibility "module_name"
registry_check_compatibility() {
    local module="$1"
    # TODO: Implement version compatibility checks
    return 0
}

# Auto-initialize registry on load
registry_init

