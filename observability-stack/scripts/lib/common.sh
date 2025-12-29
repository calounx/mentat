#!/bin/bash
#===============================================================================
# Common Library Functions
# Shared utilities for the observability stack module system
#===============================================================================

# Guard against multiple sourcing
[[ -n "${COMMON_SH_LOADED:-}" ]] && return 0
COMMON_SH_LOADED=1

#===============================================================================
# EXIT CODES
#===============================================================================
readonly E_SUCCESS=0
readonly E_GENERAL=1
readonly E_MODULE_NOT_FOUND=2
readonly E_VALIDATION_FAILED=3
readonly E_INSTALL_FAILED=4
readonly E_PERMISSION_DENIED=5
readonly E_CONFIG_ERROR=6
readonly E_NETWORK_ERROR=7

#===============================================================================
# PATH CONSTANTS
#===============================================================================
readonly INSTALL_BIN_DIR="${INSTALL_BIN_DIR:-/usr/local/bin}"
readonly CONFIG_BASE_DIR="${CONFIG_BASE_DIR:-/etc}"
readonly DATA_BASE_DIR="${DATA_BASE_DIR:-/var/lib}"
readonly LOG_BASE_DIR="${LOG_BASE_DIR:-/var/log}"
readonly SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"

# Observability stack specific paths
readonly OBSERVABILITY_LOG_FILE="${OBSERVABILITY_LOG_FILE:-${LOG_BASE_DIR}/observability-setup.log}"
readonly OBSERVABILITY_LOG_MAX_SIZE="${OBSERVABILITY_LOG_MAX_SIZE:-10485760}"  # 10MB

# Colors
readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[1;33m'
readonly BLUE=$'\033[0;34m'
readonly CYAN=$'\033[0;36m'
readonly NC=$'\033[0m'

#===============================================================================
# LOGGING FUNCTIONS
#===============================================================================

# Rotate log file if it exceeds max size
# Usage: _rotate_log_if_needed
_rotate_log_if_needed() {
    if [[ -f "$OBSERVABILITY_LOG_FILE" ]]; then
        local size
        size=$(stat -f%z "$OBSERVABILITY_LOG_FILE" 2>/dev/null || stat -c%s "$OBSERVABILITY_LOG_FILE" 2>/dev/null || echo "0")
        if [[ "$size" -gt "$OBSERVABILITY_LOG_MAX_SIZE" ]]; then
            local timestamp
            timestamp=$(date +%Y%m%d_%H%M%S)
            mv "$OBSERVABILITY_LOG_FILE" "${OBSERVABILITY_LOG_FILE}.${timestamp}"
            gzip "${OBSERVABILITY_LOG_FILE}.${timestamp}" 2>/dev/null || true
        fi
    fi
}

# Log to file with timestamp
# Usage: _log_to_file "LEVEL" "message"
_log_to_file() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Ensure log directory exists
    if [[ -n "$OBSERVABILITY_LOG_FILE" ]]; then
        local log_dir
        log_dir=$(dirname "$OBSERVABILITY_LOG_FILE")
        mkdir -p "$log_dir" 2>/dev/null || true

        # Rotate if needed
        _rotate_log_if_needed

        # Write to log file
        printf '[%s] [%s] %s\n' "$timestamp" "$level" "$message" >> "$OBSERVABILITY_LOG_FILE" 2>/dev/null || true
    fi
}

# Log informational message
# Usage: log_info "message"
# Parameters:
#   $1 - Message to log
# Returns: 0 (E_SUCCESS)
log_info() {
    local message="$1"
    echo "${BLUE}[INFO]${NC} ${message}"
    _log_to_file "INFO" "$message"
}

# Log success message
# Usage: log_success "message"
# Parameters:
#   $1 - Message to log
# Returns: 0 (E_SUCCESS)
log_success() {
    local message="$1"
    echo "${GREEN}[SUCCESS]${NC} ${message}"
    _log_to_file "SUCCESS" "$message"
}

# Log skip message
# Usage: log_skip "message"
# Parameters:
#   $1 - Message to log
# Returns: 0 (E_SUCCESS)
log_skip() {
    local message="$1"
    echo "${GREEN}[SKIP]${NC} ${message}"
    _log_to_file "SKIP" "$message"
}

# Log warning message
# Usage: log_warn "message"
# Parameters:
#   $1 - Message to log
# Returns: 0 (E_SUCCESS)
log_warn() {
    local message="$1"
    echo "${YELLOW}[WARN]${NC} ${message}" >&2
    _log_to_file "WARN" "$message"
}

# Log error message
# Usage: log_error "message"
# Parameters:
#   $1 - Message to log
# Returns: 0 (E_SUCCESS) - does not exit
log_error() {
    local message="$1"
    echo "${RED}[ERROR]${NC} ${message}" >&2
    _log_to_file "ERROR" "$message"
}

# Log fatal error and exit
# Usage: log_fatal "message" [exit_code]
# Parameters:
#   $1 - Message to log
#   $2 - Exit code (optional, defaults to E_GENERAL)
# Returns: Does not return, exits with specified code
log_fatal() {
    local message="$1"
    local exit_code="${2:-$E_GENERAL}"
    echo "${RED}[FATAL]${NC} ${message}" >&2
    _log_to_file "FATAL" "$message"
    exit "$exit_code"
}

# Log debug message (only if DEBUG=true)
# Usage: log_debug "message"
# Parameters:
#   $1 - Message to log
# Returns: 0 (E_SUCCESS)
log_debug() {
    local message="$1"
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo "${CYAN}[DEBUG]${NC} ${message}"
        _log_to_file "DEBUG" "$message"
    fi
}

#===============================================================================
# PATH UTILITIES
#===============================================================================

# Get the absolute path of the observability stack root directory
# Usage: get_stack_root
# Returns: Absolute path to stack root (2 levels up from this script)
# Exit codes: 0 (E_SUCCESS)
# Example:
#   ROOT=$(get_stack_root)
#   echo "Stack root: $ROOT"
get_stack_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "$script_dir/../.." && pwd
}

# Get the modules directory path
# Usage: get_modules_dir
# Returns: Absolute path to modules directory
# Exit codes: 0 (E_SUCCESS)
# Example:
#   MODULES=$(get_modules_dir)
get_modules_dir() {
    echo "$(get_stack_root)/modules"
}

# Get the config directory path
# Usage: get_config_dir
# Returns: Absolute path to config directory
# Exit codes: 0 (E_SUCCESS)
# Example:
#   CONFIG=$(get_config_dir)
get_config_dir() {
    echo "$(get_stack_root)/config"
}

# Get the hosts config directory path
# Usage: get_hosts_config_dir
# Returns: Absolute path to hosts config directory
# Exit codes: 0 (E_SUCCESS)
# Example:
#   HOSTS_DIR=$(get_hosts_config_dir)
get_hosts_config_dir() {
    echo "$(get_stack_root)/config/hosts"
}

#===============================================================================
#===============================================================================
# FILE OPERATIONS
#===============================================================================

# Atomically write content to a file (using temp file + move)
# Usage: atomic_write "file_path" "content"
# Parameters:
#   $1 - Target file path
#   $2 - Content to write
# Returns: 0 on success, E_GENERAL on failure
# Example:
#   atomic_write "/etc/myapp/config.txt" "config_content_here"
atomic_write() {
    local target_file="$1"
    local content="$2"
    local temp_file

    # Create temp file in same directory as target (ensures same filesystem)
    local target_dir
    target_dir=$(dirname "$target_file")
    temp_file=$(mktemp "${target_dir}/.tmp.XXXXXX") || {
        log_error "Failed to create temporary file in $target_dir"
        return "$E_GENERAL"
    }

    # Write content to temp file
    if ! printf '%s\n' "$content" > "$temp_file"; then
        log_error "Failed to write to temporary file $temp_file"
        rm -f "$temp_file"
        return "$E_GENERAL"
    fi

    # Atomic move (on same filesystem, this is atomic)
    if ! mv "$temp_file" "$target_file"; then
        log_error "Failed to move $temp_file to $target_file"
        rm -f "$temp_file"
        return "$E_GENERAL"
    fi

    return "$E_SUCCESS"
}

# INPUT VALIDATION FUNCTIONS
#===============================================================================

# Validate IPv4 address format
# Usage: validate_ip "ip_address"
# Parameters:
#   $1 - IP address to validate
# Returns: 0 if valid, E_VALIDATION_FAILED if invalid
# Example:
#   if validate_ip "192.168.1.1"; then
#       echo "Valid IP"
#   fi
validate_ip() {
    local ip="$1"
    local stat=1

    if [[ -z "$ip" ]]; then
        return "$E_VALIDATION_FAILED"
    fi

    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local -a octets
        IFS='.' read -ra octets <<< "$ip"
        if [[ ${octets[0]} -le 255 && ${octets[1]} -le 255 && \
              ${octets[2]} -le 255 && ${octets[3]} -le 255 ]]; then
            stat=0
        fi
    fi

    return "$stat"
}

# Validate port number (1-65535)
# Usage: validate_port "port_number"
# Parameters:
#   $1 - Port number to validate
# Returns: 0 if valid, E_VALIDATION_FAILED if invalid
# Example:
#   if validate_port 8080; then
#       echo "Valid port"
#   fi
validate_port() {
    local port="$1"

    if [[ -z "$port" ]]; then
        return "$E_VALIDATION_FAILED"
    fi

    if [[ "$port" =~ ^[0-9]+$ ]] && [[ "$port" -ge 1 ]] && [[ "$port" -le 65535 ]]; then
        return "$E_SUCCESS"
    fi

    return "$E_VALIDATION_FAILED"
}

# Validate hostname/domain format
# Usage: validate_hostname "hostname"
# Parameters:
#   $1 - Hostname to validate
# Returns: 0 if valid, E_VALIDATION_FAILED if invalid
# Example:
#   if validate_hostname "example.com"; then
#       echo "Valid hostname"
#   fi
validate_hostname() {
    local hostname="$1"

    if [[ -z "$hostname" ]]; then
        return "$E_VALIDATION_FAILED"
    fi

    # Basic hostname/FQDN validation
    if [[ "$hostname" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        return "$E_SUCCESS"
    fi

    return "$E_VALIDATION_FAILED"
}

# Validate path exists and is safe (no path traversal)
# Usage: validate_path "path" [must_exist]
# Parameters:
#   $1 - Path to validate
#   $2 - If "true", path must exist (optional, default: false)
# Returns: 0 if valid, E_VALIDATION_FAILED if invalid
# Example:
#   if validate_path "/etc/config" "true"; then
#       echo "Path exists and is valid"
#   fi
validate_path() {
    local path="$1"
    local must_exist="${2:-false}"

    if [[ -z "$path" ]]; then
        return "$E_VALIDATION_FAILED"
    fi

    # Check for path traversal attempts
    if [[ "$path" =~ \.\. ]]; then
        log_error "Path validation failed: path traversal detected in '$path'"
        return "$E_VALIDATION_FAILED"
    fi

    # Check if path must exist
    if [[ "$must_exist" == "true" ]] && [[ ! -e "$path" ]]; then
        return "$E_VALIDATION_FAILED"
    fi

    return "$E_SUCCESS"
}

# Validate email address format (basic)
# Usage: validate_email "email"
# Parameters:
#   $1 - Email address to validate
# Returns: 0 if valid, E_VALIDATION_FAILED if invalid
# Example:
#   if validate_email "user@example.com"; then
#       echo "Valid email"
#   fi
validate_email() {
    local email="$1"

    if [[ -z "$email" ]]; then
        return "$E_VALIDATION_FAILED"
    fi

    # Basic email validation
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return "$E_SUCCESS"
    fi

    return "$E_VALIDATION_FAILED"
}

#===============================================================================
# YAML PARSING UTILITIES
# Robust YAML parsing with intelligent fallback (yq -> python -> awk)
# Source the new yaml-parser library for all YAML operations
#===============================================================================

# Source the YAML parser library
_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${YAML_PARSER_LOADED:-}" ]]; then
    # Prevent circular dependency by temporarily marking common as loaded
    _COMMON_WAS_LOADED="${COMMON_SH_LOADED:-}"
    COMMON_SH_LOADED=1
    source "$_COMMON_DIR/yaml-parser.sh"
    if [[ -z "$_COMMON_WAS_LOADED" ]]; then
        unset COMMON_SH_LOADED
    fi
fi

# Backward compatibility wrapper for yaml_get
# Other YAML functions (yaml_get_nested, yaml_get_deep, yaml_get_array, yaml_has_key)
# are now provided by yaml-parser.sh which was sourced above

# Get a simple key: value from a YAML file
# Usage: yaml_get "file.yaml" "key"
# DEPRECATED: Use yaml_get_value from yaml-parser.sh
yaml_get() {
    if [[ "${YAML_DEPRECATION_WARNINGS:-false}" == "true" ]]; then
        log_debug "DEPRECATED: yaml_get() - use yaml_get_value() instead"
    fi
    yaml_get_value "$@"
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
# Parameters:
#   $1 - Path to existing file
#   $2 - New content to compare
#   $3 - Description for user prompts
# Returns: 0 if should overwrite, 1 if should skip
# Exit codes: 0 or 1
# Example:
#   if check_config_diff "/etc/app/config" "$new_config" "App configuration"; then
#       echo "User approved overwrite"
#   fi
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

    # Create temp file with new content - separate declare and assign
    local temp_file
    temp_file=$(mktemp)
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create temporary file"
        return "$E_GENERAL"
    fi
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
    echo "${YELLOW}--- Current (deployed)${NC}"
    echo "${GREEN}+++ New (from script)${NC}"
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

# Check if a port is available (not in use)
# Usage: check_port_available "port"
# Returns: 0 if port is available, 1 if in use
check_port_available() {
    local port="$1"

    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        log_error "Invalid port number: $port"
        return 1
    fi

    # Check using ss (more reliable than netstat)
    if command -v ss &>/dev/null; then
        if ss -tln 2>/dev/null | grep -q ":${port}\s"; then
            log_error "Port $port is already in use"
            # Show what's using the port
            log_info "Port $port is being used by:"
            ss -tlnp 2>/dev/null | grep ":${port}\s" || true
            return 1
        fi
    # Fallback to netstat
    elif command -v netstat &>/dev/null; then
        if netstat -tln 2>/dev/null | grep -q ":${port}\s"; then
            log_error "Port $port is already in use"
            log_info "Port $port is being used by:"
            netstat -tlnp 2>/dev/null | grep ":${port}\s" || true
            return 1
        fi
    # Fallback to lsof
    elif command -v lsof &>/dev/null; then
        if lsof -i ":${port}" -sTCP:LISTEN &>/dev/null; then
            log_error "Port $port is already in use"
            log_info "Port $port is being used by:"
            lsof -i ":${port}" -sTCP:LISTEN || true
            return 1
        fi
    else
        log_warn "No port checking utility available (ss, netstat, or lsof), skipping port check"
        return 0
    fi

    log_debug "Port $port is available"
    return 0
}

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

# H-7: Stop service with robust 3-layer verification before binary replacement
# SECURITY: Ensures service is fully stopped before replacing binaries
#
# Three-layer protection:
#   Layer 1: Graceful systemd stop with timeout
#   Layer 2: SIGTERM for stubborn processes
#   Layer 3: SIGKILL for hung processes (last resort)
#
# Arguments:
#   $1 - Service name (for systemd)
#   $2 - Binary path (for process verification)
#   $3 - Optional: Max wait time in seconds (default: 30)
#
# Returns:
#   0 on success (service fully stopped)
#   1 on failure (service could not be stopped)
#
# Usage:
#   stop_and_verify_service "prometheus" "/usr/local/bin/prometheus"
#   stop_and_verify_service "loki" "/usr/local/bin/loki" 60
stop_and_verify_service() {
    local service_name="$1"
    local binary_path="$2"
    local max_wait="${3:-30}"

    log_info "Stopping $service_name service..."

    # LAYER 1: Graceful systemd stop
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        log_debug "Sending systemd stop signal to $service_name..."
        systemctl stop "$service_name"

        # Wait for graceful shutdown with timeout
        local wait_count=0
        while pgrep -f "$binary_path" >/dev/null 2>&1 && [[ $wait_count -lt $max_wait ]]; do
            if [[ $((wait_count % 5)) -eq 0 ]]; then
                log_info "Waiting for $service_name to stop gracefully... ($wait_count/$max_wait)"
            fi
            sleep 1
            ((wait_count++))
        done

        # Check if graceful stop succeeded
        if ! pgrep -f "$binary_path" >/dev/null 2>&1; then
            log_success "$service_name stopped gracefully"
            return 0
        fi
    fi

    # LAYER 2: SIGTERM for processes that didn't respond to systemd
    if pgrep -f "$binary_path" >/dev/null 2>&1; then
        log_warn "$service_name did not stop gracefully, sending SIGTERM..."
        pkill -TERM -f "$binary_path" 2>/dev/null || true

        # Wait for SIGTERM to take effect
        local term_wait=10
        local term_count=0
        while pgrep -f "$binary_path" >/dev/null 2>&1 && [[ $term_count -lt $term_wait ]]; do
            sleep 1
            ((term_count++))
        done

        # Check if SIGTERM succeeded
        if ! pgrep -f "$binary_path" >/dev/null 2>&1; then
            log_success "$service_name stopped after SIGTERM"
            return 0
        fi
    fi

    # LAYER 3: SIGKILL for hung processes (last resort)
    if pgrep -f "$binary_path" >/dev/null 2>&1; then
        log_error "$service_name did not respond to SIGTERM, sending SIGKILL (last resort)..."
        pkill -9 -f "$binary_path" 2>/dev/null || true
        sleep 2

        # Final verification
        if pgrep -f "$binary_path" >/dev/null 2>&1; then
            log_error "CRITICAL: Failed to stop $service_name even with SIGKILL!"
            log_error "Manual intervention required. Do NOT proceed with binary replacement."
            log_error "Process IDs still running:"
            pgrep -a -f "$binary_path" || true
            return 1
        fi

        log_warn "$service_name forcefully killed with SIGKILL"
    fi

    log_success "$service_name stopped and verified (no processes remaining)"
    return 0
}

# Check if running as root
# Usage: check_root
# Returns: Does not return if not root (calls log_fatal)
# Exit codes: E_PERMISSION_DENIED if not root
# Example:
#   check_root  # Exits if not root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_fatal "This script must be run as root" "$E_PERMISSION_DENIED"
    fi
}

#===============================================================================
# CLEANUP AND TRAP HELPERS
#===============================================================================

# Array to track temporary files for cleanup
declare -a _CLEANUP_TEMP_FILES=()

# Array to track cleanup functions to call
declare -a _CLEANUP_FUNCTIONS=()

# Register a temporary file for automatic cleanup
# Usage: register_temp_file "/path/to/temp/file"
# Parameters:
#   $1 - Path to temporary file
# Returns: 0 (E_SUCCESS)
# Example:
#   temp=$(mktemp)
#   register_temp_file "$temp"
register_temp_file() {
    local file="$1"
    _CLEANUP_TEMP_FILES+=("$file")
}

# Register a cleanup function to be called on exit
# Usage: register_cleanup_function "function_name"
# Parameters:
#   $1 - Name of function to call on exit
# Returns: 0 (E_SUCCESS)
# Example:
#   my_cleanup() {
#       # cleanup code
#   }
#   register_cleanup_function "my_cleanup"
register_cleanup_function() {
    local func="$1"
    _CLEANUP_FUNCTIONS+=("$func")
}

# Cleanup function called on EXIT
# This is an internal function, do not call directly
_cleanup_on_exit() {
    local exit_code=$?

    # Call registered cleanup functions
    for func in "${_CLEANUP_FUNCTIONS[@]}"; do
        if declare -f "$func" > /dev/null; then
            "$func" || true
        fi
    done

    # Clean up temporary files
    for file in "${_CLEANUP_TEMP_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file" 2>/dev/null || true
        fi
    done

    return "$exit_code"
}

# Setup cleanup traps for a script
# Usage: setup_cleanup_traps
# Returns: 0 (E_SUCCESS)
# Example:
#   setup_cleanup_traps
#   # Now EXIT, INT, TERM, ERR will trigger cleanup
setup_cleanup_traps() {
    trap _cleanup_on_exit EXIT INT TERM ERR
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

#===============================================================================
# SECURITY - CREDENTIAL VALIDATION
#===============================================================================

# SECURITY: Validate credentials to prevent use of default/weak passwords
# Usage: validate_credentials "username" "password" ["description"]
# Returns: 0 if valid, 1 if invalid (with error messages)
validate_credentials() {
    local username="$1"
    local password="$2"
    local description="${3:-credential}"
    local errors=()

    # SECURITY: Check for placeholder/default password patterns
    local -a FORBIDDEN_PATTERNS=(
        "CHANGE_ME"
        "YOUR_"
        "EXAMPLE"
        "PLACEHOLDER"
        "DEFAULT"
        "REPLACE_"
        "TODO"
        "FIXME"
        "PASSWORD"
        "SECRET"
        "changeme"
        "admin"
        "root"
        "test"
        "demo"
    )

    for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
        if [[ "$password" =~ $pattern ]]; then
            errors+=("Password contains forbidden placeholder pattern: $pattern")
            break
        fi
    done

    # SECURITY: Check minimum password complexity requirements
    # Requirement: 16+ characters, mixed case, numbers, and symbols
    local min_length=16

    if [[ ${#password} -lt $min_length ]]; then
        errors+=("Password must be at least $min_length characters (current: ${#password})")
    fi

    if ! [[ "$password" =~ [a-z] ]]; then
        errors+=("Password must contain lowercase letters")
    fi

    if ! [[ "$password" =~ [A-Z] ]]; then
        errors+=("Password must contain uppercase letters")
    fi

    if ! [[ "$password" =~ [0-9] ]]; then
        errors+=("Password must contain numbers")
    fi

    if ! [[ "$password" =~ [^a-zA-Z0-9] ]]; then
        errors+=("Password must contain special characters")
    fi

    # SECURITY: Validate username is not empty or default
    if [[ -z "$username" ]] || [[ "$username" == "CHANGE_ME" ]] || [[ "$username" == "YOUR_USER" ]]; then
        errors+=("Username cannot be empty or a placeholder")
    fi

    # Report validation results
    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "SECURITY: Credential validation failed for $description:"
        for error in "${errors[@]}"; do
            log_error "  - $error"
        done
        return 1
    fi

    log_debug "SECURITY: Credentials validated successfully for $description"
    return 0
}

# SECURITY: Check if a value appears to be a placeholder that needs changing
# Usage: is_placeholder "value"
# Returns: 0 if it's a placeholder, 1 if it appears to be a real value
is_placeholder() {
    local value="$1"

    local -a PLACEHOLDER_PATTERNS=(
        "CHANGE_ME"
        "YOUR_"
        "EXAMPLE"
        "PLACEHOLDER"
        "REPLACE_"
        "TODO"
        "FIXME"
    )

    for pattern in "${PLACEHOLDER_PATTERNS[@]}"; do
        if [[ "$value" =~ $pattern ]]; then
            return 0
        fi
    done

    return 1
}

#===============================================================================
# SECURITY - CHECKSUM VERIFICATION
#===============================================================================

# SECURITY: Download and verify file with SHA256 checksum
# Usage: download_and_verify "url" "output_file" "expected_checksum_or_url"
# Returns: 0 if download and verification successful, 1 otherwise
download_and_verify() {
    local url="$1"
    local output_file="$2"
    local checksum_source="$3"
    local expected_checksum=""
    local max_attempts=3
    local timeout_seconds=300

    log_info "SECURITY: Downloading with checksum verification: $(basename "$output_file")"

    # SECURITY: Only allow HTTPS URLs (except localhost for testing)
    if [[ ! "$url" =~ ^https:// ]] && [[ ! "$url" =~ ^http://localhost ]]; then
        log_error "SECURITY: Only HTTPS URLs are allowed: $url"
        return 1
    fi

    # Download the file with retry logic
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if [[ $attempt -gt 1 ]]; then
            log_info "Retry attempt $attempt/$max_attempts..."
            sleep 2
        fi

        if timeout "$timeout_seconds" wget \
            --quiet \
            --show-progress \
            --progress=bar:force:noscroll \
            --tries=1 \
            --timeout=30 \
            --dns-timeout=10 \
            --connect-timeout=10 \
            --read-timeout=30 \
            -O "$output_file" \
            "$url"; then
            break
        fi

        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log_warn "Download timed out (attempt $attempt/$max_attempts)"
        else
            log_warn "Download failed (attempt $attempt/$max_attempts)"
        fi

        rm -f "$output_file"
        ((attempt++))
    done

    if [[ $attempt -gt $max_attempts ]]; then
        log_error "SECURITY: Failed to download from $url after $max_attempts attempts"
        return 1
    fi

    # Determine if checksum_source is a URL or direct checksum
    if [[ "$checksum_source" =~ ^https?:// ]]; then
        # Download checksum file
        local checksum_file
        checksum_file=$(mktemp)

        if ! wget -q "$checksum_source" -O "$checksum_file"; then
            log_error "SECURITY: Failed to download checksum from $checksum_source"
            rm -f "$checksum_file" "$output_file"
            return 1
        fi

        # Extract checksum for our file
        local basename_file
        basename_file=$(basename "$output_file")

        # Try to find checksum in various formats
        if grep -q "$basename_file" "$checksum_file"; then
            expected_checksum=$(grep "$basename_file" "$checksum_file" | awk '{print $1}')
        else
            # If filename not in checksum file, try to extract from URL
            local url_basename
            url_basename=$(basename "$url")
            if grep -q "$url_basename" "$checksum_file"; then
                expected_checksum=$(grep "$url_basename" "$checksum_file" | awk '{print $1}')
            fi
        fi

        rm -f "$checksum_file"
    else
        # Direct checksum provided
        expected_checksum="$checksum_source"
    fi

    # SECURITY: Verify we got a checksum
    if [[ -z "$expected_checksum" ]]; then
        log_error "SECURITY: No checksum available for verification"
        rm -f "$output_file"
        return 1
    fi

    # SECURITY: Calculate actual checksum
    local actual_checksum
    actual_checksum=$(sha256sum "$output_file" | awk '{print $1}')

    # SECURITY: Verify checksum matches
    if [[ "$actual_checksum" != "$expected_checksum" ]]; then
        log_error "SECURITY: Checksum verification FAILED!"
        log_error "  Expected: $expected_checksum"
        log_error "  Actual:   $actual_checksum"
        rm -f "$output_file"
        return 1
    fi

    log_success "SECURITY: Checksum verified successfully"
    return 0
}

#===============================================================================
# SECURITY - INPUT SANITIZATION
#===============================================================================

# SECURITY: Sanitize string for safe use in sed commands
# Escapes special sed characters to prevent injection attacks
# Usage: sanitize_for_sed "input_string"
sanitize_for_sed() {
    local input="$1"

    # SECURITY: Escape special characters that have meaning in sed
    # & is replacement string reference
    # \ is escape character
    # / is default delimiter
    # | is alternative delimiter
    # newline can break sed commands

    input="${input//\\/\\\\}"  # Escape backslashes first
    input="${input//&/\\&}"    # Escape ampersands
    input="${input//\//\\/}"   # Escape forward slashes
    input="${input//|/\\|}"    # Escape pipes
    input="${input//$'\n'/\\n}" # Escape newlines

    echo "$input"
}

#===============================================================================
# SECURITY - SAFE FILE OPERATIONS
#===============================================================================

# SECURITY: Safe chown that validates user/group exist first
# Usage: safe_chown "user:group" "path"
# Returns: 0 if successful, 1 if validation fails
safe_chown() {
    local usergroup="$1"
    local path="$2"
    local user group

    # Parse user:group
    if [[ "$usergroup" =~ : ]]; then
        user="${usergroup%%:*}"
        group="${usergroup##*:}"
    else
        user="$usergroup"
        group="$usergroup"
    fi

    # SECURITY: Validate user exists
    if ! id "$user" &>/dev/null; then
        log_error "SECURITY: Cannot chown - user '$user' does not exist"
        return 1
    fi

    # SECURITY: Validate group exists
    if ! getent group "$group" &>/dev/null; then
        log_error "SECURITY: Cannot chown - group '$group' does not exist"
        return 1
    fi

    # SECURITY: Validate path exists
    if [[ ! -e "$path" ]]; then
        log_error "SECURITY: Cannot chown - path '$path' does not exist"
        return 1
    fi

    # Execute chown and log
    chown "$usergroup" "$path"
    log_debug "SECURITY: Changed ownership of $path to $usergroup"
    return 0
}

# SECURITY: Safe chmod that validates permissions and logs changes
# Usage: safe_chmod "mode" "path" ["description"]
# Returns: 0 if successful, 1 if validation fails
safe_chmod() {
    local mode="$1"
    local path="$2"
    local description="${3:-$path}"

    # SECURITY: Validate mode is numeric octal
    if ! [[ "$mode" =~ ^[0-7]{3,4}$ ]]; then
        log_error "SECURITY: Invalid chmod mode '$mode' (must be octal like 644 or 0755)"
        return 1
    fi

    # SECURITY: Validate path exists
    if [[ ! -e "$path" ]]; then
        log_error "SECURITY: Cannot chmod - path '$path' does not exist"
        return 1
    fi

    # SECURITY: Warn about overly permissive modes
    if [[ "$mode" =~ 7$ ]] || [[ "$mode" =~ [0-9]7$ ]]; then
        log_warn "SECURITY: Setting world-writable permission $mode on $description"
    fi

    # Execute chmod and log
    chmod "$mode" "$path"
    log_debug "SECURITY: Changed permissions of $path to $mode"
    return 0
}

#===============================================================================
# SECURITY UTILITIES - Command Validation
#===============================================================================

# Validate and execute detection commands with strict allowlist
# Usage: validate_and_execute_detection_command "command_string"
# Returns: 0 if command succeeds and is allowed, 1 otherwise
validate_and_execute_detection_command() {
    local cmd="$1"
    local timeout_seconds=5

    # Remove leading/trailing whitespace
    cmd=$(echo "$cmd" | xargs)

    # Empty command is invalid
    if [[ -z "$cmd" ]]; then
        log_debug "Empty detection command"
        return 1
    fi

    # Extract the base command (first word)
    local base_cmd
    base_cmd=$(echo "$cmd" | awk '{print $1}')

    # SECURITY: Strict allowlist of permitted detection commands
    # Each command is safe for detection purposes and cannot cause harm
    local -A allowed_commands=(
        # File/directory checks
        ["test"]="1"
        ["["]="1"
        ["[["]="1"
        ["-f"]="1"
        ["-d"]="1"
        ["-e"]="1"
        ["-x"]="1"

        # Safe utilities
        ["which"]="1"
        ["command"]="1"
        ["type"]="1"

        # Process checks
        ["pgrep"]="1"
        ["pidof"]="1"

        # System utilities
        ["systemctl"]="1"
        ["service"]="1"

        # Package managers (read-only operations)
        ["dpkg"]="1"
        ["rpm"]="1"
        ["apt-cache"]="1"
        ["yum"]="1"
    )

    # Check if base command is in allowlist
    if [[ -z "${allowed_commands[$base_cmd]:-}" ]]; then
        log_debug "Detection command not in allowlist: $base_cmd"
        return 1
    fi

    # SECURITY: Block dangerous patterns even if base command is allowed
    # No command substitution: $() or ``
    if [[ "$cmd" =~ \$\( ]] || [[ "$cmd" =~ \` ]]; then
        log_debug "Command substitution not allowed in detection commands"
        return 1
    fi

    # No pipe chains (could bypass allowlist)
    if [[ "$cmd" =~ \| ]]; then
        log_debug "Pipe operators not allowed in detection commands"
        return 1
    fi

    # No command chaining with ; & or &&
    if [[ "$cmd" =~ \; ]] || [[ "$cmd" =~ \&\& ]] || [[ "$cmd" =~ \& ]]; then
        log_debug "Command chaining not allowed in detection commands"
        return 1
    fi

    # No redirects (>, >>, <)
    if [[ "$cmd" =~ \> ]] || [[ "$cmd" =~ \< ]]; then
        log_debug "Redirects not allowed in detection commands"
        return 1
    fi

    # Execute with timeout to prevent hanging
    # Suppress all output, only check exit code
    if timeout "$timeout_seconds" bash -c "$cmd" &>/dev/null; then
        log_debug "Detection command succeeded: $cmd"
        return 0
    else
        local exit_code=$?
        # 124 is timeout exit code
        if [[ $exit_code -eq 124 ]]; then
            log_debug "Detection command timed out: $cmd"
        else
            log_debug "Detection command failed: $cmd (exit: $exit_code)"
        fi
        return 1
    fi
}

#===============================================================================
# SECURITY UTILITIES - Input Validation
#===============================================================================

# Validate IPv4 address (RFC 791 compliant)
# Usage: is_valid_ip "192.168.1.1"
# Returns: 0 if valid, 1 if invalid
is_valid_ip() {
    local ip="$1"

    # Check basic format: four octets separated by dots
    if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 1
    fi

    # Validate each octet (0-255)
    local -a octets
    IFS='.' read -ra octets <<< "$ip"

    for octet in "${octets[@]}"; do
        # Remove leading zeros for arithmetic comparison
        octet=$((10#$octet))
        if [[ $octet -gt 255 ]]; then
            return 1
        fi
    done

    return 0
}

# Validate hostname (RFC 952/1123 compliant)
# Usage: is_valid_hostname "web-server-01.example.com"
# Returns: 0 if valid, 1 if invalid
is_valid_hostname() {
    local hostname="$1"

    # Length check: 1-253 characters
    if [[ ${#hostname} -lt 1 ]] || [[ ${#hostname} -gt 253 ]]; then
        return 1
    fi

    # RFC 952/1123 hostname validation:
    # - Labels separated by dots
    # - Each label: 1-63 chars, alphanumeric and hyphens
    # - Cannot start or end with hyphen
    # - Cannot start with digit (relaxed in RFC 1123, but we keep strict)
    if [[ ! "$hostname" =~ ^[a-zA-Z]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi

    return 0
}

# Validate semantic version string
# Usage: is_valid_version "1.2.3" or "2.0.0-beta.1"
# Returns: 0 if valid, 1 if invalid
is_valid_version() {
    local version="$1"

    # Semantic versioning 2.0.0 format: MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]
    # We support basic semver: X.Y.Z with optional prerelease and build metadata
    if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?(\+[a-zA-Z0-9.-]+)?$ ]]; then
        return 0
    fi

    return 1
}

#===============================================================================
# SECURITY UTILITIES - Secure Downloads
#===============================================================================

# SHA256 checksums for verified components
# Format: "version:checksum"
declare -gA COMPONENT_CHECKSUMS=(
    # Prometheus exporters
    ["node_exporter:1.7.0"]="a550cd5c05f760b7934a2d0afad66d2e92e681482f5f57a917465b1fba3b02a6"
    ["prometheus:2.48.1"]="9e4e3eda9be6a224089b1127e1b8d3f5632b7e4e8f99c93e33d0b08dda5f37d1"
    ["loki:2.9.3"]="to-be-added"  # Update with actual checksum
    ["grafana:latest"]="to-be-added"  # Update with actual checksum
    # Add more as needed
)

# Safe download function with SHA256 verification, retry logic, and timeout
# Usage: safe_download "url" "output_file" "component_name:version"
# Returns: 0 on success, 1 on failure
safe_download() {
    local url="$1"
    local output_file="$2"
    local component_key="${3:-}"  # Optional: component_name:version for checksum verification
    local max_attempts=3
    local timeout_seconds=300  # 5 minutes
    local attempt=1

    # Validate inputs
    if [[ -z "$url" ]] || [[ -z "$output_file" ]]; then
        log_error "safe_download: URL and output file are required"
        return 1
    fi

    # SECURITY: Only allow HTTPS URLs (except localhost for testing)
    if [[ ! "$url" =~ ^https:// ]] && [[ ! "$url" =~ ^http://localhost ]]; then
        log_error "safe_download: Only HTTPS URLs are allowed: $url"
        return 1
    fi

    log_info "Downloading: $url"

    # Retry loop
    while [[ $attempt -le $max_attempts ]]; do
        if [[ $attempt -gt 1 ]]; then
            log_info "Retry attempt $attempt/$max_attempts..."
            sleep 2
        fi

        # Download with timeout and progress bar
        if timeout "$timeout_seconds" wget \
            --quiet \
            --show-progress \
            --progress=bar:force:noscroll \
            --tries=1 \
            --timeout=30 \
            --dns-timeout=10 \
            --connect-timeout=10 \
            --read-timeout=30 \
            -O "$output_file" \
            "$url"; then

            # Download succeeded, now verify checksum if provided
            if [[ -n "$component_key" ]]; then
                local expected_checksum="${COMPONENT_CHECKSUMS[$component_key]:-}"

                if [[ -z "$expected_checksum" ]]; then
                    log_warn "No checksum defined for $component_key - skipping verification"
                    log_warn "SECURITY: This download is not verified! Update COMPONENT_CHECKSUMS in common.sh"
                elif [[ "$expected_checksum" == "to-be-added" ]]; then
                    log_warn "Checksum for $component_key needs to be added to common.sh"
                    log_warn "SECURITY: This download is not verified!"
                else
                    log_info "Verifying SHA256 checksum..."
                    local actual_checksum
                    actual_checksum=$(sha256sum "$output_file" | awk '{print $1}')

                    if [[ "$actual_checksum" == "$expected_checksum" ]]; then
                        log_success "Checksum verified"
                        return 0
                    else
                        log_error "CHECKSUM MISMATCH for $component_key!"
                        log_error "Expected: $expected_checksum"
                        log_error "Got:      $actual_checksum"
                        rm -f "$output_file"
                        return 1
                    fi
                fi
            fi

            # No checksum verification requested or skipped
            log_success "Download complete"
            return 0
        fi

        # Download failed
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log_warn "Download timed out (attempt $attempt/$max_attempts)"
        else
            log_warn "Download failed with exit code $exit_code (attempt $attempt/$max_attempts)"
        fi

        rm -f "$output_file"
        ((attempt++))
    done

    log_error "Failed to download after $max_attempts attempts: $url"
    return 1
}

#===============================================================================
# SECURITY UTILITIES - File Permissions
#===============================================================================

# Audit and report file permissions for sensitive files
# Usage: audit_file_permissions "/path/to/file" "expected_mode" "expected_owner:group"
# Returns: 0 if permissions match, 1 if they don't
audit_file_permissions() {
    local file_path="$1"
    local expected_mode="$2"
    local expected_owner="${3:-root:root}"

    if [[ ! -e "$file_path" ]]; then
        log_error "audit_file_permissions: File does not exist: $file_path"
        return 1
    fi

    # Get actual permissions
    local actual_mode
    actual_mode=$(stat -c '%a' "$file_path" 2>/dev/null || stat -f '%A' "$file_path" 2>/dev/null)

    local actual_owner
    actual_owner=$(stat -c '%U:%G' "$file_path" 2>/dev/null || stat -f '%Su:%Sg' "$file_path" 2>/dev/null)

    local issues=0

    # Check mode
    if [[ "$actual_mode" != "$expected_mode" ]]; then
        log_warn "Permission mismatch on $file_path: expected $expected_mode, got $actual_mode"
        ((issues++))
    fi

    # Check ownership
    if [[ "$actual_owner" != "$expected_owner" ]]; then
        log_warn "Ownership mismatch on $file_path: expected $expected_owner, got $actual_owner"
        ((issues++))
    fi

    if [[ $issues -eq 0 ]]; then
        log_debug "Permissions OK: $file_path ($actual_mode $actual_owner)"
        return 0
    fi

    return 1
}

# Secure file write with proper permissions
# Usage: secure_write "file_path" "content" "mode" "owner:group"
# Sets umask before writing and applies explicit permissions
secure_write() {
    local file_path="$1"
    local content="$2"
    local mode="${3:-600}"
    local owner="${4:-root:root}"

    # SECURITY: Set restrictive umask before creating file
    local old_umask
    old_umask=$(umask)
    umask 077

    # Write content
    printf '%s\n' "$content" > "$file_path"

    # Restore umask
    umask "$old_umask"

    # SECURITY: Set explicit permissions and ownership
    chmod "$mode" "$file_path"
    chown "$owner" "$file_path"

    log_debug "Secure write: $file_path ($mode $owner)"
}
#===============================================================================
# SECRETS MANAGEMENT
#===============================================================================

# Get the secrets directory path
# Usage: get_secrets_dir
# Returns: Absolute path to secrets directory
get_secrets_dir() {
    echo "$(get_stack_root)/secrets"
}

# Resolve a secret value using multiple fallback strategies
# SECURITY: Implements defense-in-depth secret resolution
#
# Resolution order:
#   1. Environment variable: OBSERVABILITY_SECRET_<NAME_UPPERCASE>
#   2. Secret file: secrets/<name>
#   3. Encrypted secret file: secrets/<name>.age or secrets/<name>.gpg (with decryption)
#
# Arguments:
#   $1 - Secret name (e.g., "smtp_password")
#   $2 - Optional: Silent mode (true/false) - suppress errors
#
# Returns:
#   Secret value on stdout, returns 0 on success, 1 on failure
#
# Security Features:
# - Never logs actual secret values (only length)
# - Validates secret file permissions (must be 600 or more restrictive)
# - Supports encrypted secrets with age/gpg
# - Environment variables take precedence for CI/CD flexibility
#
# Usage:
#   SMTP_PASS=$(resolve_secret "smtp_password")
#   if [[ $? -eq 0 ]]; then
#       use_password "$SMTP_PASS"
#   fi
resolve_secret() {
    local secret_name="$1"
    local silent_mode="${2:-false}"
    local secrets_dir
    secrets_dir="$(get_secrets_dir)"

    # Strategy 1: Check environment variable
    # Convention: OBSERVABILITY_SECRET_<SECRET_NAME_UPPERCASE>
    local env_var_name="OBSERVABILITY_SECRET_${secret_name^^}"
    env_var_name="${env_var_name//-/_}"  # Replace hyphens with underscores

    if [[ -n "${!env_var_name:-}" ]]; then
        log_debug "Resolved secret '$secret_name' from environment variable"
        echo "${!env_var_name}"
        return 0
    fi

    # Strategy 2: Check plaintext secret file
    local secret_file="$secrets_dir/$secret_name"
    if [[ -f "$secret_file" ]]; then
        # Security: Validate file permissions
        if ! validate_secret_file_permissions "$secret_file" "$silent_mode"; then
            if [[ "$silent_mode" != "true" ]]; then
                log_error "Secret file has insecure permissions: $secret_file"
                log_error "Fix with: chmod 600 $secret_file && chown root:root $secret_file"
            fi
            return 1
        fi

        log_debug "Resolved secret '$secret_name' from file ($(wc -c < "$secret_file") bytes)"
        cat "$secret_file"
        return 0
    fi

    # Strategy 3: Check encrypted secret file (age)
    if [[ -f "${secret_file}.age" ]]; then
        if command -v age &> /dev/null; then
            local age_key="${AGE_KEY_FILE:-$HOME/.config/age/key.txt}"
            if [[ -f "$age_key" ]]; then
                log_debug "Decrypting secret '$secret_name' with age"
                age -d -i "$age_key" "${secret_file}.age" 2>/dev/null && return 0
            fi
        fi
    fi

    # Strategy 4: Check encrypted secret file (gpg)
    if [[ -f "${secret_file}.gpg" ]]; then
        if command -v gpg &> /dev/null; then
            log_debug "Decrypting secret '$secret_name' with gpg"
            gpg --decrypt --quiet "${secret_file}.gpg" 2>/dev/null && return 0
        fi
    fi

    # Secret not found
    if [[ "$silent_mode" != "true" ]]; then
        log_error "Secret not found: $secret_name"
        log_error "Tried:"
        log_error "  - Environment variable: $env_var_name"
        log_error "  - Secret file: $secret_file"
        log_error "  - Encrypted files: ${secret_file}.age, ${secret_file}.gpg"
        log_error ""
        log_error "To fix:"
        log_error "  1. Run: ./scripts/init-secrets.sh"
        log_error "  2. Or set: export ${env_var_name}='your-secret'"
        log_error "  3. Or create: echo 'your-secret' > $secret_file && chmod 600 $secret_file"
    fi

    return 1
}

# Validate secret file has secure permissions
# SECURITY: Ensures secrets are only readable by owner (root)
#
# Arguments:
#   $1 - Secret file path
#   $2 - Optional: Silent mode (true/false)
#
# Returns:
#   0 if permissions are secure (600, 400, or more restrictive)
#   1 if permissions are insecure
validate_secret_file_permissions() {
    local secret_file="$1"
    local silent_mode="${2:-false}"

    # Get file permissions in octal
    local perms
    perms=$(stat -c "%a" "$secret_file" 2>/dev/null)

    # Check owner
    local owner
    owner=$(stat -c "%U" "$secret_file" 2>/dev/null)

    # Acceptable permissions: 600, 400 (owner read/write or read-only)
    # Group and other must have no permissions
    if [[ "$perms" =~ ^[4-6]00$ ]] && [[ "$owner" == "root" ]]; then
        return 0
    fi

    if [[ "$silent_mode" != "true" ]]; then
        log_warn "Insecure permissions on secret file: $secret_file"
        log_warn "Current: $perms (owner: $owner), Required: 600 (owner: root)"
    fi

    return 1
}

# Resolve a secret and validate it's not a placeholder
# Arguments:
#   $1 - Secret name
#   $2 - Optional: Silent mode
# Returns:
#   Secret value on stdout, returns 0 on success, 1 on failure
resolve_secret_validated() {
    local secret_name="$1"
    local silent_mode="${2:-false}"
    local secret_value

    secret_value=$(resolve_secret "$secret_name" "$silent_mode")
    local result=$?

    if [[ $result -ne 0 ]]; then
        return 1
    fi

    # Check if secret is a placeholder value
    if [[ "$secret_value" =~ ^(CHANGE_ME|YOUR_|REPLACE_|TODO|FIXME|XXX) ]]; then
        if [[ "$silent_mode" != "true" ]]; then
            log_error "Secret '$secret_name' contains placeholder value"
            log_error "Run ./scripts/init-secrets.sh to generate secure secrets"
        fi
        return 1
    fi

    # Check minimum length (at least 8 characters for any secret)
    if [[ ${#secret_value} -lt 8 ]]; then
        if [[ "$silent_mode" != "true" ]]; then
            log_error "Secret '$secret_name' is too short (${#secret_value} < 8 characters)"
        fi
        return 1
    fi

    echo "$secret_value"
    return 0
}

# Check if a secret exists (without revealing its value)
# Arguments:
#   $1 - Secret name
# Returns:
#   0 if secret exists and is valid, 1 otherwise
secret_exists() {
    local secret_name="$1"
    resolve_secret "$secret_name" "true" > /dev/null 2>&1
}

# Generate a secure random password
# SECURITY: Uses cryptographically secure random source
# Arguments:
#   $1 - Length (default: 32)
# Returns:
#   Random password on stdout
generate_secret() {
    local length="${1:-32}"

    # Use openssl for cryptographically secure random generation
    # Remove characters that might cause issues: /, +, =
    openssl rand -base64 "$((length * 2))" | tr -d '/+=' | head -c "$length"
}

# Store a secret securely
# SECURITY: Creates file with 600 permissions, owned by root
# Arguments:
#   $1 - Secret name
#   $2 - Secret value
# Returns:
#   0 on success, 1 on failure
store_secret() {
    local secret_name="$1"
    local secret_value="$2"
    local secrets_dir
    secrets_dir="$(get_secrets_dir)"
    local secret_file="$secrets_dir/$secret_name"

    # Ensure secrets directory exists
    ensure_dir "$secrets_dir" "root" "root" "0700"

    # Use umask to ensure file is created with 600 permissions
    local old_umask
    old_umask=$(umask)
    umask 0077

    # Write secret to file
    echo -n "$secret_value" > "$secret_file"

    # Restore umask
    umask "$old_umask"

    # Ensure proper ownership and permissions
    chown root:root "$secret_file"
    chmod 600 "$secret_file"

    log_debug "Stored secret: $secret_name (${#secret_value} bytes)"
    return 0
}

# Create htpasswd entry without exposing password in process args
# SECURITY: Uses stdin to pass password, never via command-line args
# Arguments:
#   $1 - Username
#   $2 - Password
#   $3 - Output file path
# Returns:
#   0 on success, 1 on failure
create_htpasswd_secure() {
    local username="$1"
    local password="$2"
    local output_file="$3"

    # SECURITY: Validate inputs to prevent injection
    if [[ -z "$username" ]] || [[ "$username" =~ [^a-zA-Z0-9_-] ]]; then
        log_error "Invalid username for htpasswd: $username"
        return 1
    fi

    if [[ -z "$password" ]]; then
        log_error "Empty password provided for htpasswd"
        return 1
    fi

    # SECURITY: Pass password via stdin to avoid process argument exposure
    # The -i flag reads password from stdin (bcrypt hash, -B flag implied in newer versions)
    echo "$password" | htpasswd -ci "$output_file" "$username" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        chmod 600 "$output_file"
        chown root:root "$output_file"
        log_debug "Created htpasswd entry for user: $username"
        return 0
    else
        log_error "Failed to create htpasswd entry"
        return 1
    fi
}
