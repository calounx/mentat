#!/bin/bash
#===============================================================================
# Tempo Installation Script
# Distributed tracing backend - completes the observability triangle
#===============================================================================

set -euo pipefail

# Module configuration
MODULE_NAME="tempo"
MODULE_VERSION="${MODULE_VERSION:-2.6.1}"
INSTALL_PATH="/usr/local/bin/tempo"
CONFIG_DIR="/etc/tempo"
DATA_DIR="/var/lib/tempo"
LOG_DIR="/var/log/tempo"
SERVICE_NAME="tempo"

# Ports
TEMPO_HTTP_PORT=3200
TEMPO_GRPC_PORT=9095
OTLP_GRPC_PORT=4317
OTLP_HTTP_PORT=4318
JAEGER_THRIFT_HTTP_PORT=14268
JAEGER_GRPC_PORT=14250
ZIPKIN_PORT=9411

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${BASE_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

# Source common functions
if [[ -f "$BASE_DIR/scripts/lib/common.sh" ]]; then
    source "$BASE_DIR/scripts/lib/common.sh"
else
    echo "ERROR: common.sh not found"
    exit 1
fi

#===============================================================================
# Pre-flight checks
#===============================================================================

preflight_check() {
    log_info "Running pre-flight checks..."

    # Check disk space (need at least 2GB for traces)
    local available_space
    available_space=$(df -BG /var/lib | tail -1 | awk '{print $4}' | tr -d 'G')
    if [[ $available_space -lt 2 ]]; then
        log_error "Insufficient disk space. Need at least 2GB, have ${available_space}GB"
        return 1
    fi

    # Check if ports are available
    for port in $TEMPO_HTTP_PORT $OTLP_GRPC_PORT $OTLP_HTTP_PORT; do
        if ss -tlnp 2>/dev/null | grep -q ":${port} " || \
           netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
            log_warn "Port $port is already in use"
        fi
    done

    log_success "Pre-flight checks passed"
}

#===============================================================================
# User and directory setup
#===============================================================================

create_user() {
    if ! id tempo &>/dev/null; then
        log_info "Creating tempo user..."
        useradd --system --no-create-home --shell /bin/false tempo
    fi
}

create_directories() {
    log_info "Creating directories..."

    mkdir -p "$CONFIG_DIR"
    mkdir -p "$DATA_DIR"/{wal,blocks,compactor}
    mkdir -p "$LOG_DIR"

    chown -R tempo:tempo "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    chmod 755 "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
}

#===============================================================================
# Download and install
#===============================================================================

download_tempo() {
    log_info "Downloading Tempo v${MODULE_VERSION}..."

    local download_url="https://github.com/grafana/tempo/releases/download/v${MODULE_VERSION}/tempo_${MODULE_VERSION}_linux_amd64.tar.gz"
    local checksum_url="https://github.com/grafana/tempo/releases/download/v${MODULE_VERSION}/SHA256SUMS"
    local archive_name="tempo_${MODULE_VERSION}_linux_amd64.tar.gz"

    cd /tmp

    # Security: Require checksum verification
    if ! type download_and_verify &>/dev/null; then
        log_error "SECURITY: download_and_verify function not available"
        log_error "Cannot install without checksum verification"
        return 1
    fi

    if ! download_and_verify "$download_url" "$checksum_url" "$archive_name"; then
        log_error "Failed to download and verify Tempo"
        return 1
    fi

    # Extract
    tar -xzf "$archive_name"

    # Verify binary exists
    if [[ ! -f "tempo-linux-amd64" ]]; then
        # Try alternate name
        if [[ -f "tempo" ]]; then
            mv tempo tempo-linux-amd64
        else
            log_error "Tempo binary not found in archive"
            return 1
        fi
    fi

    log_success "Tempo downloaded and verified"
}

install_binary() {
    log_info "Installing Tempo binary..."

    # H-7: Stop service with robust 3-layer verification before binary replacement
    if systemctl list-units --type=service --all | grep -q "^[[:space:]]*$SERVICE_NAME.service" 2>/dev/null; then
        if type stop_and_verify_service &>/dev/null; then
            stop_and_verify_service "$SERVICE_NAME" "$INSTALL_PATH" || {
                log_error "Failed to stop $SERVICE_NAME safely"
                return 1
            }
        else
            # Fallback if stop_and_verify_service not available
            log_warn "stop_and_verify_service not available, using enhanced basic stop"
            systemctl stop "$SERVICE_NAME" 2>/dev/null || true

            # Wait for process to exit
            local wait_count=0
            while pgrep -f "$INSTALL_PATH" >/dev/null 2>&1 && [[ $wait_count -lt 30 ]]; do
                sleep 1
                ((wait_count++))
            done

            # Force kill if needed
            pkill -9 -f "$INSTALL_PATH" 2>/dev/null || true

            # CRITICAL: Wait for file lock release
            wait_count=0
            while [[ $wait_count -lt 30 ]]; do
                if ! lsof "$INSTALL_PATH" &>/dev/null 2>&1; then
                    log_success "Binary file lock released"
                    break
                fi
                sleep 1
                ((wait_count++))
            done

            # Final verification
            if lsof "$INSTALL_PATH" &>/dev/null 2>&1; then
                log_error "File lock still held on $INSTALL_PATH - cannot replace binary"
                return 1
            fi
        fi
    fi

    # Install binary
    cp /tmp/tempo-linux-amd64 "$INSTALL_PATH"
    chown root:root "$INSTALL_PATH"
    chmod 755 "$INSTALL_PATH"

    # Verify installation
    if ! "$INSTALL_PATH" --version &>/dev/null; then
        log_error "Tempo binary verification failed"
        return 1
    fi

    log_success "Tempo binary installed: $("$INSTALL_PATH" --version 2>&1 | head -1)"
}

#===============================================================================
# Configuration
#===============================================================================

create_config() {
    log_info "Creating Tempo configuration..."

    cat > "$CONFIG_DIR/tempo.yaml" << 'EOF'
# Tempo Configuration
# Optimized for single-node deployment

server:
  http_listen_port: 3200
  grpc_listen_port: 9095
  log_level: info

# Distributor receives traces from various sources
distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318
    jaeger:
      protocols:
        thrift_http:
          endpoint: 0.0.0.0:14268
        grpc:
          endpoint: 0.0.0.0:14250
        thrift_binary:
          endpoint: 0.0.0.0:6832
        thrift_compact:
          endpoint: 0.0.0.0:6831
    zipkin:
      endpoint: 0.0.0.0:9411

# Ingester writes traces to storage
ingester:
  trace_idle_period: 10s
  max_block_bytes: 1048576  # 1MB
  max_block_duration: 5m
  lifecycler:
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1

# Compactor merges blocks
compactor:
  compaction:
    block_retention: 336h  # 14 days
  ring:
    kvstore:
      store: inmemory

# Storage configuration
storage:
  trace:
    backend: local
    local:
      path: /var/lib/tempo/blocks
    wal:
      path: /var/lib/tempo/wal
    block:
      bloom_filter_false_positive: 0.05
      v2_index_downsample_bytes: 1048576
      v2_encoding: zstd

# Metrics generator for span metrics and service graphs
metrics_generator:
  registry:
    external_labels:
      source: tempo
  storage:
    path: /var/lib/tempo/generator/wal
    remote_write:
      - url: http://localhost:9090/api/v1/write
        send_exemplars: true
  traces_storage:
    path: /var/lib/tempo/generator/traces
  processor:
    service_graphs:
      wait: 10s
      max_items: 10000
      workers: 10
      histogram_buckets: [0.1, 0.2, 0.4, 0.8, 1.6, 3.2, 6.4, 12.8]
      dimensions:
        - service.namespace
        - service.name
    span_metrics:
      histogram_buckets: [0.002, 0.004, 0.008, 0.016, 0.032, 0.064, 0.128, 0.256, 0.512, 1.024, 2.048, 4.096, 8.192, 16.384]
      dimensions:
        - service.name
        - span.name
        - span.kind
        - status.code

# Query frontend
query_frontend:
  search:
    duration_slo: 5s
    throughput_bytes_slo: 1073741824
  trace_by_id:
    duration_slo: 5s

# Overrides for multi-tenancy (disabled for single tenant)
overrides:
  defaults:
    metrics_generator:
      processors:
        - service-graphs
        - span-metrics

# Usage reporting (disabled)
usage_report:
  reporting_enabled: false
EOF

    chown tempo:tempo "$CONFIG_DIR/tempo.yaml"
    chmod 644 "$CONFIG_DIR/tempo.yaml"

    log_success "Tempo configuration created"
}

#===============================================================================
# Systemd service
#===============================================================================

create_service() {
    log_info "Creating systemd service..."

    cat > /etc/systemd/system/tempo.service << EOF
[Unit]
Description=Grafana Tempo - Distributed Tracing Backend
Documentation=https://grafana.com/docs/tempo/latest/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=tempo
Group=tempo
ExecStart=${INSTALL_PATH} -config.file=${CONFIG_DIR}/tempo.yaml
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5s
LimitNOFILE=65536
LimitNPROC=65536

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ReadWritePaths=${DATA_DIR}
ReadWritePaths=${LOG_DIR}

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload

    log_success "Systemd service created"
}

#===============================================================================
# Start and verify
#===============================================================================

start_service() {
    log_info "Starting Tempo..."

    systemctl enable tempo
    systemctl start tempo

    # Wait for service to be ready
    local max_attempts=30
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if curl -sf "http://localhost:${TEMPO_HTTP_PORT}/ready" &>/dev/null; then
            log_success "Tempo is ready"
            return 0
        fi
        sleep 1
        ((attempt++))
    done

    log_error "Tempo failed to become ready"
    journalctl -u tempo --no-pager -n 50
    return 1
}

verify_installation() {
    log_info "Verifying Tempo installation..."

    # Check service status
    if ! systemctl is-active --quiet tempo; then
        log_error "Tempo service is not running"
        return 1
    fi

    # Check HTTP endpoint
    if ! curl -sf "http://localhost:${TEMPO_HTTP_PORT}/ready" &>/dev/null; then
        log_error "Tempo HTTP endpoint not responding"
        return 1
    fi

    # Check OTLP endpoint
    if ! nc -z localhost $OTLP_GRPC_PORT 2>/dev/null; then
        log_warn "OTLP gRPC endpoint not responding (may be normal if nc not installed)"
    fi

    log_success "Tempo installation verified"

    echo ""
    echo "Tempo endpoints:"
    echo "  HTTP API:     http://localhost:${TEMPO_HTTP_PORT}"
    echo "  OTLP gRPC:    localhost:${OTLP_GRPC_PORT}"
    echo "  OTLP HTTP:    http://localhost:${OTLP_HTTP_PORT}"
    echo "  Jaeger HTTP:  http://localhost:${JAEGER_THRIFT_HTTP_PORT}"
    echo "  Zipkin:       http://localhost:${ZIPKIN_PORT}"
    echo ""
}

#===============================================================================
# Grafana datasource
#===============================================================================

create_grafana_datasource() {
    log_info "Creating Grafana datasource for Tempo..."

    local datasource_dir="$BASE_DIR/grafana/provisioning/datasources"

    if [[ -d "$datasource_dir" ]]; then
        cat > "$datasource_dir/tempo.yaml" << 'EOF'
apiVersion: 1

datasources:
  - name: Tempo
    type: tempo
    uid: tempo
    url: http://localhost:3200
    access: proxy
    isDefault: false
    jsonData:
      httpMethod: GET
      tracesToLogs:
        datasourceUid: loki
        mapTagNamesEnabled: true
        mappedTags:
          - key: service.name
            value: service_name
        filterByTraceID: true
        filterBySpanID: true
      tracesToMetrics:
        datasourceUid: prometheus
        queries:
          - name: Request rate
            query: sum(rate(traces_spanmetrics_calls_total{$$__tags}[5m]))
          - name: Error rate
            query: sum(rate(traces_spanmetrics_calls_total{$$__tags,status_code="STATUS_CODE_ERROR"}[5m]))
      serviceMap:
        datasourceUid: prometheus
      nodeGraph:
        enabled: true
      lokiSearch:
        datasourceUid: loki
EOF
        log_success "Grafana datasource created"
    else
        log_warn "Grafana provisioning directory not found"
    fi
}

#===============================================================================
# Main
#===============================================================================

main() {
    log_info "Installing Tempo v${MODULE_VERSION}..."

    preflight_check
    create_user
    create_directories
    download_tempo
    install_binary
    create_config
    create_service
    start_service
    verify_installation
    create_grafana_datasource

    log_success "Tempo installation complete!"
}

# Run main
main "$@"
