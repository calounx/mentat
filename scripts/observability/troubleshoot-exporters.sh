#!/bin/bash
#===============================================================================
# Automated Exporter Troubleshooting System
#===============================================================================
# Comprehensive diagnostics and auto-remediation for exporter issues
#
# Usage:
#   ./troubleshoot-exporters.sh [OPTIONS]
#
# Options:
#   --quick              Quick scan (< 30 seconds)
#   --deep               Deep diagnostics (comprehensive)
#   --exporter NAME      Focus on specific exporter
#   --multi-host         Check multiple hosts in parallel
#   --apply-fix          Apply automatic fixes (default: dry-run)
#   --install-missing    Auto-install missing exporters
#   --remote HOST        Check remote host via SSH
#   --parallel N         Max parallel checks (default: 4)
#   --output json|text   Output format (default: text)
#   --verbose            Verbose output
#   --log FILE           Log to file
#
# Examples:
#   ./troubleshoot-exporters.sh --quick
#   ./troubleshoot-exporters.sh --exporter nginx_exporter --apply-fix
#   ./troubleshoot-exporters.sh --multi-host --remote host1,host2,host3
#   ./troubleshoot-exporters.sh --deep --install-missing --apply-fix
#
#===============================================================================

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# Source diagnostic library
source "${LIB_DIR}/diagnostic-helpers.sh" 2>/dev/null || {
    echo "ERROR: Missing diagnostic-helpers.sh library"
    echo "Please ensure ${LIB_DIR}/diagnostic-helpers.sh exists"
    exit 1
}

#===============================================================================
# Configuration
#===============================================================================

# Default options
SCAN_MODE="quick"           # quick, deep
DRY_RUN=true               # Safety: dry-run by default
INSTALL_MISSING=false
APPLY_FIX=false
SPECIFIC_EXPORTER=""
MULTI_HOST=false
REMOTE_HOSTS=()
MAX_PARALLEL=4
OUTPUT_FORMAT="text"       # text, json
VERBOSE=false
LOG_FILE=""

# Timing
START_TIME=$(date +%s)

# Results tracking
declare -A EXPORTER_STATUS
declare -A EXPORTER_ISSUES
declare -A EXPORTER_FIXES
TOTAL_CHECKS=0
TOTAL_ISSUES=0
TOTAL_FIXES=0

#===============================================================================
# Known Exporters Configuration
#===============================================================================

declare -A EXPORTER_CONFIG
EXPORTER_CONFIG=(
    # Format: "exporter_name|port|systemd_service|binary_path|config_path|metrics_path"

    [node_exporter]="9100|node_exporter|/usr/local/bin/node_exporter||/metrics"
    [nginx_exporter]="9113|nginx_exporter|/usr/local/bin/nginx_exporter|/etc/nginx_exporter.conf|/metrics"
    [mysqld_exporter]="9104|mysqld_exporter|/usr/local/bin/mysqld_exporter|/etc/.mysqld_exporter.cnf|/metrics"
    [mysql_exporter]="9104|mysql_exporter|/usr/local/bin/mysql_exporter|/etc/.mysql_exporter.cnf|/metrics"
    [phpfpm_exporter]="9253|phpfpm_exporter|/usr/local/bin/phpfpm_exporter||/metrics"
    [redis_exporter]="9121|redis_exporter|/usr/local/bin/redis_exporter||/metrics"
    [postgres_exporter]="9187|postgres_exporter|/usr/local/bin/postgres_exporter||/metrics"
    [apache_exporter]="9117|apache_exporter|/usr/local/bin/apache_exporter||/metrics"
    [blackbox_exporter]="9115|blackbox_exporter|/usr/local/bin/blackbox_exporter|/etc/blackbox_exporter.yml|/metrics"
    [promtail]="9080|promtail|/usr/local/bin/promtail|/etc/promtail/config.yml|/metrics"
)

#===============================================================================
# Functions
#===============================================================================

usage() {
    grep '^#' "$0" | grep -E '^# (Usage|Options|Examples):' -A 100 | grep -v '^#=$' | sed 's/^# \?//'
    exit 0
}

log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ "$VERBOSE" == "true" ]] || [[ "$level" != "DEBUG" ]]; then
        echo "[${timestamp}] [${level}] ${msg}"
    fi

    if [[ -n "$LOG_FILE" ]]; then
        echo "[${timestamp}] [${level}] ${msg}" >> "$LOG_FILE"
    fi
}

print_header() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo ""
        echo "================================================================================"
        echo "  $1"
        echo "================================================================================"
        echo ""
    fi
}

print_section() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo ""
        echo "$(colorize BLUE "▶ $1")"
        echo "$(colorize BLUE "$(printf '─%.0s' {1..80})")"
    fi
}

print_result() {
    local status="$1"
    local exporter="$2"
    local message="$3"

    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        case "$status" in
            OK)
                echo "  $(colorize GREEN '✓') ${exporter}: ${message}"
                ;;
            WARN)
                echo "  $(colorize YELLOW '⚠') ${exporter}: ${message}"
                ;;
            ERROR)
                echo "  $(colorize RED '✗') ${exporter}: ${message}"
                ;;
            INFO)
                echo "  $(colorize BLUE '→') ${exporter}: ${message}"
                ;;
        esac
    fi
}

#===============================================================================
# Diagnostic Functions
#===============================================================================

run_diagnostics() {
    local exporter="$1"
    local host="${2:-localhost}"

    log "INFO" "Running diagnostics for ${exporter} on ${host}"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    # Get exporter configuration
    local config="${EXPORTER_CONFIG[$exporter]:-}"
    if [[ -z "$config" ]]; then
        log "WARN" "Unknown exporter: ${exporter}"
        EXPORTER_STATUS[$exporter]="UNKNOWN"
        return 1
    fi

    IFS='|' read -r port service binary config_path metrics_path <<< "$config"

    # Initialize results
    local issues=()
    local fixes=()
    local status="OK"

    # Run diagnostic checks
    print_section "Diagnostics: ${exporter}"

    # 1. Service checks
    local service_status=$(check_service_status "$service" "$host")
    if [[ "$service_status" != "active" ]]; then
        issues+=("Service not running: ${service_status}")
        fixes+=("systemctl start ${service}")
        status="ERROR"
        print_result "ERROR" "$exporter" "Service ${service_status}"
    else
        print_result "OK" "$exporter" "Service running"
    fi

    # 2. Binary checks
    if ! check_binary_exists "$binary" "$host"; then
        issues+=("Binary not found: ${binary}")
        fixes+=("install_exporter ${exporter}")
        status="ERROR"
        print_result "ERROR" "$exporter" "Binary not installed"
    else
        print_result "OK" "$exporter" "Binary installed"
    fi

    # 3. Network checks
    if ! check_port_listening "$port" "$host"; then
        issues+=("Port ${port} not listening")
        fixes+=("check_bind_address ${exporter}")
        status="ERROR"
        print_result "ERROR" "$exporter" "Port ${port} not listening"
    else
        print_result "OK" "$exporter" "Port ${port} listening"
    fi

    if ! check_port_accessible "$port" "$host"; then
        issues+=("Port ${port} not accessible")
        fixes+=("firewall_allow_port ${port}")
        status="ERROR"
        print_result "ERROR" "$exporter" "Port ${port} blocked by firewall"
    else
        print_result "OK" "$exporter" "Port ${port} accessible"
    fi

    # 4. Metrics endpoint check
    if ! check_metrics_endpoint "$host" "$port" "$metrics_path"; then
        issues+=("Metrics endpoint unreachable")
        fixes+=("check_exporter_config ${exporter}")
        status="ERROR"
        print_result "ERROR" "$exporter" "Metrics endpoint failed"
    else
        print_result "OK" "$exporter" "Metrics endpoint responding"
    fi

    # 5. Prometheus configuration check
    if ! check_prometheus_target "$exporter" "$host" "$port"; then
        issues+=("Not in Prometheus targets")
        fixes+=("add_prometheus_target ${exporter} ${host} ${port}")
        status="WARN"
        print_result "WARN" "$exporter" "Not in Prometheus configuration"
    else
        print_result "OK" "$exporter" "Configured in Prometheus"
    fi

    # 6. Permission checks (deep scan only)
    if [[ "$SCAN_MODE" == "deep" ]]; then
        local perm_issues=$(check_permissions "$exporter" "$service" "$host")
        if [[ -n "$perm_issues" ]]; then
            issues+=("Permission issues: ${perm_issues}")
            fixes+=("fix_permissions ${exporter}")
            status="ERROR"
            print_result "ERROR" "$exporter" "Permission issues detected"
        fi
    fi

    # 7. Resource checks (deep scan only)
    if [[ "$SCAN_MODE" == "deep" ]]; then
        local resource_issues=$(check_resource_usage "$service" "$host")
        if [[ -n "$resource_issues" ]]; then
            issues+=("Resource issues: ${resource_issues}")
            status="WARN"
            print_result "WARN" "$exporter" "${resource_issues}"
        fi
    fi

    # 8. Check crash logs
    if [[ "$service_status" == "failed" ]] || [[ "$service_status" == "inactive" ]]; then
        local crash_info=$(check_crash_logs "$service" "$host")
        if [[ -n "$crash_info" ]]; then
            issues+=("Crash detected: ${crash_info}")
            print_result "ERROR" "$exporter" "Recent crash: ${crash_info}"
        fi
    fi

    # 9. Auto-start check
    if ! check_auto_start "$service" "$host"; then
        issues+=("Service not enabled for auto-start")
        fixes+=("systemctl enable ${service}")
        status="WARN"
        print_result "WARN" "$exporter" "Auto-start disabled"
    fi

    # Store results
    EXPORTER_STATUS[$exporter]="$status"
    EXPORTER_ISSUES[$exporter]="${issues[*]:-}"
    EXPORTER_FIXES[$exporter]="${fixes[*]:-}"

    if [[ "${#issues[@]}" -gt 0 ]]; then
        TOTAL_ISSUES=$((TOTAL_ISSUES + ${#issues[@]}))
    fi

    # Apply fixes if requested
    if [[ "$APPLY_FIX" == "true" ]] && [[ "${#fixes[@]}" -gt 0 ]]; then
        apply_fixes "$exporter" "${fixes[@]}"
    fi
}

apply_fixes() {
    local exporter="$1"
    shift
    local fixes=("$@")

    print_section "Auto-Remediation: ${exporter}"

    for fix in "${fixes[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            print_result "INFO" "$exporter" "[DRY-RUN] Would execute: ${fix}"
        else
            log "INFO" "Applying fix: ${fix}"
            if execute_fix "$fix"; then
                print_result "OK" "$exporter" "Applied fix: ${fix}"
                TOTAL_FIXES=$((TOTAL_FIXES + 1))
            else
                print_result "ERROR" "$exporter" "Failed to apply fix: ${fix}"
            fi
        fi
    done
}

execute_fix() {
    local fix_command="$1"

    # Parse and execute fix command
    case "$fix_command" in
        systemctl*)
            run_command "$fix_command"
            ;;
        firewall_allow_port*)
            local port=$(echo "$fix_command" | awk '{print $2}')
            firewall_allow_port "$port"
            ;;
        add_prometheus_target*)
            local exporter=$(echo "$fix_command" | awk '{print $2}')
            local host=$(echo "$fix_command" | awk '{print $3}')
            local port=$(echo "$fix_command" | awk '{print $4}')
            add_prometheus_target "$exporter" "$host" "$port"
            ;;
        install_exporter*)
            local exporter=$(echo "$fix_command" | awk '{print $2}')
            install_exporter "$exporter"
            ;;
        fix_permissions*)
            local exporter=$(echo "$fix_command" | awk '{print $2}')
            fix_permissions "$exporter"
            ;;
        check_bind_address*)
            local exporter=$(echo "$fix_command" | awk '{print $2}')
            fix_bind_address "$exporter"
            ;;
        check_exporter_config*)
            local exporter=$(echo "$fix_command" | awk '{print $2}')
            log "WARN" "Manual intervention required: Check ${exporter} configuration"
            return 1
            ;;
        *)
            log "WARN" "Unknown fix command: ${fix_command}"
            return 1
            ;;
    esac
}

#===============================================================================
# Auto-Discovery
#===============================================================================

discover_exporters() {
    local host="${1:-localhost}"

    log "INFO" "Discovering exporters on ${host}"

    local discovered=()

    # Check for running services
    for exporter in "${!EXPORTER_CONFIG[@]}"; do
        IFS='|' read -r port service binary config_path metrics_path <<< "${EXPORTER_CONFIG[$exporter]}"

        # Check if service exists
        if systemctl list-unit-files "${service}.service" 2>/dev/null | grep -q "${service}"; then
            discovered+=("$exporter")
        # Check if binary exists
        elif [[ -f "$binary" ]]; then
            discovered+=("$exporter")
        # Check if port is listening
        elif netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            discovered+=("$exporter")
        fi
    done

    # Also discover potential services that could have exporters
    discover_services_needing_exporters "$host"

    echo "${discovered[@]}"
}

discover_services_needing_exporters() {
    local host="${1:-localhost}"

    print_section "Service Discovery"

    # Check for services that should have exporters
    if systemctl is-active nginx &>/dev/null; then
        if ! systemctl is-active nginx_exporter &>/dev/null; then
            print_result "INFO" "nginx" "Detected but no exporter installed"
            if [[ "$INSTALL_MISSING" == "true" ]]; then
                print_result "INFO" "nginx_exporter" "Auto-install available"
            fi
        fi
    fi

    if systemctl is-active mysql &>/dev/null || systemctl is-active mariadb &>/dev/null; then
        if ! systemctl is-active mysqld_exporter &>/dev/null; then
            print_result "INFO" "mysql" "Detected but no exporter installed"
            if [[ "$INSTALL_MISSING" == "true" ]]; then
                print_result "INFO" "mysqld_exporter" "Auto-install available"
            fi
        fi
    fi

    if systemctl is-active redis &>/dev/null || systemctl is-active redis-server &>/dev/null; then
        if ! systemctl is-active redis_exporter &>/dev/null; then
            print_result "INFO" "redis" "Detected but no exporter installed"
            if [[ "$INSTALL_MISSING" == "true" ]]; then
                print_result "INFO" "redis_exporter" "Auto-install available"
            fi
        fi
    fi

    if systemctl is-active postgresql &>/dev/null; then
        if ! systemctl is-active postgres_exporter &>/dev/null; then
            print_result "INFO" "postgresql" "Detected but no exporter installed"
            if [[ "$INSTALL_MISSING" == "true" ]]; then
                print_result "INFO" "postgres_exporter" "Auto-install available"
            fi
        fi
    fi

    if systemctl is-active php*-fpm &>/dev/null; then
        if ! systemctl is-active phpfpm_exporter &>/dev/null; then
            print_result "INFO" "php-fpm" "Detected but no exporter installed"
            if [[ "$INSTALL_MISSING" == "true" ]]; then
                print_result "INFO" "phpfpm_exporter" "Auto-install available"
            fi
        fi
    fi
}

#===============================================================================
# Multi-Host Support
#===============================================================================

check_multi_host() {
    local hosts=("$@")

    print_header "Multi-Host Diagnostics"

    log "INFO" "Checking ${#hosts[@]} hosts in parallel (max ${MAX_PARALLEL})"

    local pids=()
    local running=0

    for host in "${hosts[@]}"; do
        # Wait if we've reached max parallel
        while [[ "$running" -ge "$MAX_PARALLEL" ]]; do
            for pid in "${pids[@]}"; do
                if ! kill -0 "$pid" 2>/dev/null; then
                    wait "$pid" 2>/dev/null || true
                    running=$((running - 1))
                fi
            done
            sleep 0.1
        done

        # Start check for this host
        (
            check_remote_host "$host"
        ) &
        pids+=($!)
        running=$((running + 1))
    done

    # Wait for all checks to complete
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
}

check_remote_host() {
    local host="$1"

    print_section "Host: ${host}"

    # Test SSH connectivity
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "${host}" "echo ok" &>/dev/null; then
        print_result "ERROR" "$host" "SSH connection failed"
        return 1
    fi

    print_result "OK" "$host" "SSH connection established"

    # Discover exporters on remote host
    local exporters=$(ssh "${host}" "$(declare -f discover_exporters); discover_exporters")

    # Run diagnostics for each exporter
    for exporter in $exporters; do
        run_diagnostics "$exporter" "$host"
    done
}

#===============================================================================
# Summary Report
#===============================================================================

print_summary() {
    local duration=$(($(date +%s) - START_TIME))

    print_header "DIAGNOSTIC SUMMARY"

    echo "Scan completed in ${duration}s"
    echo "Total checks: ${TOTAL_CHECKS}"
    echo "Total issues: ${TOTAL_ISSUES}"

    if [[ "$APPLY_FIX" == "true" ]]; then
        echo "Total fixes applied: ${TOTAL_FIXES}"
    fi

    echo ""
    echo "Exporter Status:"
    echo "$(printf '─%.0s' {1..80})"

    for exporter in "${!EXPORTER_STATUS[@]}"; do
        local status="${EXPORTER_STATUS[$exporter]}"
        local issues="${EXPORTER_ISSUES[$exporter]}"
        local fixes="${EXPORTER_FIXES[$exporter]}"

        case "$status" in
            OK)
                echo "$(colorize GREEN '✓') ${exporter}"
                ;;
            WARN)
                echo "$(colorize YELLOW '⚠') ${exporter}"
                if [[ -n "$issues" ]]; then
                    echo "    Issues: ${issues}"
                fi
                if [[ -n "$fixes" ]]; then
                    echo "    Fixes: ${fixes}"
                fi
                ;;
            ERROR)
                echo "$(colorize RED '✗') ${exporter}"
                if [[ -n "$issues" ]]; then
                    echo "    Issues: ${issues}"
                fi
                if [[ -n "$fixes" ]]; then
                    echo "    Fixes: ${fixes}"
                fi
                ;;
            UNKNOWN)
                echo "$(colorize GRAY '?') ${exporter}"
                ;;
        esac
    done

    echo ""

    # Recommendations
    if [[ "$TOTAL_ISSUES" -gt 0 ]] && [[ "$APPLY_FIX" != "true" ]]; then
        print_section "Recommendations"
        echo "  $(colorize YELLOW '→') Run with --apply-fix to auto-remediate issues"
        echo "  $(colorize YELLOW '→') Run with --deep for comprehensive diagnostics"
        echo "  $(colorize YELLOW '→') Check logs with: journalctl -u <service> -n 50"
    fi

    if [[ "$INSTALL_MISSING" == "true" ]]; then
        print_section "Installation Queue"
        echo "  Run with --install-missing to auto-install missing exporters"
    fi
}

#===============================================================================
# Main
#===============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --quick)
                SCAN_MODE="quick"
                shift
                ;;
            --deep)
                SCAN_MODE="deep"
                shift
                ;;
            --exporter)
                SPECIFIC_EXPORTER="$2"
                shift 2
                ;;
            --apply-fix)
                APPLY_FIX=true
                DRY_RUN=false
                shift
                ;;
            --install-missing)
                INSTALL_MISSING=true
                shift
                ;;
            --multi-host)
                MULTI_HOST=true
                shift
                ;;
            --remote)
                IFS=',' read -ra REMOTE_HOSTS <<< "$2"
                shift 2
                ;;
            --parallel)
                MAX_PARALLEL="$2"
                shift 2
                ;;
            --output)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --log)
                LOG_FILE="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Banner
    print_header "Exporter Troubleshooting System"

    log "INFO" "Mode: ${SCAN_MODE}"
    log "INFO" "Dry-run: ${DRY_RUN}"

    # Multi-host mode
    if [[ "$MULTI_HOST" == "true" ]] || [[ "${#REMOTE_HOSTS[@]}" -gt 0 ]]; then
        if [[ "${#REMOTE_HOSTS[@]}" -eq 0 ]]; then
            log "ERROR" "No remote hosts specified. Use --remote host1,host2,host3"
            exit 1
        fi
        check_multi_host "${REMOTE_HOSTS[@]}"
    else
        # Single host mode
        if [[ -n "$SPECIFIC_EXPORTER" ]]; then
            # Check specific exporter
            run_diagnostics "$SPECIFIC_EXPORTER"
        else
            # Discover and check all exporters
            local exporters=($(discover_exporters))

            if [[ "${#exporters[@]}" -eq 0 ]]; then
                log "WARN" "No exporters discovered"
                discover_services_needing_exporters
            else
                for exporter in "${exporters[@]}"; do
                    run_diagnostics "$exporter"
                done
            fi
        fi
    fi

    # Print summary
    print_summary

    # Exit code based on results
    if [[ "$TOTAL_ISSUES" -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Run main
main "$@"
