#!/bin/bash
#===============================================================================
# Grafana Alloy Installation Script
# Production-ready unified telemetry collector for metrics, logs, and traces
#
# Environment variables:
#   MODULE_NAME        - Name of the module (alloy)
#   MODULE_VERSION     - Version to install (default: 1.5.1)
#   MODULE_PORT        - HTTP listen port (default: 12345)
#   DEPLOYMENT_ROLE    - Role: observability|monitored|vpsmanager (default: monitored)
#   FORCE_MODE         - Set to "true" to force reinstall
#   PROMETHEUS_URL     - Prometheus remote_write URL
#   LOKI_URL           - Loki push URL
#   TEMPO_URL          - Tempo OTLP endpoint
#   OBSERVABILITY_IP   - IP of observability stack (for firewall)
#   HOST_NAME          - Hostname for labels (default: $(hostname))
#   ENVIRONMENT        - Environment label (default: production)
#
# Usage:
#   ./install.sh [--force] [--role=observability|monitored|vpsmanager]
#===============================================================================

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../../../scripts/lib" 2>/dev/null && pwd)" || LIB_DIR="$(cd "$SCRIPT_DIR/../../scripts/lib" && pwd)"

if [[ -f "$LIB_DIR/common.sh" ]]; then
    source "$LIB_DIR/common.sh"
else
    # Minimal fallback if common.sh not available
    log_info() { echo "[INFO] $1"; }
    log_success() { echo "[SUCCESS] $1"; }
    log_skip() { echo "[SKIP] $1"; }
    log_warn() { echo "[WARN] $1"; }
    log_error() { echo "[ERROR] $1" >&2; }
    log_debug() { [[ "${DEBUG:-false}" == "true" ]] && echo "[DEBUG] $1"; }
fi

#===============================================================================
# CONFIGURATION
#===============================================================================

MODULE_NAME="${MODULE_NAME:-alloy}"
MODULE_VERSION="${MODULE_VERSION:-1.5.1}"
MODULE_PORT="${MODULE_PORT:-12345}"
DEPLOYMENT_ROLE="${DEPLOYMENT_ROLE:-monitored}"
FORCE_MODE="${FORCE_MODE:-false}"

# Endpoints (set based on role if not explicitly provided)
PROMETHEUS_URL="${PROMETHEUS_URL:-}"
LOKI_URL="${LOKI_URL:-}"
TEMPO_URL="${TEMPO_URL:-}"
OBSERVABILITY_IP="${OBSERVABILITY_IP:-}"

# Labels
HOST_NAME="${HOST_NAME:-$(hostname -f 2>/dev/null || hostname)}"
ENVIRONMENT="${ENVIRONMENT:-production}"

# Installation paths
BINARY_NAME="alloy"
INSTALL_PATH="/usr/local/bin/$BINARY_NAME"
SERVICE_NAME="alloy"
USER_NAME="alloy"
GROUP_NAME="alloy"
CONFIG_DIR="/etc/alloy"
DATA_DIR="/var/lib/alloy"
LOG_DIR="/var/log/alloy"
BACKUP_DIR="${BACKUP_DIR:-/var/lib/observability-upgrades/backups/alloy}"

# Alloy-specific ports
OTLP_GRPC_PORT="${OTLP_GRPC_PORT:-4317}"
OTLP_HTTP_PORT="${OTLP_HTTP_PORT:-4318}"

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --force|-f)
            FORCE_MODE=true
            ;;
        --role=*)
            DEPLOYMENT_ROLE="${arg#*=}"
            ;;
        --version=*)
            MODULE_VERSION="${arg#*=}"
            ;;
    esac
done

# Validate deployment role
case "$DEPLOYMENT_ROLE" in
    observability|monitored|vpsmanager)
        log_info "Deployment role: $DEPLOYMENT_ROLE"
        ;;
    *)
        log_error "Invalid deployment role: $DEPLOYMENT_ROLE"
        log_error "Valid roles: observability, monitored, vpsmanager"
        exit 1
        ;;
esac

#===============================================================================
# ARCHITECTURE DETECTION
#===============================================================================

get_architecture() {
    local arch
    arch=$(uname -m)

    case "$arch" in
        x86_64|amd64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l|armhf)
            echo "arm"
            ;;
        *)
            log_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
}

#===============================================================================
# VERSION DETECTION
#===============================================================================

get_installed_version() {
    if [[ -x "$INSTALL_PATH" ]]; then
        "$INSTALL_PATH" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo ""
    else
        echo ""
    fi
}

is_installed() {
    [[ "$FORCE_MODE" == "true" ]] && return 1
    [[ ! -x "$INSTALL_PATH" ]] && return 1
    local current_version
    current_version=$(get_installed_version)
    [[ "$current_version" == "$MODULE_VERSION" ]]
}

#===============================================================================
# BACKUP OPERATIONS
#===============================================================================

backup_alloy() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local hostname
    hostname=$(hostname)
    local backup_path="$BACKUP_DIR/$hostname/$timestamp"

    log_info "Creating backup at $backup_path..."
    mkdir -p "$backup_path"
    chmod 700 "$backup_path"

    # Backup binary
    if [[ -f "$INSTALL_PATH" ]]; then
        local current_version
        current_version=$(get_installed_version)
        cp -p "$INSTALL_PATH" "$backup_path/alloy-${current_version}" 2>/dev/null || true
        log_info "Backed up binary: alloy-${current_version}"
    fi

    # Backup configuration
    if [[ -d "$CONFIG_DIR" ]]; then
        cp -rp "$CONFIG_DIR" "$backup_path/config"
        log_info "Backed up configuration"
    fi

    # Backup systemd service
    if [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
        cp -p "/etc/systemd/system/${SERVICE_NAME}.service" "$backup_path/"
        log_info "Backed up service file"
    fi

    # Create backup metadata
    cat > "$backup_path/metadata.json" <<EOF
{
  "component": "alloy",
  "hostname": "$hostname",
  "timestamp": "$timestamp",
  "version": "$(get_installed_version)",
  "target_version": "$MODULE_VERSION",
  "deployment_role": "$DEPLOYMENT_ROLE",
  "created_by": "alloy-install"
}
EOF

    log_success "Backup created: $backup_path"
    echo "$backup_path"
}

restore_from_backup() {
    local backup_path="$1"

    if [[ ! -d "$backup_path" ]]; then
        log_error "Backup directory not found: $backup_path"
        return 1
    fi

    log_info "Restoring from backup: $backup_path"

    # Stop service
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    sleep 2

    # Restore binary
    local binary_backup
    binary_backup=$(ls "$backup_path"/alloy-* 2>/dev/null | head -1)
    if [[ -f "$binary_backup" ]]; then
        cp -p "$binary_backup" "$INSTALL_PATH"
        chown root:root "$INSTALL_PATH"
        chmod 755 "$INSTALL_PATH"
        log_info "Restored binary"
    fi

    # Restore configuration
    if [[ -d "$backup_path/config" ]]; then
        rm -rf "$CONFIG_DIR"
        cp -rp "$backup_path/config" "$CONFIG_DIR"
        chown -R "$USER_NAME:$GROUP_NAME" "$CONFIG_DIR"
        log_info "Restored configuration"
    fi

    # Restore service file
    if [[ -f "$backup_path/${SERVICE_NAME}.service" ]]; then
        cp -p "$backup_path/${SERVICE_NAME}.service" "/etc/systemd/system/"
        systemctl daemon-reload
        log_info "Restored service file"
    fi

    # Start service
    systemctl start "$SERVICE_NAME"

    log_success "Restore completed"
    return 0
}

#===============================================================================
# INSTALLATION FUNCTIONS
#===============================================================================

create_user() {
    if ! id "$USER_NAME" &>/dev/null; then
        log_info "Creating user $USER_NAME..."
        useradd --no-create-home --shell /bin/false --system "$USER_NAME"
    fi

    # Add to groups for log access
    usermod -a -G adm "$USER_NAME" 2>/dev/null || true
    usermod -a -G systemd-journal "$USER_NAME" 2>/dev/null || true
    usermod -a -G www-data "$USER_NAME" 2>/dev/null || true

    # Create directories
    mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    chown -R "$USER_NAME:$GROUP_NAME" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    chmod 755 "$CONFIG_DIR"
    chmod 750 "$DATA_DIR" "$LOG_DIR"
}

install_binary() {
    log_info "Installing $MODULE_NAME v$MODULE_VERSION..."

    local arch
    arch=$(get_architecture)
    local archive_name="alloy-linux-${arch}.zip"
    local download_url="https://github.com/grafana/alloy/releases/download/v${MODULE_VERSION}/${archive_name}"
    local checksum_url="https://github.com/grafana/alloy/releases/download/v${MODULE_VERSION}/SHA256SUMS"

    cd /tmp

    # SECURITY: Download with checksum verification
    if type download_and_verify &>/dev/null; then
        if ! download_and_verify "$download_url" "$archive_name" "$checksum_url"; then
            log_error "SECURITY: Checksum verification failed for Alloy"
            log_error "Refusing to install unverified binary"
            return 1
        fi
    else
        # Fallback: Manual download and verification
        log_warn "download_and_verify not available, using manual verification"

        # Download archive
        if ! curl -fsSL --max-time 300 -o "$archive_name" "$download_url"; then
            log_error "Failed to download Alloy"
            return 1
        fi

        # Download and verify checksum
        if curl -fsSL --max-time 60 -o "SHA256SUMS" "$checksum_url" 2>/dev/null; then
            local expected_checksum
            expected_checksum=$(grep "$archive_name" SHA256SUMS | awk '{print $1}')
            local actual_checksum
            actual_checksum=$(sha256sum "$archive_name" | awk '{print $1}')

            if [[ "$expected_checksum" != "$actual_checksum" ]]; then
                log_error "SECURITY: Checksum verification FAILED!"
                log_error "  Expected: $expected_checksum"
                log_error "  Actual:   $actual_checksum"
                rm -f "$archive_name" SHA256SUMS
                return 1
            fi
            log_info "Checksum verified successfully"
        else
            log_error "SECURITY: Could not download checksum file - aborting"
            rm -f "$archive_name"
            return 1
        fi
    fi

    # Extract archive
    if ! unzip -o "$archive_name" -d alloy_extract; then
        log_error "Failed to extract archive"
        rm -f "$archive_name"
        return 1
    fi

    # Find and install binary
    local binary_path
    binary_path=$(find alloy_extract -name "alloy*" -type f -executable 2>/dev/null | head -1)
    if [[ -z "$binary_path" ]]; then
        # Try without executable flag (may not be set after extraction)
        binary_path=$(find alloy_extract -name "alloy-linux-*" -type f 2>/dev/null | head -1)
    fi

    if [[ -z "$binary_path" ]]; then
        log_error "Could not find Alloy binary in archive"
        rm -rf "$archive_name" alloy_extract SHA256SUMS
        return 1
    fi

    # Verify binary works
    chmod +x "$binary_path"
    if ! "$binary_path" --version &>/dev/null; then
        log_error "Downloaded binary failed version check"
        rm -rf "$archive_name" alloy_extract SHA256SUMS
        return 1
    fi

    # Install binary
    install -m 755 "$binary_path" "$INSTALL_PATH"

    # Cleanup
    rm -rf "$archive_name" alloy_extract SHA256SUMS

    log_success "$MODULE_NAME binary installed"
}

#===============================================================================
# CONFIGURATION GENERATION
#===============================================================================

generate_config() {
    local role="$1"
    local config_file="$CONFIG_DIR/config.alloy"

    log_info "Generating Alloy configuration for role: $role"

    # Check for role-specific template
    local template_file="$SCRIPT_DIR/configs/${role}.alloy"

    if [[ -f "$template_file" ]]; then
        log_info "Using template: $template_file"

        # Read template and substitute variables
        local config_content
        config_content=$(<"$template_file")

        # Substitute placeholders
        config_content="${config_content//\$\{HOST_NAME\}/$HOST_NAME}"
        config_content="${config_content//\$\{ENVIRONMENT\}/$ENVIRONMENT}"
        config_content="${config_content//\$\{MODULE_PORT\}/$MODULE_PORT}"
        config_content="${config_content//\$\{OTLP_GRPC_PORT\}/$OTLP_GRPC_PORT}"
        config_content="${config_content//\$\{OTLP_HTTP_PORT\}/$OTLP_HTTP_PORT}"

        # Set default URLs based on role if not provided
        case "$role" in
            observability)
                PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
                LOKI_URL="${LOKI_URL:-http://localhost:3100}"
                TEMPO_URL="${TEMPO_URL:-localhost:4317}"
                ;;
            monitored|vpsmanager)
                if [[ -n "$OBSERVABILITY_IP" ]]; then
                    PROMETHEUS_URL="${PROMETHEUS_URL:-http://${OBSERVABILITY_IP}:9090}"
                    LOKI_URL="${LOKI_URL:-http://${OBSERVABILITY_IP}:3100}"
                    TEMPO_URL="${TEMPO_URL:-${OBSERVABILITY_IP}:4317}"
                else
                    PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
                    LOKI_URL="${LOKI_URL:-http://localhost:3100}"
                    TEMPO_URL="${TEMPO_URL:-localhost:4317}"
                fi
                ;;
        esac

        config_content="${config_content//\$\{PROMETHEUS_URL\}/$PROMETHEUS_URL}"
        config_content="${config_content//\$\{LOKI_URL\}/$LOKI_URL}"
        config_content="${config_content//\$\{TEMPO_URL\}/$TEMPO_URL}"

        echo "$config_content" > "$config_file"
    else
        log_warn "Template not found: $template_file"
        log_info "Generating inline configuration..."
        generate_inline_config "$role" > "$config_file"
    fi

    chown "$USER_NAME:$GROUP_NAME" "$config_file"
    chmod 644 "$config_file"

    log_success "Configuration generated at $config_file"
}

generate_inline_config() {
    local role="$1"

    cat << 'ALLOY_CONFIG_HEADER'
// ============================================================================
// Grafana Alloy Configuration
// Generated by install.sh
// ============================================================================

// Logging configuration
logging {
  level  = "info"
  format = "logfmt"
}

ALLOY_CONFIG_HEADER

    # Self-monitoring (common to all roles)
    cat << 'ALLOY_SELF_MONITORING'
// ============================================================================
// Self-Monitoring
// ============================================================================

prometheus.exporter.self "alloy" { }

prometheus.scrape "alloy_self" {
  targets         = prometheus.exporter.self.alloy.targets
  forward_to      = [prometheus.remote_write.default.receiver]
  scrape_interval = "15s"
}

ALLOY_SELF_MONITORING

    # Role-specific configuration
    case "$role" in
        observability)
            generate_observability_config
            ;;
        monitored)
            generate_monitored_config
            ;;
        vpsmanager)
            generate_vpsmanager_config
            ;;
    esac
}

generate_observability_config() {
    cat << OBSERVABILITY_CONFIG
// ============================================================================
// Observability Stack Configuration
// Central telemetry collector for the observability infrastructure
// ============================================================================

// Local scrape targets - observability stack components
prometheus.scrape "observability_stack" {
  targets = [
    {__address__ = "localhost:9090", job = "prometheus", tier = "observability"},
    {__address__ = "localhost:3100", job = "loki", tier = "observability"},
    {__address__ = "localhost:3200", job = "tempo", tier = "observability"},
    {__address__ = "localhost:3000", job = "grafana", tier = "observability"},
    {__address__ = "localhost:9100", job = "node-exporter", tier = "observability"},
  ]
  forward_to      = [prometheus.remote_write.default.receiver]
  scrape_interval = "15s"
}

// Prometheus remote write (local)
prometheus.remote_write "default" {
  endpoint {
    url = "${PROMETHEUS_URL}/api/v1/write"
  }
}

// ============================================================================
// Log Collection
// ============================================================================

// Collect systemd journal
loki.source.journal "system_logs" {
  forward_to = [loki.process.system.receiver]
  labels     = {
    job  = "systemd-journal",
    tier = "observability",
    host = "$HOST_NAME",
  }
}

// Collect observability stack logs
local.file_match "observability_logs" {
  path_targets = [
    {__path__ = "/var/log/prometheus/*.log"},
    {__path__ = "/var/log/loki/*.log"},
    {__path__ = "/var/log/tempo/*.log"},
    {__path__ = "/var/log/grafana/*.log"},
  ]
}

loki.source.file "observability_files" {
  targets    = local.file_match.observability_logs.targets
  forward_to = [loki.process.system.receiver]
}

// Process and label logs
loki.process "system" {
  forward_to = [loki.write.default.receiver]

  stage.static_labels {
    values = {
      tier        = "observability",
      host        = "$HOST_NAME",
      environment = "$ENVIRONMENT",
    }
  }

  stage.json {
    expressions = {
      level = "level",
      msg   = "msg",
    }
  }

  stage.labels {
    values = {
      level = "",
    }
  }
}

// Loki writer
loki.write "default" {
  endpoint {
    url = "${LOKI_URL}/loki/api/v1/push"
  }
}

// ============================================================================
// Trace Collection (OTLP Receiver)
// ============================================================================

otelcol.receiver.otlp "default" {
  grpc {
    endpoint = "0.0.0.0:${OTLP_GRPC_PORT}"
  }
  http {
    endpoint = "0.0.0.0:${OTLP_HTTP_PORT}"
  }

  output {
    traces  = [otelcol.processor.batch.default.input]
    metrics = [otelcol.processor.batch.default.input]
    logs    = [otelcol.processor.batch.default.input]
  }
}

otelcol.processor.batch "default" {
  timeout             = "5s"
  send_batch_size     = 8192
  send_batch_max_size = 0

  output {
    traces  = [otelcol.exporter.otlp.tempo.input]
    metrics = [otelcol.exporter.prometheus.default.input]
    logs    = [otelcol.exporter.loki.default.input]
  }
}

otelcol.exporter.otlp "tempo" {
  client {
    endpoint = "${TEMPO_URL}"
    tls {
      insecure = true
    }
  }
}

otelcol.exporter.prometheus "default" {
  forward_to = [prometheus.remote_write.default.receiver]
}

otelcol.exporter.loki "default" {
  forward_to = [loki.write.default.receiver]
}
OBSERVABILITY_CONFIG
}

generate_monitored_config() {
    cat << MONITORED_CONFIG
// ============================================================================
// Monitored Node Configuration
// Ships metrics, logs, and traces to central observability stack
// ============================================================================

// Scrape local exporters
prometheus.scrape "local_exporters" {
  targets = [
    {__address__ = "localhost:9100", job = "node-exporter"},
    {__address__ = "localhost:9113", job = "nginx-exporter"},
    {__address__ = "localhost:9104", job = "mysql-exporter"},
    {__address__ = "localhost:9253", job = "phpfpm-exporter"},
  ]
  forward_to      = [prometheus.relabel.add_labels.receiver]
  scrape_interval = "15s"
}

// Add common labels
prometheus.relabel "add_labels" {
  forward_to = [prometheus.remote_write.default.receiver]

  rule {
    target_label = "host"
    replacement  = "$HOST_NAME"
  }
  rule {
    target_label = "environment"
    replacement  = "$ENVIRONMENT"
  }
  rule {
    target_label = "tier"
    replacement  = "application"
  }
}

// Remote write to observability stack
prometheus.remote_write "default" {
  endpoint {
    url = "${PROMETHEUS_URL}/api/v1/write"

    queue_config {
      capacity             = 10000
      max_shards           = 10
      min_shards           = 1
      max_samples_per_send = 5000
      batch_send_deadline  = "5s"
      min_backoff          = "30ms"
      max_backoff          = "5s"
    }
  }
}

// ============================================================================
// Log Collection
// ============================================================================

// Nginx access logs (JSON format)
local.file_match "nginx_access" {
  path_targets = [{__path__ = "/var/log/nginx/*access*.log"}]
}

loki.source.file "nginx_access" {
  targets    = local.file_match.nginx_access.targets
  forward_to = [loki.process.nginx_access.receiver]
}

loki.process "nginx_access" {
  forward_to = [loki.write.default.receiver]

  stage.json {
    expressions = {
      status  = "status",
      method  = "method",
      path    = "uri",
      latency = "request_time",
    }
  }

  stage.static_labels {
    values = {
      job         = "nginx-access",
      host        = "$HOST_NAME",
      environment = "$ENVIRONMENT",
      tier        = "application",
      component   = "webserver",
    }
  }

  stage.labels {
    values = {
      status = "",
    }
  }
}

// Nginx error logs
local.file_match "nginx_error" {
  path_targets = [{__path__ = "/var/log/nginx/*error*.log"}]
}

loki.source.file "nginx_error" {
  targets    = local.file_match.nginx_error.targets
  forward_to = [loki.process.nginx_error.receiver]
}

loki.process "nginx_error" {
  forward_to = [loki.write.default.receiver]

  stage.static_labels {
    values = {
      job         = "nginx-error",
      host        = "$HOST_NAME",
      environment = "$ENVIRONMENT",
      tier        = "application",
      component   = "webserver",
      level       = "error",
    }
  }
}

// PHP-FPM logs
local.file_match "phpfpm" {
  path_targets = [{__path__ = "/var/log/php*-fpm*.log"}]
}

loki.source.file "phpfpm" {
  targets    = local.file_match.phpfpm.targets
  forward_to = [loki.process.phpfpm.receiver]
}

loki.process "phpfpm" {
  forward_to = [loki.write.default.receiver]

  stage.static_labels {
    values = {
      job         = "php-fpm",
      host        = "$HOST_NAME",
      environment = "$ENVIRONMENT",
      tier        = "application",
      component   = "runtime",
    }
  }
}

// MySQL logs
local.file_match "mysql" {
  path_targets = [{__path__ = "/var/log/mysql/*.log"}]
}

loki.source.file "mysql" {
  targets    = local.file_match.mysql.targets
  forward_to = [loki.process.mysql.receiver]
}

loki.process "mysql" {
  forward_to = [loki.write.default.receiver]

  stage.static_labels {
    values = {
      job         = "mysql",
      host        = "$HOST_NAME",
      environment = "$ENVIRONMENT",
      tier        = "application",
      component   = "database",
    }
  }
}

// System logs
local.file_match "syslog" {
  path_targets = [
    {__path__ = "/var/log/syslog"},
    {__path__ = "/var/log/auth.log"},
    {__path__ = "/var/log/kern.log"},
  ]
}

loki.source.file "syslog" {
  targets    = local.file_match.syslog.targets
  forward_to = [loki.process.syslog.receiver]
}

loki.process "syslog" {
  forward_to = [loki.write.default.receiver]

  stage.static_labels {
    values = {
      job         = "syslog",
      host        = "$HOST_NAME",
      environment = "$ENVIRONMENT",
      tier        = "system",
    }
  }
}

// Loki writer
loki.write "default" {
  endpoint {
    url = "${LOKI_URL}/loki/api/v1/push"

    // Queue configuration for reliability
    queue_config {
      capacity          = 500000
      drain_timeout     = "5s"
      batch_wait        = "1s"
      max_backoff       = "5s"
      min_backoff       = "500ms"
    }
  }
}

// ============================================================================
// Trace Collection (Optional OTLP)
// ============================================================================

otelcol.receiver.otlp "default" {
  grpc {
    endpoint = "127.0.0.1:${OTLP_GRPC_PORT}"
  }
  http {
    endpoint = "127.0.0.1:${OTLP_HTTP_PORT}"
  }

  output {
    traces = [otelcol.processor.batch.default.input]
  }
}

otelcol.processor.batch "default" {
  output {
    traces = [otelcol.exporter.otlp.tempo.input]
  }
}

otelcol.exporter.otlp "tempo" {
  client {
    endpoint = "${TEMPO_URL}"
    tls {
      insecure = true
    }
  }
}
MONITORED_CONFIG
}

generate_vpsmanager_config() {
    cat << VPSMANAGER_CONFIG
// ============================================================================
// VPSManager/CHOM Node Configuration
// Full telemetry collection for Laravel application hosting
// ============================================================================

// Scrape local exporters
prometheus.scrape "local_exporters" {
  targets = [
    {__address__ = "localhost:9100", job = "node-exporter"},
    {__address__ = "localhost:9113", job = "nginx-exporter"},
    {__address__ = "localhost:9104", job = "mysql-exporter"},
    {__address__ = "localhost:9253", job = "phpfpm-exporter"},
    {__address__ = "localhost:9117", job = "fail2ban-exporter"},
  ]
  forward_to      = [prometheus.relabel.add_labels.receiver]
  scrape_interval = "15s"
}

// Add common labels
prometheus.relabel "add_labels" {
  forward_to = [prometheus.remote_write.default.receiver]

  rule {
    target_label = "host"
    replacement  = "$HOST_NAME"
  }
  rule {
    target_label = "environment"
    replacement  = "$ENVIRONMENT"
  }
  rule {
    target_label = "tier"
    replacement  = "vpsmanager"
  }
}

// Remote write to observability stack
prometheus.remote_write "default" {
  endpoint {
    url = "${PROMETHEUS_URL}/api/v1/write"

    queue_config {
      capacity             = 10000
      max_shards           = 10
      min_shards           = 1
      max_samples_per_send = 5000
      batch_send_deadline  = "5s"
      min_backoff          = "30ms"
      max_backoff          = "5s"
    }
  }
}

// ============================================================================
// Log Collection
// ============================================================================

// Nginx access logs (JSON format)
local.file_match "nginx_access" {
  path_targets = [
    {__path__ = "/var/log/nginx/*access*.log"},
    {__path__ = "/var/log/nginx/chom-access.log"},
  ]
}

loki.source.file "nginx_access" {
  targets    = local.file_match.nginx_access.targets
  forward_to = [loki.process.nginx_access.receiver]
}

loki.process "nginx_access" {
  forward_to = [loki.write.default.receiver]

  stage.json {
    expressions = {
      status        = "status",
      method        = "method",
      path          = "uri",
      latency       = "request_time",
      upstream_time = "upstream_response_time",
    }
  }

  stage.static_labels {
    values = {
      job         = "nginx-access",
      host        = "$HOST_NAME",
      environment = "$ENVIRONMENT",
      tier        = "vpsmanager",
      component   = "webserver",
    }
  }

  stage.labels {
    values = {
      status = "",
    }
  }
}

// Nginx error logs
local.file_match "nginx_error" {
  path_targets = [
    {__path__ = "/var/log/nginx/*error*.log"},
    {__path__ = "/var/log/nginx/chom-error.log"},
  ]
}

loki.source.file "nginx_error" {
  targets    = local.file_match.nginx_error.targets
  forward_to = [loki.process.nginx_error.receiver]
}

loki.process "nginx_error" {
  forward_to = [loki.write.default.receiver]

  stage.static_labels {
    values = {
      job         = "nginx-error",
      host        = "$HOST_NAME",
      environment = "$ENVIRONMENT",
      tier        = "vpsmanager",
      component   = "webserver",
      level       = "error",
    }
  }
}

// Laravel application logs
local.file_match "laravel" {
  path_targets = [
    {__path__ = "/var/www/chom/storage/logs/*.log"},
    {__path__ = "/var/www/*/storage/logs/*.log"},
  ]
}

loki.source.file "laravel" {
  targets    = local.file_match.laravel.targets
  forward_to = [loki.process.laravel.receiver]
}

loki.process "laravel" {
  forward_to = [loki.write.default.receiver]

  // Parse Laravel log format: [YYYY-MM-DD HH:MM:SS] environment.LEVEL: message
  stage.regex {
    expression = "\\[(?P<timestamp>[^\\]]+)\\] (?P<env>\\w+)\\.(?P<level>\\w+): (?P<message>.*)"
  }

  stage.static_labels {
    values = {
      job         = "laravel",
      host        = "$HOST_NAME",
      environment = "$ENVIRONMENT",
      tier        = "vpsmanager",
      component   = "application",
    }
  }

  stage.labels {
    values = {
      level = "",
      env   = "",
    }
  }
}

// PHP-FPM logs
local.file_match "phpfpm" {
  path_targets = [{__path__ = "/var/log/php*-fpm*.log"}]
}

loki.source.file "phpfpm" {
  targets    = local.file_match.phpfpm.targets
  forward_to = [loki.process.phpfpm.receiver]
}

loki.process "phpfpm" {
  forward_to = [loki.write.default.receiver]

  stage.static_labels {
    values = {
      job         = "php-fpm",
      host        = "$HOST_NAME",
      environment = "$ENVIRONMENT",
      tier        = "vpsmanager",
      component   = "runtime",
    }
  }
}

// MySQL logs
local.file_match "mysql" {
  path_targets = [
    {__path__ = "/var/log/mysql/*.log"},
    {__path__ = "/var/log/mysql/mysql-slow.log"},
  ]
}

loki.source.file "mysql" {
  targets    = local.file_match.mysql.targets
  forward_to = [loki.process.mysql.receiver]
}

loki.process "mysql" {
  forward_to = [loki.write.default.receiver]

  // Handle multiline slow query logs
  stage.multiline {
    firstline     = "^# Time:|^# User@Host:"
    max_wait_time = "3s"
  }

  stage.static_labels {
    values = {
      job         = "mysql",
      host        = "$HOST_NAME",
      environment = "$ENVIRONMENT",
      tier        = "vpsmanager",
      component   = "database",
    }
  }
}

// Supervisor logs (Laravel queue workers, scheduler)
local.file_match "supervisor" {
  path_targets = [{__path__ = "/var/log/supervisor/*.log"}]
}

loki.source.file "supervisor" {
  targets    = local.file_match.supervisor.targets
  forward_to = [loki.process.supervisor.receiver]
}

loki.process "supervisor" {
  forward_to = [loki.write.default.receiver]

  stage.static_labels {
    values = {
      job         = "supervisor",
      host        = "$HOST_NAME",
      environment = "$ENVIRONMENT",
      tier        = "vpsmanager",
      component   = "process-manager",
    }
  }
}

// System/security logs
local.file_match "syslog" {
  path_targets = [
    {__path__ = "/var/log/syslog"},
    {__path__ = "/var/log/auth.log"},
    {__path__ = "/var/log/fail2ban.log"},
  ]
}

loki.source.file "syslog" {
  targets    = local.file_match.syslog.targets
  forward_to = [loki.process.syslog.receiver]
}

loki.process "syslog" {
  forward_to = [loki.write.default.receiver]

  stage.static_labels {
    values = {
      job         = "syslog",
      host        = "$HOST_NAME",
      environment = "$ENVIRONMENT",
      tier        = "vpsmanager",
    }
  }
}

// Loki writer with enhanced queue config
loki.write "default" {
  endpoint {
    url = "${LOKI_URL}/loki/api/v1/push"

    queue_config {
      capacity          = 500000
      drain_timeout     = "5s"
      batch_wait        = "1s"
      max_backoff       = "5s"
      min_backoff       = "500ms"
    }
  }
}

// ============================================================================
// Trace Collection (OTLP)
// ============================================================================

otelcol.receiver.otlp "default" {
  grpc {
    endpoint = "127.0.0.1:${OTLP_GRPC_PORT}"
  }
  http {
    endpoint = "127.0.0.1:${OTLP_HTTP_PORT}"
  }

  output {
    traces = [otelcol.processor.batch.default.input]
  }
}

otelcol.processor.batch "default" {
  timeout             = "5s"
  send_batch_size     = 8192

  output {
    traces = [otelcol.exporter.otlp.tempo.input]
  }
}

otelcol.exporter.otlp "tempo" {
  client {
    endpoint = "${TEMPO_URL}"
    tls {
      insecure = true
    }
  }
}
VPSMANAGER_CONFIG
}

#===============================================================================
# SYSTEMD SERVICE
#===============================================================================

create_systemd_service() {
    log_info "Creating systemd service..."

    # Determine OTLP binding based on role
    local otlp_bind="127.0.0.1"
    if [[ "$DEPLOYMENT_ROLE" == "observability" ]]; then
        otlp_bind="0.0.0.0"
    fi

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Grafana Alloy - Unified Telemetry Collector
Documentation=https://grafana.com/docs/alloy/latest/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${USER_NAME}
Group=${GROUP_NAME}
ExecStart=${INSTALL_PATH} run \\
    --storage.path=${DATA_DIR} \\
    --server.http.listen-addr=0.0.0.0:${MODULE_PORT} \\
    ${CONFIG_DIR}/config.alloy
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
TimeoutStopSec=30

# Resource limits
LimitNOFILE=65536
LimitNPROC=32768

# SECURITY: Systemd hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
RestrictNamespaces=yes
LockPersonality=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
MemoryDenyWriteExecute=no

# Read-write paths for Alloy
ReadWritePaths=${DATA_DIR}
ReadWritePaths=${LOG_DIR}
ReadWritePaths=/tmp

# Read-only paths for log collection
ReadOnlyPaths=/var/log
ReadOnlyPaths=/var/www
ReadOnlyPaths=/proc
ReadOnlyPaths=/sys

# Allow network access
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK

# System call filtering
SystemCallFilter=@system-service
SystemCallFilter=~@privileged
SystemCallErrorNumber=EPERM

# Capabilities
CapabilityBoundingSet=CAP_DAC_READ_SEARCH CAP_NET_BIND_SERVICE CAP_SYS_PTRACE
AmbientCapabilities=CAP_DAC_READ_SEARCH CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Systemd service created"
}

#===============================================================================
# FIREWALL CONFIGURATION
#===============================================================================

configure_firewall() {
    if ! command -v ufw &>/dev/null; then
        log_warn "UFW not installed, skipping firewall configuration"
        return
    fi

    log_info "Configuring firewall..."

    # Always allow localhost
    # Port 12345 - Alloy HTTP (metrics, health, UI)

    case "$DEPLOYMENT_ROLE" in
        observability)
            # Allow OTLP ports from anywhere (will be restricted by security groups)
            ufw allow "$MODULE_PORT/tcp" comment "Alloy HTTP" 2>/dev/null || true
            ufw allow "$OTLP_GRPC_PORT/tcp" comment "Alloy OTLP gRPC" 2>/dev/null || true
            ufw allow "$OTLP_HTTP_PORT/tcp" comment "Alloy OTLP HTTP" 2>/dev/null || true
            ;;
        monitored|vpsmanager)
            # Only allow metrics port from observability IP
            if [[ -n "$OBSERVABILITY_IP" ]]; then
                ufw allow from "$OBSERVABILITY_IP" to any port "$MODULE_PORT" proto tcp comment "Alloy metrics from observability" 2>/dev/null || true
            fi
            ;;
    esac

    log_success "Firewall configured"
}

#===============================================================================
# VALIDATION
#===============================================================================

validate_config() {
    log_info "Validating Alloy configuration..."

    local config_file="$CONFIG_DIR/config.alloy"

    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi

    # Use alloy fmt to check syntax
    if "$INSTALL_PATH" fmt "$config_file" > /dev/null 2>&1; then
        log_success "Configuration syntax is valid"
        return 0
    else
        log_error "Configuration has syntax errors:"
        "$INSTALL_PATH" fmt "$config_file" 2>&1 || true
        return 1
    fi
}

#===============================================================================
# SERVICE MANAGEMENT
#===============================================================================

stop_service() {
    # H-7: Use robust 3-layer verification if available
    if type stop_and_verify_service &>/dev/null; then
        stop_and_verify_service "$SERVICE_NAME" "$INSTALL_PATH" || {
            log_error "Failed to stop $SERVICE_NAME safely"
            return 1
        }
    else
        # Fallback: Enhanced basic stop with proper verification
        log_info "Stopping $SERVICE_NAME service..."

        if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            systemctl stop "$SERVICE_NAME"

            # Wait for graceful stop
            local wait_count=0
            local max_wait=30
            while pgrep -f "$INSTALL_PATH" >/dev/null 2>&1 && [[ $wait_count -lt $max_wait ]]; do
                sleep 1
                ((wait_count++))
            done

            # Force kill if needed
            if pgrep -f "$INSTALL_PATH" >/dev/null 2>&1; then
                log_warn "Service did not stop gracefully, sending SIGKILL"
                pkill -9 -f "$INSTALL_PATH" 2>/dev/null || true
                sleep 2
            fi

            # Final verification
            if pgrep -f "$INSTALL_PATH" >/dev/null 2>&1; then
                log_error "CRITICAL: Failed to stop $SERVICE_NAME"
                return 1
            fi
        fi

        log_success "$SERVICE_NAME stopped"
    fi
}

start_service() {
    log_info "Starting $SERVICE_NAME..."
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"

    sleep 3

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "$SERVICE_NAME is running"
        return 0
    else
        log_error "$SERVICE_NAME failed to start"
        journalctl -u "$SERVICE_NAME" -n 30 --no-pager
        return 1
    fi
}

verify_health() {
    log_info "Verifying Alloy health..."

    local max_attempts=30
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if curl -sf "http://localhost:${MODULE_PORT}/-/ready" &>/dev/null; then
            log_success "Alloy is ready"

            # Check metrics endpoint
            if curl -sf "http://localhost:${MODULE_PORT}/metrics" | grep -q "alloy_build_info"; then
                log_success "Metrics endpoint verified"
            fi

            return 0
        fi

        log_info "Waiting for Alloy to become ready... (attempt $attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done

    log_error "Alloy failed to become ready after $max_attempts attempts"
    return 1
}

#===============================================================================
# MIGRATION FROM PROMTAIL
#===============================================================================

migrate_from_promtail() {
    log_info "Checking for existing Promtail installation..."

    if systemctl is-active --quiet promtail 2>/dev/null; then
        log_warn "Promtail is currently running"
        log_info "Alloy will replace Promtail as the log collector"

        # Do not auto-disable Promtail - let operator do it after verifying Alloy works
        log_info ""
        log_info "After verifying Alloy is working correctly, disable Promtail with:"
        log_info "  systemctl stop promtail"
        log_info "  systemctl disable promtail"
        log_info ""
    fi

    # Check for Promtail config to help migration
    if [[ -f "/etc/promtail/promtail.yaml" ]]; then
        log_info "Found Promtail configuration at /etc/promtail/promtail.yaml"
        log_info "You can convert it to Alloy format with:"
        log_info "  alloy convert --source-format=promtail \\"
        log_info "    --output=/etc/alloy/config.alloy.migrated \\"
        log_info "    /etc/promtail/promtail.yaml"
        log_info ""
    fi
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    log_info "=========================================="
    log_info "Grafana Alloy Installation Script"
    log_info "Version: $MODULE_VERSION"
    log_info "Role: $DEPLOYMENT_ROLE"
    log_info "=========================================="

    # Check root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi

    # Check dependencies
    for cmd in curl unzip; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done

    # Current version info
    local current_version
    current_version=$(get_installed_version)

    if [[ -n "$current_version" ]]; then
        log_info "Current version: $current_version"
    else
        log_info "New installation"
    fi

    # Check if already at target version
    if is_installed; then
        log_skip "$MODULE_NAME v$MODULE_VERSION already installed"

        # Still ensure config and service are up to date
        if [[ "$FORCE_MODE" == "true" ]]; then
            generate_config "$DEPLOYMENT_ROLE"
            create_systemd_service
            systemctl restart "$SERVICE_NAME"
        fi

        verify_health
        return 0
    fi

    # Check for Promtail migration
    migrate_from_promtail

    # Stop existing service before upgrade
    if systemctl list-units --type=service --all | grep -q "^[[:space:]]*${SERVICE_NAME}.service" 2>/dev/null; then
        stop_service
    fi

    # Backup if upgrading
    local backup_path=""
    if [[ -n "$current_version" ]]; then
        backup_path=$(backup_alloy)
        export BACKUP_PATH="$backup_path"
    fi

    # Create user and directories
    create_user

    # Install binary
    if ! install_binary; then
        log_error "Binary installation failed"
        if [[ -n "$backup_path" ]]; then
            log_warn "Attempting rollback..."
            restore_from_backup "$backup_path" || log_error "Rollback failed"
        fi
        return 1
    fi

    # Generate configuration
    generate_config "$DEPLOYMENT_ROLE"

    # Validate configuration
    if ! validate_config; then
        log_error "Configuration validation failed"
        if [[ -n "$backup_path" ]]; then
            log_warn "Attempting rollback..."
            restore_from_backup "$backup_path" || log_error "Rollback failed"
        fi
        return 1
    fi

    # Create systemd service
    create_systemd_service

    # Configure firewall
    configure_firewall

    # Start service
    if ! start_service; then
        log_error "Service failed to start"
        if [[ -n "$backup_path" ]]; then
            log_warn "Attempting rollback..."
            restore_from_backup "$backup_path" && log_success "Rollback successful"
        fi
        return 1
    fi

    # Verify health
    if ! verify_health; then
        log_error "Health verification failed"
        if [[ -n "$backup_path" ]]; then
            log_warn "Attempting rollback..."
            restore_from_backup "$backup_path" && log_success "Rollback successful"
        fi
        return 1
    fi

    # Success
    local new_version
    new_version=$(get_installed_version)

    log_success "=========================================="
    log_success "Grafana Alloy installation completed!"
    if [[ -n "$current_version" ]]; then
        log_success "Version: $current_version -> $new_version"
    else
        log_success "Version: $new_version (new install)"
    fi
    log_success "Role: $DEPLOYMENT_ROLE"
    if [[ -n "$backup_path" ]]; then
        log_info "Backup available at: $backup_path"
    fi
    log_success "=========================================="
    log_info ""
    log_info "Alloy UI: http://localhost:${MODULE_PORT}"
    log_info "Metrics: http://localhost:${MODULE_PORT}/metrics"
    log_info "Health: http://localhost:${MODULE_PORT}/-/ready"
    log_info ""

    return 0
}

main "$@"
