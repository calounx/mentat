#!/usr/bin/env bash
# SSL management commands for vpsmanager

# Configuration
CERTBOT_EMAIL="${CERTBOT_EMAIL:-admin@example.com}"
NGINX_SITES_AVAILABLE="${NGINX_SITES_AVAILABLE:-/etc/nginx/sites-available}"

# Get SSL certificate info
get_cert_info() {
    local domain="$1"
    local cert_path="/etc/letsencrypt/live/${domain}/cert.pem"

    if [[ ! -f "$cert_path" ]]; then
        echo "{}"
        return 1
    fi

    local expiry_date issuer subject
    expiry_date=$(openssl x509 -enddate -noout -in "$cert_path" 2>/dev/null | cut -d= -f2)
    issuer=$(openssl x509 -issuer -noout -in "$cert_path" 2>/dev/null | sed 's/issuer=//')
    subject=$(openssl x509 -subject -noout -in "$cert_path" 2>/dev/null | sed 's/subject=//')

    # Convert to epoch for comparison
    local expiry_epoch
    expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry_date" +%s 2>/dev/null || echo 0)
    local now_epoch
    now_epoch=$(date +%s)
    local days_remaining=$(( (expiry_epoch - now_epoch) / 86400 ))

    json_object \
        "domain" "$domain" \
        "expiry_date" "$expiry_date" \
        "days_remaining" "$days_remaining" \
        "issuer" "$(json_escape "$issuer")" \
        "cert_path" "$cert_path" \
        "valid" "$([ $days_remaining -gt 0 ] && echo true || echo false)"
}

# Update nginx config for SSL
update_nginx_for_ssl() {
    local domain="$1"
    local nginx_config="${NGINX_SITES_AVAILABLE}/${domain}.conf"

    if [[ ! -f "$nginx_config" ]]; then
        log_error "Nginx config not found: ${nginx_config}"
        return 1
    fi

    # Check if SSL is already configured
    if grep -q "ssl_certificate" "$nginx_config"; then
        log_info "SSL already configured in nginx for ${domain}"
        return 0
    fi

    # Get site info from registry to get PHP version
    local site_info php_version site_root
    site_info=$(get_site_info "$domain")
    if command -v jq &> /dev/null && [[ -n "$site_info" ]]; then
        php_version=$(echo "$site_info" | jq -r '.php_version // "8.2"')
        site_root=$(echo "$site_info" | jq -r '.site_root // empty')
    else
        php_version="${PHP_VERSION:-8.2}"
        # Fallback: get site root from config
        site_root=$(grep -oP 'root\s+\K[^;]+' "$nginx_config" | head -1 | xargs dirname)
    fi

    # If site_root still empty, try to extract from nginx config
    if [[ -z "$site_root" ]]; then
        site_root=$(grep -oP 'root\s+\K[^;]+' "$nginx_config" | head -1 | xargs dirname)
    fi

    log_info "Updating nginx config for SSL: ${domain} (PHP ${php_version})"

    # Create SSL version of config
    cat > "$nginx_config" <<EOF
# HTTP to HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name ${domain} www.${domain};

    location /.well-known/acme-challenge/ {
        root ${site_root}/public;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${domain} www.${domain};

    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    # Modern TLS configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # HSTS
    add_header Strict-Transport-Security "max-age=63072000" always;

    root ${site_root}/public;
    index index.php index.html index.htm;

    access_log ${site_root}/logs/access.log;
    error_log ${site_root}/logs/error.log;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/run/php/php${php_version}-fpm-${domain}.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_hide_header X-Powered-By;
    }

    location ~ /\.(?!well-known) {
        deny all;
    }

    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|svg)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
EOF

    return 0
}

# Update site registry for SSL
update_registry_ssl() {
    local domain="$1"
    local ssl_enabled="$2"

    if command -v jq &> /dev/null && [[ -f "$SITES_REGISTRY" ]]; then
        local temp_file="${SITES_REGISTRY}.tmp"
        jq "(.sites[] | select(.domain == \"${domain}\")).ssl_enabled = ${ssl_enabled}" "$SITES_REGISTRY" > "$temp_file" && mv "$temp_file" "$SITES_REGISTRY"
    fi
}

# ============================================================================
# Command handlers
# ============================================================================

# ssl:issue command
cmd_ssl_issue() {
    local domain="$1"

    if [[ -z "$domain" ]]; then
        json_error "Domain is required" "MISSING_DOMAIN"
        return 1
    fi

    # Validate domain
    local validation_error
    if ! validation_error=$(validate_domain "$domain"); then
        json_error "$validation_error" "INVALID_DOMAIN"
        return 1
    fi

    # Check if site exists
    if ! site_exists "$domain"; then
        json_error "Site not found: ${domain}. Create site first." "SITE_NOT_FOUND"
        return 1
    fi

    # Check if certificate already exists
    if [[ -f "/etc/letsencrypt/live/${domain}/cert.pem" ]]; then
        local cert_info
        cert_info=$(get_cert_info "$domain")
        local days_remaining
        days_remaining=$(echo "$cert_info" | jq -r '.days_remaining // 0' 2>/dev/null || echo "0")

        if [[ "$days_remaining" -gt 30 ]]; then
            json_success "SSL certificate already exists and is valid" "$cert_info"
            return 0
        fi
        log_info "Certificate exists but expires soon, renewing..."
    fi

    log_info "Issuing SSL certificate for ${domain}"

    # Get site root for webroot verification
    local site_info site_root
    site_info=$(get_site_info "$domain")
    if command -v jq &> /dev/null; then
        site_root=$(echo "$site_info" | jq -r '.site_root // empty')
    else
        site_root="${SITES_ROOT:-/var/www/sites}/${domain}"
    fi

    local webroot="${site_root}/public"

    # Issue certificate using certbot
    local certbot_output
    if certbot_output=$(certbot certonly \
        --webroot \
        --webroot-path "$webroot" \
        --domain "$domain" \
        --domain "www.${domain}" \
        --email "$CERTBOT_EMAIL" \
        --agree-tos \
        --non-interactive \
        --quiet \
        2>&1); then

        log_info "SSL certificate issued for ${domain}"

        # Update nginx config for SSL
        if update_nginx_for_ssl "$domain"; then
            # Test and reload nginx
            if nginx -t 2>&1; then
                systemctl reload nginx
                update_registry_ssl "$domain" "true"

                local cert_info
                cert_info=$(get_cert_info "$domain")
                json_success "SSL certificate issued and configured" "$cert_info"
                return 0
            else
                json_error "Nginx configuration test failed after SSL setup" "NGINX_CONFIG_ERROR"
                return 1
            fi
        else
            json_error "Failed to update nginx config for SSL" "NGINX_UPDATE_ERROR"
            return 1
        fi
    else
        log_error "Certbot failed: ${certbot_output}"
        json_error "Failed to issue SSL certificate: ${certbot_output}" "CERTBOT_ERROR"
        return 1
    fi
}

# ssl:renew command
cmd_ssl_renew() {
    local domain="$1"

    if [[ -z "$domain" ]]; then
        json_error "Domain is required" "MISSING_DOMAIN"
        return 1
    fi

    # Check if certificate exists
    if [[ ! -f "/etc/letsencrypt/live/${domain}/cert.pem" ]]; then
        json_error "No SSL certificate found for ${domain}" "CERT_NOT_FOUND"
        return 1
    fi

    log_info "Renewing SSL certificate for ${domain}"

    # Force renew certificate
    local certbot_output
    if certbot_output=$(certbot renew \
        --cert-name "$domain" \
        --force-renewal \
        --quiet \
        2>&1); then

        log_info "SSL certificate renewed for ${domain}"

        # Reload nginx
        systemctl reload nginx

        local cert_info
        cert_info=$(get_cert_info "$domain")
        json_success "SSL certificate renewed" "$cert_info"
        return 0
    else
        log_error "Certificate renewal failed: ${certbot_output}"
        json_error "Failed to renew SSL certificate: ${certbot_output}" "RENEWAL_ERROR"
        return 1
    fi
}

# ssl:status command
cmd_ssl_status() {
    local domain="$1"

    if [[ -z "$domain" ]]; then
        json_error "Domain is required" "MISSING_DOMAIN"
        return 1
    fi

    # Check if certificate exists
    if [[ ! -f "/etc/letsencrypt/live/${domain}/cert.pem" ]]; then
        json_success "No SSL certificate" "$(json_object "domain" "$domain" "ssl_enabled" "false" "message" "No certificate found")"
        return 0
    fi

    local cert_info
    cert_info=$(get_cert_info "$domain")

    json_success "SSL status retrieved" "$cert_info"
    return 0
}
