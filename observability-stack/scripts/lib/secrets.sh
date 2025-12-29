#!/bin/bash
#===============================================================================
# Secrets Management Library
# Secure secret resolution from multiple sources with validation
#===============================================================================

[[ -n "${SECRETS_SH_LOADED:-}" ]] && return 0
SECRETS_SH_LOADED=1

_SECRETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${COMMON_SH_LOADED:-}" ]] && source "$_SECRETS_DIR/common.sh"
[[ -z "${ERRORS_SH_LOADED:-}" ]] && source "$_SECRETS_DIR/errors.sh"
[[ -z "${VALIDATION_SH_LOADED:-}" ]] && source "$_SECRETS_DIR/validation.sh"

# Secret sources priority order
readonly SECRET_SOURCES="${SECRET_SOURCES:-file env vault}"
readonly SECRET_FILE_DIR="${SECRET_FILE_DIR:-/etc/observability/secrets}"

# Secret resolution from multiple sources
# Usage: secret_get "secret_name" [default]
secret_get() {
    local name="$1"
    local default="${2:-}"
    
    for source in $SECRET_SOURCES; do
        local value=""
        case "$source" in
            file)
                value=$(secret_from_file "$name")
                ;;
            env)
                value=$(secret_from_env "$name")
                ;;
            vault)
                value=$(secret_from_vault "$name")
                ;;
        esac
        
        if [[ -n "$value" ]]; then
            echo "$value"
            return 0
        fi
    done
    
    if [[ -n "$default" ]]; then
        echo "$default"
        return 0
    fi
    
    error_report "Secret not found: $name" "$E_NOT_FOUND"
    return 1
}

# Get secret from file
# Usage: secret_from_file "secret_name"
secret_from_file() {
    local name="$1"
    local file="$SECRET_FILE_DIR/$name"
    
    if [[ -f "$file" ]]; then
        cat "$file" | tr -d '\n'
        return 0
    fi
    return 1
}

# Get secret from environment variable
# Usage: secret_from_env "secret_name"
secret_from_env() {
    local name="$1"
    local env_var="SECRET_${name^^}"
    
    if [[ -n "${!env_var:-}" ]]; then
        echo "${!env_var}"
        return 0
    fi
    return 1
}

# Get secret from vault (stub for future implementation)
# Usage: secret_from_vault "secret_name"
secret_from_vault() {
    local name="$1"
    # TODO: Implement Hashicorp Vault integration
    return 1
}

# Set a file-based secret
# Usage: secret_set_file "secret_name" "value" [mode]
secret_set_file() {
    local name="$1"
    local value="$2"
    local mode="${3:-0600}"
    
    mkdir -p "$SECRET_FILE_DIR"
    chmod 700 "$SECRET_FILE_DIR"
    
    local file="$SECRET_FILE_DIR/$name"
    printf '%s' "$value" > "$file"
    chmod "$mode" "$file"
    
    log_success "Secret stored: $name"
}

# Validate secret exists and meets requirements
# Usage: secret_validate "secret_name" [min_length]
secret_validate() {
    local name="$1"
    local min_length="${2:-8}"
    
    local value
    value=$(secret_get "$name") || return 1
    
    validate_not_empty "$value" "$name" || return 1
    validate_length "$value" "$min_length" "" "$name" || return 1
    
    return 0
}

# Generate a random secret
# Usage: secret_generate [length]
secret_generate() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d '\n'
}

# Encrypt a file with a password
# Usage: secret_encrypt_file "file" "password"
secret_encrypt_file() {
    local file="$1"
    local password="$2"

    # Use PBKDF2 with 310,000 iterations (OWASP recommendation for 2023+)
    # This is more secure than the deprecated -k flag
    openssl enc -aes-256-cbc -salt -pbkdf2 -iter 310000 \
        -in "$file" -out "${file}.enc" -pass "pass:$password"
}

# Decrypt a file with a password
# Usage: secret_decrypt_file "encrypted_file" "password" "output_file"
secret_decrypt_file() {
    local encrypted_file="$1"
    local password="$2"
    local output_file="$3"

    # Use PBKDF2 with 310,000 iterations (must match encryption)
    openssl enc -aes-256-cbc -d -pbkdf2 -iter 310000 \
        -in "$encrypted_file" -out "$output_file" -pass "pass:$password"
}

