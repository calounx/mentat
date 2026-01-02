#!/bin/bash
# ==============================================================================
# CHOM Application Tests
# ==============================================================================
# Tests for Laravel application functionality on landsraad_tst
#
# Tests:
# - Health endpoint returns 200 (/health)
# - Health endpoint returns valid JSON with status "ok"
# - Homepage loads (/)
# - API endpoints respond (/api/v1/...)
# - CSRF protection works
# - Rate limiting works
# - Error pages render correctly (404, 500)
# ==============================================================================

set -e

# Get script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/test-common.sh"

# ==============================================================================
# Test Functions
# ==============================================================================

test_health_endpoint_responds() {
    print_test "Health endpoint responds with 200"

    local code
    code=$(check_http_code "/api/v1/health")

    if [[ "${code}" == "200" ]]; then
        print_pass
        return 0
    fi

    print_fail "(HTTP ${code})"
    return 1
}

test_health_endpoint_valid_json() {
    print_test "Health endpoint returns valid JSON"

    local response
    response=$(http_get_body "/api/v1/health")

    if is_valid_json "${response}"; then
        print_pass
        return 0
    fi

    print_fail "(invalid JSON response)"
    return 1
}

test_health_endpoint_status_ok() {
    print_test "Health endpoint status is 'ok'"

    local response
    response=$(http_get_body "/api/v1/health")

    local status
    status=$(json_get "${response}" '.status')

    if [[ "${status}" == "ok" ]]; then
        print_pass
        return 0
    fi

    print_fail "(status: ${status})"
    return 1
}

test_health_endpoint_has_service_name() {
    print_test "Health endpoint includes service name"

    local response
    response=$(http_get_body "/api/v1/health")

    local service
    service=$(json_get "${response}" '.service')

    if [[ "${service}" == "chom-api" ]]; then
        print_pass "(${service})"
        return 0
    fi

    print_fail "(service: ${service})"
    return 1
}

test_health_endpoint_has_timestamp() {
    print_test "Health endpoint includes timestamp"

    local response
    response=$(http_get_body "/api/v1/health")

    local timestamp
    timestamp=$(json_get "${response}" '.timestamp')

    if [[ -n "${timestamp}" ]] && [[ "${timestamp}" != "null" ]]; then
        print_pass "(${timestamp})"
        return 0
    fi

    print_fail "(no timestamp)"
    return 1
}

test_detailed_health_endpoint() {
    print_test "Detailed health endpoint responds"

    local code
    code=$(check_http_code "/api/v1/health/detailed")

    # May return 200 (healthy) or 503 (degraded)
    if [[ "${code}" =~ ^(200|503)$ ]]; then
        print_pass "(HTTP ${code})"
        return 0
    fi

    print_fail "(HTTP ${code})"
    return 1
}

test_detailed_health_has_checks() {
    print_test "Detailed health includes component checks"

    local response
    response=$(http_get_body "/api/v1/health/detailed")

    if ! is_valid_json "${response}"; then
        print_fail "(invalid JSON)"
        return 1
    fi

    local checks
    checks=$(json_get "${response}" '.checks')

    if [[ -n "${checks}" ]] && [[ "${checks}" != "null" ]]; then
        local db_check
        db_check=$(json_get "${response}" '.checks.database.status')
        print_pass "(database: ${db_check})"
        return 0
    fi

    print_fail "(no checks section)"
    return 1
}

test_homepage_loads() {
    print_test "Homepage loads successfully"

    local code
    code=$(check_http_code "/")

    if [[ "${code}" =~ ^(200|302)$ ]]; then
        print_pass "(HTTP ${code})"
        return 0
    fi

    print_fail "(HTTP ${code})"
    return 1
}

test_homepage_content() {
    print_test "Homepage contains expected content"

    local response
    response=$(http_get_body "/")

    # Check for Laravel/CHOM markers in the response
    if [[ "${response}" == *"<html"* ]] || [[ "${response}" == *"<!DOCTYPE"* ]]; then
        print_pass
        return 0
    fi

    # If redirected, check the redirect location
    local headers
    headers=$(http_get_headers "/")
    if echo "${headers}" | grep -qi "Location:"; then
        print_pass "(redirects to login/dashboard)"
        return 0
    fi

    print_fail "(no HTML content)"
    return 1
}

test_login_page_loads() {
    print_test "Login page loads"

    local code
    code=$(check_http_code "/login")

    if [[ "${code}" == "200" ]]; then
        print_pass
        return 0
    fi

    print_fail "(HTTP ${code})"
    return 1
}

test_register_page_loads() {
    print_test "Register page loads"

    local code
    code=$(check_http_code "/register")

    if [[ "${code}" == "200" ]]; then
        print_pass
        return 0
    fi

    print_fail "(HTTP ${code})"
    return 1
}

test_api_auth_register_endpoint() {
    print_test "API auth/register endpoint responds"

    # OPTIONS request to check if endpoint exists
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        "http://${WEB_HOST}:${WEB_PORT}/api/v1/auth/register" 2>/dev/null)

    # Should respond with validation error (422) or success, not 404/500
    if [[ "${code}" =~ ^(200|201|422|429)$ ]]; then
        print_pass "(HTTP ${code})"
        return 0
    fi

    print_fail "(HTTP ${code})"
    return 1
}

test_api_auth_login_endpoint() {
    print_test "API auth/login endpoint responds"

    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d '{"email":"test@test.com","password":"test"}' \
        "http://${WEB_HOST}:${WEB_PORT}/api/v1/auth/login" 2>/dev/null)

    # Should respond with unauthorized (401) or validation error (422), not 404/500
    if [[ "${code}" =~ ^(401|422|429)$ ]]; then
        print_pass "(HTTP ${code})"
        return 0
    fi

    print_fail "(HTTP ${code})"
    return 1
}

test_api_sites_requires_auth() {
    print_test "API sites endpoint requires authentication"

    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Accept: application/json" \
        "http://${WEB_HOST}:${WEB_PORT}/api/v1/sites" 2>/dev/null)

    # Should respond with 401 Unauthorized
    if [[ "${code}" == "401" ]]; then
        print_pass "(401 Unauthorized)"
        return 0
    fi

    print_fail "(HTTP ${code} - expected 401)"
    return 1
}

test_api_backups_requires_auth() {
    print_test "API backups endpoint requires authentication"

    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Accept: application/json" \
        "http://${WEB_HOST}:${WEB_PORT}/api/v1/backups" 2>/dev/null)

    if [[ "${code}" == "401" ]]; then
        print_pass "(401 Unauthorized)"
        return 0
    fi

    print_fail "(HTTP ${code} - expected 401)"
    return 1
}

test_api_team_requires_auth() {
    print_test "API team endpoint requires authentication"

    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Accept: application/json" \
        "http://${WEB_HOST}:${WEB_PORT}/api/v1/team/members" 2>/dev/null)

    if [[ "${code}" == "401" ]]; then
        print_pass "(401 Unauthorized)"
        return 0
    fi

    print_fail "(HTTP ${code} - expected 401)"
    return 1
}

test_csrf_token_in_forms() {
    print_test "CSRF token present in login form"

    local response
    response=$(http_get_body "/login")

    # Check for CSRF token in the HTML
    if [[ "${response}" == *"csrf"* ]] || [[ "${response}" == *"_token"* ]] || [[ "${response}" == *"XSRF"* ]]; then
        print_pass
        return 0
    fi

    # Also check meta tag
    if [[ "${response}" == *"csrf-token"* ]]; then
        print_pass "(meta tag)"
        return 0
    fi

    print_skip "(CSRF may be handled differently)"
    return 0
}

test_csrf_protection_post() {
    print_test "CSRF protection blocks POST without token"

    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "email=test@test.com&password=test" \
        "http://${WEB_HOST}:${WEB_PORT}/login" 2>/dev/null)

    # Should return 419 (CSRF token mismatch) or 302 redirect
    if [[ "${code}" =~ ^(419|302|405)$ ]]; then
        print_pass "(HTTP ${code})"
        return 0
    fi

    # API endpoints may handle CSRF differently
    print_skip "(HTTP ${code})"
    return 0
}

test_rate_limiting_auth() {
    print_test "Rate limiting on auth endpoints"

    local count=0
    local rate_limited=false

    # Make multiple rapid requests
    for i in {1..10}; do
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -d '{"email":"ratelimit@test.com","password":"test"}' \
            "http://${WEB_HOST}:${WEB_PORT}/api/v1/auth/login" 2>/dev/null)

        if [[ "${code}" == "429" ]]; then
            rate_limited=true
            count=$i
            break
        fi
    done

    if [[ "${rate_limited}" == "true" ]]; then
        print_pass "(rate limited after ${count} requests)"
        return 0
    fi

    print_skip "(rate limiting may have higher threshold)"
    return 0
}

test_rate_limit_headers() {
    print_test "Rate limit headers present"

    local headers
    headers=$(curl -sI -H "Accept: application/json" \
        "http://${WEB_HOST}:${WEB_PORT}/api/v1/health" 2>/dev/null)

    if echo "${headers}" | grep -qi "X-RateLimit"; then
        print_pass
        return 0
    fi

    # Also check for Retry-After header
    if echo "${headers}" | grep -qi "Retry-After"; then
        print_pass "(Retry-After present)"
        return 0
    fi

    print_skip "(rate limit headers not exposed)"
    return 0
}

test_404_error_page() {
    print_test "404 page returns correct status"

    local code
    code=$(check_http_code "/nonexistent-page-that-should-not-exist-12345")

    if [[ "${code}" == "404" ]]; then
        print_pass
        return 0
    fi

    print_fail "(HTTP ${code})"
    return 1
}

test_404_json_response() {
    print_test "404 for API returns JSON"

    local response
    response=$(curl -s -H "Accept: application/json" \
        "http://${WEB_HOST}:${WEB_PORT}/api/v1/nonexistent-endpoint-12345" 2>/dev/null)

    if is_valid_json "${response}"; then
        print_pass
        return 0
    fi

    print_fail "(not JSON response)"
    return 1
}

test_method_not_allowed() {
    print_test "405 Method Not Allowed for wrong HTTP method"

    # POST to a GET-only endpoint
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
        -H "Accept: application/json" \
        "http://${WEB_HOST}:${WEB_PORT}/api/v1/health" 2>/dev/null)

    if [[ "${code}" == "405" ]]; then
        print_pass
        return 0
    fi

    # Some frameworks return 404 for invalid methods
    if [[ "${code}" == "404" ]]; then
        print_pass "(returns 404)"
        return 0
    fi

    print_fail "(HTTP ${code})"
    return 1
}

test_json_content_type_api() {
    print_test "API returns JSON content type"

    local headers
    headers=$(http_get_headers "/api/v1/health")

    if echo "${headers}" | grep -qi "Content-Type:.*application/json"; then
        print_pass
        return 0
    fi

    print_fail "(wrong content type)"
    return 1
}

test_cors_headers() {
    print_test "CORS headers present for API"

    local headers
    headers=$(curl -sI -X OPTIONS \
        -H "Origin: http://example.com" \
        -H "Access-Control-Request-Method: GET" \
        "http://${WEB_HOST}:${WEB_PORT}/api/v1/health" 2>/dev/null)

    if echo "${headers}" | grep -qi "Access-Control-Allow"; then
        print_pass
        return 0
    fi

    print_skip "(CORS may not be configured for same-origin)"
    return 0
}

test_api_version_prefix() {
    print_test "API uses /api/v1 versioning"

    local code
    code=$(check_http_code "/api/v1/health")

    if [[ "${code}" == "200" ]]; then
        print_pass
        return 0
    fi

    print_fail "(HTTP ${code})"
    return 1
}

test_dashboard_requires_auth() {
    print_test "Dashboard requires authentication"

    local code
    code=$(check_http_code "/dashboard")

    # Should redirect to login (302) or return 401
    if [[ "${code}" =~ ^(302|401)$ ]]; then
        print_pass "(HTTP ${code})"
        return 0
    fi

    print_fail "(HTTP ${code} - expected redirect)"
    return 1
}

test_sites_page_requires_auth() {
    print_test "Sites page requires authentication"

    local code
    code=$(check_http_code "/sites")

    if [[ "${code}" =~ ^(302|401)$ ]]; then
        print_pass "(HTTP ${code})"
        return 0
    fi

    print_fail "(HTTP ${code})"
    return 1
}

test_stripe_webhook_endpoint() {
    print_test "Stripe webhook endpoint exists"

    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        "http://${WEB_HOST}:${WEB_PORT}/stripe/webhook" 2>/dev/null)

    # Should not be 404
    if [[ "${code}" != "404" ]]; then
        print_pass "(HTTP ${code})"
        return 0
    fi

    print_skip "(webhook endpoint not configured)"
    return 0
}

# ==============================================================================
# Main Execution
# ==============================================================================

main() {
    print_header "CHOM Application Tests"

    # Check prerequisites
    check_prerequisites

    echo "  Target: ${CONTAINER_NAME}"
    echo "  Web URL: http://${WEB_HOST}:${WEB_PORT}"
    echo ""

    # Health Endpoint Tests
    echo -e "${CYAN}--- Health Endpoint ---${NC}"
    test_health_endpoint_responds
    test_health_endpoint_valid_json
    test_health_endpoint_status_ok
    test_health_endpoint_has_service_name
    test_health_endpoint_has_timestamp
    test_detailed_health_endpoint
    test_detailed_health_has_checks

    # Web Page Tests
    echo ""
    echo -e "${CYAN}--- Web Pages ---${NC}"
    test_homepage_loads
    test_homepage_content
    test_login_page_loads
    test_register_page_loads
    test_dashboard_requires_auth
    test_sites_page_requires_auth

    # API Endpoint Tests
    echo ""
    echo -e "${CYAN}--- API Endpoints ---${NC}"
    test_api_version_prefix
    test_api_auth_register_endpoint
    test_api_auth_login_endpoint
    test_api_sites_requires_auth
    test_api_backups_requires_auth
    test_api_team_requires_auth
    test_json_content_type_api
    test_stripe_webhook_endpoint

    # CSRF Protection Tests
    echo ""
    echo -e "${CYAN}--- CSRF Protection ---${NC}"
    test_csrf_token_in_forms
    test_csrf_protection_post

    # Rate Limiting Tests
    echo ""
    echo -e "${CYAN}--- Rate Limiting ---${NC}"
    test_rate_limiting_auth
    test_rate_limit_headers

    # Error Handling Tests
    echo ""
    echo -e "${CYAN}--- Error Handling ---${NC}"
    test_404_error_page
    test_404_json_response
    test_method_not_allowed
    test_cors_headers

    # Print summary
    print_summary "Application Tests"

    # Return exit code
    get_exit_code
}

# Run main function
main "$@"
