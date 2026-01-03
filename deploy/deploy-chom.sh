#!/usr/bin/env bash
# Main deployment orchestration script for CHOM
# Coordinates deployment across mentat and landsraad servers
# Run from mentat.arewel.com as user stilgar
#
# Usage: ./deploy-chom.sh --environment=production --branch=main [options]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/logging.sh"
source "${SCRIPT_DIR}/utils/notifications.sh"

# Default configuration
ENVIRONMENT="${ENVIRONMENT:-production}"
BRANCH="${BRANCH:-main}"
REPO_URL="${REPO_URL:-}"
SKIP_BACKUP=false
SKIP_MIGRATIONS=false
SKIP_OBSERVABILITY=false
DEPLOY_USER="${DEPLOY_USER:-stilgar}"
MENTAT_HOST="${MENTAT_HOST:-mentat.arewel.com}"
LANDSRAAD_HOST="${LANDSRAAD_HOST:-landsraad.arewel.com}"

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
        --help)
            cat <<EOF
CHOM Deployment Script
=====================

Usage: $0 [OPTIONS]

Options:
  --environment=ENV         Deployment environment (default: production)
  --branch=BRANCH          Git branch to deploy (default: main)
  --repo-url=URL           Repository URL (required)
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

# Check SSH connectivity
check_ssh_connectivity() {
    log_section "Checking SSH Connectivity"

    log_step "Testing connection to landsraad.arewel.com"
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "${DEPLOY_USER}@${LANDSRAAD_HOST}" "echo 'SSH OK'" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "SSH connection to landsraad established"
    else
        log_fatal "Cannot connect to landsraad via SSH. Please check SSH keys and connectivity."
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
    local disk_usage=$(ssh "${DEPLOY_USER}@${LANDSRAAD_HOST}" "df / | tail -1 | awk '{print \$5}' | sed 's/%//'")

    if [[ $disk_usage -lt 80 ]]; then
        log_success "Disk usage on landsraad: ${disk_usage}%"
    else
        log_warning "Disk usage on landsraad is high: ${disk_usage}%"
    fi

    # Check if services are running on landsraad
    log_step "Checking services on landsraad"
    local services=("nginx" "php8.2-fpm" "postgresql" "redis-server")

    for service in "${services[@]}"; do
        if ssh "${DEPLOY_USER}@${LANDSRAAD_HOST}" "sudo systemctl is-active --quiet $service"; then
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

    # Build deployment command
    local deploy_cmd="/var/www/chom/deploy/scripts/deploy-application.sh --branch $BRANCH --repo-url '$REPO_URL'"

    if [[ "$SKIP_BACKUP" == true ]]; then
        deploy_cmd="$deploy_cmd --skip-backup"
    fi

    if [[ "$SKIP_MIGRATIONS" == true ]]; then
        deploy_cmd="$deploy_cmd --skip-migrations"
    fi

    # Export environment variables for remote execution
    local env_vars="export ENVIRONMENT='$ENVIRONMENT'; export REPO_URL='$REPO_URL'; export BRANCH='$BRANCH';"

    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        env_vars="$env_vars export GITHUB_TOKEN='$GITHUB_TOKEN';"
    fi

    # Execute deployment on landsraad
    log_info "Executing deployment on landsraad.arewel.com"

    if ssh "${DEPLOY_USER}@${LANDSRAAD_HOST}" "$env_vars $deploy_cmd" 2>&1 | tee -a "$LOG_FILE"; then
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

    if ssh "${DEPLOY_USER}@${LANDSRAAD_HOST}" "/var/www/chom/deploy/scripts/health-check.sh" 2>&1 | tee -a "$LOG_FILE"; then
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
    local release_id=$(ssh "${DEPLOY_USER}@${LANDSRAAD_HOST}" "basename \$(readlink -f /var/www/chom/current)" 2>/dev/null || echo "unknown")

    log_info "Environment: $ENVIRONMENT"
    log_info "Branch: $BRANCH"
    log_info "Release ID: $release_id"
    log_info "Deployed to: $LANDSRAAD_HOST"

    # Get commit information
    if [[ "$release_id" != "unknown" ]]; then
        local commit_info=$(ssh "${DEPLOY_USER}@${LANDSRAAD_HOST}" "cat /var/www/chom/current/.deployment-info 2>/dev/null" || echo "")
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
