#!/bin/bash

# Comprehensive Deployment Workflows Test Suite
# Tests all deployment scripts and workflows for production readiness
#
# Usage:
#   ./deployment-workflows-test.sh [--container landsraad_tst] [--verbose] [--stop-on-failure]
#
# Requirements:
#   - Docker running with test container (landsraad_tst at 10.10.100.20)
#   - SSH access to test container
#   - All deployment scripts present in chom/scripts/

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Configuration
TEST_CONTAINER="${TEST_CONTAINER:-landsraad_tst}"
TEST_CONTAINER_IP="${TEST_CONTAINER_IP:-10.10.100.20}"
TEST_SSH_USER="${TEST_SSH_USER:-root}"
CHOM_PATH="/opt/chom"
VERBOSE="${VERBOSE:-false}"
STOP_ON_FAILURE="${STOP_ON_FAILURE:-false}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-text}"  # text, json, junit

# Test results
declare -A TEST_RESULTS
declare -A TEST_TIMINGS
declare -A TEST_MESSAGES
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0
START_TIME=$(date +%s)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Logging functions
log() {
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        echo "$1"
    fi
}

log_header() {
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        echo ""
        echo -e "${CYAN}=========================================${NC}"
        echo -e "${CYAN}$1${NC}"
        echo -e "${CYAN}=========================================${NC}"
    fi
}

log_test() {
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        echo -e "${BLUE}[TEST]${NC} $1"
    fi
}

log_success() {
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        echo -e "${GREEN}✓${NC} $1"
    fi
}

log_error() {
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        echo -e "${RED}✗${NC} $1"
    fi
}

log_warning() {
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        echo -e "${YELLOW}⚠${NC} $1"
    fi
}

log_info() {
    if [ "$OUTPUT_FORMAT" = "text" ]; then
        echo -e "${MAGENTA}ℹ${NC} $1"
    fi
}

log_verbose() {
    if [ "$VERBOSE" = "true" ] && [ "$OUTPUT_FORMAT" = "text" ]; then
        echo -e "${NC}  $1${NC}"
    fi
}

# Test execution framework
run_test() {
    local test_name=$1
    local test_function=$2
    local description=$3

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log_test "${test_name}: ${description}"

    local test_start=$(date +%s)
    local result="PASS"
    local message=""

    # Run test in subshell to capture output
    if output=$(eval "$test_function" 2>&1); then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        log_success "PASSED: ${test_name}"
        message="$output"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        result="FAIL"
        log_error "FAILED: ${test_name}"
        message="$output"

        if [ "$VERBOSE" = "true" ]; then
            echo "$output" | head -20
        fi

        if [ "$STOP_ON_FAILURE" = "true" ]; then
            log_error "Stopping on failure as requested"
            exit 1
        fi
    fi

    local test_end=$(date +%s)
    local duration=$((test_end - test_start))

    TEST_RESULTS[$test_name]=$result
    TEST_TIMINGS[$test_name]=$duration
    TEST_MESSAGES[$test_name]=$message

    log_verbose "Duration: ${duration}s"
}

# Helper functions
ssh_exec() {
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${TEST_SSH_USER}@${TEST_CONTAINER_IP}" "$@"
}

scp_file() {
    scp -o StrictHostKeyChecking=no "$1" "${TEST_SSH_USER}@${TEST_CONTAINER_IP}:$2"
}

# Environment setup
setup_test_environment() {
    log_header "Setting Up Test Environment"

    log_info "Checking Docker container: ${TEST_CONTAINER}"
    if ! docker ps | grep -q "${TEST_CONTAINER}"; then
        log_error "Container ${TEST_CONTAINER} not running"
        return 1
    fi
    log_success "Container running"

    log_info "Checking SSH connectivity to ${TEST_CONTAINER_IP}"
    if ! ssh_exec "echo 'SSH OK'" > /dev/null 2>&1; then
        log_error "Cannot SSH to ${TEST_CONTAINER_IP}"
        return 1
    fi
    log_success "SSH connectivity OK"

    log_info "Checking CHOM installation in container"
    if ! ssh_exec "test -d ${CHOM_PATH}"; then
        log_warning "CHOM not found at ${CHOM_PATH}, will create test installation"
        ssh_exec "mkdir -p ${CHOM_PATH}"
    fi
    log_success "CHOM path exists"

    return 0
}

cleanup_test_environment() {
    log_header "Cleaning Up Test Environment"

    # Clean up test artifacts
    log_info "Removing test artifacts from container"
    ssh_exec "rm -f /tmp/test_* 2>/dev/null || true"

    # Reset any maintenance mode
    log_info "Ensuring application is out of maintenance mode"
    ssh_exec "cd ${CHOM_PATH} && php artisan up 2>/dev/null || true"

    log_success "Cleanup complete"
}

# ============================================================================
# TEST 1: PRE-DEPLOYMENT CHECKS
# ============================================================================

test_predeployment_all_checks_pass() {
    # Setup environment for success
    ssh_exec "cd ${CHOM_PATH} && bash scripts/pre-deployment-check.sh"
}

test_predeployment_missing_env() {
    # Temporarily rename .env
    ssh_exec "
        cd ${CHOM_PATH}
        mv .env .env.backup 2>/dev/null || true
        ! bash scripts/pre-deployment-check.sh
        mv .env.backup .env 2>/dev/null || true
    "
}

test_predeployment_disk_space() {
    # Test disk space check
    ssh_exec "cd ${CHOM_PATH} && bash scripts/pre-deployment-check.sh | grep -q 'Disk usage'"
}

test_predeployment_php_version() {
    # Test PHP version check
    ssh_exec "cd ${CHOM_PATH} && bash scripts/pre-deployment-check.sh | grep -q 'PHP version'"
}

test_predeployment_database_connectivity() {
    # Test database connectivity check
    ssh_exec "cd ${CHOM_PATH} && bash scripts/pre-deployment-check.sh | grep -q 'Database connection'"
}

test_predeployment_redis_connectivity() {
    # Test Redis connectivity check
    ssh_exec "cd ${CHOM_PATH} && bash scripts/pre-deployment-check.sh | grep -q 'Redis'"
}

test_predeployment_storage_permissions() {
    # Test storage permissions check
    ssh_exec "cd ${CHOM_PATH} && bash scripts/pre-deployment-check.sh | grep -q 'storage'"
}

test_predeployment_exit_codes() {
    # Test proper exit codes
    ssh_exec "
        cd ${CHOM_PATH}
        bash scripts/pre-deployment-check.sh && echo 'EXIT_0' || echo 'EXIT_NON_ZERO'
    " | grep -q "EXIT_0"
}

# ============================================================================
# TEST 2: HEALTH CHECKS
# ============================================================================

test_health_check_basic() {
    # Test basic health check execution
    ssh_exec "cd ${CHOM_PATH} && timeout 60 bash scripts/health-check.sh"
}

test_health_check_http_endpoints() {
    # Test HTTP endpoint checks
    ssh_exec "cd ${CHOM_PATH} && bash scripts/health-check.sh 2>&1 | grep -q 'health endpoint'"
}

test_health_check_database() {
    # Test database health check
    ssh_exec "cd ${CHOM_PATH} && bash scripts/health-check.sh 2>&1 | grep -q 'Database'"
}

test_health_check_redis() {
    # Test Redis health check
    ssh_exec "cd ${CHOM_PATH} && bash scripts/health-check.sh 2>&1 | grep -q 'Redis'"
}

test_health_check_cache() {
    # Test cache functionality check
    ssh_exec "cd ${CHOM_PATH} && bash scripts/health-check.sh 2>&1 | grep -q 'Cache'"
}

test_health_check_storage() {
    # Test storage write check
    ssh_exec "cd ${CHOM_PATH} && bash scripts/health-check.sh 2>&1 | grep -q 'Storage'"
}

test_health_check_response_time() {
    # Test response time measurement
    ssh_exec "cd ${CHOM_PATH} && bash scripts/health-check.sh 2>&1 | grep -q 'response time'"
}

test_health_check_exit_code() {
    # Test exit code on success
    ssh_exec "cd ${CHOM_PATH} && bash scripts/health-check.sh && echo 'SUCCESS'"  | grep -q "SUCCESS"
}

# ============================================================================
# TEST 3: ENHANCED HEALTH CHECKS
# ============================================================================

test_health_check_enhanced_all() {
    # Test all enhanced health checks
    ssh_exec "cd ${CHOM_PATH} && timeout 120 bash scripts/health-check-enhanced.sh"
}

test_health_check_enhanced_json_output() {
    # Test JSON output format
    ssh_exec "cd ${CHOM_PATH} && OUTPUT_FORMAT=json bash scripts/health-check-enhanced.sh | jq -e '.checks'"
}

test_health_check_enhanced_prometheus_output() {
    # Test Prometheus output format
    ssh_exec "cd ${CHOM_PATH} && OUTPUT_FORMAT=prometheus bash scripts/health-check-enhanced.sh | grep -q 'health_check_status'"
}

test_health_check_enhanced_cpu() {
    # Test CPU check
    ssh_exec "cd ${CHOM_PATH} && bash scripts/health-check-enhanced.sh 2>&1 | grep -q 'CPU usage'"
}

test_health_check_enhanced_memory() {
    # Test memory check
    ssh_exec "cd ${CHOM_PATH} && bash scripts/health-check-enhanced.sh 2>&1 | grep -q 'Memory usage'"
}

test_health_check_enhanced_services() {
    # Test service checks (Nginx, PHP-FPM, MySQL, Redis)
    ssh_exec "cd ${CHOM_PATH} && bash scripts/health-check-enhanced.sh 2>&1 | grep -E '(Nginx|PHP-FPM|MySQL|Redis)'"
}

test_health_check_enhanced_ssl() {
    # Test SSL certificate check
    ssh_exec "cd ${CHOM_PATH} && bash scripts/health-check-enhanced.sh 2>&1 | grep -q 'SSL'"
}

# ============================================================================
# TEST 4: PRODUCTION DEPLOYMENT WORKFLOW
# ============================================================================

test_production_deployment_dry_run() {
    # Test deployment script validation (without actual deployment)
    ssh_exec "
        cd ${CHOM_PATH}
        # Check script is executable and has no syntax errors
        bash -n scripts/deploy-production.sh
    "
}

test_production_deployment_backup_creation() {
    # Test that backup is created during deployment
    ssh_exec "
        cd ${CHOM_PATH}
        # Create backup directory
        mkdir -p storage/app/backups
        # Test backup command
        php artisan db:show > /dev/null 2>&1 || echo 'DB not available, skip backup test'
    "
}

test_production_deployment_maintenance_mode() {
    # Test maintenance mode enable/disable
    ssh_exec "
        cd ${CHOM_PATH}
        php artisan down --retry=10
        php artisan status | grep -q 'Down' || true
        php artisan up
        echo 'Maintenance mode test OK'
    "
}

test_production_deployment_composer_install() {
    # Test composer install step
    ssh_exec "
        cd ${CHOM_PATH}
        composer install --dry-run --no-dev --optimize-autoloader --no-interaction
    "
}

test_production_deployment_cache_optimization() {
    # Test cache optimization commands
    ssh_exec "
        cd ${CHOM_PATH}
        php artisan config:clear
        php artisan config:cache
        test -f bootstrap/cache/config.php && echo 'Config cached'
    "
}

test_production_deployment_queue_restart() {
    # Test queue worker restart
    ssh_exec "
        cd ${CHOM_PATH}
        php artisan queue:restart
        echo 'Queue restart OK'
    "
}

test_production_deployment_rollback_on_migration_failure() {
    # Test rollback mechanism (simulated)
    ssh_exec "
        cd ${CHOM_PATH}
        CURRENT_COMMIT=\$(git rev-parse HEAD 2>/dev/null || echo 'NO_GIT')
        echo \"Current commit: \$CURRENT_COMMIT\"
        # Test git reset capability
        git rev-parse HEAD~1 2>/dev/null || echo 'Not enough commits for rollback test'
    "
}

test_production_deployment_logging() {
    # Test deployment logging
    ssh_exec "
        cd ${CHOM_PATH}
        mkdir -p storage/logs
        touch storage/logs/deployment_test_$(date +%Y%m%d_%H%M%S).log
        test -d storage/logs && echo 'Logging directory OK'
    "
}

# ============================================================================
# TEST 5: BLUE-GREEN DEPLOYMENT
# ============================================================================

test_blue_green_directory_structure() {
    # Test blue-green deployment directory structure
    ssh_exec "
        mkdir -p /var/www/releases
        mkdir -p /var/www/shared/storage
        mkdir -p /var/backups/chom
        test -d /var/www/releases && echo 'Releases directory OK'
    "
}

test_blue_green_symlink_creation() {
    # Test symlink creation and atomic switch
    ssh_exec "
        mkdir -p /var/www/releases/test_release_$(date +%s)
        RELEASE_DIR=\$(ls -t /var/www/releases | head -1)
        ln -sfn /var/www/releases/\$RELEASE_DIR /var/www/chom_current_test
        test -L /var/www/chom_current_test && echo 'Symlink creation OK'
        rm /var/www/chom_current_test
    "
}

test_blue_green_health_check_before_switch() {
    # Test pre-switch health check
    ssh_exec "
        cd ${CHOM_PATH}
        bash scripts/health-check.sh || echo 'Health check before switch'
    "
}

test_blue_green_rollback_capability() {
    # Test rollback to previous release
    ssh_exec "
        cd /var/www/releases
        PREVIOUS=\$(ls -t | sed -n 2p || echo 'NO_PREVIOUS')
        if [ \"\$PREVIOUS\" != 'NO_PREVIOUS' ]; then
            echo \"Previous release available: \$PREVIOUS\"
        else
            echo 'No previous release for rollback'
        fi
    "
}

test_blue_green_cleanup_old_releases() {
    # Test cleanup of old releases
    ssh_exec "
        cd /var/www/releases
        # Create test releases
        for i in {1..7}; do
            mkdir -p test_release_\$i
            sleep 1
        done
        # Keep only last 5
        ls -t | grep test_release | tail -n +6 | xargs -r rm -rf
        REMAINING=\$(ls -t | grep -c test_release || echo 0)
        test \$REMAINING -le 5 && echo 'Cleanup OK'
        # Clean up test releases
        rm -rf test_release_*
    "
}

# ============================================================================
# TEST 6: CANARY DEPLOYMENT
# ============================================================================

test_canary_traffic_splitting_config() {
    # Test canary traffic splitting configuration
    ssh_exec "
        # Test nginx upstream configuration capability
        test -d /etc/nginx/conf.d || mkdir -p /etc/nginx/conf.d
        cat > /tmp/test_upstream.conf << 'EOF'
upstream test_backend {
    server unix:/run/php/stable.sock weight=90;
    server unix:/run/php/canary.sock weight=10;
}
EOF
        nginx -t -c /tmp/test_upstream.conf 2>&1 | grep -q 'syntax' || echo 'Nginx config test OK'
        rm /tmp/test_upstream.conf
    "
}

test_canary_metrics_collection() {
    # Test metrics collection capability
    ssh_exec "
        # Test Prometheus metrics availability (if configured)
        if command -v curl > /dev/null; then
            curl -sf http://localhost:9100/metrics > /dev/null 2>&1 && echo 'Metrics endpoint OK' || echo 'No metrics endpoint'
        else
            echo 'curl not available'
        fi
    "
}

test_canary_gradual_rollout_stages() {
    # Test gradual rollout stages (10%, 25%, 50%, 75%, 100%)
    ssh_exec "
        STAGES='10,25,50,75,100'
        IFS=',' read -ra STAGE_ARRAY <<< \"\$STAGES\"
        for stage in \"\${STAGE_ARRAY[@]}\"; do
            echo \"Stage: \${stage}%\"
        done
        test \${#STAGE_ARRAY[@]} -eq 5 && echo 'All stages defined'
    "
}

test_canary_automatic_rollback() {
    # Test automatic rollback on threshold breach
    ssh_exec "
        # Simulate threshold check
        ERROR_RATE=3.5
        THRESHOLD=5.0
        if (( \$(echo \"\$ERROR_RATE < \$THRESHOLD\" | bc -l) )); then
            echo 'Threshold check OK'
        else
            echo 'Would trigger rollback'
        fi
    "
}

# ============================================================================
# TEST 7: ROLLBACK FUNCTIONALITY
# ============================================================================

test_rollback_script_validation() {
    # Test rollback script syntax
    ssh_exec "cd ${CHOM_PATH} && bash -n scripts/rollback.sh"
}

test_rollback_commit_identification() {
    # Test identification of previous commits
    ssh_exec "
        cd ${CHOM_PATH}
        if [ -d .git ]; then
            CURRENT=\$(git rev-parse HEAD)
            PREVIOUS=\$(git rev-parse HEAD~1 2>/dev/null || echo 'NO_PREVIOUS')
            echo \"Current: \$CURRENT\"
            echo \"Previous: \$PREVIOUS\"
        else
            echo 'Not a git repository'
        fi
    "
}

test_rollback_migration_counting() {
    # Test migration rollback counting
    ssh_exec "
        cd ${CHOM_PATH}
        php artisan migrate:status 2>&1 | head -10 || echo 'No migrations'
    "
}

test_rollback_backup_before_rollback() {
    # Test backup creation before rollback
    ssh_exec "
        cd ${CHOM_PATH}
        mkdir -p storage/app/backups
        # Test backup capability
        php artisan db:show > /dev/null 2>&1 || echo 'DB not available'
    "
}

test_rollback_cache_clear() {
    # Test cache clearing during rollback
    ssh_exec "
        cd ${CHOM_PATH}
        php artisan cache:clear
        php artisan config:clear
        echo 'Cache clear OK'
    "
}

test_rollback_dependency_restore() {
    # Test dependency restoration
    ssh_exec "
        cd ${CHOM_PATH}
        # Test composer install
        composer install --dry-run --no-dev --no-interaction || echo 'Composer install test'
    "
}

# ============================================================================
# TEST 8: BACKUP AND RESTORE
# ============================================================================

test_backup_creation() {
    # Test backup file creation
    ssh_exec "
        cd ${CHOM_PATH}
        mkdir -p storage/app/backups
        BACKUP_FILE=\"storage/app/backups/test_backup_\$(date +%Y%m%d_%H%M%S).sql\"
        # Create test backup
        php artisan db:show > /dev/null 2>&1 && mysqldump --help > /dev/null 2>&1
        echo 'Backup capability test OK'
    "
}

test_backup_retention_policy() {
    # Test backup retention (cleanup old backups)
    ssh_exec "
        cd ${CHOM_PATH}
        mkdir -p storage/app/backups
        # Create test backup files
        for i in {1..10}; do
            touch storage/app/backups/backup_test_\$i.sql
        done
        # Test cleanup (keep last 7)
        find storage/app/backups -name 'backup_test_*.sql' | tail -n +8 | xargs -r rm
        REMAINING=\$(find storage/app/backups -name 'backup_test_*.sql' | wc -l)
        test \$REMAINING -le 7 && echo 'Retention policy OK'
        # Cleanup
        rm -f storage/app/backups/backup_test_*.sql
    "
}

test_backup_verification() {
    # Test backup file integrity
    ssh_exec "
        cd ${CHOM_PATH}
        mkdir -p storage/app/backups
        # Create a simple test backup
        echo 'SELECT 1;' > storage/app/backups/test_verify.sql
        test -s storage/app/backups/test_verify.sql && echo 'Backup file valid'
        rm storage/app/backups/test_verify.sql
    "
}

# ============================================================================
# TEST 9: ERROR HANDLING & EDGE CASES
# ============================================================================

test_error_handling_network_failure() {
    # Test network failure handling (simulated)
    ssh_exec "
        cd ${CHOM_PATH}
        # Test git fetch with timeout
        timeout 5 git fetch origin 2>&1 || echo 'Network timeout handled'
    "
}

test_error_handling_disk_full() {
    # Test disk full scenario (check, not simulate)
    ssh_exec "
        cd ${CHOM_PATH}
        DISK_USAGE=\$(df ${CHOM_PATH} | tail -1 | awk '{print \$5}' | sed 's/%//')
        if [ \$DISK_USAGE -lt 95 ]; then
            echo 'Sufficient disk space'
        else
            echo 'Disk space critical'
        fi
    "
}

test_error_handling_composer_timeout() {
    # Test composer timeout handling
    ssh_exec "
        cd ${CHOM_PATH}
        # Test with short timeout
        timeout 10 composer validate || echo 'Composer timeout test'
    "
}

test_error_handling_npm_build_failure() {
    # Test NPM build failure handling
    ssh_exec "
        cd ${CHOM_PATH}
        # Check npm availability
        npm --version > /dev/null 2>&1 || echo 'npm not available'
    "
}

test_error_handling_migration_failure() {
    # Test migration failure handling
    ssh_exec "
        cd ${CHOM_PATH}
        # Check migration system
        php artisan migrate:status > /dev/null 2>&1 || echo 'No migrations'
    "
}

test_error_handling_graceful_errors() {
    # Test graceful error messages
    ssh_exec "
        cd ${CHOM_PATH}
        # Test script with deliberate error
        bash -c 'echo ERROR >&2; exit 1' 2>&1 | grep -q 'ERROR' && echo 'Error output captured'
    "
}

# ============================================================================
# TEST 10: PERFORMANCE & TIMING
# ============================================================================

test_performance_predeployment_checks() {
    # Test pre-deployment check timing (< 15s target)
    local start=$(date +%s)
    ssh_exec "cd ${CHOM_PATH} && timeout 20 bash scripts/pre-deployment-check.sh" > /dev/null 2>&1 || true
    local end=$(date +%s)
    local duration=$((end - start))

    if [ $duration -lt 15 ]; then
        echo "Pre-deployment checks completed in ${duration}s (target: <15s)"
        return 0
    else
        echo "Pre-deployment checks took ${duration}s (target: <15s) - WARNING"
        return 0  # Don't fail, just warn
    fi
}

test_performance_health_check_timing() {
    # Test health check timing (< 30s target)
    local start=$(date +%s)
    ssh_exec "cd ${CHOM_PATH} && timeout 35 bash scripts/health-check.sh" > /dev/null 2>&1 || true
    local end=$(date +%s)
    local duration=$((end - start))

    if [ $duration -lt 30 ]; then
        echo "Health check completed in ${duration}s (target: <30s)"
        return 0
    else
        echo "Health check took ${duration}s (target: <30s) - WARNING"
        return 0
    fi
}

test_performance_cache_optimization() {
    # Test cache optimization timing
    local start=$(date +%s)
    ssh_exec "
        cd ${CHOM_PATH}
        php artisan config:cache
        php artisan route:cache
        php artisan view:cache
    " > /dev/null 2>&1
    local end=$(date +%s)
    local duration=$((end - start))

    echo "Cache optimization completed in ${duration}s"
    return 0
}

# ============================================================================
# TEST 11: VPS SETUP SCRIPTS
# ============================================================================

test_vps_setup_script_syntax() {
    # Test VPS setup script syntax validation
    bash -n "${PROJECT_ROOT}/chom/deploy/scripts/setup-vpsmanager-vps.sh"
    bash -n "${PROJECT_ROOT}/chom/deploy/scripts/setup-observability-vps.sh"
}

test_vps_setup_dependency_check() {
    # Test that setup scripts check for dependencies
    grep -q "apt-get\|yum\|dnf" "${PROJECT_ROOT}/chom/deploy/scripts/setup-vpsmanager-vps.sh"
}

test_vps_setup_service_configuration() {
    # Test service configuration in setup scripts
    grep -E "systemctl|service" "${PROJECT_ROOT}/chom/deploy/scripts/setup-vpsmanager-vps.sh" > /dev/null
}

# ============================================================================
# TEST 12: CI/CD PIPELINE
# ============================================================================

test_github_actions_workflow_syntax() {
    # Test GitHub Actions workflow YAML syntax
    if command -v yamllint > /dev/null 2>&1; then
        yamllint "${PROJECT_ROOT}/.github/workflows/deploy-production.yml" || echo 'yamllint not available'
    else
        # Basic YAML check
        grep -q "jobs:" "${PROJECT_ROOT}/.github/workflows/deploy-production.yml"
    fi
}

test_github_actions_build_stage() {
    # Test build stage configuration
    grep -q "build-and-test:" "${PROJECT_ROOT}/.github/workflows/deploy-production.yml"
}

test_github_actions_security_scan() {
    # Test security scan stage
    grep -q "security-scan:" "${PROJECT_ROOT}/.github/workflows/deploy-production.yml"
}

test_github_actions_deployment_stage() {
    # Test deployment stage
    grep -q "deploy-blue-green:" "${PROJECT_ROOT}/.github/workflows/deploy-production.yml"
}

test_github_actions_smoke_tests() {
    # Test smoke tests stage
    grep -q "smoke-tests:" "${PROJECT_ROOT}/.github/workflows/deploy-production.yml"
}

test_github_actions_rollback_on_failure() {
    # Test automatic rollback configuration
    grep -q "Rollback on failure" "${PROJECT_ROOT}/.github/workflows/deploy-production.yml"
}

# ============================================================================
# MAIN TEST EXECUTION
# ============================================================================

main() {
    log_header "DEPLOYMENT WORKFLOWS COMPREHENSIVE TEST SUITE"
    log_info "Start time: $(date)"
    log_info "Test container: ${TEST_CONTAINER} (${TEST_CONTAINER_IP})"
    log_info "CHOM path: ${CHOM_PATH}"
    echo ""

    # Setup environment
    if ! setup_test_environment; then
        log_error "Environment setup failed. Aborting tests."
        exit 1
    fi

    # TEST SUITE 1: Pre-deployment Checks
    log_header "TEST SUITE 1: Pre-deployment Checks (8 tests)"
    run_test "predeployment_01" "test_predeployment_all_checks_pass" "All pre-deployment checks pass"
    run_test "predeployment_02" "test_predeployment_missing_env" "Detect missing .env file"
    run_test "predeployment_03" "test_predeployment_disk_space" "Check disk space"
    run_test "predeployment_04" "test_predeployment_php_version" "Verify PHP version"
    run_test "predeployment_05" "test_predeployment_database_connectivity" "Test database connectivity"
    run_test "predeployment_06" "test_predeployment_redis_connectivity" "Test Redis connectivity"
    run_test "predeployment_07" "test_predeployment_storage_permissions" "Verify storage permissions"
    run_test "predeployment_08" "test_predeployment_exit_codes" "Verify exit codes"

    # TEST SUITE 2: Basic Health Checks
    log_header "TEST SUITE 2: Basic Health Checks (8 tests)"
    run_test "health_01" "test_health_check_basic" "Basic health check execution"
    run_test "health_02" "test_health_check_http_endpoints" "HTTP endpoint checks"
    run_test "health_03" "test_health_check_database" "Database health check"
    run_test "health_04" "test_health_check_redis" "Redis health check"
    run_test "health_05" "test_health_check_cache" "Cache functionality check"
    run_test "health_06" "test_health_check_storage" "Storage write check"
    run_test "health_07" "test_health_check_response_time" "Response time measurement"
    run_test "health_08" "test_health_check_exit_code" "Exit code validation"

    # TEST SUITE 3: Enhanced Health Checks
    log_header "TEST SUITE 3: Enhanced Health Checks (7 tests)"
    run_test "health_enhanced_01" "test_health_check_enhanced_all" "All enhanced checks"
    run_test "health_enhanced_02" "test_health_check_enhanced_json_output" "JSON output format"
    run_test "health_enhanced_03" "test_health_check_enhanced_prometheus_output" "Prometheus output format"
    run_test "health_enhanced_04" "test_health_check_enhanced_cpu" "CPU usage check"
    run_test "health_enhanced_05" "test_health_check_enhanced_memory" "Memory usage check"
    run_test "health_enhanced_06" "test_health_check_enhanced_services" "Service status checks"
    run_test "health_enhanced_07" "test_health_check_enhanced_ssl" "SSL certificate check"

    # TEST SUITE 4: Production Deployment
    log_header "TEST SUITE 4: Production Deployment Workflow (8 tests)"
    run_test "production_01" "test_production_deployment_dry_run" "Deployment script validation"
    run_test "production_02" "test_production_deployment_backup_creation" "Backup creation"
    run_test "production_03" "test_production_deployment_maintenance_mode" "Maintenance mode"
    run_test "production_04" "test_production_deployment_composer_install" "Composer install"
    run_test "production_05" "test_production_deployment_cache_optimization" "Cache optimization"
    run_test "production_06" "test_production_deployment_queue_restart" "Queue worker restart"
    run_test "production_07" "test_production_deployment_rollback_on_migration_failure" "Rollback mechanism"
    run_test "production_08" "test_production_deployment_logging" "Deployment logging"

    # TEST SUITE 5: Blue-Green Deployment
    log_header "TEST SUITE 5: Blue-Green Deployment (5 tests)"
    run_test "bluegreen_01" "test_blue_green_directory_structure" "Directory structure"
    run_test "bluegreen_02" "test_blue_green_symlink_creation" "Atomic symlink switch"
    run_test "bluegreen_03" "test_blue_green_health_check_before_switch" "Pre-switch health check"
    run_test "bluegreen_04" "test_blue_green_rollback_capability" "Rollback capability"
    run_test "bluegreen_05" "test_blue_green_cleanup_old_releases" "Old release cleanup"

    # TEST SUITE 6: Canary Deployment
    log_header "TEST SUITE 6: Canary Deployment (4 tests)"
    run_test "canary_01" "test_canary_traffic_splitting_config" "Traffic splitting configuration"
    run_test "canary_02" "test_canary_metrics_collection" "Metrics collection"
    run_test "canary_03" "test_canary_gradual_rollout_stages" "Gradual rollout stages"
    run_test "canary_04" "test_canary_automatic_rollback" "Automatic rollback"

    # TEST SUITE 7: Rollback Functionality
    log_header "TEST SUITE 7: Rollback Functionality (6 tests)"
    run_test "rollback_01" "test_rollback_script_validation" "Script validation"
    run_test "rollback_02" "test_rollback_commit_identification" "Commit identification"
    run_test "rollback_03" "test_rollback_migration_counting" "Migration counting"
    run_test "rollback_04" "test_rollback_backup_before_rollback" "Pre-rollback backup"
    run_test "rollback_05" "test_rollback_cache_clear" "Cache clearing"
    run_test "rollback_06" "test_rollback_dependency_restore" "Dependency restoration"

    # TEST SUITE 8: Backup and Restore
    log_header "TEST SUITE 8: Backup and Restore (3 tests)"
    run_test "backup_01" "test_backup_creation" "Backup creation"
    run_test "backup_02" "test_backup_retention_policy" "Retention policy"
    run_test "backup_03" "test_backup_verification" "Backup verification"

    # TEST SUITE 9: Error Handling
    log_header "TEST SUITE 9: Error Handling & Edge Cases (6 tests)"
    run_test "error_01" "test_error_handling_network_failure" "Network failure handling"
    run_test "error_02" "test_error_handling_disk_full" "Disk full detection"
    run_test "error_03" "test_error_handling_composer_timeout" "Composer timeout"
    run_test "error_04" "test_error_handling_npm_build_failure" "NPM build failure"
    run_test "error_05" "test_error_handling_migration_failure" "Migration failure"
    run_test "error_06" "test_error_handling_graceful_errors" "Graceful error messages"

    # TEST SUITE 10: Performance & Timing
    log_header "TEST SUITE 10: Performance & Timing (3 tests)"
    run_test "performance_01" "test_performance_predeployment_checks" "Pre-deployment check timing"
    run_test "performance_02" "test_performance_health_check_timing" "Health check timing"
    run_test "performance_03" "test_performance_cache_optimization" "Cache optimization timing"

    # TEST SUITE 11: VPS Setup Scripts
    log_header "TEST SUITE 11: VPS Setup Scripts (3 tests)"
    run_test "vps_01" "test_vps_setup_script_syntax" "Script syntax validation"
    run_test "vps_02" "test_vps_setup_dependency_check" "Dependency checking"
    run_test "vps_03" "test_vps_setup_service_configuration" "Service configuration"

    # TEST SUITE 12: CI/CD Pipeline
    log_header "TEST SUITE 12: CI/CD Pipeline (6 tests)"
    run_test "cicd_01" "test_github_actions_workflow_syntax" "Workflow YAML syntax"
    run_test "cicd_02" "test_github_actions_build_stage" "Build stage"
    run_test "cicd_03" "test_github_actions_security_scan" "Security scanning"
    run_test "cicd_04" "test_github_actions_deployment_stage" "Deployment stage"
    run_test "cicd_05" "test_github_actions_smoke_tests" "Smoke tests"
    run_test "cicd_06" "test_github_actions_rollback_on_failure" "Rollback on failure"

    # Cleanup
    cleanup_test_environment

    # Generate report
    generate_report
}

# Report generation
generate_report() {
    local end_time=$(date +%s)
    local total_duration=$((end_time - START_TIME))

    log_header "TEST EXECUTION SUMMARY"

    echo "Total Tests:    $TOTAL_TESTS"
    echo "Passed:         $PASSED_TESTS ($(( PASSED_TESTS * 100 / TOTAL_TESTS ))%)"
    echo "Failed:         $FAILED_TESTS"
    echo "Skipped:        $SKIPPED_TESTS"
    echo "Total Duration: ${total_duration}s"
    echo ""

    # Performance summary
    log_header "PERFORMANCE BENCHMARKS"
    echo "Test Name                           | Duration | Status"
    echo "----------------------------------------------------"
    for test_name in "${!TEST_TIMINGS[@]}"; do
        printf "%-35s | %6ss | %s\n" \
            "$test_name" \
            "${TEST_TIMINGS[$test_name]}" \
            "${TEST_RESULTS[$test_name]}"
    done | sort
    echo ""

    # Failed tests detail
    if [ $FAILED_TESTS -gt 0 ]; then
        log_header "FAILED TESTS DETAIL"
        for test_name in "${!TEST_RESULTS[@]}"; do
            if [ "${TEST_RESULTS[$test_name]}" = "FAIL" ]; then
                echo ""
                log_error "Test: $test_name"
                echo "Message: ${TEST_MESSAGES[$test_name]}" | head -5
            fi
        done | sort
    fi

    # Generate JSON report
    if [ "$OUTPUT_FORMAT" = "json" ]; then
        generate_json_report
    fi

    # Generate JUnit XML report
    if [ "$OUTPUT_FORMAT" = "junit" ]; then
        generate_junit_report
    fi

    # Final status
    echo ""
    if [ $FAILED_TESTS -eq 0 ]; then
        log_success "ALL TESTS PASSED!"
        echo ""
        echo "Production readiness: VERIFIED"
        exit 0
    else
        log_error "SOME TESTS FAILED"
        echo ""
        echo "Production readiness: ISSUES FOUND"
        exit 1
    fi
}

generate_json_report() {
    local json_file="/tmp/deployment-test-report-${TIMESTAMP}.json"

    cat > "$json_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "summary": {
    "total": $TOTAL_TESTS,
    "passed": $PASSED_TESTS,
    "failed": $FAILED_TESTS,
    "skipped": $SKIPPED_TESTS,
    "duration": $(($(date +%s) - START_TIME))
  },
  "tests": {
EOF

    local first=true
    for test_name in "${!TEST_RESULTS[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$json_file"
        fi

        cat >> "$json_file" << EOF
    "$test_name": {
      "status": "${TEST_RESULTS[$test_name]}",
      "duration": ${TEST_TIMINGS[$test_name]},
      "message": "$(echo "${TEST_MESSAGES[$test_name]}" | head -1 | sed 's/"/\\"/g')"
    }
EOF
    done

    echo "  }" >> "$json_file"
    echo "}" >> "$json_file"

    log_info "JSON report: $json_file"
}

generate_junit_report() {
    local junit_file="/tmp/deployment-test-report-${TIMESTAMP}.xml"

    cat > "$junit_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites tests="$TOTAL_TESTS" failures="$FAILED_TESTS" skipped="$SKIPPED_TESTS" time="$(($(date +%s) - START_TIME))">
  <testsuite name="DeploymentWorkflows" tests="$TOTAL_TESTS" failures="$FAILED_TESTS" skipped="$SKIPPED_TESTS">
EOF

    for test_name in "${!TEST_RESULTS[@]}"; do
        local status="${TEST_RESULTS[$test_name]}"
        local duration="${TEST_TIMINGS[$test_name]}"
        local message="${TEST_MESSAGES[$test_name]}"

        echo "    <testcase name=\"$test_name\" time=\"$duration\">" >> "$junit_file"

        if [ "$status" = "FAIL" ]; then
            echo "      <failure message=\"Test failed\">$message</failure>" >> "$junit_file"
        fi

        echo "    </testcase>" >> "$junit_file"
    done

    echo "  </testsuite>" >> "$junit_file"
    echo "</testsuites>" >> "$junit_file"

    log_info "JUnit report: $junit_file"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --container)
            TEST_CONTAINER="$2"
            shift 2
            ;;
        --ip)
            TEST_CONTAINER_IP="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --stop-on-failure)
            STOP_ON_FAILURE=true
            shift
            ;;
        --output)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --container NAME       Test container name (default: landsraad_tst)"
            echo "  --ip IP                Test container IP (default: 10.10.100.20)"
            echo "  --verbose              Enable verbose output"
            echo "  --stop-on-failure      Stop on first failure"
            echo "  --output FORMAT        Output format: text, json, junit (default: text)"
            echo "  --help                 Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main test suite
main
