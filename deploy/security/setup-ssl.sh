#!/bin/bash
# ============================================================================
# SSL/TLS Certificate Setup Script
# ============================================================================
# Purpose: Configure Let's Encrypt SSL certificates with A+ security rating
# Targets: landsraad.arewel.com and mentat.arewel.com
# Features: Auto-renewal, HSTS, OCSP stapling, strong ciphers
# Compliance: PCI DSS, SOC 2, OWASP
# ============================================================================

set -euo pipefail
# Dependency validation - MUST run before doing anything else
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Validate dependencies
validate_deployment_dependencies() {
    local script_dir="$1"
    local deploy_root="$2"
    local script_name="$(basename "$0")"
    local errors=()

    if [[ ! -d "$deploy_root" ]]; then
        errors+=("Deploy root directory not found: $deploy_root")
    fi

    local security_dir="${deploy_root}/security"
    if [[ ! -d "$security_dir" ]]; then
        errors+=("Security directory not found: $security_dir")
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "" >&2
        echo "ERROR: Missing required dependencies for ${script_name}" >&2
        echo "" >&2
        echo "Script location: ${script_dir}" >&2
        echo "Deploy root: ${deploy_root}" >&2
        echo "" >&2
        echo "Missing dependencies:" >&2
        for error in "${errors[@]}"; do
            echo "  - ${error}" >&2
        done
        echo "" >&2
        echo "Run from repository root: sudo ./deploy/security/${script_name}" >&2
        exit 1
    fi
}

validate_deployment_dependencies "$SCRIPT_DIR" "$DEPLOY_ROOT"

# Configuration
DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"
WEBROOT="${WEBROOT:-/var/www/html}"
NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
CERTBOT_DIR="/etc/letsencrypt"
SSL_DHPARAM="/etc/ssl/certs/dhparam.pem"
RENEWAL_HOOK_DIR="/etc/letsencrypt/renewal-hooks"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
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
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Detect domain from hostname
detect_domain() {
    if [[ -z "$DOMAIN" ]]; then
        local hostname=$(hostname -f)
        log_info "Detected domain from hostname: $hostname"

        read -p "Use this domain? (yes/no/custom): " -r choice

        case $choice in
            yes|y|Y)
                DOMAIN="$hostname"
                ;;
            custom|c|C)
                read -p "Enter domain name: " -r DOMAIN
                ;;
            *)
                log_error "Domain is required"
                exit 1
                ;;
        esac
    fi

    log_success "Domain: $DOMAIN"

    # Get email if not set
    if [[ -z "$EMAIL" ]]; then
        read -p "Enter email for Let's Encrypt notifications: " -r EMAIL
    fi

    log_success "Email: $EMAIL"
}

# Install Certbot
install_certbot() {
    log_info "Installing Certbot..."

    # Update package list
    apt-get update -qq

    # Install certbot and nginx plugin
    apt-get install -y certbot python3-certbot-nginx

    log_success "Certbot installed"
}

# Install Nginx if not present
install_nginx() {
    log_info "Checking Nginx installation..."

    if command -v nginx &> /dev/null; then
        log_success "Nginx is already installed"
        return 0
    fi

    log_info "Installing Nginx..."
    apt-get install -y nginx

    # Start and enable Nginx
    systemctl start nginx
    systemctl enable nginx

    log_success "Nginx installed and started"
}

# Generate strong DH parameters
generate_dhparam() {
    log_info "Generating Diffie-Hellman parameters (this may take several minutes)..."

    if [[ -f "$SSL_DHPARAM" ]]; then
        log_warning "DH parameters already exist"
        read -p "Regenerate? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Using existing DH parameters"
            return 0
        fi
    fi

    openssl dhparam -out "$SSL_DHPARAM" 2048

    log_success "DH parameters generated"
}

# Create initial Nginx configuration for HTTP
create_http_config() {
    log_info "Creating initial HTTP Nginx configuration..."

    local config_file="$NGINX_AVAILABLE/$DOMAIN"

    cat > "$config_file" <<EOF
# ============================================================================
# CHOM Initial HTTP Configuration
# Domain: $DOMAIN
# Purpose: Let's Encrypt verification
# ============================================================================

server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    # Root directory for Let's Encrypt verification
    root $WEBROOT;

    # Let's Encrypt verification
    location /.well-known/acme-challenge/ {
        root $WEBROOT;
        allow all;
    }

    # Temporary: redirect everything else to HTTPS (after cert is obtained)
    # location / {
    #     return 301 https://\$server_name\$request_uri;
    # }

    # Access and error logs
    access_log /var/log/nginx/${DOMAIN}_access.log;
    error_log /var/log/nginx/${DOMAIN}_error.log;
}
EOF

    # Enable site
    ln -sf "$config_file" "$NGINX_ENABLED/$DOMAIN"

    # Test Nginx configuration
    if nginx -t; then
        systemctl reload nginx
        log_success "HTTP configuration created and enabled"
    else
        log_error "Nginx configuration test failed"
        return 1
    fi
}

# Obtain SSL certificate
obtain_certificate() {
    log_info "Obtaining SSL certificate from Let's Encrypt..."

    # Create webroot if it doesn't exist
    mkdir -p "$WEBROOT"

    # Obtain certificate using webroot method
    certbot certonly \
        --webroot \
        --webroot-path "$WEBROOT" \
        --email "$EMAIL" \
        --agree-tos \
        --no-eff-email \
        --domain "$DOMAIN" \
        --non-interactive

    if [[ $? -eq 0 ]]; then
        log_success "SSL certificate obtained successfully"
    else
        log_error "Failed to obtain SSL certificate"
        log_info "Troubleshooting steps:"
        log_info "  1. Ensure DNS points to this server"
        log_info "  2. Ensure port 80 is accessible"
        log_info "  3. Check firewall rules"
        log_info "  4. Verify domain ownership"
        exit 1
    fi
}

# Create SSL configuration snippet
create_ssl_snippet() {
    log_info "Creating SSL configuration snippet..."

    local ssl_snippet="/etc/nginx/snippets/ssl-${DOMAIN}.conf"
    local security_snippet="/etc/nginx/snippets/ssl-security.conf"

    # Certificate paths snippet
    cat > "$ssl_snippet" <<EOF
# SSL Certificate Configuration for $DOMAIN
ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
ssl_trusted_certificate /etc/letsencrypt/live/$DOMAIN/chain.pem;
EOF

    # Security configuration snippet (reusable)
    cat > "$security_snippet" <<'EOF'
# ============================================================================
# SSL/TLS Security Configuration
# Target: SSL Labs A+ Rating
# Standards: PCI DSS, OWASP, SOC 2
# ============================================================================

# SSL Protocols (TLS 1.2 and 1.3 only)
ssl_protocols TLSv1.2 TLSv1.3;

# Strong Cipher Suites (prioritize AEAD ciphers)
ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';

# Prefer server ciphers
ssl_prefer_server_ciphers on;

# Diffie-Hellman parameters for perfect forward secrecy
ssl_dhparam /etc/ssl/certs/dhparam.pem;

# Session Cache and Timeout
ssl_session_cache shared:SSL:50m;
ssl_session_timeout 1d;
ssl_session_tickets off;

# OCSP Stapling (verify certificate validity)
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;

# Security Headers
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

# Content Security Policy (customize per application)
# add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline';" always;
EOF

    log_success "SSL configuration snippets created"
}

# Create HTTPS Nginx configuration
create_https_config() {
    log_info "Creating HTTPS Nginx configuration..."

    local config_file="$NGINX_AVAILABLE/$DOMAIN"

    cat > "$config_file" <<EOF
# ============================================================================
# CHOM Secure HTTPS Configuration
# Domain: $DOMAIN
# Security: SSL Labs A+ Rating
# ============================================================================

# HTTP to HTTPS Redirect
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    # Let's Encrypt verification
    location /.well-known/acme-challenge/ {
        root $WEBROOT;
        allow all;
    }

    # Redirect all HTTP to HTTPS
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# HTTPS Server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;

    # SSL Configuration
    include snippets/ssl-${DOMAIN}.conf;
    include snippets/ssl-security.conf;

    # Root directory
    root $WEBROOT;
    index index.php index.html index.htm;

    # Client body size limit
    client_max_body_size 100M;

    # Logging
    access_log /var/log/nginx/${DOMAIN}_ssl_access.log;
    error_log /var/log/nginx/${DOMAIN}_ssl_error.log;

    # Security: Hide Nginx version
    server_tokens off;

    # PHP-FPM Configuration (adjust socket path as needed)
    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;

        # Security headers for PHP
        fastcgi_hide_header X-Powered-By;
    }

    # Laravel Public Directory (if applicable)
    # location / {
    #     try_files \$uri \$uri/ /index.php?\$query_string;
    # }

    # Deny access to sensitive files
    location ~ /\.(?!well-known).* {
        deny all;
    }

    # Deny access to backup files
    location ~* \.(bak|config|sql|fla|psd|ini|log|sh|inc|swp|dist)$ {
        deny all;
    }

    # Cache static assets
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

    # Test Nginx configuration
    if nginx -t; then
        systemctl reload nginx
        log_success "HTTPS configuration created and enabled"
    else
        log_error "Nginx configuration test failed"
        return 1
    fi
}

# Setup auto-renewal
setup_auto_renewal() {
    log_info "Setting up certificate auto-renewal..."

    # Test renewal process (dry run)
    certbot renew --dry-run

    if [[ $? -eq 0 ]]; then
        log_success "Auto-renewal test successful"
    else
        log_warning "Auto-renewal test failed, but continuing..."
    fi

    # Create renewal hook to reload Nginx
    mkdir -p "$RENEWAL_HOOK_DIR/deploy"

    cat > "$RENEWAL_HOOK_DIR/deploy/reload-nginx.sh" <<'EOF'
#!/bin/bash
# Reload Nginx after certificate renewal
systemctl reload nginx
EOF

    chmod +x "$RENEWAL_HOOK_DIR/deploy/reload-nginx.sh"

    # Certbot creates a systemd timer automatically
    systemctl list-timers | grep certbot && log_success "Certbot renewal timer is active" || log_warning "Certbot renewal timer not found"
}

# Test SSL configuration with SSL Labs
test_ssl_config() {
    log_info "SSL Configuration Test..."
    echo ""

    log_info "Testing SSL certificate..."
    echo "" | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null | openssl x509 -noout -dates

    echo ""
    log_info "SSL Configuration Summary:"
    echo "  Domain: $DOMAIN"
    echo "  Certificate: /etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    echo "  Private Key: /etc/letsencrypt/live/$DOMAIN/privkey.pem"
    echo "  Protocol: TLS 1.2, TLS 1.3"
    echo "  HSTS: Enabled (2 years)"
    echo "  OCSP Stapling: Enabled"
    echo ""

    log_info "Online SSL Test:"
    echo "  SSL Labs: https://www.ssllabs.com/ssltest/analyze.html?d=$DOMAIN"
    echo "  Expected Rating: A+"
    echo ""
}

# Create SSL management helper
create_ssl_helper() {
    log_info "Creating SSL management helper..."

    local helper_script="/usr/local/bin/chom-ssl"

    cat > "$helper_script" <<'EOF'
#!/bin/bash
# CHOM SSL Certificate Management

case "$1" in
    status)
        certbot certificates
        ;;
    renew)
        certbot renew
        ;;
    test-renew)
        certbot renew --dry-run
        ;;
    info)
        if [[ -z "$2" ]]; then
            echo "Usage: chom-ssl info <domain>"
            exit 1
        fi
        openssl x509 -in "/etc/letsencrypt/live/$2/cert.pem" -text -noout
        ;;
    expiry)
        if [[ -z "$2" ]]; then
            echo "Usage: chom-ssl expiry <domain>"
            exit 1
        fi
        openssl x509 -in "/etc/letsencrypt/live/$2/cert.pem" -noout -dates
        ;;
    test)
        if [[ -z "$2" ]]; then
            echo "Usage: chom-ssl test <domain>"
            exit 1
        fi
        echo "" | openssl s_client -connect "$2:443" -servername "$2"
        ;;
    revoke)
        if [[ -z "$2" ]]; then
            echo "Usage: chom-ssl revoke <domain>"
            exit 1
        fi
        read -p "Are you sure you want to revoke the certificate for $2? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            certbot revoke --cert-path "/etc/letsencrypt/live/$2/cert.pem"
        fi
        ;;
    *)
        echo "CHOM SSL Certificate Management"
        echo ""
        echo "Usage: chom-ssl <command> [args]"
        echo ""
        echo "Commands:"
        echo "  status              Show all certificates"
        echo "  renew               Renew all certificates"
        echo "  test-renew          Test renewal process (dry run)"
        echo "  info <domain>       Show certificate details"
        echo "  expiry <domain>     Show expiration dates"
        echo "  test <domain>       Test SSL connection"
        echo "  revoke <domain>     Revoke certificate"
        echo ""
        ;;
esac
EOF

    chmod +x "$helper_script"
    log_success "SSL helper created: $helper_script"
}

# Verify certificate
verify_certificate() {
    log_info "Verifying SSL certificate installation..."

    local cert_path="/etc/letsencrypt/live/$DOMAIN/cert.pem"

    if [[ ! -f "$cert_path" ]]; then
        log_error "Certificate not found at $cert_path"
        return 1
    fi

    # Check certificate validity
    if openssl x509 -in "$cert_path" -noout -checkend 0; then
        log_success "Certificate is valid"
    else
        log_error "Certificate is expired or invalid"
        return 1
    fi

    # Check certificate domain
    local cert_domain=$(openssl x509 -in "$cert_path" -noout -subject | sed -n 's/.*CN=\(.*\)/\1/p')
    if [[ "$cert_domain" == "$DOMAIN" ]]; then
        log_success "Certificate domain matches: $DOMAIN"
    else
        log_warning "Certificate domain mismatch: $cert_domain vs $DOMAIN"
    fi

    return 0
}

# Display summary
display_summary() {
    echo ""
    log_success "=========================================="
    log_success "SSL/TLS Configuration Complete"
    log_success "=========================================="
    echo ""
    log_info "Domain: $DOMAIN"
    log_info "Certificate Path: /etc/letsencrypt/live/$DOMAIN/"
    echo ""
    log_info "Security Features Enabled:"
    echo "  ✓ TLS 1.2 and TLS 1.3"
    echo "  ✓ Strong cipher suites (AEAD preferred)"
    echo "  ✓ Perfect Forward Secrecy (PFS)"
    echo "  ✓ HSTS with 2-year max-age"
    echo "  ✓ OCSP Stapling"
    echo "  ✓ Security headers (XSS, Clickjacking, etc.)"
    echo "  ✓ Automatic renewal (systemd timer)"
    echo ""
    log_info "SSL Labs Test: https://www.ssllabs.com/ssltest/analyze.html?d=$DOMAIN"
    log_info "Expected Rating: A+"
    echo ""
    log_info "Certificate Management:"
    echo "  chom-ssl status      - Show all certificates"
    echo "  chom-ssl renew       - Renew certificates"
    echo "  chom-ssl expiry $DOMAIN - Check expiration"
    echo ""
}

# Main execution
main() {
    log_info "Starting SSL/TLS certificate setup..."
    echo ""

    check_root
    detect_domain
    install_nginx
    install_certbot
    generate_dhparam
    create_http_config
    obtain_certificate
    create_ssl_snippet
    create_https_config
    setup_auto_renewal
    verify_certificate
    create_ssl_helper
    test_ssl_config
    display_summary

    log_success "SSL/TLS setup complete!"
}

# Run main function
main "$@"
