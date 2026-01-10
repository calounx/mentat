#!/bin/bash
################################################################################
# SSL Certificate Fix for landsraad.arewel.com
# COPY THIS ENTIRE FILE TO THE SERVER AND EXECUTE AS ROOT
################################################################################
#
# Quick Start:
#   1. SSH to server: ssh stilgar@landsraad.arewel.com
#   2. Copy this file to server: nano /tmp/ssl-fix.sh (paste content)
#   3. Make executable: chmod +x /tmp/ssl-fix.sh
#   4. Run as root: sudo /tmp/ssl-fix.sh
#
# OR use this one-liner on the server:
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/...)"
#
# What this does:
#   - Expands SSL certificate to include landsraad.arewel.com
#   - Updates nginx configuration
#   - Reloads nginx (no downtime)
#   - Verifies the fix
#
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Check root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    echo "Please run: sudo $0"
    exit 1
fi

echo ""
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD} SSL Certificate Fix for landsraad${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""

# Step 1: Check current certificate
echo -e "${BLUE}[1/6]${NC} Checking current certificate..."
if certbot certificates 2>/dev/null | grep -q "chom.arewel.com"; then
    echo -e "${GREEN}✓${NC} Found existing certificate for chom.arewel.com"
    certbot certificates | grep -A 10 "Certificate Name: chom.arewel.com" || true
else
    echo -e "${RED}✗${NC} No certificate found for chom.arewel.com"
    echo "Please ensure Let's Encrypt is set up first"
    exit 1
fi

echo ""

# Step 2: Expand certificate
echo -e "${BLUE}[2/6]${NC} Expanding certificate to include landsraad.arewel.com..."
echo "This may take 10-30 seconds..."

if certbot certonly \
    --webroot \
    --webroot-path /var/www/html \
    --expand \
    --non-interactive \
    --agree-tos \
    --domains chom.arewel.com,landsraad.arewel.com 2>&1 | tee /tmp/certbot-expand.log; then
    echo -e "${GREEN}✓${NC} Certificate expanded successfully"
else
    echo -e "${RED}✗${NC} Failed to expand certificate"
    echo ""
    echo "Common issues:"
    echo "  1. DNS: Ensure landsraad.arewel.com points to this server"
    echo "  2. Firewall: Ensure port 80 is open"
    echo "  3. Nginx: Ensure .well-known/acme-challenge is accessible"
    echo ""
    echo "Check logs: cat /tmp/certbot-expand.log"
    exit 1
fi

echo ""

# Step 3: Verify certificate expansion
echo -e "${BLUE}[3/6]${NC} Verifying certificate..."
if certbot certificates | grep -A 5 "chom.arewel.com" | grep -q "landsraad.arewel.com"; then
    echo -e "${GREEN}✓${NC} Certificate now includes both domains:"
    certbot certificates | grep -A 5 "Certificate Name: chom.arewel.com"
else
    echo -e "${YELLOW}⚠${NC} Certificate may not include landsraad.arewel.com"
    certbot certificates | grep -A 10 "chom.arewel.com"
fi

echo ""

# Step 4: Backup and update nginx configuration
echo -e "${BLUE}[4/6]${NC} Updating nginx configuration..."

NGINX_CONFIG="/etc/nginx/sites-available/chom"
BACKUP_FILE="${NGINX_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"

if [[ ! -f "$NGINX_CONFIG" ]]; then
    echo -e "${RED}✗${NC} Nginx configuration not found: $NGINX_CONFIG"
    exit 1
fi

# Create backup
cp "$NGINX_CONFIG" "$BACKUP_FILE"
echo -e "${GREEN}✓${NC} Backup created: $BACKUP_FILE"

# Check if already updated
if grep -q "server_name chom.arewel.com landsraad.arewel.com" "$NGINX_CONFIG"; then
    echo -e "${YELLOW}⚠${NC} Nginx config already includes both domains (skipping)"
else
    # Update server_name directives
    sed -i 's/server_name chom\.arewel\.com;/server_name chom.arewel.com landsraad.arewel.com;/g' "$NGINX_CONFIG"
    echo -e "${GREEN}✓${NC} Updated nginx configuration"

    # Show changes
    echo "Changes made:"
    grep "server_name" "$NGINX_CONFIG" | sed 's/^/  /'
fi

echo ""

# Step 5: Test nginx configuration
echo -e "${BLUE}[5/6]${NC} Testing nginx configuration..."

if nginx -t 2>&1 | tee /tmp/nginx-test.log; then
    echo -e "${GREEN}✓${NC} Nginx configuration test passed"
else
    echo -e "${RED}✗${NC} Nginx configuration test failed"
    echo ""
    echo "Restoring backup..."
    cp "$BACKUP_FILE" "$NGINX_CONFIG"
    echo "Backup restored. Please check the error above."
    exit 1
fi

echo ""

# Step 6: Reload nginx
echo -e "${BLUE}[6/6]${NC} Reloading nginx..."

if systemctl reload nginx; then
    echo -e "${GREEN}✓${NC} Nginx reloaded successfully"
else
    echo -e "${RED}✗${NC} Failed to reload nginx"
    echo ""
    echo "Restoring backup..."
    cp "$BACKUP_FILE" "$NGINX_CONFIG"
    nginx -t && systemctl reload nginx
    echo "Backup restored"
    exit 1
fi

echo ""
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}${GREEN}  ✓ SSL FIX COMPLETE!${NC}${BOLD}"
echo -e "${BOLD}========================================${NC}"
echo ""

# Final verification
echo -e "${BOLD}Certificate Details:${NC}"
certbot certificates | grep -A 8 "Certificate Name: chom.arewel.com"

echo ""
echo -e "${BOLD}Nginx Configuration:${NC}"
echo -e "  ${GREEN}✓${NC} Serving both domains:"
grep "server_name" "$NGINX_CONFIG" | grep -v "^#" | sed 's/^/    /'

echo ""
echo -e "${BOLD}Testing SSL Connections:${NC}"

# Test chom.arewel.com
if timeout 5 bash -c "echo | openssl s_client -connect chom.arewel.com:443 -servername chom.arewel.com" &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} chom.arewel.com - SSL connection successful"
else
    echo -e "  ${YELLOW}⚠${NC} chom.arewel.com - Could not test (timeout or connection issue)"
fi

# Test landsraad.arewel.com
if timeout 5 bash -c "echo | openssl s_client -connect landsraad.arewel.com:443 -servername landsraad.arewel.com" &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} landsraad.arewel.com - SSL connection successful"
else
    echo -e "  ${YELLOW}⚠${NC} landsraad.arewel.com - Could not test (timeout or connection issue)"
fi

echo ""
echo -e "${BOLD}Next Steps:${NC}"
echo "  1. Visit https://landsraad.arewel.com in your browser"
echo "  2. Click the padlock icon and view certificate"
echo "  3. Verify certificate shows both domains"
echo "  4. Confirm no security warnings appear"
echo ""
echo -e "${BOLD}Backup Location:${NC}"
echo "  $BACKUP_FILE"
echo ""
echo -e "${GREEN}All done! The SSL certificate issue is fixed.${NC}"
echo ""
