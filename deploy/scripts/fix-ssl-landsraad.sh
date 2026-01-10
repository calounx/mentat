#!/bin/bash
# ============================================================================
# Fix SSL Certificate for landsraad.arewel.com
# ============================================================================
# Purpose: Expand SSL certificate to include both chom.arewel.com and landsraad.arewel.com
# Approach: Use certbot --expand to add landsraad.arewel.com to existing certificate
# ============================================================================

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

log_info "Starting SSL certificate fix for landsraad.arewel.com..."
echo ""

# Step 1: Check current certificate
log_info "Step 1: Checking current certificate..."
if certbot certificates | grep -q "chom.arewel.com"; then
    log_success "Found existing certificate for chom.arewel.com"
    certbot certificates | grep -A 10 "chom.arewel.com"
else
    log_error "No existing certificate found for chom.arewel.com"
    exit 1
fi

echo ""

# Step 2: Expand certificate to include landsraad.arewel.com
log_info "Step 2: Expanding certificate to include landsraad.arewel.com..."
log_warning "This will add landsraad.arewel.com to the existing certificate"
echo ""

# Expand the certificate
certbot certonly \
    --webroot \
    --webroot-path /var/www/html \
    --expand \
    --non-interactive \
    --agree-tos \
    --domains chom.arewel.com,landsraad.arewel.com

if [[ $? -eq 0 ]]; then
    log_success "Certificate expanded successfully"
else
    log_error "Failed to expand certificate"
    log_info "Troubleshooting:"
    log_info "  1. Ensure DNS for landsraad.arewel.com points to this server"
    log_info "  2. Ensure port 80 is accessible for ACME challenge"
    log_info "  3. Check nginx configuration allows .well-known/acme-challenge/"
    exit 1
fi

echo ""

# Step 3: Update nginx configuration to accept both domains
log_info "Step 3: Updating nginx configuration..."

NGINX_CONFIG="/etc/nginx/sites-available/chom"

if [[ ! -f "$NGINX_CONFIG" ]]; then
    log_error "Nginx configuration not found: $NGINX_CONFIG"
    exit 1
fi

# Backup current configuration
cp "$NGINX_CONFIG" "${NGINX_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
log_success "Created configuration backup"

# Update server_name directives to include both domains
sed -i 's/server_name chom\.arewel\.com;/server_name chom.arewel.com landsraad.arewel.com;/g' "$NGINX_CONFIG"

log_success "Updated nginx configuration to accept both domains"

echo ""

# Step 4: Test nginx configuration
log_info "Step 4: Testing nginx configuration..."

if nginx -t; then
    log_success "Nginx configuration test passed"
else
    log_error "Nginx configuration test failed"
    log_info "Restoring backup configuration..."
    cp "${NGINX_CONFIG}.backup."* "$NGINX_CONFIG"
    exit 1
fi

echo ""

# Step 5: Reload nginx
log_info "Step 5: Reloading nginx..."

systemctl reload nginx

if [[ $? -eq 0 ]]; then
    log_success "Nginx reloaded successfully"
else
    log_error "Failed to reload nginx"
    exit 1
fi

echo ""

# Step 6: Verify the fix
log_info "Step 6: Verifying SSL certificate..."

# Check certificate details
log_info "Certificate details:"
certbot certificates | grep -A 15 "chom.arewel.com"

echo ""

# Test SSL connection for both domains
log_info "Testing SSL connection for chom.arewel.com..."
echo "" | timeout 5 openssl s_client -connect chom.arewel.com:443 -servername chom.arewel.com 2>/dev/null | grep -E "subject=|issuer=" || log_warning "Connection test inconclusive"

echo ""

log_info "Testing SSL connection for landsraad.arewel.com..."
echo "" | timeout 5 openssl s_client -connect landsraad.arewel.com:443 -servername landsraad.arewel.com 2>/dev/null | grep -E "subject=|issuer=" || log_warning "Connection test inconclusive"

echo ""
echo "=============================================="
log_success "SSL Certificate Fix Complete!"
echo "=============================================="
echo ""
log_info "Summary:"
echo "  ✓ Certificate expanded to include both domains"
echo "  ✓ Nginx configuration updated"
echo "  ✓ Nginx reloaded successfully"
echo ""
log_info "Both domains now use the same SSL certificate:"
echo "  - https://chom.arewel.com"
echo "  - https://landsraad.arewel.com"
echo ""
log_info "Certificate location:"
echo "  /etc/letsencrypt/live/chom.arewel.com/"
echo ""
log_info "Verify in browser:"
echo "  1. Visit https://landsraad.arewel.com"
echo "  2. Check certificate details (should show both domains)"
echo "  3. No security warnings should appear"
echo ""
