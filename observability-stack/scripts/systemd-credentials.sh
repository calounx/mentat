#!/bin/bash
#===============================================================================
# systemd Credentials Integration Script
# Integrates secrets with systemd's native credential management (Debian 13+)
#
# SECURITY FEATURES:
# - Uses systemd-creds for encrypted credential storage
# - Credentials are decrypted only by the service that needs them
# - TPM2 hardware encryption support (if available)
# - Credentials never written to disk in plaintext
#
# Requirements:
# - Debian 13+ (systemd 255+)
# - systemd-creds utility
# - Optional: TPM2 module for hardware encryption
#
# Usage:
#   ./systemd-credentials.sh encrypt <secret_name>    # Encrypt a secret
#   ./systemd-credentials.sh list                     # List encrypted credentials
#   ./systemd-credentials.sh test <service>           # Test credential loading
#   ./systemd-credentials.sh help                     # Show help
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
readonly CREDSTORE_DIR="/etc/credstore.encrypted"
readonly MIN_SYSTEMD_VERSION="255"

#===============================================================================
# FUNCTIONS
#===============================================================================

# Check if systemd credentials are supported
check_systemd_credentials_support() {
    # Check systemd version
    if ! command -v systemd-creds &> /dev/null; then
        log_error "systemd-creds command not found"
        log_error "This feature requires systemd 255+ (Debian 13+)"
        return 1
    fi

    # Get systemd version
    local systemd_version
    systemd_version=$(systemctl --version | head -1 | awk '{print $2}')

    if [[ "$systemd_version" -lt "$MIN_SYSTEMD_VERSION" ]]; then
        log_error "systemd version $systemd_version is too old"
        log_error "This feature requires systemd $MIN_SYSTEMD_VERSION+ (found: $systemd_version)"
        return 1
    fi

    log_info "systemd credentials supported (version: $systemd_version)"
    return 0
}

# Check if TPM2 is available for hardware encryption
check_tpm2_support() {
    if command -v systemd-cryptenroll &> /dev/null; then
        if [[ -c /dev/tpm0 ]] || [[ -c /dev/tpmrm0 ]]; then
            log_info "TPM2 hardware encryption available"
            return 0
        fi
    fi

    log_warn "TPM2 not available - using software encryption only"
    return 1
}

# Encrypt a secret with systemd-creds
# Arguments:
#   $1 - Secret name
encrypt_secret() {
    local secret_name="$1"
    local secrets_dir
    secrets_dir="$(get_secrets_dir)"
    local secret_file="$secrets_dir/$secret_name"

    # Check if secret exists
    if [[ ! -f "$secret_file" ]]; then
        log_error "Secret file not found: $secret_file"
        log_error "Run ./scripts/init-secrets.sh first to generate secrets"
        return 1
    fi

    # Ensure credstore directory exists
    ensure_dir "$CREDSTORE_DIR" "root" "root" "0700"

    # Output file
    local cred_file="$CREDSTORE_DIR/$secret_name.cred"

    log_info "Encrypting secret: $secret_name"

    # Encrypt with systemd-creds
    # Options:
    #   --name: Credential name
    #   --with-key=auto: Use best available encryption (TPM2 if available, otherwise host key)
    if systemd-creds encrypt \
        --name="$secret_name" \
        --with-key=auto \
        "$secret_file" \
        "$cred_file" 2>&1; then

        chmod 600 "$cred_file"
        chown root:root "$cred_file"
        log_success "Encrypted credential: $cred_file"

        # Show info about the credential
        log_info "Credential information:"
        systemd-creds has-tpm2 "$cred_file" && log_info "  - TPM2 encryption: Yes" || log_info "  - TPM2 encryption: No (using host key)"

        return 0
    else
        log_error "Failed to encrypt credential"
        return 1
    fi
}

# List all encrypted credentials
list_credentials() {
    if [[ ! -d "$CREDSTORE_DIR" ]]; then
        log_info "No encrypted credentials found (directory doesn't exist)"
        return 0
    fi

    log_info "Encrypted credentials in $CREDSTORE_DIR:"
    echo

    local count=0
    for cred_file in "$CREDSTORE_DIR"/*.cred; do
        if [[ -f "$cred_file" ]]; then
            local name
            name=$(basename "$cred_file" .cred)
            local size
            size=$(stat -c %s "$cred_file")
            local modified
            modified=$(stat -c %y "$cred_file" | cut -d'.' -f1)

            echo "  $name"
            echo "    File: $cred_file"
            echo "    Size: $size bytes"
            echo "    Modified: $modified"

            # Check if TPM2 encrypted
            if systemd-creds has-tpm2 "$cred_file" 2>/dev/null; then
                echo "    Encryption: TPM2 + Host Key"
            else
                echo "    Encryption: Host Key Only"
            fi
            echo

            ((count++))
        fi
    done

    if [[ $count -eq 0 ]]; then
        log_info "No encrypted credentials found"
    else
        log_success "Found $count encrypted credential(s)"
    fi
}

# Generate systemd service integration example
generate_service_example() {
    local secret_name="$1"
    local service_name="${2:-myservice}"

    cat << EOF

# Example systemd service file integration for: $secret_name
# Add these lines to your service file (e.g., /etc/systemd/system/${service_name}.service)

[Service]
# Load the encrypted credential
LoadCredential=${secret_name}:${CREDSTORE_DIR}/${secret_name}.cred

# The credential will be available as a file in the service's runtime directory
# Access it via: \${CREDENTIALS_DIRECTORY}/${secret_name}

# Example: Pass as environment variable
EnvironmentFile=-\${CREDENTIALS_DIRECTORY}/${secret_name}

# Or read directly in ExecStart
ExecStart=/usr/bin/myapp --password-file=\${CREDENTIALS_DIRECTORY}/${secret_name}

# SECURITY NOTE:
# - The credential is decrypted only when the service starts
# - Only this specific service can access its credentials
# - Credentials are stored in a private tmpfs (RAM only, never on disk)
# - Automatically cleaned up when service stops

EOF
}

# Test credential decryption
test_credential() {
    local secret_name="$1"
    local cred_file="$CREDSTORE_DIR/$secret_name.cred"

    if [[ ! -f "$cred_file" ]]; then
        log_error "Encrypted credential not found: $cred_file"
        return 1
    fi

    log_info "Testing credential decryption: $secret_name"

    # Decrypt to stdout (for testing only!)
    if systemd-creds decrypt "$cred_file" - 2>&1 | head -c 10 > /dev/null; then
        log_success "Credential can be decrypted successfully"
        log_warn "Actual value not displayed for security"
        return 0
    else
        log_error "Failed to decrypt credential"
        return 1
    fi
}

# Encrypt all secrets in secrets directory
encrypt_all_secrets() {
    local secrets_dir
    secrets_dir="$(get_secrets_dir)"

    if [[ ! -d "$secrets_dir" ]]; then
        log_error "Secrets directory not found: $secrets_dir"
        log_error "Run ./scripts/init-secrets.sh first"
        return 1
    fi

    log_info "Encrypting all secrets for systemd credentials..."
    echo

    local count=0
    local failed=0

    for secret_file in "$secrets_dir"/*; do
        if [[ -f "$secret_file" ]]; then
            local name
            name=$(basename "$secret_file")

            # Skip encrypted files and templates
            if [[ "$name" =~ \.(age|gpg|example)$ ]]; then
                continue
            fi

            if encrypt_secret "$name"; then
                ((count++))
            else
                ((failed++))
            fi
            echo
        fi
    done

    echo
    log_info "Summary:"
    log_info "  Encrypted: $count"
    if [[ $failed -gt 0 ]]; then
        log_error "  Failed: $failed"
    fi
}

# Show usage help
usage() {
    cat << EOF
systemd Credentials Integration for Observability Stack

DESCRIPTION:
    Integrates secrets with systemd's native credential management system.
    Provides encrypted, service-isolated credential storage using systemd-creds.

REQUIREMENTS:
    - Debian 13+ (systemd 255+)
    - systemd-creds utility
    - Optional: TPM2 for hardware encryption

USAGE:
    $0 <command> [arguments]

COMMANDS:
    check               Check if systemd credentials are supported
    encrypt <name>      Encrypt a specific secret
    encrypt-all         Encrypt all secrets in secrets/ directory
    list                List all encrypted credentials
    test <name>         Test decryption of a credential
    example <name>      Show service file integration example
    help                Show this help message

EXAMPLES:
    # Check system support
    $0 check

    # Encrypt all secrets
    $0 encrypt-all

    # Encrypt a specific secret
    $0 encrypt smtp_password

    # List encrypted credentials
    $0 list

    # Test credential decryption
    $0 test smtp_password

    # Show service integration example
    $0 example smtp_password alertmanager

SECURITY NOTES:
    - Credentials are encrypted at rest using systemd-creds
    - If TPM2 is available, hardware encryption is used
    - Credentials are decrypted only when needed by specific services
    - Decrypted credentials exist only in service's private tmpfs (RAM)
    - No plaintext credentials ever written to disk after encryption

SEE ALSO:
    man systemd-creds(1)
    man systemd.exec(5) - LoadCredential= directive
    https://systemd.io/CREDENTIALS/

EOF
}

#===============================================================================
# MAIN
#===============================================================================
main() {
    local command="${1:-help}"

    case "$command" in
        check)
            log_info "Checking systemd credentials support..."
            if check_systemd_credentials_support; then
                check_tpm2_support || true
                log_success "systemd credentials are supported on this system"
                exit 0
            else
                exit 1
            fi
            ;;

        encrypt)
            check_root
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 encrypt <secret_name>"
                exit 1
            fi
            check_systemd_credentials_support || exit 1
            encrypt_secret "$2"
            echo
            generate_service_example "$2"
            ;;

        encrypt-all)
            check_root
            check_systemd_credentials_support || exit 1
            encrypt_all_secrets
            ;;

        list)
            list_credentials
            ;;

        test)
            check_root
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 test <secret_name>"
                exit 1
            fi
            check_systemd_credentials_support || exit 1
            test_credential "$2"
            ;;

        example)
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 example <secret_name> [service_name]"
                exit 1
            fi
            generate_service_example "$2" "${3:-myservice}"
            ;;

        help|--help|-h)
            usage
            exit 0
            ;;

        *)
            log_error "Unknown command: $command"
            echo
            usage
            exit 1
            ;;
    esac
}

# Run main with all arguments
main "$@"
