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

download_file() {
    local url="$1"
    local dest="$2"
    local max_time="${3:-300}"

    if ! curl -fsSL --max-time "$max_time" -o "$dest" "$url"; then
        log_error "Failed to download: $url"
        return 1
    fi
}

download_github_release() {
    local repo="$1"
    local version="$2"
    local asset_pattern="$3"
    local dest="$4"

    local download_url="https://github.com/${repo}/releases/download/v${version}/${asset_pattern}"

    download_file "$download_url" "$dest"
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
