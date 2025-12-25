#!/bin/bash
#===============================================================================
# Validation Library
# Comprehensive input validation, configuration validation, and prerequisite checking
#===============================================================================

# Guard against multiple sourcing
[[ -n "${VALIDATION_SH_LOADED:-}" ]] && return 0
VALIDATION_SH_LOADED=1

# Source dependencies
_VALIDATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${COMMON_SH_LOADED:-}" ]]; then
    source "$_VALIDATION_DIR/common.sh"
fi
if [[ -z "${ERRORS_SH_LOADED:-}" ]]; then
    source "$_VALIDATION_DIR/errors.sh"
fi

#===============================================================================
# INPUT VALIDATION - PRIMITIVES
#===============================================================================

# Validate integer
# Usage: validate_integer "value" [min] [max]
validate_integer() {
    local value="$1"
    local min="${2:-}"
    local max="${3:-}"

    if ! [[ "$value" =~ ^-?[0-9]+$ ]]; then
        error_report "Invalid integer: '$value'" "$E_VALIDATION_FAILED"
        return 1
    fi

    if [[ -n "$min" ]] && [[ $value -lt $min ]]; then
        error_report "Integer $value is less than minimum $min" "$E_VALIDATION_FAILED"
        return 1
    fi

    if [[ -n "$max" ]] && [[ $value -gt $max ]]; then
        error_report "Integer $value is greater than maximum $max" "$E_VALIDATION_FAILED"
        return 1
    fi

    return 0
}

# Validate positive integer
# Usage: validate_positive_integer "value" [max]
validate_positive_integer() {
    local value="$1"
    local max="${2:-}"

    validate_integer "$value" 1 "$max"
}

# Validate boolean value
# Usage: validate_boolean "value"
validate_boolean() {
    local value="$1"

    if [[ "$value" =~ ^(true|false|yes|no|1|0|on|off)$ ]]; then
        return 0
    fi

    error_report "Invalid boolean: '$value' (expected: true/false/yes/no/1/0/on/off)" "$E_VALIDATION_FAILED"
    return 1
}

# Validate string is not empty
# Usage: validate_not_empty "value" "field_name"
validate_not_empty() {
    local value="$1"
    local field_name="${2:-value}"

    if [[ -z "$value" ]]; then
        error_report "Field '$field_name' cannot be empty" "$E_VALIDATION_FAILED"
        return 1
    fi

    return 0
}

# Validate string length
# Usage: validate_length "value" [min_length] [max_length] "field_name"
validate_length() {
    local value="$1"
    local min_length="${2:-0}"
    local max_length="${3:-}"
    local field_name="${4:-value}"

    local length=${#value}

    if [[ $length -lt $min_length ]]; then
        error_report "Field '$field_name' is too short (min: $min_length, got: $length)" "$E_VALIDATION_FAILED"
        return 1
    fi

    if [[ -n "$max_length" ]] && [[ $length -gt $max_length ]]; then
        error_report "Field '$field_name' is too long (max: $max_length, got: $length)" "$E_VALIDATION_FAILED"
        return 1
    fi

    return 0
}

# Validate string matches regex pattern
# Usage: validate_pattern "value" "pattern" "description"
validate_pattern() {
    local value="$1"
    local pattern="$2"
    local description="${3:-pattern}"

    if [[ ! "$value" =~ $pattern ]]; then
        error_report "Value '$value' does not match $description" "$E_VALIDATION_FAILED"
        return 1
    fi

    return 0
}

# Validate value is in allowed list
# Usage: validate_in_list "value" "item1" "item2" "item3" ...
validate_in_list() {
    local value="$1"
    shift
    local allowed=("$@")

    for item in "${allowed[@]}"; do
        if [[ "$value" == "$item" ]]; then
            return 0
        fi
    done

    error_report "Invalid value '$value'. Allowed: ${allowed[*]}" "$E_VALIDATION_FAILED"
    return 1
}

#===============================================================================
# NETWORK VALIDATION
#===============================================================================

# Validate IPv4 address
# Usage: validate_ipv4 "ip_address"
validate_ipv4() {
    local ip="$1"
    local pattern='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

    if [[ ! "$ip" =~ $pattern ]]; then
        error_report "Invalid IPv4 address: '$ip'" "$E_VALIDATION_FAILED"
        return 1
    fi

    # Validate each octet is 0-255
    IFS='.' read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if [[ $octet -gt 255 ]]; then
            error_report "Invalid IPv4 address: '$ip' (octet $octet > 255)" "$E_VALIDATION_FAILED"
            return 1
        fi
    done

    return 0
}

# Validate IPv6 address (basic check)
# Usage: validate_ipv6 "ip_address"
validate_ipv6() {
    local ip="$1"
    local pattern='^([0-9a-fA-F]{0,4}:){7}[0-9a-fA-F]{0,4}$|^::$|^::1$'

    if [[ ! "$ip" =~ $pattern ]]; then
        error_report "Invalid IPv6 address: '$ip'" "$E_VALIDATION_FAILED"
        return 1
    fi

    return 0
}

# Validate IP address (IPv4 or IPv6)
# Usage: validate_ip "ip_address"
validate_ip() {
    local ip="$1"

    if validate_ipv4 "$ip" 2>/dev/null || validate_ipv6 "$ip" 2>/dev/null; then
        return 0
    fi

    error_report "Invalid IP address: '$ip'" "$E_VALIDATION_FAILED"
    return 1
}

# Validate port number
# Usage: validate_port "port"
validate_port() {
    local port="$1"

    if ! validate_integer "$port" 1 65535 2>/dev/null; then
        error_report "Invalid port: '$port' (must be 1-65535)" "$E_VALIDATION_FAILED"
        return 1
    fi

    return 0
}

# Validate hostname
# Usage: validate_hostname "hostname"
validate_hostname() {
    local hostname="$1"
    local pattern='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$'

    if [[ ! "$hostname" =~ $pattern ]]; then
        error_report "Invalid hostname: '$hostname'" "$E_VALIDATION_FAILED"
        return 1
    fi

    if [[ ${#hostname} -gt 253 ]]; then
        error_report "Hostname too long: '$hostname' (max 253 chars)" "$E_VALIDATION_FAILED"
        return 1
    fi

    return 0
}

# Validate domain name
# Usage: validate_domain "domain"
validate_domain() {
    local domain="$1"
    validate_hostname "$domain"
}

# Validate URL
# Usage: validate_url "url"
validate_url() {
    local url="$1"
    local pattern='^https?://[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*'

    if [[ ! "$url" =~ $pattern ]]; then
        error_report "Invalid URL: '$url'" "$E_VALIDATION_FAILED"
        return 1
    fi

    return 0
}

# Validate email address
# Usage: validate_email "email"
validate_email() {
    local email="$1"
    local pattern='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'

    if [[ ! "$email" =~ $pattern ]]; then
        error_report "Invalid email address: '$email'" "$E_VALIDATION_FAILED"
        return 1
    fi

    return 0
}

# Validate CIDR notation
# Usage: validate_cidr "cidr"
validate_cidr() {
    local cidr="$1"

    if [[ ! "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        error_report "Invalid CIDR notation: '$cidr'" "$E_VALIDATION_FAILED"
        return 1
    fi

    local ip="${cidr%/*}"
    local mask="${cidr#*/}"

    validate_ipv4 "$ip" || return 1
    validate_integer "$mask" 0 32 || return 1

    return 0
}

#===============================================================================
# FILE SYSTEM VALIDATION
#===============================================================================

# Validate path exists
# Usage: validate_path_exists "path" "description"
validate_path_exists() {
    local path="$1"
    local description="${2:-path}"

    if [[ ! -e "$path" ]]; then
        error_report "Path does not exist: $description ($path)" "$E_NOT_FOUND"
        return 1
    fi

    return 0
}

# Validate file exists
# Usage: validate_file_exists "file" "description"
validate_file_exists() {
    local file="$1"
    local description="${2:-file}"

    if [[ ! -f "$file" ]]; then
        error_report "File does not exist: $description ($file)" "$E_NOT_FOUND"
        return 1
    fi

    return 0
}

# Validate directory exists
# Usage: validate_directory_exists "directory" "description"
validate_directory_exists() {
    local directory="$1"
    local description="${2:-directory}"

    if [[ ! -d "$directory" ]]; then
        error_report "Directory does not exist: $description ($directory)" "$E_NOT_FOUND"
        return 1
    fi

    return 0
}

# Validate path is absolute
# Usage: validate_absolute_path "path"
validate_absolute_path() {
    local path="$1"

    if [[ ! "$path" =~ ^/ ]]; then
        error_report "Path is not absolute: '$path'" "$E_VALIDATION_FAILED"
        return 1
    fi

    return 0
}

# Validate file is readable
# Usage: validate_file_readable "file"
validate_file_readable() {
    local file="$1"

    validate_file_exists "$file" || return 1

    if [[ ! -r "$file" ]]; then
        error_report "File is not readable: '$file'" "$E_PERMISSION_DENIED"
        return 1
    fi

    return 0
}

# Validate file is writable
# Usage: validate_file_writable "file"
validate_file_writable() {
    local file="$1"

    if [[ -e "$file" ]]; then
        if [[ ! -w "$file" ]]; then
            error_report "File is not writable: '$file'" "$E_PERMISSION_DENIED"
            return 1
        fi
    else
        # Check if parent directory is writable
        local parent_dir
        parent_dir=$(dirname "$file")
        if [[ ! -w "$parent_dir" ]]; then
            error_report "Cannot create file (parent directory not writable): '$file'" "$E_PERMISSION_DENIED"
            return 1
        fi
    fi

    return 0
}

# Validate file is executable
# Usage: validate_file_executable "file"
validate_file_executable() {
    local file="$1"

    validate_file_exists "$file" || return 1

    if [[ ! -x "$file" ]]; then
        error_report "File is not executable: '$file'" "$E_PERMISSION_DENIED"
        return 1
    fi

    return 0
}

# Validate directory is writable
# Usage: validate_directory_writable "directory"
validate_directory_writable() {
    local directory="$1"

    validate_directory_exists "$directory" || return 1

    if [[ ! -w "$directory" ]]; then
        error_report "Directory is not writable: '$directory'" "$E_PERMISSION_DENIED"
        return 1
    fi

    return 0
}

# Validate file size
# Usage: validate_file_size "file" [min_bytes] [max_bytes]
validate_file_size() {
    local file="$1"
    local min_bytes="${2:-0}"
    local max_bytes="${3:-}"

    validate_file_exists "$file" || return 1

    local size
    size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)

    if [[ $size -lt $min_bytes ]]; then
        error_report "File too small: '$file' (min: $min_bytes bytes, got: $size)" "$E_VALIDATION_FAILED"
        return 1
    fi

    if [[ -n "$max_bytes" ]] && [[ $size -gt $max_bytes ]]; then
        error_report "File too large: '$file' (max: $max_bytes bytes, got: $size)" "$E_VALIDATION_FAILED"
        return 1
    fi

    return 0
}

#===============================================================================
# YAML VALIDATION
#===============================================================================

# Validate YAML syntax (requires yq or python)
# Usage: validate_yaml_syntax "file"
validate_yaml_syntax() {
    local file="$1"

    validate_file_exists "$file" "YAML file" || return 1

    # Try yq first
    if command -v yq &>/dev/null; then
        if ! yq eval '.' "$file" >/dev/null 2>&1; then
            error_report "Invalid YAML syntax in: $file" "$E_VALIDATION_FAILED"
            return 1
        fi
        return 0
    fi

    # Try python as fallback
    if command -v python3 &>/dev/null; then
        if ! python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
            error_report "Invalid YAML syntax in: $file" "$E_VALIDATION_FAILED"
            return 1
        fi
        return 0
    fi

    log_warn "Cannot validate YAML syntax: neither yq nor python3 available"
    return 0
}

# Validate required YAML keys exist
# Usage: validate_yaml_keys "file" "key1" "key2" ...
validate_yaml_keys() {
    local file="$1"
    shift
    local required_keys=("$@")

    validate_file_exists "$file" "YAML file" || return 1

    local missing_keys=()

    for key in "${required_keys[@]}"; do
        if ! yaml_has_key "$file" "$key"; then
            missing_keys+=("$key")
        fi
    done

    if [[ ${#missing_keys[@]} -gt 0 ]]; then
        error_report "Missing required YAML keys in $file: ${missing_keys[*]}" "$E_VALIDATION_FAILED"
        return 1
    fi

    return 0
}

#===============================================================================
# PREREQUISITE CHECKS
#===============================================================================

# Validate command exists
# Usage: validate_command "command" ["description"]
validate_command() {
    local cmd="$1"
    local description="${2:-$cmd}"

    if ! command -v "$cmd" &>/dev/null; then
        error_report "Required command not found: $description ($cmd)" "$E_DEPENDENCY_MISSING"
        return 1
    fi

    return 0
}

# Validate multiple commands exist
# Usage: validate_commands "cmd1" "cmd2" "cmd3" ...
validate_commands() {
    local commands=("$@")
    local missing=()

    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        error_report "Missing required commands: ${missing[*]}" "$E_DEPENDENCY_MISSING"
        return 1
    fi

    return 0
}

# Validate running as root
# Usage: validate_root
validate_root() {
    if [[ $EUID -ne 0 ]]; then
        error_report "This operation requires root privileges" "$E_PERMISSION_DENIED"
        return 1
    fi
    return 0
}

# Validate not running as root
# Usage: validate_not_root
validate_not_root() {
    if [[ $EUID -eq 0 ]]; then
        error_report "This operation should not be run as root" "$E_PERMISSION_DENIED"
        return 1
    fi
    return 0
}

# Validate user exists
# Usage: validate_user_exists "username"
validate_user_exists() {
    local username="$1"

    if ! id "$username" &>/dev/null; then
        error_report "User does not exist: $username" "$E_NOT_FOUND"
        return 1
    fi

    return 0
}

# Validate group exists
# Usage: validate_group_exists "groupname"
validate_group_exists() {
    local groupname="$1"

    if ! getent group "$groupname" &>/dev/null; then
        error_report "Group does not exist: $groupname" "$E_NOT_FOUND"
        return 1
    fi

    return 0
}

# Validate systemd service exists
# Usage: validate_service_exists "service_name"
validate_service_exists() {
    local service="$1"

    if ! systemctl list-unit-files | grep -q "^${service}.service"; then
        error_report "Systemd service not found: $service" "$E_NOT_FOUND"
        return 1
    fi

    return 0
}

# Validate systemd service is active
# Usage: validate_service_active "service_name"
validate_service_active() {
    local service="$1"

    if ! systemctl is-active --quiet "$service" 2>/dev/null; then
        error_report "Service is not active: $service" "$E_INVALID_STATE"
        return 1
    fi

    return 0
}

# Validate systemd service is enabled
# Usage: validate_service_enabled "service_name"
validate_service_enabled() {
    local service="$1"

    if ! systemctl is-enabled --quiet "$service" 2>/dev/null; then
        error_report "Service is not enabled: $service" "$E_INVALID_STATE"
        return 1
    fi

    return 0
}

#===============================================================================
# RESOURCE VALIDATION
#===============================================================================

# Validate sufficient disk space
# Usage: validate_disk_space "path" "required_bytes"
validate_disk_space() {
    local path="$1"
    local required_bytes="$2"

    # Get available space in bytes
    local available
    available=$(df -B1 "$path" | tail -1 | awk '{print $4}')

    if [[ $available -lt $required_bytes ]]; then
        local required_mb=$((required_bytes / 1024 / 1024))
        local available_mb=$((available / 1024 / 1024))
        error_report "Insufficient disk space at $path (required: ${required_mb}MB, available: ${available_mb}MB)" "$E_RESOURCE_UNAVAILABLE"
        return 1
    fi

    return 0
}

# Validate sufficient memory
# Usage: validate_memory "required_mb"
validate_memory() {
    local required_mb="$1"
    local required_kb=$((required_mb * 1024))

    local available_kb
    available_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')

    if [[ $available_kb -lt $required_kb ]]; then
        local available_mb=$((available_kb / 1024))
        error_report "Insufficient memory (required: ${required_mb}MB, available: ${available_mb}MB)" "$E_RESOURCE_UNAVAILABLE"
        return 1
    fi

    return 0
}

# Validate port is available (not in use)
# Usage: validate_port_available "port"
validate_port_available() {
    local port="$1"

    validate_port "$port" || return 1

    if ss -tuln 2>/dev/null | grep -q ":${port} "; then
        error_report "Port $port is already in use" "$E_RESOURCE_UNAVAILABLE"
        return 1
    fi

    return 0
}

# Validate network connectivity
# Usage: validate_network_connectivity [host] [port]
validate_network_connectivity() {
    local host="${1:-8.8.8.8}"
    local port="${2:-53}"

    if ! timeout 5 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
        error_report "No network connectivity to $host:$port" "$E_NETWORK_ERROR"
        return 1
    fi

    return 0
}

#===============================================================================
# CONFIGURATION VALIDATION
#===============================================================================

# Validate configuration completeness
# Usage: validate_config_complete "config_file" "key1" "key2" ...
validate_config_complete() {
    local config_file="$1"
    shift
    local required_keys=("$@")

    validate_file_exists "$config_file" "configuration file" || return 1
    validate_yaml_syntax "$config_file" || return 1
    validate_yaml_keys "$config_file" "${required_keys[@]}" || return 1

    return 0
}

# Validate module configuration
# Usage: validate_module_config "module_name"
validate_module_config() {
    local module_name="$1"

    error_push_context "Validating module config: $module_name"

    # Check module exists
    if ! module_exists "$module_name" 2>/dev/null; then
        error_report "Module does not exist: $module_name" "$E_MODULE_NOT_FOUND"
        error_pop_context
        return 1
    fi

    # Get manifest and validate
    local manifest
    manifest=$(get_module_manifest "$module_name" 2>/dev/null)

    validate_file_exists "$manifest" "module manifest" || {
        error_pop_context
        return 1
    }

    validate_yaml_syntax "$manifest" || {
        error_pop_context
        return 1
    }

    # Validate required fields
    local required_keys=(
        "module.name"
        "module.version"
        "exporter.port"
    )

    for key in "${required_keys[@]}"; do
        local parent="${key%.*}"
        local child="${key#*.}"

        if ! yaml_get_nested "$manifest" "$parent" "$child" &>/dev/null; then
            error_report "Missing required field in module manifest: $key" "$E_VALIDATION_FAILED"
            error_pop_context
            return 1
        fi
    done

    error_pop_context
    return 0
}

#===============================================================================
# USAGE EXAMPLES
#===============================================================================

# Example 1: Validate IP and port
# validate_ip "192.168.1.1" && validate_port "9090"

# Example 2: Validate file permissions
# validate_file_readable "/etc/config.yaml"
# validate_file_writable "/var/log/app.log"

# Example 3: Validate prerequisites
# validate_commands "systemctl" "curl" "jq"
# validate_root

# Example 4: Validate configuration
# validate_config_complete "/etc/app.yaml" "server.host" "server.port" "database.url"

# Example 5: Validate resources
# validate_disk_space "/var/lib" "$((100 * 1024 * 1024))"  # 100MB
# validate_memory 512  # 512MB
# validate_port_available 9090

# Example 6: Batch validation with error aggregation
# error_aggregate_start
# validate_ip "$IP_ADDR" || true
# validate_port "$PORT" || true
# validate_hostname "$HOSTNAME" || true
# error_aggregate_finish || exit 1
