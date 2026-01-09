#!/usr/bin/env bash
# Input validation utilities for vpsmanager

# Validate domain name format
# Returns 0 if valid, 1 if invalid
validate_domain() {
    local domain="$1"

    # Check if empty
    if [[ -z "$domain" ]]; then
        echo "Domain cannot be empty"
        return 1
    fi

    # Check length (max 253 characters)
    if [[ ${#domain} -gt 253 ]]; then
        echo "Domain name too long (max 253 characters)"
        return 1
    fi

    # Check format (basic validation)
    # Allows subdomains, must have at least one dot, valid characters
    if ! echo "$domain" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$'; then
        echo "Invalid domain format"
        return 1
    fi

    # Check for dangerous characters (security)
    if echo "$domain" | grep -qE '[;&|`$(){}]'; then
        echo "Domain contains invalid characters"
        return 1
    fi

    return 0
}

# Validate site type
validate_site_type() {
    local type="$1"
    local valid_types=("wordpress" "laravel" "html" "php")

    for valid in "${valid_types[@]}"; do
        if [[ "$type" == "$valid" ]]; then
            return 0
        fi
    done

    echo "Invalid site type. Valid types: ${valid_types[*]}"
    return 1
}

# Validate PHP version
validate_php_version() {
    local version="$1"
    local valid_versions=("8.2" "8.3" "8.4")

    for valid in "${valid_versions[@]}"; do
        if [[ "$version" == "$valid" ]]; then
            return 0
        fi
    done

    echo "Invalid PHP version. Valid versions: ${valid_versions[*]}"
    return 1
}

# Validate backup type
validate_backup_type() {
    local type="$1"
    local valid_types=("full" "files" "database")

    for valid in "${valid_types[@]}"; do
        if [[ "$type" == "$valid" ]]; then
            return 0
        fi
    done

    echo "Invalid backup type. Valid types: ${valid_types[*]}"
    return 1
}

# Sanitize string for safe use in paths and commands
# Removes all characters except alphanumeric, dash, underscore, dot
sanitize_string() {
    local str="$1"
    echo "$str" | tr -cd 'a-zA-Z0-9._-'
}

# Convert domain to safe directory name
# example.com -> example_com
domain_to_dirname() {
    local domain="$1"
    echo "$domain" | tr '.' '_' | tr -cd 'a-zA-Z0-9_-'
}

# Convert domain to database name (max 64 chars, no dots)
domain_to_dbname() {
    local domain="$1"
    local dbname
    dbname=$(echo "$domain" | tr '.' '_' | tr '-' '_' | tr -cd 'a-zA-Z0-9_')
    # Truncate to 60 chars to leave room for prefix
    echo "${dbname:0:60}"
}

# Check if site exists in registry - FIXED
site_exists() {
    local domain="$1"
    local sites_file="${VPSMANAGER_ROOT}/data/sites.json"

    if [[ ! -f "$sites_file" ]]; then
        return 1
    fi

    # Fixed: Handle spaces in JSON formatting
    # Match both "domain":"value" and "domain": "value"
    if grep -q "\"domain\"[[:space:]]*:[[:space:]]*\"${domain}\"" "$sites_file" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Require root privileges
require_root() {
    if [[ $EUID -ne 0 ]]; then
        json_error "This command requires root privileges" "PERMISSION_DENIED"
        exit 1
    fi
}
