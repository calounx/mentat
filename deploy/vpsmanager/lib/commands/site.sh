#!/usr/bin/env bash
# Site management commands for vpsmanager

# Configuration
SITES_ROOT="${SITES_ROOT:-/var/www/sites}"
NGINX_SITES_AVAILABLE="${NGINX_SITES_AVAILABLE:-/etc/nginx/sites-available}"
NGINX_SITES_ENABLED="${NGINX_SITES_ENABLED:-/etc/nginx/sites-enabled}"
PHP_FPM_POOL_DIR="${PHP_FPM_POOL_DIR:-/etc/php/8.2/fpm/pool.d}"
SITES_REGISTRY="${VPSMANAGER_ROOT}/data/sites.json"

# Initialize sites registry if it doesn't exist
init_sites_registry() {
    if [[ ! -f "$SITES_REGISTRY" ]]; then
        echo '{"sites":[]}' > "$SITES_REGISTRY"
    fi
}

# Add site to registry
add_to_registry() {
    local domain="$1"
    local site_type="$2"
    local php_version="$3"
    local db_name="$4"
    local db_user="$5"
    local site_root="$6"
    local created_at
    created_at=$(date -Iseconds)

    init_sites_registry

    # Create site JSON object
    local site_json
    site_json=$(json_object \
        "domain" "$domain" \
        "type" "$site_type" \
        "php_version" "$php_version" \
        "db_name" "$db_name" \
        "db_user" "$db_user" \
        "site_root" "$site_root" \
        "ssl_enabled" "false" \
        "enabled" "true" \
        "created_at" "$created_at")

    # Add to registry using jq if available, otherwise basic append
    if command -v jq &> /dev/null; then
        local temp_file="${SITES_REGISTRY}.tmp"
        jq ".sites += [${site_json}]" "$SITES_REGISTRY" > "$temp_file" && mv "$temp_file" "$SITES_REGISTRY"
    else
        # Fallback: simple file-based registry (one domain per line)
        echo "$site_json" >> "${SITES_REGISTRY}.list"
    fi
}

# Remove site from registry - FIXED
remove_from_registry() {
    local domain="$1"

    if command -v jq &> /dev/null && [[ -f "$SITES_REGISTRY" ]]; then
        local temp_file="${SITES_REGISTRY}.tmp"
        # Fixed: Use map(select()) to properly filter out the site
        jq ".sites |= map(select(.domain != \"${domain}\"))" "$SITES_REGISTRY" > "$temp_file" && mv "$temp_file" "$SITES_REGISTRY"
    fi
}

# Get site from registry - FIXED
get_site_info() {
    local domain="$1"

    if command -v jq &> /dev/null && [[ -f "$SITES_REGISTRY" ]]; then
        # Fixed: Use -c for compact output and handle empty results
        local result
        result=$(jq -c ".sites[] | select(.domain == \"${domain}\")" "$SITES_REGISTRY" 2>/dev/null)
        if [[ -n "$result" ]]; then
            echo "$result"
        else
            echo "{}"
        fi
    else
        echo "{}"
    fi
}

# Create site directory structure
create_site_directories() {
    local domain="$1"
    local site_type="$2"
    local site_root="${SITES_ROOT}/${domain}"
    local site_user
    site_user=$(domain_to_username "$domain")

    log_info "Creating directories for ${domain}"

    # Create site-specific system user for isolation
    if ! create_site_user "$domain"; then
        log_error "Failed to create site user for ${domain}"
        return 1
    fi

    # Create main directories
    mkdir -p "${site_root}/public"
    mkdir -p "${site_root}/logs"
    mkdir -p "${site_root}/tmp"        # Per-site /tmp for security
    mkdir -p "${site_root}/sessions"    # Per-site sessions for security

    # Type-specific setup
    case "$site_type" in
        wordpress)
            mkdir -p "${site_root}/public/wp-content/uploads"
            ;;
        laravel)
            mkdir -p "${site_root}/storage/framework/cache"
            mkdir -p "${site_root}/storage/framework/sessions"
            mkdir -p "${site_root}/storage/framework/views"
            mkdir -p "${site_root}/storage/logs"
            mkdir -p "${site_root}/bootstrap/cache"
            ;;
    esac

    # Create default index.html
    cat > "${site_root}/public/index.html" <<EOFHTML
<!DOCTYPE html>
<html>
<head>
    <title>${domain}</title>
    <style>
        body { font-family: sans-serif; text-align: center; padding: 50px; }
        h1 { color: #333; }
    </style>
</head>
<body>
    <h1>Welcome to ${domain}</h1>
    <p>Your site is ready to be configured.</p>
</body>
</html>
EOFHTML

    # Set ownership to SITE-SPECIFIC user (NOT www-data)
    # This ensures file-level isolation between sites
    chown -R "${site_user}:${site_user}" "$site_root"

    # Set permissions to 750 (owner: rwx, group: r-x, world: none)
    # Removes world-read to prevent cross-site file access
    chmod -R 750 "$site_root"

    # Ensure public directory is readable by nginx (www-data group)
    chgrp -R www-data "${site_root}/public"
    chmod -R 750 "${site_root}/public"

    log_info "Site directory owned by ${site_user} with 750 permissions"
    echo "$site_root"
}

# Create nginx configuration
create_nginx_config() {
    local domain="$1"
    local site_root="$2"
    local php_version="$3"
    local site_type="$4"

    local nginx_config="${NGINX_SITES_AVAILABLE}/${domain}.conf"
    local php_socket="/run/php/php${php_version}-fpm-${domain}.sock"

    log_info "Creating nginx config for ${domain}"

    # Determine document root based on site type
    local document_root="${site_root}/public"

    # Read template and substitute
    local template="${VPSMANAGER_ROOT}/templates/nginx-site.conf"

    if [[ -f "$template" ]]; then
        sed -e "s|{{DOMAIN}}|${domain}|g" \
            -e "s|{{DOCUMENT_ROOT}}|${document_root}|g" \
            -e "s|{{PHP_SOCKET}}|${php_socket}|g" \
            -e "s|{{SITE_ROOT}}|${site_root}|g" \
            -e "s|{{SITE_TYPE}}|${site_type}|g" \
            "$template" > "$nginx_config"
    else
        # Fallback: generate inline
        cat > "$nginx_config" <<EOFNGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${domain} www.${domain};

    root ${document_root};
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
        fastcgi_pass unix:${php_socket};
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_hide_header X-Powered-By;
    }

    location ~ /\.(?!well-known) {
        deny all;
    }

    # Static files caching
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|svg)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
EOFNGINX
    fi

    log_info "Nginx config created: ${nginx_config}"
    return 0
}

# Create PHP-FPM pool configuration
create_phpfpm_pool() {
    local domain="$1"
    local php_version="$2"
    local site_root="$3"

    local pool_name
    pool_name=$(domain_to_dirname "$domain")
    local pool_config="${PHP_FPM_POOL_DIR}/${domain}.conf"
    local php_socket="/run/php/php${php_version}-fpm-${domain}.sock"

    # Get site-specific user for isolation
    local site_user
    site_user=$(domain_to_username "$domain")

    log_info "Creating PHP-FPM pool for ${domain} (user: ${site_user})"

    # Read template and substitute
    local template="${VPSMANAGER_ROOT}/templates/php-fpm-pool.conf"

    if [[ -f "$template" ]]; then
        sed -e "s|{{POOL_NAME}}|${pool_name}|g" \
            -e "s|{{DOMAIN}}|${domain}|g" \
            -e "s|{{PHP_SOCKET}}|${php_socket}|g" \
            -e "s|{{SITE_ROOT}}|${site_root}|g" \
            -e "s|{{SITE_USER}}|${site_user}|g" \
            "$template" > "$pool_config"
    else
        # Fallback: generate inline with site-specific user
        cat > "$pool_config" <<EOFPHP
[${pool_name}]
user = ${site_user}
group = ${site_user}

listen = ${php_socket}
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 5
pm.max_requests = 500

; Logging
php_admin_value[error_log] = ${site_root}/logs/php-error.log
php_admin_flag[log_errors] = on

; Security - per-site isolation
php_admin_value[open_basedir] = ${site_root}:${site_root}/tmp:${site_root}/sessions:/usr/share/php
php_admin_value[disable_functions] = exec,passthru,shell_exec,system,proc_open,popen
php_admin_value[upload_tmp_dir] = ${site_root}/tmp
php_admin_value[session.save_path] = ${site_root}/sessions

; Limits
php_admin_value[memory_limit] = 256M
php_admin_value[upload_max_filesize] = 64M
php_admin_value[post_max_size] = 64M
php_admin_value[max_execution_time] = 300
EOFPHP
    fi

    log_info "PHP-FPM pool created: ${pool_config}"
    return 0
}

# Enable site (create symlink)
enable_site_config() {
    local domain="$1"

    local config="${NGINX_SITES_AVAILABLE}/${domain}.conf"
    local enabled="${NGINX_SITES_ENABLED}/${domain}.conf"

    if [[ ! -f "$config" ]]; then
        log_error "Nginx config not found: ${config}"
        return 1
    fi

    if [[ ! -L "$enabled" ]]; then
        ln -sf "$config" "$enabled"
        log_info "Site enabled: ${domain}"
    fi

    return 0
}

# Disable site (remove symlink)
disable_site_config() {
    local domain="$1"

    local enabled="${NGINX_SITES_ENABLED}/${domain}.conf"

    if [[ -L "$enabled" ]]; then
        rm -f "$enabled"
        log_info "Site disabled: ${domain}"
    fi

    return 0
}

# Reload services
reload_services() {
    log_info "Reloading services"

    # Test nginx config first
    if ! nginx -t 2>&1; then
        log_error "Nginx configuration test failed"
        return 1
    fi

    # Reload nginx
    systemctl reload nginx 2>&1 || true

    # Reload PHP-FPM
    local php_service="php${PHP_VERSION:-8.2}-fpm"
    systemctl reload "$php_service" 2>&1 || true

    log_info "Services reloaded"
    return 0
}

# ============================================================================
# Command handlers
# ============================================================================

# site:create command
cmd_site_create() {
    local domain=""
    local site_type="php"
    local php_version="8.2"

    # Parse arguments (supports both --type=value and --type value formats)
    while [[ $# -gt 0 ]]; do
        case $1 in
            --type=*)
                site_type="${1#*=}"
                shift
                ;;
            --type)
                site_type="$2"
                shift 2
                ;;
            --php-version=*)
                php_version="${1#*=}"
                shift
                ;;
            --php-version)
                php_version="$2"
                shift 2
                ;;
            *)
                if [[ -z "$domain" ]]; then
                    domain="$1"
                fi
                shift
                ;;
        esac
    done

    # Validate inputs
    local validation_error
    if ! validation_error=$(validate_domain "$domain"); then
        json_error "$validation_error" "INVALID_DOMAIN"
        return 1
    fi

    if ! validation_error=$(validate_site_type "$site_type"); then
        json_error "$validation_error" "INVALID_SITE_TYPE"
        return 1
    fi

    if ! validation_error=$(validate_php_version "$php_version"); then
        json_error "$validation_error" "INVALID_PHP_VERSION"
        return 1
    fi

    # Check if site already exists (idempotent)
    if site_exists "$domain"; then
        local existing_info
        existing_info=$(get_site_info "$domain")
        json_success "Site already exists" "$existing_info"
        return 0
    fi

    log_info "Creating site: ${domain} (type: ${site_type}, php: ${php_version})"

    # Generate database credentials
    local db_name
    local db_user
    local db_password
    db_name="site_$(domain_to_dbname "$domain")"
    db_user="${db_name}"
    db_password=$(generate_db_password 24)

    # Create site components
    local site_root
    site_root=$(create_site_directories "$domain" "$site_type")

    if ! create_site_database "$domain" "$db_name" "$db_user" "$db_password"; then
        json_error "Failed to create database" "DATABASE_ERROR"
        return 1
    fi

    if ! create_nginx_config "$domain" "$site_root" "$php_version" "$site_type"; then
        json_error "Failed to create nginx config" "NGINX_ERROR"
        return 1
    fi

    if ! create_phpfpm_pool "$domain" "$php_version" "$site_root"; then
        json_error "Failed to create PHP-FPM pool" "PHPFPM_ERROR"
        return 1
    fi

    if ! enable_site_config "$domain"; then
        json_error "Failed to enable site" "ENABLE_ERROR"
        return 1
    fi

    # Add to registry
    add_to_registry "$domain" "$site_type" "$php_version" "$db_name" "$db_user" "$site_root"

    # Reload services
    reload_services

    # Build response
    local response_data
    response_data=$(json_object \
        "domain" "$domain" \
        "site_root" "$site_root" \
        "document_root" "${site_root}/public" \
        "type" "$site_type" \
        "php_version" "$php_version" \
        "database" "$(json_object "name" "$db_name" "user" "$db_user" "password" "$db_password" "host" "localhost")" \
        "ssl_enabled" "false" \
        "enabled" "true")

    log_info "Site created successfully: ${domain}"
    json_success "Site created successfully" "$response_data"
    return 0
}

# site:delete command - FIXED
cmd_site_delete() {
    local domain=""
    local force=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force=true
                shift
                ;;
            *)
                if [[ -z "$domain" ]]; then
                    domain="$1"
                fi
                shift
                ;;
        esac
    done

    # Validate domain
    local validation_error
    if ! validation_error=$(validate_domain "$domain"); then
        json_error "$validation_error" "INVALID_DOMAIN"
        return 1
    fi

    # Check if site exists
    if ! site_exists "$domain"; then
        if [[ "$force" == "true" ]]; then
            json_success "Site does not exist (force mode)" "{}"
            return 0
        fi
        json_error "Site not found: ${domain}" "SITE_NOT_FOUND"
        return 1
    fi

    log_info "Deleting site: ${domain} (force: ${force})"

    # Get site info for cleanup
    local site_info
    site_info=$(get_site_info "$domain")

    # Get values from registry
    local site_root db_name db_user
    if command -v jq &> /dev/null && [[ "$site_info" != "{}" ]]; then
        site_root=$(echo "$site_info" | jq -r '.site_root // empty')
        db_name=$(echo "$site_info" | jq -r '.db_name // empty')
        db_user=$(echo "$site_info" | jq -r '.db_user // empty')
    fi
    
    # Fallback to defaults if not in registry
    if [[ -z "$site_root" ]]; then
        site_root="${SITES_ROOT}/${domain}"
    fi
    if [[ -z "$db_name" ]]; then
        db_name="site_$(domain_to_dbname "$domain")"
        db_user="$db_name"
    fi

    log_info "Cleanup targets - site_root: ${site_root}, db: ${db_name}"

    # Disable and remove nginx config
    disable_site_config "$domain"
    if [[ -f "${NGINX_SITES_AVAILABLE}/${domain}.conf" ]]; then
        rm -f "${NGINX_SITES_AVAILABLE}/${domain}.conf"
        log_info "Removed nginx config: ${NGINX_SITES_AVAILABLE}/${domain}.conf"
    fi

    # Remove PHP-FPM pool
    if [[ -f "${PHP_FPM_POOL_DIR}/${domain}.conf" ]]; then
        rm -f "${PHP_FPM_POOL_DIR}/${domain}.conf"
        log_info "Removed PHP-FPM pool: ${PHP_FPM_POOL_DIR}/${domain}.conf"
    fi

    # Drop database and user
    if [[ -n "$db_name" ]]; then
        drop_site_database "$db_name" "$db_user"
        log_info "Dropped database: ${db_name}"
    fi

    # Remove site files
    if [[ -n "$site_root" ]] && [[ -d "$site_root" ]]; then
        rm -rf "$site_root"
        log_info "Removed site files: ${site_root}"
    fi

    # Delete site-specific system user
    if delete_site_user "$domain"; then
        log_info "Deleted site-specific user for: ${domain}"
    else
        log_warning "Failed to delete site user (may not exist): ${domain}"
    fi

    # Remove from registry
    remove_from_registry "$domain"
    log_info "Removed from registry: ${domain}"

    # Reload services
    reload_services

    log_info "Site deleted successfully: ${domain}"
    json_success "Site deleted successfully" "$(json_object "domain" "$domain")"
    return 0
}

# site:enable command
cmd_site_enable() {
    local domain="$1"

    if [[ -z "$domain" ]]; then
        json_error "Domain is required" "MISSING_DOMAIN"
        return 1
    fi

    if ! site_exists "$domain"; then
        json_error "Site not found: ${domain}" "SITE_NOT_FOUND"
        return 1
    fi

    enable_site_config "$domain"
    reload_services

    json_success "Site enabled" "$(json_object "domain" "$domain" "enabled" "true")"
    return 0
}

# site:disable command
cmd_site_disable() {
    local domain="$1"

    if [[ -z "$domain" ]]; then
        json_error "Domain is required" "MISSING_DOMAIN"
        return 1
    fi

    if ! site_exists "$domain"; then
        json_error "Site not found: ${domain}" "SITE_NOT_FOUND"
        return 1
    fi

    disable_site_config "$domain"
    reload_services

    json_success "Site disabled" "$(json_object "domain" "$domain" "enabled" "false")"
    return 0
}

# site:list command
cmd_site_list() {
    init_sites_registry

    if command -v jq &> /dev/null && [[ -f "$SITES_REGISTRY" ]]; then
        local sites
        sites=$(jq -c '.sites' "$SITES_REGISTRY")
        json_success "Sites retrieved" "$(json_object "sites" "$sites" "count" "$(jq '.sites | length' "$SITES_REGISTRY")")"
    else
        json_success "Sites retrieved" "$(json_object "sites" "[]" "count" "0")"
    fi
    return 0
}

# site:info command - FIXED
cmd_site_info() {
    local domain="$1"

    if [[ -z "$domain" ]]; then
        json_error "Domain is required" "MISSING_DOMAIN"
        return 1
    fi

    if ! site_exists "$domain"; then
        json_error "Site not found: ${domain}" "SITE_NOT_FOUND"
        return 1
    fi

    local site_info
    site_info=$(get_site_info "$domain")

    # Check if we got valid site info
    if [[ "$site_info" == "{}" ]] || [[ -z "$site_info" ]]; then
        json_error "Site exists but info not found in registry: ${domain}" "SITE_INFO_ERROR"
        return 1
    fi

    # Add runtime info
    local site_root
    if command -v jq &> /dev/null; then
        site_root=$(echo "$site_info" | jq -r '.site_root // empty')
    else
        site_root="${SITES_ROOT}/${domain}"
    fi

    # Get disk usage
    local disk_usage="0"
    if [[ -d "$site_root" ]]; then
        disk_usage=$(du -sm "$site_root" 2>/dev/null | cut -f1 || echo "0")
    fi

    # Check if enabled
    local is_enabled="false"
    if [[ -L "${NGINX_SITES_ENABLED}/${domain}.conf" ]]; then
        is_enabled="true"
    fi

    local full_info
    if command -v jq &> /dev/null; then
        full_info=$(echo "$site_info" | jq -c ". + {disk_usage_mb: ${disk_usage}, enabled: ${is_enabled}}")
    else
        full_info="$site_info"
    fi

    json_success "Site info retrieved" "$full_info"
    return 0
}
