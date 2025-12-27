#!/bin/bash
#===============================================================================
# Common Functions for Deployment Scripts
#===============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }

print_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
  ___  _                              _     _ _ _ _
 / _ \| |__  ___  ___ _ ____   ____ _| |__ (_) (_) |_ _   _
| | | | '_ \/ __|/ _ \ '__\ \ / / _` | '_ \| | | | __| | | |
| |_| | |_) \__ \  __/ |   \ V / (_| | |_) | | | | |_| |_| |
 \___/|_.__/|___/\___|_|    \_/ \__,_|_.__/|_|_|_|\__|\__, |
                                                      |___/
EOF
    echo -e "${NC}"
}

#===============================================================================
# System Functions
#===============================================================================

get_architecture() {
    local arch
    arch=$(uname -m)
    case $arch in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l)  echo "armv7" ;;
        *)       echo "$arch" ;;
    esac
}

create_system_user() {
    local user="$1"
    local group="${2:-$user}"

    if ! getent group "$group" >/dev/null 2>&1; then
        groupadd --system "$group"
    fi

    if ! id "$user" >/dev/null 2>&1; then
        useradd --system --no-create-home --shell /usr/sbin/nologin -g "$group" "$user"
    fi
}

wait_for_service() {
    local service="$1"
    local max_wait="${2:-30}"
    local count=0

    while ! systemctl is-active --quiet "$service"; do
        sleep 1
        count=$((count + 1))
        if [[ $count -ge $max_wait ]]; then
            return 1
        fi
    done
    return 0
}

check_port_available() {
    local port="$1"
    if ss -tlnp | grep -q ":${port} "; then
        return 1
    fi
    return 0
}

#===============================================================================
# Download Functions
#===============================================================================

# Download a file with optional checksum verification
# Usage: download_file "url" "dest" [max_time] [expected_checksum] [checksum_algo]
# Returns: 0 on success, 1 on failure
download_file() {
    local url="$1"
    local dest="$2"
    local max_time="${3:-300}"
    local expected_checksum="${4:-}"
    local checksum_algo="${5:-sha256}"

    # Security: Require HTTPS for non-localhost URLs
    if [[ ! "$url" =~ ^https:// ]] && [[ ! "$url" =~ ^http://localhost ]] && [[ ! "$url" =~ ^http://127\. ]]; then
        log_error "Security: Only HTTPS URLs are allowed (got: $url)"
        return 1
    fi

    if ! curl -fsSL --max-time "$max_time" -o "$dest" "$url"; then
        log_error "Failed to download: $url"
        return 1
    fi

    # Verify checksum if provided
    if [[ -n "$expected_checksum" ]]; then
        if ! verify_checksum "$dest" "$expected_checksum" "$checksum_algo"; then
            log_error "Checksum verification failed for: $dest"
            rm -f "$dest"
            return 1
        fi
        log_info "Checksum verified: $dest"
    fi

    return 0
}

# Verify file checksum
# Usage: verify_checksum "file" "expected_checksum" [algo]
# Returns: 0 if matches, 1 if not
verify_checksum() {
    local file="$1"
    local expected="$2"
    local algo="${3:-sha256}"

    if [[ ! -f "$file" ]]; then
        log_error "File not found for checksum: $file"
        return 1
    fi

    local actual=""
    case "$algo" in
        sha256)
            actual=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
            ;;
        sha512)
            actual=$(sha512sum "$file" 2>/dev/null | awk '{print $1}')
            ;;
        md5)
            actual=$(md5sum "$file" 2>/dev/null | awk '{print $1}')
            ;;
        *)
            log_error "Unsupported checksum algorithm: $algo"
            return 1
            ;;
    esac

    if [[ -z "$actual" ]]; then
        log_error "Failed to compute checksum for: $file"
        return 1
    fi

    # Case-insensitive comparison
    if [[ "${actual,,}" != "${expected,,}" ]]; then
        log_error "Checksum mismatch for $file"
        log_error "  Expected: $expected"
        log_error "  Actual:   $actual"
        return 1
    fi

    return 0
}

# Download and verify using checksums file from GitHub release
# Usage: download_and_verify_github "repo" "version" "asset" "dest" [checksums_file]
# Returns: 0 on success, 1 on failure
download_and_verify_github() {
    local repo="$1"
    local version="$2"
    local asset="$3"
    local dest="$4"
    local checksums_file="${5:-sha256sums.txt}"

    local base_url="https://github.com/${repo}/releases/download/v${version}"
    local asset_url="${base_url}/${asset}"
    local checksums_url="${base_url}/${checksums_file}"

    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf '$temp_dir'" RETURN

    local checksums_path="${temp_dir}/checksums.txt"

    # Download checksums file first
    log_info "Downloading checksums from: $checksums_url"
    if curl -fsSL --max-time 30 -o "$checksums_path" "$checksums_url" 2>/dev/null; then
        # Extract expected checksum for our asset
        local expected_checksum
        expected_checksum=$(grep -E "(^| )${asset}$" "$checksums_path" 2>/dev/null | awk '{print $1}' | head -1)

        if [[ -n "$expected_checksum" ]]; then
            log_info "Found checksum for ${asset}: ${expected_checksum:0:16}..."
            download_file "$asset_url" "$dest" 300 "$expected_checksum" "sha256"
            return $?
        else
            log_warn "No checksum found for $asset in checksums file"
        fi
    else
        log_warn "Checksums file not available: $checksums_url"
    fi

    # Fallback: download without checksum verification (with warning)
    log_warn "SECURITY WARNING: Downloading without checksum verification"
    download_file "$asset_url" "$dest" 300
}

download_github_release() {
    local repo="$1"
    local version="$2"
    local asset_pattern="$3"
    local dest="$4"

    # Try to download with checksum verification
    download_and_verify_github "$repo" "$version" "$asset_pattern" "$dest"
}

get_latest_github_release() {
    local repo="$1"

    curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" | \
        jq -r '.tag_name' | sed 's/^v//'
}

#===============================================================================
# Firewall Functions
#===============================================================================

setup_firewall_observability() {
    log_step "Configuring firewall for Observability VPS..."

    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing

    # SSH
    ufw allow 22/tcp comment 'SSH'

    # HTTP/HTTPS for Grafana
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'

    # Prometheus (internal, but allow for federation if needed)
    # ufw allow 9090/tcp comment 'Prometheus'

    # Loki push endpoint (from monitored hosts)
    ufw allow 3100/tcp comment 'Loki'

    # Tempo OTLP (from monitored hosts)
    ufw allow 4317/tcp comment 'OTLP gRPC'
    ufw allow 4318/tcp comment 'OTLP HTTP'

    ufw --force enable
    log_success "Firewall configured"
}

setup_firewall_monitored() {
    local observability_ip="$1"

    log_step "Configuring firewall for monitored host..."

    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing

    # SSH
    ufw allow 22/tcp comment 'SSH'

    # Allow metrics scraping from observability VPS only
    ufw allow from "$observability_ip" to any port 9100 proto tcp comment 'node_exporter'
    ufw allow from "$observability_ip" to any port 9113 proto tcp comment 'nginx_exporter'
    ufw allow from "$observability_ip" to any port 9104 proto tcp comment 'mysqld_exporter'
    ufw allow from "$observability_ip" to any port 9253 proto tcp comment 'phpfpm_exporter'
    ufw allow from "$observability_ip" to any port 9191 proto tcp comment 'fail2ban_exporter'

    ufw --force enable
    log_success "Firewall configured (metrics only from $observability_ip)"
}

#===============================================================================
# Service Functions
#===============================================================================

create_systemd_service() {
    local name="$1"
    local exec_start="$2"
    local user="${3:-root}"
    local description="${4:-$name service}"

    cat > "/etc/systemd/system/${name}.service" << EOF
[Unit]
Description=$description
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$user
ExecStart=$exec_start
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
}

enable_and_start() {
    local service="$1"

    systemctl enable "$service"
    systemctl start "$service"

    if wait_for_service "$service" 10; then
        log_success "$service started"
    else
        log_error "$service failed to start"
        journalctl -u "$service" --no-pager -n 20
        return 1
    fi
}

#===============================================================================
# Configuration Functions
#===============================================================================

backup_config() {
    local file="$1"
    if [[ -f "$file" ]]; then
        cp "$file" "${file}.backup.$(date +%Y%m%d%H%M%S)"
    fi
}

generate_password() {
    openssl rand -base64 16 2>/dev/null || head -c 16 /dev/urandom | base64
}
