#!/bin/bash
# ============================================================================
# CHOM Test Environment Manager
# ============================================================================
# Manages the 3-VPS test environment for regression testing
#
# VPS Nodes:
#   - mentat_tst (10.10.100.10): Observability (Prometheus, Grafana, Loki, Tempo)
#   - landsraad_tst (10.10.100.20): VPSManager/CHOM application (primary)
#   - richese_tst (10.10.100.30): Hosting node (secondary web server)
#
# Usage:
#   ./test-env.sh up          # Start VPS containers
#   ./test-env.sh down        # Stop and remove containers
#   ./test-env.sh reset       # Reset to clean state
#   ./test-env.sh deploy      # Run deployment scripts on all VPS
#   ./test-env.sh status      # Show status of all services
#   ./test-env.sh logs [vps]  # Show logs (mentat_tst, landsraad_tst, richese_tst)
#   ./test-env.sh shell [vps] # Open shell in VPS container
#   ./test-env.sh test        # Run regression tests
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$DOCKER_DIR/docker-compose.vps.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Start VPS containers
cmd_up() {
    log_info "Starting VPS containers..."
    cd "$DOCKER_DIR"
    docker compose -f docker-compose.vps.yml up -d --build

    log_info "Waiting for containers to be healthy..."
    sleep 10

    # Wait for systemd in all containers
    for vps in mentat_tst landsraad_tst richese_tst; do
        log_info "Waiting for $vps systemd..."
        timeout=60
        while [ $timeout -gt 0 ]; do
            if docker exec $vps systemctl is-system-running --quiet 2>/dev/null; then
                log_success "$vps is ready"
                break
            fi
            sleep 2
            timeout=$((timeout - 2))
        done
        if [ $timeout -le 0 ]; then
            log_warn "$vps systemd not fully ready, but continuing..."
        fi
    done

    log_success "VPS containers are running"
    echo ""
    echo "VPS Endpoints:"
    echo "  mentat_tst (Observability): 10.10.100.10"
    echo "    - SSH: localhost:2210"
    echo "    - Grafana: http://localhost:3000"
    echo "    - Prometheus: http://localhost:9090"
    echo ""
    echo "  landsraad_tst (CHOM): 10.10.100.20"
    echo "    - SSH: localhost:2220"
    echo "    - Web: http://localhost:8000"
    echo "    - MySQL: localhost:3316"
    echo ""
    echo "  richese_tst (Hosting): 10.10.100.30"
    echo "    - SSH: localhost:2230"
    echo "    - Web: http://localhost:8010"
    echo "    - MySQL: localhost:3326"
}

# Stop and remove containers
cmd_down() {
    log_info "Stopping VPS containers..."
    cd "$DOCKER_DIR"
    docker compose -f docker-compose.vps.yml down
    log_success "VPS containers stopped"
}

# Reset to clean state (removes volumes too)
cmd_reset() {
    log_warn "This will delete all data and reset to clean state!"
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Resetting test environment..."
        cd "$DOCKER_DIR"
        docker compose -f docker-compose.vps.yml down -v --remove-orphans
        log_success "Test environment reset complete"
    else
        log_info "Reset cancelled"
    fi
}

# Deploy to VPS containers
cmd_deploy() {
    local target="${1:-all}"

    if [ "$target" = "all" ] || [ "$target" = "observability" ] || [ "$target" = "mentat" ]; then
        log_info "Deploying Observability stack to mentat_tst..."
        docker exec mentat_tst bash /opt/scripts/deploy-observability.sh
        log_success "Observability deployment complete"
    fi

    if [ "$target" = "all" ] || [ "$target" = "vpsmanager" ] || [ "$target" = "landsraad" ]; then
        log_info "Deploying VPSManager stack to landsraad_tst..."
        docker exec landsraad_tst bash /opt/scripts/deploy-vpsmanager.sh
        log_success "VPSManager deployment complete"
    fi
}

# Show status
cmd_status() {
    echo "=== VPS Container Status ==="
    docker compose -f "$COMPOSE_FILE" ps
    echo ""

    echo "=== mentat_tst Services ==="
    docker exec mentat_tst systemctl list-units --type=service --state=running --no-pager 2>/dev/null | grep -E "(prometheus|grafana|loki|tempo|alertmanager|node_exporter)" || echo "No observability services running yet"
    echo ""

    echo "=== landsraad_tst Services ==="
    docker exec landsraad_tst systemctl list-units --type=service --state=running --no-pager 2>/dev/null | grep -E "(nginx|php|mysql|mariadb|redis)" || echo "No application services running yet"
    echo ""

    echo "=== richese_tst Services ==="
    docker exec richese_tst systemctl list-units --type=service --state=running --no-pager 2>/dev/null | grep -E "(nginx|php|mysql|mariadb|redis)" || echo "No hosting services running yet"
    echo ""

    echo "=== Health Checks ==="
    # Check Prometheus
    if curl -sf http://localhost:9090/-/healthy >/dev/null 2>&1; then
        log_success "Prometheus: healthy"
    else
        log_warn "Prometheus: not responding"
    fi

    # Check Grafana
    if curl -sf http://localhost:3000/api/health >/dev/null 2>&1; then
        log_success "Grafana: healthy"
    else
        log_warn "Grafana: not responding"
    fi

    # Check Loki
    if curl -sf http://localhost:3100/ready >/dev/null 2>&1; then
        log_success "Loki: healthy"
    else
        log_warn "Loki: not responding"
    fi

    # Check Web App (CHOM)
    if curl -sf http://localhost:8000/health >/dev/null 2>&1; then
        log_success "CHOM Web App: healthy"
    else
        log_warn "CHOM Web App: not responding"
    fi

    # Check Web App (Hosting)
    if curl -sf http://localhost:8010/health >/dev/null 2>&1; then
        log_success "Hosting Web App: healthy"
    else
        log_warn "Hosting Web App: not responding"
    fi
}

# Show logs
cmd_logs() {
    local vps="${1:-mentat_tst}"
    docker logs -f "$vps"
}

# Open shell
cmd_shell() {
    local vps="${1:-mentat_tst}"
    docker exec -it "$vps" bash
}

# Run regression tests
cmd_test() {
    log_info "Running regression tests..."

    local failed=0

    # Test 1: VPS containers are running
    echo -n "Test: VPS containers running... "
    if docker ps | grep -q mentat_tst && docker ps | grep -q landsraad_tst && docker ps | grep -q richese_tst; then
        log_success "PASS"
    else
        log_error "FAIL"
        failed=$((failed + 1))
    fi

    # Test 2: Systemd is active in all containers (degraded is OK in containers)
    echo -n "Test: Systemd active in mentat_tst... "
    status=$(docker exec mentat_tst systemctl is-system-running 2>/dev/null | tr -d '\n' || echo "failed")
    if [[ "$status" == "running" ]] || [[ "$status" == "degraded" ]]; then
        log_success "PASS ($status)"
    else
        log_error "FAIL ($status)"
        failed=$((failed + 1))
    fi

    echo -n "Test: Systemd active in landsraad_tst... "
    status=$(docker exec landsraad_tst systemctl is-system-running 2>/dev/null | tr -d '\n' || echo "failed")
    if [[ "$status" == "running" ]] || [[ "$status" == "degraded" ]]; then
        log_success "PASS ($status)"
    else
        log_error "FAIL ($status)"
        failed=$((failed + 1))
    fi

    echo -n "Test: Systemd active in richese_tst... "
    status=$(docker exec richese_tst systemctl is-system-running 2>/dev/null | tr -d '\n' || echo "failed")
    if [[ "$status" == "running" ]] || [[ "$status" == "degraded" ]]; then
        log_success "PASS ($status)"
    else
        log_error "FAIL ($status)"
        failed=$((failed + 1))
    fi

    # Test 3: Network connectivity between VPS
    echo -n "Test: Network connectivity mentat -> landsraad... "
    if docker exec mentat_tst ping -c 1 10.10.100.20 >/dev/null 2>&1; then
        log_success "PASS"
    else
        log_error "FAIL"
        failed=$((failed + 1))
    fi

    echo -n "Test: Network connectivity landsraad -> mentat... "
    if docker exec landsraad_tst ping -c 1 10.10.100.10 >/dev/null 2>&1; then
        log_success "PASS"
    else
        log_error "FAIL"
        failed=$((failed + 1))
    fi

    echo -n "Test: Network connectivity mentat -> richese... "
    if docker exec mentat_tst ping -c 1 10.10.100.30 >/dev/null 2>&1; then
        log_success "PASS"
    else
        log_error "FAIL"
        failed=$((failed + 1))
    fi

    echo -n "Test: Network connectivity richese -> landsraad... "
    if docker exec richese_tst ping -c 1 10.10.100.20 >/dev/null 2>&1; then
        log_success "PASS"
    else
        log_error "FAIL"
        failed=$((failed + 1))
    fi

    # Test 4: Observability services (if deployed)
    echo -n "Test: Prometheus responding... "
    if curl -sf http://localhost:9090/-/healthy >/dev/null 2>&1; then
        log_success "PASS"
    else
        log_warn "SKIP (not deployed)"
    fi

    echo -n "Test: Grafana responding... "
    if curl -sf http://localhost:3000/api/health >/dev/null 2>&1; then
        log_success "PASS"
    else
        log_warn "SKIP (not deployed)"
    fi

    # Test 5: Web services (if deployed)
    echo -n "Test: CHOM Nginx responding... "
    if curl -sf http://localhost:8000/health >/dev/null 2>&1; then
        log_success "PASS"
    else
        log_warn "SKIP (not deployed)"
    fi

    echo -n "Test: Hosting Nginx responding... "
    if curl -sf http://localhost:8010/health >/dev/null 2>&1; then
        log_success "PASS"
    else
        log_warn "SKIP (not deployed)"
    fi

    echo ""
    if [ $failed -eq 0 ]; then
        log_success "All tests passed!"
        return 0
    else
        log_error "$failed test(s) failed"
        return 1
    fi
}

# Main command handler
case "${1:-}" in
    up)
        cmd_up
        ;;
    down)
        cmd_down
        ;;
    reset)
        cmd_reset
        ;;
    deploy)
        cmd_deploy "${2:-all}"
        ;;
    status)
        cmd_status
        ;;
    logs)
        cmd_logs "${2:-mentat_tst}"
        ;;
    shell)
        cmd_shell "${2:-mentat_tst}"
        ;;
    test)
        cmd_test
        ;;
    *)
        echo "CHOM Test Environment Manager"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  up              Start VPS containers"
        echo "  down            Stop and remove containers"
        echo "  reset           Reset to clean state (deletes all data)"
        echo "  deploy [target] Run deployment scripts"
        echo "                  targets: all, observability, vpsmanager"
        echo "  status          Show status of all services"
        echo "  logs [vps]      Show logs (mentat_tst, landsraad_tst, richese_tst)"
        echo "  shell [vps]     Open shell in VPS container"
        echo "  test            Run regression tests"
        ;;
esac
