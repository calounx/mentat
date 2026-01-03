#!/usr/bin/env bash
# Comprehensive health checks for CHOM application
# Returns 0 if all checks pass, non-zero otherwise
# Usage: ./health-check.sh [--release-path /path/to/release] [--timeout 30]

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utils/logging.sh"

# Configuration
APP_DIR="${APP_DIR:-/var/www/chom}"
RELEASE_PATH="${RELEASE_PATH:-${APP_DIR}/current}"
TIMEOUT="${TIMEOUT:-30}"
APP_URL="${APP_URL:-http://localhost}"
PHP_VERSION="${PHP_VERSION:-8.2}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --release-path)
            RELEASE_PATH="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --app-url)
            APP_URL="$2"
            shift 2
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# Track health check failures
HEALTH_CHECK_FAILED=0

init_deployment_log "health-check-$(date +%Y%m%d_%H%M%S)"
log_section "Health Check"

# Check if a service is running
check_service() {
    local service_name="$1"

    log_step "Checking $service_name service"

    if sudo systemctl is-active --quiet "$service_name"; then
        log_success "$service_name is running"
        return 0
    else
        log_error "$service_name is not running"
        HEALTH_CHECK_FAILED=1
        return 1
    fi
}

# Check if a port is listening
check_port() {
    local port="$1"
    local service_name="$2"

    log_step "Checking if $service_name is listening on port $port"

    if netstat -tuln | grep -q ":$port "; then
        log_success "$service_name is listening on port $port"
        return 0
    else
        log_error "$service_name is not listening on port $port"
        HEALTH_CHECK_FAILED=1
        return 1
    fi
}

# Check HTTP response
check_http_response() {
    local url="$1"
    local expected_code="${2:-200}"

    log_step "Checking HTTP response from $url"

    local response_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" "$url" || echo "000")

    if [[ "$response_code" == "$expected_code" ]]; then
        log_success "HTTP response code: $response_code (expected: $expected_code)"
        return 0
    else
        log_error "HTTP response code: $response_code (expected: $expected_code)"
        HEALTH_CHECK_FAILED=1
        return 1
    fi
}

# Check database connectivity
check_database() {
    log_step "Checking PostgreSQL database connectivity"

    if [[ ! -f "${RELEASE_PATH}/.env" ]]; then
        log_warning "No .env file found at ${RELEASE_PATH}/.env, skipping database check"
        return 0
    fi

    # Source environment variables
    local db_host=$(grep "^DB_HOST=" "${RELEASE_PATH}/.env" | cut -d'=' -f2)
    local db_port=$(grep "^DB_PORT=" "${RELEASE_PATH}/.env" | cut -d'=' -f2)
    local db_database=$(grep "^DB_DATABASE=" "${RELEASE_PATH}/.env" | cut -d'=' -f2)
    local db_username=$(grep "^DB_USERNAME=" "${RELEASE_PATH}/.env" | cut -d'=' -f2)
    local db_password=$(grep "^DB_PASSWORD=" "${RELEASE_PATH}/.env" | cut -d'=' -f2)

    # Test database connection
    if PGPASSWORD="$db_password" psql -h "$db_host" -p "$db_port" -U "$db_username" -d "$db_database" -c "SELECT 1;" > /dev/null 2>&1; then
        log_success "Database connection successful"
        return 0
    else
        log_error "Database connection failed"
        HEALTH_CHECK_FAILED=1
        return 1
    fi
}

# Check Redis connectivity
check_redis() {
    log_step "Checking Redis connectivity"

    if redis-cli ping > /dev/null 2>&1; then
        log_success "Redis is responding"
        return 0
    else
        log_error "Redis is not responding"
        HEALTH_CHECK_FAILED=1
        return 1
    fi
}

# Check disk space
check_disk_space() {
    local threshold="${1:-90}"

    log_step "Checking disk space"

    local usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')

    if [[ $usage -lt $threshold ]]; then
        log_success "Disk usage: ${usage}% (threshold: ${threshold}%)"
        return 0
    else
        log_error "Disk usage: ${usage}% exceeds threshold ${threshold}%"
        HEALTH_CHECK_FAILED=1
        return 1
    fi
}

# Check memory usage
check_memory() {
    local threshold="${1:-90}"

    log_step "Checking memory usage"

    local total_mem=$(free | grep Mem | awk '{print $2}')
    local used_mem=$(free | grep Mem | awk '{print $3}')
    local usage=$(( (used_mem * 100) / total_mem ))

    if [[ $usage -lt $threshold ]]; then
        log_success "Memory usage: ${usage}% (threshold: ${threshold}%)"
        return 0
    else
        log_warning "Memory usage: ${usage}% exceeds threshold ${threshold}%"
        return 0  # Don't fail on memory warning
    fi
}

# Check Laravel application
check_laravel_app() {
    log_step "Checking Laravel application"

    if [[ ! -d "$RELEASE_PATH" ]]; then
        log_error "Release path does not exist: $RELEASE_PATH"
        HEALTH_CHECK_FAILED=1
        return 1
    fi

    # Check if artisan exists
    if [[ ! -f "${RELEASE_PATH}/artisan" ]]; then
        log_error "artisan file not found in $RELEASE_PATH"
        HEALTH_CHECK_FAILED=1
        return 1
    fi

    # Check if vendor directory exists
    if [[ ! -d "${RELEASE_PATH}/vendor" ]]; then
        log_error "vendor directory not found in $RELEASE_PATH"
        HEALTH_CHECK_FAILED=1
        return 1
    fi

    # Test artisan command
    cd "$RELEASE_PATH"
    if php artisan --version > /dev/null 2>&1; then
        log_success "Laravel application is working"
        return 0
    else
        log_error "Laravel artisan command failed"
        HEALTH_CHECK_FAILED=1
        return 1
    fi
}

# Check queue workers
check_queue_workers() {
    log_step "Checking Laravel queue workers"

    local worker_count=$(pgrep -f "queue:work" | wc -l)

    if [[ $worker_count -gt 0 ]]; then
        log_success "Queue workers running: $worker_count"
        return 0
    else
        log_warning "No queue workers running"
        return 0  # Don't fail if queue workers aren't running yet
    fi
}

# Check file permissions
check_permissions() {
    log_step "Checking file permissions"

    local failed=0

    # Check storage directory
    if [[ -d "${RELEASE_PATH}/storage" ]]; then
        if [[ -w "${RELEASE_PATH}/storage" ]]; then
            log_success "storage directory is writable"
        else
            log_error "storage directory is not writable"
            failed=1
        fi
    fi

    # Check bootstrap/cache directory
    if [[ -d "${RELEASE_PATH}/bootstrap/cache" ]]; then
        if [[ -w "${RELEASE_PATH}/bootstrap/cache" ]]; then
            log_success "bootstrap/cache directory is writable"
        else
            log_error "bootstrap/cache directory is not writable"
            failed=1
        fi
    fi

    if [[ $failed -eq 1 ]]; then
        HEALTH_CHECK_FAILED=1
        return 1
    fi

    return 0
}

# Check environment configuration
check_environment() {
    log_step "Checking environment configuration"

    if [[ ! -f "${RELEASE_PATH}/.env" ]]; then
        log_error ".env file not found"
        HEALTH_CHECK_FAILED=1
        return 1
    fi

    # Check required environment variables
    local required_vars=("APP_KEY" "DB_HOST" "DB_DATABASE" "DB_USERNAME" "DB_PASSWORD")

    for var in "${required_vars[@]}"; do
        if grep -q "^${var}=" "${RELEASE_PATH}/.env"; then
            local value=$(grep "^${var}=" "${RELEASE_PATH}/.env" | cut -d'=' -f2)
            if [[ -n "$value" ]]; then
                log_success "$var is set"
            else
                log_error "$var is empty"
                HEALTH_CHECK_FAILED=1
            fi
        else
            log_error "$var is not defined"
            HEALTH_CHECK_FAILED=1
        fi
    done

    if [[ $HEALTH_CHECK_FAILED -eq 1 ]]; then
        return 1
    fi

    return 0
}

# Check metrics endpoint
check_metrics_endpoint() {
    log_step "Checking metrics endpoint"

    local metrics_url="${APP_URL}/metrics"

    # Try to fetch metrics (may not be available in all environments)
    local response_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$metrics_url" || echo "000")

    if [[ "$response_code" == "200" ]]; then
        log_success "Metrics endpoint is responding"
        return 0
    else
        log_info "Metrics endpoint returned $response_code (this may be expected)"
        return 0  # Don't fail on metrics endpoint
    fi
}

# Check SSL certificate (if HTTPS)
check_ssl_certificate() {
    local domain="${1:-}"

    if [[ -z "$domain" ]]; then
        log_info "No domain specified, skipping SSL check"
        return 0
    fi

    log_step "Checking SSL certificate for $domain"

    local cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"

    if [[ ! -f "$cert_path" ]]; then
        log_warning "SSL certificate not found: $cert_path"
        return 0  # Don't fail if SSL not configured
    fi

    # Check certificate expiration
    local expiry_date=$(sudo openssl x509 -in "$cert_path" -noout -enddate | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s)
    local now_epoch=$(date +%s)
    local days_until_expiry=$(( (expiry_epoch - now_epoch) / 86400 ))

    if [[ $days_until_expiry -gt 7 ]]; then
        log_success "SSL certificate valid for $days_until_expiry days"
        return 0
    else
        log_warning "SSL certificate expires in $days_until_expiry days"
        return 0  # Don't fail, but warn
    fi
}

# Main execution
main() {
    start_timer

    print_header "CHOM Health Check"
    log_info "Release path: $RELEASE_PATH"
    log_info "Timeout: ${TIMEOUT}s"
    log_info "App URL: $APP_URL"
    echo ""

    # System checks
    log_section "System Services"
    check_service "nginx"
    check_service "php${PHP_VERSION}-fpm"
    check_service "postgresql"
    check_service "redis-server"

    # Port checks
    log_section "Port Availability"
    check_port 80 "Nginx HTTP"
    check_port 443 "Nginx HTTPS" || true  # Don't fail if HTTPS not configured
    check_port 5432 "PostgreSQL"
    check_port 6379 "Redis"

    # Application checks
    log_section "Application Health"
    check_laravel_app
    check_environment
    check_permissions
    check_database
    check_redis
    check_queue_workers

    # HTTP checks
    log_section "HTTP Endpoints"
    check_http_response "$APP_URL"
    check_metrics_endpoint

    # System resource checks
    log_section "System Resources"
    check_disk_space 90
    check_memory 90

    # SSL checks (optional)
    if [[ -n "${DOMAIN:-}" ]]; then
        log_section "SSL Certificate"
        check_ssl_certificate "$DOMAIN"
    fi

    end_timer "Health check"

    echo ""
    if [[ $HEALTH_CHECK_FAILED -eq 0 ]]; then
        print_header "Health Check: PASSED"
        log_success "All health checks passed"
        exit 0
    else
        print_header "Health Check: FAILED"
        log_error "Some health checks failed"
        exit 1
    fi
}

main
