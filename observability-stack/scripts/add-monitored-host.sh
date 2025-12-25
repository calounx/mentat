#!/bin/bash
#===============================================================================
# Add Monitored Host to Observability Stack
# Run this on the mentat (observability) server to add a new monitored host
#
# Usage:
#   ./add-monitored-host.sh --name "hostname" --ip "IP" [--description "desc"]
#   ./add-monitored-host.sh --name "webserver" --ip "10.0.0.5" --description "Production server"
#===============================================================================

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${BASE_DIR}/config/global.yaml"

# Source common library for security utilities
if [[ -f "$SCRIPT_DIR/lib/common.sh" ]]; then
    source "$SCRIPT_DIR/lib/common.sh"
else
    # Fallback colors if common.sh not available
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'

    log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
    log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

    # Minimal validation fallbacks
    is_valid_ip() { [[ "$1" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; }
    is_valid_hostname() { [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; }
fi

# Parameters
HOST_NAME=""
HOST_IP=""
HOST_DESC=""
EXPORTERS=()
RELOAD_PROMETHEUS=true

show_help() {
    echo "Usage: $0 --name NAME --ip IP [OPTIONS]"
    echo ""
    echo "Required:"
    echo "  --name NAME           Short hostname for the monitored host"
    echo "  --ip IP               IP address of the monitored host"
    echo ""
    echo "Optional:"
    echo "  --description DESC    Description of the host"
    echo "  --exporters LIST      Comma-separated list of exporters"
    echo "                        (default: node_exporter,nginx_exporter,mysqld_exporter,phpfpm_exporter)"
    echo "  --no-reload           Don't reload Prometheus after adding"
    echo "  --help                Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 --name webserver1 --ip 10.0.0.5"
    echo "  $0 --name webserver1 --ip 10.0.0.5 --description 'Production web server'"
    echo "  $0 --name webserver1 --ip 10.0.0.5 --exporters node_exporter,nginx_exporter"
    echo ""
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                HOST_NAME="$2"
                shift 2
                ;;
            --ip)
                HOST_IP="$2"
                shift 2
                ;;
            --description)
                HOST_DESC="$2"
                shift 2
                ;;
            --exporters)
                IFS=',' read -ra EXPORTERS <<< "$2"
                shift 2
                ;;
            --no-reload)
                RELOAD_PROMETHEUS=false
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Validate required args
    if [[ -z "$HOST_NAME" ]]; then
        log_error "Missing required argument: --name"
        echo ""
        echo "Usage: $0 --name HOSTNAME --ip IP_ADDRESS"
        echo ""
        echo "Example:"
        echo "  $0 --name webserver1 --ip 10.0.0.5"
        echo ""
        echo "Run '$0 --help' for more information"
        exit 1
    fi
    if [[ -z "$HOST_IP" ]]; then
        log_error "Missing required argument: --ip"
        echo ""
        echo "Usage: $0 --name HOSTNAME --ip IP_ADDRESS"
        echo ""
        echo "Example:"
        echo "  $0 --name webserver1 --ip 10.0.0.5"
        echo ""
        echo "Run '$0 --help' for more information"
        exit 1
    fi

    # SECURITY: Validate hostname format (RFC 952/1123)
    # Allow relaxed validation for short hostnames
    if [[ ! "$HOST_NAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        log_error "Invalid hostname: '$HOST_NAME' - must contain only alphanumeric characters and hyphens"
    fi

    # SECURITY: Validate IP address (RFC 791 - IPv4)
    if ! is_valid_ip "$HOST_IP"; then
        log_error "Invalid IP address: '$HOST_IP' - must be a valid IPv4 address (e.g., 192.168.1.100)"
    fi

    # Default exporters if not specified
    if [[ ${#EXPORTERS[@]} -eq 0 ]]; then
        EXPORTERS=(node_exporter nginx_exporter mysqld_exporter phpfpm_exporter)
    fi

    # Default description
    if [[ -z "$HOST_DESC" ]]; then
        HOST_DESC="Monitored host $HOST_NAME"
    fi
}

check_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Config file not found: $CONFIG_FILE"
        echo ""
        echo "The global configuration file is missing."
        echo ""
        echo "To fix:"
        echo "  1. Ensure you're in the observability-stack directory"
        echo "  2. Create config/global.yaml from template if needed"
        echo "  3. Verify the file exists: ls -l $CONFIG_FILE"
        exit 1
    fi
}

check_duplicate() {
    # Check if host already exists in config
    if grep -q "name: \"$HOST_NAME\"" "$CONFIG_FILE" 2>/dev/null; then
        log_error "Host '$HOST_NAME' already exists in $CONFIG_FILE"
        echo ""
        echo "To fix:"
        echo "  1. Choose a different hostname"
        echo "  2. Or remove the existing entry from $CONFIG_FILE"
        echo "  3. View existing hosts: grep 'name:' $CONFIG_FILE"
        exit 1
    fi
    if grep -q "ip: \"$HOST_IP\"" "$CONFIG_FILE" 2>/dev/null; then
        log_error "IP '$HOST_IP' already exists in $CONFIG_FILE"
        echo ""
        echo "Each monitored host must have a unique IP address."
        echo ""
        echo "To fix:"
        echo "  1. Verify the IP address is correct"
        echo "  2. Or remove the existing entry with this IP from $CONFIG_FILE"
        echo "  3. View existing hosts: grep 'ip:' $CONFIG_FILE"
        exit 1
    fi
}

test_connectivity() {
    log_info "Testing connectivity to $HOST_IP..."

    local failed=false

    for exporter in "${EXPORTERS[@]}"; do
        local port
        case "$exporter" in
            node_exporter) port=9100 ;;
            nginx_exporter) port=9113 ;;
            mysqld_exporter) port=9104 ;;
            phpfpm_exporter) port=9253 ;;
            *) continue ;;
        esac

        if curl -s --connect-timeout 3 "http://${HOST_IP}:${port}/metrics" > /dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} $exporter (port $port) - reachable"
        else
            echo -e "  ${YELLOW}!${NC} $exporter (port $port) - unreachable"
            failed=true
        fi
    done

    if [[ "$failed" == "true" ]]; then
        echo ""
        echo -e "${YELLOW}Warning: Some exporters are unreachable.${NC}"
        echo "Ensure the monitored host's firewall allows connections from this server."
        echo ""
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

add_host_to_config() {
    log_info "Adding host to $CONFIG_FILE..."

    # Build exporters list
    local exporters_yaml=""
    for exp in "${EXPORTERS[@]}"; do
        exporters_yaml="${exporters_yaml}      - ${exp}\n"
    done

    # Create the YAML block
    local yaml_block
    yaml_block=$(cat <<EOF

  - name: "${HOST_NAME}"
    ip: "${HOST_IP}"
    description: "${HOST_DESC}"
    exporters:
$(for exp in "${EXPORTERS[@]}"; do echo "      - ${exp}"; done)
EOF
)

    # Append to config file
    echo "$yaml_block" >> "$CONFIG_FILE"

    log_success "Host added to config"
}

regenerate_prometheus_config() {
    log_info "Regenerating Prometheus configuration..."

    # Run the setup script to regenerate configs
    "${SCRIPT_DIR}/setup-observability.sh"
}

reload_prometheus() {
    if [[ "$RELOAD_PROMETHEUS" == "true" ]]; then
        log_info "Reloading Prometheus..."
        systemctl reload prometheus || systemctl restart prometheus
        log_success "Prometheus reloaded"
    else
        log_info "Skipping Prometheus reload (--no-reload specified)"
        echo "Run manually: sudo systemctl reload prometheus"
    fi
}

verify_targets() {
    log_info "Verifying Prometheus targets..."
    sleep 3

    local targets
    targets=$(curl -s "http://localhost:9090/api/v1/targets" 2>/dev/null)

    if echo "$targets" | grep -q "$HOST_IP"; then
        local up_count down_count
        up_count=$(echo "$targets" | grep -o "\"$HOST_IP:[0-9]*\"" | while read -r t; do
            if echo "$targets" | grep -A5 "$t" | grep -q '"health":"up"'; then
                echo "1"
            fi
        done | wc -l)

        echo -e "  Targets for $HOST_IP found in Prometheus"
        log_success "Host $HOST_NAME ($HOST_IP) added successfully"
    else
        echo -e "${YELLOW}Warning: Targets not yet visible in Prometheus. May take a few seconds.${NC}"
    fi
}

main() {
    echo ""
    echo "=========================================="
    echo "Add Monitored Host to Observability Stack"
    echo "=========================================="
    echo ""

    parse_args "$@"
    check_config
    check_duplicate

    echo "Host details:"
    echo "  Name:        $HOST_NAME"
    echo "  IP:          $HOST_IP"
    echo "  Description: $HOST_DESC"
    echo "  Exporters:   ${EXPORTERS[*]}"
    echo ""

    test_connectivity
    add_host_to_config
    regenerate_prometheus_config
    reload_prometheus
    verify_targets

    echo ""
    echo "=========================================="
    echo -e "${GREEN}Done!${NC}"
    echo "=========================================="
    echo ""
    echo "View targets: https://mentat.arewel.com/prometheus/targets"
    echo "Run health check: ./health-check.sh"
    echo ""
}

main "$@"
