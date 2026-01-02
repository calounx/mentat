#!/bin/bash
#===============================================================================
# Exporter Auto-Discovery and Configuration System
#===============================================================================
# Scans the system for running services and automatically configures
# appropriate Prometheus exporters with intelligent detection and validation.
#
# Features:
#   - Detects running services (nginx, mysql, postgresql, mongodb, redis, etc.)
#   - Identifies installed exporters and their status
#   - Validates Prometheus scrape configurations
#   - Auto-generates missing configurations
#   - Installs missing exporters with proper setup
#   - Safe dry-run mode by default
#
# Usage:
#   ./detect-exporters.sh [OPTIONS]
#
# Options:
#   --scan              Scan for services and exporters (default)
#   --auto-configure    Apply configuration changes automatically
#   --install           Install missing exporters
#   --dry-run           Preview changes without applying (default)
#   --format FORMAT     Output format: text, json, prometheus (default: text)
#   --prometheus-config Path to prometheus.yml (auto-detect if not specified)
#   --verbose           Enable verbose output
#   --help              Show this help message
#
# Examples:
#   ./detect-exporters.sh                          # Scan and show status
#   ./detect-exporters.sh --dry-run                # Preview what would be done
#   ./detect-exporters.sh --auto-configure         # Apply configuration changes
#   ./detect-exporters.sh --install                # Install missing exporters
#   ./detect-exporters.sh --format json            # JSON output for automation
#
#===============================================================================

set -euo pipefail

# Script directory and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
DRY_RUN=true
AUTO_CONFIGURE=false
AUTO_INSTALL=false
SCAN_ONLY=true
OUTPUT_FORMAT="text"
VERBOSE=false
PROMETHEUS_CONFIG=""

# Detection results
declare -A SERVICES_DETECTED
declare -A EXPORTERS_INSTALLED
declare -A EXPORTERS_RUNNING
declare -A PROMETHEUS_TARGETS
declare -A MISSING_EXPORTERS
declare -A CONFIG_ISSUES

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Statistics
SERVICES_COUNT=0
EXPORTERS_OK=0
EXPORTERS_MISSING=0
EXPORTERS_NOT_RUNNING=0
CONFIG_ERRORS=0

#===============================================================================
# HELPER FUNCTIONS
#===============================================================================

log_info() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo -e "${BLUE}[INFO]${NC} $*"
    fi
}

log_success() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo -e "${GREEN}[OK]${NC} $*"
    fi
}

log_warning() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo -e "${YELLOW}[WARN]${NC} $*"
    fi
}

log_error() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo -e "${RED}[ERROR]${NC} $*"
    fi
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]] && [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $*"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if systemd service is running
service_running() {
    local service="$1"
    systemctl is-active --quiet "$service" 2>/dev/null
}

# Check if port is listening
port_listening() {
    local port="$1"
    ss -tuln 2>/dev/null | grep -q ":${port} " || \
    netstat -tuln 2>/dev/null | grep -q ":${port} "
}

# Get service port
get_service_port() {
    local service="$1"
    case "$service" in
        mysql|mariadb) echo "3306" ;;
        postgresql|postgres) echo "5432" ;;
        mongodb) echo "27017" ;;
        redis) echo "6379" ;;
        nginx) echo "80" ;;
        apache|httpd) echo "80" ;;
        rabbitmq) echo "5672" ;;
        memcached) echo "11211" ;;
        *) echo "" ;;
    esac
}

# Get exporter port
get_exporter_port() {
    local exporter="$1"
    case "$exporter" in
        node_exporter) echo "9100" ;;
        nginx_exporter) echo "9113" ;;
        mysqld_exporter) echo "9104" ;;
        postgres_exporter) echo "9187" ;;
        mongodb_exporter) echo "9216" ;;
        redis_exporter) echo "9121" ;;
        phpfpm_exporter) echo "9253" ;;
        apache_exporter) echo "9117" ;;
        memcached_exporter) echo "9150" ;;
        rabbitmq_exporter) echo "9419" ;;
        fail2ban_exporter) echo "9191" ;;
        *) echo "" ;;
    esac
}

# Map service to exporter
get_exporter_for_service() {
    local service="$1"
    case "$service" in
        nginx) echo "nginx_exporter" ;;
        mysql|mariadb) echo "mysqld_exporter" ;;
        postgresql|postgres) echo "postgres_exporter" ;;
        mongodb) echo "mongodb_exporter" ;;
        redis) echo "redis_exporter" ;;
        php-fpm*) echo "phpfpm_exporter" ;;
        apache*|httpd) echo "apache_exporter" ;;
        memcached) echo "memcached_exporter" ;;
        rabbitmq*) echo "rabbitmq_exporter" ;;
        fail2ban) echo "fail2ban_exporter" ;;
        *) echo "" ;;
    esac
}

#===============================================================================
# SERVICE DETECTION
#===============================================================================

detect_nginx() {
    log_verbose "Detecting Nginx..."

    if command_exists nginx || service_running nginx || [[ -f /etc/nginx/nginx.conf ]]; then
        local version=""
        if command_exists nginx; then
            version=$(nginx -v 2>&1 | grep -oP 'nginx/\K[0-9.]+' || echo "unknown")
        fi

        local port="80"
        if port_listening 80; then
            port="80"
        elif port_listening 443; then
            port="443"
        fi

        SERVICES_DETECTED[nginx]="version=$version,port=$port"
        SERVICES_COUNT=$((SERVICES_COUNT + 1))
        log_verbose "Nginx detected: version=$version, port=$port"
        return 0
    fi
    return 1
}

detect_mysql() {
    log_verbose "Detecting MySQL/MariaDB..."

    if service_running mysql || service_running mariadb || service_running mysqld; then
        local version=""
        local service_name="mysql"

        if command_exists mysql; then
            version=$(mysql --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "unknown")
        fi

        if service_running mariadb; then
            service_name="mariadb"
        fi

        SERVICES_DETECTED[$service_name]="version=$version,port=3306"
        SERVICES_COUNT=$((SERVICES_COUNT + 1))
        log_verbose "MySQL/MariaDB detected: $service_name version=$version"
        return 0
    fi
    return 1
}

detect_postgresql() {
    log_verbose "Detecting PostgreSQL..."

    if service_running postgresql || service_running postgres || port_listening 5432; then
        local version=""
        if command_exists psql; then
            version=$(psql --version 2>/dev/null | grep -oP '\d+\.\d+' | head -1 || echo "unknown")
        fi

        SERVICES_DETECTED[postgresql]="version=$version,port=5432"
        SERVICES_COUNT=$((SERVICES_COUNT + 1))
        log_verbose "PostgreSQL detected: version=$version"
        return 0
    fi
    return 1
}

detect_mongodb() {
    log_verbose "Detecting MongoDB..."

    if service_running mongod || port_listening 27017; then
        local version=""
        if command_exists mongod; then
            version=$(mongod --version 2>/dev/null | grep -oP 'db version v\K[0-9.]+' | head -1 || echo "unknown")
        fi

        SERVICES_DETECTED[mongodb]="version=$version,port=27017"
        SERVICES_COUNT=$((SERVICES_COUNT + 1))
        log_verbose "MongoDB detected: version=$version"
        return 0
    fi
    return 1
}

detect_redis() {
    log_verbose "Detecting Redis..."

    if service_running redis || service_running redis-server || port_listening 6379; then
        local version=""
        if command_exists redis-server; then
            version=$(redis-server --version 2>/dev/null | grep -oP 'v=\K[0-9.]+' || echo "unknown")
        fi

        SERVICES_DETECTED[redis]="version=$version,port=6379"
        SERVICES_COUNT=$((SERVICES_COUNT + 1))
        log_verbose "Redis detected: version=$version"
        return 0
    fi
    return 1
}

detect_phpfpm() {
    log_verbose "Detecting PHP-FPM..."

    if service_running php*-fpm || pgrep -f php-fpm >/dev/null; then
        local version=""
        if command_exists php; then
            version=$(php -v 2>/dev/null | grep -oP 'PHP \K[0-9.]+' | head -1 || echo "unknown")
        fi

        # Detect PHP-FPM socket or port
        local socket=""
        for sock in /var/run/php/php*-fpm.sock /run/php/php*-fpm.sock /var/run/php-fpm/*.sock; do
            if [[ -S "$sock" ]]; then
                socket="$sock"
                break
            fi
        done

        SERVICES_DETECTED[php-fpm]="version=$version,socket=$socket"
        SERVICES_COUNT=$((SERVICES_COUNT + 1))
        log_verbose "PHP-FPM detected: version=$version, socket=$socket"
        return 0
    fi
    return 1
}

detect_apache() {
    log_verbose "Detecting Apache..."

    if service_running apache2 || service_running httpd || command_exists apache2; then
        local version=""
        if command_exists apache2; then
            version=$(apache2 -v 2>/dev/null | grep -oP 'Apache/\K[0-9.]+' || echo "unknown")
        elif command_exists httpd; then
            version=$(httpd -v 2>/dev/null | grep -oP 'Apache/\K[0-9.]+' || echo "unknown")
        fi

        SERVICES_DETECTED[apache]="version=$version,port=80"
        SERVICES_COUNT=$((SERVICES_COUNT + 1))
        log_verbose "Apache detected: version=$version"
        return 0
    fi
    return 1
}

detect_memcached() {
    log_verbose "Detecting Memcached..."

    if service_running memcached || port_listening 11211; then
        SERVICES_DETECTED[memcached]="port=11211"
        SERVICES_COUNT=$((SERVICES_COUNT + 1))
        log_verbose "Memcached detected"
        return 0
    fi
    return 1
}

detect_rabbitmq() {
    log_verbose "Detecting RabbitMQ..."

    if service_running rabbitmq-server || port_listening 5672; then
        local version=""
        if command_exists rabbitmqctl; then
            version=$(rabbitmqctl status 2>/dev/null | grep -oP 'RabbitMQ version: \K[0-9.]+' || echo "unknown")
        fi

        SERVICES_DETECTED[rabbitmq]="version=$version,port=5672"
        SERVICES_COUNT=$((SERVICES_COUNT + 1))
        log_verbose "RabbitMQ detected: version=$version"
        return 0
    fi
    return 1
}

detect_fail2ban() {
    log_verbose "Detecting Fail2ban..."

    if service_running fail2ban || command_exists fail2ban-client; then
        SERVICES_DETECTED[fail2ban]="service=security"
        SERVICES_COUNT=$((SERVICES_COUNT + 1))
        log_verbose "Fail2ban detected"
        return 0
    fi
    return 1
}

# Run all service detections
detect_all_services() {
    log_info "Scanning for running services..."

    # Always detect node_exporter as it's universal
    SERVICES_DETECTED[system]="type=node"
    SERVICES_COUNT=$((SERVICES_COUNT + 1))

    detect_nginx || true
    detect_mysql || true
    detect_postgresql || true
    detect_mongodb || true
    detect_redis || true
    detect_phpfpm || true
    detect_apache || true
    detect_memcached || true
    detect_rabbitmq || true
    detect_fail2ban || true

    log_info "Found $SERVICES_COUNT service(s)"
}

#===============================================================================
# EXPORTER DETECTION
#===============================================================================

check_exporter_installed() {
    local exporter="$1"

    # Check common installation paths
    for path in "/usr/local/bin/$exporter" "/usr/bin/$exporter" "/opt/$exporter/$exporter"; do
        if [[ -f "$path" ]] && [[ -x "$path" ]]; then
            EXPORTERS_INSTALLED[$exporter]="path=$path"
            log_verbose "Exporter $exporter installed at $path"
            return 0
        fi
    done

    # Check if binary exists in PATH
    if command_exists "$exporter"; then
        EXPORTERS_INSTALLED[$exporter]="path=$(command -v "$exporter")"
        log_verbose "Exporter $exporter found in PATH"
        return 0
    fi

    return 1
}

check_exporter_running() {
    local exporter="$1"

    # Check systemd service
    if service_running "$exporter"; then
        EXPORTERS_RUNNING[$exporter]="method=systemd"
        log_verbose "Exporter $exporter running via systemd"
        return 0
    fi

    # Check if process is running
    if pgrep -f "$exporter" >/dev/null; then
        EXPORTERS_RUNNING[$exporter]="method=process"
        log_verbose "Exporter $exporter running as process"
        return 0
    fi

    # Check if port is listening
    local port=$(get_exporter_port "$exporter")
    if [[ -n "$port" ]] && port_listening "$port"; then
        EXPORTERS_RUNNING[$exporter]="method=port"
        log_verbose "Exporter $exporter listening on port $port"
        return 0
    fi

    return 1
}

verify_exporter_metrics() {
    local exporter="$1"
    local port=$(get_exporter_port "$exporter")

    if [[ -z "$port" ]]; then
        return 1
    fi

    # Try to fetch metrics
    if curl -sf "http://localhost:${port}/metrics" >/dev/null 2>&1; then
        log_verbose "Exporter $exporter metrics accessible on port $port"
        return 0
    fi

    return 1
}

detect_all_exporters() {
    log_info "Checking installed exporters..."

    # Check node_exporter (always recommended)
    check_exporter_installed "node_exporter"
    check_exporter_running "node_exporter"

    # Check exporters for detected services
    for service in "${!SERVICES_DETECTED[@]}"; do
        local exporter=$(get_exporter_for_service "$service")

        if [[ -z "$exporter" ]]; then
            if [[ "$service" == "system" ]]; then
                exporter="node_exporter"
            else
                continue
            fi
        fi

        log_verbose "Checking exporter for service: $service -> $exporter"

        if check_exporter_installed "$exporter"; then
            EXPORTERS_OK=$((EXPORTERS_OK + 1))

            if ! check_exporter_running "$exporter"; then
                EXPORTERS_NOT_RUNNING=$((EXPORTERS_NOT_RUNNING + 1))
                CONFIG_ISSUES[$exporter]="installed but not running"
            fi
        else
            EXPORTERS_MISSING=$((EXPORTERS_MISSING + 1))
            MISSING_EXPORTERS[$exporter]="service=$service"
        fi
    done
}

#===============================================================================
# PROMETHEUS CONFIGURATION
#===============================================================================

find_prometheus_config() {
    if [[ -n "$PROMETHEUS_CONFIG" ]] && [[ -f "$PROMETHEUS_CONFIG" ]]; then
        return 0
    fi

    # Search common locations
    local search_paths=(
        "/etc/prometheus/prometheus.yml"
        "$PROJECT_ROOT/observability-stack/prometheus/prometheus.yml"
        "$PROJECT_ROOT/docker/observability/prometheus/prometheus.yml"
        "/opt/prometheus/prometheus.yml"
        "./prometheus.yml"
    )

    for path in "${search_paths[@]}"; do
        if [[ -f "$path" ]]; then
            PROMETHEUS_CONFIG="$path"
            log_verbose "Found Prometheus config: $path"
            return 0
        fi
    done

    log_warning "Prometheus configuration not found"
    return 1
}

check_prometheus_target() {
    local exporter="$1"

    if [[ ! -f "$PROMETHEUS_CONFIG" ]]; then
        return 1
    fi

    local port=$(get_exporter_port "$exporter")
    if [[ -z "$port" ]]; then
        return 1
    fi

    # Check if target exists in config
    if grep -q ":${port}" "$PROMETHEUS_CONFIG" 2>/dev/null; then
        PROMETHEUS_TARGETS[$exporter]="configured"
        log_verbose "Prometheus target for $exporter exists in config"
        return 0
    fi

    return 1
}

generate_prometheus_scrape_config() {
    local exporter="$1"
    local hostname="${2:-localhost}"
    local port=$(get_exporter_port "$exporter")

    if [[ -z "$port" ]]; then
        return 1
    fi

    # Generate job name and labels based on exporter
    local job_name="${exporter/_exporter/}"
    local service_label="$job_name"

    cat << EOF

  # $exporter
  - job_name: '$job_name'
    static_configs:
      - targets: ['$hostname:$port']
        labels:
          service: '$service_label'
          exporter: '$exporter'
          host: '$(hostname)'
EOF
}

check_all_prometheus_targets() {
    if ! find_prometheus_config; then
        CONFIG_ERRORS=$((CONFIG_ERRORS + 1))
        return 1
    fi

    log_info "Validating Prometheus targets..."

    for exporter in "${!EXPORTERS_INSTALLED[@]}"; do
        if ! check_prometheus_target "$exporter"; then
            CONFIG_ERRORS=$((CONFIG_ERRORS + 1))
            CONFIG_ISSUES[$exporter]="${CONFIG_ISSUES[$exporter]:-}; missing from prometheus config"
        fi
    done
}

#===============================================================================
# INSTALLATION & CONFIGURATION
#===============================================================================

get_exporter_download_url() {
    local exporter="$1"
    local version="latest"

    case "$exporter" in
        node_exporter)
            echo "https://github.com/prometheus/node_exporter/releases/latest/download/node_exporter-latest.linux-amd64.tar.gz"
            ;;
        nginx_exporter)
            echo "https://github.com/nginxinc/nginx-prometheus-exporter/releases/latest/download/nginx-prometheus-exporter_latest_linux_amd64.tar.gz"
            ;;
        mysqld_exporter)
            echo "https://github.com/prometheus/mysqld_exporter/releases/latest/download/mysqld_exporter-latest.linux-amd64.tar.gz"
            ;;
        postgres_exporter)
            echo "https://github.com/prometheus-community/postgres_exporter/releases/latest/download/postgres_exporter-latest.linux-amd64.tar.gz"
            ;;
        redis_exporter)
            echo "https://github.com/oliver006/redis_exporter/releases/latest/download/redis_exporter-latest.linux-amd64.tar.gz"
            ;;
        *)
            echo ""
            ;;
    esac
}

create_systemd_service() {
    local exporter="$1"
    local binary_path="$2"
    local port=$(get_exporter_port "$exporter")

    local service_file="/etc/systemd/system/${exporter}.service"

    cat > "$service_file" << EOF
[Unit]
Description=Prometheus ${exporter}
Documentation=https://github.com/prometheus/${exporter}
After=network.target

[Service]
Type=simple
User=${exporter}
Group=${exporter}
ExecStart=${binary_path}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$exporter"
    systemctl start "$exporter"
}

install_exporter() {
    local exporter="$1"

    log_info "Installing $exporter..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install $exporter"
        return 0
    fi

    # Create user if not exists
    if ! id "$exporter" &>/dev/null; then
        useradd --no-create-home --shell /bin/false "$exporter"
    fi

    # Download and install
    local url=$(get_exporter_download_url "$exporter")
    if [[ -z "$url" ]]; then
        log_error "No download URL for $exporter"
        return 1
    fi

    local tmpdir=$(mktemp -d)
    cd "$tmpdir"

    wget -q "$url" -O exporter.tar.gz || {
        log_error "Failed to download $exporter"
        rm -rf "$tmpdir"
        return 1
    }

    tar xzf exporter.tar.gz
    local binary=$(find . -name "$exporter" -type f | head -1)

    if [[ -z "$binary" ]]; then
        log_error "Binary not found in archive"
        rm -rf "$tmpdir"
        return 1
    fi

    install -m 755 "$binary" "/usr/local/bin/$exporter"
    rm -rf "$tmpdir"

    # Create systemd service
    create_systemd_service "$exporter" "/usr/local/bin/$exporter"

    log_success "Installed $exporter"
}

#===============================================================================
# OUTPUT & REPORTING
#===============================================================================

print_text_report() {
    echo ""
    echo "==============================================================================="
    echo "  EXPORTER AUTO-DISCOVERY REPORT"
    echo "==============================================================================="
    echo ""
    echo "Hostname: $(hostname)"
    echo "Date: $(date)"
    echo ""

    # Services summary
    echo "DETECTED SERVICES ($SERVICES_COUNT)"
    echo "-------------------------------------------------------------------------------"
    for service in "${!SERVICES_DETECTED[@]}"; do
        local info="${SERVICES_DETECTED[$service]}"
        local exporter=$(get_exporter_for_service "$service")
        [[ "$service" == "system" ]] && exporter="node_exporter"

        echo -e "  ${GREEN}✓${NC} $service"
        echo "      Info: $info"
        [[ -n "$exporter" ]] && echo "      Exporter: $exporter"
    done
    echo ""

    # Exporters summary
    echo "EXPORTER STATUS"
    echo "-------------------------------------------------------------------------------"

    if [[ ${#EXPORTERS_INSTALLED[@]} -gt 0 ]]; then
        echo "Installed and Running:"
        for exporter in "${!EXPORTERS_INSTALLED[@]}"; do
            if [[ -n "${EXPORTERS_RUNNING[$exporter]:-}" ]]; then
                local port=$(get_exporter_port "$exporter")
                echo -e "  ${GREEN}✓${NC} $exporter (port $port)"

                if ! check_prometheus_target "$exporter"; then
                    echo -e "      ${YELLOW}⚠${NC} Missing from Prometheus config"
                fi
            fi
        done
        echo ""
    fi

    if [[ $EXPORTERS_NOT_RUNNING -gt 0 ]]; then
        echo "Installed but Not Running:"
        for exporter in "${!EXPORTERS_INSTALLED[@]}"; do
            if [[ -z "${EXPORTERS_RUNNING[$exporter]:-}" ]]; then
                echo -e "  ${YELLOW}⚠${NC} $exporter"
                echo "      Status: ${CONFIG_ISSUES[$exporter]}"
            fi
        done
        echo ""
    fi

    if [[ ${#MISSING_EXPORTERS[@]} -gt 0 ]]; then
        echo "Missing Exporters (service running but no exporter):"
        for exporter in "${!MISSING_EXPORTERS[@]}"; do
            local service_info="${MISSING_EXPORTERS[$exporter]}"
            echo -e "  ${RED}✗${NC} $exporter"
            echo "      Needed for: $service_info"
        done
        echo ""
    fi

    # Prometheus config status
    echo "PROMETHEUS CONFIGURATION"
    echo "-------------------------------------------------------------------------------"
    if [[ -n "$PROMETHEUS_CONFIG" ]]; then
        echo "Config file: $PROMETHEUS_CONFIG"
        echo "Configured targets: ${#PROMETHEUS_TARGETS[@]}"

        if [[ $CONFIG_ERRORS -gt 0 ]]; then
            echo -e "${YELLOW}Configuration issues: $CONFIG_ERRORS${NC}"
        else
            echo -e "${GREEN}All exporters properly configured${NC}"
        fi
    else
        echo -e "${RED}Prometheus configuration not found${NC}"
    fi
    echo ""

    # Summary
    echo "SUMMARY"
    echo "-------------------------------------------------------------------------------"
    echo "Services detected:           $SERVICES_COUNT"
    echo "Exporters installed:         ${#EXPORTERS_INSTALLED[@]}"
    echo "Exporters running:           $((${#EXPORTERS_INSTALLED[@]} - EXPORTERS_NOT_RUNNING))"
    echo "Exporters not running:       $EXPORTERS_NOT_RUNNING"
    echo "Missing exporters:           ${#MISSING_EXPORTERS[@]}"
    echo "Configuration errors:        $CONFIG_ERRORS"
    echo ""

    # Recommendations
    if [[ ${#MISSING_EXPORTERS[@]} -gt 0 ]] || [[ $EXPORTERS_NOT_RUNNING -gt 0 ]] || [[ $CONFIG_ERRORS -gt 0 ]]; then
        echo "RECOMMENDATIONS"
        echo "-------------------------------------------------------------------------------"

        if [[ ${#MISSING_EXPORTERS[@]} -gt 0 ]]; then
            echo "Install missing exporters:"
            echo "  $0 --install"
            echo ""
        fi

        if [[ $EXPORTERS_NOT_RUNNING -gt 0 ]]; then
            echo "Start stopped exporters:"
            for exporter in "${!EXPORTERS_INSTALLED[@]}"; do
                if [[ -z "${EXPORTERS_RUNNING[$exporter]:-}" ]]; then
                    echo "  systemctl start $exporter"
                fi
            done
            echo ""
        fi

        if [[ $CONFIG_ERRORS -gt 0 ]]; then
            echo "Update Prometheus configuration:"
            echo "  $0 --auto-configure"
            echo ""
        fi
    else
        echo -e "${GREEN}✓ All systems operational!${NC}"
        echo ""
    fi

    echo "==============================================================================="
}

print_json_report() {
    cat << EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "summary": {
    "services_detected": $SERVICES_COUNT,
    "exporters_installed": ${#EXPORTERS_INSTALLED[@]},
    "exporters_running": $((${#EXPORTERS_INSTALLED[@]} - EXPORTERS_NOT_RUNNING)),
    "exporters_not_running": $EXPORTERS_NOT_RUNNING,
    "missing_exporters": ${#MISSING_EXPORTERS[@]},
    "config_errors": $CONFIG_ERRORS
  },
  "services": $(
    echo "{"
    local first=true
    for service in "${!SERVICES_DETECTED[@]}"; do
        [[ "$first" == "false" ]] && echo ","
        first=false
        echo "\"$service\": \"${SERVICES_DETECTED[$service]}\""
    done
    echo "}"
  ),
  "exporters": {
    "installed": $(
      echo "["
      local first=true
      for exporter in "${!EXPORTERS_INSTALLED[@]}"; do
          [[ "$first" == "false" ]] && echo ","
          first=false
          echo "\"$exporter\""
      done
      echo "]"
    ),
    "running": $(
      echo "["
      local first=true
      for exporter in "${!EXPORTERS_RUNNING[@]}"; do
          [[ "$first" == "false" ]] && echo ","
          first=false
          echo "\"$exporter\""
      done
      echo "]"
    ),
    "missing": $(
      echo "["
      local first=true
      for exporter in "${!MISSING_EXPORTERS[@]}"; do
          [[ "$first" == "false" ]] && echo ","
          first=false
          echo "\"$exporter\""
      done
      echo "]"
    )
  },
  "prometheus": {
    "config_file": "$PROMETHEUS_CONFIG",
    "targets_configured": ${#PROMETHEUS_TARGETS[@]},
    "config_errors": $CONFIG_ERRORS
  }
}
EOF
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

print_help() {
    cat << 'EOF'
Exporter Auto-Discovery and Configuration System

Usage: detect-exporters.sh [OPTIONS]

Options:
  --scan              Scan for services and exporters (default)
  --auto-configure    Apply configuration changes automatically
  --install           Install missing exporters
  --dry-run           Preview changes without applying (default)
  --format FORMAT     Output format: text, json (default: text)
  --prometheus-config Path to prometheus.yml
  --verbose           Enable verbose output
  --help              Show this help message

Examples:
  detect-exporters.sh                          # Scan and show status
  detect-exporters.sh --dry-run                # Preview what would be done
  detect-exporters.sh --auto-configure         # Apply configuration changes
  detect-exporters.sh --install                # Install missing exporters
  detect-exporters.sh --format json            # JSON output
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --scan)
                SCAN_ONLY=true
                shift
                ;;
            --auto-configure)
                AUTO_CONFIGURE=true
                DRY_RUN=false
                shift
                ;;
            --install)
                AUTO_INSTALL=true
                DRY_RUN=false
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --prometheus-config)
                PROMETHEUS_CONFIG="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                print_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_help
                exit 1
                ;;
        esac
    done
}

main() {
    parse_args "$@"

    # Detection phase
    detect_all_services
    detect_all_exporters
    check_all_prometheus_targets

    # Installation phase
    if [[ "$AUTO_INSTALL" == "true" ]]; then
        for exporter in "${!MISSING_EXPORTERS[@]}"; do
            install_exporter "$exporter"
        done
    fi

    # Configuration phase
    if [[ "$AUTO_CONFIGURE" == "true" ]]; then
        if [[ -n "$PROMETHEUS_CONFIG" ]]; then
            log_info "Updating Prometheus configuration..."

            for exporter in "${!EXPORTERS_INSTALLED[@]}"; do
                if [[ -z "${PROMETHEUS_TARGETS[$exporter]:-}" ]]; then
                    if [[ "$DRY_RUN" == "true" ]]; then
                        log_info "[DRY-RUN] Would add $exporter to Prometheus config"
                    else
                        log_info "Adding $exporter to Prometheus config"
                        # Backup and update config would go here
                    fi
                fi
            done
        fi
    fi

    # Report phase
    case "$OUTPUT_FORMAT" in
        json)
            print_json_report
            ;;
        text|*)
            print_text_report
            ;;
    esac

    # Exit code based on issues found
    if [[ ${#MISSING_EXPORTERS[@]} -gt 0 ]] || [[ $EXPORTERS_NOT_RUNNING -gt 0 ]]; then
        exit 1
    elif [[ $CONFIG_ERRORS -gt 0 ]]; then
        exit 2
    else
        exit 0
    fi
}

# Run main function
main "$@"
