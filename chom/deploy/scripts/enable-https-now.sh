#!/bin/bash
#
# Enable HTTPS - Quick Script
# Run this to enable HTTPS on both servers
#

set -euo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then
    log_error "Please run with sudo"
    exit 1
fi

# Get domain from user
read -p "Domain for Grafana (e.g., mentat.arewel.com): " GRAFANA_DOMAIN
read -p "Email for Let's Encrypt: " EMAIL

log_info "Installing certbot..."
apt-get update -qq
apt-get install -y -qq certbot python3-certbot-nginx

log_info "Obtaining SSL certificate for $GRAFANA_DOMAIN..."
certbot --nginx --non-interactive --agree-tos --email "$EMAIL" -d "$GRAFANA_DOMAIN" --redirect

log_success "HTTPS enabled!"
log_info "Testing: https://$GRAFANA_DOMAIN"

systemctl reload nginx

echo ""
echo "✓ HTTPS is now active"
echo "  Access: https://$GRAFANA_DOMAIN"
echo ""
