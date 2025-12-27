#!/bin/bash
#===============================================================================
# Checksum Generator for Observability Stack Components
# Automatically fetches and generates SHA256 checksums from official sources
#===============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKSUMS_FILE="${SCRIPT_DIR}/../config/checksums.sha256"
TEMP_DIR="/tmp/observability-checksums-$$"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TEMP_DIR"

#===============================================================================
# COMPONENT DEFINITIONS
#===============================================================================

# Component URLs and versions
declare -A COMPONENTS=(
    ["loki"]="2.9.3|https://github.com/grafana/loki/releases/download/v2.9.3/loki-linux-amd64.zip"
    ["grafana"]="10.2.3|https://dl.grafana.com/oss/release/grafana-10.2.3.linux-amd64.tar.gz"
    ["nginx_exporter"]="0.11.0|https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v0.11.0/nginx-prometheus-exporter_0.11.0_linux_amd64.tar.gz"
    ["mysqld_exporter"]="0.15.1|https://github.com/prometheus/mysqld_exporter/releases/download/v0.15.1/mysqld_exporter-0.15.1.linux-amd64.tar.gz"
    ["phpfpm_exporter"]="2.2.0|https://github.com/hipages/php-fpm_exporter/releases/download/v2.2.0/php-fpm_exporter_2.2.0_linux_amd64"
    ["fail2ban_exporter"]="0.4.0|https://gitlab.com/hectorjsmith/fail2ban-prometheus-exporter/-/releases/v0.4.0/downloads/fail2ban-prometheus-exporter_0.4.0_linux_amd64.tar.gz"
    ["promtail"]="2.9.3|https://github.com/grafana/loki/releases/download/v2.9.3/promtail-linux-amd64.zip"
)

#===============================================================================
# FUNCTIONS
#===============================================================================

# Download and generate checksum for a component
generate_checksum() {
    local component="$1"
    local version_url="${COMPONENTS[$component]}"
    local version="${version_url%%|*}"
    local url="${version_url##*|}"
    local filename=$(basename "$url")

    log_info "Processing $component:$version..."

    # Download file
    log_info "  Downloading $filename..."
    if ! wget -q --show-progress -O "$TEMP_DIR/$filename" "$url"; then
        log_error "  Failed to download $component from $url"
        return 1
    fi

    # Calculate checksum
    log_info "  Calculating SHA256 checksum..."
    local checksum
    checksum=$(sha256sum "$TEMP_DIR/$filename" | awk '{print $1}')

    if [[ -z "$checksum" ]] || [[ ${#checksum} -ne 64 ]]; then
        log_error "  Invalid checksum generated for $component"
        return 1
    fi

    log_success "  $component:$version"
    log_info "  Checksum: $checksum"
    echo "$checksum  $component:$version"

    # Clean up downloaded file
    rm -f "$TEMP_DIR/$filename"

    return 0
}

# Update checksums file
update_checksums_file() {
    local component="$1"
    local version="$2"
    local checksum="$3"

    # Replace NEEDS_VERIFICATION with actual checksum
    if grep -q "${component}:${version}" "$CHECKSUMS_FILE"; then
        sed -i "s/^NEEDS_VERIFICATION  ${component}:${version}$/${checksum}  ${component}:${version}/" "$CHECKSUMS_FILE"
        log_success "Updated $component:$version in checksums file"
    else
        log_warn "Entry for $component:$version not found in checksums file"
    fi
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    log_info "Observability Stack - Checksum Generator"
    log_info "=========================================="
    echo ""

    if [[ ! -f "$CHECKSUMS_FILE" ]]; then
        log_error "Checksums file not found: $CHECKSUMS_FILE"
        exit 1
    fi

    log_info "Generating checksums for ${#COMPONENTS[@]} components..."
    echo ""

    local success_count=0
    local total_count=${#COMPONENTS[@]}

    for component in "${!COMPONENTS[@]}"; do
        echo ""
        if result=$(generate_checksum "$component" 2>&1); then
            echo "$result"

            # Extract checksum and version from result
            local checksum version
            checksum=$(echo "$result" | tail -1 | awk '{print $1}')
            version="${COMPONENTS[$component]%%|*}"

            # Update checksums file
            update_checksums_file "$component" "$version" "$checksum"

            ((success_count++))
        else
            echo "$result"
            log_error "Failed to process $component"
        fi
    done

    echo ""
    log_info "=========================================="
    log_info "Summary: $success_count/$total_count components processed successfully"
    echo ""

    if [[ $success_count -eq $total_count ]]; then
        log_success "All checksums generated successfully!"
        log_info "Checksums file updated: $CHECKSUMS_FILE"
        echo ""
        log_info "Next steps:"
        echo "  1. Review the updated checksums file"
        echo "  2. Verify checksums against official sources"
        echo "  3. Commit the updated checksums file"
        echo ""
        exit 0
    else
        log_warn "Some checksums could not be generated"
        log_info "Please manually verify and update the checksums file"
        exit 1
    fi
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
