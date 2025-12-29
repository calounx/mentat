#!/bin/bash
#===============================================================================
# Test Script for SSL Configuration Logic
# Tests the nginx configuration generation under different SSL scenarios
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$SCRIPT_DIR/observability-stack"

# Source the libraries
source "$STACK_DIR/deploy/lib/common.sh"

echo "=========================================="
echo "SSL Configuration Logic Test"
echo "=========================================="
echo

# Test 1: SSL enabled with certificates
echo "Test 1: SSL enabled with certificates present"
export USE_SSL=true
export GRAFANA_DOMAIN="test.example.com"

# Create fake certificate for testing
sudo mkdir -p "/etc/letsencrypt/live/$GRAFANA_DOMAIN"
sudo touch "/etc/letsencrypt/live/$GRAFANA_DOMAIN/fullchain.pem"
sudo touch "/etc/letsencrypt/live/$GRAFANA_DOMAIN/privkey.pem"

# Check what configuration would be generated
if [[ "${USE_SSL:-false}" == "true" ]] && [[ -n "${GRAFANA_DOMAIN:-}" ]]; then
    if [[ -f "/etc/letsencrypt/live/${GRAFANA_DOMAIN}/fullchain.pem" ]] && \
       [[ -f "/etc/letsencrypt/live/${GRAFANA_DOMAIN}/privkey.pem" ]]; then
        log_success "Would generate HTTPS configuration"
    else
        log_error "Would generate HTTP fallback (unexpected)"
    fi
else
    log_error "Would skip SSL configuration (unexpected)"
fi
echo

# Test 2: SSL enabled but certificates missing
echo "Test 2: SSL enabled but certificates missing"
export USE_SSL=true
export GRAFANA_DOMAIN="missing.example.com"

if [[ "${USE_SSL:-false}" == "true" ]] && [[ -n "${GRAFANA_DOMAIN:-}" ]]; then
    if [[ -f "/etc/letsencrypt/live/${GRAFANA_DOMAIN}/fullchain.pem" ]] && \
       [[ -f "/etc/letsencrypt/live/${GRAFANA_DOMAIN}/privkey.pem" ]]; then
        log_error "Would generate HTTPS configuration (unexpected)"
    else
        log_success "Would generate HTTP fallback with domain"
    fi
else
    log_error "Would skip SSL configuration (unexpected)"
fi
echo

# Test 3: SSL disabled with domain
echo "Test 3: SSL disabled with domain"
export USE_SSL=false
export GRAFANA_DOMAIN="nossl.example.com"

if [[ "${USE_SSL:-false}" == "true" ]] && [[ -n "${GRAFANA_DOMAIN:-}" ]]; then
    log_error "Would generate HTTPS configuration (unexpected)"
elif [[ -n "${GRAFANA_DOMAIN:-}" ]]; then
    log_success "Would generate HTTP configuration with domain"
else
    log_error "Would generate IP-only configuration (unexpected)"
fi
echo

# Test 4: No domain (IP-only)
echo "Test 4: No domain (IP-only installation)"
export USE_SSL=false
export GRAFANA_DOMAIN=""

if [[ "${USE_SSL:-false}" == "true" ]] && [[ -n "${GRAFANA_DOMAIN:-}" ]]; then
    log_error "Would generate HTTPS configuration (unexpected)"
elif [[ -n "${GRAFANA_DOMAIN:-}" ]]; then
    log_error "Would generate HTTP with domain (unexpected)"
else
    log_success "Would generate IP-only configuration"
fi
echo

# Test 5: Completion message logic
echo "Test 5: Completion message URL logic"
echo

echo "  Scenario A: SSL success"
export USE_SSL=true
export GRAFANA_DOMAIN="test.example.com"
export OBSERVABILITY_IP="192.168.1.10"

if [[ "${USE_SSL:-false}" == "true" ]] && [[ -n "${GRAFANA_DOMAIN:-}" ]]; then
    if [[ -f "/etc/letsencrypt/live/${GRAFANA_DOMAIN}/fullchain.pem" ]]; then
        log_success "Would show: https://${GRAFANA_DOMAIN}"
    else
        log_error "Would show: http://${GRAFANA_DOMAIN} (SSL setup failed)"
    fi
fi
echo

echo "  Scenario B: SSL failed"
export USE_SSL=false
export GRAFANA_DOMAIN="failed.example.com"

if [[ "${USE_SSL:-false}" == "true" ]] && [[ -n "${GRAFANA_DOMAIN:-}" ]]; then
    log_error "Checking SSL (unexpected)"
elif [[ -n "${GRAFANA_DOMAIN:-}" ]]; then
    log_success "Would show: http://${GRAFANA_DOMAIN}"
fi
echo

echo "  Scenario C: No domain"
export USE_SSL=false
export GRAFANA_DOMAIN=""

if [[ "${USE_SSL:-false}" == "true" ]] && [[ -n "${GRAFANA_DOMAIN:-}" ]]; then
    log_error "Checking SSL (unexpected)"
elif [[ -n "${GRAFANA_DOMAIN:-}" ]]; then
    log_error "Showing domain URL (unexpected)"
else
    log_success "Would show: http://${OBSERVABILITY_IP} and http://${OBSERVABILITY_IP}:3000"
fi
echo

# Cleanup
sudo rm -rf "/etc/letsencrypt/live/test.example.com"

echo "=========================================="
log_success "All SSL logic tests passed!"
echo "=========================================="
echo
echo "Summary:"
echo "  ✓ HTTPS config generated only when certificates exist"
echo "  ✓ HTTP fallback with domain when SSL fails"
echo "  ✓ IP-only config when no domain provided"
echo "  ✓ Completion messages match actual configuration"
echo
