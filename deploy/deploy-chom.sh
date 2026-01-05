#!/usr/bin/env bash
# Main deployment orchestration script for CHOM
# Coordinates deployment across mentat and landsraad servers
# Run from mentat.arewel.com as user stilgar
#
# Usage: ./deploy-chom.sh --environment=production --branch=main [options]

set -euo pipefail

# Dependency validation - MUST run before sourcing any files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Validate dependencies before doing anything else
validate_deployment_dependencies() {
    local script_dir="$1"
    local script_name="$(basename "$0")"
    local deploy_root="$script_dir"
    local errors=()

    # Validate deploy root structure
    if [[ ! -d "$deploy_root" ]]; then
        errors+=("Deploy root directory not found: $deploy_root")
    fi

    # Validate utils directory
    local utils_dir="${deploy_root}/utils"
    if [[ ! -d "$utils_dir" ]]; then
        errors+=("Utils directory not found: $utils_dir")
    else
        # Validate required utility files
        local required_utils=(
            "${utils_dir}/logging.sh"
            "${utils_dir}/colors.sh"
            "${utils_dir}/notifications.sh"
            "${utils_dir}/idempotence.sh"
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

    # Validate scripts directory
    local scripts_dir="${deploy_root}/scripts"
    if [[ ! -d "$scripts_dir" ]]; then
        errors+=("Scripts directory not found: $scripts_dir")
    fi

    # If errors found, print comprehensive error message and exit
    if [[ ${#errors[@]} -gt 0 ]]; then
        echo ""
        echo "ERROR: Missing required dependencies for ${script_name}" >&2
        echo ""
        echo "Script location: ${script_dir}" >&2
        echo "Deploy root: ${deploy_root}" >&2
        echo "Utils directory: ${utils_dir}" >&2
        echo ""
        echo "Missing dependencies:" >&2
        for error in "${errors[@]}"; do
            echo "  - ${error}" >&2
        done
        echo ""
        echo "Troubleshooting:" >&2
        echo "  1. Verify you are in the correct repository:" >&2
        echo "     cd /home/calounx/repositories/mentat" >&2
        echo "" >&2
        echo "  2. Run the script from the repository root:" >&2
        echo "     sudo ./deploy/${script_name}" >&2
        echo "" >&2
        echo "  3. Check that all deployment files are present:" >&2
        echo "     ls -la deploy/utils/" >&2
        echo "" >&2
        echo "  4. If files are missing, ensure git repository is complete:" >&2
        echo "     git status" >&2
        echo "     git pull" >&2
        echo "" >&2
        exit 1
    fi
}

# Run validation before sourcing
validate_deployment_dependencies "$SCRIPT_DIR"

# Now safe to source utility files
source "${SCRIPT_DIR}/utils/logging.sh"
source "${SCRIPT_DIR}/utils/notifications.sh"
source "${SCRIPT_DIR}/utils/dependency-validation.sh"

# Default configuration
ENVIRONMENT="${ENVIRONMENT:-production}"
BRANCH="${BRANCH:-main}"
REPO_URL="${REPO_URL:-}"
SKIP_BACKUP=false
SKIP_MIGRATIONS=false
SKIP_OBSERVABILITY=false
DEPLOY_USER="${DEPLOY_USER:-stilgar}"
BOOTSTRAP_USER="${BOOTSTRAP_USER:-root}"
MENTAT_HOST="${MENTAT_HOST:-mentat.arewel.com}"
LANDSRAAD_HOST="${LANDSRAAD_HOST:-landsraad.arewel.com}"

# Detect SSH key to use - prefer DEPLOY_USER's keys, fall back to SUDO_USER
find_ssh_key() {
    local user="$1"
    local home=$(eval echo "~${user}")
    for key in "${home}/.ssh/id_ed25519" "${home}/.ssh/id_rsa"; do
        if [[ -f "$key" ]]; then
            echo "$key"
            return 0
        fi
    done
    return 1
}

SSH_KEY=""
# First try DEPLOY_USER (stilgar)
if SSH_KEY=$(find_ssh_key "$DEPLOY_USER" 2>/dev/null); then
    : # Found stilgar's key
# Then try SUDO_USER (calounx when running with sudo)
elif [[ -n "${SUDO_USER:-}" ]] && SSH_KEY=$(find_ssh_key "$SUDO_USER" 2>/dev/null); then
    : # Found sudo user's key
# Finally try current user
elif SSH_KEY=$(find_ssh_key "$(whoami)" 2>/dev/null); then
    : # Found current user's key
fi

SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=5"
if [[ -n "$SSH_KEY" && -f "$SSH_KEY" ]]; then
    SSH_OPTS="$SSH_OPTS -i $SSH_KEY"
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --environment=*)
            ENVIRONMENT="${1#*=}"
            shift
            ;;
        --branch=*)
            BRANCH="${1#*=}"
            shift
            ;;
        --repo-url=*)
            REPO_URL="${1#*=}"
            shift
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        --skip-migrations)
            SKIP_MIGRATIONS=true
            shift
            ;;
        --skip-observability)
            SKIP_OBSERVABILITY=true
            shift
            ;;
        --bootstrap-user=*)
            BOOTSTRAP_USER="${1#*=}"
            shift
            ;;
        --help)
            cat <<EOF
CHOM Deployment Script
=====================

Usage: $0 [OPTIONS]

Options:
  --environment=ENV         Deployment environment (default: production)
  --branch=BRANCH          Git branch to deploy (default: main)
  --repo-url=URL           Repository URL (required)
  --bootstrap-user=USER    User for initial setup if stilgar doesn't exist (default: root)
  --skip-backup            Skip pre-deployment backup
  --skip-migrations        Skip database migrations
  --skip-observability     Skip observability stack deployment
  --help                   Show this help message

Environment Variables:
  REPO_URL                 Repository URL
  GITHUB_TOKEN             GitHub access token (for private repos)
  SLACK_WEBHOOK_URL        Slack webhook for notifications
  EMAIL_RECIPIENTS         Email addresses for notifications
  DB_PASSWORD              Database password
  REDIS_PASSWORD           Redis password

Examples:
  # Full deployment
  ./deploy-chom.sh --environment=production --branch=main --repo-url=https://github.com/user/chom.git

  # Skip backup (for quick deployments)
  ./deploy-chom.sh --environment=staging --branch=develop --skip-backup

  # Application only (skip observability)
  ./deploy-chom.sh --environment=production --skip-observability

EOF
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            log_info "Run with --help for usage information"
            exit 1
            ;;
    esac
done

# Validate required configuration
if [[ -z "$REPO_URL" ]]; then
    log_fatal "Repository URL is required. Set REPO_URL environment variable or use --repo-url"
fi

# Initialize deployment
init_deployment_log "deploy-$(date +%Y%m%d_%H%M%S)"
export ENVIRONMENT

print_header "CHOM Deployment Orchestration"
log_info "Environment: $ENVIRONMENT"
log_info "Branch: $BRANCH"
log_info "Repository: $REPO_URL"
log_info "Mentat: $MENTAT_HOST"
log_info "Landsraad: $LANDSRAAD_HOST"
echo ""

# Send deployment started notification
notify_deployment_started "$ENVIRONMENT" "$BRANCH"

# Global error handler
deployment_error_handler() {
    local exit_code=$?
    log_error "Deployment failed with exit code: $exit_code"

    notify_deployment_failure "$ENVIRONMENT" "Deployment orchestration failed"

    exit "$exit_code"
}

trap deployment_error_handler ERR

# Check SSH connectivity and bootstrap if needed
check_ssh_connectivity() {
    log_section "Checking SSH Connectivity"

    log_step "Testing connection to landsraad.arewel.com as ${DEPLOY_USER}"
    if ssh $SSH_OPTS "${DEPLOY_USER}@${LANDSRAAD_HOST}" "echo 'SSH OK'" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "SSH connection to landsraad established as ${DEPLOY_USER}"
    else
        log_warning "Cannot connect as ${DEPLOY_USER}, attempting bootstrap..."
        bootstrap_deploy_user
    fi

    # Check if we're running on mentat
    local current_host=$(hostname)
    if [[ "$current_host" == *"mentat"* ]] || [[ "$current_host" == "$MENTAT_HOST" ]]; then
        log_success "Running on mentat.arewel.com"
    else
        log_warning "Not running on mentat.arewel.com (current: $current_host)"
        log_warning "This script should be run from mentat for full deployment orchestration"
    fi
}

# Bootstrap deploy user on landsraad if it doesn't exist
bootstrap_deploy_user() {
    log_step "Bootstrapping ${DEPLOY_USER} user on landsraad via ${BOOTSTRAP_USER}"

    # Test connection as bootstrap user
    if ! ssh $SSH_OPTS "${BOOTSTRAP_USER}@${LANDSRAAD_HOST}" "echo 'Bootstrap SSH OK'" 2>&1 | tee -a "$LOG_FILE"; then
        log_fatal "Cannot connect as ${BOOTSTRAP_USER}@${LANDSRAAD_HOST}. Please check SSH keys."
    fi

    log_info "Connected as ${BOOTSTRAP_USER}, creating ${DEPLOY_USER} user..."

    # Create deploy user and setup SSH
    local bootstrap_script=$(cat <<'BOOTSTRAP_EOF'
set -e
DEPLOY_USER="__DEPLOY_USER__"

echo "Checking if user exists..."
if id "$DEPLOY_USER" &>/dev/null; then
    echo "User $DEPLOY_USER already exists"
else
    echo "Creating user $DEPLOY_USER..."
    useradd -m -s /bin/bash "$DEPLOY_USER"
    usermod -aG sudo "$DEPLOY_USER"
    usermod -aG www-data "$DEPLOY_USER"
    echo "$DEPLOY_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$DEPLOY_USER
    chmod 440 /etc/sudoers.d/$DEPLOY_USER
    echo "User $DEPLOY_USER created with sudo access"
fi

# Setup SSH directory
echo "Setting up SSH for $DEPLOY_USER..."
mkdir -p /home/$DEPLOY_USER/.ssh
chmod 700 /home/$DEPLOY_USER/.ssh

# Copy authorized_keys from root or bootstrap user if exists
if [[ -f /root/.ssh/authorized_keys ]]; then
    cp /root/.ssh/authorized_keys /home/$DEPLOY_USER/.ssh/
    echo "Copied SSH keys from root"
fi

chown -R $DEPLOY_USER:$DEPLOY_USER /home/$DEPLOY_USER/.ssh
chmod 600 /home/$DEPLOY_USER/.ssh/authorized_keys 2>/dev/null || true

echo "Bootstrap complete for $DEPLOY_USER"
BOOTSTRAP_EOF
)
    bootstrap_script="${bootstrap_script//__DEPLOY_USER__/$DEPLOY_USER}"

    if ssh $SSH_OPTS "${BOOTSTRAP_USER}@${LANDSRAAD_HOST}" "$bootstrap_script" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "User ${DEPLOY_USER} bootstrapped successfully"
    else
        log_fatal "Failed to bootstrap ${DEPLOY_USER} user"
    fi

    # Verify we can now connect as deploy user
    log_step "Verifying SSH connection as ${DEPLOY_USER}"
    sleep 2  # Give SSH a moment to recognize the new user
    if ssh $SSH_OPTS "${DEPLOY_USER}@${LANDSRAAD_HOST}" "echo 'SSH OK'" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "SSH connection verified as ${DEPLOY_USER}"
    else
        log_fatal "Cannot connect as ${DEPLOY_USER} after bootstrap. Check SSH key setup."
    fi
}

# Pre-deployment checks
pre_deployment_checks() {
    log_section "Pre-Deployment Checks"

    # Check required environment variables
    log_step "Checking environment variables"

    local required_vars=("REPO_URL")
    local missing_vars=()

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_fatal "Please set all required environment variables before deployment"
    fi

    log_success "All required environment variables are set"

    # Check disk space on landsraad
    log_step "Checking disk space on landsraad"
    local disk_usage=$(ssh $SSH_OPTS "${DEPLOY_USER}@${LANDSRAAD_HOST}" "df / | tail -1 | awk '{print \$5}' | sed 's/%//'")

    if [[ $disk_usage -lt 80 ]]; then
        log_success "Disk usage on landsraad: ${disk_usage}%"
    else
        log_warning "Disk usage on landsraad is high: ${disk_usage}%"
    fi

    # Check if services are running on landsraad
    log_step "Checking services on landsraad"
    local services=("nginx" "php8.2-fpm" "postgresql" "redis-server")

    for service in "${services[@]}"; do
        if ssh $SSH_OPTS "${DEPLOY_USER}@${LANDSRAAD_HOST}" "sudo systemctl is-active --quiet $service"; then
            log_success "$service is running"
        else
            log_error "$service is not running on landsraad"
        fi
    done
}

# Deploy observability stack
deploy_observability() {
    if [[ "$SKIP_OBSERVABILITY" == true ]]; then
        log_info "Skipping observability deployment (--skip-observability flag)"
        return 0
    fi

    log_section "Deploying Observability Stack"

    # Check if we're on mentat
    local current_host=$(hostname)
    if [[ "$current_host" == *"mentat"* ]] || [[ "$current_host" == "$MENTAT_HOST" ]]; then
        log_info "Deploying observability stack locally"

        if bash "${SCRIPT_DIR}/scripts/deploy-observability.sh" 2>&1 | tee -a "$LOG_FILE"; then
            log_success "Observability stack deployed"
            return 0
        else
            log_warning "Observability deployment failed, but continuing with application deployment"
            return 0  # Don't fail the entire deployment
        fi
    else
        log_info "Skipping observability deployment (not running on mentat)"
        return 0
    fi
}

# Deploy application
deploy_application() {
    log_section "Deploying Application to landsraad"

    local app_dir="/var/www/chom"
    local deploy_user="${DEPLOY_USER}"

    # Check if application directory exists on landsraad
    log_step "Checking if application exists on landsraad"

    if ! ssh $SSH_OPTS "${deploy_user}@${LANDSRAAD_HOST}" "test -d ${app_dir}/.git"; then
        log_info "Application not found on landsraad - performing initial setup"

        # Initial clone and setup
        local init_script=$(cat <<'INIT_EOF'
set -e
APP_DIR="/var/www/chom"
REPO_URL="__REPO_URL__"
BRANCH="__BRANCH__"
DEPLOY_USER="__DEPLOY_USER__"

echo "Creating application directory..."
sudo mkdir -p /var/www
cd /var/www

echo "Cloning repository..."
sudo git clone --branch "$BRANCH" "$REPO_URL" chom

echo "Setting ownership..."
sudo chown -R ${DEPLOY_USER}:www-data chom
cd chom

echo "Installing PHP dependencies..."
composer install --no-dev --optimize-autoloader --no-interaction

echo "Installing Node dependencies..."
npm ci

echo "Building assets..."
npm run build

echo "Setting up environment..."
if [[ ! -f .env ]]; then
    cp .env.example .env
    php artisan key:generate
fi

echo "Setting permissions..."
sudo chown -R ${DEPLOY_USER}:www-data storage bootstrap/cache
chmod -R 775 storage bootstrap/cache

echo "Running migrations..."
php artisan migrate --force

echo "Optimizing..."
php artisan config:cache
php artisan route:cache
php artisan view:cache

echo "Installing vpsmanager CLI..."
sudo ./deploy/vpsmanager/install.sh || true

echo "Restarting services..."
sudo systemctl restart php8.2-fpm
sudo systemctl reload nginx

echo "Initial setup complete!"
INIT_EOF
)
        # Replace placeholders
        init_script="${init_script//__REPO_URL__/$REPO_URL}"
        init_script="${init_script//__BRANCH__/$BRANCH}"
        init_script="${init_script//__DEPLOY_USER__/$deploy_user}"

        if ssh $SSH_OPTS "${deploy_user}@${LANDSRAAD_HOST}" "$init_script" 2>&1 | tee -a "$LOG_FILE"; then
            log_success "Initial application setup completed"
            return 0
        else
            log_error "Initial application setup failed"
            return 1
        fi
    fi

    # Application exists - do normal update deployment
    log_info "Application found - performing update deployment"

    # Build deployment command
    local deploy_cmd="${app_dir}/deploy/scripts/deploy-application.sh --branch $BRANCH --repo-url '$REPO_URL'"

    if [[ "$SKIP_BACKUP" == true ]]; then
        deploy_cmd="$deploy_cmd --skip-backup"
    fi

    if [[ "$SKIP_MIGRATIONS" == true ]]; then
        deploy_cmd="$deploy_cmd --skip-migrations"
    fi

    # Check if deploy-application.sh exists, otherwise do inline deployment
    if ! ssh $SSH_OPTS "${deploy_user}@${LANDSRAAD_HOST}" "test -f ${app_dir}/deploy/scripts/deploy-application.sh"; then
        log_info "deploy-application.sh not found, using inline deployment"

        local update_script=$(cat <<'UPDATE_EOF'
set -e
cd /var/www/chom
BRANCH="__BRANCH__"

echo "Pulling latest changes..."
git fetch origin
git checkout "$BRANCH"
git pull origin "$BRANCH"

echo "Installing dependencies..."
composer install --no-dev --optimize-autoloader --no-interaction
npm ci
npm run build

echo "Running migrations..."
php artisan migrate --force

echo "Optimizing..."
php artisan config:cache
php artisan route:cache
php artisan view:cache

echo "Updating vpsmanager..."
sudo ./deploy/vpsmanager/install.sh || true

echo "Restarting services..."
sudo systemctl restart php8.2-fpm
sudo systemctl reload nginx

echo "Update complete!"
UPDATE_EOF
)
        update_script="${update_script//__BRANCH__/$BRANCH}"

        if ssh $SSH_OPTS "${deploy_user}@${LANDSRAAD_HOST}" "$update_script" 2>&1 | tee -a "$LOG_FILE"; then
            log_success "Application updated successfully"
            return 0
        else
            log_error "Application update failed"
            return 1
        fi
    fi

    # Export environment variables for remote execution
    local env_vars="export ENVIRONMENT='$ENVIRONMENT'; export REPO_URL='$REPO_URL'; export BRANCH='$BRANCH';"

    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        env_vars="$env_vars export GITHUB_TOKEN='$GITHUB_TOKEN';"
    fi

    # Execute deployment on landsraad
    log_info "Executing deployment script on landsraad.arewel.com"

    if ssh $SSH_OPTS "${deploy_user}@${LANDSRAAD_HOST}" "$env_vars $deploy_cmd" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Application deployed successfully"
        return 0
    else
        log_error "Application deployment failed"
        return 1
    fi
}

# Post-deployment validation
post_deployment_validation() {
    log_section "Post-Deployment Validation"

    # Run health checks on landsraad
    log_step "Running health checks on landsraad"

    if ssh $SSH_OPTS "${DEPLOY_USER}@${LANDSRAAD_HOST}" "/var/www/chom/deploy/scripts/health-check.sh" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Health checks passed"
    else
        log_error "Health checks failed"
        return 1
    fi

    # Test HTTP endpoint
    log_step "Testing HTTP endpoint"

    local app_url="https://${LANDSRAAD_HOST}"
    local response_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$app_url" || echo "000")

    if [[ "$response_code" == "200" ]]; then
        log_success "Application is responding (HTTP $response_code)"
    else
        log_warning "Application returned HTTP $response_code"
    fi

    # Check metrics endpoint
    log_step "Checking metrics endpoint"

    local metrics_url="http://${LANDSRAAD_HOST}:9100/metrics"
    if curl -sf "$metrics_url" > /dev/null; then
        log_success "Metrics endpoint is accessible"
    else
        log_info "Metrics endpoint not accessible (this may be expected)"
    fi
}

# Deployment summary
deployment_summary() {
    log_section "Deployment Summary"

    # Get deployment info from landsraad
    local release_id=$(ssh $SSH_OPTS "${DEPLOY_USER}@${LANDSRAAD_HOST}" "basename \$(readlink -f /var/www/chom/current)" 2>/dev/null || echo "unknown")

    log_info "Environment: $ENVIRONMENT"
    log_info "Branch: $BRANCH"
    log_info "Release ID: $release_id"
    log_info "Deployed to: $LANDSRAAD_HOST"

    # Get commit information
    if [[ "$release_id" != "unknown" ]]; then
        local commit_info=$(ssh $SSH_OPTS "${DEPLOY_USER}@${LANDSRAAD_HOST}" "cat /var/www/chom/current/.deployment-info 2>/dev/null" || echo "")
        if [[ -n "$commit_info" ]]; then
            log_info "Deployment info:"
            echo "$commit_info" | tee -a "$LOG_FILE"
        fi
    fi
}

# Main deployment flow
main() {
    start_timer

    check_ssh_connectivity
    pre_deployment_checks
    deploy_observability
    deploy_application
    post_deployment_validation
    deployment_summary

    end_timer "Total deployment"

    print_header "Deployment Successful"
    log_success "CHOM application deployed successfully"
    log_success "Environment: $ENVIRONMENT"
    log_success "Application URL: https://$LANDSRAAD_HOST"

    if [[ "$SKIP_OBSERVABILITY" == false ]]; then
        log_success "Monitoring: http://$MENTAT_HOST:3000 (Grafana)"
    fi

    notify_deployment_success "$ENVIRONMENT" "$(( $(date +%s) - TIMER_START ))s"

    echo ""
    log_info "Next steps:"
    log_info "  1. Verify application functionality at https://$LANDSRAAD_HOST"
    log_info "  2. Check monitoring dashboards at http://$MENTAT_HOST:3000"
    log_info "  3. Review deployment logs: $LOG_FILE"
    echo ""

    exit 0
}

# Execute main deployment flow
main
