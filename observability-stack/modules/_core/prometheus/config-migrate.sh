#!/bin/bash
#===============================================================================
# Prometheus Configuration Migration Script
# Part of the observability-stack module system
#
# Handles configuration migration for Prometheus 2.x -> 3.x upgrade
#
# Breaking changes addressed:
#   - Deprecated command-line flags
#   - Configuration file changes
#   - Remote write/read configuration changes
#   - Rule file compatibility
#
# Usage:
#   ./config-migrate.sh [options]
#
# Options:
#   --check              Check for issues without making changes
#   --migrate            Apply migrations
#   --backup             Create backup before migration
#   --service-file=PATH  Path to systemd service file
#   --config-file=PATH   Path to prometheus.yml
#   --dry-run            Show what would be done
#===============================================================================

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../../scripts/lib" 2>/dev/null && pwd)" || LIB_DIR="$(cd "$SCRIPT_DIR/../../../scripts/lib" && pwd)"

if [[ -f "$LIB_DIR/common.sh" ]]; then
    source "$LIB_DIR/common.sh"
else
    log_info() { echo "[INFO] $1"; }
    log_success() { echo "[SUCCESS] $1"; }
    log_warn() { echo "[WARN] $1"; }
    log_error() { echo "[ERROR] $1" >&2; }
fi

#===============================================================================
# CONFIGURATION
#===============================================================================

SERVICE_FILE="${SERVICE_FILE:-/etc/systemd/system/prometheus.service}"
CONFIG_FILE="${CONFIG_FILE:-/etc/prometheus/prometheus.yml}"
RULES_DIR="${RULES_DIR:-/etc/prometheus/rules}"

CHECK_ONLY="${CHECK_ONLY:-false}"
DO_MIGRATE="${DO_MIGRATE:-false}"
DO_BACKUP="${DO_BACKUP:-true}"
DRY_RUN="${DRY_RUN:-false}"

BACKUP_DIR="${BACKUP_DIR:-/var/lib/observability-upgrades/backups/prometheus/config-migration}"

#===============================================================================
# ARGUMENT PARSING
#===============================================================================

for arg in "$@"; do
    case "$arg" in
        --check)
            CHECK_ONLY=true
            ;;
        --migrate)
            DO_MIGRATE=true
            ;;
        --backup)
            DO_BACKUP=true
            ;;
        --service-file=*)
            SERVICE_FILE="${arg#*=}"
            ;;
        --config-file=*)
            CONFIG_FILE="${arg#*=}"
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --check              Check for issues without making changes"
            echo "  --migrate            Apply migrations"
            echo "  --backup             Create backup before migration"
            echo "  --service-file=PATH  Path to systemd service file"
            echo "  --config-file=PATH   Path to prometheus.yml"
            echo "  --dry-run            Show what would be done"
            exit 0
            ;;
    esac
done

#===============================================================================
# DEPRECATED FLAGS DATABASE
#===============================================================================

# Flags removed in Prometheus 3.x
declare -A REMOVED_FLAGS=(
    ["--storage.tsdb.no-lockfile"]="Removed in 3.x - TSDB always uses lockfile"
    ["--storage.tsdb.allow-overlapping-blocks"]="Removed in 3.x - overlapping blocks always handled"
    ["--storage.tsdb.retention"]="Renamed to --storage.tsdb.retention.time"
    ["--alertmanager.notification-queue-capacity"]="Removed - use alertmanager_config in prometheus.yml"
    ["--alertmanager.timeout"]="Removed - configure in alertmanager_config"
    ["--query.max-concurrency"]="Renamed to --query.max-samples"
)

# Flags renamed in Prometheus 3.x
declare -A RENAMED_FLAGS=(
    ["--storage.tsdb.wal-compression"]="--storage.tsdb.wal-compression-type=zstd"
    ["--storage.tsdb.retention"]="--storage.tsdb.retention.time"
    ["--web.read-timeout"]="--web.read-header-timeout"
)

# Flags with changed defaults
declare -A CHANGED_DEFAULTS=(
    ["--storage.tsdb.min-block-duration"]="Changed from 2h to automatic"
    ["--storage.tsdb.max-block-duration"]="Changed from 36h to automatic"
    ["--query.lookback-delta"]="Default changed from 5m to 5m (no change)"
)

# Deprecated config file options
declare -A DEPRECATED_CONFIG=(
    ["remote_write.queue_config.max_shards"]="Consider using capacity instead"
    ["remote_write.queue_config.max_samples_per_send"]="Default increased in 3.x"
    ["scrape_configs.honor_timestamps"]="Behavior changed in 3.x"
)

#===============================================================================
# SERVICE FILE CHECKS
#===============================================================================

# Check service file for deprecated flags
check_service_file() {
    local issues=()
    local warnings=()

    if [[ ! -f "$SERVICE_FILE" ]]; then
        log_warn "Service file not found: $SERVICE_FILE"
        return 0
    fi

    log_info "Checking service file: $SERVICE_FILE"

    # Extract ExecStart line
    local exec_start
    exec_start=$(grep -E "^ExecStart=" "$SERVICE_FILE" | head -1 || true)

    if [[ -z "$exec_start" ]]; then
        log_warn "Could not find ExecStart in service file"
        return 0
    fi

    # Check for removed flags
    for flag in "${!REMOVED_FLAGS[@]}"; do
        if grep -q "$flag" "$SERVICE_FILE"; then
            issues+=("REMOVED: $flag - ${REMOVED_FLAGS[$flag]}")
        fi
    done

    # Check for renamed flags
    for flag in "${!RENAMED_FLAGS[@]}"; do
        if grep -q "$flag" "$SERVICE_FILE"; then
            local new_flag="${RENAMED_FLAGS[$flag]}"
            issues+=("RENAMED: $flag -> $new_flag")
        fi
    done

    # Check for flags with changed defaults
    for flag in "${!CHANGED_DEFAULTS[@]}"; do
        if grep -q "$flag" "$SERVICE_FILE"; then
            warnings+=("CHANGED DEFAULT: $flag - ${CHANGED_DEFAULTS[$flag]}")
        fi
    done

    # Report findings
    if [[ ${#issues[@]} -gt 0 ]]; then
        echo ""
        log_error "Service file issues found:"
        for issue in "${issues[@]}"; do
            echo "  - $issue"
        done
        echo ""
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        echo ""
        log_warn "Service file warnings:"
        for warning in "${warnings[@]}"; do
            echo "  - $warning"
        done
        echo ""
    fi

    if [[ ${#issues[@]} -eq 0 && ${#warnings[@]} -eq 0 ]]; then
        log_success "Service file: No issues found"
    fi

    return ${#issues[@]}
}

# Migrate service file
migrate_service_file() {
    if [[ ! -f "$SERVICE_FILE" ]]; then
        log_warn "Service file not found, skipping migration"
        return 0
    fi

    log_info "Migrating service file..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would migrate service file"
        return 0
    fi

    # Create backup
    if [[ "$DO_BACKUP" == "true" ]]; then
        local backup_file="${BACKUP_DIR}/prometheus.service.$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        cp "$SERVICE_FILE" "$backup_file"
        log_info "Backup created: $backup_file"
    fi

    # Apply migrations
    local tmp_file
    tmp_file=$(mktemp)
    cp "$SERVICE_FILE" "$tmp_file"

    # Remove deprecated flags
    for flag in "${!REMOVED_FLAGS[@]}"; do
        # Remove flag and its value if any
        sed -i "s|${flag}[= ][^ \\\\]*||g" "$tmp_file"
        sed -i "s|${flag}||g" "$tmp_file"
    done

    # Rename flags
    for old_flag in "${!RENAMED_FLAGS[@]}"; do
        local new_flag="${RENAMED_FLAGS[$old_flag]}"
        # Handle flags with values
        if [[ "$new_flag" == *"="* ]]; then
            # Replace whole flag with new flag (ignore existing value)
            sed -i "s|${old_flag}[= ][^ \\\\]*|${new_flag}|g" "$tmp_file"
            sed -i "s|${old_flag}|${new_flag}|g" "$tmp_file"
        else
            # Just rename the flag, keep value
            sed -i "s|${old_flag}|${new_flag}|g" "$tmp_file"
        fi
    done

    # Clean up multiple spaces and empty backslash continuations
    sed -i 's/  */ /g' "$tmp_file"
    sed -i 's/ \\$/\\/g' "$tmp_file"
    sed -i '/^[[:space:]]*\\$/d' "$tmp_file"

    # Validate the new service file
    if ! systemd-analyze verify "$tmp_file" 2>/dev/null; then
        log_warn "systemd-analyze verify not available or returned warnings"
    fi

    # Apply changes
    mv "$tmp_file" "$SERVICE_FILE"
    chmod 644 "$SERVICE_FILE"

    # Reload systemd
    systemctl daemon-reload

    log_success "Service file migrated"
}

#===============================================================================
# CONFIG FILE CHECKS
#===============================================================================

# Check prometheus.yml for deprecated options
check_config_file() {
    local issues=()
    local warnings=()

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_warn "Config file not found: $CONFIG_FILE"
        return 0
    fi

    log_info "Checking config file: $CONFIG_FILE"

    # Check for deprecated config options
    for option in "${!DEPRECATED_CONFIG[@]}"; do
        local key="${option%%.*}"
        if grep -q "$key" "$CONFIG_FILE"; then
            warnings+=("DEPRECATED: $option - ${DEPRECATED_CONFIG[$option]}")
        fi
    done

    # Check for remote_write configuration that may need updates
    if grep -q "remote_write:" "$CONFIG_FILE"; then
        log_info "Remote write configuration detected - review for 3.x compatibility"
        warnings+=("Remote write config detected - verify queue_config settings")
    fi

    # Check for remote_read configuration
    if grep -q "remote_read:" "$CONFIG_FILE"; then
        log_info "Remote read configuration detected - review for 3.x compatibility"
        warnings+=("Remote read config detected - verify read_recent setting")
    fi

    # Check for alertmanager configuration
    if grep -q "alerting:" "$CONFIG_FILE"; then
        log_info "Alertmanager configuration detected"
        # Check for deprecated alertmanager options
        if grep -q "timeout:" "$CONFIG_FILE" && grep -A5 "alertmanagers:" "$CONFIG_FILE" | grep -q "timeout:"; then
            warnings+=("Alertmanager timeout config should be reviewed")
        fi
    fi

    # Check for relabel_configs that might use deprecated features
    if grep -q "relabel_configs:" "$CONFIG_FILE"; then
        # Check for action: labelkeep/labeldrop (changed behavior)
        if grep -q "action: labelkeep\|action: labeldrop" "$CONFIG_FILE"; then
            warnings+=("labelkeep/labeldrop actions - verify behavior in 3.x")
        fi
    fi

    # Report findings
    if [[ ${#issues[@]} -gt 0 ]]; then
        echo ""
        log_error "Config file issues found:"
        for issue in "${issues[@]}"; do
            echo "  - $issue"
        done
        echo ""
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        echo ""
        log_warn "Config file warnings:"
        for warning in "${warnings[@]}"; do
            echo "  - $warning"
        done
        echo ""
    fi

    if [[ ${#issues[@]} -eq 0 && ${#warnings[@]} -eq 0 ]]; then
        log_success "Config file: No issues found"
    fi

    return ${#issues[@]}
}

# Validate config with promtool
validate_config() {
    log_info "Validating configuration with promtool..."

    if [[ ! -x "/usr/local/bin/promtool" ]]; then
        log_warn "promtool not available, skipping validation"
        return 0
    fi

    if /usr/local/bin/promtool check config "$CONFIG_FILE" 2>&1; then
        log_success "Configuration validation passed"
        return 0
    else
        log_error "Configuration validation failed"
        return 1
    fi
}

#===============================================================================
# RULE FILE CHECKS
#===============================================================================

# Check rule files for compatibility
check_rule_files() {
    if [[ ! -d "$RULES_DIR" ]]; then
        log_info "No rules directory found: $RULES_DIR"
        return 0
    fi

    log_info "Checking rule files in: $RULES_DIR"

    local issues=()
    local warnings=()

    # Find all rule files
    while IFS= read -r -d '' rule_file; do
        log_info "Checking: $(basename "$rule_file")"

        # Check for deprecated PromQL functions
        # Note: Most PromQL is backward compatible, but some edge cases exist

        # Check for timestamp() usage with subqueries (behavior changed)
        if grep -q "timestamp(" "$rule_file"; then
            warnings+=("$(basename "$rule_file"): timestamp() function - verify subquery behavior")
        fi

        # Check for @ modifier usage
        if grep -q "@" "$rule_file" && grep -qE '@[0-9]|@start|@end' "$rule_file"; then
            warnings+=("$(basename "$rule_file"): @ modifier - verify behavior in 3.x")
        fi

        # Validate with promtool if available
        if [[ -x "/usr/local/bin/promtool" ]]; then
            if ! /usr/local/bin/promtool check rules "$rule_file" 2>&1 | grep -q "SUCCESS"; then
                issues+=("$(basename "$rule_file"): Rule validation failed")
            fi
        fi

    done < <(find "$RULES_DIR" -name "*.yml" -o -name "*.yaml" -print0 2>/dev/null)

    # Report findings
    if [[ ${#issues[@]} -gt 0 ]]; then
        echo ""
        log_error "Rule file issues found:"
        for issue in "${issues[@]}"; do
            echo "  - $issue"
        done
        echo ""
    fi

    if [[ ${#warnings[@]} -gt 0 ]]; then
        echo ""
        log_warn "Rule file warnings:"
        for warning in "${warnings[@]}"; do
            echo "  - $warning"
        done
        echo ""
    fi

    if [[ ${#issues[@]} -eq 0 && ${#warnings[@]} -eq 0 ]]; then
        log_success "Rule files: No issues found"
    fi

    return ${#issues[@]}
}

#===============================================================================
# GENERATE MIGRATION REPORT
#===============================================================================

generate_report() {
    local output_file="${1:-/tmp/prometheus-migration-report.txt}"

    log_info "Generating migration report: $output_file"

    {
        echo "=========================================="
        echo "Prometheus 2.x -> 3.x Migration Report"
        echo "Generated: $(date)"
        echo "=========================================="
        echo ""
        echo "Service File: $SERVICE_FILE"
        echo "Config File:  $CONFIG_FILE"
        echo "Rules Dir:    $RULES_DIR"
        echo ""
        echo "=========================================="
        echo "Service File Analysis"
        echo "=========================================="
    } > "$output_file"

    check_service_file >> "$output_file" 2>&1 || true

    {
        echo ""
        echo "=========================================="
        echo "Configuration File Analysis"
        echo "=========================================="
    } >> "$output_file"

    check_config_file >> "$output_file" 2>&1 || true

    {
        echo ""
        echo "=========================================="
        echo "Rule Files Analysis"
        echo "=========================================="
    } >> "$output_file"

    check_rule_files >> "$output_file" 2>&1 || true

    {
        echo ""
        echo "=========================================="
        echo "Recommendations"
        echo "=========================================="
        echo ""
        echo "1. Run ./config-migrate.sh --migrate to apply automatic fixes"
        echo "2. Review warnings and update configuration manually if needed"
        echo "3. Test configuration with: promtool check config $CONFIG_FILE"
        echo "4. Create TSDB backup before upgrade: ./tsdb-backup.sh"
        echo "5. Proceed with Stage 1 upgrade to 2.55.1 first"
        echo ""
    } >> "$output_file"

    log_success "Report generated: $output_file"
    cat "$output_file"
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    log_info "=========================================="
    log_info "Prometheus Configuration Migration Tool"
    log_info "=========================================="
    echo ""

    local total_issues=0

    # Check service file
    local service_issues=0
    check_service_file || service_issues=$?
    ((total_issues += service_issues)) || true

    echo ""

    # Check config file
    local config_issues=0
    check_config_file || config_issues=$?
    ((total_issues += config_issues)) || true

    echo ""

    # Check rule files
    local rule_issues=0
    check_rule_files || rule_issues=$?
    ((total_issues += rule_issues)) || true

    echo ""

    # Validate config
    validate_config || true

    echo ""
    echo "=========================================="
    echo "Summary"
    echo "=========================================="
    echo "Total issues requiring migration: $total_issues"
    echo ""

    # Apply migrations if requested
    if [[ "$DO_MIGRATE" == "true" && $total_issues -gt 0 ]]; then
        log_info "Applying migrations..."
        migrate_service_file
        log_success "Migrations applied"
        echo ""
        log_info "Re-checking after migration..."
        check_service_file || true
    elif [[ "$DO_MIGRATE" == "true" && $total_issues -eq 0 ]]; then
        log_success "No migrations needed"
    elif [[ "$CHECK_ONLY" == "true" ]]; then
        if [[ $total_issues -gt 0 ]]; then
            log_warn "Issues found. Run with --migrate to apply fixes"
        else
            log_success "Configuration is ready for 3.x upgrade"
        fi
    else
        if [[ $total_issues -gt 0 ]]; then
            echo ""
            echo "Actions:"
            echo "  - Run with --migrate to apply automatic fixes"
            echo "  - Run with --check for read-only analysis"
            echo ""
        fi
    fi

    return $total_issues
}

main "$@"
