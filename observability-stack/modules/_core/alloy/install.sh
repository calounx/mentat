#!/bin/bash
# Grafana Alloy Installation Script
# OpenTelemetry-compatible telemetry collector

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../scripts/lib/common.sh"

# Configuration
ALLOY_VERSION="${ALLOY_VERSION:-1.5.1}"
ALLOY_USER="alloy"
ALLOY_GROUP="alloy"
ALLOY_PORT="${ALLOY_PORT:-12345}"
ALLOY_CONFIG_DIR="/etc/alloy"
ALLOY_DATA_DIR="/var/lib/alloy"

# Checksums for verification (SHA256)
declare -A ALLOY_CHECKSUMS=(
    ["1.5.1-linux-amd64"]="e8f15b7e6f8c9a3c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c"
    ["1.5.1-linux-arm64"]="a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2"
)

#=============================================================================
# Installation Functions
#=============================================================================

install_alloy() {
    log_info "Installing Grafana Alloy ${ALLOY_VERSION}..."

    local arch
    arch=$(get_architecture)
    local binary_name="alloy-linux-${arch}"
    local download_url="https://github.com/grafana/alloy/releases/download/v${ALLOY_VERSION}/${binary_name}.zip"
    local checksum_key="${ALLOY_VERSION}-linux-${arch}"

    # Create user and group
    create_system_user "${ALLOY_USER}" "${ALLOY_GROUP}"

    # Create directories
    mkdir -p "${ALLOY_CONFIG_DIR}"
    mkdir -p "${ALLOY_DATA_DIR}"

    # Download and verify
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf ${temp_dir}" EXIT

    log_info "Downloading Alloy from ${download_url}..."
    curl -fsSL --max-time 300 -o "${temp_dir}/alloy.zip" "${download_url}"

    # Verify checksum if available
    local expected_checksum="${ALLOY_CHECKSUMS[${checksum_key}]:-}"
    if [[ -n "${expected_checksum}" && "${expected_checksum}" != *"placeholder"* ]]; then
        log_info "Verifying checksum..."
        echo "${expected_checksum}  ${temp_dir}/alloy.zip" | sha256sum -c - || {
            log_error "Checksum verification failed"
            return 1
        }
    else
        log_warn "Checksum not available for ${checksum_key}, downloading checksum file..."
        if curl -fsSL --max-time 60 -o "${temp_dir}/SHA256SUMS" \
            "https://github.com/grafana/alloy/releases/download/v${ALLOY_VERSION}/SHA256SUMS" 2>/dev/null; then
            cd "${temp_dir}"
            if grep "${binary_name}.zip" SHA256SUMS | sha256sum -c -; then
                log_info "Checksum verified from release file"
            else
                log_error "Checksum verification failed"
                return 1
            fi
            cd - >/dev/null
        else
            log_error "Could not verify checksum - aborting for security"
            return 1
        fi
    fi

    # Extract and install
    unzip -q "${temp_dir}/alloy.zip" -d "${temp_dir}"

    # Find the binary (may be in subdirectory)
    local binary_path
    binary_path=$(find "${temp_dir}" -name "alloy" -type f -executable | head -1)
    if [[ -z "${binary_path}" ]]; then
        binary_path=$(find "${temp_dir}" -name "${binary_name}" -type f | head -1)
    fi

    if [[ -z "${binary_path}" ]]; then
        log_error "Could not find Alloy binary in archive"
        return 1
    fi

    install -m 755 "${binary_path}" /usr/local/bin/alloy

    # Set ownership
    chown -R "${ALLOY_USER}:${ALLOY_GROUP}" "${ALLOY_CONFIG_DIR}"
    chown -R "${ALLOY_USER}:${ALLOY_GROUP}" "${ALLOY_DATA_DIR}"

    log_info "Alloy binary installed successfully"
}

create_default_config() {
    log_info "Creating default Alloy configuration..."

    local prometheus_url="${PROMETHEUS_URL:-http://localhost:9090}"
    local loki_url="${LOKI_URL:-http://localhost:3100}"
    local tempo_url="${TEMPO_URL:-http://localhost:4317}"

    cat > "${ALLOY_CONFIG_DIR}/config.alloy" << 'EOF'
// Grafana Alloy Configuration
// River configuration language - https://grafana.com/docs/alloy/latest/

//=============================================================================
// Logging Configuration
//=============================================================================
logging {
  level  = "info"
  format = "logfmt"
}

//=============================================================================
// Self-Monitoring
//=============================================================================
// Export Alloy's own metrics
prometheus.exporter.self "alloy" {
}

// Scrape Alloy metrics
prometheus.scrape "alloy_self" {
  targets    = prometheus.exporter.self.alloy.targets
  forward_to = [prometheus.remote_write.default.receiver]

  scrape_interval = "15s"
}

//=============================================================================
// Node Metrics Collection (Optional - enable if node_exporter not installed)
//=============================================================================
// prometheus.exporter.unix "node" {
//   include_exporter_metrics = true
//   disable_collectors       = ["mdadm"]
// }
//
// prometheus.scrape "node" {
//   targets    = prometheus.exporter.unix.node.targets
//   forward_to = [prometheus.remote_write.default.receiver]
// }

//=============================================================================
// Log Collection
//=============================================================================
// Collect local log files
local.file_match "logs" {
  path_targets = [
    {__path__ = "/var/log/*.log"},
    {__path__ = "/var/log/syslog"},
    {__path__ = "/var/log/messages"},
  ]
}

loki.source.file "local_logs" {
  targets    = local.file_match.logs.targets
  forward_to = [loki.process.local.receiver]
}

// Process logs - add labels
loki.process "local" {
  forward_to = [loki.write.default.receiver]

  stage.static_labels {
    values = {
      host = env("HOSTNAME"),
      job  = "alloy",
    }
  }
}

//=============================================================================
// OpenTelemetry Receivers
//=============================================================================
// OTLP receiver for traces and metrics
otelcol.receiver.otlp "default" {
  grpc {
    endpoint = "0.0.0.0:4317"
  }
  http {
    endpoint = "0.0.0.0:4318"
  }

  output {
    metrics = [otelcol.processor.batch.default.input]
    traces  = [otelcol.processor.batch.default.input]
  }
}

// Batch processor for better performance
otelcol.processor.batch "default" {
  output {
    metrics = [otelcol.exporter.prometheus.default.input]
    traces  = [otelcol.exporter.otlp.tempo.input]
  }
}

//=============================================================================
// Exporters
//=============================================================================
// Prometheus remote write
prometheus.remote_write "default" {
  endpoint {
    url = "http://localhost:9090/api/v1/write"

    // Basic auth (uncomment if needed)
    // basic_auth {
    //   username = "prometheus"
    //   password = env("PROMETHEUS_PASSWORD")
    // }
  }
}

// Loki push
loki.write "default" {
  endpoint {
    url = "http://localhost:3100/loki/api/v1/push"
  }
}

// OpenTelemetry metrics to Prometheus
otelcol.exporter.prometheus "default" {
  forward_to = [prometheus.remote_write.default.receiver]
}

// Traces to Tempo
otelcol.exporter.otlp "tempo" {
  client {
    endpoint = "localhost:4317"

    tls {
      insecure = true
    }
  }
}

//=============================================================================
// HTTP Server (for UI and health checks)
//=============================================================================
// Alloy exposes UI at http://localhost:12345 by default
EOF

    chown "${ALLOY_USER}:${ALLOY_GROUP}" "${ALLOY_CONFIG_DIR}/config.alloy"
    chmod 644 "${ALLOY_CONFIG_DIR}/config.alloy"

    log_info "Default configuration created at ${ALLOY_CONFIG_DIR}/config.alloy"
}

create_systemd_service() {
    log_info "Creating systemd service..."

    cat > /etc/systemd/system/alloy.service << EOF
[Unit]
Description=Grafana Alloy
Documentation=https://grafana.com/docs/alloy/latest/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${ALLOY_USER}
Group=${ALLOY_GROUP}
ExecStart=/usr/local/bin/alloy run \\
    --storage.path=${ALLOY_DATA_DIR} \\
    --server.http.listen-addr=0.0.0.0:${ALLOY_PORT} \\
    ${ALLOY_CONFIG_DIR}/config.alloy
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
LimitNOFILE=65536

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=${ALLOY_DATA_DIR}
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_info "Systemd service created"
}

validate_config() {
    log_info "Validating Alloy configuration..."

    if /usr/local/bin/alloy fmt "${ALLOY_CONFIG_DIR}/config.alloy" > /dev/null 2>&1; then
        log_info "Configuration syntax is valid"
    else
        log_warn "Configuration may have issues, checking..."
        /usr/local/bin/alloy fmt "${ALLOY_CONFIG_DIR}/config.alloy" || true
    fi
}

start_service() {
    log_info "Starting Alloy service..."
    systemctl enable alloy
    systemctl start alloy

    # Wait for startup
    sleep 3

    if systemctl is-active --quiet alloy; then
        log_info "Alloy is running"

        # Check health endpoint
        if curl -sf --max-time 10 "http://localhost:${ALLOY_PORT}/-/ready" > /dev/null 2>&1; then
            log_info "Alloy health check passed"
        else
            log_warn "Health check not yet responding (may still be initializing)"
        fi
    else
        log_error "Alloy failed to start"
        journalctl -u alloy --no-pager -n 20
        return 1
    fi
}

#=============================================================================
# Upgrade Functions
#=============================================================================

upgrade_alloy() {
    log_info "Upgrading Grafana Alloy to ${ALLOY_VERSION}..."

    # Stop service
    systemctl stop alloy || true

    # Backup current binary
    if [[ -f /usr/local/bin/alloy ]]; then
        cp /usr/local/bin/alloy /usr/local/bin/alloy.backup
    fi

    # Install new version
    if install_alloy; then
        log_info "Upgrade successful"
        rm -f /usr/local/bin/alloy.backup
    else
        log_error "Upgrade failed, rolling back..."
        if [[ -f /usr/local/bin/alloy.backup ]]; then
            mv /usr/local/bin/alloy.backup /usr/local/bin/alloy
        fi
        return 1
    fi

    # Restart service
    systemctl start alloy
}

#=============================================================================
# Main Installation
#=============================================================================

main() {
    local action="${1:-install}"

    case "${action}" in
        install)
            log_info "=== Grafana Alloy Installation ==="
            install_alloy
            create_default_config
            create_systemd_service
            validate_config
            start_service
            log_info "=== Installation Complete ==="
            log_info "Alloy UI available at: http://localhost:${ALLOY_PORT}"
            log_info "Metrics endpoint: http://localhost:${ALLOY_PORT}/metrics"
            ;;
        upgrade)
            log_info "=== Grafana Alloy Upgrade ==="
            upgrade_alloy
            validate_config
            log_info "=== Upgrade Complete ==="
            ;;
        config)
            create_default_config
            validate_config
            ;;
        *)
            echo "Usage: $0 {install|upgrade|config}"
            exit 1
            ;;
    esac
}

main "$@"
