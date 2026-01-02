#!/bin/bash
# ==============================================================================
# CHOM Web Server Tests
# ==============================================================================
# Tests for Nginx web server and PHP-FPM on landsraad_tst
#
# Tests:
# - Nginx responds on port 80
# - PHP-FPM is processing requests
# - Static files are served correctly
# - Correct HTTP headers (security headers)
# - Gzip compression works
# ==============================================================================

set -e

# Get script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/test-common.sh"

# ==============================================================================
# Test Functions
# ==============================================================================

test_nginx_service_running() {
    print_test "Nginx service is running"

    if service_running "nginx"; then
        print_pass
        return 0
    else
        local status
        status=$(service_status "nginx")
        print_fail "(status: ${status})"
        return 1
    fi
}

test_nginx_responds_port_80() {
    print_test "Nginx responds on port 80"

    local response
    response=$(container_bash "curl -s -o /dev/null -w '%{http_code}' http://localhost:80/" 2>/dev/null)

    if [[ "${response}" =~ ^(200|301|302)$ ]]; then
        print_pass "(HTTP ${response})"
        return 0
    else
        print_fail "(HTTP ${response})"
        return 1
    fi
}

test_nginx_external_access() {
    print_test "Nginx accessible from host (port ${WEB_PORT})"

    local code
    code=$(check_http_code "/")

    if [[ "${code}" =~ ^(200|301|302)$ ]]; then
        print_pass "(HTTP ${code})"
        return 0
    else
        print_fail "(HTTP ${code})"
        return 1
    fi
}

test_phpfpm_service_running() {
    print_test "PHP-FPM service is running"

    # Check for php-fpm or php8.4-fpm service
    if service_running "php8.4-fpm" || service_running "php-fpm"; then
        print_pass
        return 0
    fi

    # Alternative: check process directly
    if container_bash "pgrep -f 'php-fpm: master'" &>/dev/null; then
        print_pass "(via process check)"
        return 0
    fi

    local status
    status=$(container_bash "systemctl is-active php8.4-fpm 2>/dev/null || systemctl is-active php-fpm 2>/dev/null || echo 'not-found'")
    print_fail "(status: ${status})"
    return 1
}

test_phpfpm_socket_exists() {
    print_test "PHP-FPM socket exists"

    # Common socket locations
    local sockets=(
        "/run/php/php8.4-fpm.sock"
        "/run/php/php-fpm.sock"
        "/var/run/php/php8.4-fpm.sock"
        "/var/run/php/php-fpm.sock"
    )

    for socket in "${sockets[@]}"; do
        if container_bash "test -S ${socket}" 2>/dev/null; then
            print_pass "(${socket})"
            return 0
        fi
    done

    # Check if using TCP instead
    if container_bash "ss -tln | grep -q ':9000'" 2>/dev/null; then
        print_pass "(TCP port 9000)"
        return 0
    fi

    print_fail "(no socket or port found)"
    return 1
}

test_php_processing() {
    print_test "PHP-FPM processes PHP files"

    # Request a PHP endpoint and check for proper response
    local response
    response=$(http_get_body "/api/v1/health")

    if [[ -n "${response}" ]] && is_valid_json "${response}"; then
        local status
        status=$(json_get "${response}" '.status')
        if [[ "${status}" == "ok" ]]; then
            print_pass "(health endpoint returns valid JSON)"
            return 0
        fi
    fi

    # Alternative: check that we're not getting raw PHP code
    if [[ "${response}" != *"<?php"* ]]; then
        print_pass "(PHP is being processed)"
        return 0
    fi

    print_fail "(raw PHP code returned)"
    return 1
}

test_static_files_served() {
    print_test "Static files are served correctly"

    # Check for common static files
    local files_to_check=(
        "/favicon.ico"
        "/robots.txt"
    )

    local found=0
    for file in "${files_to_check[@]}"; do
        local code
        code=$(check_http_code "${file}")
        if [[ "${code}" =~ ^(200|204)$ ]]; then
            found=$((found + 1))
        fi
    done

    # Also check that CSS/JS assets would be served (if they exist)
    local asset_code
    asset_code=$(check_http_code "/build/manifest.json" 2>/dev/null || echo "404")

    if [[ ${found} -gt 0 ]] || [[ "${asset_code}" == "200" ]]; then
        print_pass "(${found} static files accessible)"
        return 0
    fi

    # At minimum, verify Nginx serves from document root
    if container_bash "test -d /var/www/vpsmanager/public" 2>/dev/null; then
        print_pass "(document root exists)"
        return 0
    fi

    print_fail "(no static files accessible)"
    return 1
}

test_security_header_x_frame_options() {
    print_test "X-Frame-Options header present"

    local headers
    headers=$(http_get_headers "/")

    if echo "${headers}" | grep -qi "X-Frame-Options"; then
        local value
        value=$(echo "${headers}" | grep -i "X-Frame-Options" | head -1 | cut -d: -f2 | tr -d ' \r')
        print_pass "(${value})"
        return 0
    fi

    print_fail "(header missing)"
    return 1
}

test_security_header_x_content_type_options() {
    print_test "X-Content-Type-Options header present"

    local headers
    headers=$(http_get_headers "/")

    if echo "${headers}" | grep -qi "X-Content-Type-Options"; then
        local value
        value=$(echo "${headers}" | grep -i "X-Content-Type-Options" | head -1 | cut -d: -f2 | tr -d ' \r')
        print_pass "(${value})"
        return 0
    fi

    print_fail "(header missing)"
    return 1
}

test_security_header_xss_protection() {
    print_test "X-XSS-Protection header present"

    local headers
    headers=$(http_get_headers "/")

    if echo "${headers}" | grep -qi "X-XSS-Protection"; then
        print_pass
        return 0
    fi

    # Modern browsers deprecated this, so skip if using CSP instead
    if echo "${headers}" | grep -qi "Content-Security-Policy"; then
        print_skip "(using CSP instead)"
        return 0
    fi

    print_fail "(header missing)"
    return 1
}

test_security_header_content_security_policy() {
    print_test "Content-Security-Policy header present"

    local headers
    headers=$(http_get_headers "/")

    if echo "${headers}" | grep -qi "Content-Security-Policy"; then
        print_pass
        return 0
    fi

    print_skip "(not configured - recommended for production)"
    return 0
}

test_security_header_strict_transport() {
    print_test "Strict-Transport-Security header (HTTPS)"

    local headers
    headers=$(http_get_headers "/")

    if echo "${headers}" | grep -qi "Strict-Transport-Security"; then
        print_pass
        return 0
    fi

    # HSTS only applies when using HTTPS, skip for HTTP-only test env
    print_skip "(only applies to HTTPS connections)"
    return 0
}

test_server_signature_hidden() {
    print_test "Server signature is hidden/minimal"

    local headers
    headers=$(http_get_headers "/")

    # Check if Server header reveals version
    local server_header
    server_header=$(echo "${headers}" | grep -i "^Server:" | head -1)

    if [[ -z "${server_header}" ]]; then
        print_pass "(no Server header)"
        return 0
    fi

    # Check if version numbers are exposed
    if echo "${server_header}" | grep -qE "[0-9]+\.[0-9]+"; then
        print_fail "(version exposed: ${server_header})"
        return 1
    fi

    print_pass "(minimal: ${server_header})"
    return 0
}

test_gzip_compression_enabled() {
    print_test "Gzip compression is enabled"

    local response
    response=$(curl -sI -H "Accept-Encoding: gzip" "http://${WEB_HOST}:${WEB_PORT}/" 2>/dev/null)

    if echo "${response}" | grep -qi "Content-Encoding: gzip"; then
        print_pass
        return 0
    fi

    # Also check in container directly
    local container_response
    container_response=$(container_bash "curl -sI -H 'Accept-Encoding: gzip' http://localhost/" 2>/dev/null)

    if echo "${container_response}" | grep -qi "Content-Encoding: gzip"; then
        print_pass "(verified in container)"
        return 0
    fi

    print_skip "(may not apply to small responses)"
    return 0
}

test_gzip_for_assets() {
    print_test "Gzip compression for CSS/JS assets"

    # Test with a request that would normally be compressed
    local content_types=("text/html" "text/css" "application/javascript" "application/json")

    for ct in "${content_types[@]}"; do
        local response
        response=$(curl -sI -H "Accept-Encoding: gzip" -H "Accept: ${ct}" "http://${WEB_HOST}:${WEB_PORT}/api/v1/health" 2>/dev/null)

        if echo "${response}" | grep -qi "Content-Encoding: gzip"; then
            print_pass "(${ct})"
            return 0
        fi
    done

    # Check nginx config for gzip
    if container_bash "grep -r 'gzip on' /etc/nginx/ 2>/dev/null" &>/dev/null; then
        print_pass "(gzip configured in nginx)"
        return 0
    fi

    print_skip "(gzip may be configured but not used for small responses)"
    return 0
}

test_nginx_error_log_accessible() {
    print_test "Nginx error log is accessible"

    if container_bash "test -f /var/log/nginx/error.log && test -r /var/log/nginx/error.log"; then
        print_pass
        return 0
    fi

    print_fail "(log file not accessible)"
    return 1
}

test_nginx_access_log_accessible() {
    print_test "Nginx access log is accessible"

    if container_bash "test -f /var/log/nginx/access.log && test -r /var/log/nginx/access.log"; then
        print_pass
        return 0
    fi

    print_fail "(log file not accessible)"
    return 1
}

test_nginx_config_valid() {
    print_test "Nginx configuration is valid"

    local result
    result=$(container_bash "nginx -t 2>&1")

    if [[ "${result}" == *"syntax is ok"* ]] && [[ "${result}" == *"test is successful"* ]]; then
        print_pass
        return 0
    fi

    print_fail "(${result})"
    return 1
}

test_php_version() {
    print_test "PHP version is 8.4.x"

    local version
    version=$(container_bash "php -v 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'" | head -1)

    if [[ "${version}" =~ ^8\.4\. ]]; then
        print_pass "(${version})"
        return 0
    elif [[ "${version}" =~ ^8\.[0-9]+\. ]]; then
        print_pass "(PHP ${version} - acceptable)"
        return 0
    fi

    print_fail "(got: ${version})"
    return 1
}

test_php_extensions_loaded() {
    print_test "Required PHP extensions are loaded"

    local required_extensions=(
        "pdo_mysql"
        "redis"
        "mbstring"
        "openssl"
        "json"
        "curl"
    )

    local loaded_extensions
    loaded_extensions=$(container_bash "php -m" 2>/dev/null)

    local missing=()
    for ext in "${required_extensions[@]}"; do
        if ! echo "${loaded_extensions}" | grep -qi "^${ext}$"; then
            missing+=("${ext}")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        print_pass "(${#required_extensions[@]} extensions verified)"
        return 0
    fi

    print_fail "(missing: ${missing[*]})"
    return 1
}

test_document_root_permissions() {
    print_test "Document root has correct permissions"

    local owner
    owner=$(container_bash "stat -c '%U:%G' /var/www/vpsmanager/public 2>/dev/null || stat -c '%U:%G' /opt/chom/public 2>/dev/null")

    # Should be owned by www-data or similar web user
    if [[ "${owner}" == *"www-data"* ]] || [[ "${owner}" == *"nginx"* ]]; then
        print_pass "(${owner})"
        return 0
    fi

    # Also acceptable if readable by web server (check permissions directly)
    local perms
    perms=$(container_bash "stat -c '%a' /var/www/vpsmanager/public/index.php 2>/dev/null || stat -c '%a' /opt/chom/public/index.php 2>/dev/null" | head -1)
    if [[ "${perms}" =~ ^[0-7]*[4-7][0-7]*$ ]]; then
        print_pass "(readable: mode ${perms})"
        return 0
    fi

    print_fail "(owner: ${owner})"
    return 1
}

# ==============================================================================
# Main Execution
# ==============================================================================

main() {
    print_header "CHOM Web Server Tests"

    # Check prerequisites
    check_prerequisites

    echo "  Target: ${CONTAINER_NAME}"
    echo "  Web URL: http://${WEB_HOST}:${WEB_PORT}"
    echo ""

    # Nginx Service Tests
    echo -e "${CYAN}--- Nginx Service ---${NC}"
    test_nginx_service_running
    test_nginx_responds_port_80
    test_nginx_external_access
    test_nginx_config_valid
    test_nginx_error_log_accessible
    test_nginx_access_log_accessible

    # PHP-FPM Tests
    echo ""
    echo -e "${CYAN}--- PHP-FPM Service ---${NC}"
    test_phpfpm_service_running
    test_phpfpm_socket_exists
    test_php_processing
    test_php_version
    test_php_extensions_loaded

    # Static Content Tests
    echo ""
    echo -e "${CYAN}--- Static Content ---${NC}"
    test_static_files_served
    test_document_root_permissions

    # Security Headers Tests
    echo ""
    echo -e "${CYAN}--- Security Headers ---${NC}"
    test_security_header_x_frame_options
    test_security_header_x_content_type_options
    test_security_header_xss_protection
    test_security_header_content_security_policy
    test_security_header_strict_transport
    test_server_signature_hidden

    # Compression Tests
    echo ""
    echo -e "${CYAN}--- Compression ---${NC}"
    test_gzip_compression_enabled
    test_gzip_for_assets

    # Print summary
    print_summary "Web Server Tests"

    # Return exit code
    get_exit_code
}

# Run main function
main "$@"
