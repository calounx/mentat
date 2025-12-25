#!/bin/bash
#===============================================================================
# Migration Script: Plaintext to Secure Secrets
# Migrates existing deployments from plaintext passwords to secure secrets
#
# This script:
# 1. Backs up current configuration
# 2. Extracts plaintext passwords from config files
# 3. Stores them as secrets with proper permissions
# 4. Updates config files to use secret references
# 5. Verifies the migration was successful
#
# SECURITY: This script handles sensitive data - run it carefully
#
# Usage:
#   ./migrate-plaintext-secrets.sh [--dry-run] [--backup-only]
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
readonly CONFIG_FILE="$STACK_ROOT/config/global.yaml"
readonly BACKUP_DIR="$STACK_ROOT/.migration-backup-$(date +%Y%m%d-%H%M%S)"

#===============================================================================
# FLAGS
#===============================================================================
DRY_RUN=false
BACKUP_ONLY=false

#===============================================================================
# ARGUMENT PARSING
#===============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --backup-only)
                BACKUP_ONLY=true
                shift
                ;;
            --help|-h)
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

usage() {
    cat << EOF
Migration Script: Plaintext to Secure Secrets

Usage: $0 [OPTIONS]

OPTIONS:
    --dry-run       Show what would be done without making changes
    --backup-only   Only create backups, don't migrate
    --help          Show this help message

DESCRIPTION:
    Migrates existing observability stack from plaintext passwords
    to secure secrets management.

    Steps performed:
    1. Create backup of current configuration
    2. Extract passwords from global.yaml
    3. Store as secure secrets (600 permissions)
    4. Update global.yaml to use ${SECRET:name} references
    5. Verify migration succeeded

EXAMPLES:
    # Preview migration
    $0 --dry-run

    # Create backup only
    $0 --backup-only

    # Perform migration
    sudo $0

IMPORTANT:
    - Run this as root (sudo)
    - Review changes before restarting services
    - Keep backup in case of issues
    - Test after migration

EOF
}

#===============================================================================
# BACKUP FUNCTIONS
#===============================================================================

create_backup() {
    log_info "Creating backup..."

    # Ensure backup directory exists
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"

    # Backup global.yaml
    if [[ -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "$BACKUP_DIR/global.yaml.backup"
        log_success "Backed up: $CONFIG_FILE"
    fi

    # Backup existing secrets directory if it exists
    if [[ -d "$STACK_ROOT/secrets" ]]; then
        cp -r "$STACK_ROOT/secrets" "$BACKUP_DIR/secrets.backup"
        log_success "Backed up: existing secrets/"
    fi

    # Backup nginx htpasswd files if they exist
    for file in /etc/nginx/.htpasswd_prometheus /etc/nginx/.htpasswd_loki; do
        if [[ -f "$file" ]]; then
            cp "$file" "$BACKUP_DIR/$(basename "$file").backup"
            log_success "Backed up: $file"
        fi
    done

    # Create manifest
    cat > "$BACKUP_DIR/MANIFEST.txt" << EOF
Observability Stack Migration Backup
Created: $(date)
Migration Script Version: 1.0

Contents:
- global.yaml.backup: Original configuration file
- secrets.backup/: Existing secrets (if any)
- .htpasswd_*.backup: Nginx password files

To restore:
1. Stop all services
2. cp global.yaml.backup $CONFIG_FILE
3. cp -r secrets.backup/ $STACK_ROOT/secrets/
4. Restart services

EOF

    log_success "Backup created: $BACKUP_DIR"
    log_info "Backup manifest:"
    cat "$BACKUP_DIR/MANIFEST.txt"
}

#===============================================================================
# EXTRACTION FUNCTIONS
#===============================================================================

extract_password() {
    local yaml_path="$1"
    local description="$2"

    local value
    case "$yaml_path" in
        smtp.password)
            value=$(yaml_get_nested "$CONFIG_FILE" "smtp" "password")
            ;;
        grafana.admin_password)
            value=$(yaml_get_nested "$CONFIG_FILE" "grafana" "admin_password")
            ;;
        security.prometheus_basic_auth_password)
            value=$(yaml_get_nested "$CONFIG_FILE" "security" "prometheus_basic_auth_password")
            ;;
        security.loki_basic_auth_password)
            value=$(yaml_get_nested "$CONFIG_FILE" "security" "loki_basic_auth_password")
            ;;
        *)
            log_error "Unknown password path: $yaml_path"
            return 1
            ;;
    esac

    # Check if already using secret reference
    if [[ "$value" =~ ^\$\{SECRET: ]]; then
        log_skip "$description - already using secret reference"
        return 1
    fi

    # Check if it's a placeholder
    if is_placeholder "$value"; then
        log_warn "$description - contains placeholder: $value"
        return 1
    fi

    # Return the extracted value
    echo "$value"
    return 0
}

#===============================================================================
# MIGRATION FUNCTIONS
#===============================================================================

migrate_secret() {
    local secret_name="$1"
    local yaml_path="$2"
    local description="$3"

    log_info "Migrating: $description"

    # Extract password
    local password
    if ! password=$(extract_password "$yaml_path" "$description"); then
        return 0  # Already migrated or placeholder
    fi

    if [[ -z "$password" ]]; then
        log_warn "$description - no password found, skipping"
        return 0
    fi

    log_debug "Extracted password (length: ${#password})"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would store: secrets/$secret_name (${#password} chars)"
        log_info "[DRY RUN] Would update: $yaml_path -> \${SECRET:$secret_name}"
        return 0
    fi

    # Store as secret
    store_secret "$secret_name" "$password"
    log_success "Stored secret: $secret_name"

    return 0
}

update_config_file() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would update config file with secret references"
        return 0
    fi

    log_info "Updating configuration file..."

    # Create temporary file
    local temp_file
    temp_file=$(mktemp)

    # Read and update config file
    awk '
    /^  password:/ && prev ~ /smtp:/ {
        print "  # SECURITY: Password stored in secrets/smtp_password"
        print "  password: ${SECRET:smtp_password}"
        next
    }
    /^  admin_password:/ && prev ~ /grafana:/ {
        print "  # SECURITY: Password stored in secrets/grafana_admin_password"
        print "  admin_password: ${SECRET:grafana_admin_password}"
        next
    }
    /^  prometheus_basic_auth_password:/ {
        print "  # SECURITY: Password stored in secrets/prometheus_basic_auth_password"
        print "  prometheus_basic_auth_password: ${SECRET:prometheus_basic_auth_password}"
        next
    }
    /^  loki_basic_auth_password:/ {
        print "  # SECURITY: Password stored in secrets/loki_basic_auth_password"
        print "  loki_basic_auth_password: ${SECRET:loki_basic_auth_password}"
        next
    }
    {
        print
        prev = $0
    }
    ' "$CONFIG_FILE" > "$temp_file"

    # Validate the new file (check it's not empty)
    if [[ ! -s "$temp_file" ]]; then
        log_error "Generated config file is empty, aborting"
        rm -f "$temp_file"
        return 1
    fi

    # Replace original file
    mv "$temp_file" "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"

    log_success "Updated configuration file"
}

#===============================================================================
# VERIFICATION FUNCTIONS
#===============================================================================

verify_migration() {
    log_info "Verifying migration..."

    local errors=0

    # Check that secrets exist
    local secrets=(
        "smtp_password"
        "grafana_admin_password"
        "prometheus_basic_auth_password"
        "loki_basic_auth_password"
    )

    for secret in "${secrets[@]}"; do
        if secret_exists "$secret"; then
            log_success "Secret exists: $secret"
        else
            log_error "Secret missing: $secret"
            ((errors++))
        fi
    done

    # Check that config file uses secret references
    if grep -q '\${SECRET:smtp_password}' "$CONFIG_FILE"; then
        log_success "Config uses secret reference: smtp_password"
    else
        log_error "Config missing secret reference: smtp_password"
        ((errors++))
    fi

    # Check permissions
    local secrets_dir
    secrets_dir="$(get_secrets_dir)"

    if [[ -d "$secrets_dir" ]]; then
        local dir_perms
        dir_perms=$(stat -c "%a" "$secrets_dir")
        if [[ "$dir_perms" == "700" ]]; then
            log_success "Secrets directory permissions correct: 700"
        else
            log_warn "Secrets directory permissions: $dir_perms (should be 700)"
        fi

        for secret_file in "$secrets_dir"/*; do
            if [[ -f "$secret_file" ]]; then
                local file_perms
                file_perms=$(stat -c "%a" "$secret_file")
                if [[ "$file_perms" == "600" ]]; then
                    log_success "Secret file permissions correct: $(basename "$secret_file")"
                else
                    log_error "Secret file permissions: $(basename "$secret_file"): $file_perms (should be 600)"
                    ((errors++))
                fi
            fi
        done
    fi

    if [[ $errors -eq 0 ]]; then
        log_success "Migration verification passed!"
        return 0
    else
        log_error "Migration verification failed with $errors error(s)"
        return 1
    fi
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

main() {
    log_info "Observability Stack - Secrets Migration"
    log_info "========================================"
    echo

    # Parse arguments
    parse_args "$@"

    # Check we're running as root
    check_root

    # Check config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_fatal "Configuration file not found: $CONFIG_FILE"
    fi

    # Create backup
    create_backup
    echo

    if [[ "$BACKUP_ONLY" == "true" ]]; then
        log_success "Backup completed. Exiting (--backup-only specified)"
        exit 0
    fi

    # Show dry run notice
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY RUN MODE - No changes will be made"
        echo
    fi

    # Migrate each secret
    log_info "Extracting and migrating secrets..."
    echo

    migrate_secret "smtp_password" "smtp.password" "SMTP password"
    migrate_secret "grafana_admin_password" "grafana.admin_password" "Grafana admin password"
    migrate_secret "prometheus_basic_auth_password" "security.prometheus_basic_auth_password" "Prometheus HTTP auth"
    migrate_secret "loki_basic_auth_password" "security.loki_basic_auth_password" "Loki HTTP auth"

    echo

    # Update config file
    update_config_file
    echo

    # Verify if not dry run
    if [[ "$DRY_RUN" != "true" ]]; then
        verify_migration
        echo

        log_success "Migration completed successfully!"
        echo
        log_info "Next steps:"
        log_info "1. Review the changes in: $CONFIG_FILE"
        log_info "2. Verify secrets in: $(get_secrets_dir)/"
        log_info "3. Test with: sudo ./scripts/setup-observability.sh"
        log_info "4. If everything works, you can remove: $BACKUP_DIR"
        echo
        log_warn "Important:"
        log_warn "- Keep the backup until you verify everything works"
        log_warn "- Document the secret locations for your team"
        log_warn "- Set up a backup strategy for the secrets/ directory"
    else
        log_info "Dry run completed. Run without --dry-run to perform migration."
    fi

    echo
}

# Run main with all arguments
main "$@"
