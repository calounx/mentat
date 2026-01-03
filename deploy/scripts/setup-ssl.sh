#!/usr/bin/env bash
# Setup Let's Encrypt SSL certificates
# Usage: ./setup-ssl.sh --domain chom.example.com --email admin@example.com

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utils/logging.sh"

# Default values
DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"
WEBROOT="${WEBROOT:-/var/www/html}"
STAGING="${STAGING:-false}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --email)
            EMAIL="$2"
            shift 2
            ;;
        --webroot)
            WEBROOT="$2"
            shift 2
            ;;
        --staging)
            STAGING=true
            shift
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$DOMAIN" ]]; then
    log_fatal "Domain is required. Usage: $0 --domain example.com --email admin@example.com"
fi

if [[ -z "$EMAIL" ]]; then
    log_fatal "Email is required. Usage: $0 --domain example.com --email admin@example.com"
fi

init_deployment_log "ssl-setup-$(date +%Y%m%d_%H%M%S)"
log_section "SSL Certificate Setup"

# Install Certbot
install_certbot() {
    log_step "Installing Certbot"

    if command -v certbot &> /dev/null; then
        log_success "Certbot is already installed"
        return 0
    fi

    # Install snapd if not present
    if ! command -v snap &> /dev/null; then
        log_info "Installing snapd..."
        sudo apt-get update
        sudo apt-get install -y snapd
        sudo systemctl enable --now snapd.socket
        sudo ln -sf /var/lib/snapd/snap /snap
    fi

    # Install certbot via snap
    log_info "Installing certbot via snap..."
    sudo snap install --classic certbot
    sudo ln -sf /snap/bin/certbot /usr/bin/certbot

    log_success "Certbot installed"
}

# Create webroot directory
create_webroot() {
    log_step "Creating webroot directory"

    if [[ ! -d "$WEBROOT" ]]; then
        sudo mkdir -p "$WEBROOT"
        sudo chown -R www-data:www-data "$WEBROOT"
        sudo chmod -R 755 "$WEBROOT"
        log_success "Webroot directory created: $WEBROOT"
    else
        log_success "Webroot directory already exists: $WEBROOT"
    fi
}

# Obtain SSL certificate
obtain_certificate() {
    log_step "Obtaining SSL certificate for $DOMAIN"

    local certbot_args=(
        "certonly"
        "--webroot"
        "-w" "$WEBROOT"
        "-d" "$DOMAIN"
        "--email" "$EMAIL"
        "--agree-tos"
        "--non-interactive"
        "--expand"
    )

    if [[ "$STAGING" == "true" ]]; then
        log_warning "Using Let's Encrypt staging environment"
        certbot_args+=("--staging")
    fi

    if sudo certbot "${certbot_args[@]}" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "SSL certificate obtained successfully"
    else
        local exit_code=$?
        log_error "Failed to obtain SSL certificate (exit code: $exit_code)"
        return $exit_code
    fi
}

# Setup auto-renewal
setup_auto_renewal() {
    log_step "Setting up auto-renewal"

    # Certbot snap includes automatic renewal
    sudo certbot renew --dry-run 2>&1 | tee -a "$LOG_FILE"

    if [[ $? -eq 0 ]]; then
        log_success "Auto-renewal configured and tested successfully"
    else
        log_warning "Auto-renewal test failed, but this might be okay"
    fi

    # Create renewal hook for Nginx reload
    local renewal_hook="/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh"
    sudo mkdir -p "$(dirname "$renewal_hook")"

    sudo tee "$renewal_hook" > /dev/null <<'EOF'
#!/usr/bin/env bash
# Reload Nginx after certificate renewal
systemctl reload nginx
EOF

    sudo chmod +x "$renewal_hook"
    log_success "Nginx reload hook created"
}

# Verify certificate
verify_certificate() {
    log_step "Verifying certificate"

    local cert_path="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"

    if [[ -f "$cert_path" ]]; then
        log_success "Certificate found: $cert_path"

        # Show certificate info
        sudo openssl x509 -in "$cert_path" -noout -text | grep -E "Subject:|Issuer:|Not Before:|Not After:" | tee -a "$LOG_FILE"

        # Show days until expiration
        local expiry_date=$(sudo openssl x509 -in "$cert_path" -noout -enddate | cut -d= -f2)
        local expiry_epoch=$(date -d "$expiry_date" +%s)
        local now_epoch=$(date +%s)
        local days_until_expiry=$(( (expiry_epoch - now_epoch) / 86400 ))

        log_success "Certificate expires in $days_until_expiry days"
    else
        log_error "Certificate not found: $cert_path"
        return 1
    fi
}

# Create Nginx SSL configuration snippet
create_nginx_ssl_config() {
    log_step "Creating Nginx SSL configuration snippet"

    local ssl_config="/etc/nginx/snippets/ssl-${DOMAIN}.conf"

    sudo tee "$ssl_config" > /dev/null <<EOF
# SSL certificate configuration for $DOMAIN
ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

# SSL session configuration
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:50m;
ssl_session_tickets off;

# Modern SSL configuration
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers off;

# OCSP Stapling
ssl_stapling on;
ssl_stapling_verify on;
ssl_trusted_certificate /etc/letsencrypt/live/$DOMAIN/chain.pem;

# Security headers
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
EOF

    log_success "Nginx SSL configuration created: $ssl_config"
    log_info "Include this in your Nginx site config with: include snippets/ssl-${DOMAIN}.conf;"
}

# Main execution
main() {
    start_timer

    install_certbot
    create_webroot
    obtain_certificate
    setup_auto_renewal
    verify_certificate
    create_nginx_ssl_config

    end_timer "SSL setup"

    print_header "SSL Setup Complete"
    log_success "SSL certificate obtained for: $DOMAIN"
    log_success "Certificate path: /etc/letsencrypt/live/$DOMAIN/"
    log_success "Auto-renewal is configured"
    log_info "To renew manually: sudo certbot renew"
    log_info "Nginx SSL config snippet: /etc/nginx/snippets/ssl-${DOMAIN}.conf"
}

main
