#!/bin/bash
# ============================================================================
# CHOM Docker Test Environment - Validation Script
# ============================================================================
# Validates the Docker environment is properly configured and operational
# ============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}============================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================================================${NC}\n"
}

print_test() {
    echo -e "${BLUE}Testing:${NC} $1"
}

print_pass() {
    echo -e "  ${GREEN}✓ PASS${NC} - $1"
}

print_fail() {
    echo -e "  ${RED}✗ FAIL${NC} - $1"
}

print_info() {
    echo -e "  ${BLUE}i INFO${NC} - $1"
}

# ============================================================================
# Tests
# ============================================================================

print_header "CHOM Docker Test Environment - Validation"

FAILED_TESTS=0
TOTAL_TESTS=0

# Test 1: Web Application HTTP
print_test "Web Application HTTP endpoint"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if curl -f -s http://localhost:8000/health > /dev/null 2>&1; then
    print_pass "Nginx is responding on port 8000"
else
    print_fail "Nginx is not responding on port 8000"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Test 2: PHP-FPM
print_test "PHP-FPM status endpoint"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if curl -f -s http://localhost:8000/fpm-ping > /dev/null 2>&1; then
    print_pass "PHP-FPM is responding"
else
    print_fail "PHP-FPM is not responding"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Test 3: Prometheus
print_test "Prometheus API"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if curl -f -s http://localhost:9090/-/healthy > /dev/null 2>&1; then
    print_pass "Prometheus is healthy"
else
    print_fail "Prometheus is not healthy"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Test 4: Prometheus targets
print_test "Prometheus target scraping"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
UP_TARGETS=$(curl -s http://localhost:9090/api/v1/targets | grep -o '"health":"up"' | wc -l)
if [ "$UP_TARGETS" -gt 0 ]; then
    print_pass "Prometheus has $UP_TARGETS healthy targets"
else
    print_fail "No healthy Prometheus targets found"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Test 5: Loki
print_test "Loki readiness"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if curl -f -s http://localhost:3100/ready > /dev/null 2>&1; then
    print_pass "Loki is ready"
else
    print_fail "Loki is not ready"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Test 6: Grafana
print_test "Grafana API"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if curl -f -s http://localhost:3000/api/health > /dev/null 2>&1; then
    print_pass "Grafana is healthy"
else
    print_fail "Grafana is not healthy"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Test 7: Node Exporter (Web)
print_test "Node Exporter (Web Application)"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if curl -f -s http://localhost:9101/metrics > /dev/null 2>&1; then
    print_pass "Node Exporter is responding"
else
    print_fail "Node Exporter is not responding"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Test 8: Nginx Exporter
print_test "Nginx Exporter"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if curl -f -s http://localhost:9113/metrics > /dev/null 2>&1; then
    print_pass "Nginx Exporter is responding"
else
    print_fail "Nginx Exporter is not responding"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Test 9: MySQL Exporter
print_test "MySQL Exporter"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if curl -f -s http://localhost:9104/metrics > /dev/null 2>&1; then
    print_pass "MySQL Exporter is responding"
else
    print_fail "MySQL Exporter is not responding"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Test 10: PHP-FPM Exporter
print_test "PHP-FPM Exporter"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if curl -f -s http://localhost:9253/metrics > /dev/null 2>&1; then
    print_pass "PHP-FPM Exporter is responding"
else
    print_fail "PHP-FPM Exporter is not responding"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Test 11: Container health
print_test "Docker container health"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
UNHEALTHY=$(docker ps --filter "health=unhealthy" --format "{{.Names}}" | wc -l)
if [ "$UNHEALTHY" -eq 0 ]; then
    print_pass "All containers are healthy"
else
    print_fail "$UNHEALTHY containers are unhealthy"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Test 12: Network connectivity (web -> observability)
print_test "Network connectivity (web to observability)"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if docker exec chom_web ping -c 1 chom_observability > /dev/null 2>&1; then
    print_pass "Web can reach observability stack"
else
    print_fail "Web cannot reach observability stack"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Test 13: Laravel application
print_test "Laravel application"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if docker exec chom_web test -f /var/www/chom/artisan; then
    print_pass "Laravel application is mounted"
    # Check if .env exists
    if docker exec chom_web test -f /var/www/chom/.env; then
        print_info ".env file exists"
    else
        print_info ".env file not found (will be created on startup)"
    fi
else
    print_fail "Laravel application not found at /var/www/chom"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Summary
print_header "Validation Summary"

echo -e "${BLUE}Total Tests:${NC} $TOTAL_TESTS"
echo -e "${GREEN}Passed:${NC}      $((TOTAL_TESTS - FAILED_TESTS))"
echo -e "${RED}Failed:${NC}      $FAILED_TESTS"

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "\n${GREEN}✓ All validation tests passed!${NC}\n"
    echo -e "${GREEN}Your CHOM Docker test environment is fully operational.${NC}\n"
    exit 0
else
    echo -e "\n${RED}✗ Some validation tests failed.${NC}\n"
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo -e "  1. Check service logs: ${BLUE}docker-compose logs${NC}"
    echo -e "  2. Check container status: ${BLUE}docker-compose ps${NC}"
    echo -e "  3. Restart services: ${BLUE}docker-compose restart${NC}"
    echo -e "  4. See README.md for detailed troubleshooting\n"
    exit 1
fi
