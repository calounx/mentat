#!/usr/bin/env bash
# Quick Deployment Script for Phase 0 Reliability Optimizations
# Run this script to deploy Phase 0 changes to production servers
#
# Usage: ./DEPLOY-PHASE-0-NOW.sh [--skip-observability] [--dry-run]
#
# This script automates the deployment steps from PHASE-0-DEPLOYMENT-REPORT.md

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MENTAT_HOST="mentat.arewel.com"
LANDSRAAD_HOST="landsraad.arewel.com"
REPO_URL="https://github.com/calounx/mentat.git"
DEPLOY_USER="stilgar"
SKIP_OBSERVABILITY=false
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-observability)
            SKIP_OBSERVABILITY=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            cat <<EOF
Phase 0 Deployment Script

Usage: $0 [OPTIONS]

Options:
  --skip-observability    Skip observability stack update
  --dry-run              Show commands without executing
  --help                 Show this help message

This script will:
1. Copy updated deployment scripts to mentat
2. Deploy application to landsraad (new API endpoints, migrations)
3. Deploy observability updates to mentat (alert rules, SMTP config)

Total estimated time: 20-30 minutes

EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Helper functions
log_section() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

log_step() {
    echo -e "${GREEN}▶${NC} $1"
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

execute() {
    local cmd="$1"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} Would execute: $cmd"
    else
        log_info "Executing: $cmd"
        eval "$cmd"
    fi
}

# Check prerequisites
check_prerequisites() {
    log_section "Phase 0: Prerequisites Check"

    local checks_passed=true

    # Check SSH access to mentat
    log_step "Checking SSH access to $MENTAT_HOST..."
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "calounx@${MENTAT_HOST}" "echo 'SSH OK'" &>/dev/null; then
        log_success "SSH to $MENTAT_HOST: OK"
    else
        log_error "SSH to $MENTAT_HOST: FAILED"
        checks_passed=false
    fi

    # Check SSH access to landsraad
    log_step "Checking SSH access to $LANDSRAAD_HOST..."
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "calounx@${LANDSRAAD_HOST}" "echo 'SSH OK'" &>/dev/null; then
        log_success "SSH to $LANDSRAAD_HOST: OK"
    else
        log_error "SSH to $LANDSRAAD_HOST: FAILED"
        checks_passed=false
    fi

    # Check if deployment scripts exist locally
    log_step "Checking local deployment files..."
    if [[ -f "deploy/scripts/deploy-observability.sh" ]]; then
        log_success "deploy-observability.sh: Found"
    else
        log_error "deploy-observability.sh: NOT FOUND"
        checks_passed=false
    fi

    if [[ -f "deploy/config/mentat/prometheus-alerts/exporters.yml" ]]; then
        log_success "exporters.yml: Found"
    else
        log_error "exporters.yml: NOT FOUND"
        checks_passed=false
    fi

    if [[ "$checks_passed" == "false" ]]; then
        log_error "Prerequisites check failed. Please fix errors before proceeding."
        exit 1
    fi

    log_success "All prerequisites passed!"
}

# Phase 1: Update deployment scripts on mentat
phase1_update_scripts() {
    log_section "Phase 1: Update Deployment Scripts on mentat"

    log_step "Copying deploy-observability.sh to mentat..."
    execute "scp deploy/scripts/deploy-observability.sh calounx@${MENTAT_HOST}:/tmp/"

    log_step "Copying exporters.yml to mentat..."
    execute "scp deploy/config/mentat/prometheus-alerts/exporters.yml calounx@${MENTAT_HOST}:/tmp/"

    log_step "Installing updated scripts on mentat..."
    execute "ssh calounx@${MENTAT_HOST} 'sudo cp /tmp/deploy-observability.sh /opt/chom-deploy/scripts/ && \
        sudo chmod +x /opt/chom-deploy/scripts/deploy-observability.sh && \
        sudo chown stilgar:stilgar /opt/chom-deploy/scripts/deploy-observability.sh && \
        sudo mkdir -p /opt/chom-deploy/config/mentat/prometheus-alerts/ && \
        sudo cp /tmp/exporters.yml /opt/chom-deploy/config/mentat/prometheus-alerts/ && \
        sudo chown -R stilgar:stilgar /opt/chom-deploy/config/'"

    log_success "Phase 1 complete: Deployment scripts updated on mentat"
}

# Phase 2: Deploy application to landsraad
phase2_deploy_application() {
    log_section "Phase 2: Deploy Application to landsraad"

    log_warning "This phase will:"
    log_info "  - Pull latest code from GitHub (bb283db)"
    log_info "  - Create new release in /var/www/chom/releases/"
    log_info "  - Run database migrations (create system_settings table)"
    log_info "  - Switch current symlink to new release"
    log_info "  - Restart PHP-FPM"
    log_info "  - Run health checks"
    echo ""
    log_warning "Estimated time: 5-10 minutes"
    echo ""

    if [[ "$DRY_RUN" == "false" ]]; then
        read -p "Proceed with application deployment? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_warning "Application deployment skipped by user"
            return
        fi
    fi

    log_step "Starting deployment on mentat (will SSH to landsraad)..."

    local deploy_cmd="cd /opt/chom-deploy && sudo -u ${DEPLOY_USER} ./deploy-chom.sh \
        --environment=production \
        --branch=main \
        --repo-url=${REPO_URL}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute on mentat: $deploy_cmd"
    else
        log_info "Executing deployment..."
        log_warning "This may take 5-10 minutes. Please wait..."
        ssh -t "calounx@${MENTAT_HOST}" "$deploy_cmd"
    fi

    log_success "Phase 2 complete: Application deployed to landsraad"
}

# Phase 3: Configure SMTP settings
phase3_configure_smtp() {
    log_section "Phase 3: Configure SMTP Settings (Manual Step)"

    log_warning "SMTP configuration must be done manually:"
    echo ""
    log_info "Option A: Via Web UI (Recommended)"
    log_info "  1. Open: https://${LANDSRAAD_HOST}/admin/system-settings"
    log_info "  2. Fill in SMTP configuration form"
    log_info "  3. Click Save"
    echo ""
    log_info "Option B: Via Artisan Tinker"
    log_info "  1. SSH to landsraad: ssh calounx@${LANDSRAAD_HOST}"
    log_info "  2. Run: sudo -u stilgar php /var/www/chom/current/artisan tinker"
    log_info "  3. Execute:"
    log_info "     App\\Models\\SystemSetting::set('mail.host', 'smtp.example.com', 'string');"
    log_info "     App\\Models\\SystemSetting::set('mail.port', '587', 'integer');"
    log_info "     App\\Models\\SystemSetting::set('mail.username', 'user', 'string');"
    log_info "     App\\Models\\SystemSetting::set('mail.password', 'pass', 'encrypted');"
    log_info "     App\\Models\\SystemSetting::set('mail.from_address', 'alerts@chom.arewel.com', 'string');"
    echo ""

    if [[ "$DRY_RUN" == "false" ]]; then
        read -p "Have you configured SMTP settings? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_warning "SMTP not configured. Observability deployment will use defaults."
            log_warning "You can run Phase 4 again after configuring SMTP."
        fi
    fi
}

# Phase 4: Deploy observability updates
phase4_deploy_observability() {
    if [[ "$SKIP_OBSERVABILITY" == "true" ]]; then
        log_warning "Observability deployment skipped (--skip-observability flag)"
        return
    fi

    log_section "Phase 4: Deploy Observability Updates to mentat"

    log_warning "This phase will:"
    log_info "  - Fetch SMTP config from CHOM API"
    log_info "  - Update Alertmanager configuration"
    log_info "  - Deploy new alert rules (exporters.yml)"
    log_info "  - Reload Prometheus (hot reload, no downtime)"
    log_info "  - Restart Alertmanager (brief interruption)"
    log_info "  - Run health checks"
    echo ""
    log_warning "Estimated time: 3-5 minutes"
    echo ""

    if [[ "$DRY_RUN" == "false" ]]; then
        read -p "Proceed with observability deployment? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_warning "Observability deployment skipped by user"
            return
        fi
    fi

    log_step "Starting observability deployment..."

    local deploy_cmd="cd /opt/chom-deploy && sudo -u ${DEPLOY_USER} ./scripts/deploy-observability.sh --config-dir ./config/mentat"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute on mentat: $deploy_cmd"
    else
        log_info "Executing deployment..."
        ssh -t "calounx@${MENTAT_HOST}" "$deploy_cmd"
    fi

    log_success "Phase 4 complete: Observability stack updated on mentat"
}

# Phase 5: Verify deployment
phase5_verify() {
    log_section "Phase 5: Verify Deployment"

    log_step "Testing API endpoints..."

    # Test SMTP config API
    log_info "Testing /api/v1/system/smtp-config..."
    if curl -sf "https://${LANDSRAAD_HOST}/api/v1/system/smtp-config" >/dev/null 2>&1; then
        log_success "SMTP config API: OK"
    else
        log_error "SMTP config API: FAILED"
    fi

    # Test observability health API
    log_info "Testing /api/v1/observability/health..."
    if curl -sf "https://${LANDSRAAD_HOST}/api/v1/observability/health" >/dev/null 2>&1; then
        log_success "Observability health API: OK"
    else
        log_error "Observability health API: FAILED"
    fi

    if [[ "$SKIP_OBSERVABILITY" == "false" ]]; then
        log_step "Checking observability services..."

        log_info "Checking Prometheus..."
        ssh "calounx@${MENTAT_HOST}" "sudo systemctl is-active prometheus" >/dev/null 2>&1 && \
            log_success "Prometheus: Running" || \
            log_error "Prometheus: NOT RUNNING"

        log_info "Checking Alertmanager..."
        ssh "calounx@${MENTAT_HOST}" "sudo systemctl is-active alertmanager" >/dev/null 2>&1 && \
            log_success "Alertmanager: Running" || \
            log_error "Alertmanager: NOT RUNNING"
    fi

    echo ""
    log_success "Verification complete!"
    echo ""
    log_info "For detailed verification, see PHASE-0-DEPLOYMENT-REPORT.md Section: Success Criteria"
}

# Main deployment flow
main() {
    echo -e "${GREEN}"
    cat <<'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║   Phase 0 Reliability Optimizations - Deployment Script      ║
║                                                               ║
║   This will deploy:                                           ║
║   • New API endpoints (SMTP config, observability health)     ║
║   • Database migrations (system_settings table)               ║
║   • Enhanced alert rules for exporters                        ║
║   • Alertmanager SMTP auto-configuration                      ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE: No changes will be made"
        echo ""
    fi

    # Run all phases
    check_prerequisites
    phase1_update_scripts
    phase2_deploy_application
    phase3_configure_smtp
    phase4_deploy_observability
    phase5_verify

    # Final summary
    log_section "Deployment Complete!"

    log_success "Phase 0 reliability optimizations have been deployed successfully!"
    echo ""
    log_info "What was deployed:"
    log_info "  ✓ New API endpoints for SMTP config and observability health"
    log_info "  ✓ Database migration for system_settings table"
    log_info "  ✓ Enhanced Prometheus alert rules for exporter monitoring"
    log_info "  ✓ Alertmanager auto-configuration via CHOM API"
    echo ""
    log_info "Next steps:"
    log_info "  1. Verify all API endpoints are responding correctly"
    log_info "  2. Configure SMTP settings if not done yet (Phase 3)"
    log_info "  3. Send test alert to verify email delivery"
    log_info "  4. Monitor logs for any issues"
    echo ""
    log_info "Useful commands:"
    log_info "  • Check Prometheus alerts: https://${MENTAT_HOST}/prometheus/alerts"
    log_info "  • Check Alertmanager: https://${MENTAT_HOST}/alertmanager"
    log_info "  • View API response: curl https://${LANDSRAAD_HOST}/api/v1/system/smtp-config"
    log_info "  • Check logs: ssh calounx@${LANDSRAAD_HOST} sudo journalctl -u php8.2-fpm -f"
    echo ""
    log_success "Deployment report: PHASE-0-DEPLOYMENT-REPORT.md"
}

# Run main
main
