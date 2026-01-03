#!/bin/bash

###############################################################################
# CHOM Pre-Deployment Validation Script
# Validates all prerequisites before deployment begins
# Exit 0: All checks pass, safe to deploy
# Exit 1: One or more checks failed, deployment blocked
###############################################################################

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEPLOY_USER="stilgar"
APP_SERVER="landsraad.arewel.com"
MONITORING_SERVER="mentat.arewel.com"
MIN_DISK_GB=10
MIN_MEMORY_GB=2
SSH_TIMEOUT=10
JSON_OUTPUT=false
QUIET_MODE=false
FAILED_CHECKS=0
TOTAL_CHECKS=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --quiet)
            QUIET_MODE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--json] [--quiet]"
            echo "  --json   Output results in JSON format"
            echo "  --quiet  Suppress progress output"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Logging functions
log_info() {
    if [[ "$QUIET_MODE" == "false" ]]; then
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
}

log_success() {
    if [[ "$QUIET_MODE" == "false" ]]; then
        echo -e "${GREEN}[✓]${NC} $1"
    fi
}

log_warning() {
    if [[ "$QUIET_MODE" == "false" ]]; then
        echo -e "${YELLOW}[⚠]${NC} $1"
    fi
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" >&2
}

log_section() {
    if [[ "$QUIET_MODE" == "false" ]]; then
        echo ""
        echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD}$1${NC}"
        echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi
}

# Results tracking
declare -A check_results
declare -A check_messages

record_check() {
    local check_name="$1"
    local status="$2"
    local message="${3:-}"

    ((TOTAL_CHECKS++))
    check_results["$check_name"]="$status"
    check_messages["$check_name"]="$message"

    if [[ "$status" == "FAIL" ]]; then
        ((FAILED_CHECKS++))
        log_error "$check_name: $message"
    elif [[ "$status" == "PASS" ]]; then
        log_success "$check_name"
    elif [[ "$status" == "WARN" ]]; then
        log_warning "$check_name: $message"
    fi
}

###############################################################################
# CHECK FUNCTIONS
###############################################################################

check_local_prerequisites() {
    log_section "Local Prerequisites"

    # Check required commands
    local required_commands=("ssh" "git" "jq" "curl" "grep" "awk" "sed")
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            record_check "Command: $cmd" "PASS"
        else
            record_check "Command: $cmd" "FAIL" "Required command not found. Install: $cmd"
        fi
    done

    # Check project root exists
    if [[ -d "$PROJECT_ROOT" ]]; then
        record_check "Project directory" "PASS"
    else
        record_check "Project directory" "FAIL" "Project root not found: $PROJECT_ROOT"
    fi

    # Check .env file exists
    if [[ -f "$PROJECT_ROOT/.env" ]]; then
        record_check ".env file" "PASS"
    else
        record_check ".env file" "FAIL" ".env file not found in $PROJECT_ROOT"
    fi

    # Check composer.json exists
    if [[ -f "$PROJECT_ROOT/composer.json" ]]; then
        record_check "composer.json" "PASS"
    else
        record_check "composer.json" "FAIL" "composer.json not found"
    fi

    # Check git repository
    if git -C "$PROJECT_ROOT" rev-parse --git-dir &>/dev/null; then
        record_check "Git repository" "PASS"

        # Check for uncommitted changes
        if [[ -z "$(git -C "$PROJECT_ROOT" status --porcelain)" ]]; then
            record_check "Git working tree" "PASS"
        else
            record_check "Git working tree" "WARN" "Uncommitted changes detected"
        fi
    else
        record_check "Git repository" "FAIL" "Not a git repository"
    fi
}

check_ssh_connectivity() {
    log_section "SSH Connectivity"

    # Test SSH to application server
    log_info "Testing SSH connection to $APP_SERVER..."
    if ssh -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes "$DEPLOY_USER@$APP_SERVER" "echo 'SSH test successful'" &>/dev/null; then
        record_check "SSH to $APP_SERVER" "PASS"

        # Test sudo access
        if ssh -o ConnectTimeout=$SSH_TIMEOUT "$DEPLOY_USER@$APP_SERVER" "sudo -n true" &>/dev/null; then
            record_check "Sudo on $APP_SERVER" "PASS"
        else
            record_check "Sudo on $APP_SERVER" "WARN" "Passwordless sudo not configured"
        fi
    else
        record_check "SSH to $APP_SERVER" "FAIL" "Cannot connect via SSH. Check keys and network."
    fi

    # Test SSH to monitoring server
    log_info "Testing SSH connection to $MONITORING_SERVER..."
    if ssh -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes "$DEPLOY_USER@$MONITORING_SERVER" "echo 'SSH test successful'" &>/dev/null; then
        record_check "SSH to $MONITORING_SERVER" "PASS"
    else
        record_check "SSH to $MONITORING_SERVER" "WARN" "Cannot connect to monitoring server"
    fi
}

check_remote_software() {
    log_section "Remote Software Requirements"

    local server="$DEPLOY_USER@$APP_SERVER"

    # PHP
    local php_version
    php_version=$(ssh "$server" "php -v 2>/dev/null | head -n1 | grep -oP 'PHP \K[0-9]+\.[0-9]+'" || echo "")
    if [[ -n "$php_version" ]]; then
        local major_version="${php_version%.*}"
        if [[ "$major_version" -ge 8 ]]; then
            record_check "PHP version ($php_version)" "PASS"
        else
            record_check "PHP version ($php_version)" "FAIL" "PHP 8.0+ required, found $php_version"
        fi
    else
        record_check "PHP" "FAIL" "PHP not installed"
    fi

    # PHP extensions
    local required_extensions=("mbstring" "xml" "pdo" "pdo_pgsql" "curl" "zip" "gd" "redis" "bcmath")
    for ext in "${required_extensions[@]}"; do
        if ssh "$server" "php -m 2>/dev/null | grep -qi '^${ext}$'" &>/dev/null; then
            record_check "PHP ext: $ext" "PASS"
        else
            record_check "PHP ext: $ext" "FAIL" "Required PHP extension not installed"
        fi
    done

    # Composer
    if ssh "$server" "command -v composer &>/dev/null"; then
        record_check "Composer" "PASS"
    else
        record_check "Composer" "FAIL" "Composer not installed"
    fi

    # Nginx
    if ssh "$server" "command -v nginx &>/dev/null"; then
        record_check "Nginx" "PASS"
    else
        record_check "Nginx" "FAIL" "Nginx not installed"
    fi

    # PostgreSQL client
    if ssh "$server" "command -v psql &>/dev/null"; then
        record_check "PostgreSQL client" "PASS"
    else
        record_check "PostgreSQL client" "FAIL" "PostgreSQL client not installed"
    fi

    # Redis client
    if ssh "$server" "command -v redis-cli &>/dev/null"; then
        record_check "Redis client" "PASS"
    else
        record_check "Redis client" "FAIL" "Redis client not installed"
    fi

    # Supervisor
    if ssh "$server" "command -v supervisorctl &>/dev/null"; then
        record_check "Supervisor" "PASS"
    else
        record_check "Supervisor" "WARN" "Supervisor not installed (needed for queue workers)"
    fi

    # Git
    if ssh "$server" "command -v git &>/dev/null"; then
        record_check "Git" "PASS"
    else
        record_check "Git" "FAIL" "Git not installed"
    fi
}

check_disk_space() {
    log_section "Disk Space"

    local server="$DEPLOY_USER@$APP_SERVER"

    # Check application partition
    local app_disk_info
    app_disk_info=$(ssh "$server" "df -BG /var/www 2>/dev/null | tail -1" || echo "")

    if [[ -n "$app_disk_info" ]]; then
        local available_gb=$(echo "$app_disk_info" | awk '{print $4}' | sed 's/G//')
        local usage_percent=$(echo "$app_disk_info" | awk '{print $5}' | sed 's/%//')

        if [[ "$available_gb" -ge "$MIN_DISK_GB" ]]; then
            record_check "Disk space: /var/www" "PASS"
        else
            record_check "Disk space: /var/www" "FAIL" "Only ${available_gb}GB available, need ${MIN_DISK_GB}GB minimum"
        fi

        if [[ "$usage_percent" -gt 90 ]]; then
            record_check "Disk usage: /var/www" "WARN" "Disk ${usage_percent}% full"
        else
            record_check "Disk usage: /var/www" "PASS"
        fi
    else
        record_check "Disk space check" "FAIL" "Cannot check disk space"
    fi

    # Check tmp space
    local tmp_disk_info
    tmp_disk_info=$(ssh "$server" "df -BG /tmp 2>/dev/null | tail -1" || echo "")

    if [[ -n "$tmp_disk_info" ]]; then
        local tmp_available_gb=$(echo "$tmp_disk_info" | awk '{print $4}' | sed 's/G//')
        if [[ "$tmp_available_gb" -ge 1 ]]; then
            record_check "Disk space: /tmp" "PASS"
        else
            record_check "Disk space: /tmp" "WARN" "Only ${tmp_available_gb}GB available in /tmp"
        fi
    fi
}

check_memory() {
    log_section "Memory Resources"

    local server="$DEPLOY_USER@$APP_SERVER"

    # Check available memory
    local mem_info
    mem_info=$(ssh "$server" "free -g | grep Mem:" || echo "")

    if [[ -n "$mem_info" ]]; then
        local total_gb=$(echo "$mem_info" | awk '{print $2}')
        local available_gb=$(echo "$mem_info" | awk '{print $7}')
        local used_percent=$(awk "BEGIN {printf \"%.0f\", (($total_gb - $available_gb) / $total_gb) * 100}")

        if [[ "$available_gb" -ge "$MIN_MEMORY_GB" ]]; then
            record_check "Available memory" "PASS"
        else
            record_check "Available memory" "WARN" "Only ${available_gb}GB available"
        fi

        if [[ "$used_percent" -gt 90 ]]; then
            record_check "Memory usage" "WARN" "Memory ${used_percent}% used"
        else
            record_check "Memory usage" "PASS"
        fi
    else
        record_check "Memory check" "FAIL" "Cannot check memory"
    fi
}

check_database() {
    log_section "Database Connectivity"

    local server="$DEPLOY_USER@$APP_SERVER"

    # Read database credentials from .env
    local db_host db_port db_name db_user db_pass

    if [[ -f "$PROJECT_ROOT/.env" ]]; then
        db_host=$(grep "^DB_HOST=" "$PROJECT_ROOT/.env" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        db_port=$(grep "^DB_PORT=" "$PROJECT_ROOT/.env" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        db_name=$(grep "^DB_DATABASE=" "$PROJECT_ROOT/.env" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        db_user=$(grep "^DB_USERNAME=" "$PROJECT_ROOT/.env" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        db_pass=$(grep "^DB_PASSWORD=" "$PROJECT_ROOT/.env" | cut -d'=' -f2- | tr -d '"' | tr -d "'")

        # Test database connection
        if [[ -n "$db_host" && -n "$db_name" && -n "$db_user" ]]; then
            local db_test
            db_test=$(ssh "$server" "PGPASSWORD='${db_pass}' psql -h '${db_host}' -p '${db_port:-5432}' -U '${db_user}' -d '${db_name}' -c 'SELECT 1;' 2>&1" || echo "FAILED")

            if [[ "$db_test" == *"FAILED"* ]] || [[ "$db_test" == *"error"* ]] || [[ "$db_test" == *"could not connect"* ]]; then
                record_check "Database connection" "FAIL" "Cannot connect to PostgreSQL database"
            else
                record_check "Database connection" "PASS"

                # Check database size
                local db_size
                db_size=$(ssh "$server" "PGPASSWORD='${db_pass}' psql -h '${db_host}' -p '${db_port:-5432}' -U '${db_user}' -d '${db_name}' -t -c \"SELECT pg_size_pretty(pg_database_size('${db_name}'));\" 2>/dev/null" || echo "")

                if [[ -n "$db_size" ]]; then
                    log_info "Database size: $(echo $db_size | xargs)"
                fi
            fi
        else
            record_check "Database config" "FAIL" "Missing database configuration in .env"
        fi
    else
        record_check "Database config" "FAIL" ".env file not found"
    fi
}

check_redis() {
    log_section "Redis Connectivity"

    local server="$DEPLOY_USER@$APP_SERVER"

    # Read Redis configuration
    local redis_host redis_port redis_pass

    if [[ -f "$PROJECT_ROOT/.env" ]]; then
        redis_host=$(grep "^REDIS_HOST=" "$PROJECT_ROOT/.env" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        redis_port=$(grep "^REDIS_PORT=" "$PROJECT_ROOT/.env" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        redis_pass=$(grep "^REDIS_PASSWORD=" "$PROJECT_ROOT/.env" | cut -d'=' -f2- | tr -d '"' | tr -d "'")

        # Default values
        redis_host="${redis_host:-127.0.0.1}"
        redis_port="${redis_port:-6379}"

        # Test Redis connection
        local redis_test
        if [[ -n "$redis_pass" ]]; then
            redis_test=$(ssh "$server" "redis-cli -h '${redis_host}' -p '${redis_port}' -a '${redis_pass}' --no-auth-warning ping 2>&1" || echo "FAILED")
        else
            redis_test=$(ssh "$server" "redis-cli -h '${redis_host}' -p '${redis_port}' ping 2>&1" || echo "FAILED")
        fi

        if [[ "$redis_test" == "PONG" ]]; then
            record_check "Redis connection" "PASS"
        else
            record_check "Redis connection" "FAIL" "Cannot connect to Redis server"
        fi
    fi
}

check_git_access() {
    log_section "Git Repository Access"

    # Check if repository is accessible
    local repo_url
    repo_url=$(git -C "$PROJECT_ROOT" config --get remote.origin.url || echo "")

    if [[ -n "$repo_url" ]]; then
        log_info "Repository URL: $repo_url"

        # Try to fetch from remote
        if git -C "$PROJECT_ROOT" ls-remote --exit-code "$repo_url" &>/dev/null; then
            record_check "Git remote access" "PASS"
        else
            record_check "Git remote access" "FAIL" "Cannot access remote repository"
        fi
    else
        record_check "Git remote" "WARN" "No remote repository configured"
    fi

    # Check current branch
    local current_branch
    current_branch=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD || echo "")

    if [[ -n "$current_branch" ]]; then
        log_info "Current branch: $current_branch"
        record_check "Git branch" "PASS"
    fi
}

check_ssl_certificates() {
    log_section "SSL Certificates"

    local server="$DEPLOY_USER@$APP_SERVER"

    # Check if SSL certificate exists
    local cert_path="/etc/ssl/certs/chom.crt"
    local key_path="/etc/ssl/private/chom.key"

    if ssh "$server" "sudo test -f $cert_path" &>/dev/null; then
        record_check "SSL certificate exists" "PASS"

        # Check certificate expiration
        local cert_expiry
        cert_expiry=$(ssh "$server" "sudo openssl x509 -in $cert_path -noout -enddate 2>/dev/null" || echo "")

        if [[ -n "$cert_expiry" ]]; then
            local expiry_date=$(echo "$cert_expiry" | cut -d'=' -f2)
            local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
            local current_epoch=$(date +%s)
            local days_remaining=$(( (expiry_epoch - current_epoch) / 86400 ))

            if [[ "$days_remaining" -gt 30 ]]; then
                record_check "SSL certificate validity" "PASS"
            elif [[ "$days_remaining" -gt 0 ]]; then
                record_check "SSL certificate validity" "WARN" "Certificate expires in ${days_remaining} days"
            else
                record_check "SSL certificate validity" "FAIL" "Certificate has expired"
            fi
        fi

        # Check if key exists
        if ssh "$server" "sudo test -f $key_path" &>/dev/null; then
            record_check "SSL private key exists" "PASS"
        else
            record_check "SSL private key exists" "FAIL" "SSL private key not found"
        fi
    else
        record_check "SSL certificate" "WARN" "No SSL certificate found (will use HTTP)"
    fi
}

check_conflicting_processes() {
    log_section "Process Conflicts"

    local server="$DEPLOY_USER@$APP_SERVER"

    # Check if deployment is already running
    local deploy_lock="/tmp/chom-deploy.lock"
    if ssh "$server" "test -f $deploy_lock" &>/dev/null; then
        local lock_age
        lock_age=$(ssh "$server" "stat -c %Y $deploy_lock 2>/dev/null || echo 0")
        local current_time=$(date +%s)
        local age_minutes=$(( (current_time - lock_age) / 60 ))

        if [[ "$age_minutes" -lt 60 ]]; then
            record_check "Deployment lock" "FAIL" "Deployment already in progress (lock age: ${age_minutes}m)"
        else
            record_check "Deployment lock" "WARN" "Stale deployment lock found (${age_minutes}m old)"
        fi
    else
        record_check "Deployment lock" "PASS"
    fi

    # Check for hung PHP processes
    local php_procs
    php_procs=$(ssh "$server" "ps aux | grep '[p]hp.*artisan' | wc -l" || echo "0")

    if [[ "$php_procs" -gt 10 ]]; then
        record_check "PHP processes" "WARN" "High number of PHP processes: $php_procs"
    else
        record_check "PHP processes" "PASS"
    fi
}

check_file_permissions() {
    log_section "File Permissions"

    local server="$DEPLOY_USER@$APP_SERVER"
    local app_path="/var/www/chom"

    # Check if application directory exists
    if ssh "$server" "test -d $app_path" &>/dev/null; then
        # Check ownership
        local owner
        owner=$(ssh "$server" "stat -c '%U' $app_path 2>/dev/null" || echo "")

        if [[ "$owner" == "$DEPLOY_USER" ]] || [[ "$owner" == "www-data" ]]; then
            record_check "App directory ownership" "PASS"
        else
            record_check "App directory ownership" "WARN" "Directory owned by: $owner"
        fi

        # Check storage directory
        if ssh "$server" "test -d $app_path/storage" &>/dev/null; then
            if ssh "$server" "test -w $app_path/storage" &>/dev/null; then
                record_check "Storage writable" "PASS"
            else
                record_check "Storage writable" "FAIL" "Storage directory not writable"
            fi
        else
            record_check "Storage directory" "WARN" "Storage directory not found (fresh install)"
        fi
    else
        record_check "Application directory" "WARN" "Application not yet deployed"
    fi
}

check_environment_files() {
    log_section "Environment Configuration"

    local server="$DEPLOY_USER@$APP_SERVER"
    local app_path="/var/www/chom"

    # Check local .env file
    if [[ -f "$PROJECT_ROOT/.env" ]]; then
        record_check "Local .env file" "PASS"

        # Check for required variables
        local required_vars=("APP_KEY" "DB_DATABASE" "DB_USERNAME" "APP_URL")
        for var in "${required_vars[@]}"; do
            if grep -q "^${var}=" "$PROJECT_ROOT/.env"; then
                local value=$(grep "^${var}=" "$PROJECT_ROOT/.env" | cut -d'=' -f2-)
                if [[ -n "$value" ]]; then
                    record_check "Env var: $var" "PASS"
                else
                    record_check "Env var: $var" "FAIL" "Variable is empty"
                fi
            else
                record_check "Env var: $var" "FAIL" "Variable not defined"
            fi
        done
    else
        record_check "Local .env file" "FAIL" ".env file not found"
    fi

    # Check remote .env file exists
    if ssh "$server" "test -f $app_path/.env" &>/dev/null; then
        record_check "Remote .env file" "PASS"
    else
        record_check "Remote .env file" "WARN" "No .env on remote (fresh install)"
    fi
}

check_network_connectivity() {
    log_section "Network Connectivity"

    # Check DNS resolution
    if host "$APP_SERVER" &>/dev/null; then
        record_check "DNS: $APP_SERVER" "PASS"
    else
        record_check "DNS: $APP_SERVER" "FAIL" "Cannot resolve hostname"
    fi

    if host "$MONITORING_SERVER" &>/dev/null; then
        record_check "DNS: $MONITORING_SERVER" "PASS"
    else
        record_check "DNS: $MONITORING_SERVER" "WARN" "Cannot resolve monitoring server"
    fi

    # Check HTTP(S) connectivity
    local app_url
    app_url=$(grep "^APP_URL=" "$PROJECT_ROOT/.env" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")

    if [[ -n "$app_url" ]]; then
        if curl -sSf -m 10 "$app_url" &>/dev/null; then
            record_check "HTTP access: $app_url" "PASS"
        else
            record_check "HTTP access: $app_url" "WARN" "Application not accessible (may not be deployed yet)"
        fi
    fi
}

###############################################################################
# OUTPUT FUNCTIONS
###############################################################################

output_json() {
    local status="success"
    if [[ "$FAILED_CHECKS" -gt 0 ]]; then
        status="failure"
    fi

    echo "{"
    echo "  \"status\": \"$status\","
    echo "  \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
    echo "  \"total_checks\": $TOTAL_CHECKS,"
    echo "  \"failed_checks\": $FAILED_CHECKS,"
    echo "  \"checks\": {"

    local first=true
    for check_name in "${!check_results[@]}"; do
        if [[ "$first" == "false" ]]; then
            echo ","
        fi
        first=false

        local status="${check_results[$check_name]}"
        local message="${check_messages[$check_name]}"

        echo -n "    \"$check_name\": {"
        echo -n "\"status\": \"$status\""
        if [[ -n "$message" ]]; then
            echo -n ", \"message\": \"$message\""
        fi
        echo -n "}"
    done

    echo ""
    echo "  }"
    echo "}"
}

output_summary() {
    echo ""
    log_section "Pre-Deployment Check Summary"

    local passed=$((TOTAL_CHECKS - FAILED_CHECKS))

    echo -e "Total checks: ${BOLD}$TOTAL_CHECKS${NC}"
    echo -e "Passed: ${GREEN}${BOLD}$passed${NC}"
    echo -e "Failed: ${RED}${BOLD}$FAILED_CHECKS${NC}"
    echo ""

    if [[ "$FAILED_CHECKS" -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ All pre-deployment checks passed!${NC}"
        echo -e "${GREEN}${BOLD}✓ Safe to proceed with deployment${NC}"
        return 0
    else
        echo -e "${RED}${BOLD}✗ Pre-deployment checks failed!${NC}"
        echo -e "${RED}${BOLD}✗ Fix the issues above before deploying${NC}"
        echo ""
        echo -e "${YELLOW}Failed checks:${NC}"
        for check_name in "${!check_results[@]}"; do
            if [[ "${check_results[$check_name]}" == "FAIL" ]]; then
                echo -e "  ${RED}✗${NC} $check_name: ${check_messages[$check_name]}"
            fi
        done
        return 1
    fi
}

###############################################################################
# MAIN EXECUTION
###############################################################################

main() {
    if [[ "$QUIET_MODE" == "false" ]]; then
        echo -e "${BOLD}${BLUE}"
        echo "╔═══════════════════════════════════════════════════════════════╗"
        echo "║        CHOM Pre-Deployment Validation                         ║"
        echo "║        Validating deployment prerequisites...                 ║"
        echo "╚═══════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
    fi

    # Run all checks
    check_local_prerequisites
    check_ssh_connectivity
    check_remote_software
    check_disk_space
    check_memory
    check_database
    check_redis
    check_git_access
    check_ssl_certificates
    check_conflicting_processes
    check_file_permissions
    check_environment_files
    check_network_connectivity

    # Output results
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        output_json
    else
        output_summary
    fi

    # Exit with appropriate code
    if [[ "$FAILED_CHECKS" -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

main "$@"
