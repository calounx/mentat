#!/bin/bash
# ============================================================================
# CHOM Test Environment Setup Script
# ============================================================================
# Sets up the two-node test environment:
#   - mentat_tst: Observability stack + CHOM Laravel application (Docker)
#   - landsraad_tst: Managed VPS target for site provisioning
#
# Usage:
#   ./setup-test-environment.sh [--local|--remote]
#
# Options:
#   --local   Set up only the local Docker environment (mentat_tst)
#   --remote  Also deploy to landsraad_tst via SSH
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$DOCKER_DIR")"

# Test environment settings
MENTAT_TST_IP="${MENTAT_TST_IP:-10.10.100.10}"
LANDSRAAD_TST_IP="${LANDSRAAD_TST_IP:-10.10.100.20}"
SSH_USER="${SSH_USER:-deploy}"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing=()

    # Check for required tools
    command -v docker &>/dev/null || missing+=("docker")
    command -v docker-compose &>/dev/null || missing+=("docker-compose")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        log_error "Please install them before running this script."
        exit 1
    fi

    # Check Docker daemon
    if ! docker info &>/dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# ============================================================================
# ENVIRONMENT SETUP
# ============================================================================

setup_environment() {
    log_info "Setting up test environment configuration..."

    cd "$DOCKER_DIR"

    # Copy test environment file if .env doesn't exist
    if [[ ! -f .env ]]; then
        if [[ -f .env.test ]]; then
            cp .env.test .env
            log_success "Created .env from .env.test"
        elif [[ -f .env.example ]]; then
            cp .env.example .env
            log_warn "Created .env from .env.example - please review settings"
        else
            log_error "No environment template found"
            exit 1
        fi
    else
        log_info ".env already exists, using existing configuration"
    fi

    # Generate APP_KEY if not set
    if grep -q "APP_KEY=base64:TEST_KEY" .env 2>/dev/null || grep -q "APP_KEY=$" .env 2>/dev/null; then
        log_info "Generating Laravel APP_KEY..."
        NEW_KEY=$(openssl rand -base64 32)
        sed -i "s|APP_KEY=.*|APP_KEY=base64:${NEW_KEY}|" .env
        log_success "Generated new APP_KEY"
    fi
}

# ============================================================================
# DOCKER BUILD AND START
# ============================================================================

build_containers() {
    log_info "Building Docker containers..."

    cd "$DOCKER_DIR"

    # Build with progress output
    docker-compose build --progress=plain

    log_success "Docker containers built successfully"
}

start_containers() {
    log_info "Starting Docker containers..."

    cd "$DOCKER_DIR"

    # Start in detached mode
    docker-compose up -d

    log_success "Docker containers started"
}

wait_for_services() {
    log_info "Waiting for services to become healthy..."

    local max_wait=120
    local waited=0

    while [[ $waited -lt $max_wait ]]; do
        # Check if all containers are healthy
        local unhealthy=$(docker-compose ps | grep -E "(unhealthy|starting)" | wc -l)

        if [[ $unhealthy -eq 0 ]]; then
            log_success "All services are healthy"
            return 0
        fi

        sleep 5
        waited=$((waited + 5))

        if [[ $((waited % 30)) -eq 0 ]]; then
            log_info "Still waiting for services... (${waited}s elapsed)"
            docker-compose ps
        fi
    done

    log_warn "Some services may not be fully healthy yet"
    docker-compose ps
}

# ============================================================================
# LARAVEL INITIALIZATION
# ============================================================================

init_laravel() {
    log_info "Initializing Laravel application..."

    cd "$DOCKER_DIR"

    # Wait for MySQL to be ready
    log_info "Waiting for MySQL to be ready..."
    local retries=30
    while [[ $retries -gt 0 ]]; do
        if docker-compose exec -T web mysqladmin ping -h 127.0.0.1 -u root -proot_test_secret &>/dev/null; then
            log_success "MySQL is ready"
            break
        fi
        retries=$((retries - 1))
        sleep 2
    done

    if [[ $retries -eq 0 ]]; then
        log_error "MySQL failed to become ready"
        exit 1
    fi

    # Run migrations
    log_info "Running database migrations..."
    docker-compose exec -T web php /var/www/chom/artisan migrate --force

    # Seed database with test data
    log_info "Seeding database with test data..."
    docker-compose exec -T web php /var/www/chom/artisan db:seed --class=TestDataSeeder --force || true

    # Clear and cache config
    log_info "Optimizing Laravel..."
    docker-compose exec -T web php /var/www/chom/artisan config:cache
    docker-compose exec -T web php /var/www/chom/artisan route:cache
    docker-compose exec -T web php /var/www/chom/artisan view:cache

    log_success "Laravel application initialized"
}

# ============================================================================
# REMOTE VPS SETUP (landsraad_tst)
# ============================================================================

setup_remote_vps() {
    log_info "Setting up remote VPS (landsraad_tst)..."

    # Check SSH connectivity
    if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "${SSH_USER}@${LANDSRAAD_TST_IP}" exit 2>/dev/null; then
        log_error "Cannot connect to landsraad_tst at ${LANDSRAAD_TST_IP}"
        log_error "Please ensure SSH access is configured"
        return 1
    fi

    log_success "SSH connectivity to landsraad_tst confirmed"

    # Copy VPS setup script
    log_info "Copying VPS setup script..."
    scp "${PROJECT_ROOT}/chom/deploy/scripts/setup-vpsmanager-vps.sh" \
        "${SSH_USER}@${LANDSRAAD_TST_IP}:/tmp/"
    scp "${PROJECT_ROOT}/chom/deploy/lib/deploy-common.sh" \
        "${SSH_USER}@${LANDSRAAD_TST_IP}:/tmp/"

    # Run VPS setup script
    log_info "Running VPS setup on landsraad_tst..."
    ssh "${SSH_USER}@${LANDSRAAD_TST_IP}" "
        sudo mkdir -p /opt/chom/deploy/lib
        sudo mv /tmp/deploy-common.sh /opt/chom/deploy/lib/
        sudo mv /tmp/setup-vpsmanager-vps.sh /opt/chom/deploy/scripts/
        cd /opt/chom/deploy/scripts
        sudo OBSERVABILITY_IP=${MENTAT_TST_IP} DOMAIN=landsraad.test bash setup-vpsmanager-vps.sh
    "

    log_success "landsraad_tst VPS setup complete"
}

# ============================================================================
# PROMETHEUS TARGET CONFIGURATION
# ============================================================================

configure_prometheus_targets() {
    log_info "Configuring Prometheus scrape targets..."

    cd "$DOCKER_DIR"

    # Add landsraad_tst as a scrape target
    cat >> observability/prometheus/prometheus.yml << EOF

  # landsraad_tst - Managed VPS
  - job_name: 'landsraad_tst'
    static_configs:
      - targets: ['${LANDSRAAD_TST_IP}:9100']
        labels:
          node: 'landsraad_tst'
          role: 'vps'
          environment: 'test'

  - job_name: 'landsraad_tst_nginx'
    static_configs:
      - targets: ['${LANDSRAAD_TST_IP}:9113']
        labels:
          node: 'landsraad_tst'

  - job_name: 'landsraad_tst_mysql'
    static_configs:
      - targets: ['${LANDSRAAD_TST_IP}:9104']
        labels:
          node: 'landsraad_tst'

  - job_name: 'landsraad_tst_phpfpm'
    static_configs:
      - targets: ['${LANDSRAAD_TST_IP}:9253']
        labels:
          node: 'landsraad_tst'
EOF

    # Reload Prometheus configuration
    docker-compose exec -T observability curl -X POST http://localhost:9090/-/reload 2>/dev/null || \
        docker-compose restart observability

    log_success "Prometheus targets configured"
}

# ============================================================================
# HEALTH CHECK
# ============================================================================

run_health_check() {
    log_info "Running health checks..."

    echo ""
    echo "=========================================="
    echo "  Service Health Check"
    echo "=========================================="

    # Web application
    echo -n "  Web Application (Nginx):  "
    if curl -sf http://localhost:8000/health &>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
    fi

    # PHP-FPM
    echo -n "  PHP-FPM:                  "
    if curl -sf http://localhost:8000/fpm-ping &>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
    fi

    # Prometheus
    echo -n "  Prometheus:               "
    if curl -sf http://localhost:9090/-/healthy &>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
    fi

    # Loki
    echo -n "  Loki:                     "
    if curl -sf http://localhost:3100/ready &>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
    fi

    # Grafana
    echo -n "  Grafana:                  "
    if curl -sf http://localhost:3000/api/health &>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
    fi

    # Alertmanager
    echo -n "  Alertmanager:             "
    if curl -sf http://localhost:9093/-/healthy &>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
    fi

    echo "=========================================="
}

# ============================================================================
# SUMMARY
# ============================================================================

print_summary() {
    echo ""
    echo "=========================================="
    echo "  Test Environment Ready!"
    echo "=========================================="
    echo ""
    echo "Node: mentat_tst (Debian 13)"
    echo ""
    echo "Access URLs:"
    echo "  - CHOM Application:  http://localhost:8000"
    echo "  - Grafana:           http://localhost:3000 (admin/admin_test_secret)"
    echo "  - Prometheus:        http://localhost:9090"
    echo "  - Loki:              http://localhost:3100"
    echo "  - Alertmanager:      http://localhost:9093"
    echo ""
    echo "Database:"
    echo "  - Host:     localhost:3306"
    echo "  - Database: chom_test"
    echo "  - User:     chom_test"
    echo ""
    echo "Useful Commands:"
    echo "  make logs          # View all logs"
    echo "  make logs-web      # View web app logs"
    echo "  make shell-web     # Shell into web container"
    echo "  make test          # Run Laravel tests"
    echo "  make migrate       # Run migrations"
    echo ""

    if [[ "${SETUP_REMOTE:-false}" == "true" ]]; then
        echo "Remote VPS (landsraad_tst):"
        echo "  - IP:               ${LANDSRAAD_TST_IP}"
        echo "  - Node Exporter:    http://${LANDSRAAD_TST_IP}:9100"
        echo "  - Dashboard:        http://${LANDSRAAD_TST_IP}:8080"
        echo ""
    fi

    echo "=========================================="
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local setup_remote=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --remote)
                setup_remote=true
                shift
                ;;
            --local)
                setup_remote=false
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    export SETUP_REMOTE=$setup_remote

    echo ""
    echo "=========================================="
    echo "  CHOM Test Environment Setup"
    echo "=========================================="
    echo "  mentat_tst:   Observability + CHOM"
    echo "  landsraad_tst: Managed VPS target"
    echo "=========================================="
    echo ""

    check_prerequisites
    setup_environment
    build_containers
    start_containers
    wait_for_services
    init_laravel

    if [[ "$setup_remote" == "true" ]]; then
        setup_remote_vps
        configure_prometheus_targets
    fi

    run_health_check
    print_summary

    log_success "Test environment setup complete!"
}

main "$@"
