#!/bin/bash
# ============================================================================
# Secrets Management Script
# ============================================================================
# Purpose: Securely generate, encrypt, store, and rotate application secrets
# Features: GPG encryption, key rotation, secure storage
# Compliance: OWASP, SOC 2, PCI DSS
# ============================================================================

set -euo pipefail

# Configuration
SECRETS_DIR="/etc/chom/secrets"
ENCRYPTED_SECRETS_DIR="/etc/chom/secrets/encrypted"
APP_ENV_FILE="/var/www/chom/.env"
GPG_KEY_ID="${GPG_KEY_ID:-}"
BACKUP_DIR="/var/backups/chom/secrets"

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

# Create directories
create_directories() {
    log_info "Creating secrets directories..."

    mkdir -p "$SECRETS_DIR"
    mkdir -p "$ENCRYPTED_SECRETS_DIR"
    mkdir -p "$BACKUP_DIR"

    chmod 700 "$SECRETS_DIR"
    chmod 700 "$ENCRYPTED_SECRETS_DIR"
    chmod 700 "$BACKUP_DIR"

    log_success "Directories created"
}

# Install required tools
install_dependencies() {
    log_info "Installing dependencies..."

    apt-get update -qq
    apt-get install -y gnupg2 pwgen openssl

    log_success "Dependencies installed"
}

# Setup GPG key
setup_gpg_key() {
    log_info "Setting up GPG encryption key..."

    if [[ -n "$GPG_KEY_ID" ]]; then
        # Verify key exists
        if gpg --list-keys "$GPG_KEY_ID" &>/dev/null; then
            log_success "Using existing GPG key: $GPG_KEY_ID"
            return 0
        else
            log_error "GPG key $GPG_KEY_ID not found"
            exit 1
        fi
    fi

    # Check if we already have a key
    local existing_key=$(gpg --list-keys --with-colons | grep "^uid" | grep "CHOM Secrets" | head -1)

    if [[ -n "$existing_key" ]]; then
        GPG_KEY_ID=$(gpg --list-keys --with-colons | grep "^fpr" | head -1 | cut -d: -f10)
        log_success "Found existing CHOM GPG key: $GPG_KEY_ID"
        return 0
    fi

    # Generate new GPG key
    log_info "Generating new GPG key pair..."

    cat > /tmp/gpg-batch <<EOF
%echo Generating GPG key for CHOM secrets
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: CHOM Secrets
Name-Email: secrets@chom.local
Expire-Date: 0
%no-protection
%commit
%echo Done
EOF

    gpg --batch --generate-key /tmp/gpg-batch
    rm /tmp/gpg-batch

    # Get the key ID
    GPG_KEY_ID=$(gpg --list-keys --with-colons | grep "^fpr" | head -1 | cut -d: -f10)

    log_success "GPG key generated: $GPG_KEY_ID"

    # Export public key for backup
    gpg --export --armor "$GPG_KEY_ID" > "$SECRETS_DIR/gpg-public-key.asc"
    chmod 600 "$SECRETS_DIR/gpg-public-key.asc"

    log_success "Public key exported to $SECRETS_DIR/gpg-public-key.asc"
}

# Generate random secret
generate_secret() {
    local length="${1:-64}"
    local type="${2:-base64}"

    case "$type" in
        base64)
            openssl rand -base64 "$length" | tr -d '\n'
            ;;
        hex)
            openssl rand -hex "$length" | tr -d '\n'
            ;;
        alnum)
            pwgen -s -1 "$length"
            ;;
        *)
            log_error "Unknown secret type: $type"
            return 1
            ;;
    esac
}

# Generate Laravel APP_KEY
generate_app_key() {
    log_info "Generating Laravel APP_KEY..."

    local app_key="base64:$(openssl rand -base64 32)"

    echo "$app_key" > "$SECRETS_DIR/app_key"
    chmod 600 "$SECRETS_DIR/app_key"

    log_success "APP_KEY generated"
}

# Generate JWT secret
generate_jwt_secret() {
    log_info "Generating JWT_SECRET..."

    local jwt_secret=$(generate_secret 64 base64)

    echo "$jwt_secret" > "$SECRETS_DIR/jwt_secret"
    chmod 600 "$SECRETS_DIR/jwt_secret"

    log_success "JWT_SECRET generated"
}

# Generate database password
generate_db_password() {
    log_info "Generating database password..."

    local db_password=$(generate_secret 32 alnum)

    echo "$db_password" > "$SECRETS_DIR/db_password"
    chmod 600 "$SECRETS_DIR/db_password"

    log_success "Database password generated"
}

# Generate Redis password
generate_redis_password() {
    log_info "Generating Redis password..."

    local redis_password=$(generate_secret 32 base64)

    echo "$redis_password" > "$SECRETS_DIR/redis_password"
    chmod 600 "$SECRETS_DIR/redis_password"

    log_success "Redis password generated"
}

# Generate session secret
generate_session_secret() {
    log_info "Generating session secret..."

    local session_secret=$(generate_secret 64 hex)

    echo "$session_secret" > "$SECRETS_DIR/session_secret"
    chmod 600 "$SECRETS_DIR/session_secret"

    log_success "Session secret generated"
}

# Generate encryption key
generate_encryption_key() {
    log_info "Generating data encryption key..."

    local encryption_key=$(generate_secret 32 hex)

    echo "$encryption_key" > "$SECRETS_DIR/encryption_key"
    chmod 600 "$SECRETS_DIR/encryption_key"

    log_success "Encryption key generated"
}

# Generate API tokens
generate_api_tokens() {
    log_info "Generating API tokens..."

    # Prometheus API token
    local prometheus_token=$(generate_secret 64 hex)
    echo "$prometheus_token" > "$SECRETS_DIR/prometheus_token"

    # Grafana API token
    local grafana_token=$(generate_secret 64 hex)
    echo "$grafana_token" > "$SECRETS_DIR/grafana_token"

    # Loki API token
    local loki_token=$(generate_secret 64 hex)
    echo "$loki_token" > "$SECRETS_DIR/loki_token"

    chmod 600 "$SECRETS_DIR"/*_token

    log_success "API tokens generated"
}

# Encrypt secret
encrypt_secret() {
    local secret_file="$1"
    local encrypted_file="${ENCRYPTED_SECRETS_DIR}/$(basename "$secret_file").gpg"

    if [[ ! -f "$secret_file" ]]; then
        log_error "Secret file not found: $secret_file"
        return 1
    fi

    gpg --encrypt \
        --recipient "$GPG_KEY_ID" \
        --trust-model always \
        --output "$encrypted_file" \
        "$secret_file"

    chmod 600 "$encrypted_file"

    log_success "Encrypted: $(basename "$secret_file")"
}

# Decrypt secret
decrypt_secret() {
    local encrypted_file="$1"
    local output_file="${2:-}"

    if [[ ! -f "$encrypted_file" ]]; then
        log_error "Encrypted file not found: $encrypted_file"
        return 1
    fi

    if [[ -z "$output_file" ]]; then
        output_file="${encrypted_file%.gpg}"
    fi

    gpg --decrypt \
        --output "$output_file" \
        "$encrypted_file"

    chmod 600 "$output_file"

    log_success "Decrypted: $(basename "$encrypted_file")"
}

# Encrypt all secrets
encrypt_all_secrets() {
    log_info "Encrypting all secrets..."

    for secret_file in "$SECRETS_DIR"/*; do
        if [[ -f "$secret_file" ]] && [[ "$secret_file" != *.gpg ]] && [[ "$secret_file" != *.asc ]]; then
            encrypt_secret "$secret_file"
        fi
    done

    log_success "All secrets encrypted"
}

# Decrypt all secrets
decrypt_all_secrets() {
    log_info "Decrypting all secrets..."

    for encrypted_file in "$ENCRYPTED_SECRETS_DIR"/*.gpg; do
        if [[ -f "$encrypted_file" ]]; then
            local output_file="$SECRETS_DIR/$(basename "${encrypted_file%.gpg}")"
            decrypt_secret "$encrypted_file" "$output_file"
        fi
    done

    log_success "All secrets decrypted"
}

# Load secrets into environment file
load_secrets_to_env() {
    log_info "Loading secrets to environment file..."

    if [[ ! -f "$APP_ENV_FILE" ]]; then
        log_error "Environment file not found: $APP_ENV_FILE"
        return 1
    fi

    # Backup existing .env
    cp "$APP_ENV_FILE" "${APP_ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

    # Load secrets
    local app_key=$(cat "$SECRETS_DIR/app_key" 2>/dev/null || echo "")
    local jwt_secret=$(cat "$SECRETS_DIR/jwt_secret" 2>/dev/null || echo "")
    local db_password=$(cat "$SECRETS_DIR/db_password" 2>/dev/null || echo "")
    local redis_password=$(cat "$SECRETS_DIR/redis_password" 2>/dev/null || echo "")

    # Update .env file
    if [[ -n "$app_key" ]]; then
        sed -i "s|^APP_KEY=.*|APP_KEY=$app_key|" "$APP_ENV_FILE"
        log_success "APP_KEY updated in .env"
    fi

    if [[ -n "$jwt_secret" ]]; then
        if grep -q "^JWT_SECRET=" "$APP_ENV_FILE"; then
            sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$jwt_secret|" "$APP_ENV_FILE"
        else
            echo "JWT_SECRET=$jwt_secret" >> "$APP_ENV_FILE"
        fi
        log_success "JWT_SECRET updated in .env"
    fi

    if [[ -n "$db_password" ]]; then
        sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$db_password|" "$APP_ENV_FILE"
        log_success "DB_PASSWORD updated in .env"
    fi

    if [[ -n "$redis_password" ]]; then
        sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=$redis_password|" "$APP_ENV_FILE"
        log_success "REDIS_PASSWORD updated in .env"
    fi

    # Set secure permissions
    chmod 600 "$APP_ENV_FILE"
    chown www-data:www-data "$APP_ENV_FILE" 2>/dev/null || true

    log_success "Secrets loaded to environment file"
}

# Rotate secrets
rotate_secrets() {
    log_warning "Starting secret rotation..."

    # Backup current secrets
    local backup_file="$BACKUP_DIR/secrets_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    tar -czf "$backup_file" -C "$(dirname "$SECRETS_DIR")" "$(basename "$SECRETS_DIR")"

    log_success "Current secrets backed up to: $backup_file"

    # Generate new secrets
    generate_app_key
    generate_jwt_secret
    generate_session_secret
    generate_encryption_key

    # Encrypt new secrets
    encrypt_all_secrets

    log_success "Secrets rotated successfully"
    log_warning "Remember to update database and Redis passwords manually!"
}

# Backup secrets
backup_secrets() {
    log_info "Backing up secrets..."

    local backup_file="$BACKUP_DIR/secrets_$(date +%Y%m%d_%H%M%S).tar.gz"

    tar -czf "$backup_file" \
        -C "$(dirname "$SECRETS_DIR")" \
        "$(basename "$SECRETS_DIR")"

    chmod 600 "$backup_file"

    log_success "Secrets backed up to: $backup_file"
}

# Display secrets summary
display_secrets_summary() {
    echo ""
    log_success "=========================================="
    log_success "Secrets Management Summary"
    log_success "=========================================="
    echo ""

    log_info "Generated Secrets:"
    for secret_file in "$SECRETS_DIR"/*; do
        if [[ -f "$secret_file" ]] && [[ "$secret_file" != *.gpg ]] && [[ "$secret_file" != *.asc ]]; then
            echo "  ✓ $(basename "$secret_file")"
        fi
    done

    echo ""
    log_info "Encrypted Secrets:"
    for encrypted_file in "$ENCRYPTED_SECRETS_DIR"/*.gpg; do
        if [[ -f "$encrypted_file" ]]; then
            echo "  ✓ $(basename "$encrypted_file")"
        fi
    done

    echo ""
    log_info "GPG Key ID: $GPG_KEY_ID"
    log_info "Secrets Directory: $SECRETS_DIR"
    log_info "Encrypted Directory: $ENCRYPTED_SECRETS_DIR"
    log_info "Backup Directory: $BACKUP_DIR"
    echo ""

    log_warning "SECURITY REMINDERS:"
    echo "  1. Keep GPG private key secure and backed up"
    echo "  2. Never commit unencrypted secrets to git"
    echo "  3. Rotate secrets regularly (every 90 days)"
    echo "  4. Use different secrets for each environment"
    echo "  5. Restrict access to secrets directory (chmod 700)"
    echo ""
}

# Create secrets management helper
create_secrets_helper() {
    log_info "Creating secrets management helper..."

    local helper_script="/usr/local/bin/chom-secrets"

    cat > "$helper_script" <<EOF
#!/bin/bash
# CHOM Secrets Management Helper

SECRETS_DIR="$SECRETS_DIR"
ENCRYPTED_SECRETS_DIR="$ENCRYPTED_SECRETS_DIR"
GPG_KEY_ID="$GPG_KEY_ID"

case "\$1" in
    generate)
        bash $0 generate
        ;;
    encrypt)
        for secret_file in "\$SECRETS_DIR"/*; do
            if [[ -f "\$secret_file" ]] && [[ "\$secret_file" != *.gpg ]] && [[ "\$secret_file" != *.asc ]]; then
                gpg --encrypt --recipient "\$GPG_KEY_ID" --trust-model always --output "\${ENCRYPTED_SECRETS_DIR}/\$(basename "\$secret_file").gpg" "\$secret_file"
                echo "Encrypted: \$(basename "\$secret_file")"
            fi
        done
        ;;
    decrypt)
        for encrypted_file in "\$ENCRYPTED_SECRETS_DIR"/*.gpg; do
            if [[ -f "\$encrypted_file" ]]; then
                gpg --decrypt --output "\${SECRETS_DIR}/\$(basename "\${encrypted_file%.gpg}")" "\$encrypted_file"
                echo "Decrypted: \$(basename "\$encrypted_file")"
            fi
        done
        ;;
    rotate)
        read -p "Rotate all secrets? This will generate new keys. (yes/no): " confirm
        if [[ "\$confirm" == "yes" ]]; then
            bash $(readlink -f "$0") rotate
        fi
        ;;
    backup)
        backup_file="$BACKUP_DIR/secrets_\$(date +%Y%m%d_%H%M%S).tar.gz"
        tar -czf "\$backup_file" -C "\$(dirname "\$SECRETS_DIR")" "\$(basename "\$SECRETS_DIR")"
        echo "Backup created: \$backup_file"
        ;;
    list)
        echo "Plaintext Secrets:"
        ls -lh "\$SECRETS_DIR" | grep -v ".gpg" | grep -v ".asc" | grep -v "^d" | grep -v "^total"
        echo ""
        echo "Encrypted Secrets:"
        ls -lh "\$ENCRYPTED_SECRETS_DIR"
        ;;
    show)
        if [[ -z "\$2" ]]; then
            echo "Usage: chom-secrets show <secret-name>"
            exit 1
        fi
        if [[ -f "\$SECRETS_DIR/\$2" ]]; then
            cat "\$SECRETS_DIR/\$2"
            echo ""
        else
            echo "Secret not found: \$2"
        fi
        ;;
    *)
        echo "CHOM Secrets Management"
        echo ""
        echo "Usage: chom-secrets <command> [args]"
        echo ""
        echo "Commands:"
        echo "  generate            Generate new secrets"
        echo "  encrypt             Encrypt all secrets"
        echo "  decrypt             Decrypt all secrets"
        echo "  rotate              Rotate all secrets (generates new)"
        echo "  backup              Backup secrets"
        echo "  list                List all secrets"
        echo "  show <name>         Show specific secret"
        echo ""
        ;;
esac
EOF

    chmod +x "$helper_script"
    log_success "Secrets helper created: $helper_script"
}

# Main execution
main() {
    local command="${1:-generate}"

    log_info "CHOM Secrets Management"
    echo ""

    check_root
    create_directories
    install_dependencies
    setup_gpg_key

    case "$command" in
        generate)
            generate_app_key
            generate_jwt_secret
            generate_db_password
            generate_redis_password
            generate_session_secret
            generate_encryption_key
            generate_api_tokens
            encrypt_all_secrets
            backup_secrets
            create_secrets_helper
            display_secrets_summary
            ;;
        encrypt)
            encrypt_all_secrets
            ;;
        decrypt)
            decrypt_all_secrets
            ;;
        rotate)
            rotate_secrets
            ;;
        load)
            decrypt_all_secrets
            load_secrets_to_env
            ;;
        *)
            log_error "Unknown command: $command"
            echo "Usage: $0 {generate|encrypt|decrypt|rotate|load}"
            exit 1
            ;;
    esac

    log_success "Secrets management complete!"
}

# Run main function
main "$@"
