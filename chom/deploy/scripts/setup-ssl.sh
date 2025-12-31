#!/bin/bash
#
# SSL Certificate Setup Script
# Run this AFTER deployment to enable HTTPS
#
# Prerequisites:
# - Domain DNS must point to server IP
# - Nginx must be running
# - Ports 80 and 443 must be open
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if user has sudo access
if ! sudo -n true 2>/dev/null; then
    log_error "This script requires passwordless sudo access"
    exit 1
fi

echo ""
echo "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo "${CYAN}  CHOM SSL Certificate Setup${NC}"
echo "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Detect which services are running
SERVICES_RUNNING=()
if systemctl is-active --quiet grafana-server; then
    SERVICES_RUNNING+=("observability")
fi
if systemctl is-active --quiet mariadb; then
    SERVICES_RUNNING+=("vpsmanager")
fi

if [ ${#SERVICES_RUNNING[@]} -eq 0 ]; then
    log_error "No CHOM services detected. Please run deployment first."
    exit 1
fi

log_info "Detected services: ${SERVICES_RUNNING[*]}"
echo ""

# Get domain names
read -p "Enter domain for Grafana (e.g., mentat.arewel.com): " GRAFANA_DOMAIN
read -p "Enter email for Let's Encrypt notifications: " EMAIL

# Validate domain resolves to this server
log_info "Validating DNS resolution for $GRAFANA_DOMAIN..."
SERVER_IP=$(hostname -I | awk '{print $1}')
DOMAIN_IP=$(dig +short "$GRAFANA_DOMAIN" | tail -1)

if [ -z "$DOMAIN_IP" ]; then
    log_error "Domain $GRAFANA_DOMAIN does not resolve to any IP"
    log_error "Please configure DNS before running this script"
    exit 1
fi

if [ "$DOMAIN_IP" != "$SERVER_IP" ]; then
    log_warn "Domain resolves to $DOMAIN_IP but server IP is $SERVER_IP"
    read -p "Continue anyway? (y/N): " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        log_info "Aborted by user"
        exit 0
    fi
fi

# Check if certbot is installed
if ! command -v certbot &>/dev/null; then
    log_info "Installing certbot..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq certbot python3-certbot-nginx
fi

# Stop nginx temporarily for certbot standalone mode
log_info "Stopping nginx temporarily..."
sudo systemctl stop nginx

# Obtain certificate
log_info "Requesting SSL certificate for $GRAFANA_DOMAIN..."
sudo certbot certonly \
    --standalone \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    -d "$GRAFANA_DOMAIN" || {
    log_error "Failed to obtain SSL certificate"
    sudo systemctl start nginx
    exit 1
}

# Update nginx configuration
log_info "Updating nginx configuration for HTTPS..."

if [[ " ${SERVICES_RUNNING[*]} " =~ " observability " ]]; then
    # Backup original config
    sudo cp /etc/nginx/sites-available/observability /etc/nginx/sites-available/observability.bak

    # Create new HTTPS-enabled config
    write_system_file() {
        local file="$1"
        sudo tee "$file" > /dev/null
    }

    write_system_file /etc/nginx/sites-available/observability << EOF
# HTTP - Redirect to HTTPS
server {
    listen 80;
    server_name $GRAFANA_DOMAIN;

    # Allow ACME challenge for certificate renewal
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Redirect all other traffic to HTTPS
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# HTTPS - Grafana
server {
    listen 443 ssl http2;
    server_name $GRAFANA_DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$GRAFANA_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$GRAFANA_DOMAIN/privkey.pem;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# Prometheus (internal only - no SSL needed)
server {
    listen 127.0.0.1:9090;
    server_name localhost;

    location / {
        proxy_pass http://127.0.0.1:9090;
    }
}
EOF
fi

# Test nginx configuration
log_info "Testing nginx configuration..."
sudo nginx -t || {
    log_error "Nginx configuration test failed"
    log_info "Restoring backup..."
    sudo cp /etc/nginx/sites-available/observability.bak /etc/nginx/sites-available/observability
    sudo systemctl start nginx
    exit 1
}

# Start nginx
log_info "Starting nginx..."
sudo systemctl start nginx

# Set up automatic renewal
log_info "Setting up automatic certificate renewal..."
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer

# Update Grafana root URL
if [[ " ${SERVICES_RUNNING[*]} " =~ " observability " ]]; then
    log_info "Updating Grafana configuration..."
    sudo sed -i "s|^;root_url =.*|root_url = https://$GRAFANA_DOMAIN|" /etc/grafana/grafana.ini
    sudo sed -i "s|^root_url =.*|root_url = https://$GRAFANA_DOMAIN|" /etc/grafana/grafana.ini
    sudo systemctl restart grafana-server
fi

echo ""
log_success "SSL certificate installed successfully!"
echo ""
echo "${GREEN}Access URLs (HTTPS):${NC}"
echo "  Grafana:     https://$GRAFANA_DOMAIN"
echo "  Prometheus:  http://localhost:9090 (internal only)"
echo ""
echo "${YELLOW}Certificate Details:${NC}"
echo "  Domain:      $GRAFANA_DOMAIN"
echo "  Email:       $EMAIL"
echo "  Expires:     $(sudo certbot certificates | grep "Expiry Date" | head -1)"
echo ""
echo "${YELLOW}Automatic Renewal:${NC}"
echo "  Certificates will renew automatically via certbot.timer"
echo "  Check status: sudo systemctl status certbot.timer"
echo ""
log_info "Test renewal: sudo certbot renew --dry-run"
echo ""
