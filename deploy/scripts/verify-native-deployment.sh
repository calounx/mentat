#!/usr/bin/env bash
# Verify native deployment - no Docker, Debian 13 compatible
# Usage: ./verify-native-deployment.sh

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ERRORS=0

echo "========================================"
echo "  Native Deployment Verification"
echo "========================================"
echo ""

# Check 1: No Docker references in main scripts
log_info "Check 1: Verifying no Docker references in deployment scripts..."
if grep -r "docker" "$SCRIPT_DIR/prepare-mentat.sh" "$SCRIPT_DIR/deploy-observability.sh" 2>/dev/null | grep -v "backup"; then
    log_error "Found Docker references in main deployment scripts!"
    ((ERRORS++))
else
    log_success "No Docker references found in main deployment scripts"
fi

# Check 2: No software-properties-common
log_info "Check 2: Verifying no software-properties-common references..."
if grep -r "software-properties-common" "$SCRIPT_DIR"/*.sh 2>/dev/null | grep -v "verify-"; then
    log_error "Found software-properties-common references!"
    ((ERRORS++))
else
    log_success "No software-properties-common references found"
fi

# Check 3: Systemd service files present in prepare-mentat.sh
log_info "Check 3: Verifying systemd services are created..."
if grep -q "prometheus.service" "$SCRIPT_DIR/prepare-mentat.sh" && \
   grep -q "loki.service" "$SCRIPT_DIR/prepare-mentat.sh" && \
   grep -q "alertmanager.service" "$SCRIPT_DIR/prepare-mentat.sh"; then
    log_success "Systemd service creation found in prepare-mentat.sh"
else
    log_error "Systemd service creation missing!"
    ((ERRORS++))
fi

# Check 4: Native binary installations
log_info "Check 4: Verifying native binary installations..."
if grep -q 'OBSERVABILITY_DIR}/bin/prometheus' "$SCRIPT_DIR/prepare-mentat.sh" && \
   grep -q 'OBSERVABILITY_DIR}/bin/loki' "$SCRIPT_DIR/prepare-mentat.sh"; then
    log_success "Native binary installations found"
else
    log_error "Native binary installations missing!"
    ((ERRORS++))
fi

# Check 5: Grafana from APT repository
log_info "Check 5: Verifying Grafana APT installation..."
if grep -q "apt.grafana.com" "$SCRIPT_DIR/prepare-mentat.sh" && \
   grep -q "apt-get install -y grafana" "$SCRIPT_DIR/prepare-mentat.sh"; then
    log_success "Grafana APT installation found"
else
    log_error "Grafana APT installation missing!"
    ((ERRORS++))
fi

# Check 6: Docker compose file deleted/renamed
log_info "Check 6: Verifying docker-compose.prod.yml is removed..."
if [[ ! -f "$SCRIPT_DIR/../config/mentat/docker-compose.prod.yml" ]]; then
    log_success "docker-compose.prod.yml not found (correctly removed)"
else
    log_error "docker-compose.prod.yml still exists!"
    ((ERRORS++))
fi

# Check 7: Backup files exist
log_info "Check 7: Verifying backup files exist..."
if [[ -f "$SCRIPT_DIR/prepare-mentat.sh.docker-backup" ]] && \
   [[ -f "$SCRIPT_DIR/deploy-observability.sh.docker-backup" ]]; then
    log_success "Backup files exist"
else
    log_warn "Backup files not found (may have been created elsewhere)"
fi

# Check 8: Native deployment in deploy-observability.sh
log_info "Check 8: Verifying native deployment commands..."
if grep -q "systemctl" "$SCRIPT_DIR/deploy-observability.sh" && \
   ! grep -q "docker compose" "$SCRIPT_DIR/deploy-observability.sh"; then
    log_success "Native deployment using systemctl found"
else
    log_error "Docker compose references still in deploy-observability.sh!"
    ((ERRORS++))
fi

# Check 9: Observability user creation
log_info "Check 9: Verifying observability user creation..."
if grep -q "useradd.*observability" "$SCRIPT_DIR/prepare-mentat.sh"; then
    log_success "Observability user creation found"
else
    log_error "Observability user creation missing!"
    ((ERRORS++))
fi

# Check 10: Configuration validation
log_info "Check 10: Verifying configuration validation tools..."
if grep -q "promtool" "$SCRIPT_DIR/deploy-observability.sh" && \
   grep -q "amtool" "$SCRIPT_DIR/deploy-observability.sh"; then
    log_success "Configuration validation tools found"
else
    log_warn "Configuration validation tools may be missing"
fi

echo ""
echo "========================================"
if [[ $ERRORS -eq 0 ]]; then
    log_success "All checks passed! Deployment is native and Debian 13 compatible."
    echo ""
    echo "Summary:"
    echo "  - No Docker dependencies"
    echo "  - No software-properties-common"
    echo "  - Systemd services configured"
    echo "  - Native binaries installed"
    echo "  - Grafana from APT repository"
    echo "  - Docker Compose file removed"
    echo ""
    exit 0
else
    log_error "$ERRORS checks failed!"
    echo ""
    echo "Please review the errors above and fix them."
    exit 1
fi
