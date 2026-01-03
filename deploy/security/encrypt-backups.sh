#!/bin/bash
# ============================================================================
# Backup Encryption Script
# ============================================================================
# Purpose: Encrypt all backups using GPG for secure storage
# Features: GPG encryption, key management, automated encryption
# Compliance: GDPR, PCI DSS 3.4, SOC 2, ISO 27001
# ============================================================================

set -euo pipefail
# Dependency validation - MUST run before doing anything else
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Validate dependencies
validate_deployment_dependencies() {
    local script_dir="$1"
    local deploy_root="$2"
    local script_name="$(basename "$0")"
    local errors=()

    if [[ ! -d "$deploy_root" ]]; then
        errors+=("Deploy root directory not found: $deploy_root")
    fi

    local security_dir="${deploy_root}/security"
    if [[ ! -d "$security_dir" ]]; then
        errors+=("Security directory not found: $security_dir")
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "" >&2
        echo "ERROR: Missing required dependencies for ${script_name}" >&2
        echo "" >&2
        echo "Script location: ${script_dir}" >&2
        echo "Deploy root: ${deploy_root}" >&2
        echo "" >&2
        echo "Missing dependencies:" >&2
        for error in "${errors[@]}"; do
            echo "  - ${error}" >&2
        done
        echo "" >&2
        echo "Run from repository root: sudo ./deploy/security/${script_name}" >&2
        exit 1
    fi
}

validate_deployment_dependencies "$SCRIPT_DIR" "$DEPLOY_ROOT"

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/var/backups/chom}"
ENCRYPTED_DIR="${ENCRYPTED_DIR:-/var/backups/chom/encrypted}"
GPG_KEY_ID="${GPG_KEY_ID:-}"
GPG_KEY_EMAIL="${GPG_KEY_EMAIL:-backup@chom.local}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Install dependencies
install_dependencies() {
    log_info "Installing encryption dependencies..."

    apt-get update -qq
    apt-get install -y gnupg2

    log_success "Dependencies installed"
}

# Setup GPG key
setup_gpg_key() {
    log_info "Setting up GPG encryption key..."

    # Check if key already exists
    if [[ -n "$GPG_KEY_ID" ]] && gpg --list-keys "$GPG_KEY_ID" &>/dev/null; then
        log_success "Using existing GPG key: $GPG_KEY_ID"
        return 0
    fi

    # Look for existing backup key
    local existing_key=$(gpg --list-keys --with-colons | grep "CHOM Backup" || echo "")

    if [[ -n "$existing_key" ]]; then
        GPG_KEY_ID=$(echo "$existing_key" | grep "^fpr" | cut -d: -f10)
        log_success "Found existing backup key: $GPG_KEY_ID"
        return 0
    fi

    # Generate new GPG key
    log_info "Generating new GPG key pair..."

    cat > /tmp/gpg-backup-batch <<EOF
%echo Generating GPG key for backup encryption
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: CHOM Backup Encryption
Name-Email: $GPG_KEY_EMAIL
Expire-Date: 0
%no-protection
%commit
%echo Done
EOF

    gpg --batch --generate-key /tmp/gpg-backup-batch
    rm /tmp/gpg-backup-batch

    # Get the key ID
    GPG_KEY_ID=$(gpg --list-keys --with-colons | grep "^fpr" | tail -1 | cut -d: -f10)

    log_success "GPG key generated: $GPG_KEY_ID"

    # Export public key
    mkdir -p "$BACKUP_DIR"
    gpg --export --armor "$GPG_KEY_ID" > "$BACKUP_DIR/backup-public-key.asc"
    chmod 600 "$BACKUP_DIR/backup-public-key.asc"

    # Export private key (for disaster recovery)
    gpg --export-secret-keys --armor "$GPG_KEY_ID" > "$BACKUP_DIR/backup-private-key.asc"
    chmod 400 "$BACKUP_DIR/backup-private-key.asc"

    log_success "Keys exported to $BACKUP_DIR"
    log_warning "CRITICAL: Store backup-private-key.asc in a secure offline location!"
}

# Create directories
create_directories() {
    log_info "Creating backup directories..."

    mkdir -p "$BACKUP_DIR"
    mkdir -p "$ENCRYPTED_DIR"

    chmod 700 "$BACKUP_DIR"
    chmod 700 "$ENCRYPTED_DIR"

    log_success "Directories created"
}

# Encrypt file
encrypt_file() {
    local source_file="$1"
    local output_file="$2"

    if [[ ! -f "$source_file" ]]; then
        log_error "Source file not found: $source_file"
        return 1
    fi

    gpg --encrypt \
        --recipient "$GPG_KEY_ID" \
        --trust-model always \
        --compress-algo bzip2 \
        --output "$output_file" \
        "$source_file"

    if [[ $? -eq 0 ]]; then
        chmod 600 "$output_file"
        return 0
    else
        log_error "Encryption failed for: $source_file"
        return 1
    fi
}

# Decrypt file (for testing)
decrypt_file() {
    local encrypted_file="$1"
    local output_file="$2"

    if [[ ! -f "$encrypted_file" ]]; then
        log_error "Encrypted file not found: $encrypted_file"
        return 1
    fi

    gpg --decrypt \
        --output "$output_file" \
        "$encrypted_file"

    if [[ $? -eq 0 ]]; then
        chmod 600 "$output_file"
        return 0
    else
        log_error "Decryption failed for: $encrypted_file"
        return 1
    fi
}

# Encrypt all backups
encrypt_all_backups() {
    log_info "Encrypting all backup files..."

    local encrypted_count=0
    local skipped_count=0

    # Find all backup files
    while IFS= read -r -d '' backup_file; do
        local filename=$(basename "$backup_file")
        local encrypted_file="$ENCRYPTED_DIR/${filename}.gpg"

        # Skip if already encrypted
        if [[ "$filename" == *.gpg ]]; then
            ((skipped_count++))
            continue
        fi

        # Skip key files
        if [[ "$filename" == *"key.asc" ]]; then
            ((skipped_count++))
            continue
        fi

        # Check if encrypted version already exists
        if [[ -f "$encrypted_file" ]]; then
            # Check if source is newer
            if [[ "$backup_file" -nt "$encrypted_file" ]]; then
                log_info "Re-encrypting updated file: $filename"
                encrypt_file "$backup_file" "$encrypted_file"
                ((encrypted_count++))
            else
                ((skipped_count++))
            fi
        else
            log_info "Encrypting: $filename"
            encrypt_file "$backup_file" "$encrypted_file"
            ((encrypted_count++))
        fi
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -print0)

    log_success "Encrypted $encrypted_count files, skipped $skipped_count files"
}

# Verify encryption
verify_encryption() {
    log_info "Verifying encrypted backups..."

    local verified=0
    local failed=0

    while IFS= read -r -d '' encrypted_file; do
        # Test decryption (just headers, not full file)
        if gpg --list-packets "$encrypted_file" &>/dev/null; then
            ((verified++))
        else
            log_error "Verification failed: $(basename "$encrypted_file")"
            ((failed++))
        fi
    done < <(find "$ENCRYPTED_DIR" -name "*.gpg" -type f -print0)

    log_success "Verified $verified encrypted files"

    if [[ $failed -gt 0 ]]; then
        log_error "$failed files failed verification"
        return 1
    fi

    return 0
}

# Create backup encryption script
create_backup_script() {
    log_info "Creating automated backup encryption script..."

    cat > /usr/local/bin/chom-encrypt-backup <<EOF
#!/bin/bash
# Automated Backup Encryption

BACKUP_DIR="$BACKUP_DIR"
ENCRYPTED_DIR="$ENCRYPTED_DIR"
GPG_KEY_ID="$GPG_KEY_ID"

# Encrypt new backup
encrypt_backup() {
    local backup_file="\$1"

    if [[ ! -f "\$backup_file" ]]; then
        echo "Error: Backup file not found: \$backup_file"
        return 1
    fi

    local filename=\$(basename "\$backup_file")
    local encrypted_file="\$ENCRYPTED_DIR/\${filename}.gpg"

    echo "Encrypting backup: \$filename"

    gpg --encrypt \\
        --recipient "\$GPG_KEY_ID" \\
        --trust-model always \\
        --compress-algo bzip2 \\
        --output "\$encrypted_file" \\
        "\$backup_file"

    if [[ \$? -eq 0 ]]; then
        chmod 600 "\$encrypted_file"
        echo "Backup encrypted: \$encrypted_file"

        # Optionally remove unencrypted backup
        if [[ "\${REMOVE_UNENCRYPTED:-false}" == "true" ]]; then
            rm -f "\$backup_file"
            echo "Removed unencrypted backup"
        fi

        return 0
    else
        echo "Encryption failed"
        return 1
    fi
}

# Main
if [[ -z "\$1" ]]; then
    echo "Usage: chom-encrypt-backup <backup-file>"
    exit 1
fi

encrypt_backup "\$1"
EOF

    chmod +x /usr/local/bin/chom-encrypt-backup

    log_success "Backup encryption script created"
}

# Setup automated encryption
setup_automated_encryption() {
    log_info "Setting up automated backup encryption..."

    # Create systemd service for backup encryption
    cat > /etc/systemd/system/chom-backup-encrypt.service <<EOF
[Unit]
Description=CHOM Backup Encryption
After=chom-backup.service

[Service]
Type=oneshot
ExecStart=/bin/bash $0 auto
StandardOutput=journal
StandardError=journal
EOF

    cat > /etc/systemd/system/chom-backup-encrypt.timer <<EOF
[Unit]
Description=Daily Backup Encryption

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable chom-backup-encrypt.timer
    systemctl start chom-backup-encrypt.timer

    log_success "Automated encryption configured"
}

# Clean old encrypted backups
cleanup_old_backups() {
    log_info "Cleaning up old encrypted backups (>${RETENTION_DAYS} days)..."

    local deleted_count=$(find "$ENCRYPTED_DIR" -name "*.gpg" -type f -mtime +${RETENTION_DAYS} -delete -print | wc -l)

    if [[ $deleted_count -gt 0 ]]; then
        log_success "Deleted $deleted_count old encrypted backups"
    else
        log_info "No old backups to delete"
    fi
}

# Test encryption/decryption
test_encryption() {
    log_info "Testing encryption/decryption..."

    local test_file="/tmp/backup_test_$(date +%s).txt"
    local encrypted_file="/tmp/backup_test_encrypted.gpg"
    local decrypted_file="/tmp/backup_test_decrypted.txt"

    # Create test file
    echo "CHOM Backup Encryption Test - $(date)" > "$test_file"
    local original_checksum=$(md5sum "$test_file" | awk '{print $1}')

    # Encrypt
    encrypt_file "$test_file" "$encrypted_file"

    # Decrypt
    decrypt_file "$encrypted_file" "$decrypted_file"

    # Verify
    local decrypted_checksum=$(md5sum "$decrypted_file" | awk '{print $1}')

    if [[ "$original_checksum" == "$decrypted_checksum" ]]; then
        log_success "Encryption/decryption test passed"
        rm -f "$test_file" "$encrypted_file" "$decrypted_file"
        return 0
    else
        log_error "Encryption/decryption test failed"
        return 1
    fi
}

# Create management helper
create_management_helper() {
    log_info "Creating backup encryption management helper..."

    cat > /usr/local/bin/chom-backup-encryption <<EOF
#!/bin/bash
# CHOM Backup Encryption Management

BACKUP_DIR="$BACKUP_DIR"
ENCRYPTED_DIR="$ENCRYPTED_DIR"
GPG_KEY_ID="$GPG_KEY_ID"

case "\$1" in
    encrypt)
        if [[ -z "\$2" ]]; then
            echo "Usage: chom-backup-encryption encrypt <file>"
            exit 1
        fi
        bash $0 encrypt "\$2"
        ;;
    decrypt)
        if [[ -z "\$2" ]] || [[ -z "\$3" ]]; then
            echo "Usage: chom-backup-encryption decrypt <encrypted-file> <output-file>"
            exit 1
        fi
        bash $0 decrypt "\$2" "\$3"
        ;;
    list)
        echo "Encrypted Backups:"
        ls -lh "\$ENCRYPTED_DIR" | grep ".gpg"
        ;;
    verify)
        echo "Verifying encrypted backups..."
        bash $0 verify
        ;;
    cleanup)
        echo "Cleaning up old backups..."
        bash $0 cleanup
        ;;
    test)
        bash $0 test
        ;;
    export-key)
        gpg --export --armor "\$GPG_KEY_ID"
        ;;
    status)
        echo "Backup Encryption Status"
        echo "========================"
        echo "GPG Key ID: \$GPG_KEY_ID"
        echo "Backup Dir: \$BACKUP_DIR"
        echo "Encrypted Dir: \$ENCRYPTED_DIR"
        echo ""
        echo "Encrypted Backups:"
        ls -1 "\$ENCRYPTED_DIR" | wc -l
        ;;
    *)
        echo "CHOM Backup Encryption Management"
        echo ""
        echo "Usage: chom-backup-encryption <command> [args]"
        echo ""
        echo "Commands:"
        echo "  encrypt <file>              Encrypt backup file"
        echo "  decrypt <enc> <out>         Decrypt backup file"
        echo "  list                        List encrypted backups"
        echo "  verify                      Verify all encrypted backups"
        echo "  cleanup                     Remove old encrypted backups"
        echo "  test                        Test encryption/decryption"
        echo "  export-key                  Export public key"
        echo "  status                      Show encryption status"
        echo ""
        ;;
esac
EOF

    chmod +x /usr/local/bin/chom-backup-encryption

    log_success "Management helper created"
}

# Display summary
display_summary() {
    echo ""
    log_success "=========================================="
    log_success "Backup Encryption Setup Complete"
    log_success "=========================================="
    echo ""

    log_info "Configuration:"
    echo "  GPG Key ID: $GPG_KEY_ID"
    echo "  Backup Directory: $BACKUP_DIR"
    echo "  Encrypted Directory: $ENCRYPTED_DIR"
    echo "  Retention: $RETENTION_DAYS days"
    echo ""

    log_info "Encrypted Backups:"
    local count=$(find "$ENCRYPTED_DIR" -name "*.gpg" 2>/dev/null | wc -l)
    echo "  Total: $count files"
    echo ""

    log_info "Features:"
    echo "  ✓ GPG encryption (RSA 4096-bit)"
    echo "  ✓ Automated encryption"
    echo "  ✓ Encryption verification"
    echo "  ✓ Automated cleanup"
    echo "  ✓ Key management"
    echo ""

    log_info "Management Commands:"
    echo "  chom-backup-encryption status      - Show status"
    echo "  chom-backup-encryption list        - List encrypted backups"
    echo "  chom-backup-encryption verify      - Verify backups"
    echo "  chom-backup-encryption test        - Test encryption"
    echo ""

    log_warning "CRITICAL SECURITY REMINDERS:"
    echo "  1. Store private key securely offline: $BACKUP_DIR/backup-private-key.asc"
    echo "  2. Never share private key"
    echo "  3. Test decryption regularly"
    echo "  4. Keep key backups in multiple secure locations"
    echo "  5. Document key recovery procedures"
    echo ""
}

# Main execution
main() {
    local command="${1:-setup}"

    log_info "CHOM Backup Encryption"
    echo ""

    check_root

    case "$command" in
        setup)
            install_dependencies
            create_directories
            setup_gpg_key
            encrypt_all_backups
            verify_encryption
            test_encryption
            create_backup_script
            create_management_helper
            setup_automated_encryption
            cleanup_old_backups
            display_summary
            ;;
        auto)
            # Automated encryption (called by timer)
            encrypt_all_backups
            cleanup_old_backups
            ;;
        encrypt)
            encrypt_file "$2" "$3"
            ;;
        decrypt)
            decrypt_file "$2" "$3"
            ;;
        verify)
            verify_encryption
            ;;
        test)
            test_encryption
            ;;
        cleanup)
            cleanup_old_backups
            ;;
        *)
            log_error "Unknown command: $command"
            echo "Usage: $0 {setup|auto|encrypt|decrypt|verify|test|cleanup}"
            exit 1
            ;;
    esac

    log_success "Backup encryption complete!"
}

# Run main function
main "$@"
