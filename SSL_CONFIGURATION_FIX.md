# SSL Configuration Fix Documentation

## Problem Summary

The observability stack installer was showing HTTPS URLs even when SSL certificate acquisition failed, leading to inaccessible services.

### Symptoms
- Installation completes and shows: "Grafana URL: https://mentat.arewel.com"
- Port 443 (HTTPS) is not listening: `ss -tulpn` shows no port 443
- Only port 80 is listening, but redirects to HTTPS fail
- Grafana is inaccessible via the displayed URL

### User Report
```
Installation Complete!
Grafana URL: https://mentat.arewel.com

$ curl https://mentat.arewel.com
curl: (7) Failed to connect to mentat.arewel.com port 443
```

## Root Cause Analysis

### Bug 1: `generate_nginx_config()` Ignores SSL Failure

**Location**: `observability-stack/deploy/lib/config.sh` line 415

**Problem**: The function only checks if `GRAFANA_DOMAIN` is set, not whether SSL actually succeeded:

```bash
if [[ -n "${GRAFANA_DOMAIN:-}" ]]; then
    # Generates HTTPS config with cert paths
```

**Impact**: Even when `certbot` fails and `setup_ssl()` sets `USE_SSL=false`, the nginx config generator still creates an HTTPS configuration with non-existent certificate paths.

### Bug 2: Broken HTTPS Redirect During ACME Challenge

**Location**: `observability-stack/deploy/roles/observability.sh` lines 645-659

**Problem**: Before attempting certificate acquisition, a temporary nginx config redirects all HTTP to HTTPS:

```bash
location / {
    return 301 https://\$server_name\$request_uri;
}
```

**Impact**: If certbot fails, this broken redirect remains briefly until `generate_nginx_config()` overwrites it. Users can't access the server during this window.

### Bug 3: Misleading Success Message

**Location**: `observability-stack/deploy/install.sh` lines 475-479

**Problem**: The completion message only checks `USE_SSL` flag, not actual certificate existence:

```bash
if [[ "${USE_SSL:-false}" == "true" ]]; then
    echo "https://${GRAFANA_DOMAIN}"
else
    echo "http://${OBSERVABILITY_IP}:3000"
fi
```

**Impact**: If `USE_SSL` remains true despite certbot failure, shows wrong URL.

## Solution

### Fix 1: Smart Nginx Configuration Generation

**File**: `observability-stack/deploy/lib/config.sh`

Added proper SSL validation before generating HTTPS config:

```bash
generate_nginx_config() {
    log_step "Generating Nginx configuration..."

    # Check if SSL is actually configured and certificates exist
    local ssl_configured=false
    if [[ "${USE_SSL:-false}" == "true" ]] && [[ -n "${GRAFANA_DOMAIN:-}" ]]; then
        if [[ -f "/etc/letsencrypt/live/${GRAFANA_DOMAIN}/fullchain.pem" ]] && \
           [[ -f "/etc/letsencrypt/live/${GRAFANA_DOMAIN}/privkey.pem" ]]; then
            ssl_configured=true
            log_info "SSL certificates found - configuring HTTPS"
        else
            log_warn "SSL enabled but certificates not found - falling back to HTTP"
        fi
    fi

    if [[ "$ssl_configured" == "true" ]]; then
        # HTTPS configuration with valid certificates
        ...
    elif [[ -n "${GRAFANA_DOMAIN:-}" ]]; then
        # Domain configured but no SSL - HTTP only with domain
        ...
    else
        # No domain - simple IP-based access
        ...
    fi
}
```

**Benefits**:
- Checks actual certificate file existence, not just flags
- Three-tier configuration: HTTPS, HTTP with domain, HTTP with IP
- Clear logging of configuration choice

### Fix 2: Safe ACME Challenge Setup

**File**: `observability-stack/deploy/roles/observability.sh`

Changed temporary nginx config to NOT redirect to HTTPS before certificates exist:

```bash
setup_ssl() {
    # Create temporary HTTP-only nginx config for ACME challenge
    # NOTE: Do NOT redirect to HTTPS yet - certificates don't exist!
    cat > /etc/nginx/sites-available/observability << EOF
server {
    listen 80;
    server_name ${GRAFANA_DOMAIN};

    # ACME challenge for Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Temporary HTTP access (will be replaced if cert succeeds)
    location / {
        proxy_pass http://127.0.0.1:3000;
        ...
    }
}
EOF

    # Try to get certificate
    if certbot certonly ...; then
        log_success "SSL certificate obtained"
    else
        log_error "SSL certificate acquisition failed"
        log_warn "Continuing with HTTP-only access"
        USE_SSL=false
    fi
}
```

**Benefits**:
- Server remains accessible during certificate acquisition
- Clear error messages when certbot fails
- Graceful fallback to HTTP-only

### Fix 3: Accurate Completion Message

**File**: `observability-stack/deploy/install.sh`

Updated completion message to verify certificate existence:

```bash
echo "  Grafana URL:"
# Check if SSL is actually configured with valid certificates
if [[ "${USE_SSL:-false}" == "true" ]] && [[ -n "${GRAFANA_DOMAIN:-}" ]]; then
    if [[ -f "/etc/letsencrypt/live/${GRAFANA_DOMAIN}/fullchain.pem" ]]; then
        echo "    https://${GRAFANA_DOMAIN}"
    else
        echo "    http://${GRAFANA_DOMAIN} (SSL setup failed)"
    fi
elif [[ -n "${GRAFANA_DOMAIN:-}" ]]; then
    echo "    http://${GRAFANA_DOMAIN}"
else
    echo "    http://${OBSERVABILITY_IP} (nginx proxy on port 80)"
    echo "    http://${OBSERVABILITY_IP}:3000 (direct Grafana access)"
fi
```

**Benefits**:
- Shows correct URL based on actual configuration
- Indicates SSL failure status
- Provides multiple access methods for IP-based installs

## Testing

### Test Case 1: SSL Success (Domain Points to Server)

**Setup**: Domain DNS points to installation server, port 80 accessible

**Expected Behavior**:
1. certbot succeeds, certificates obtained
2. nginx configured with HTTPS + redirect
3. Completion message shows: `https://domain.com`
4. Port 443 is listening
5. HTTP redirects to HTTPS

### Test Case 2: SSL Failure (Domain Points Elsewhere)

**Setup**: Domain DNS points to different server

**Expected Behavior**:
1. certbot fails (can't verify domain ownership)
2. `setup_ssl()` sets `USE_SSL=false` and logs error
3. `generate_nginx_config()` detects missing certificates
4. nginx configured for HTTP-only with domain name
5. Completion message shows: `http://domain.com (SSL setup failed)`
6. Port 443 is NOT listening
7. HTTP works on port 80

### Test Case 3: No Domain (IP-Only Installation)

**Setup**: User provides no domain, only IP

**Expected Behavior**:
1. SSL setup skipped entirely
2. nginx configured for IP-based access
3. Completion message shows both:
   - `http://192.168.1.10` (nginx proxy)
   - `http://192.168.1.10:3000` (direct Grafana)
4. Port 443 is NOT listening
5. HTTP works on port 80

## Files Modified

1. **`observability-stack/deploy/lib/config.sh`**
   - Enhanced `generate_nginx_config()` with SSL validation (lines 412-549)
   - Added certificate file existence checks
   - Added three-tier configuration logic

2. **`observability-stack/deploy/roles/observability.sh`**
   - Fixed `setup_ssl()` ACME challenge config (lines 637-687)
   - Removed premature HTTPS redirect
   - Improved error logging

3. **`observability-stack/deploy/install.sh`**
   - Enhanced `show_completion()` message (lines 472-503)
   - Added certificate validation to final message
   - Shows SSL failure status when applicable

## Prevention

To prevent similar issues in the future:

1. **Always verify resources exist before using them**: Check for certificate files before configuring nginx SSL
2. **Test failure paths**: Ensure graceful fallback when external services (certbot) fail
3. **Clear logging**: Distinguish between "SSL enabled" and "SSL working"
4. **Idempotency**: Don't leave broken state if intermediate step fails

## Related Issues

This fix also addresses:
- Nginx failing to start when SSL certificates missing
- Confusing error messages about SSL
- Inability to access services after failed SSL setup
- Documentation mismatch between expected and actual URLs

## Verification Commands

Run these on the installation server to verify SSL configuration:

```bash
# Check if SSL certificates exist
ls -la /etc/letsencrypt/live/*/fullchain.pem

# Check nginx configuration
cat /etc/nginx/sites-enabled/observability

# Check listening ports
ss -tulpn | grep -E "(80|443)"

# Test HTTP access
curl -I http://localhost/

# Test HTTPS access (if configured)
curl -I https://your-domain.com/
```
