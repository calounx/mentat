#!/bin/bash
# =============================================================================
# CHOM Deployment Common Library
# Shared functions for deployment scripts
# =============================================================================

# =============================================================================
# COLOR DEFINITIONS
# =============================================================================
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m'

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

# Global logging configuration
DEPLOYMENT_LOG_FILE="${DEPLOYMENT_LOG_FILE:-/tmp/deployment-$(date +%Y%m%d-%H%M%S).log}"
DEPLOYMENT_LOG_ENABLED="${DEPLOYMENT_LOG_ENABLED:-true}"

# Initialize deployment log
init_deployment_log() {
    if [[ "$DEPLOYMENT_LOG_ENABLED" == "true" ]]; then
        mkdir -p "$(dirname "$DEPLOYMENT_LOG_FILE")"
        {
            echo "==========================================="
            echo "CHOM Deployment Log"
            echo "Host: $(hostname)"
            echo "IP: $(hostname -I | awk '{print $1}')"
            echo "Date: $(date)"
            echo "==========================================="
            echo ""
        } > "$DEPLOYMENT_LOG_FILE"
        chmod 600 "$DEPLOYMENT_LOG_FILE"
        log_info "Deployment logging to: $DEPLOYMENT_LOG_FILE"
    fi
}

# Log to file (strips ANSI color codes)
log_to_file() {
    if [[ "$DEPLOYMENT_LOG_ENABLED" == "true" ]]; then
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local clean_msg=$(echo "$1" | sed 's/\x1B\[[0-9;]*[JKmsu]//g')
        echo "[$timestamp] $clean_msg" >> "$DEPLOYMENT_LOG_FILE"
    fi
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log_to_file "[INFO] $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log_to_file "[SUCCESS] $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    log_to_file "[WARN] $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log_to_file "[ERROR] $1"
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Write content to system files (requires sudo)
write_system_file() {
    local file="$1"
    sudo tee "$file" > /dev/null
}

# Check sudo access
check_sudo_access() {
    log_info "Checking sudo access..."

    if ! sudo -n true 2>/dev/null; then
        log_error "This script requires passwordless sudo access"
        log_error "Please run: sudo visudo and add: $USER ALL=(ALL) NOPASSWD:ALL"
        exit 1
    fi

    log_success "Sudo access confirmed"
}

# =============================================================================
# OS DETECTION
# =============================================================================

# Detect and validate Debian OS
detect_debian_os() {
    log_info "Detecting operating system..."

    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS - /etc/os-release not found"
        exit 1
    fi

    source /etc/os-release

    if [[ "$ID" != "debian" ]]; then
        log_error "This script only supports Debian (detected: $ID)"
        exit 1
    fi

    export DEBIAN_VERSION=$(echo "$VERSION_ID" | cut -d. -f1)
    export DEBIAN_CODENAME="$VERSION_CODENAME"

    case "$DEBIAN_VERSION" in
        12)
            log_info "Detected: Debian 12 (Bookworm)"
            ;;
        13)
            log_info "Detected: Debian 13 (Trixie)"
            ;;
        *)
            log_warn "Unsupported Debian version: $DEBIAN_VERSION ($DEBIAN_CODENAME)"
            log_warn "This script is tested on Debian 12 (Bookworm) and 13 (Trixie)"
            log_warn "Continuing anyway, but you may encounter issues..."
            ;;
    esac
}

# =============================================================================
# VERSION MANAGEMENT
# =============================================================================

# Version cache configuration
VERSION_CACHE="/tmp/chom-versions.cache"
CACHE_MAX_AGE=3600  # 1 hour

# Get version from cache or fetch from GitHub API
get_github_version() {
    local component="$1"
    local repo="$2"
    local fallback="$3"
    local cache_key="${component}_version"

    # Check cache first
    if [[ -f "$VERSION_CACHE" ]]; then
        local cached_version=$(grep "^${cache_key}=" "$VERSION_CACHE" 2>/dev/null | cut -d= -f2)
        local cache_age=$(($(date +%s) - $(stat -c %Y "$VERSION_CACHE" 2>/dev/null || echo 0)))

        if [[ -n "$cached_version" ]] && [[ $cache_age -lt $CACHE_MAX_AGE ]]; then
            log_info "${component} version ${cached_version} (cached)"
            echo "$cached_version"
            return 0
        fi
    fi

    # Fetch from GitHub API with timeout protection
    log_info "Fetching latest ${component} version from GitHub..."
    local version=$(curl --connect-timeout 10 --max-time 30 -s "https://api.github.com/repos/${repo}/releases/latest" | \
                   grep '"tag_name":' | \
                   sed -E 's/.*"v([^"]+)".*/\1/' 2>/dev/null)

    # Use fallback if fetch failed
    if [[ -z "$version" ]]; then
        log_warn "Failed to fetch ${component} version, using fallback: ${fallback}"
        version="$fallback"
    fi

    # Update cache with atomic write (prevent race conditions)
    mkdir -p "$(dirname "$VERSION_CACHE")"
    (
        # Use flock for atomic cache update
        flock -x 200 || return 0
        grep -v "^${cache_key}=" "$VERSION_CACHE" 2>/dev/null > "${VERSION_CACHE}.tmp" || true
        echo "${cache_key}=${version}" >> "${VERSION_CACHE}.tmp"
        mv "${VERSION_CACHE}.tmp" "$VERSION_CACHE"
    ) 200>/var/lock/chom-version-cache.lock 2>/dev/null || true

    log_success "${component} version: ${version}"
    echo "$version"
}

# =============================================================================
# SERVICE MANAGEMENT
# =============================================================================

# Stop service with force-kill capabilities (5-step escalation)
stop_and_verify_service() {
    local service_name="$1"
    local binary_path="$2"
    local max_wait=30
    local waited=0

    log_info "Attempting to stop ${service_name}..."

    # Step 1: Check if service exists
    if ! systemctl list-unit-files | grep -q "^${service_name}.service"; then
        log_info "Service ${service_name} does not exist yet, skipping stop"
        return 0
    fi

    # Step 2: Disable to prevent auto-restart
    if systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
        log_info "Disabling ${service_name} to prevent auto-restart..."
        sudo systemctl disable "$service_name" 2>/dev/null || log_warn "Disable returned error, continuing..."
    fi

    # Step 3: Graceful stop
    if systemctl is-active --quiet "$service_name"; then
        log_info "Stopping ${service_name} gracefully..."
        sudo systemctl stop "$service_name" 2>/dev/null || log_warn "Graceful stop returned error, continuing..."
    fi

    # Step 4: Wait for binary release (with timeout)
    log_info "Waiting up to ${max_wait}s for ${binary_path} to be released..."
    while [[ $waited -lt $max_wait ]]; do
        if ! lsof "$binary_path" 2>/dev/null | grep -q "$binary_path"; then
            log_success "${service_name} stopped and binary released"
            return 0
        fi
        sleep 1
        ((waited++))
    done

    # Step 5: Force kill with SIGTERM → SIGKILL escalation
    log_warn "Binary still in use after ${max_wait}s, force killing processes..."

    local pids=$(lsof -t "$binary_path" 2>/dev/null)
    if [[ -n "$pids" ]]; then
        log_info "Sending SIGTERM to PIDs: $pids"
        echo "$pids" | xargs -r sudo kill -15 2>/dev/null || true
        sleep 2

        pids=$(lsof -t "$binary_path" 2>/dev/null)
        if [[ -n "$pids" ]]; then
            log_warn "Processes still alive, sending SIGKILL to PIDs: $pids"
            echo "$pids" | xargs -r sudo kill -9 2>/dev/null || true
            sleep 1
        fi
    fi

    # Nuclear option: fuser -k
    if lsof "$binary_path" 2>/dev/null | grep -q "$binary_path"; then
        log_warn "Binary STILL in use, using fuser -k (nuclear option)..."
        sudo fuser -k -TERM "$binary_path" 2>/dev/null || true
        sleep 2
        sudo fuser -k -KILL "$binary_path" 2>/dev/null || true
        sleep 1
    fi

    # Final check
    if lsof "$binary_path" 2>/dev/null | grep -q "$binary_path"; then
        log_warn "Binary may still be in use, but proceeding anyway (will be overwritten)"
    else
        log_success "Binary successfully released after force kill"
    fi

    return 0
}

# Cleanup port conflicts (SIGTERM → SIGKILL escalation)
cleanup_port_conflicts() {
    local ports=("$@")

    log_info "Checking for port conflicts on ports: ${ports[*]}"

    for port in "${ports[@]}"; do
        local pids=$(sudo lsof -ti ":$port" 2>/dev/null || true)

        if [[ -n "$pids" ]]; then
            log_warn "Port $port is in use by PIDs: $pids"
            log_info "Sending SIGTERM to processes on port $port..."
            echo "$pids" | xargs -r sudo kill -15 2>/dev/null || true
            sleep 2

            # Check if still alive
            pids=$(sudo lsof -ti ":$port" 2>/dev/null || true)
            if [[ -n "$pids" ]]; then
                log_warn "Processes still alive on port $port, sending SIGKILL..."
                echo "$pids" | xargs -r sudo kill -9 2>/dev/null || true
                sleep 1
            fi

            # Final verification
            pids=$(sudo lsof -ti ":$port" 2>/dev/null || true)
            if [[ -n "$pids" ]]; then
                log_warn "Port $port may still be in use (PIDs: $pids), but proceeding..."
            else
                log_success "Port $port cleared"
            fi
        else
            log_info "Port $port is available"
        fi
    done
}

# =============================================================================
# PACKAGE MANAGEMENT
# =============================================================================

# Update system packages
update_system_packages() {
    log_info "Updating system packages..."
    sudo apt-get update -qq
    sudo apt-get upgrade -y -qq
    log_success "System packages updated"
}

# =============================================================================
# FIREWALL CONFIGURATION
# =============================================================================

# Configure firewall base rules (reset + defaults + SSH)
configure_firewall_base() {
    log_info "Configuring firewall base rules..."
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow ssh
    log_success "Firewall base rules configured"
}

# =============================================================================
# PORT VALIDATION
# =============================================================================

# Validate ports are available (with cleanup if needed)
validate_ports_available() {
    local ports=("$@")

    log_info "Validating ports are available: ${ports[*]}"

    # Collect unavailable ports
    local unavailable_ports=()
    for port in "${ports[@]}"; do
        if lsof -ti ":$port" &>/dev/null; then
            unavailable_ports+=("$port")
        fi
    done

    # Clean all unavailable ports at once
    if [[ ${#unavailable_ports[@]} -gt 0 ]]; then
        log_warn "Ports in use: ${unavailable_ports[*]}"
        cleanup_port_conflicts "${unavailable_ports[@]}"

        # Final verification - fail if any still unavailable
        for port in "${unavailable_ports[@]}"; do
            if lsof -ti ":$port" &>/dev/null; then
                log_error "Failed to free port $port. Cannot start services."
                log_error "Please manually investigate: sudo lsof -i :$port"
                exit 1
            fi
        done
    fi

    log_success "All required ports are available"
}

# =============================================================================
# SERVICE VERIFICATION
# =============================================================================

# Verify services are running
verify_services() {
    local services=("$@")
    local all_ok=true

    log_info "Verifying services..."

    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "$svc"; then
            log_success "$svc is running"
        else
            log_error "$svc failed to start"
            all_ok=false
        fi
    done

    if [[ "$all_ok" == "true" ]]; then
        log_success "All services verified successfully"
        return 0
    else
        log_error "Some services failed verification"
        return 1
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get primary IP address
get_ip_address() {
    hostname -I | awk '{print $1}'
}

# Download and extract tarball
download_and_extract() {
    local url="$1"
    local filename="$2"

    cd /tmp

    # Download with timeout and retry protection
    if ! wget --timeout=60 --tries=3 --continue --quiet "$url" -O "$filename"; then
        log_error "Failed to download: $url"
        return 1
    fi

    # Verify file was downloaded
    if [[ ! -f "$filename" ]]; then
        log_error "Download file not found: $filename"
        return 1
    fi

    # Extract based on file type
    if [[ "$filename" == *.tar.gz ]]; then
        if ! tar xzf "$filename"; then
            log_error "Failed to extract: $filename"
            return 1
        fi
    elif [[ "$filename" == *.zip ]]; then
        if ! unzip -qq "$filename"; then
            log_error "Failed to extract: $filename"
            return 1
        fi
    else
        log_error "Unsupported archive format: $filename"
        return 1
    fi

    return 0
}

# Generate secure random password
generate_password() {
    local length="${1:-24}"
    openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c "$length"
}

# Securely hash password with bcrypt
hash_password_bcrypt() {
    local password="$1"
    local temp_py="/tmp/hash_bcrypt_$$.py"

    # Create temporary Python script (avoid password in process list)
    cat > "$temp_py" << 'EOPY'
import bcrypt
import sys
password = sys.stdin.read().strip()
hashed = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt(rounds=12))
print(hashed.decode('utf-8'))
EOPY

    chmod 600 "$temp_py"
    local hashed=$(echo -n "$password" | python3 "$temp_py")
    shred -u "$temp_py"

    echo "$hashed"
}

# =============================================================================
# SYSTEMD SERVICE CREATION
# =============================================================================

# Create standard systemd service file
create_systemd_service() {
    local service_name="$1"
    local description="$2"
    local user="$3"
    local exec_start="$4"
    local extra_options="${5:-}"

    write_system_file "/etc/systemd/system/${service_name}.service" << EOF
[Unit]
Description=${description}
Wants=network-online.target
After=network-online.target

[Service]
User=${user}
Group=${user}
Type=simple
ExecStart=${exec_start}
Restart=always
RestartSec=5
${extra_options}

[Install]
WantedBy=multi-user.target
EOF

    log_success "Created systemd service: ${service_name}"
}

# =============================================================================
# SSL/HTTPS CONFIGURATION
# =============================================================================

# Setup SSL certificate with Let's Encrypt using certbot
# Args: domain email [additional_domains...]
setup_letsencrypt_ssl() {
    local domain="$1"
    local email="$2"
    shift 2
    local additional_domains=("$@")

    log_info "Setting up Let's Encrypt SSL for ${domain}..."

    # Validate domain parameter
    if [[ -z "$domain" ]]; then
        log_error "Domain parameter is required for SSL setup"
        return 1
    fi

    # Validate domain format (prevent injection)
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        log_error "Invalid domain format: ${domain}"
        return 1
    fi

    # Check domain length
    if [[ ${#domain} -gt 253 ]]; then
        log_error "Domain name too long: ${domain}"
        return 1
    fi

    # Validate email parameter
    if [[ -z "$email" ]]; then
        log_error "Email parameter is required for SSL setup"
        return 1
    fi

    # Validate email format (prevent injection)
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_error "Invalid email format: ${email}"
        return 1
    fi

    # Build certbot command as array (avoid eval injection)
    local certbot_args=(
        certbot
        --nginx
        -d "$domain"
    )

    # Add additional domains
    for add_domain in "${additional_domains[@]}"; do
        certbot_args+=(-d "$add_domain")
    done

    # Add non-interactive flags
    certbot_args+=(--non-interactive --agree-tos --email "$email" --redirect)

    log_info "Running certbot for ${domain}..."
    log_info "Email: ${email}"

    # Execute certbot (safe from injection)
    if sudo "${certbot_args[@]}"; then
        log_success "SSL certificate installed for ${domain}"

        # Test nginx configuration
        if sudo nginx -t 2>/dev/null; then
            log_success "Nginx configuration valid"
            sudo systemctl reload nginx
            log_success "Nginx reloaded with SSL configuration"
        else
            log_error "Nginx configuration test failed after SSL setup"
            return 1
        fi

        return 0
    else
        log_error "Failed to obtain SSL certificate for ${domain}"
        log_warn "Continuing without SSL - you can run certbot manually later"
        return 1
    fi
}

# Setup SSL with automatic renewal
# Args: domain email [additional_domains...]
setup_ssl_with_renewal() {
    local domain="$1"
    local email="$2"
    shift 2
    local additional_domains=("$@")

    # Setup initial certificate
    if setup_letsencrypt_ssl "$domain" "$email" "${additional_domains[@]}"; then
        # Enable automatic renewal (certbot installs systemd timer by default)
        log_info "Enabling automatic SSL renewal..."

        if systemctl list-timers | grep -q certbot; then
            log_success "Certbot renewal timer is active"
        else
            log_warn "Certbot renewal timer not found - manual renewal may be required"
        fi

        # Test renewal process
        log_info "Testing SSL renewal process..."
        if sudo certbot renew --dry-run 2>/dev/null; then
            log_success "SSL auto-renewal test passed"
        else
            log_warn "SSL auto-renewal test failed - check certbot configuration"
        fi

        return 0
    else
        return 1
    fi
}

# Check if domain is accessible (DNS resolution)
check_domain_accessible() {
    local domain="$1"

    log_info "Checking if ${domain} is accessible..."

    # Validate domain format
    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        log_error "Invalid domain format: ${domain}"
        return 1
    fi

    # Try to resolve domain
    if host "$domain" >/dev/null 2>&1; then
        local resolved_ip=$(host "$domain" | grep "has address" | awk '{print $4}' | head -n1)
        local server_ip=$(get_ip_address)

        log_info "Domain ${domain} resolves to: ${resolved_ip}"
        log_info "Server IP address: ${server_ip}"

        if [[ "$resolved_ip" == "$server_ip" ]]; then
            log_success "Domain ${domain} correctly points to this server"
            return 0
        else
            log_warn "Domain ${domain} points to ${resolved_ip} but server IP is ${server_ip}"
            log_warn "DNS may not be configured correctly"
            return 1
        fi
    else
        log_error "Cannot resolve domain: ${domain}"
        log_error "Please configure DNS before setting up SSL"
        return 1
    fi
}

# Wait for domain to be accessible with timeout
# Args: domain timeout_seconds
wait_for_domain() {
    local domain="$1"
    local timeout="${2:-300}"  # Default 5 minutes
    local elapsed=0

    log_info "Waiting for ${domain} to be accessible (timeout: ${timeout}s)..."

    while [[ $elapsed -lt $timeout ]]; do
        if check_domain_accessible "$domain" 2>/dev/null; then
            log_success "Domain ${domain} is accessible"
            return 0
        fi

        sleep 10
        elapsed=$((elapsed + 10))

        if [[ $((elapsed % 60)) -eq 0 ]]; then
            log_info "Still waiting... (${elapsed}s elapsed)"
        fi
    done

    log_error "Timeout waiting for ${domain} to be accessible"
    return 1
}

# =============================================================================
# LIBRARY INITIALIZATION
# =============================================================================

log_info "CHOM Common Library loaded successfully"
