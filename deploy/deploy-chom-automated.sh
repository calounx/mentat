#!/usr/bin/env bash
# CHOM Automated Deployment - Master Orchestration Script
# Fully automated, idempotent deployment from scratch to production
#
# This script orchestrates the complete deployment process:
# 1. Creates stilgar user on both servers
# 2. Generates and distributes SSH keys
# 3. Generates deployment secrets
# 4. Prepares mentat (observability server)
# 5. Prepares landsraad (application server)
# 6. Deploys CHOM application
# 7. Deploys observability stack
# 8. Verifies everything is working
#
# Usage:
#   Run as root on mentat.arewel.com:
#   ./deploy-chom-automated.sh
#
#   Or with custom options:
#   ./deploy-chom-automated.sh --skip-user-setup --skip-ssh --interactive

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

# Configuration
DEPLOY_USER="${DEPLOY_USER:-stilgar}"
CURRENT_USER="${SUDO_USER:-$(whoami)}"  # User running this script (e.g., calounx)
MENTAT_HOST="${MENTAT_HOST:-mentat.arewel.com}"
LANDSRAAD_HOST="${LANDSRAAD_HOST:-landsraad.arewel.com}"
SECRETS_FILE="${SCRIPT_DIR}/.deployment-secrets"

# Deployment phases
SKIP_USER_SETUP=false
SKIP_SSH_SETUP=false
SKIP_SECRETS=false
SKIP_MENTAT_PREP=false
SKIP_LANDSRAAD_PREP=false
SKIP_APP_DEPLOY=false
SKIP_OBSERVABILITY=false
SKIP_VERIFICATION=false
INTERACTIVE=false
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-user-setup)
            SKIP_USER_SETUP=true
            shift
            ;;
        --skip-ssh)
            SKIP_SSH_SETUP=true
            shift
            ;;
        --skip-secrets)
            SKIP_SECRETS=true
            shift
            ;;
        --skip-mentat-prep)
            SKIP_MENTAT_PREP=true
            shift
            ;;
        --skip-landsraad-prep)
            SKIP_LANDSRAAD_PREP=true
            shift
            ;;
        --skip-app-deploy)
            SKIP_APP_DEPLOY=true
            shift
            ;;
        --skip-observability)
            SKIP_OBSERVABILITY=true
            shift
            ;;
        --skip-verification)
            SKIP_VERIFICATION=true
            shift
            ;;
        --interactive)
            INTERACTIVE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            cat <<EOF
CHOM Automated Deployment Script

Usage: $0 [OPTIONS]

OPTIONS:
  --skip-user-setup       Skip stilgar user creation
  --skip-ssh              Skip SSH key generation and distribution
  --skip-secrets          Skip secrets generation (use existing)
  --skip-mentat-prep      Skip mentat server preparation
  --skip-landsraad-prep   Skip landsraad server preparation
  --skip-app-deploy       Skip application deployment
  --skip-observability    Skip observability stack deployment
  --skip-verification     Skip post-deployment verification
  --interactive           Interactive mode (prompt for secrets)
  --dry-run               Show what would be done without executing
  --help                  Show this help message

EXAMPLES:
  # Full automated deployment (recommended first run)
  sudo ./deploy-chom-automated.sh

  # Interactive deployment with prompts
  sudo ./deploy-chom-automated.sh --interactive

  # Re-deploy application only (servers already prepared)
  sudo ./deploy-chom-automated.sh --skip-user-setup --skip-ssh --skip-secrets --skip-mentat-prep --skip-landsraad-prep

  # Setup servers only (no deployment)
  sudo ./deploy-chom-automated.sh --skip-app-deploy --skip-observability

REQUIREMENTS:
  - Run on mentat.arewel.com as root or with sudo
  - SSH access to landsraad.arewel.com as root (for initial setup)
  - Internet connectivity on both servers

WHAT THIS SCRIPT DOES:
  1. Creates stilgar user on mentat and landsraad
  2. Generates SSH keys for passwordless access
  3. Auto-generates deployment secrets
  4. Installs and configures observability stack on mentat
  5. Installs and configures application stack on landsraad
  6. Deploys CHOM application
  7. Verifies all services are running

EOF
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

init_deployment_log "automated-deploy-$(date +%Y%m%d_%H%M%S)"

# Pre-flight checks
preflight_checks() {
    log_section "Pre-flight Checks"

    # Check if running on mentat
    local current_hostname=$(hostname)
    if [[ "$current_hostname" != "mentat"* ]] && [[ "$current_hostname" != "$MENTAT_HOST" ]]; then
        log_warning "Not running on mentat.arewel.com (current: $current_hostname)"
        log_warning "This script should be run on the mentat server"

        if [[ "$DRY_RUN" != "true" ]]; then
            read -p "Continue anyway? (y/N): " confirm
            if [[ "$confirm" != "y" ]] && [[ "$confirm" != "Y" ]]; then
                log_fatal "Deployment cancelled"
            fi
        fi
    fi

    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        log_fatal "This script must be run as root or with sudo privileges"
    fi

    # Check internet connectivity
    log_step "Checking internet connectivity"
    if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        log_success "Internet connectivity OK"
    else
        log_error "No internet connectivity"
        log_fatal "Internet access is required for deployment"
    fi

    # Check SSH access to landsraad
    log_step "Checking SSH access to $LANDSRAAD_HOST"
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "${CURRENT_USER}@$LANDSRAAD_HOST" "echo 'SSH OK'" &>/dev/null; then
        log_success "SSH access to $LANDSRAAD_HOST OK"
    else
        log_warning "Cannot connect to $LANDSRAAD_HOST as root with key-based auth"
        log_info "You may be prompted for the root password during deployment"
    fi

    # Check required commands
    log_step "Checking required commands"
    local missing_commands=()
    for cmd in git curl wget ssh openssl sudo; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_commands+=("$cmd")
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        log_fatal "Please install missing commands and try again"
    fi

    log_success "All required commands available"

    # Check disk space
    log_step "Checking disk space"
    local available_space=$(df / | awk 'NR==2 {print $4}')
    local required_space=5242880  # 5GB in KB

    if [[ $available_space -lt $required_space ]]; then
        log_warning "Low disk space: $(($available_space / 1024 / 1024))GB available"
        log_warning "Recommended: at least 5GB free"
    else
        log_success "Sufficient disk space available"
    fi

    log_success "Pre-flight checks completed"
}

# Display deployment plan
display_deployment_plan() {
    print_header "Deployment Plan"

    log_info "Deployment Configuration:"
    log_info "  Mentat (Observability): $MENTAT_HOST"
    log_info "  Landsraad (Application): $LANDSRAAD_HOST"
    log_info "  Deploy User: $DEPLOY_USER"
    log_info ""
    log_info "Deployment Phases:"

    if [[ "$SKIP_USER_SETUP" == "true" ]]; then
        log_warning "  [SKIP] Phase 1: User Setup"
    else
        log_info "  [RUN]  Phase 1: User Setup"
    fi

    if [[ "$SKIP_SSH_SETUP" == "true" ]]; then
        log_warning "  [SKIP] Phase 2: SSH Automation"
    else
        log_info "  [RUN]  Phase 2: SSH Automation"
    fi

    if [[ "$SKIP_SECRETS" == "true" ]]; then
        log_warning "  [SKIP] Phase 3: Secrets Generation"
    else
        log_info "  [RUN]  Phase 3: Secrets Generation"
    fi

    if [[ "$SKIP_MENTAT_PREP" == "true" ]]; then
        log_warning "  [SKIP] Phase 4: Prepare Mentat"
    else
        log_info "  [RUN]  Phase 4: Prepare Mentat"
    fi

    if [[ "$SKIP_LANDSRAAD_PREP" == "true" ]]; then
        log_warning "  [SKIP] Phase 5: Prepare Landsraad"
    else
        log_info "  [RUN]  Phase 5: Prepare Landsraad"
    fi

    if [[ "$SKIP_APP_DEPLOY" == "true" ]]; then
        log_warning "  [SKIP] Phase 6: Deploy Application"
    else
        log_info "  [RUN]  Phase 6: Deploy Application"
    fi

    if [[ "$SKIP_OBSERVABILITY" == "true" ]]; then
        log_warning "  [SKIP] Phase 7: Deploy Observability"
    else
        log_info "  [RUN]  Phase 7: Deploy Observability"
    fi

    if [[ "$SKIP_VERIFICATION" == "true" ]]; then
        log_warning "  [SKIP] Phase 8: Verification"
    else
        log_info "  [RUN]  Phase 8: Verification"
    fi

    log_info ""

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No changes will be made"
        return 0
    fi

    if [[ "$INTERACTIVE" == "true" ]]; then
        read -p "Proceed with deployment? (y/N): " confirm
        if [[ "$confirm" != "y" ]] && [[ "$confirm" != "Y" ]]; then
            log_fatal "Deployment cancelled by user"
        fi
    else
        log_info "Starting automated deployment in 5 seconds..."
        log_info "Press Ctrl+C to cancel"
        sleep 5
    fi
}

# Phase 1: Setup deployment user on both servers
phase_user_setup() {
    if [[ "$SKIP_USER_SETUP" == "true" ]]; then
        log_section "Phase 1: User Setup [SKIPPED]"
        return 0
    fi

    log_section "Phase 1: Creating Deployment User ($DEPLOY_USER)"

    # Create user on mentat (local)
    log_step "Creating user on $MENTAT_HOST (local)"
    if [[ "$DRY_RUN" != "true" ]]; then
        sudo bash "${SCRIPT_DIR}/scripts/setup-stilgar-user-standalone.sh" "$DEPLOY_USER"
    else
        log_info "[DRY RUN] Would run: setup-stilgar-user-standalone.sh"
    fi

    # Create user on landsraad (remote)
    log_step "Creating user on $LANDSRAAD_HOST (remote)"
    if [[ "$DRY_RUN" != "true" ]]; then
        # Copy standalone script to remote and execute with sudo
        scp "${SCRIPT_DIR}/scripts/setup-stilgar-user-standalone.sh" "${CURRENT_USER}@${LANDSRAAD_HOST}:/tmp/setup-stilgar-user-standalone.sh" || {
            log_error "Failed to copy script to $LANDSRAAD_HOST"
            return 1
        }
        ssh "${CURRENT_USER}@${LANDSRAAD_HOST}" "sudo bash /tmp/setup-stilgar-user-standalone.sh ${DEPLOY_USER} && rm /tmp/setup-stilgar-user-standalone.sh" || {
            log_error "Failed to create user on $LANDSRAAD_HOST"
            log_info "You may need to run this manually on $LANDSRAAD_HOST:"
            log_info "  ssh ${CURRENT_USER}@$LANDSRAAD_HOST"
            log_info "  sudo bash /tmp/setup-stilgar-user-standalone.sh ${DEPLOY_USER}"
            return 1
        }
    else
        log_info "[DRY RUN] Would create user on $LANDSRAAD_HOST"
    fi

    log_success "Phase 1: User setup completed"
}

# Phase 2: Setup SSH automation
phase_ssh_setup() {
    if [[ "$SKIP_SSH_SETUP" == "true" ]]; then
        log_section "Phase 2: SSH Automation [SKIPPED]"
        return 0
    fi

    log_section "Phase 2: SSH Key Generation and Distribution"

    log_step "Setting up passwordless SSH: $MENTAT_HOST -> $LANDSRAAD_HOST"

    if [[ "$DRY_RUN" != "true" ]]; then
        # Generate SSH key on mentat
        log_info "Generating SSH key on mentat for $DEPLOY_USER"
        sudo -u "$DEPLOY_USER" bash -c "
            if [[ ! -f /home/${DEPLOY_USER}/.ssh/id_ed25519 ]]; then
                ssh-keygen -t ed25519 -f /home/${DEPLOY_USER}/.ssh/id_ed25519 -N '' -C '${DEPLOY_USER}@${MENTAT_HOST}'
            fi
        "

        # Copy SSH key to landsraad using current user with sudo
        # (Cannot use ssh-copy-id because stilgar doesn't have password auth set up)
        log_info "Copying SSH key to $LANDSRAAD_HOST"
        local pub_key=$(sudo cat /home/${DEPLOY_USER}/.ssh/id_ed25519.pub)

        ssh "${CURRENT_USER}@${LANDSRAAD_HOST}" "
            sudo mkdir -p /home/${DEPLOY_USER}/.ssh
            echo '$pub_key' | sudo tee -a /home/${DEPLOY_USER}/.ssh/authorized_keys >/dev/null
            sudo chmod 600 /home/${DEPLOY_USER}/.ssh/authorized_keys
            sudo chmod 700 /home/${DEPLOY_USER}/.ssh
            sudo chown -R ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.ssh
        " || {
            log_error "Failed to copy SSH key to $LANDSRAAD_HOST"
            return 1
        }

        log_success "SSH key copied to $LANDSRAAD_HOST"

        # Test connection
        log_info "Testing SSH connection"
        if sudo -u "$DEPLOY_USER" ssh -o BatchMode=yes "$DEPLOY_USER@$LANDSRAAD_HOST" "echo 'SSH OK'" &>/dev/null; then
            log_success "Passwordless SSH connection verified"
        else
            log_warning "SSH connection test failed - may need manual intervention"
        fi
    else
        log_info "[DRY RUN] Would setup SSH keys"
    fi

    log_success "Phase 2: SSH automation completed"
}

# Phase 3: Generate deployment secrets
phase_secrets_generation() {
    if [[ "$SKIP_SECRETS" == "true" ]]; then
        log_section "Phase 3: Secrets Generation [SKIPPED]"

        # Load existing secrets
        if [[ -f "$SECRETS_FILE" ]]; then
            log_info "Loading existing secrets from $SECRETS_FILE"
            source "$SECRETS_FILE"
        else
            log_error "No secrets file found at $SECRETS_FILE"
            log_fatal "Run without --skip-secrets or create secrets file manually"
        fi
        return 0
    fi

    log_section "Phase 3: Generating Deployment Secrets"

    if [[ "$DRY_RUN" != "true" ]]; then
        local interactive_flag=""
        if [[ "$INTERACTIVE" == "true" ]]; then
            interactive_flag="--interactive"
        fi

        bash "${SCRIPT_DIR}/scripts/generate-deployment-secrets.sh" $interactive_flag

        # Load generated secrets
        if [[ -f "$SECRETS_FILE" ]]; then
            source "$SECRETS_FILE"
            log_success "Secrets loaded and ready"
        else
            log_fatal "Secrets file not created"
        fi
    else
        log_info "[DRY RUN] Would generate deployment secrets"
    fi

    log_success "Phase 3: Secrets generation completed"
}

# Phase 4: Prepare Mentat server
phase_prepare_mentat() {
    if [[ "$SKIP_MENTAT_PREP" == "true" ]]; then
        log_section "Phase 4: Prepare Mentat [SKIPPED]"
        return 0
    fi

    log_section "Phase 4: Preparing Mentat (Observability Server)"

    if [[ "$DRY_RUN" != "true" ]]; then
        # Run prepare script with sudo (needs root for system packages)
        log_info "Running prepare-mentat.sh"
        sudo bash "${SCRIPT_DIR}/scripts/prepare-mentat.sh" || {
            log_error "Mentat preparation failed"
            return 1
        }
    else
        log_info "[DRY RUN] Would prepare mentat server"
    fi

    log_success "Phase 4: Mentat preparation completed"
}

# Phase 5: Prepare Landsraad server
phase_prepare_landsraad() {
    if [[ "$SKIP_LANDSRAAD_PREP" == "true" ]]; then
        log_section "Phase 5: Prepare Landsraad [SKIPPED]"
        return 0
    fi

    log_section "Phase 5: Preparing Landsraad (Application Server)"

    if [[ "$DRY_RUN" != "true" ]]; then
        # Copy prepare script to landsraad using current user (has file access)
        log_info "Copying scripts to $LANDSRAAD_HOST"
        scp -r \
            "${SCRIPT_DIR}/scripts/prepare-landsraad.sh" \
            "${SCRIPT_DIR}/utils" \
            "${CURRENT_USER}@$LANDSRAAD_HOST:/tmp/" || {
            log_error "Failed to copy scripts to $LANDSRAAD_HOST"
            return 1
        }

        log_info "Running prepare-landsraad.sh on $LANDSRAAD_HOST"
        ssh "${CURRENT_USER}@$LANDSRAAD_HOST" \
            "sudo bash /tmp/prepare-landsraad.sh" || {
            log_error "Landsraad preparation failed"
            return 1
        }
    else
        log_info "[DRY RUN] Would prepare landsraad server"
    fi

    log_success "Phase 5: Landsraad preparation completed"
}

# Phase 6: Deploy application
phase_deploy_application() {
    if [[ "$SKIP_APP_DEPLOY" == "true" ]]; then
        log_section "Phase 6: Deploy Application [SKIPPED]"
        return 0
    fi

    log_section "Phase 6: Deploying CHOM Application"

    if [[ "$DRY_RUN" != "true" ]]; then
        # Create .env file on landsraad
        log_info "Creating .env file on $LANDSRAAD_HOST"

        # Source secrets file
        if [[ -f "$SECRETS_FILE" ]]; then
            # shellcheck source=/dev/null
            source "$SECRETS_FILE"

            # Create .env file on remote server
            ssh "${CURRENT_USER}@${LANDSRAAD_HOST}" "sudo -u $DEPLOY_USER bash" <<'ENVEOF'
mkdir -p /var/www/chom/shared
cat > /var/www/chom/shared/.env <<'INNEREOF'
APP_NAME=CHOM
APP_ENV=${APP_ENV:-production}
APP_KEY=${APP_KEY}
APP_DEBUG=${APP_DEBUG:-false}
APP_URL=${APP_URL:-https://chom.arewel.com}

LOG_CHANNEL=stack
LOG_LEVEL=info

DB_CONNECTION=pgsql
DB_HOST=localhost
DB_PORT=5432
DB_DATABASE=${DB_NAME:-chom}
DB_USERNAME=${DB_USER:-chom}
DB_PASSWORD=${DB_PASSWORD}

BROADCAST_DRIVER=log
CACHE_DRIVER=redis
FILESYSTEM_DISK=local
QUEUE_CONNECTION=redis
SESSION_DRIVER=redis
SESSION_LIFETIME=120

REDIS_HOST=localhost
REDIS_PASSWORD=${REDIS_PASSWORD:-}
REDIS_PORT=6379

MAIL_MAILER=smtp
MAIL_HOST=${MAIL_HOST:-localhost}
MAIL_PORT=${MAIL_PORT:-1025}
MAIL_USERNAME=${MAIL_USERNAME:-null}
MAIL_PASSWORD=${MAIL_PASSWORD:-null}
MAIL_ENCRYPTION=${MAIL_ENCRYPTION:-null}
MAIL_FROM_ADDRESS=${MAIL_FROM_ADDRESS:-noreply@chom.arewel.com}
MAIL_FROM_NAME="${APP_NAME:-CHOM}"
INNEREOF
chmod 600 /var/www/chom/shared/.env
ENVEOF

            log_success ".env file created on $LANDSRAAD_HOST"
        else
            log_error "Secrets file not found: $SECRETS_FILE"
            log_warning "Manual step required: Create .env file on $LANDSRAAD_HOST"
            log_info "  Location: /var/www/chom/shared/.env"
        fi

        # Run deployment script
        if [[ -n "${REPO_URL:-}" ]]; then
            log_info "Deploying application from $REPO_URL"
            # Use current user for SSH, then sudo to deploy user on remote
            ssh "${CURRENT_USER}@${LANDSRAAD_HOST}" \
                "sudo -u $DEPLOY_USER bash -c 'export REPO_URL=\"$REPO_URL\" && bash /tmp/deploy-application.sh'" || {
                log_error "Application deployment failed"
                return 1
            }
        else
            log_warning "REPO_URL not set - skipping application deployment"
            log_info "Set REPO_URL in secrets file and run deploy-application.sh manually"
        fi
    else
        log_info "[DRY RUN] Would deploy application"
    fi

    log_success "Phase 6: Application deployment completed"
}

# Phase 7: Deploy observability stack
phase_deploy_observability() {
    if [[ "$SKIP_OBSERVABILITY" == "true" ]]; then
        log_section "Phase 7: Deploy Observability [SKIPPED]"
        return 0
    fi

    log_section "Phase 7: Deploying Observability Stack"

    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "Deploying observability stack on mentat"

        # Start observability services
        sudo systemctl start prometheus grafana-server loki promtail alertmanager node_exporter || {
            log_warning "Some observability services failed to start"
        }

        # Verify services are running
        sleep 3
        local failed_services=()
        for service in prometheus grafana-server loki promtail alertmanager node_exporter; do
            if ! systemctl is-active --quiet "$service"; then
                failed_services+=("$service")
            fi
        done

        if [[ ${#failed_services[@]} -gt 0 ]]; then
            log_warning "Failed to start: ${failed_services[*]}"
        else
            log_success "All observability services started"
        fi
    else
        log_info "[DRY RUN] Would deploy observability stack"
    fi

    log_success "Phase 7: Observability deployment completed"
}

# Phase 8: Verification
phase_verification() {
    if [[ "$SKIP_VERIFICATION" == "true" ]]; then
        log_section "Phase 8: Verification [SKIPPED]"
        return 0
    fi

    log_section "Phase 8: Post-Deployment Verification"

    if [[ "$DRY_RUN" != "true" ]]; then
        # Check mentat services
        log_step "Verifying mentat services"
        local mentat_services=(prometheus grafana-server loki promtail alertmanager node_exporter)
        for service in "${mentat_services[@]}"; do
            if systemctl is-active --quiet "$service"; then
                log_success "$service is running"
            else
                log_error "$service is not running"
            fi
        done

        # Check landsraad services
        log_step "Verifying landsraad services"
        ssh "${CURRENT_USER}@${LANDSRAAD_HOST}" "
            for service in nginx postgresql redis-server php*-fpm; do
                if systemctl is-active --quiet \$service 2>/dev/null; then
                    echo \"OK: \$service\"
                else
                    echo \"FAILED: \$service\"
                fi
            done
        " || log_warning "Could not verify landsraad services"

        # Test HTTP endpoints
        log_step "Testing HTTP endpoints"

        # Test Prometheus
        if curl -sf http://localhost:9090/-/healthy &>/dev/null; then
            log_success "Prometheus is healthy"
        else
            log_warning "Prometheus health check failed"
        fi

        # Test Grafana
        if curl -sf http://localhost:3000/api/health &>/dev/null; then
            log_success "Grafana is healthy"
        else
            log_warning "Grafana health check failed"
        fi

    else
        log_info "[DRY RUN] Would verify deployment"
    fi

    log_success "Phase 8: Verification completed"
}

# Display post-deployment information
display_post_deployment_info() {
    print_header "Deployment Complete"

    log_success "CHOM has been deployed successfully!"
    log_info ""
    log_info "Access URLs:"
    log_info "  Application:  https://${APP_DOMAIN:-chom.arewel.com}"
    log_info "  Grafana:      http://${MENTAT_HOST}:3000"
    log_info "  Prometheus:   http://${MENTAT_HOST}:9090"
    log_info "  AlertManager: http://${MENTAT_HOST}:9093"
    log_info ""
    log_info "Default Credentials:"
    log_info "  Grafana: admin / (check /etc/grafana/grafana.ini)"
    log_info ""
    log_info "Next Steps:"
    log_info "  1. Configure Grafana datasources and dashboards"
    log_info "  2. Set up SSL certificates with Certbot"
    log_info "  3. Configure firewall rules"
    log_info "  4. Set up monitoring alerts"
    log_info "  5. Configure backup schedule"
    log_info ""
    log_info "Important Files:"
    log_info "  Secrets: $SECRETS_FILE"
    log_info "  Logs: $LOG_FILE"
    log_info ""
    log_warning "Security Reminders:"
    log_warning "  - Change default Grafana admin password"
    log_warning "  - Review firewall rules"
    log_warning "  - Enable SSL/TLS for all services"
    log_warning "  - Set up regular backups"
    log_warning "  - Keep $SECRETS_FILE secure (permissions: 600)"
}

# Main execution
main() {
    start_timer

    print_header "CHOM Automated Deployment"
    print_section "Fully Automated Infrastructure and Application Deployment"

    preflight_checks
    display_deployment_plan

    if [[ "$DRY_RUN" == "true" ]]; then
        log_success "Dry run completed - no changes made"
        exit 0
    fi

    # Execute deployment phases
    phase_user_setup
    phase_ssh_setup
    phase_secrets_generation
    phase_prepare_mentat
    phase_prepare_landsraad
    phase_deploy_application
    phase_deploy_observability
    phase_verification

    display_post_deployment_info

    end_timer "Total deployment"

    log_success "Automated deployment completed successfully!"

    exit 0
}

# Error handler
deployment_error() {
    local exit_code=$?
    log_error "Deployment failed at line $BASH_LINENO"
    log_error "Exit code: $exit_code"
    log_info "Check logs: $LOG_FILE"

    notify_deployment_failure "${APP_ENV:-production}" "Automated deployment failed"

    exit "$exit_code"
}

trap deployment_error ERR

main
