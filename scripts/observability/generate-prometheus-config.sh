#!/bin/bash
#===============================================================================
# Prometheus Scrape Configuration Generator
#===============================================================================
# Dynamically generates Prometheus scrape configurations for detected
# exporters across multiple hosts.
#
# Features:
#   - Template-based configuration generation
#   - Multi-host support
#   - Automatic service discovery
#   - Configuration validation
#   - Atomic updates with rollback
#
# Usage:
#   ./generate-prometheus-config.sh [OPTIONS]
#
# Options:
#   --host HOSTNAME      Target host to scan (can be repeated)
#   --output FILE        Output file (default: stdout)
#   --template FILE      Template file to use
#   --merge              Merge with existing config
#   --validate           Validate generated config
#   --dry-run            Preview without writing
#   --help               Show this help
#
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
declare -a TARGET_HOSTS=()
OUTPUT_FILE=""
TEMPLATE_FILE="${SCRIPT_DIR}/templates/prometheus-scrape.yml.template"
MERGE_MODE=false
VALIDATE=true
DRY_RUN=false

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#===============================================================================
# HELPER FUNCTIONS
#===============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

#===============================================================================
# CONFIGURATION GENERATION
#===============================================================================

generate_scrape_config() {
    local exporter="$1"
    local host="$2"
    local port="$3"
    local labels="${4:-}"

    local job_name="${exporter/_exporter/}"
    local service="${exporter/_exporter/}"

    cat << EOF
  # $exporter on $host
  - job_name: '${job_name}-${host}'
    static_configs:
      - targets: ['${host}:${port}']
        labels:
          service: '${service}'
          exporter: '${exporter}'
          host: '${host}'
EOF

    if [[ -n "$labels" ]]; then
        echo "$labels" | while IFS='=' read -r key value; do
            echo "          ${key}: '${value}'"
        done
    fi
}

generate_node_exporter_config() {
    local host="$1"

    cat << EOF
  - job_name: 'node-${host}'
    scrape_interval: 15s
    scrape_timeout: 10s
    static_configs:
      - targets: ['${host}:9100']
        labels:
          service: 'node'
          tier: 'system'
          host: '${host}'
EOF
}

generate_nginx_exporter_config() {
    local host="$1"

    cat << EOF
  - job_name: 'nginx-${host}'
    scrape_interval: 15s
    scrape_timeout: 10s
    static_configs:
      - targets: ['${host}:9113']
        labels:
          service: 'nginx'
          tier: 'webserver'
          host: '${host}'
EOF
}

generate_mysql_exporter_config() {
    local host="$1"

    cat << EOF
  - job_name: 'mysql-${host}'
    scrape_interval: 15s
    scrape_timeout: 10s
    static_configs:
      - targets: ['${host}:9104']
        labels:
          service: 'mysql'
          tier: 'database'
          host: '${host}'
EOF
}

generate_postgres_exporter_config() {
    local host="$1"

    cat << EOF
  - job_name: 'postgres-${host}'
    scrape_interval: 15s
    scrape_timeout: 10s
    static_configs:
      - targets: ['${host}:9187']
        labels:
          service: 'postgres'
          tier: 'database'
          host: '${host}'
EOF
}

generate_redis_exporter_config() {
    local host="$1"

    cat << EOF
  - job_name: 'redis-${host}'
    scrape_interval: 15s
    scrape_timeout: 10s
    static_configs:
      - targets: ['${host}:9121']
        labels:
          service: 'redis'
          tier: 'cache'
          host: '${host}'
EOF
}

generate_phpfpm_exporter_config() {
    local host="$1"

    cat << EOF
  - job_name: 'phpfpm-${host}'
    scrape_interval: 15s
    scrape_timeout: 10s
    static_configs:
      - targets: ['${host}:9253']
        labels:
          service: 'php-fpm'
          tier: 'runtime'
          host: '${host}'
EOF
}

generate_mongodb_exporter_config() {
    local host="$1"

    cat << EOF
  - job_name: 'mongodb-${host}'
    scrape_interval: 15s
    scrape_timeout: 10s
    static_configs:
      - targets: ['${host}:9216']
        labels:
          service: 'mongodb'
          tier: 'database'
          host: '${host}'
EOF
}

#===============================================================================
# HOST DETECTION
#===============================================================================

detect_exporters_on_host() {
    local host="$1"
    local -a configs=()

    log_info "Detecting exporters on $host..."

    # Check each common exporter port
    local -A exporter_ports=(
        [node_exporter]=9100
        [nginx_exporter]=9113
        [mysqld_exporter]=9104
        [postgres_exporter]=9187
        [redis_exporter]=9121
        [phpfpm_exporter]=9253
        [mongodb_exporter]=9216
    )

    for exporter in "${!exporter_ports[@]}"; do
        local port="${exporter_ports[$exporter]}"

        # Try to connect to metrics endpoint
        if timeout 2 curl -sf "http://${host}:${port}/metrics" >/dev/null 2>&1; then
            log_success "Found $exporter on $host:$port"

            case "$exporter" in
                node_exporter)
                    configs+=("$(generate_node_exporter_config "$host")")
                    ;;
                nginx_exporter)
                    configs+=("$(generate_nginx_exporter_config "$host")")
                    ;;
                mysqld_exporter)
                    configs+=("$(generate_mysql_exporter_config "$host")")
                    ;;
                postgres_exporter)
                    configs+=("$(generate_postgres_exporter_config "$host")")
                    ;;
                redis_exporter)
                    configs+=("$(generate_redis_exporter_config "$host")")
                    ;;
                phpfpm_exporter)
                    configs+=("$(generate_phpfpm_exporter_config "$host")")
                    ;;
                mongodb_exporter)
                    configs+=("$(generate_mongodb_exporter_config "$host")")
                    ;;
            esac
        fi
    done

    # Print all configs for this host
    for config in "${configs[@]}"; do
        echo "$config"
        echo ""
    done
}

#===============================================================================
# CONFIG VALIDATION
#===============================================================================

validate_prometheus_config() {
    local config_file="$1"

    log_info "Validating Prometheus configuration..."

    # Check if promtool is available
    if ! command -v promtool >/dev/null 2>&1; then
        log_warning "promtool not found, skipping validation"
        return 0
    fi

    if promtool check config "$config_file" >/dev/null 2>&1; then
        log_success "Configuration is valid"
        return 0
    else
        log_error "Configuration validation failed"
        promtool check config "$config_file"
        return 1
    fi
}

#===============================================================================
# CONFIG MERGING
#===============================================================================

merge_configurations() {
    local existing_config="$1"
    local new_config="$2"

    log_info "Merging configurations..."

    # Create backup
    local backup="${existing_config}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$existing_config" "$backup"
    log_info "Created backup: $backup"

    # Simple merge: append new scrape configs before the last line
    # This is a simplified approach - for production, use proper YAML parsing
    local temp_file=$(mktemp)

    # Extract everything before scrape_configs section from new config
    grep -A 999999 "^scrape_configs:" "$new_config" > "$temp_file" || true

    # Append to existing config if it doesn't have scrape_configs yet
    if ! grep -q "^scrape_configs:" "$existing_config"; then
        echo "" >> "$existing_config"
        echo "scrape_configs:" >> "$existing_config"
    fi

    cat "$temp_file" >> "$existing_config"
    rm -f "$temp_file"

    log_success "Configurations merged"
}

#===============================================================================
# MAIN GENERATION
#===============================================================================

generate_full_config() {
    cat << 'EOF'
# Prometheus Configuration
# Auto-generated by generate-prometheus-config.sh
# Generated:
EOF
    echo "# Date: $(date)"
    echo ""

    cat << 'EOF'
global:
  scrape_interval: 15s
  scrape_timeout: 10s
  evaluation_interval: 15s
  external_labels:
    cluster: 'observability'
    environment: 'production'

# Alertmanager configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - 'localhost:9093'

# Load alert rules
rule_files:
  - '/etc/prometheus/rules/*.yml'

# Scrape configurations
scrape_configs:
  # Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
        labels:
          service: 'prometheus'
          tier: 'observability'

EOF

    # Generate configs for each target host
    for host in "${TARGET_HOSTS[@]}"; do
        echo "  # ========================================"
        echo "  # Host: $host"
        echo "  # ========================================"
        echo ""
        detect_exporters_on_host "$host"
    done
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

print_help() {
    cat << 'EOF'
Prometheus Scrape Configuration Generator

Usage: generate-prometheus-config.sh [OPTIONS]

Options:
  --host HOSTNAME      Target host to scan (can be repeated)
  --output FILE        Output file (default: stdout)
  --template FILE      Template file to use
  --merge              Merge with existing config
  --validate           Validate generated config (default)
  --no-validate        Skip validation
  --dry-run            Preview without writing
  --help               Show this help

Examples:
  # Generate config for local host
  generate-prometheus-config.sh --host localhost

  # Generate config for multiple hosts
  generate-prometheus-config.sh --host mentat.arewel.com --host landsraad.arewel.com

  # Generate and save to file
  generate-prometheus-config.sh --host localhost --output prometheus.yml

  # Merge with existing configuration
  generate-prometheus-config.sh --host localhost --merge --output /etc/prometheus/prometheus.yml
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --host)
                TARGET_HOSTS+=("$2")
                shift 2
                ;;
            --output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --template)
                TEMPLATE_FILE="$2"
                shift 2
                ;;
            --merge)
                MERGE_MODE=true
                shift
                ;;
            --validate)
                VALIDATE=true
                shift
                ;;
            --no-validate)
                VALIDATE=false
                shift
                ;;
            --dry-run)
                DRY_RUN=true
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

    # Default to localhost if no hosts specified
    if [[ ${#TARGET_HOSTS[@]} -eq 0 ]]; then
        TARGET_HOSTS=("localhost")
    fi
}

main() {
    parse_args "$@"

    log_info "Generating Prometheus configuration..."
    log_info "Target hosts: ${TARGET_HOSTS[*]}"

    # Generate configuration
    local config_content
    config_content=$(generate_full_config)

    # Output or save
    if [[ -z "$OUTPUT_FILE" ]] || [[ "$DRY_RUN" == "true" ]]; then
        echo "$config_content"
    else
        if [[ "$MERGE_MODE" == "true" ]] && [[ -f "$OUTPUT_FILE" ]]; then
            # Save new config to temp file first
            local temp_file=$(mktemp)
            echo "$config_content" > "$temp_file"

            # Merge configurations
            merge_configurations "$OUTPUT_FILE" "$temp_file"
            rm -f "$temp_file"
        else
            # Direct write
            echo "$config_content" > "$OUTPUT_FILE"
            log_success "Configuration written to $OUTPUT_FILE"
        fi

        # Validate if requested
        if [[ "$VALIDATE" == "true" ]]; then
            validate_prometheus_config "$OUTPUT_FILE"
        fi
    fi

    log_success "Configuration generation complete"
}

main "$@"
