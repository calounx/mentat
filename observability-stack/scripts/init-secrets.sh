#!/bin/bash
#===============================================================================
# Secrets Initialization Script
# Generates and manages secrets for the observability stack
#
# SECURITY FEATURES:
# - Generates cryptographically secure random passwords
# - Sets strict file permissions (600, root:root)
# - Supports optional encryption with age/gpg
# - Never logs or displays actual secret values
# - Prevents overwriting existing secrets without confirmation
#
# Usage:
#   ./init-secrets.sh [OPTIONS]
#
# Options:
#   --force              Force regeneration of all secrets (DANGEROUS)
#   --encrypt-age        Encrypt secrets with age after generation
#   --encrypt-gpg        Encrypt secrets with gpg after generation
#   --age-recipient FILE Path to age public key file
#   --gpg-recipient ID   GPG key ID or email for encryption
#   --length N           Password length (default: 32)
#   --help               Show this help message
#===============================================================================

set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source common library
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

#===============================================================================
# CONSTANTS
#===============================================================================
readonly SECRETS_DIR="$STACK_ROOT/secrets"
readonly DEFAULT_PASSWORD_LENGTH=32
readonly MIN_PASSWORD_LENGTH=16

#===============================================================================
# CONFIGURATION
#===============================================================================
FORCE_MODE=false
ENCRYPT_AGE=false
ENCRYPT_GPG=false
AGE_RECIPIENT=""
GPG_RECIPIENT=""
PASSWORD_LENGTH=$DEFAULT_PASSWORD_LENGTH

#===============================================================================
# SECRET DEFINITIONS
# Define all secrets needed by the observability stack
#===============================================================================
# Format: "secret_name:description:min_length"
declare -a SECRETS=(
    "smtp_password:SMTP authentication password for Alertmanager:32"
    "grafana_admin_password:Grafana admin user initial password:32"
    "prometheus_basic_auth_password:HTTP basic auth for Prometheus API:32"
    "loki_basic_auth_password:HTTP basic auth for Loki API:32"
)

#===============================================================================
# USAGE
#===============================================================================
usage() {
    cat << EOF
Secrets Initialization Script for Observability Stack

Usage: $0 [OPTIONS]

OPTIONS:
    --force                    Force regeneration of existing secrets (DANGEROUS)
    --encrypt-age              Encrypt secrets with age after generation
    --encrypt-gpg              Encrypt secrets with gpg after generation
    --age-recipient FILE       Path to age public key file (default: ~/.config/age/pubkey.txt)
    --gpg-recipient ID         GPG key ID or email for encryption
    --length N                 Password length in characters (default: 32, min: 16)
    --help                     Show this help message

EXAMPLES:
    # Generate all secrets with defaults
    $0

    # Force regenerate all secrets
    $0 --force

    # Generate and encrypt with age
    $0 --encrypt-age --age-recipient ~/.config/age/pubkey.txt

    # Generate and encrypt with gpg
    $0 --encrypt-gpg --gpg-recipient admin@example.com

SECURITY NOTES:
    - All secrets are generated using cryptographically secure random sources
    - Secret files are created with 600 permissions (owner read/write only)
    - Existing secrets are never overwritten unless --force is used
    - Secret values are never logged or displayed on screen
    - Use encryption for additional security on shared systems

For more information, see: $STACK_ROOT/secrets/README.md
EOF
}

#===============================================================================
# ARGUMENT PARSING
#===============================================================================
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_MODE=true
                shift
                ;;
            --encrypt-age)
                ENCRYPT_AGE=true
                shift
                ;;
            --encrypt-gpg)
                ENCRYPT_GPG=true
                shift
                ;;
            --age-recipient)
                AGE_RECIPIENT="$2"
                shift 2
                ;;
            --gpg-recipient)
                GPG_RECIPIENT="$2"
                shift 2
                ;;
            --length)
                PASSWORD_LENGTH="$2"
                shift 2
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

#===============================================================================
# VALIDATION
#===============================================================================
validate_environment() {
    # Check if running as root
    check_root

    # Validate password length
    if [[ $PASSWORD_LENGTH -lt $MIN_PASSWORD_LENGTH ]]; then
        log_fatal "Password length must be at least $MIN_PASSWORD_LENGTH characters"
    fi

    # Validate encryption options
    if [[ "$ENCRYPT_AGE" == "true" ]]; then
        if ! command -v age &> /dev/null; then
            log_fatal "age is not installed. Install with: apt-get install age"
        fi

        if [[ -z "$AGE_RECIPIENT" ]]; then
            AGE_RECIPIENT="$HOME/.config/age/pubkey.txt"
        fi

        if [[ ! -f "$AGE_RECIPIENT" ]]; then
            log_fatal "Age public key not found: $AGE_RECIPIENT"
        fi

        log_info "Will encrypt secrets with age using: $AGE_RECIPIENT"
    fi

    if [[ "$ENCRYPT_GPG" == "true" ]]; then
        if ! command -v gpg &> /dev/null; then
            log_fatal "gpg is not installed. Install with: apt-get install gnupg"
        fi

        if [[ -z "$GPG_RECIPIENT" ]]; then
            log_fatal "GPG recipient must be specified with --gpg-recipient"
        fi

        # Verify GPG key exists
        if ! gpg --list-keys "$GPG_RECIPIENT" &> /dev/null; then
            log_fatal "GPG key not found for recipient: $GPG_RECIPIENT"
        fi

        log_info "Will encrypt secrets with GPG for recipient: $GPG_RECIPIENT"
    fi

    # Ensure secrets directory exists
    ensure_dir "$SECRETS_DIR" "root" "root" "0700"
}

#===============================================================================
# SECRET GENERATION
#===============================================================================

# Generate a cryptographically secure random password
# SECURITY: Uses /dev/urandom with base64 encoding for strong randomness
# Arguments:
#   $1 - Length of password to generate
# Returns:
#   Random password string
generate_secure_password() {
    local length="$1"

    # Use openssl for cryptographically secure random generation
    # Remove characters that might cause issues in configs: /, +, =
    openssl rand -base64 "$((length * 2))" | tr -d '/+=' | head -c "$length"
}

# Store a secret to file with secure permissions
# SECURITY:
# - Creates file with 600 permissions (only owner can read/write)
# - Sets owner to root:root
# - Never logs the actual secret value
# Arguments:
#   $1 - Secret name (becomes filename)
#   $2 - Secret value
# Returns:
#   0 on success, 1 on failure
store_secret() {
    local secret_name="$1"
    local secret_value="$2"
    local secret_file="$SECRETS_DIR/$secret_name"

    # Security: Use umask to ensure file is created with 600 permissions
    local old_umask
    old_umask=$(umask)
    umask 0077

    # Write secret to file
    echo -n "$secret_value" > "$secret_file"

    # Restore umask
    umask "$old_umask"

    # Ensure proper ownership
    chown root:root "$secret_file"
    chmod 600 "$secret_file"

    log_debug "Stored secret: $secret_name (length: ${#secret_value})"
    return 0
}

# Encrypt a secret file with age
# Arguments:
#   $1 - Secret file path
encrypt_with_age() {
    local secret_file="$1"
    local encrypted_file="${secret_file}.age"

    if [[ ! -f "$secret_file" ]]; then
        log_error "Secret file not found: $secret_file"
        return 1
    fi

    # Read recipient public key
    local recipient
    recipient=$(cat "$AGE_RECIPIENT")

    # Encrypt the secret
    age -r "$recipient" -o "$encrypted_file" "$secret_file"

    if [[ -f "$encrypted_file" ]]; then
        chmod 600 "$encrypted_file"
        log_debug "Encrypted: $(basename "$secret_file") -> $(basename "$encrypted_file")"

        # Ask if original should be removed
        if [[ "$FORCE_MODE" != "true" ]]; then
            read -p "Remove unencrypted version of $(basename "$secret_file")? [y/N] " -n 1 -r
            echo
            if [[ "$REPLY" =~ ^[Yy]$ ]]; then
                shred -u "$secret_file"
                log_info "Removed unencrypted version"
            fi
        fi
        return 0
    fi

    return 1
}

# Encrypt a secret file with GPG
# Arguments:
#   $1 - Secret file path
encrypt_with_gpg() {
    local secret_file="$1"
    local encrypted_file="${secret_file}.gpg"

    if [[ ! -f "$secret_file" ]]; then
        log_error "Secret file not found: $secret_file"
        return 1
    fi

    # Encrypt the secret
    gpg --encrypt --recipient "$GPG_RECIPIENT" --output "$encrypted_file" "$secret_file"

    if [[ -f "$encrypted_file" ]]; then
        chmod 600 "$encrypted_file"
        log_debug "Encrypted: $(basename "$secret_file") -> $(basename "$encrypted_file")"

        # Ask if original should be removed
        if [[ "$FORCE_MODE" != "true" ]]; then
            read -p "Remove unencrypted version of $(basename "$secret_file")? [y/N] " -n 1 -r
            echo
            if [[ "$REPLY" =~ ^[Yy]$ ]]; then
                shred -u "$secret_file"
                log_info "Removed unencrypted version"
            fi
        fi
        return 0
    fi

    return 1
}

# Load an existing secret from file
# Arguments:
#   $1 - Secret name
# Returns:
#   Secret value (to stdout)
load_secret() {
    local secret_name="$1"
    local secret_file="$SECRETS_DIR/$secret_name"

    if [[ -f "$secret_file" ]]; then
        cat "$secret_file"
        return 0
    fi

    return 1
}

# Generate or load a secret
# Arguments:
#   $1 - Secret name
#   $2 - Secret description
#   $3 - Minimum length
generate_or_load_secret() {
    local secret_name="$1"
    local description="$2"
    local min_length="${3:-32}"
    local secret_file="$SECRETS_DIR/$secret_name"

    # Check if secret already exists
    if [[ -f "$secret_file" ]] && [[ "$FORCE_MODE" != "true" ]]; then
        local existing_length
        existing_length=$(wc -c < "$secret_file")
        log_skip "$description - already exists (${existing_length} bytes)"
        return 0
    fi

    # Warn if forcing regeneration
    if [[ -f "$secret_file" ]] && [[ "$FORCE_MODE" == "true" ]]; then
        log_warn "Regenerating existing secret: $secret_name"
    fi

    # Generate new secret
    local length=$PASSWORD_LENGTH
    if [[ $length -lt $min_length ]]; then
        length=$min_length
    fi

    log_info "Generating: $description ($length chars)..."
    local secret_value
    secret_value=$(generate_secure_password "$length")

    # Store the secret
    store_secret "$secret_name" "$secret_value"
    log_success "Generated: $description"

    # Encrypt if requested
    if [[ "$ENCRYPT_AGE" == "true" ]]; then
        encrypt_with_age "$secret_file"
    fi

    if [[ "$ENCRYPT_GPG" == "true" ]]; then
        encrypt_with_gpg "$secret_file"
    fi
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================
main() {
    log_info "Observability Stack - Secrets Initialization"
    log_info "============================================"
    echo

    # Parse arguments
    parse_arguments "$@"

    # Validate environment
    validate_environment

    # Show warning if force mode
    if [[ "$FORCE_MODE" == "true" ]]; then
        log_warn "FORCE MODE ENABLED - Existing secrets will be regenerated!"
        log_warn "This will break existing configurations using old secrets."
        read -p "Are you sure? Type 'yes' to continue: " -r
        if [[ "$REPLY" != "yes" ]]; then
            log_info "Cancelled"
            exit 0
        fi
    fi

    echo
    log_info "Generating secrets..."
    echo

    # Generate all secrets
    local generated=0
    local skipped=0

    for secret_def in "${SECRETS[@]}"; do
        IFS=':' read -r name description min_length <<< "$secret_def"

        if generate_or_load_secret "$name" "$description" "$min_length"; then
            if [[ -f "$SECRETS_DIR/$name" ]] && [[ "$FORCE_MODE" != "true" ]]; then
                ((skipped++))
            else
                ((generated++))
            fi
        fi
    done

    echo
    log_info "Summary"
    log_info "-------"
    log_info "Generated: $generated secret(s)"
    log_info "Skipped:   $skipped secret(s) (already exist)"
    log_info "Location:  $SECRETS_DIR"

    # Show encryption status
    if [[ "$ENCRYPT_AGE" == "true" ]]; then
        log_info "Encrypted: age (recipient from $AGE_RECIPIENT)"
    fi
    if [[ "$ENCRYPT_GPG" == "true" ]]; then
        log_info "Encrypted: gpg (recipient: $GPG_RECIPIENT)"
    fi

    echo
    log_success "Secrets initialization complete!"
    echo
    log_info "Next Steps:"
    log_info "1. Review generated secrets in: $SECRETS_DIR"
    log_info "2. Update config/global.yaml to use secret references"
    log_info "3. Run setup scripts which will automatically resolve secrets"
    log_info "4. IMPORTANT: Backup secrets securely (see secrets/README.md)"
    echo
    log_warn "Security Reminders:"
    log_warn "- These secrets are NOT stored in git (gitignored)"
    log_warn "- Back up secrets separately from code repository"
    log_warn "- Rotate secrets regularly (every 90 days minimum)"
    log_warn "- Use encryption for backups"
    echo
}

# Run main with all arguments
main "$@"
