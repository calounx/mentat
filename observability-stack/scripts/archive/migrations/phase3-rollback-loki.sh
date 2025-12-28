#!/bin/bash
################################################################################
# Phase 3: Loki Rollback Script
# Rolls back Loki from 3.6.3 to 2.9.3
#
# Usage:
#   ./phase3-rollback-loki.sh [BACKUP_TIMESTAMP]
#
# If BACKUP_TIMESTAMP not provided, uses most recent backup.
#
# Exit Codes:
#   0 - Rollback successful
#   1 - Backup not found
#   2 - Rollback failed
#   3 - Validation failed after rollback
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
BACKUP_BASE_DIR="/var/lib/observability-upgrades/backups/phase3-loki"
LOG_FILE="/var/log/loki-rollback-$(date +%Y%m%d_%H%M%S).log"

# Functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 2
    fi
}

find_latest_backup() {
    if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
        error "Backup directory not found: $BACKUP_BASE_DIR"
        exit 1
    fi

    LATEST=$(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "20*" | sort -r | head -1)

    if [[ -z "$LATEST" ]]; then
        error "No backup directories found in $BACKUP_BASE_DIR"
        exit 1
    fi

    echo "$LATEST"
}

validate_backup() {
    local backup_dir=$1

    log "Validating backup: $backup_dir"

    # Check required files exist
    if [[ ! -f "$backup_dir/loki-2.9.3" ]]; then
        error "Loki binary not found in backup: $backup_dir/loki-2.9.3"
        return 1
    fi

    if [[ ! -d "$backup_dir/config" ]]; then
        error "Configuration not found in backup: $backup_dir/config"
        return 1
    fi

    # Optional: Check for data backup
    if [[ ! -f "$backup_dir/loki-data.tar.gz" ]] && [[ ! -d "$backup_dir/snapshot" ]]; then
        warn "No data backup found (loki-data.tar.gz or snapshot). Only binary and config will be restored."
    fi

    # Check version file
    if [[ -f "$backup_dir/version.txt" ]]; then
        BACKUP_VERSION=$(cat "$backup_dir/version.txt" | grep -oP 'version \K[0-9.]+' || echo "unknown")
        log "Backup version: $BACKUP_VERSION"
    fi

    return 0
}

stop_loki() {
    log "Stopping Loki service..."

    if systemctl is-active --quiet loki; then
        systemctl stop loki
        sleep 5
    else
        warn "Loki service not running"
    fi

    # Verify stopped
    if systemctl is-active --quiet loki; then
        error "Failed to stop Loki service"
        return 1
    fi

    log "Loki service stopped"
    return 0
}

restore_binary() {
    local backup_dir=$1

    log "Restoring Loki binary from backup..."

    # Backup current binary (3.6.3) just in case
    if [[ -f /usr/local/bin/loki ]]; then
        cp /usr/local/bin/loki /usr/local/bin/loki.3.6.3.bak
        log "Current binary backed up to /usr/local/bin/loki.3.6.3.bak"
    fi

    # Restore 2.9.3 binary
    cp "$backup_dir/loki-2.9.3" /usr/local/bin/loki
    chown root:root /usr/local/bin/loki
    chmod 755 /usr/local/bin/loki

    # Verify restored version
    VERSION=$(/usr/local/bin/loki --version 2>&1 | grep -oP 'version \K[0-9.]+' || echo "unknown")

    if [[ "$VERSION" == "2.9.3" ]]; then
        log "Binary restored successfully: Loki $VERSION"
        return 0
    else
        error "Binary restoration failed. Expected 2.9.3, got: $VERSION"
        return 1
    fi
}

restore_config() {
    local backup_dir=$1

    log "Restoring Loki configuration from backup..."

    # Backup current config (3.6.3) just in case
    if [[ -d /etc/loki ]]; then
        cp -r /etc/loki "/etc/loki.3.6.3.bak.$(date +%Y%m%d_%H%M%S)"
        log "Current config backed up to /etc/loki.3.6.3.bak.*"
    fi

    # Remove current config
    rm -rf /etc/loki

    # Restore 2.9.3 config
    cp -r "$backup_dir/config" /etc/loki
    chown -R loki:loki /etc/loki
    chmod 755 /etc/loki
    chmod 644 /etc/loki/*.yaml

    # Verify config restored
    if [[ -f /etc/loki/loki-config.yaml ]]; then
        log "Configuration restored successfully"

        # Check for table_manager (should be present in 2.9.3 config)
        if grep -q "table_manager" /etc/loki/loki-config.yaml; then
            log "✓ Verified: table_manager present in restored config (expected for 2.9.3)"
        fi

        return 0
    else
        error "Configuration restoration failed"
        return 1
    fi
}

restore_data() {
    local backup_dir=$1

    # Ask user if they want to restore data
    warn "Data restoration will OVERWRITE current Loki data."
    warn "This will LOSE all logs ingested after backup timestamp."
    read -p "Do you want to restore data? (yes/NO): " -r RESTORE_DATA

    if [[ ! "$RESTORE_DATA" =~ ^[Yy][Ee][Ss]$ ]]; then
        warn "Skipping data restoration. Existing data will be preserved."
        return 0
    fi

    log "Restoring Loki data from backup..."

    # Check for data backup
    if [[ -f "$backup_dir/loki-data.tar.gz" ]]; then
        log "Found data archive: loki-data.tar.gz"

        # Backup current data
        if [[ -d /var/lib/loki ]]; then
            mv /var/lib/loki "/var/lib/loki.3.6.3.bak.$(date +%Y%m%d_%H%M%S)"
            log "Current data backed up to /var/lib/loki.3.6.3.bak.*"
        fi

        # Extract backup
        tar -xzf "$backup_dir/loki-data.tar.gz" -C /
        chown -R loki:loki /var/lib/loki
        chmod 755 /var/lib/loki

        log "Data restored successfully from archive"
        return 0

    elif [[ -d "$backup_dir/snapshot" ]]; then
        log "Found snapshot backup"

        # Restore from snapshot
        if [[ -d /var/lib/loki ]]; then
            mv /var/lib/loki "/var/lib/loki.3.6.3.bak.$(date +%Y%m%d_%H%M%S)"
        fi

        cp -r "$backup_dir/snapshot" /var/lib/loki
        chown -R loki:loki /var/lib/loki

        log "Data restored successfully from snapshot"
        return 0
    else
        warn "No data backup found. Skipping data restoration."
        return 0
    fi
}

start_loki() {
    log "Starting Loki service..."

    systemctl start loki

    # Wait for startup
    log "Waiting 30 seconds for Loki to start..."
    sleep 30

    # Check if running
    if systemctl is-active --quiet loki; then
        log "Loki service started"
        return 0
    else
        error "Loki service failed to start"
        systemctl status loki --no-pager
        return 1
    fi
}

validate_rollback() {
    log "Validating rollback..."

    # Test 1: Check version
    VERSION=$(/usr/local/bin/loki --version 2>&1 | grep -oP 'version \K[0-9.]+' || echo "unknown")
    if [[ "$VERSION" != "2.9.3" ]]; then
        error "Version mismatch. Expected 2.9.3, got: $VERSION"
        return 1
    fi
    log "✓ Version verified: $VERSION"

    # Test 2: Check service status
    if ! systemctl is-active --quiet loki; then
        error "Loki service not running"
        return 1
    fi
    log "✓ Service running"

    # Test 3: Health check
    HEALTH=$(curl -s http://localhost:3100/ready 2>/dev/null || echo "failed")
    if [[ "$HEALTH" != *"ready"* ]]; then
        error "Health check failed: $HEALTH"
        return 1
    fi
    log "✓ Health check passed"

    # Test 4: Test query
    QUERY_STATUS=$(curl -s -G "http://localhost:3100/loki/api/v1/query" \
        --data-urlencode 'query={job=~".+"}' \
        --data-urlencode 'limit=1' 2>/dev/null | jq -r '.status' || echo "failed")

    if [[ "$QUERY_STATUS" != "success" ]]; then
        warn "Query test failed (may be normal if no recent logs)"
    else
        log "✓ Query functionality verified"
    fi

    # Test 5: Check metrics
    METRICS=$(curl -s http://localhost:3100/metrics 2>/dev/null | grep "loki_build_info" || echo "failed")
    if [[ "$METRICS" == "failed" ]]; then
        warn "Metrics endpoint not responding"
    else
        log "✓ Metrics endpoint responding"
    fi

    # Test 6: Check logs for errors
    ERROR_COUNT=$(journalctl -u loki -n 50 --no-pager | grep -i error | wc -l)
    if [[ $ERROR_COUNT -gt 0 ]]; then
        warn "$ERROR_COUNT errors found in logs (last 50 lines)"
        journalctl -u loki -n 50 --no-pager | grep -i error
    else
        log "✓ No errors in recent logs"
    fi

    log "Rollback validation completed"
    return 0
}

print_summary() {
    local backup_dir=$1
    local rollback_success=$2

    echo ""
    echo "======================================================================"
    echo "                    ROLLBACK SUMMARY"
    echo "======================================================================"
    echo "Backup Directory:     $backup_dir"
    echo "Restored Version:     $(/usr/local/bin/loki --version 2>&1 | grep version || echo 'unknown')"
    echo "Service Status:       $(systemctl is-active loki || echo 'inactive')"
    echo "Health Check:         $(curl -s http://localhost:3100/ready 2>/dev/null || echo 'failed')"
    echo "Rollback Status:      $(if [[ $rollback_success -eq 0 ]]; then echo 'SUCCESS'; else echo 'FAILED'; fi)"
    echo "Log File:            $LOG_FILE"
    echo "======================================================================"
    echo ""

    if [[ $rollback_success -eq 0 ]]; then
        echo -e "${GREEN}Rollback completed successfully!${NC}"
        echo ""
        echo "Next steps:"
        echo "1. Verify Grafana datasource: http://localhost:3000"
        echo "2. Check log ingestion: journalctl -u loki -f"
        echo "3. Test queries in Grafana Explore"
        echo "4. Review rollback logs: $LOG_FILE"
        echo ""
        echo "To re-attempt upgrade:"
        echo "1. Review failure logs: journalctl -u loki -n 200"
        echo "2. Fix identified issues"
        echo "3. Follow Phase 3 upgrade guide"
    else
        echo -e "${RED}Rollback encountered issues!${NC}"
        echo ""
        echo "Troubleshooting steps:"
        echo "1. Check service logs: journalctl -u loki -n 100"
        echo "2. Verify configuration: cat /etc/loki/loki-config.yaml"
        echo "3. Check file permissions: ls -la /var/lib/loki"
        echo "4. Review rollback log: $LOG_FILE"
        echo ""
        echo "Emergency recovery:"
        echo "1. Restore from 3.6.3 backup:"
        echo "   cp /usr/local/bin/loki.3.6.3.bak /usr/local/bin/loki"
        echo "   cp -r /etc/loki.3.6.3.bak.* /etc/loki"
        echo "2. Restart service: systemctl restart loki"
    fi
}

main() {
    log "======================================================================"
    log "         Phase 3: Loki Rollback (3.6.3 → 2.9.3)"
    log "======================================================================"

    # Check root privileges
    check_root

    # Determine backup directory
    if [[ $# -eq 1 ]]; then
        BACKUP_DIR="$BACKUP_BASE_DIR/$1"

        if [[ ! -d "$BACKUP_DIR" ]]; then
            error "Backup directory not found: $BACKUP_DIR"
            exit 1
        fi
    else
        BACKUP_DIR=$(find_latest_backup)
        log "Using latest backup: $BACKUP_DIR"
    fi

    # Validate backup
    if ! validate_backup "$BACKUP_DIR"; then
        error "Backup validation failed"
        exit 1
    fi

    # Confirm rollback
    echo ""
    echo "This will rollback Loki from 3.6.3 to 2.9.3"
    echo "Backup: $BACKUP_DIR"
    echo ""
    read -p "Continue with rollback? (yes/NO): " -r CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Rollback cancelled by user"
        exit 0
    fi

    # Execute rollback steps
    ROLLBACK_SUCCESS=0

    if ! stop_loki; then
        error "Failed to stop Loki"
        ROLLBACK_SUCCESS=2
    elif ! restore_binary "$BACKUP_DIR"; then
        error "Failed to restore binary"
        ROLLBACK_SUCCESS=2
    elif ! restore_config "$BACKUP_DIR"; then
        error "Failed to restore configuration"
        ROLLBACK_SUCCESS=2
    elif ! restore_data "$BACKUP_DIR"; then
        error "Failed to restore data"
        ROLLBACK_SUCCESS=2
    elif ! start_loki; then
        error "Failed to start Loki"
        ROLLBACK_SUCCESS=2
    elif ! validate_rollback; then
        error "Rollback validation failed"
        ROLLBACK_SUCCESS=3
    fi

    # Print summary
    print_summary "$BACKUP_DIR" $ROLLBACK_SUCCESS

    exit $ROLLBACK_SUCCESS
}

# Execute main function
main "$@"
