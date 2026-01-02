#!/bin/bash
#
# CI/CD Pipeline Integration Script for Exporter Validation
#
# Usage in CI/CD:
#   - Run after deploying new exporters
#   - Run as part of health checks
#   - Run before promoting to production
#
# Exit codes:
#   0 - All validations passed
#   1 - Warnings detected (may fail in strict mode)
#   2 - Critical failures detected
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$(dirname "$SCRIPT_DIR")"
VALIDATOR="$TOOLS_DIR/validate-exporters.py"

# CI/CD Configuration (override with environment variables)
STRICT_MODE="${STRICT_MODE:-true}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
MAX_CARDINALITY="${MAX_CARDINALITY:-1000}"
STALENESS_THRESHOLD="${STALENESS_THRESHOLD:-300}"
TIMEOUT="${TIMEOUT:-10}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-./validation-artifacts}"

# Colors (disable in CI)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Logging functions
log_step() {
    echo -e "${BLUE}==>${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*"
}

# Initialize artifacts directory
init_artifacts() {
    log_step "Initializing artifacts directory..."
    mkdir -p "$ARTIFACTS_DIR"
    echo "Validation run at $(date)" > "$ARTIFACTS_DIR/validation.log"
}

# Validate environment
validate_environment() {
    log_step "Validating environment..."

    # Check validator exists
    if [ ! -x "$VALIDATOR" ]; then
        log_error "Validator not found: $VALIDATOR"
        return 2
    fi

    # Check Python and dependencies
    if ! python3 -c "import requests" 2>/dev/null; then
        log_error "Python requests library not installed"
        log_step "Install with: pip install -r $TOOLS_DIR/requirements.txt"
        return 2
    fi

    # Check Prometheus connectivity
    if ! curl -sf "$PROMETHEUS_URL/-/healthy" > /dev/null 2>&1; then
        log_warning "Prometheus not reachable at $PROMETHEUS_URL"
        log_step "Some checks may be skipped"
    else
        log_success "Prometheus reachable"
    fi

    log_success "Environment validation passed"
    return 0
}

# Validate critical exporters
validate_critical_exporters() {
    log_step "Validating critical exporters..."

    local endpoints=(
        "http://localhost:9100/metrics:node_exporter"
        "http://localhost:9090/metrics:prometheus"
    )

    local failed=0
    local warnings=0

    for entry in "${endpoints[@]}"; do
        IFS=':' read -r endpoint name <<< "$entry"

        log_step "Validating $name..."

        local output_file="$ARTIFACTS_DIR/${name}-validation.json"
        local args=(
            "--endpoint" "$endpoint"
            "--max-cardinality" "$MAX_CARDINALITY"
            "--staleness-threshold" "$STALENESS_THRESHOLD"
            "--timeout" "$TIMEOUT"
            "--json"
        )

        if [ "$STRICT_MODE" = "true" ]; then
            args+=("--exit-on-warning")
        fi

        if "$VALIDATOR" "${args[@]}" > "$output_file" 2>&1; then
            log_success "$name passed validation"

            # Extract and display summary
            if command -v jq >/dev/null 2>&1; then
                local total_metrics=$(jq -r '.results[0].total_metrics' "$output_file")
                echo "  Metrics: $total_metrics"
            fi
        else
            local exit_code=$?

            if [ $exit_code -eq 1 ]; then
                log_warning "$name has warnings"
                ((warnings++))

                # Display issues if jq available
                if command -v jq >/dev/null 2>&1; then
                    jq -r '.results[0].issues[] | "  - [\(.severity)] \(.message)"' "$output_file" | head -n 5
                fi
            else
                log_error "$name failed validation"
                ((failed++))

                # Display critical issues
                if command -v jq >/dev/null 2>&1; then
                    jq -r '.results[0].issues[] | select(.severity=="CRITICAL") | "  - \(.message)"' "$output_file"
                fi
            fi
        fi
    done

    # Determine overall result
    if [ $failed -gt 0 ]; then
        log_error "Critical exporter validation failed ($failed failures, $warnings warnings)"
        return 2
    elif [ $warnings -gt 0 ]; then
        log_warning "Exporter validation completed with warnings ($warnings warnings)"
        return 1
    else
        log_success "All critical exporters validated successfully"
        return 0
    fi
}

# Validate Prometheus targets
validate_prometheus_targets() {
    log_step "Validating Prometheus targets..."

    local output_file="$ARTIFACTS_DIR/prometheus-targets-validation.json"

    if ! curl -sf "$PROMETHEUS_URL/-/healthy" > /dev/null 2>&1; then
        log_warning "Skipping Prometheus target validation (not reachable)"
        return 0
    fi

    if "$VALIDATOR" \
        --prometheus "$PROMETHEUS_URL" \
        --timeout "$TIMEOUT" \
        --json > "$output_file" 2>&1; then
        log_success "Prometheus targets validated"
        return 0
    else
        local exit_code=$?

        if [ $exit_code -eq 1 ]; then
            log_warning "Prometheus target validation has warnings"
            return 1
        else
            log_error "Prometheus target validation failed"

            # Show down targets
            if command -v jq >/dev/null 2>&1; then
                log_step "Down targets:"
                jq -r '.results[0].issues[] | select(.category=="prometheus") | "  - \(.message)"' "$output_file"
            fi

            return 2
        fi
    fi
}

# Run automated tests
run_automated_tests() {
    log_step "Running automated tests..."

    local test_script="$SCRIPT_DIR/test-validator.py"

    if [ ! -f "$test_script" ]; then
        log_warning "Test script not found, skipping tests"
        return 0
    fi

    if python3 "$test_script" > "$ARTIFACTS_DIR/test-results.log" 2>&1; then
        log_success "All automated tests passed"
        return 0
    else
        log_error "Automated tests failed"
        log_step "See $ARTIFACTS_DIR/test-results.log for details"
        return 2
    fi
}

# Generate CI/CD report
generate_report() {
    local overall_status=$1

    log_step "Generating CI/CD report..."

    local report_file="$ARTIFACTS_DIR/validation-report.md"

    cat > "$report_file" <<EOF
# Exporter Validation Report

**Timestamp:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")
**Status:** $([ $overall_status -eq 0 ] && echo "✓ PASSED" || [ $overall_status -eq 1 ] && echo "⚠ WARNINGS" || echo "✗ FAILED")
**Strict Mode:** $STRICT_MODE

## Configuration

- Prometheus URL: \`$PROMETHEUS_URL\`
- Max Cardinality: $MAX_CARDINALITY
- Staleness Threshold: ${STALENESS_THRESHOLD}s
- Timeout: ${TIMEOUT}s

## Results

EOF

    # Add JSON summaries if jq available
    if command -v jq >/dev/null 2>&1; then
        for json_file in "$ARTIFACTS_DIR"/*-validation.json; do
            if [ -f "$json_file" ]; then
                local name=$(basename "$json_file" -validation.json)
                echo "### $name" >> "$report_file"
                echo "" >> "$report_file"

                local total=$(jq -r '.results[0].total_metrics // 0' "$json_file")
                local duration=$(jq -r '.results[0].duration_ms // 0' "$json_file")

                echo "- **Metrics:** $total" >> "$report_file"
                echo "- **Duration:** ${duration}ms" >> "$report_file"

                # Count issues by severity
                local critical=$(jq '[.results[0].issues[] | select(.severity=="CRITICAL")] | length' "$json_file")
                local warnings=$(jq '[.results[0].issues[] | select(.severity=="WARNING")] | length' "$json_file")

                if [ "$critical" -gt 0 ]; then
                    echo "- **Critical Issues:** $critical" >> "$report_file"
                fi
                if [ "$warnings" -gt 0 ]; then
                    echo "- **Warnings:** $warnings" >> "$report_file"
                fi

                echo "" >> "$report_file"
            fi
        done
    fi

    cat >> "$report_file" <<EOF

## Artifacts

All validation results are available in: \`$ARTIFACTS_DIR/\`

- Individual exporter validations: \`*-validation.json\`
- Test results: \`test-results.log\`
- This report: \`validation-report.md\`

## Next Steps

EOF

    if [ $overall_status -eq 0 ]; then
        echo "✓ All validations passed. Deployment can proceed." >> "$report_file"
    elif [ $overall_status -eq 1 ]; then
        echo "⚠ Warnings detected. Review issues before proceeding." >> "$report_file"
        echo "" >> "$report_file"
        echo "In strict mode, this would block deployment." >> "$report_file"
    else
        echo "✗ Critical issues detected. Do not proceed with deployment." >> "$report_file"
        echo "" >> "$report_file"
        echo "Address all critical issues and re-run validation." >> "$report_file"
    fi

    log_success "Report generated: $report_file"

    # Display report summary
    if [ -t 1 ]; then
        echo ""
        cat "$report_file"
    fi
}

# Cleanup on exit
cleanup() {
    local exit_code=$?

    # Archive artifacts if in CI
    if [ -n "${CI:-}" ]; then
        log_step "Archiving validation artifacts..."
        tar -czf "validation-artifacts-$(date +%Y%m%d-%H%M%S).tar.gz" "$ARTIFACTS_DIR"
    fi

    exit $exit_code
}

trap cleanup EXIT

# Main execution
main() {
    echo "======================================================================"
    echo "Exporter Validation for CI/CD"
    echo "======================================================================"
    echo ""

    init_artifacts

    local overall_status=0

    # Run validations
    if ! validate_environment; then
        overall_status=2
    fi

    if [ $overall_status -eq 0 ]; then
        if ! validate_critical_exporters; then
            local result=$?
            [ $result -gt $overall_status ] && overall_status=$result
        fi
    fi

    if [ $overall_status -lt 2 ]; then
        if ! validate_prometheus_targets; then
            local result=$?
            [ $result -gt $overall_status ] && overall_status=$result
        fi
    fi

    # Run tests (don't fail on test failures in non-strict mode)
    if [ $overall_status -lt 2 ] || [ "$STRICT_MODE" = "true" ]; then
        if ! run_automated_tests; then
            [ "$STRICT_MODE" = "true" ] && overall_status=2
        fi
    fi

    # Generate report
    generate_report $overall_status

    # Final output
    echo ""
    echo "======================================================================"
    if [ $overall_status -eq 0 ]; then
        log_success "Validation PASSED - Ready for deployment"
    elif [ $overall_status -eq 1 ]; then
        log_warning "Validation completed with WARNINGS"
        [ "$STRICT_MODE" = "true" ] && log_error "Strict mode: Blocking deployment"
    else
        log_error "Validation FAILED - Do not deploy"
    fi
    echo "======================================================================"

    # In strict mode, warnings are failures
    if [ "$STRICT_MODE" = "true" ] && [ $overall_status -eq 1 ]; then
        overall_status=2
    fi

    exit $overall_status
}

# Run main
main "$@"
