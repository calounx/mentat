#!/usr/bin/env bash
# Auto-generate deployment secrets (IDEMPOTENT)
# Creates .deployment-secrets file with auto-generated values
# Only prompts for essential external credentials
# Usage: ./generate-deployment-secrets.sh [--output-file path] [--interactive]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utils/logging.sh"

# Configuration
OUTPUT_FILE="${OUTPUT_FILE:-${SCRIPT_DIR}/../.deployment-secrets}"
INTERACTIVE="${INTERACTIVE:-false}"
FORCE_REGENERATE="${FORCE_REGENERATE:-false}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --output-file)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --interactive)
            INTERACTIVE=true
            shift
            ;;
        --force)
            FORCE_REGENERATE=true
            shift
            ;;
        *)
            log_error "Unknown argument: $1"
            echo "Usage: $0 [--output-file path] [--interactive] [--force]"
            exit 1
            ;;
    esac
done

init_deployment_log "generate-secrets-$(date +%Y%m%d_%H%M%S)"
log_section "Generating Deployment Secrets"

# Generate random string
generate_random() {
    local length="${1:-32}"
    openssl rand -base64 48 | tr -d "=+/" | cut -c1-${length}
}

# Generate Laravel app key
generate_app_key() {
    echo "base64:$(openssl rand -base64 32)"
}

# Prompt for user input with default
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local value

    if [[ "$INTERACTIVE" == "true" ]]; then
        read -p "$prompt [$default]: " value
        echo "${value:-$default}"
    else
        echo "$default"
    fi
}

# Prompt for user input (required)
prompt_required() {
    local prompt="$1"
    local value=""

    while [[ -z "$value" ]]; do
        read -p "$prompt (required): " value
        if [[ -z "$value" ]]; then
            echo "This value is required. Please enter a value."
        fi
    done

    echo "$value"
}

# Prompt for password (hidden input)
prompt_password() {
    local prompt="$1"
    local value=""

    while [[ -z "$value" ]]; do
        read -s -p "$prompt (required, hidden): " value
        echo ""
        if [[ -z "$value" ]]; then
            echo "This value is required. Please enter a value."
        fi
    done

    echo "$value"
}

# Load existing secrets if file exists
load_existing_secrets() {
    if [[ -f "$OUTPUT_FILE" ]] && [[ "$FORCE_REGENERATE" != "true" ]]; then
        log_success "Loading existing secrets from $OUTPUT_FILE"
        source "$OUTPUT_FILE"
        return 0
    fi
    return 1
}

# Generate all secrets
generate_secrets() {
    log_step "Generating deployment secrets"

    # Check if file exists and not forcing regenerate
    local existing_file=false
    if [[ -f "$OUTPUT_FILE" ]] && [[ "$FORCE_REGENERATE" != "true" ]]; then
        existing_file=true
        log_warning "Secrets file already exists: $OUTPUT_FILE"
        log_info "Preserving existing values. Use --force to regenerate."
        source "$OUTPUT_FILE"
    fi

    # Server Configuration
    log_info "Collecting server configuration..."

    if [[ -z "${MENTAT_HOST:-}" ]]; then
        MENTAT_HOST=$(prompt_with_default "Mentat (observability) hostname" "mentat.arewel.com")
    fi

    if [[ -z "${LANDSRAAD_HOST:-}" ]]; then
        LANDSRAAD_HOST=$(prompt_with_default "Landsraad (application) hostname" "landsraad.arewel.com")
    fi

    if [[ -z "${DEPLOY_USER:-}" ]]; then
        DEPLOY_USER=$(prompt_with_default "Deployment user" "stilgar")
    fi

    # Application Configuration
    log_info "Collecting application configuration..."

    if [[ -z "${APP_NAME:-}" ]]; then
        APP_NAME=$(prompt_with_default "Application name" "CHOM")
    fi

    if [[ -z "${APP_ENV:-}" ]]; then
        APP_ENV=$(prompt_with_default "Application environment" "production")
    fi

    if [[ -z "${APP_DOMAIN:-}" ]]; then
        if [[ "$INTERACTIVE" == "true" ]]; then
            APP_DOMAIN=$(prompt_required "Application domain (e.g., chom.arewel.com)")
        else
            APP_DOMAIN="chom.arewel.com"
        fi
    fi

    if [[ -z "${APP_URL:-}" ]]; then
        APP_URL="https://${APP_DOMAIN}"
    fi

    # Generate Laravel secrets
    if [[ -z "${APP_KEY:-}" ]]; then
        APP_KEY=$(generate_app_key)
        log_success "Generated APP_KEY"
    fi

    # Database Configuration
    log_info "Generating database credentials..."

    if [[ -z "${DB_NAME:-}" ]]; then
        DB_NAME=$(prompt_with_default "Database name" "chom")
    fi

    if [[ -z "${DB_USER:-}" ]]; then
        DB_USER=$(prompt_with_default "Database user" "chom")
    fi

    if [[ -z "${DB_PASSWORD:-}" ]]; then
        DB_PASSWORD=$(generate_random 32)
        log_success "Generated DB_PASSWORD"
    fi

    # Redis Configuration
    if [[ -z "${REDIS_PASSWORD:-}" ]]; then
        REDIS_PASSWORD=$(generate_random 32)
        log_success "Generated REDIS_PASSWORD"
    fi

    # Email Configuration (only prompt if interactive)
    log_info "Collecting email configuration..."

    if [[ -z "${MAIL_MAILER:-}" ]]; then
        MAIL_MAILER=$(prompt_with_default "Mail mailer (smtp/sendmail/log)" "log")
    fi

    if [[ "$MAIL_MAILER" != "log" ]] && [[ "$INTERACTIVE" == "true" ]]; then
        if [[ -z "${MAIL_HOST:-}" ]]; then
            MAIL_HOST=$(prompt_with_default "Mail host" "smtp.example.com")
        fi

        if [[ -z "${MAIL_PORT:-}" ]]; then
            MAIL_PORT=$(prompt_with_default "Mail port" "587")
        fi

        if [[ -z "${MAIL_USERNAME:-}" ]]; then
            MAIL_USERNAME=$(prompt_with_default "Mail username" "")
        fi

        if [[ -z "${MAIL_PASSWORD:-}" ]]; then
            MAIL_PASSWORD=$(prompt_with_default "Mail password" "")
        fi

        if [[ -z "${MAIL_ENCRYPTION:-}" ]]; then
            MAIL_ENCRYPTION=$(prompt_with_default "Mail encryption (tls/ssl)" "tls")
        fi

        if [[ -z "${MAIL_FROM_ADDRESS:-}" ]]; then
            MAIL_FROM_ADDRESS=$(prompt_with_default "Mail from address" "noreply@${APP_DOMAIN}")
        fi

        if [[ -z "${MAIL_FROM_NAME:-}" ]]; then
            MAIL_FROM_NAME=$(prompt_with_default "Mail from name" "${APP_NAME}")
        fi
    else
        MAIL_HOST="${MAIL_HOST:-localhost}"
        MAIL_PORT="${MAIL_PORT:-1025}"
        MAIL_USERNAME="${MAIL_USERNAME:-}"
        MAIL_PASSWORD="${MAIL_PASSWORD:-}"
        MAIL_ENCRYPTION="${MAIL_ENCRYPTION:-null}"
        MAIL_FROM_ADDRESS="${MAIL_FROM_ADDRESS:-noreply@${APP_DOMAIN}}"
        MAIL_FROM_NAME="${MAIL_FROM_NAME:-${APP_NAME}}"
    fi

    # SSL/TLS Configuration
    log_info "Collecting SSL/TLS configuration..."

    if [[ -z "${SSL_EMAIL:-}" ]]; then
        if [[ "$INTERACTIVE" == "true" ]]; then
            SSL_EMAIL=$(prompt_required "Email for SSL certificates (Let's Encrypt)")
        else
            SSL_EMAIL="${MAIL_FROM_ADDRESS}"
        fi
    fi

    # VPS Provider Configuration (optional)
    if [[ "$INTERACTIVE" == "true" ]]; then
        log_info "Collecting VPS provider credentials (optional)..."

        if [[ -z "${OVH_APP_KEY:-}" ]]; then
            read -p "OVH Application Key (optional, press Enter to skip): " OVH_APP_KEY
        fi

        if [[ -n "${OVH_APP_KEY}" ]] && [[ -z "${OVH_APP_SECRET:-}" ]]; then
            OVH_APP_SECRET=$(prompt_password "OVH Application Secret")
        fi

        if [[ -n "${OVH_APP_KEY}" ]] && [[ -z "${OVH_CONSUMER_KEY:-}" ]]; then
            OVH_CONSUMER_KEY=$(prompt_password "OVH Consumer Key")
        fi
    else
        OVH_APP_KEY="${OVH_APP_KEY:-}"
        OVH_APP_SECRET="${OVH_APP_SECRET:-}"
        OVH_CONSUMER_KEY="${OVH_CONSUMER_KEY:-}"
    fi

    # Session & Cache
    if [[ -z "${SESSION_DRIVER:-}" ]]; then
        SESSION_DRIVER="redis"
    fi

    if [[ -z "${CACHE_DRIVER:-}" ]]; then
        CACHE_DRIVER="redis"
    fi

    if [[ -z "${QUEUE_CONNECTION:-}" ]]; then
        QUEUE_CONNECTION="redis"
    fi

    # Backup encryption key
    if [[ -z "${BACKUP_ENCRYPTION_KEY:-}" ]]; then
        BACKUP_ENCRYPTION_KEY=$(generate_random 32)
        log_success "Generated BACKUP_ENCRYPTION_KEY"
    fi

    # JWT Secret (if using)
    if [[ -z "${JWT_SECRET:-}" ]]; then
        JWT_SECRET=$(generate_random 64)
        log_success "Generated JWT_SECRET"
    fi

    log_success "All secrets generated/collected"
}

# Write secrets to file
write_secrets_file() {
    log_step "Writing secrets to $OUTPUT_FILE"

    # Create backup if file exists
    if [[ -f "$OUTPUT_FILE" ]]; then
        local backup_file="${OUTPUT_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$OUTPUT_FILE" "$backup_file"
        log_info "Created backup: $backup_file"
    fi

    # Write secrets file
    cat > "$OUTPUT_FILE" <<EOF
#!/usr/bin/env bash
# Deployment Secrets - Generated on $(date -Iseconds)
# This file contains sensitive credentials - DO NOT commit to version control
# File permissions: 600 (read/write for owner only)

# ============================================================================
# SERVER CONFIGURATION
# ============================================================================
export MENTAT_HOST="${MENTAT_HOST}"
export LANDSRAAD_HOST="${LANDSRAAD_HOST}"
export DEPLOY_USER="${DEPLOY_USER}"

# ============================================================================
# APPLICATION CONFIGURATION
# ============================================================================
export APP_NAME="${APP_NAME}"
export APP_ENV="${APP_ENV}"
export APP_DEBUG="false"
export APP_DOMAIN="${APP_DOMAIN}"
export APP_URL="${APP_URL}"
export APP_KEY="${APP_KEY}"

# ============================================================================
# DATABASE CONFIGURATION
# ============================================================================
export DB_CONNECTION="pgsql"
export DB_HOST="127.0.0.1"
export DB_PORT="5432"
export DB_NAME="${DB_NAME}"
export DB_USER="${DB_USER}"
export DB_PASSWORD="${DB_PASSWORD}"

# ============================================================================
# REDIS CONFIGURATION
# ============================================================================
export REDIS_HOST="127.0.0.1"
export REDIS_PORT="6379"
export REDIS_PASSWORD="${REDIS_PASSWORD}"

# ============================================================================
# CACHE & SESSION CONFIGURATION
# ============================================================================
export SESSION_DRIVER="${SESSION_DRIVER}"
export CACHE_DRIVER="${CACHE_DRIVER}"
export QUEUE_CONNECTION="${QUEUE_CONNECTION}"

# ============================================================================
# EMAIL CONFIGURATION
# ============================================================================
export MAIL_MAILER="${MAIL_MAILER}"
export MAIL_HOST="${MAIL_HOST}"
export MAIL_PORT="${MAIL_PORT}"
export MAIL_USERNAME="${MAIL_USERNAME}"
export MAIL_PASSWORD="${MAIL_PASSWORD}"
export MAIL_ENCRYPTION="${MAIL_ENCRYPTION}"
export MAIL_FROM_ADDRESS="${MAIL_FROM_ADDRESS}"
export MAIL_FROM_NAME="${MAIL_FROM_NAME}"

# ============================================================================
# SSL/TLS CONFIGURATION
# ============================================================================
export SSL_EMAIL="${SSL_EMAIL}"

# ============================================================================
# BACKUP CONFIGURATION
# ============================================================================
export BACKUP_ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY}"

# ============================================================================
# JWT CONFIGURATION (if using)
# ============================================================================
export JWT_SECRET="${JWT_SECRET}"

# ============================================================================
# VPS PROVIDER CREDENTIALS (optional)
# ============================================================================
export OVH_APP_KEY="${OVH_APP_KEY}"
export OVH_APP_SECRET="${OVH_APP_SECRET}"
export OVH_CONSUMER_KEY="${OVH_CONSUMER_KEY}"

# ============================================================================
# MONITORING & OBSERVABILITY
# ============================================================================
export PROMETHEUS_URL="http://${MENTAT_HOST}:9090"
export GRAFANA_URL="http://${MENTAT_HOST}:3000"
export LOKI_URL="http://${MENTAT_HOST}:3100"

# ============================================================================
# DEPLOYMENT CONFIGURATION
# ============================================================================
export DEPLOY_BRANCH="${DEPLOY_BRANCH:-main}"
export KEEP_RELEASES="${KEEP_RELEASES:-5}"
export HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-30}"

# Mark this file as loaded
export DEPLOYMENT_SECRETS_LOADED="true"
EOF

    # Set strict permissions
    chmod 600 "$OUTPUT_FILE"

    log_success "Secrets file created: $OUTPUT_FILE"
}

# Display summary
display_summary() {
    log_section "Deployment Secrets Summary"

    log_info "Secrets file: $OUTPUT_FILE"
    log_info "File permissions: $(stat -c %a "$OUTPUT_FILE")"
    log_info ""
    log_info "Generated secrets:"
    log_info "  - APP_KEY (Laravel application key)"
    log_info "  - DB_PASSWORD (PostgreSQL password)"
    log_info "  - REDIS_PASSWORD (Redis authentication)"
    log_info "  - BACKUP_ENCRYPTION_KEY (Backup encryption)"
    log_info "  - JWT_SECRET (JWT token signing)"
    log_info ""
    log_info "Configuration:"
    log_info "  - Servers: $MENTAT_HOST, $LANDSRAAD_HOST"
    log_info "  - Application: $APP_NAME ($APP_ENV)"
    log_info "  - Domain: $APP_DOMAIN"
    log_info "  - Database: $DB_NAME (user: $DB_USER)"
    log_info "  - Mail: $MAIL_MAILER"
    log_info "  - SSL Email: $SSL_EMAIL"

    if [[ -n "${OVH_APP_KEY}" ]]; then
        log_info "  - OVH API: Configured"
    fi

    log_info ""
    log_warning "IMPORTANT: Keep this file secure!"
    log_warning "  - File contains sensitive credentials"
    log_warning "  - Do NOT commit to version control"
    log_warning "  - Do NOT share publicly"
    log_warning "  - Backup securely if needed"
}

# Main execution
main() {
    start_timer

    print_header "Deployment Secrets Generator"

    if [[ "$INTERACTIVE" == "true" ]]; then
        log_info "Running in INTERACTIVE mode - you will be prompted for values"
    else
        log_info "Running in AUTOMATED mode - using defaults where possible"
        log_info "Use --interactive flag to provide custom values"
    fi

    log_info ""

    generate_secrets
    write_secrets_file
    display_summary

    end_timer "Secrets generation"

    print_header "Secrets Generation Complete"
    log_success "Deployment secrets ready: $OUTPUT_FILE"
    log_info ""
    log_info "Load secrets in your shell:"
    log_info "  source $OUTPUT_FILE"
    log_info ""
    log_info "Use in deployment scripts:"
    log_info "  source $OUTPUT_FILE && ./deploy-chom-automated.sh"
}

main
