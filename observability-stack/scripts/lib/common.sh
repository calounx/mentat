#!/bin/bash
#===============================================================================
# Common Library Functions
# Shared utilities for the observability stack module system
#===============================================================================

# Guard against multiple sourcing
[[ -n "${COMMON_SH_LOADED:-}" ]] && return 0
COMMON_SH_LOADED=1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

#===============================================================================
# LOGGING FUNCTIONS
#===============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_skip() {
    echo -e "${GREEN}[SKIP]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_fatal() {
    echo -e "${RED}[FATAL]${NC} $1" >&2
    exit 1
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
    fi
}

#===============================================================================
# PATH UTILITIES
#===============================================================================

# Get the absolute path of the observability stack root
get_stack_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$(cd "$script_dir/../.." && pwd)"
}

# Get the modules directory
get_modules_dir() {
    echo "$(get_stack_root)/modules"
}

# Get the config directory
get_config_dir() {
    echo "$(get_stack_root)/config"
}

# Get the hosts config directory
get_hosts_config_dir() {
    echo "$(get_stack_root)/config/hosts"
}

#===============================================================================
# YAML PARSING UTILITIES
# Simple YAML parsing without external dependencies (for basic key: value)
#===============================================================================

# Get a simple key: value from a YAML file
# Usage: yaml_get "file.yaml" "key"
yaml_get() {
    local file="$1"
    local key="$2"

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    grep -E "^${key}:" "$file" 2>/dev/null | sed "s/^${key}:[[:space:]]*//" | sed 's/^["'\'']//' | sed 's/["'\'']$//' | sed 's/#.*//' | xargs
}

# Get a nested key value (one level deep)
# Usage: yaml_get_nested "file.yaml" "parent" "child"
yaml_get_nested() {
    local file="$1"
    local parent="$2"
    local child="$3"

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    # Extract the section under parent and find the child key
    awk -v parent="$parent" -v child="$child" '
        /^[a-zA-Z_-]+:/ { in_section = ($0 ~ "^"parent":") }
        in_section && /^  [a-zA-Z_-]+:/ {
            gsub(/^  /, "")
            if ($0 ~ "^"child":") {
                sub("^"child":[[:space:]]*", "")
                gsub(/^["'\''"]|["'\''"]$/, "")
                print
                exit
            }
        }
    ' "$file"
}

# Get deeply nested key value (two levels deep)
# Usage: yaml_get_deep "file.yaml" "level1" "level2" "level3"
yaml_get_deep() {
    local file="$1"
    local level1="$2"
    local level2="$3"
    local level3="$4"

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    awk -v l1="$level1" -v l2="$level2" -v l3="$level3" '
        BEGIN { in_l1 = 0; in_l2 = 0 }
        /^[a-zA-Z_-]+:/ {
            in_l1 = ($0 ~ "^"l1":")
            in_l2 = 0
        }
        in_l1 && /^  [a-zA-Z_-]+:/ {
            in_l2 = ($0 ~ "^  "l2":")
        }
        in_l1 && in_l2 && /^    [a-zA-Z_-]+:/ {
            if ($0 ~ "^    "l3":") {
                sub("^    "l3":[[:space:]]*", "")
                gsub(/^["'\''"]|["'\''"]$/, "")
                print
                exit
            }
        }
    ' "$file"
}

# Get an array of values from YAML (list items under a key)
# Usage: yaml_get_array "file.yaml" "key"
# Returns lines, one per item
yaml_get_array() {
    local file="$1"
    local key="$2"

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    awk -v key="$key" '
        /^[a-zA-Z_-]+:/ { in_section = ($0 ~ "^"key":") }
        in_section && /^  - / {
            sub(/^  - /, "")
            gsub(/^["'\''"]|["'\''"]$/, "")
            print
        }
        in_section && /^[a-zA-Z_-]+:/ && !($0 ~ "^"key":") { in_section = 0 }
    ' "$file"
}

# Check if a key exists in YAML
# Usage: yaml_has_key "file.yaml" "key"
yaml_has_key() {
    local file="$1"
    local key="$2"

    grep -qE "^${key}:" "$file" 2>/dev/null
}

#===============================================================================
# VERSION UTILITIES
#===============================================================================

# Compare semantic versions
# Returns: 0 if equal, 1 if first > second, 2 if first < second
version_compare() {
    local v1="$1"
    local v2="$2"

    if [[ "$v1" == "$v2" ]]; then
        return 0
    fi

    local i v1_parts v2_parts
    IFS=. read -ra v1_parts <<< "$v1"
    IFS=. read -ra v2_parts <<< "$v2"

    for ((i=0; i<${#v1_parts[@]} || i<${#v2_parts[@]}; i++)); do
        local n1=${v1_parts[i]:-0}
        local n2=${v2_parts[i]:-0}

        if ((n1 > n2)); then
            return 1
        elif ((n1 < n2)); then
            return 2
        fi
    done

    return 0
}

# Check if installed binary matches expected version
# Usage: check_binary_version "/path/to/binary" "expected_version" [version_flag]
check_binary_version() {
    local binary="$1"
    local expected_version="$2"
    local version_flag="${3:---version}"

    if [[ ! -x "$binary" ]]; then
        return 1
    fi

    local current_version
    current_version=$("$binary" "$version_flag" 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

    if [[ "$current_version" == "$expected_version" ]]; then
        return 0
    fi
    return 1
}

#===============================================================================
# FILE UTILITIES
#===============================================================================

# Check config file differences and prompt for overwrite
# Usage: check_config_diff "existing_file" "new_content" "description"
# Returns: 0 if should overwrite, 1 if should skip
check_config_diff() {
    local existing_file="$1"
    local new_content="$2"
    local description="$3"
    local force_mode="${FORCE_MODE:-false}"

    # If file doesn't exist, proceed with creation
    if [[ ! -f "$existing_file" ]]; then
        log_info "$description: file does not exist, will create"
        return 0
    fi

    # Create temp file with new content
    local temp_file
    temp_file=$(mktemp)
    printf '%s\n' "$new_content" > "$temp_file"

    # Check if files are different
    if diff -q "$existing_file" "$temp_file" > /dev/null 2>&1; then
        log_skip "$description - no changes needed"
        rm -f "$temp_file"
        return 1
    fi

    # Files are different - show diff and prompt
    echo ""
    log_warn "$description has changes:"
    echo -e "${YELLOW}--- Current (deployed)${NC}"
    echo -e "${GREEN}+++ New (from script)${NC}"
    diff --color=always -u "$existing_file" "$temp_file" 2>/dev/null || diff -u "$existing_file" "$temp_file"
    echo ""

    rm -f "$temp_file"

    # In force mode, always overwrite
    if [[ "$force_mode" == "true" ]]; then
        log_info "Force mode: overwriting $description"
        return 0
    fi

    # Prompt user
    read -p "Overwrite $description? [Y/n] " -n 1 -r
    echo
    if [[ "$REPLY" =~ ^[Nn]$ ]]; then
        log_skip "Keeping existing $description"
        return 1
    fi

    return 0
}

# Write config only if user approves (or force mode)
# Usage: write_config_with_check "file_path" "content" "description"
write_config_with_check() {
    local file_path="$1"
    local content="$2"
    local description="$3"

    if check_config_diff "$file_path" "$content" "$description"; then
        printf '%s\n' "$content" > "$file_path"
        log_success "Updated $description"
        return 0
    fi
    return 1
}

# Ensure directory exists with proper permissions
# Usage: ensure_dir "/path/to/dir" [owner] [group] [mode]
ensure_dir() {
    local path="$1"
    local owner="${2:-root}"
    local group="${3:-root}"
    local mode="${4:-0755}"

    if [[ ! -d "$path" ]]; then
        mkdir -p "$path"
        log_debug "Created directory: $path"
    fi

    chown "$owner:$group" "$path"
    chmod "$mode" "$path"
}

#===============================================================================
# NETWORK UTILITIES
#===============================================================================

# Check if a port is open/listening
# Usage: check_port "host" "port" [timeout]
check_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-2}"

    timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null
}

# Wait for a service to become available
# Usage: wait_for_service "host" "port" [max_attempts] [delay]
wait_for_service() {
    local host="$1"
    local port="$2"
    local max_attempts="${3:-30}"
    local delay="${4:-1}"

    local attempt=1
    while ! check_port "$host" "$port"; do
        if (( attempt >= max_attempts )); then
            log_error "Service $host:$port not available after $max_attempts attempts"
            return 1
        fi
        log_debug "Waiting for $host:$port (attempt $attempt/$max_attempts)..."
        sleep "$delay"
        ((attempt++))
    done

    log_debug "Service $host:$port is available"
    return 0
}

#===============================================================================
# PROCESS UTILITIES
#===============================================================================

# Safely stop a service and wait for it
# Usage: safe_stop_service "service_name"
safe_stop_service() {
    local service_name="$1"

    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        systemctl stop "$service_name"
        sleep 1
    fi

    # Kill any remaining processes
    pkill -f "$service_name" 2>/dev/null || true
    sleep 1
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_fatal "This script must be run as root"
    fi
}

#===============================================================================
# TEMPLATE UTILITIES
#===============================================================================

# Simple template variable substitution
# Usage: template_render "template_content" "VAR1=value1" "VAR2=value2"
template_render() {
    local content="$1"
    shift

    for var in "$@"; do
        local key="${var%%=*}"
        local value="${var#*=}"
        content="${content//\$\{$key\}/$value}"
        content="${content//\$$key/$value}"
    done

    echo "$content"
}

# Render a template file
# Usage: template_render_file "/path/to/template" "VAR1=value1" "VAR2=value2"
template_render_file() {
    local template_file="$1"
    shift

    if [[ ! -f "$template_file" ]]; then
        log_error "Template file not found: $template_file"
        return 1
    fi

    local content
    content=$(<"$template_file")
    template_render "$content" "$@"
}
