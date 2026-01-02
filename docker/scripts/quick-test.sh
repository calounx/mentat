#!/usr/bin/env bash
# ============================================================================
# Quick Test Script - Verify CHOM Docker Environment
# ============================================================================
# This script performs a quick health check of all services
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Change to project root
cd "$PROJECT_ROOT"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}CHOM Docker Environment - Quick Test${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to test a service
test_service() {
    local name=$1
    local url=$2
    local expected_code=${3:-200}

    echo -n "Testing $name... "

    if response=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null); then
        if [ "$response" -eq "$expected_code" ] || [ "$response" -eq 200 ] || [ "$response" -eq 302 ]; then
            echo -e "${GREEN}✓ OK (HTTP $response)${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠ Warning (HTTP $response)${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ Failed${NC}"
        return 1
    fi
}

# Function to check container status
check_container() {
    local name=$1

    echo -n "Checking container $name... "

    if docker ps --filter "name=$name" --filter "status=running" --format "{{.Names}}" | grep -q "$name"; then
        echo -e "${GREEN}✓ Running${NC}"
        return 0
    else
        echo -e "${RED}✗ Not Running${NC}"
        return 1
    fi
}

echo -e "${BLUE}1. Checking Container Status${NC}"
echo "----------------------------"
check_container "chom_web" || true
check_container "chom_observability" || true
echo ""

echo -e "${BLUE}2. Testing Web Services${NC}"
echo "----------------------------"
test_service "CHOM Application" "http://localhost:8000" || true
test_service "Nginx Status" "http://localhost:8080/nginx_status" || true
test_service "PHP-FPM Status" "http://localhost:8080/fpm-status" || true
echo ""

echo -e "${BLUE}3. Testing Observability Services${NC}"
echo "----------------------------"
test_service "Prometheus" "http://localhost:9090/-/healthy" || true
test_service "Grafana" "http://localhost:3000/api/health" || true
test_service "Loki" "http://localhost:3100/ready" || true
test_service "Alertmanager" "http://localhost:9093/-/healthy" || true
echo ""

echo -e "${BLUE}4. Testing Metrics Exporters${NC}"
echo "----------------------------"
test_service "Node Exporter (Web)" "http://localhost:9101/metrics" || true
test_service "Nginx Exporter" "http://localhost:9113/metrics" || true
test_service "MySQL Exporter" "http://localhost:9104/metrics" || true
test_service "PHP-FPM Exporter" "http://localhost:9253/metrics" || true
echo ""

echo -e "${BLUE}5. Testing Database Connectivity${NC}"
echo "----------------------------"
echo -n "Testing MySQL... "
if docker exec chom_web mysql -u chom -psecret -e "SELECT 1" chom > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Connected${NC}"
else
    echo -e "${RED}✗ Failed${NC}"
fi

echo -n "Testing Redis... "
if docker exec chom_web redis-cli ping > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Connected${NC}"
else
    echo -e "${RED}✗ Failed${NC}"
fi
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Quick Test Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Access URLs:"
echo "  Application:  http://localhost:8000"
echo "  Grafana:      http://localhost:3000 (admin/admin)"
echo "  Prometheus:   http://localhost:9090"
echo ""
echo "Run './scripts/validate.sh' for comprehensive validation"
