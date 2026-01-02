#!/bin/bash
#
# Comprehensive Exporter Validation Script
#
# Validates all exporters in the observability stack, including:
# - Local exporters on monitoring host
# - Remote exporters on monitored hosts
# - Prometheus integration
# - Generates report and alerts on issues
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$(dirname "$SCRIPT_DIR")"
VALIDATOR="$TOOLS_DIR/validate-exporters.py"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
RESULTS_DIR="${RESULTS_DIR:-/tmp/exporter-validation}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if [ ! -x "$VALIDATOR" ]; then
        log_error "Validator script not found or not executable: $VALIDATOR"
        exit 1
    fi

    if ! python3 -c "import requests" 2>/dev/null; then
        log_error "Python requests library not installed"
        log_info "Install with: pip install -r $TOOLS_DIR/requirements.txt"
        exit 1
    fi

    # Create results directory
    mkdir -p "$RESULTS_DIR"

    log_info "Prerequisites OK"
}

# Validate local exporters
validate_local_exporters() {
    log_info "Validating local exporters..."

    "$VALIDATOR" \
        --scan-host localhost \
        --prometheus "$PROMETHEUS_URL" \
        --json > "$RESULTS_DIR/local-exporters-$TIMESTAMP.json"

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log_info "Local exporters: PASSED"
    elif [ $exit_code -eq 1 ]; then
        log_warn "Local exporters: WARNINGS detected"
    else
        log_error "Local exporters: CRITICAL issues detected"
    fi

    return $exit_code
}

# Validate specific exporter endpoints
validate_specific_exporters() {
    log_info "Validating specific exporters..."

    local endpoints=(
        "http://localhost:9100/metrics"  # node_exporter
        "http://localhost:9090/metrics"  # prometheus
        "http://localhost:9093/metrics"  # alertmanager
    )

    local failed=0
    local warnings=0

    for endpoint in "${endpoints[@]}"; do
        log_info "Validating $endpoint..."

        if "$VALIDATOR" \
            --endpoint "$endpoint" \
            --json > "$RESULTS_DIR/$(echo "$endpoint" | sed 's|[:/]|-|g')-$TIMESTAMP.json"; then
            log_info "  ✓ $endpoint passed"
        else
            local exit_code=$?
            if [ $exit_code -eq 1 ]; then
                log_warn "  ⚠ $endpoint has warnings"
                ((warnings++))
            else
                log_error "  ✗ $endpoint failed"
                ((failed++))
            fi
        fi
    done

    if [ $failed -gt 0 ]; then
        return 2
    elif [ $warnings -gt 0 ]; then
        return 1
    fi
    return 0
}

# Validate Prometheus targets
validate_prometheus_targets() {
    log_info "Validating Prometheus targets..."

    "$VALIDATOR" \
        --prometheus "$PROMETHEUS_URL" \
        --json > "$RESULTS_DIR/prometheus-targets-$TIMESTAMP.json"

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log_info "Prometheus targets: PASSED"
    elif [ $exit_code -eq 1 ]; then
        log_warn "Prometheus targets: WARNINGS detected"
    else
        log_error "Prometheus targets: CRITICAL issues detected"
    fi

    return $exit_code
}

# Generate summary report
generate_report() {
    log_info "Generating summary report..."

    local report_file="$RESULTS_DIR/validation-report-$TIMESTAMP.txt"

    {
        echo "======================================================================"
        echo "Exporter Validation Report"
        echo "======================================================================"
        echo "Timestamp: $(date)"
        echo "Prometheus: $PROMETHEUS_URL"
        echo ""
        echo "Results:"
        echo "----------------------------------------------------------------------"

        # Parse all JSON results
        for json_file in "$RESULTS_DIR"/*-"$TIMESTAMP".json; do
            if [ -f "$json_file" ]; then
                echo ""
                echo "File: $(basename "$json_file")"

                # Extract summary using jq if available
                if command -v jq >/dev/null 2>&1; then
                    jq -r '.summary | "  Total: \(.total_endpoints)\n  Passed: \(.passed)\n  Warnings: \(.warnings)\n  Failed: \(.failed)"' "$json_file"
                else
                    echo "  (Install jq for detailed summary)"
                fi
            fi
        done

        echo ""
        echo "======================================================================"
        echo "Report saved to: $report_file"
        echo "======================================================================"

    } | tee "$report_file"

    log_info "Report generated: $report_file"
}

# Send alerts if critical issues detected
send_alerts() {
    local overall_status=$1

    if [ $overall_status -eq 2 ]; then
        log_error "Critical issues detected - sending alerts..."

        # Example: Send to webhook (customize as needed)
        if [ -n "${ALERT_WEBHOOK_URL:-}" ]; then
            curl -X POST "$ALERT_WEBHOOK_URL" \
                -H "Content-Type: application/json" \
                -d '{
                    "severity": "critical",
                    "message": "Exporter validation detected critical issues",
                    "timestamp": "'$(date -Iseconds)'"
                }' || log_warn "Failed to send alert"
        fi

        # Example: Send email (requires mailx)
        if [ -n "${ALERT_EMAIL:-}" ] && command -v mailx >/dev/null 2>&1; then
            echo "Exporter validation detected critical issues. Check $RESULTS_DIR for details." | \
                mailx -s "ALERT: Exporter Validation Failed" "$ALERT_EMAIL" || \
                log_warn "Failed to send email alert"
        fi
    fi
}

# Cleanup old results
cleanup_old_results() {
    log_info "Cleaning up old results (keeping last 10)..."

    # Keep only last 10 validation runs
    find "$RESULTS_DIR" -name "*.json" -type f | \
        sort -r | \
        tail -n +11 | \
        xargs -r rm -f

    find "$RESULTS_DIR" -name "*.txt" -type f | \
        sort -r | \
        tail -n +11 | \
        xargs -r rm -f
}

# Main execution
main() {
    log_info "Starting comprehensive exporter validation..."

    check_prerequisites

    local overall_status=0

    # Run validations
    if ! validate_local_exporters; then
        [ $? -eq 2 ] && overall_status=2 || [ $overall_status -eq 0 ] && overall_status=1
    fi

    if ! validate_specific_exporters; then
        [ $? -eq 2 ] && overall_status=2 || [ $overall_status -eq 0 ] && overall_status=1
    fi

    if ! validate_prometheus_targets; then
        [ $? -eq 2 ] && overall_status=2 || [ $overall_status -eq 0 ] && overall_status=1
    fi

    # Generate report
    generate_report

    # Send alerts if needed
    send_alerts $overall_status

    # Cleanup
    cleanup_old_results

    # Final status
    echo ""
    if [ $overall_status -eq 0 ]; then
        log_info "All validations PASSED ✓"
    elif [ $overall_status -eq 1 ]; then
        log_warn "Validations completed with WARNINGS ⚠"
    else
        log_error "Validations FAILED - critical issues detected ✗"
    fi

    exit $overall_status
}

# Run main function
main "$@"
