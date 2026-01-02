#!/bin/bash

# Quick Deployment Test Script
# Runs a subset of critical deployment tests for fast validation
#
# Usage: ./quick-deployment-test.sh [--container landsraad_tst]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_CONTAINER="${TEST_CONTAINER:-landsraad_tst}"
TEST_CONTAINER_IP="${TEST_CONTAINER_IP:-10.10.100.20}"
TEST_SSH_USER="${TEST_SSH_USER:-root}"
CHOM_PATH="/opt/chom"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

log_success() {
    echo -e "${GREEN}✓${NC} $1"
    PASSED=$((PASSED + 1))
}

log_error() {
    echo -e "${RED}✗${NC} $1"
    FAILED=$((FAILED + 1))
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

ssh_exec() {
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${TEST_SSH_USER}@${TEST_CONTAINER_IP}" "$@"
}

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  QUICK DEPLOYMENT TEST SUITE${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Test 1: SSH Connectivity
log_info "Test 1: SSH connectivity to ${TEST_CONTAINER_IP}"
if ssh_exec "echo 'OK'" > /dev/null 2>&1; then
    log_success "SSH connectivity working"
else
    log_error "SSH connectivity failed"
fi

# Test 2: CHOM Installation
log_info "Test 2: CHOM installation"
if ssh_exec "test -d ${CHOM_PATH} && test -f ${CHOM_PATH}/artisan"; then
    log_success "CHOM installed at ${CHOM_PATH}"
else
    log_error "CHOM not found at ${CHOM_PATH}"
fi

# Test 3: Pre-deployment Check Script
log_info "Test 3: Pre-deployment check script"
if ssh_exec "cd ${CHOM_PATH} && timeout 30 bash scripts/pre-deployment-check.sh" > /dev/null 2>&1; then
    log_success "Pre-deployment checks pass"
else
    log_error "Pre-deployment checks failed"
fi

# Test 4: Health Check Script
log_info "Test 4: Health check script"
if ssh_exec "cd ${CHOM_PATH} && timeout 45 bash scripts/health-check.sh" > /dev/null 2>&1; then
    log_success "Health checks pass"
else
    log_error "Health checks failed"
fi

# Test 5: Deployment Script Syntax
log_info "Test 5: Deployment script syntax"
if ssh_exec "cd ${CHOM_PATH} && bash -n scripts/deploy-production.sh"; then
    log_success "Production deployment script syntax OK"
else
    log_error "Production deployment script has syntax errors"
fi

# Test 6: Rollback Script Syntax
log_info "Test 6: Rollback script syntax"
if ssh_exec "cd ${CHOM_PATH} && bash -n scripts/rollback.sh"; then
    log_success "Rollback script syntax OK"
else
    log_error "Rollback script has syntax errors"
fi

# Test 7: Blue-Green Script Syntax
log_info "Test 7: Blue-green deployment script syntax"
if ssh_exec "cd ${CHOM_PATH} && bash -n scripts/deploy-blue-green.sh"; then
    log_success "Blue-green script syntax OK"
else
    log_error "Blue-green script has syntax errors"
fi

# Test 8: Database Connectivity
log_info "Test 8: Database connectivity"
if ssh_exec "cd ${CHOM_PATH} && php artisan db:show > /dev/null 2>&1"; then
    log_success "Database connection OK"
else
    log_error "Database connection failed"
fi

# Test 9: Redis Connectivity
log_info "Test 9: Redis connectivity"
if ssh_exec "cd ${CHOM_PATH} && php artisan tinker --execute='Redis::ping();' 2>/dev/null | grep -q PONG"; then
    log_success "Redis connection OK"
else
    log_error "Redis connection failed"
fi

# Test 10: Maintenance Mode Toggle
log_info "Test 10: Maintenance mode toggle"
if ssh_exec "cd ${CHOM_PATH} && php artisan down --retry=10 && php artisan up"; then
    log_success "Maintenance mode works"
else
    log_error "Maintenance mode failed"
fi

# Summary
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  SUMMARY${NC}"
echo -e "${BLUE}=========================================${NC}"
echo "Total Tests: $((PASSED + FAILED))"
echo -e "${GREEN}Passed: ${PASSED}${NC}"
echo -e "${RED}Failed: ${FAILED}${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}ALL CRITICAL TESTS PASSED${NC}"
    echo "Ready for comprehensive testing"
    exit 0
else
    echo -e "${RED}SOME TESTS FAILED${NC}"
    echo "Fix issues before running full test suite"
    exit 1
fi
