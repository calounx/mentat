#!/bin/bash
#===============================================================================
# Observability Stack Deployment Commands
# Pre-validated and ready for execution
#
# Date: 2025-12-27
# Status: READY FOR DEPLOYMENT
#
# Usage:
#   Source this file to get helper functions, or copy/paste commands manually
#===============================================================================

set -euo pipefail

STACK_ROOT="/home/calounx/repositories/mentat/observability-stack"

#===============================================================================
# HELPER FUNCTIONS
#===============================================================================

show_status() {
    echo "==================================="
    echo "Observability Stack - Current Status"
    echo "==================================="
    cd "$STACK_ROOT"
    sudo ./scripts/upgrade-orchestrator.sh --status
}

run_dry_run() {
    local phase="${1:-1}"
    echo "==================================="
    echo "Dry-Run Mode: Phase $phase"
    echo "==================================="
    cd "$STACK_ROOT"
    sudo ./scripts/upgrade-orchestrator.sh --phase "$phase" --dry-run
}

deploy_phase1() {
    echo "==================================="
    echo "Deploying Phase 1: Low-Risk Exporters"
    echo "==================================="
    cd "$STACK_ROOT"
    sudo ./scripts/upgrade-orchestrator.sh --phase 1 --mode standard
}

deploy_phase2() {
    echo "==================================="
    echo "Deploying Phase 2: Prometheus (Two-Stage)"
    echo "==================================="
    cd "$STACK_ROOT"
    sudo ./scripts/upgrade-orchestrator.sh --phase 2 --mode safe
}

deploy_phase3() {
    echo "==================================="
    echo "Deploying Phase 3: Logging Stack"
    echo "==================================="
    cd "$STACK_ROOT"
    sudo ./scripts/upgrade-orchestrator.sh --phase 3 --mode standard
}

verify_services() {
    echo "==================================="
    echo "Service Status Verification"
    echo "==================================="
    for svc in node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter prometheus loki promtail; do
        echo -n "$svc: "
        systemctl is-active "$svc" 2>/dev/null || echo "inactive"
    done
}

test_endpoints() {
    echo "==================================="
    echo "Metrics Endpoint Testing"
    echo "==================================="

    echo "Testing node_exporter (port 9100)..."
    curl -s http://localhost:9100/metrics | head -5 || echo "FAILED"

    echo ""
    echo "Testing nginx_exporter (port 9113)..."
    curl -s http://localhost:9113/metrics | head -5 || echo "FAILED"

    echo ""
    echo "Testing mysqld_exporter (port 9104)..."
    curl -s http://localhost:9104/metrics | head -5 || echo "FAILED"

    echo ""
    echo "Testing prometheus (port 9090)..."
    curl -s http://localhost:9090/-/healthy || echo "FAILED"

    echo ""
    echo "Testing loki (port 3100)..."
    curl -s http://localhost:3100/ready || echo "FAILED"
}

rollback_upgrade() {
    echo "==================================="
    echo "Rolling Back Last Upgrade"
    echo "==================================="
    cd "$STACK_ROOT"
    sudo ./scripts/upgrade-orchestrator.sh --rollback
}

resume_upgrade() {
    echo "==================================="
    echo "Resuming Failed Upgrade"
    echo "==================================="
    cd "$STACK_ROOT"
    sudo ./scripts/upgrade-orchestrator.sh --resume
}

#===============================================================================
# QUICK DEPLOYMENT COMMANDS
# Copy and paste these directly into your terminal
#===============================================================================

cat << 'EOF'

QUICK DEPLOYMENT COMMANDS
=================================

Step 1: Navigate to stack directory
-----------------------------------
cd /home/calounx/repositories/mentat/observability-stack


Step 2: Run dry-run to preview changes
-----------------------------------
sudo ./scripts/upgrade-orchestrator.sh --phase 1 --dry-run


Step 3: Deploy Phase 1 (Low-Risk Exporters)
-----------------------------------
sudo ./scripts/upgrade-orchestrator.sh --phase 1 --mode standard


Step 4: Verify Phase 1 deployment
-----------------------------------
sudo ./scripts/upgrade-orchestrator.sh --status

# Check services
systemctl status node_exporter nginx_exporter mysqld_exporter

# Test metrics
curl http://localhost:9100/metrics | head -20


Step 5: Deploy Phase 2 (Prometheus) - OPTIONAL
-----------------------------------
# Run in safe mode with confirmations
sudo ./scripts/upgrade-orchestrator.sh --phase 2 --mode safe


Step 6: Deploy Phase 3 (Logging Stack) - OPTIONAL
-----------------------------------
sudo ./scripts/upgrade-orchestrator.sh --phase 3 --mode standard


MONITORING COMMANDS
=================================

Check upgrade status:
sudo ./scripts/upgrade-orchestrator.sh --status

Watch logs in real-time:
journalctl -f

Watch specific service:
journalctl -f -u node_exporter

Check all service statuses:
for svc in node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter; do
    echo -n "$svc: "
    systemctl is-active $svc
done


TROUBLESHOOTING COMMANDS
=================================

If deployment fails:
sudo ./scripts/upgrade-orchestrator.sh --resume

To rollback:
sudo ./scripts/upgrade-orchestrator.sh --rollback

Check specific service logs:
journalctl -u node_exporter -n 50 --no-pager

Verify network connectivity:
curl -I https://github.com
curl -s https://api.github.com/zen

Check disk space:
df -h /var/lib


ADVANCED OPTIONS
=================================

Deploy specific component only:
sudo ./scripts/upgrade-orchestrator.sh --component node_exporter

Force re-deployment:
sudo ./scripts/upgrade-orchestrator.sh --component node_exporter --force

Deploy all phases at once (not recommended):
sudo ./scripts/upgrade-orchestrator.sh --all --dry-run
sudo ./scripts/upgrade-orchestrator.sh --all

Fast mode (minimal pauses):
sudo ./scripts/upgrade-orchestrator.sh --phase 1 --mode fast

Safe mode (maximum safety):
sudo ./scripts/upgrade-orchestrator.sh --phase 1 --mode safe


VALIDATION COMMANDS
=================================

Pre-flight check:
sudo ./scripts/preflight-check.sh --observability-vps

Verify configuration files:
python3 -c "import yaml; yaml.safe_load(open('config/upgrade.yaml'))"

Check port availability:
for port in 9100 9113 9104 9253 9191 9090 3100 9080; do
    echo -n "Port $port: "
    sudo ss -tln | grep -q ":$port " && echo "IN USE" || echo "AVAILABLE"
done


POST-DEPLOYMENT VALIDATION
=================================

Run Phase 1 post-validation tests:
sudo ./tests/phase1-post-validation.sh

Check Prometheus targets (after Phase 2):
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[].health'

Verify Prometheus config:
promtool check config /etc/prometheus/prometheus.yml


BACKUP AND RECOVERY
=================================

List available backups:
sudo ls -lh /var/lib/observability-upgrades/backups/

View upgrade history:
sudo cat /var/lib/observability-upgrades/state.json | jq '.'

Manual backup before deployment:
BACKUP="/tmp/manual-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
sudo cp -r config "$BACKUP/"


DOCUMENTATION REFERENCES
=================================

Detailed validation report:
/home/calounx/repositories/mentat/observability-stack/PRE_UPGRADE_VALIDATION_REPORT.md

Quick start guide:
/home/calounx/repositories/mentat/observability-stack/QUICK_START_GUIDE.md

Phase 1 execution plan:
/home/calounx/repositories/mentat/observability-stack/docs/PHASE_1_EXECUTION_PLAN.md

Architecture review:
/home/calounx/repositories/mentat/observability-stack/ARCHITECTURE_REVIEW.md


=================================
END OF DEPLOYMENT COMMANDS
=================================

EOF

echo ""
echo "Helper functions loaded. Available commands:"
echo "  show_status       - Show current upgrade status"
echo "  run_dry_run [N]   - Run dry-run for phase N (default: 1)"
echo "  deploy_phase1     - Deploy Phase 1 exporters"
echo "  deploy_phase2     - Deploy Phase 2 Prometheus"
echo "  deploy_phase3     - Deploy Phase 3 logging stack"
echo "  verify_services   - Check all service statuses"
echo "  test_endpoints    - Test all metrics endpoints"
echo "  rollback_upgrade  - Rollback last upgrade"
echo "  resume_upgrade    - Resume failed upgrade"
echo ""
echo "To use these functions, source this file:"
echo "  source /home/calounx/repositories/mentat/observability-stack/DEPLOYMENT_COMMANDS.sh"
echo ""
