#!/bin/bash

###############################################################################
# CHOM Connection Test Tool
# Tests all critical connections with latency measurements
###############################################################################

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration
DEPLOY_USER="stilgar"
APP_SERVER="landsraad.arewel.com"
MONITORING_SERVER="mentat.arewel.com"
APP_PATH="/var/www/chom/current"
TIMEOUT=10

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

test_ssh_connection() {
    local server="$1"
    local description="$2"

    local start=$(date +%s%N)
    if ssh -o ConnectTimeout=$TIMEOUT -o BatchMode=yes "$DEPLOY_USER@$server" "echo 'OK'" &>/dev/null; then
        local end=$(date +%s%N)
        local latency=$(( (end - start) / 1000000 ))
        log_success "$description - ${latency}ms"
        return 0
    else
        log_error "$description - Connection failed"
        return 1
    fi
}

test_database_connection() {
    log_section "Database Connection"

    # Read database config
    local db_host=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^DB_HOST=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'" || echo "")
    local db_port=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^DB_PORT=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'" || echo "5432")
    local db_name=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^DB_DATABASE=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'" || echo "")
    local db_user=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^DB_USERNAME=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'" || echo "")
    local db_pass=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^DB_PASSWORD=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'" || echo "")

    log_info "Database: $db_host:$db_port/$db_name"

    if [[ -z "$db_host" ]]; then
        log_error "Database configuration not found"
        return 1
    fi

    # Test connection
    local start=$(date +%s%N)
    local result=$(ssh "$DEPLOY_USER@$APP_SERVER" "PGPASSWORD='$db_pass' psql -h '$db_host' -p '$db_port' -U '$db_user' -d '$db_name' -c 'SELECT 1;' 2>&1" || echo "FAILED")
    local end=$(date +%s%N)
    local latency=$(( (end - start) / 1000000 ))

    if [[ "$result" != *"FAILED"* ]] && [[ "$result" != *"error"* ]]; then
        log_success "PostgreSQL connection successful - ${latency}ms"

        # Test query performance
        local query_start=$(date +%s%N)
        ssh "$DEPLOY_USER@$APP_SERVER" "PGPASSWORD='$db_pass' psql -h '$db_host' -p '$db_port' -U '$db_user' -d '$db_name' -c 'SELECT COUNT(*) FROM information_schema.tables;' 2>/dev/null" &>/dev/null
        local query_end=$(date +%s%N)
        local query_latency=$(( (query_end - query_start) / 1000000 ))

        log_info "Query latency: ${query_latency}ms"
    else
        log_error "PostgreSQL connection failed"
        echo "$result" | grep -i error | head -3
    fi
}

test_redis_connection() {
    log_section "Redis Connection"

    # Read Redis config
    local redis_host=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^REDIS_HOST=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'" || echo "127.0.0.1")
    local redis_port=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^REDIS_PORT=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'" || echo "6379")
    local redis_pass=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^REDIS_PASSWORD=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'" || echo "")

    log_info "Redis: $redis_host:$redis_port"

    # Test connection
    local start=$(date +%s%N)
    local result
    if [[ -n "$redis_pass" ]]; then
        result=$(ssh "$DEPLOY_USER@$APP_SERVER" "redis-cli -h '$redis_host' -p '$redis_port' -a '$redis_pass' --no-auth-warning ping 2>&1" || echo "FAILED")
    else
        result=$(ssh "$DEPLOY_USER@$APP_SERVER" "redis-cli -h '$redis_host' -p '$redis_port' ping 2>&1" || echo "FAILED")
    fi
    local end=$(date +%s%N)
    local latency=$(( (end - start) / 1000000 ))

    if [[ "$result" == "PONG" ]]; then
        log_success "Redis connection successful - ${latency}ms"

        # Get Redis info
        local redis_version
        if [[ -n "$redis_pass" ]]; then
            redis_version=$(ssh "$DEPLOY_USER@$APP_SERVER" "redis-cli -h '$redis_host' -p '$redis_port' -a '$redis_pass' --no-auth-warning info server 2>/dev/null | grep 'redis_version' | cut -d':' -f2" || echo "unknown")
        else
            redis_version=$(ssh "$DEPLOY_USER@$APP_SERVER" "redis-cli -h '$redis_host' -p '$redis_port' info server 2>/dev/null | grep 'redis_version' | cut -d':' -f2" || echo "unknown")
        fi
        log_info "Redis version: $redis_version"
    else
        log_error "Redis connection failed"
    fi
}

test_dns_resolution() {
    log_section "DNS Resolution"

    local domains=("$APP_SERVER" "$MONITORING_SERVER" "github.com" "packagist.org")

    for domain in "${domains[@]}"; do
        local start=$(date +%s%N)
        local ip=$(host "$domain" 2>/dev/null | grep "has address" | head -1 | awk '{print $4}' || echo "")
        local end=$(date +%s%N)
        local latency=$(( (end - start) / 1000000 ))

        if [[ -n "$ip" ]]; then
            log_success "$domain → $ip (${latency}ms)"
        else
            log_error "$domain - DNS resolution failed"
        fi
    done
}

test_http_connectivity() {
    log_section "HTTP/HTTPS Connectivity"

    # Test application URL
    local app_url=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^APP_URL=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'" || echo "")

    if [[ -n "$app_url" ]]; then
        log_info "Testing: $app_url"

        local start=$(date +%s%N)
        local http_code=$(curl -sSL -w "%{http_code}" -o /dev/null -m $TIMEOUT "$app_url" 2>/dev/null || echo "000")
        local end=$(date +%s%N)
        local latency=$(( (end - start) / 1000000 ))

        if [[ "$http_code" == "200" ]] || [[ "$http_code" == "302" ]]; then
            log_success "Application accessible (HTTP $http_code) - ${latency}ms"
        else
            log_error "Application returned HTTP $http_code - ${latency}ms"
        fi
    fi

    # Test monitoring server
    local grafana_url="http://${MONITORING_SERVER}:3000"
    log_info "Testing: $grafana_url"

    local start=$(date +%s%N)
    local grafana_code=$(curl -sSL -w "%{http_code}" -o /dev/null -m 5 "${grafana_url}/api/health" 2>/dev/null || echo "000")
    local end=$(date +%s%N)
    local grafana_latency=$(( (end - start) / 1000000 ))

    if [[ "$grafana_code" == "200" ]]; then
        log_success "Grafana accessible - ${grafana_latency}ms"
    else
        log_error "Grafana not accessible (HTTP $grafana_code)"
    fi
}

test_ssl_certificate() {
    log_section "SSL Certificate Validation"

    local app_url=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep '^APP_URL=' $APP_PATH/.env 2>/dev/null | cut -d'=' -f2-" | tr -d '"' | tr -d "'" || echo "")

    if [[ "$app_url" != https://* ]]; then
        log_info "Application not using HTTPS"
        return
    fi

    local domain=$(echo "$app_url" | sed -e 's|https://||' -e 's|/.*||')
    log_info "Checking SSL for: $domain"

    # Get certificate details
    local cert_info=$(echo | timeout $TIMEOUT openssl s_client -connect "$domain:443" -servername "$domain" 2>/dev/null | openssl x509 -noout -dates -subject -issuer 2>/dev/null || echo "FAILED")

    if [[ "$cert_info" == "FAILED" ]]; then
        log_error "Cannot retrieve SSL certificate"
        return
    fi

    # Parse certificate info
    local not_after=$(echo "$cert_info" | grep "notAfter" | cut -d'=' -f2)
    local subject=$(echo "$cert_info" | grep "subject" | cut -d'=' -f2-)
    local issuer=$(echo "$cert_info" | grep "issuer" | cut -d'=' -f2-)

    log_success "SSL certificate valid"
    log_info "Subject: $subject"
    log_info "Issuer: $issuer"

    # Check expiration
    local expiry_epoch=$(date -d "$not_after" +%s 2>/dev/null || echo "0")
    local current_epoch=$(date +%s)
    local days_remaining=$(( (expiry_epoch - current_epoch) / 86400 ))

    if [[ "$days_remaining" -gt 30 ]]; then
        log_info "Expires in: ${days_remaining} days ✓"
    elif [[ "$days_remaining" -gt 0 ]]; then
        echo -e "${YELLOW}[⚠] Expires in: ${days_remaining} days (renewal needed)${NC}"
    else
        log_error "Certificate expired!"
    fi
}

test_network_latency() {
    log_section "Network Latency Tests"

    local hosts=("$APP_SERVER" "$MONITORING_SERVER" "8.8.8.8")
    local host_names=("Application Server" "Monitoring Server" "Google DNS")

    for i in "${!hosts[@]}"; do
        local host="${hosts[$i]}"
        local name="${host_names[$i]}"

        # Ping test (3 packets)
        local ping_result=$(ping -c 3 -W 2 "$host" 2>/dev/null || echo "FAILED")

        if [[ "$ping_result" != "FAILED" ]]; then
            local avg_latency=$(echo "$ping_result" | grep "avg" | awk -F'/' '{print $5}')
            local packet_loss=$(echo "$ping_result" | grep "packet loss" | awk '{print $(NF-4)}')

            log_success "$name ($host) - ${avg_latency}ms avg, ${packet_loss} loss"
        else
            log_error "$name ($host) - Ping failed"
        fi
    done
}

test_external_apis() {
    log_section "External API Connectivity"

    # Test common external services
    local services=(
        "https://packagist.org|Packagist (Composer)"
        "https://github.com|GitHub"
        "https://api.github.com|GitHub API"
    )

    for service in "${services[@]}"; do
        local url=$(echo "$service" | cut -d'|' -f1)
        local name=$(echo "$service" | cut -d'|' -f2)

        local start=$(date +%s%N)
        local http_code=$(curl -sSL -w "%{http_code}" -o /dev/null -m 5 "$url" 2>/dev/null || echo "000")
        local end=$(date +%s%N)
        local latency=$(( (end - start) / 1000000 ))

        if [[ "$http_code" == "200" ]] || [[ "$http_code" == "301" ]] || [[ "$http_code" == "302" ]]; then
            log_success "$name - ${latency}ms"
        else
            log_error "$name - HTTP $http_code"
        fi
    done
}

###############################################################################
# MAIN EXECUTION
###############################################################################

main() {
    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║            CHOM Connection Test Tool                          ║"
    echo "║            Testing all critical connections...                ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Test SSH
    log_section "SSH Connectivity"
    test_ssh_connection "$APP_SERVER" "Application Server SSH"
    test_ssh_connection "$MONITORING_SERVER" "Monitoring Server SSH"

    # Test services
    test_database_connection
    test_redis_connection
    test_dns_resolution
    test_http_connectivity
    test_ssl_certificate
    test_network_latency
    test_external_apis

    echo ""
    echo -e "${GREEN}${BOLD}Connection testing complete${NC}"
}

main "$@"
