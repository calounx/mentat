#!/usr/bin/env bash
# Deploy CHOM Laravel application to landsraad.arewel.com
# Zero-downtime deployment using blue-green strategy
# Usage: ./deploy-application.sh --branch main [--skip-backup] [--skip-migrations]

set -euo pipefail

# Dependency validation - MUST run before sourcing any files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Validate dependencies before doing anything else
validate_deployment_dependencies() {
    local script_dir="$1"
    local deploy_root="$2"
    local script_name="$(basename "$0")"
    local errors=()

    if [[ ! -d "$deploy_root" ]]; then
        errors+=("Deploy root directory not found: $deploy_root")
    fi

    local utils_dir="${deploy_root}/utils"
    if [[ ! -d "$utils_dir" ]]; then
        errors+=("Utils directory not found: $utils_dir")
    else
        local required_utils=(
            "${utils_dir}/logging.sh"
            "${utils_dir}/notifications.sh"
            "${utils_dir}/colors.sh"
            "${utils_dir}/dependency-validation.sh"
        )

        for util_file in "${required_utils[@]}"; do
            if [[ ! -f "$util_file" ]]; then
                errors+=("Required utility file not found: $util_file")
            elif [[ ! -r "$util_file" ]]; then
                errors+=("Required utility file not readable: $util_file")
            fi
        done
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
        echo "Run from repository root: sudo ./deploy/scripts/${script_name}" >&2
        exit 1
    fi
}

validate_deployment_dependencies "$SCRIPT_DIR" "$DEPLOY_ROOT"

source "${SCRIPT_DIR}/../utils/logging.sh"
source "${SCRIPT_DIR}/../utils/notifications.sh"
source "${SCRIPT_DIR}/../utils/dependency-validation.sh"

# Configuration
APP_DIR="${APP_DIR:-/var/www/chom}"
RELEASES_DIR="${APP_DIR}/releases"
SHARED_DIR="${APP_DIR}/shared"
CURRENT_LINK="${APP_DIR}/current"
REPO_URL="${REPO_URL:-}"
BRANCH="${BRANCH:-main}"
PHP_VERSION="${PHP_VERSION:-8.2}"
KEEP_RELEASES="${KEEP_RELEASES:-5}"
DEPLOY_USER="${DEPLOY_USER:-stilgar}"

# Deployment flags
SKIP_BACKUP=false
SKIP_MIGRATIONS=false
SKIP_HEALTH_CHECK=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --repo-url)
            REPO_URL="$2"
            shift 2
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        --skip-migrations)
            SKIP_MIGRATIONS=true
            shift
            ;;
        --skip-health-check)
            SKIP_HEALTH_CHECK=true
            shift
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# Validate repository URL
if [[ -z "$REPO_URL" ]]; then
    log_fatal "Repository URL is required. Set REPO_URL environment variable or use --repo-url"
fi

init_deployment_log "deploy-app-$(date +%Y%m%d_%H%M%S)"
log_section "Application Deployment"

notify_deployment_started "${ENVIRONMENT:-production}" "$BRANCH"

# Deployment error handler
deployment_error_handler() {
    local exit_code=$?
    log_error "Deployment failed with exit code: $exit_code"

    notify_deployment_failure "${ENVIRONMENT:-production}" "Deployment script failed at line $BASH_LINENO"

    # Automatic rollback
    log_warning "Initiating automatic rollback"

    if bash "${SCRIPT_DIR}/rollback.sh" --auto-confirm; then
        log_success "Automatic rollback completed"
    else
        log_error "Automatic rollback failed - manual intervention required"
    fi

    exit "$exit_code"
}

# Set error trap
trap deployment_error_handler ERR

# Generate release ID
generate_release_id() {
    echo "$(date +%Y%m%d_%H%M%S)"
}

# Create new release directory
create_release_directory() {
    local release_id="$1"
    local release_path="${RELEASES_DIR}/${release_id}"

    log_step "Creating release directory: $release_id"

    mkdir -p "$release_path"
    log_success "Release directory created: $release_path"

    echo "$release_path"
}

# Clone repository
clone_repository() {
    local release_path="$1"

    log_step "Cloning repository: $REPO_URL (branch: $BRANCH)"

    # Use git credentials if provided
    local git_url="$REPO_URL"
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        # Insert token into HTTPS URL
        git_url=$(echo "$REPO_URL" | sed "s|https://|https://${GITHUB_TOKEN}@|")
    fi

    if git clone --branch "$BRANCH" --depth 1 "$git_url" "$release_path" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Repository cloned successfully"

        # Get commit information
        cd "$release_path"
        local commit_hash=$(git rev-parse HEAD)
        local commit_message=$(git log -1 --pretty=%B)

        log_info "Commit: $commit_hash"
        log_info "Message: $commit_message"

        # Save deployment metadata
        cat > "${release_path}/.deployment-info" <<EOF
release_id=$(basename "$release_path")
deployed_at=$(date -Iseconds)
deployed_by=$(whoami)
commit_hash=$commit_hash
commit_message=$commit_message
branch=$BRANCH
EOF

        return 0
    else
        log_error "Repository clone failed"
        return 1
    fi
}

# Link shared directories
link_shared_directories() {
    local release_path="$1"

    log_step "Linking shared directories"

    cd "$release_path"

    # Remove storage directory and link to shared
    if [[ -d "storage" ]]; then
        rm -rf storage
    fi
    ln -sf "${SHARED_DIR}/storage" storage

    # Link .env file
    if [[ -f "${SHARED_DIR}/.env" ]]; then
        ln -sf "${SHARED_DIR}/.env" .env
        log_success "Shared directories linked"
    else
        log_warning "No .env file found in shared directory"
        log_warning "Make sure to create ${SHARED_DIR}/.env before deployment"
    fi
}

# Install Composer dependencies
install_composer_dependencies() {
    local release_path="$1"

    log_step "Installing Composer dependencies"

    cd "$release_path"

    if composer install \
        --no-dev \
        --no-interaction \
        --prefer-dist \
        --optimize-autoloader \
        --no-progress \
        2>&1 | tee -a "$LOG_FILE"; then

        log_success "Composer dependencies installed"
        return 0
    else
        log_error "Composer install failed"
        return 1
    fi
}

# Install NPM dependencies and build assets
build_assets() {
    local release_path="$1"

    log_step "Building frontend assets"

    cd "$release_path"

    # Check if package.json exists
    if [[ ! -f "package.json" ]]; then
        log_info "No package.json found, skipping asset build"
        return 0
    fi

    # Install dependencies (including dev for build tools like vite)
    log_info "Installing NPM dependencies"
    if npm ci 2>&1 | tee -a "$LOG_FILE"; then
        log_success "NPM dependencies installed"
    else
        log_warning "NPM install failed, but continuing deployment"
    fi

    # Build assets
    log_info "Building assets"
    if npm run build 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Assets built successfully"
        # Prune dev dependencies after build to save space
        npm prune --production 2>&1 | tee -a "$LOG_FILE" || true
    else
        log_warning "Asset build failed, but continuing deployment"
    fi
}

# Run database migrations
run_migrations() {
    local release_path="$1"

    if [[ "$SKIP_MIGRATIONS" == true ]]; then
        log_info "Skipping database migrations (--skip-migrations flag)"
        return 0
    fi

    log_step "Running database migrations"

    cd "$release_path"

    # Check if there are pending migrations
    if php artisan migrate:status 2>&1 | grep -q "Pending"; then
        log_info "Pending migrations found, running migrations"

        if php artisan migrate --force 2>&1 | tee -a "$LOG_FILE"; then
            log_success "Database migrations completed"
            return 0
        else
            log_error "Database migrations failed"
            return 1
        fi
    else
        log_success "No pending migrations"
        return 0
    fi
}

# Optimize application
optimize_application() {
    local release_path="$1"

    log_step "Optimizing application"

    cd "$release_path"

    # Publish Livewire assets
    php artisan livewire:publish --assets 2>/dev/null || true

    # Create storage symlink (to shared storage)
    php artisan storage:link 2>/dev/null || true

    # Cache configuration
    php artisan config:cache

    # Cache routes
    php artisan route:cache

    # Cache views
    php artisan view:cache

    # Optimize autoloader
    composer dump-autoload --optimize --no-dev

    log_success "Application optimized"
}

# Set proper permissions
set_permissions() {
    local release_path="$1"

    log_step "Setting file permissions"

    # Set ownership
    sudo chown -R ${DEPLOY_USER:-stilgar}:www-data "$release_path"

    # Set directory permissions
    find "$release_path" -type d -exec chmod 755 {} \;

    # Set file permissions
    find "$release_path" -type f -exec chmod 644 {} \;

    # Make artisan executable
    chmod +x "${release_path}/artisan"

    # Ensure storage is writable
    sudo chmod -R 775 "${SHARED_DIR}/storage"

    log_success "Permissions set"
}

# Switch to new release (atomic swap)
switch_release() {
    local release_path="$1"

    log_step "Switching to new release"

    # Create temporary symlink
    local temp_link="${APP_DIR}/current.tmp.$$"

    ln -sf "$release_path" "$temp_link"

    # Atomic swap
    mv -Tf "$temp_link" "$CURRENT_LINK"

    log_success "Release switched (symlink updated)"
}

# Reload services
reload_services() {
    log_step "Reloading services"

    # Reload PHP-FPM
    log_info "Reloading PHP-FPM"
    sudo systemctl reload php${PHP_VERSION}-fpm

    # Reload Nginx
    log_info "Reloading Nginx"
    sudo systemctl reload nginx

    # Restart queue workers via supervisor
    if command -v supervisorctl &> /dev/null; then
        if sudo supervisorctl status chom-worker:* &> /dev/null; then
            log_info "Restarting queue workers"
            sudo supervisorctl restart chom-worker:* 2>&1 | tee -a "$LOG_FILE" || true
        else
            log_info "Queue workers not configured in supervisor (run prepare-landsraad.sh to set up)"
        fi
    fi

    log_success "Services reloaded"
}

# Install or update VPSManager
install_vpsmanager() {
    log_step "Installing/updating VPSManager"

    local vpsmanager_install_script="${DEPLOY_ROOT}/vpsmanager/install.sh"

    if [[ ! -f "$vpsmanager_install_script" ]]; then
        log_error "VPSManager install script not found: $vpsmanager_install_script"
        log_warning "Skipping VPSManager installation"
        return 1
    fi

    if [[ ! -x "$vpsmanager_install_script" ]]; then
        log_info "Making VPSManager install script executable"
        chmod +x "$vpsmanager_install_script"
    fi

    # Run installation (non-interactive)
    log_info "Running VPSManager installer..."
    if sudo bash "$vpsmanager_install_script" install 2>&1 | tee -a "$LOG_FILE"; then
        log_success "VPSManager installed successfully"

        # Configure VPSManager with MariaDB credentials
        local vpsmanager_config="/opt/vpsmanager/config/vpsmanager.conf"
        local mariadb_secrets="/var/www/chom/shared/.mariadb-secrets"

        if [[ -f "$vpsmanager_config" ]] && [[ -f "$mariadb_secrets" ]]; then
            log_info "Configuring VPSManager with MariaDB credentials"

            # Source MariaDB secrets
            # shellcheck source=/dev/null
            source "$mariadb_secrets"

            # Update VPSManager config
            sudo sed -i "s|^MYSQL_ROOT_PASSWORD=.*|MYSQL_ROOT_PASSWORD=\"${MARIADB_ROOT_PASSWORD}\"|" "$vpsmanager_config"
            log_success "VPSManager configured with MariaDB credentials"
        elif [[ ! -f "$mariadb_secrets" ]]; then
            log_warning "MariaDB secrets file not found: $mariadb_secrets"
            log_warning "VPSManager will use empty MariaDB root password (if MariaDB is secured, sites won't provision)"
        fi

        # Verify installation
        if command -v vpsmanager &> /dev/null; then
            local version=$(sudo vpsmanager --version 2>&1 | head -1 || echo "unknown")
            log_info "VPSManager version: $version"
        else
            log_warning "VPSManager command not found in PATH"
        fi

        return 0
    else
        log_error "VPSManager installation failed"
        log_warning "Site provisioning may not work without VPSManager"
        return 1
    fi
}

# Clean old releases
clean_old_releases() {
    log_step "Cleaning old releases (keeping last $KEEP_RELEASES)"

    local release_count=$(ls -1t "$RELEASES_DIR" | wc -l)

    if [[ $release_count -le $KEEP_RELEASES ]]; then
        log_success "Release count ($release_count) is within limit ($KEEP_RELEASES)"
        return 0
    fi

    local releases_to_delete=$((release_count - KEEP_RELEASES))

    log_info "Deleting $releases_to_delete old release(s)"

    # Get list of old releases (excluding current)
    local current_release=$(basename "$(readlink -f "$CURRENT_LINK")")

    ls -1t "$RELEASES_DIR" | tail -n "$releases_to_delete" | while read release; do
        if [[ "$release" != "$current_release" ]]; then
            log_info "Deleting release: $release"
            rm -rf "${RELEASES_DIR}/${release}"
        fi
    done

    log_success "Old releases cleaned up"
}

# Pre-switch validation - structural checks only (no HTTP - symlink doesn't exist yet)
validate_release_structure() {
    local release_path="$1"

    log_step "Validating release structure"

    # Check if release directory exists
    if [[ ! -d "$release_path" ]]; then
        log_error "Release path does not exist: $release_path"
        return 1
    fi

    # Check if artisan exists
    if [[ ! -f "${release_path}/artisan" ]]; then
        log_error "artisan file not found in $release_path"
        return 1
    fi
    log_success "artisan file present"

    # Check if vendor directory exists
    if [[ ! -d "${release_path}/vendor" ]]; then
        log_error "vendor directory not found in $release_path"
        return 1
    fi
    log_success "vendor directory present"

    # Test artisan command
    cd "$release_path"
    if php artisan --version > /dev/null 2>&1; then
        log_success "Laravel artisan is functional"
    else
        log_error "Laravel artisan command failed"
        return 1
    fi

    # Check .env file exists (via symlink to shared)
    if [[ ! -f "${release_path}/.env" ]]; then
        log_error ".env file not found"
        return 1
    fi
    log_success ".env file present"

    # Check storage directory (via symlink to shared)
    if [[ ! -d "${release_path}/storage" ]]; then
        log_error "storage directory not linked"
        return 1
    fi
    log_success "storage directory linked"

    # Test database connectivity
    log_step "Testing database connectivity"
    local db_host=$(grep "^DB_HOST=" "${release_path}/.env" | cut -d'=' -f2)
    local db_port=$(grep "^DB_PORT=" "${release_path}/.env" | cut -d'=' -f2)
    local db_database=$(grep "^DB_DATABASE=" "${release_path}/.env" | cut -d'=' -f2)
    local db_username=$(grep "^DB_USERNAME=" "${release_path}/.env" | cut -d'=' -f2)
    local db_password=$(grep "^DB_PASSWORD=" "${release_path}/.env" | cut -d'=' -f2)

    if PGPASSWORD="$db_password" psql -h "$db_host" -p "$db_port" -U "$db_username" -d "$db_database" -c "SELECT 1;" > /dev/null 2>&1; then
        log_success "Database connection successful"
    else
        log_error "Database connection failed"
        return 1
    fi

    # Test Redis connectivity
    log_step "Testing Redis connectivity"
    if redis-cli ping > /dev/null 2>&1; then
        log_success "Redis is responding"
    else
        log_error "Redis is not responding"
        return 1
    fi

    log_success "Release structure validation passed"
    return 0
}

# Run full health checks (including HTTP - requires symlink to exist)
run_health_checks() {
    local release_path="$1"

    if [[ "$SKIP_HEALTH_CHECK" == true ]]; then
        log_info "Skipping health checks (--skip-health-check flag)"
        return 0
    fi

    log_step "Running full health checks"

    if bash "${SCRIPT_DIR}/health-check.sh" --release-path "$release_path"; then
        log_success "Health checks passed"
        return 0
    else
        log_error "Health checks failed"
        return 1
    fi
}

# Main execution
main() {
    start_timer

    print_header "CHOM Application Deployment"
    log_info "Branch: $BRANCH"
    log_info "Environment: ${ENVIRONMENT:-production}"

    # Pre-deployment backup
    if [[ "$SKIP_BACKUP" == false ]]; then
        log_section "Pre-Deployment Backup"
        bash "${SCRIPT_DIR}/backup-before-deploy.sh"
    else
        log_warning "Skipping backup (--skip-backup flag)"
    fi

    # Create new release
    log_section "Creating New Release"
    RELEASE_ID=$(generate_release_id)
    RELEASE_PATH=$(create_release_directory "$RELEASE_ID")

    # Ensure VPSManager SSH key exists
    log_section "VPSManager SSH Key Setup"
    local ssh_key_path="${SHARED_DIR}/storage/app/ssh/chom_deploy_key"
    if [[ ! -f "${ssh_key_path}" ]]; then
        log_info "Generating SSH key for VPSManager integration..."
        sudo mkdir -p "${SHARED_DIR}/storage/app/ssh"
        sudo ssh-keygen -t ed25519 -f "${ssh_key_path}" -N '' -C 'chom@landsraad.arewel.com'
        sudo chmod 600 "${ssh_key_path}"
        sudo chmod 644 "${ssh_key_path}.pub"

        # Add to authorized_keys for localhost/remote SSH
        local pubkey=$(sudo cat "${ssh_key_path}.pub")
        if ! sudo grep -q "${pubkey}" /home/${DEPLOY_USER}/.ssh/authorized_keys 2>/dev/null; then
            sudo mkdir -p /home/${DEPLOY_USER}/.ssh
            echo "${pubkey}" | sudo tee -a /home/${DEPLOY_USER}/.ssh/authorized_keys > /dev/null
            sudo chmod 600 /home/${DEPLOY_USER}/.ssh/authorized_keys
            sudo chown -R ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.ssh
        fi

        sudo chown ${DEPLOY_USER}:www-data "${ssh_key_path}"*
        log_success "SSH key generated and configured"
    else
        log_success "SSH key exists at ${ssh_key_path}"
    fi

    # Always ensure correct permissions (in case shared dir permissions were changed)
    sudo chmod 600 "${ssh_key_path}" 2>/dev/null || true
    sudo chmod 644 "${ssh_key_path}.pub" 2>/dev/null || true
    sudo chown ${DEPLOY_USER}:www-data "${ssh_key_path}" "${ssh_key_path}.pub" 2>/dev/null || true

    # Install/Update VPSManager
    log_section "Installing VPSManager"
    install_vpsmanager

    # Deploy application
    log_section "Deploying Application"
    clone_repository "$RELEASE_PATH"
    link_shared_directories "$RELEASE_PATH"
    install_composer_dependencies "$RELEASE_PATH"
    build_assets "$RELEASE_PATH"
    run_migrations "$RELEASE_PATH"
    optimize_application "$RELEASE_PATH"
    set_permissions "$RELEASE_PATH"

    # Pre-switch validation (structural checks only - no HTTP, symlink doesn't exist yet)
    log_section "Pre-Switch Validation"
    validate_release_structure "$RELEASE_PATH"

    # Switch release
    log_section "Activating New Release"
    switch_release "$RELEASE_PATH"
    reload_services

    # Post-deployment health check
    log_section "Post-Deployment Validation"
    log_info "Waiting 5 seconds for services to stabilize..."
    sleep 5  # Give services time to reload and stabilize
    run_health_checks "$CURRENT_LINK"

    # Cleanup
    log_section "Cleanup"
    clean_old_releases

    # Deploy exporters automatically
    log_section "Exporter Deployment"
    if [[ -x "${SCRIPT_DIR}/deploy-exporters.sh" ]]; then
        log_info "Deploying exporters for detected services..."
        sudo bash "${SCRIPT_DIR}/deploy-exporters.sh" || log_warning "Exporter deployment completed with warnings"
    else
        log_warning "deploy-exporters.sh not found or not executable - exporters not deployed"
    fi

    end_timer "Deployment"

    print_header "Deployment Successful"
    log_success "Application deployed: $RELEASE_ID"
    log_success "Current release: $(basename "$(readlink -f "$CURRENT_LINK")")"

    notify_deployment_success "${ENVIRONMENT:-production}" "$(( $(date +%s) - TIMER_START ))s"

    exit 0
}

main
