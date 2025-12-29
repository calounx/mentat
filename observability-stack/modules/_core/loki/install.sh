#!/bin/bash
#===============================================================================
# Loki Installation and Upgrade Script
# Phase 3: Loki 2.9.3 -> 3.6.3 Upgrade System
#
# Features:
#   - Pre-upgrade data backup
#   - Schema migration handling (v12 -> v13)
#   - WAL replay monitoring
#   - Bloom filter cleanup (v3.3+ format change)
#   - Configuration migration (table_manager removal)
#   - Health checks and rollback support
#
# Risk Level: MEDIUM
# Estimated Downtime: 5-10 minutes
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../../../scripts/lib" 2>/dev/null && pwd)" || LIB_DIR="$(cd "$SCRIPT_DIR/../../scripts/lib" && pwd)"

# Source common library
if [[ -f "$LIB_DIR/common.sh" ]]; then
    source "$LIB_DIR/common.sh"
else
    log_info() { echo "[INFO] $1"; }
    log_success() { echo "[SUCCESS] $1"; }
    log_skip() { echo "[SKIP] $1"; }
    log_warn() { echo "[WARN] $1"; }
    log_error() { echo "[ERROR] $1" >&2; }
fi

#===============================================================================
# CONFIGURATION
#===============================================================================

MODULE_NAME="${MODULE_NAME:-loki}"
MODULE_VERSION="${MODULE_VERSION:-3.6.3}"
MODULE_PORT="${MODULE_PORT:-3100}"
FORCE_MODE="${FORCE_MODE:-false}"

BINARY_NAME="loki"
INSTALL_PATH="/usr/local/bin/$BINARY_NAME"
SERVICE_NAME="loki"
USER_NAME="loki"
CONFIG_DIR="/etc/loki"
DATA_DIR="/var/lib/loki"
BACKUP_DIR="${BACKUP_DIR:-/var/lib/observability-upgrades/backups/loki}"

# Schema version tracking
CURRENT_SCHEMA_VERSION=""
TARGET_SCHEMA_VERSION="v13"

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --force|-f) FORCE_MODE=true ;;
    esac
done

#===============================================================================
# VERSION DETECTION
#===============================================================================

# Get currently installed version
get_installed_version() {
    if [[ -x "$INSTALL_PATH" ]]; then
        "$INSTALL_PATH" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo ""
    else
        echo ""
    fi
}

# Check if upgrade is needed
is_installed() {
    [[ "$FORCE_MODE" == "true" ]] && return 1
    [[ ! -x "$INSTALL_PATH" ]] && return 1
    local current_version
    current_version=$(get_installed_version)
    [[ "$current_version" == "$MODULE_VERSION" ]]
}

# Determine if this is a major version upgrade
is_major_upgrade() {
    local current_version
    current_version=$(get_installed_version)

    if [[ -z "$current_version" ]]; then
        return 1  # New installation
    fi

    local current_major="${current_version%%.*}"
    local target_major="${MODULE_VERSION%%.*}"

    [[ "$current_major" != "$target_major" ]]
}

#===============================================================================
# PRE-UPGRADE VALIDATION
#===============================================================================

# Validate current configuration
validate_config() {
    log_info "Validating Loki configuration..."

    local config_file="$CONFIG_DIR/loki-config.yaml"
    if [[ ! -f "$config_file" ]]; then
        config_file="$CONFIG_DIR/config.yaml"
    fi

    if [[ ! -f "$config_file" ]]; then
        log_warn "No configuration file found - will create default"
        return 0
    fi

    # Check YAML syntax
    if command -v python3 &>/dev/null; then
        if ! python3 -c "import yaml; yaml.safe_load(open('$config_file'))" 2>/dev/null; then
            log_error "Configuration file has invalid YAML syntax"
            return 1
        fi
    fi

    # Check for deprecated fields that MUST be removed in 3.x
    local deprecated_fields=("table_manager" "shared_store" "shared_store_key_prefix")
    local found_deprecated=false

    for field in "${deprecated_fields[@]}"; do
        if grep -q "^${field}:" "$config_file" 2>/dev/null; then
            log_warn "Deprecated field found: $field (will be migrated)"
            found_deprecated=true
        fi
    done

    # Check schema version
    if grep -q "schema: v13" "$config_file"; then
        log_info "Schema v13 already configured - ready for 3.x"
        CURRENT_SCHEMA_VERSION="v13"
    elif grep -q "schema: v12" "$config_file"; then
        log_warn "Schema v12 detected - migration to v13 recommended"
        CURRENT_SCHEMA_VERSION="v12"
    elif grep -q "schema: v11" "$config_file"; then
        log_warn "Schema v11 detected - migration to v13 required for best performance"
        CURRENT_SCHEMA_VERSION="v11"
    fi

    # Check for TSDB (required for schema v13)
    if grep -q "store: tsdb" "$config_file"; then
        log_info "TSDB storage configured - compatible with 3.x"
    elif grep -q "store: boltdb" "$config_file" || grep -q "store: boltdb-shipper" "$config_file"; then
        log_warn "BoltDB store detected - TSDB recommended for 3.x"
    fi

    log_success "Configuration validation passed"
    return 0
}

# Check disk space
check_disk_space() {
    log_info "Checking disk space..."

    local data_size=0
    if [[ -d "$DATA_DIR" ]]; then
        data_size=$(du -sm "$DATA_DIR" 2>/dev/null | awk '{print $1}' || echo "0")
    fi

    local required_space=$((data_size * 2 + 1024))  # 2x data + 1GB buffer
    local available_space
    available_space=$(df -m /var/lib 2>/dev/null | tail -1 | awk '{print $4}')

    if [[ $available_space -lt $required_space ]]; then
        log_error "Insufficient disk space: ${available_space}MB available, ${required_space}MB required"
        log_error "Need 2x data size for backup + 1GB buffer"
        return 1
    fi

    log_info "Disk space OK: ${available_space}MB available, ${required_space}MB required"
    return 0
}

# Check label cardinality (v3.4+ enforces 15 label limit)
check_label_cardinality() {
    log_info "Checking label cardinality..."

    if ! curl -sf "http://localhost:${MODULE_PORT}/ready" &>/dev/null; then
        log_skip "Loki not running - skipping label check"
        return 0
    fi

    local label_count
    label_count=$(curl -sf "http://localhost:${MODULE_PORT}/loki/api/v1/labels" 2>/dev/null | \
        python3 -c "import sys, json; print(len(json.load(sys.stdin).get('data', [])))" 2>/dev/null || echo "0")

    if [[ $label_count -gt 15 ]]; then
        log_warn "High label count detected: $label_count labels"
        log_warn "Loki 3.4+ enforces 15 label limit per series"
        log_warn "Review Promtail scrape configs to reduce label cardinality"
    else
        log_info "Label count OK: $label_count labels"
    fi

    return 0
}

#===============================================================================
# BACKUP OPERATIONS
#===============================================================================

# Create comprehensive backup
backup_loki() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/$timestamp"

    log_info "Creating backup at $backup_path..."
    mkdir -p "$backup_path"
    chmod 700 "$backup_path"

    # Backup binary
    if [[ -f "$INSTALL_PATH" ]]; then
        local current_version
        current_version=$(get_installed_version)
        cp -p "$INSTALL_PATH" "$backup_path/loki-${current_version}"
        log_info "Backed up binary: loki-${current_version}"
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

    # Backup data directory (WARNING: Can be large)
    if [[ -d "$DATA_DIR" ]]; then
        local data_size
        data_size=$(du -sm "$DATA_DIR" 2>/dev/null | awk '{print $1}' || echo "0")

        if [[ $data_size -gt 10240 ]]; then
            log_warn "Data directory is large (${data_size}MB)"
            log_warn "Creating lightweight backup (metadata only)"

            # Backup critical metadata only for large installations
            mkdir -p "$backup_path/data"

            # Backup WAL (critical for data integrity)
            if [[ -d "$DATA_DIR/wal" ]]; then
                cp -rp "$DATA_DIR/wal" "$backup_path/data/" 2>/dev/null || log_warn "Could not backup WAL"
            fi

            # Backup compactor state
            if [[ -d "$DATA_DIR/compactor" ]]; then
                cp -rp "$DATA_DIR/compactor" "$backup_path/data/" 2>/dev/null || log_warn "Could not backup compactor"
            fi

            # Backup TSDB index
            if [[ -d "$DATA_DIR/tsdb-index" ]]; then
                cp -rp "$DATA_DIR/tsdb-index" "$backup_path/data/" 2>/dev/null || log_warn "Could not backup TSDB index"
            fi
        else
            # Full backup for smaller installations
            log_info "Creating full data backup (${data_size}MB)..."
            tar -czf "$backup_path/loki-data.tar.gz" -C /var/lib loki 2>/dev/null || {
                log_warn "Tar backup failed, using cp..."
                cp -rp "$DATA_DIR" "$backup_path/data" || log_warn "Data backup incomplete"
            }
        fi
    fi

    # Create backup metadata
    cat > "$backup_path/metadata.json" <<EOF
{
  "component": "loki",
  "timestamp": "$timestamp",
  "version": "$(get_installed_version)",
  "target_version": "$MODULE_VERSION",
  "schema_version": "$CURRENT_SCHEMA_VERSION",
  "created_by": "loki-upgrade"
}
EOF

    log_success "Backup created: $backup_path"
    echo "$backup_path"
}

# Restore from backup
restore_from_backup() {
    local backup_path="$1"

    if [[ ! -d "$backup_path" ]]; then
        log_error "Backup directory not found: $backup_path"
        return 1
    fi

    log_info "Restoring from backup: $backup_path"

    # Stop service
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true

    # Restore binary
    local binary_backup
    binary_backup=$(ls "$backup_path"/loki-* 2>/dev/null | head -1)
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
        chown -R "$USER_NAME:$USER_NAME" "$CONFIG_DIR"
        log_info "Restored configuration"
    fi

    # Restore service file
    if [[ -f "$backup_path/${SERVICE_NAME}.service" ]]; then
        cp -p "$backup_path/${SERVICE_NAME}.service" "/etc/systemd/system/"
        systemctl daemon-reload
        log_info "Restored service file"
    fi

    # Restore data (if needed)
    if [[ -f "$backup_path/loki-data.tar.gz" ]]; then
        log_info "Restoring data from tar archive..."
        rm -rf "$DATA_DIR"
        tar -xzf "$backup_path/loki-data.tar.gz" -C /var/lib
        chown -R "$USER_NAME:$USER_NAME" "$DATA_DIR"
    elif [[ -d "$backup_path/data" ]]; then
        log_info "Restoring data from directory backup..."
        # Restore critical directories
        for subdir in wal compactor tsdb-index; do
            if [[ -d "$backup_path/data/$subdir" ]]; then
                rm -rf "$DATA_DIR/$subdir"
                cp -rp "$backup_path/data/$subdir" "$DATA_DIR/"
            fi
        done
        chown -R "$USER_NAME:$USER_NAME" "$DATA_DIR"
    fi

    # Start service
    systemctl start "$SERVICE_NAME"

    log_success "Restore completed"
    return 0
}

#===============================================================================
# MIGRATION OPERATIONS
#===============================================================================

# Clean bloom filter blocks (required for 3.3+ due to format change)
clean_bloom_blocks() {
    local bloom_dir="$DATA_DIR/bloomblocks"

    if [[ -d "$bloom_dir" ]]; then
        local bloom_size
        bloom_size=$(du -sm "$bloom_dir" 2>/dev/null | awk '{print $1}' || echo "0")

        if [[ $bloom_size -gt 0 ]]; then
            log_info "Cleaning bloom filter blocks (${bloom_size}MB)..."
            log_info "Bloom filter format changed in 3.3 - existing blocks incompatible"
            rm -rf "$bloom_dir"/*
            log_success "Bloom blocks cleaned"
        fi
    fi
}

# Migrate configuration for 3.x compatibility
migrate_config() {
    log_info "Migrating configuration for Loki 3.x compatibility..."

    local config_file="$CONFIG_DIR/loki-config.yaml"
    if [[ ! -f "$config_file" ]]; then
        config_file="$CONFIG_DIR/config.yaml"
    fi

    if [[ ! -f "$config_file" ]]; then
        log_warn "No configuration file to migrate"
        return 0
    fi

    # Backup original config
    cp -p "$config_file" "${config_file}.pre-migration"

    # Remove deprecated table_manager section using Python
    if grep -q "^table_manager:" "$config_file"; then
        log_info "Removing deprecated table_manager section..."
        python3 - "$config_file" << 'PYEOF'
import yaml
import sys

# Get config file path from command line argument
if len(sys.argv) < 2:
    print("Error: config file path required", file=sys.stderr)
    sys.exit(1)

config_file = sys.argv[1]

try:
    with open(config_file, 'r') as f:
        config = yaml.safe_load(f)

    if config is None:
        print("Warning: Empty configuration file")
        sys.exit(0)

    # Remove deprecated fields
    deprecated = ['table_manager', 'shared_store', 'shared_store_key_prefix']
    modified = False
    for field in deprecated:
        if field in config:
            print(f"Removing deprecated field: {field}")
            del config[field]
            modified = True

    if modified:
        with open(config_file, 'w') as f:
            yaml.dump(config, f, default_flow_style=False, sort_keys=False)
        print("Configuration migration complete")
    else:
        print("No deprecated fields found")

except Exception as e:
    print(f"Error processing config: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
    fi

    # Add max_label_names_per_series if not present (3.4+ enforcement)
    if ! grep -q "max_label_names_per_series" "$config_file"; then
        log_info "Adding max_label_names_per_series limit..."
        # Add to limits_config section
        if grep -q "^limits_config:" "$config_file"; then
            sed -i '/^limits_config:/a\  max_label_names_per_series: 15' "$config_file"
        fi
    fi

    log_success "Configuration migration completed"
    return 0
}

#===============================================================================
# INSTALLATION
#===============================================================================

# Create system user
create_user() {
    if ! id "$USER_NAME" &>/dev/null; then
        log_info "Creating user $USER_NAME..."
        useradd --no-create-home --shell /bin/false "$USER_NAME"
    fi

    mkdir -p "$CONFIG_DIR" "$DATA_DIR"
    mkdir -p "$DATA_DIR/chunks" "$DATA_DIR/rules" "$DATA_DIR/wal"
    mkdir -p "$DATA_DIR/compactor" "$DATA_DIR/tsdb-index" "$DATA_DIR/tsdb-cache"

    chown -R "$USER_NAME:$USER_NAME" "$CONFIG_DIR" "$DATA_DIR"
}

# Create default configuration if not exists
create_default_config() {
    local config_file="$CONFIG_DIR/loki-config.yaml"

    if [[ -f "$config_file" ]]; then
        log_skip "Configuration already exists: $config_file"
        return 0
    fi

    log_info "Creating default Loki configuration..."

    cat > "$config_file" << 'EOF'
# Loki Configuration File
# Generated by observability-stack
# Schema v13 with TSDB (recommended for Loki 3.x)

auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096
  log_level: info

common:
  instance_addr: 127.0.0.1
  path_prefix: /var/lib/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/loki/chunks
      rules_directory: /var/lib/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

query_range:
  results_cache:
    cache:
      embedded_cache:
        enabled: true
        max_size_mb: 100

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

storage_config:
  tsdb_shipper:
    active_index_directory: /var/lib/loki/tsdb-index
    cache_location: /var/lib/loki/tsdb-cache

compactor:
  working_directory: /var/lib/loki/compactor
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 2h
  delete_request_store: filesystem

limits_config:
  retention_period: 744h
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  ingestion_rate_mb: 16
  ingestion_burst_size_mb: 24
  max_label_names_per_series: 15

ruler:
  alertmanager_url: http://localhost:9093
  storage:
    type: local
    local:
      directory: /var/lib/loki/rules
  rule_path: /var/lib/loki/rules-temp
  enable_api: true

analytics:
  reporting_enabled: false
EOF

    chown "$USER_NAME:$USER_NAME" "$config_file"
    chmod 640 "$config_file"

    log_success "Default configuration created: $config_file"
}

# Download and install binary
install_binary() {
    log_info "Installing $MODULE_NAME v$MODULE_VERSION..."
    cd /tmp

    local archive_name="loki-linux-amd64.zip"
    local download_url="https://github.com/grafana/loki/releases/download/v${MODULE_VERSION}/${archive_name}"
    local checksum_url="https://github.com/grafana/loki/releases/download/v${MODULE_VERSION}/SHA256SUMS"

    # SECURITY: Always require checksum verification - fail if unavailable
    if ! type download_and_verify &>/dev/null; then
        log_error "SECURITY: download_and_verify function not available"
        log_error "Cannot install without checksum verification"
        return 1
    fi

    # SECURITY: Fail installation if checksum verification fails
    # NEVER fall back to unverified downloads
    if ! download_and_verify "$download_url" "$archive_name" "$checksum_url"; then
        log_error "SECURITY: Checksum verification failed for Loki"
        log_error "Refusing to install unverified binary"
        return 1
    fi

    unzip -o "$archive_name"
    chmod +x "loki-linux-amd64"

    # Verify binary works
    if ! ./loki-linux-amd64 --version &>/dev/null; then
        log_error "Downloaded binary failed version check"
        return 1
    fi

    # Install binary
    mv "loki-linux-amd64" "$INSTALL_PATH"
    chown root:root "$INSTALL_PATH"
    chmod 755 "$INSTALL_PATH"

    # Cleanup
    rm -f "$archive_name" SHA256SUMS

    log_success "$MODULE_NAME binary installed"
}

# Create systemd service
create_service() {
    log_info "Creating systemd service..."

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << 'EOF'
[Unit]
Description=Loki Log Aggregation System
Documentation=https://grafana.com/docs/loki/latest/
Wants=network-online.target
After=network-online.target

[Service]
User=loki
Group=loki
Type=simple
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki-config.yaml
ExecReload=/bin/kill -HUP $MAINPID

# SECURITY: Systemd hardening
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/loki /etc/loki
PrivateTmp=true
NoNewPrivileges=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
SystemCallFilter=@system-service
CapabilityBoundingSet=
RestrictNamespaces=true
LockPersonality=true

# Resource limits
LimitNOFILE=65536
LimitNPROC=65536

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Systemd service created"
}

#===============================================================================
# HEALTH CHECKS
#===============================================================================

# Wait for Loki to become ready
wait_for_ready() {
    local max_attempts="${1:-60}"
    local attempt=1

    log_info "Waiting for Loki to become ready..."

    while [[ $attempt -le $max_attempts ]]; do
        if curl -sf "http://localhost:${MODULE_PORT}/ready" &>/dev/null; then
            log_success "Loki is ready"
            return 0
        fi

        log_info "Waiting for Loki... (attempt $attempt/$max_attempts)"
        sleep 5
        ((attempt++))
    done

    log_error "Loki failed to become ready after $max_attempts attempts"
    return 1
}

# Monitor WAL replay (important during upgrade)
monitor_wal_replay() {
    log_info "Monitoring WAL replay..."

    local max_attempts=60
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        # Check if WAL replay is complete by looking at metrics
        local wal_status
        wal_status=$(curl -sf "http://localhost:${MODULE_PORT}/metrics" 2>/dev/null | \
            grep "loki_ingester_wal_replay_duration_seconds" || echo "")

        if [[ -n "$wal_status" ]]; then
            log_info "WAL replay complete"
            return 0
        fi

        # Check ready endpoint
        if curl -sf "http://localhost:${MODULE_PORT}/ready" &>/dev/null; then
            log_info "Loki ready (WAL replay complete)"
            return 0
        fi

        log_info "WAL replay in progress... (attempt $attempt/$max_attempts)"
        sleep 5
        ((attempt++))
    done

    log_warn "WAL replay status unknown after $max_attempts attempts"
    return 0
}

# Verify Loki health after upgrade
verify_health() {
    log_info "Verifying Loki health..."

    # Check ready endpoint
    if ! curl -sf "http://localhost:${MODULE_PORT}/ready" &>/dev/null; then
        log_error "Loki /ready endpoint failed"
        return 1
    fi

    # Check metrics endpoint
    local metrics
    metrics=$(curl -sf "http://localhost:${MODULE_PORT}/metrics" 2>/dev/null)

    if [[ -z "$metrics" ]]; then
        log_error "Loki /metrics endpoint failed"
        return 1
    fi

    # Verify version in metrics
    local reported_version
    reported_version=$(echo "$metrics" | grep "loki_build_info" | grep -oP 'version="[^"]*"' | cut -d'"' -f2)

    if [[ -n "$reported_version" ]]; then
        log_info "Loki reporting version: $reported_version"
    fi

    # Test query endpoint (non-destructive)
    local query_result
    query_result=$(curl -sf "http://localhost:${MODULE_PORT}/loki/api/v1/labels" 2>/dev/null)

    if [[ -z "$query_result" ]]; then
        log_warn "Loki /labels endpoint returned empty (may be normal for fresh install)"
    else
        log_info "Query endpoint responsive"
    fi

    log_success "Loki health verification passed"
    return 0
}

#===============================================================================
# START/STOP OPERATIONS
#===============================================================================

start_service() {
    log_info "Starting $SERVICE_NAME service..."

    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"

    # Wait for service to be active
    sleep 5

    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        log_error "$SERVICE_NAME failed to start"
        journalctl -u "$SERVICE_NAME" -n 20 --no-pager
        return 1
    fi

    # Wait for ready and monitor WAL
    wait_for_ready 60 || return 1
    monitor_wal_replay || log_warn "WAL monitoring incomplete"

    log_success "$MODULE_NAME service started"
    return 0
}

stop_service() {
    # H-7: Use robust 3-layer verification if available, fallback to enhanced basic stop
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
                log_info "Waiting for $SERVICE_NAME to stop... ($wait_count/$max_wait)"
                sleep 1
                ((wait_count++))
            done

            # SIGTERM if still running
            if pgrep -f "$INSTALL_PATH" >/dev/null 2>&1; then
                log_warn "Service did not stop gracefully, sending SIGTERM"
                pkill -TERM -f "$INSTALL_PATH" 2>/dev/null || true
                sleep 5
            fi

            # SIGKILL as last resort
            if pgrep -f "$INSTALL_PATH" >/dev/null 2>&1; then
                log_error "Service did not respond to SIGTERM, sending SIGKILL"
                pkill -9 -f "$INSTALL_PATH" 2>/dev/null || true
                sleep 2
            fi

            # Final check
            if pgrep -f "$INSTALL_PATH" >/dev/null 2>&1; then
                log_error "CRITICAL: Failed to stop $SERVICE_NAME"
                return 1
            fi
        fi

        log_success "$SERVICE_NAME stopped"
    fi
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

main() {
    log_info "=========================================="
    log_info "Loki Installation/Upgrade Script"
    log_info "Target version: $MODULE_VERSION"
    log_info "=========================================="

    local current_version
    current_version=$(get_installed_version)

    if [[ -n "$current_version" ]]; then
        log_info "Current version: $current_version"

        if is_major_upgrade; then
            log_warn "MAJOR VERSION UPGRADE: $current_version -> $MODULE_VERSION"
            log_warn "This upgrade includes breaking changes"
        fi
    else
        log_info "New installation"
    fi

    # Pre-upgrade checks
    if [[ -n "$current_version" ]]; then
        validate_config || {
            log_error "Configuration validation failed"
            return 1
        }

        check_disk_space || return 1
        check_label_cardinality || true  # Non-fatal
    fi

    # Check if already at target version
    if is_installed; then
        log_skip "$MODULE_NAME v$MODULE_VERSION already installed"
        return 0
    fi

    # Create backup before upgrade
    local backup_path=""
    if [[ -n "$current_version" ]]; then
        backup_path=$(backup_loki)
        export BACKUP_PATH="$backup_path"
    fi

    # Stop service before upgrade
    stop_service

    # Clean bloom blocks for major upgrades (3.3+ format change)
    if [[ -n "$current_version" ]] && is_major_upgrade; then
        clean_bloom_blocks
    fi

    # Create user and directories
    create_user

    # Create default configuration if none exists (for fresh installs)
    create_default_config

    # Install binary
    if ! install_binary; then
        log_error "Binary installation failed"

        # Attempt rollback
        if [[ -n "$backup_path" ]]; then
            log_warn "Attempting rollback..."
            restore_from_backup "$backup_path" || log_error "Rollback failed"
        fi
        return 1
    fi

    # Migrate configuration for major upgrades
    if [[ -n "$current_version" ]] && is_major_upgrade; then
        migrate_config || {
            log_error "Configuration migration failed"

            if [[ -n "$backup_path" ]]; then
                log_warn "Attempting rollback..."
                restore_from_backup "$backup_path" || log_error "Rollback failed"
            fi
            return 1
        }
    fi

    # Create or update service file
    if [[ ! -f "/etc/systemd/system/${SERVICE_NAME}.service" ]] || [[ "$FORCE_MODE" == "true" ]]; then
        create_service
    fi

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
    log_success "Loki upgrade completed successfully!"
    log_success "Version: $current_version -> $new_version"
    if [[ -n "$backup_path" ]]; then
        log_info "Backup available at: $backup_path"
    fi
    log_success "=========================================="

    # Post-upgrade notes for major version
    if is_major_upgrade; then
        echo ""
        log_info "POST-UPGRADE NOTES:"
        log_info "1. Loki UI has been moved to Grafana plugin in v3.6"
        log_info "   Install: grafana-cli plugins install grafana-lokioperational-app"
        log_info "2. Schema v13 with TSDB is now the default"
        log_info "3. Label limit enforced at 15 per series (v3.4+)"
        log_info "4. Bloom filter blocks were regenerated"
        echo ""
    fi

    return 0
}

main "$@"
