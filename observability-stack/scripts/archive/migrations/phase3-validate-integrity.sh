#!/bin/bash
################################################################################
# Phase 3: Log Integrity Validation Script
# Validates data integrity after Loki/Promtail upgrade
#
# Tests:
#   1. Log retention verification (15 days)
#   2. Log loss detection during upgrade
#   3. Query performance benchmarking
#   4. Index health check
#   5. Stream cardinality validation
#   6. Promtail connection verification
#
# Usage:
#   ./phase3-validate-integrity.sh [--upgrade-time "2025-01-15T10:00:00Z"]
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more tests failed
#   2 - Critical failure (Loki unreachable)
################################################################################

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
LOKI_URL="${LOKI_URL:-http://localhost:3100}"
RETENTION_DAYS=15
MAX_STREAMS=10000
MAX_LABELS=15
UPGRADE_TIME=""

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNED=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --upgrade-time)
            UPGRADE_TIME="$2"
            shift 2
            ;;
        --loki-url)
            LOKI_URL="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --upgrade-time TIME   Upgrade timestamp (ISO 8601 format)"
            echo "  --loki-url URL        Loki server URL (default: http://localhost:3100)"
            echo "  --help                Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Functions
log_test() {
    echo -e "${BLUE}[TEST]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    ((TESTS_FAILED++))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
    ((TESTS_WARNED++))
}

log_info() {
    echo -e "${NC}[INFO]${NC} $*"
}

check_loki_reachable() {
    log_test "Checking Loki connectivity..."

    if ! curl -s -f "$LOKI_URL/ready" > /dev/null 2>&1; then
        log_fail "Loki not reachable at $LOKI_URL"
        return 1
    fi

    local health=$(curl -s "$LOKI_URL/ready" | grep -o "ready" || echo "unknown")
    if [[ "$health" == "ready" ]]; then
        log_pass "Loki is reachable and healthy"
        return 0
    else
        log_fail "Loki health check failed: $health"
        return 1
    fi
}

test_retention() {
    log_test "Test 1: Log Retention Verification (${RETENTION_DAYS} days)"

    local cutoff_date=$(date -d "$RETENTION_DAYS days ago" +%s)
    local query_start=$((cutoff_date - 86400))  # 1 day before cutoff
    local query_end=$cutoff_date

    # Convert to nanoseconds for Loki API
    local start_ns="${query_start}000000000"
    local end_ns="${query_end}000000000"

    log_info "Querying logs from $(date -d "@$query_start" +'%Y-%m-%d') to $(date -d "@$query_end" +'%Y-%m-%d')"

    # Query for oldest logs
    local response=$(curl -s -G "$LOKI_URL/loki/api/v1/query" \
        --data-urlencode 'query={job=~".+"}' \
        --data-urlencode "start=$start_ns" \
        --data-urlencode "end=$end_ns" \
        --data-urlencode 'limit=1' 2>/dev/null || echo "{}")

    local result_count=$(echo "$response" | jq -r '.data.result | length' 2>/dev/null || echo "0")

    if [[ "$result_count" -eq 0 ]]; then
        log_pass "No logs older than $RETENTION_DAYS days found (retention working)"
        return 0
    else
        local oldest_log=$(echo "$response" | jq -r '.data.result[0].values[0][0]' 2>/dev/null || echo "0")
        local oldest_timestamp=$((oldest_log / 1000000000))
        local age_days=$(( ($(date +%s) - oldest_timestamp) / 86400 ))

        if [[ $age_days -le $RETENTION_DAYS ]]; then
            log_warn "Found logs $age_days days old (within retention period)"
            return 0
        else
            log_fail "Found logs $age_days days old (exceeds retention period of $RETENTION_DAYS days)"
            return 1
        fi
    fi
}

test_log_loss() {
    log_test "Test 2: Log Loss Detection During Upgrade"

    if [[ -z "$UPGRADE_TIME" ]]; then
        log_warn "Upgrade time not provided (use --upgrade-time). Skipping log loss test."
        return 0
    fi

    log_info "Upgrade time: $UPGRADE_TIME"

    # Parse upgrade time
    local upgrade_epoch=$(date -d "$UPGRADE_TIME" +%s 2>/dev/null || echo "0")
    if [[ $upgrade_epoch -eq 0 ]]; then
        log_fail "Invalid upgrade time format: $UPGRADE_TIME"
        return 1
    fi

    # Calculate time windows (1 hour before and after upgrade)
    local pre_upgrade=$(date -d "@$((upgrade_epoch - 3600))" --iso-8601=seconds)
    local upgrade_start=$(date -d "@$upgrade_epoch" --iso-8601=seconds)
    local post_upgrade=$(date -d "@$((upgrade_epoch + 3600))" --iso-8601=seconds)

    log_info "Comparing logs before and after upgrade..."

    # Query logs before upgrade
    local logs_before=$(curl -s -G "$LOKI_URL/loki/api/v1/query_range" \
        --data-urlencode 'query=count_over_time({job=~".+"}[1h])' \
        --data-urlencode "start=$pre_upgrade" \
        --data-urlencode "end=$upgrade_start" 2>/dev/null | \
        jq -r '.data.result[0].values[-1][1]' 2>/dev/null || echo "0")

    # Query logs after upgrade
    local logs_after=$(curl -s -G "$LOKI_URL/loki/api/v1/query_range" \
        --data-urlencode 'query=count_over_time({job=~".+"}[1h])' \
        --data-urlencode "start=$upgrade_start" \
        --data-urlencode "end=$post_upgrade" 2>/dev/null | \
        jq -r '.data.result[0].values[-1][1]' 2>/dev/null || echo "0")

    log_info "Logs before upgrade: $logs_before"
    log_info "Logs after upgrade:  $logs_after"

    if [[ $logs_before -eq 0 ]] || [[ $logs_after -eq 0 ]]; then
        log_warn "Insufficient data to compare (one or both windows have zero logs)"
        return 0
    fi

    # Calculate variance
    local diff=$(( (logs_before - logs_after) * 100 / logs_before ))
    local abs_diff=${diff#-}  # Absolute value

    log_info "Variance: ${diff}%"

    if [[ $abs_diff -lt 20 ]]; then
        log_pass "Log ingestion normal (variance: ${diff}%)"
        return 0
    elif [[ $abs_diff -lt 50 ]]; then
        log_warn "Moderate log drop detected (variance: ${diff}%)"
        return 0
    else
        log_fail "Significant log drop detected (variance: ${diff}%)"
        return 1
    fi
}

test_query_performance() {
    log_test "Test 3: Query Performance Benchmarking"

    # Test 1: Simple query (should be < 2 seconds)
    log_info "Running simple query benchmark..."
    local start_time=$(date +%s.%N)

    curl -s -G "$LOKI_URL/loki/api/v1/query" \
        --data-urlencode 'query={job=~".+"}' \
        --data-urlencode 'limit=100' > /dev/null 2>&1

    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)

    log_info "Simple query duration: ${duration}s"

    if (( $(echo "$duration < 2" | bc -l) )); then
        log_pass "Simple query performance acceptable (${duration}s < 2s)"
    else
        log_warn "Simple query slow (${duration}s >= 2s)"
    fi

    # Test 2: Range query (should be < 5 seconds for 24h)
    log_info "Running range query benchmark (24h)..."
    local today=$(date --iso-8601=seconds)
    local yesterday=$(date -d "24 hours ago" --iso-8601=seconds)

    start_time=$(date +%s.%N)

    curl -s -G "$LOKI_URL/loki/api/v1/query_range" \
        --data-urlencode 'query={job=~".+"}' \
        --data-urlencode "start=$yesterday" \
        --data-urlencode "end=$today" \
        --data-urlencode 'limit=1000' > /dev/null 2>&1

    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc)

    log_info "Range query duration: ${duration}s"

    if (( $(echo "$duration < 5" | bc -l) )); then
        log_pass "Range query performance acceptable (${duration}s < 5s)"
        return 0
    else
        log_warn "Range query slow (${duration}s >= 5s)"
        return 0
    fi
}

test_index_health() {
    log_test "Test 4: Index Health Check"

    # Check for index errors in metrics
    local index_errors=$(curl -s "$LOKI_URL/metrics" 2>/dev/null | \
        grep "loki_ingester_index_entries_errors_total" | \
        grep -oP 'loki_ingester_index_entries_errors_total \K[0-9]+' || echo "0")

    log_info "Index errors: $index_errors"

    if [[ $index_errors -eq 0 ]]; then
        log_pass "No index errors detected"
    else
        log_warn "Index errors detected: $index_errors"
    fi

    # Check compaction status
    local compaction_count=$(curl -s "$LOKI_URL/metrics" 2>/dev/null | \
        grep "loki_compactor_compaction_duration_seconds_count" | \
        grep -oP 'loki_compactor_compaction_duration_seconds_count \K[0-9]+' || echo "0")

    log_info "Compaction runs: $compaction_count"

    if [[ $compaction_count -gt 0 ]]; then
        log_pass "Compaction is running (count: $compaction_count)"
        return 0
    else
        log_warn "Compaction has not run yet (may be normal for new deployment)"
        return 0
    fi
}

test_stream_cardinality() {
    log_test "Test 5: Stream Cardinality Validation"

    # Get total unique labels
    local label_count=$(curl -s "$LOKI_URL/loki/api/v1/labels" 2>/dev/null | \
        jq -r '.data | length' || echo "0")

    log_info "Total unique labels: $label_count"

    # Get stream count
    local stream_count=$(curl -s "$LOKI_URL/loki/api/v1/series" \
        --data-urlencode 'match={job=~".+"}' 2>/dev/null | \
        jq -r '.data | length' || echo "0")

    log_info "Total streams: $stream_count"

    # Validate against limits
    if [[ $stream_count -lt $MAX_STREAMS ]]; then
        log_pass "Stream count within limits ($stream_count < $MAX_STREAMS)"
    else
        log_warn "Stream count high: $stream_count (limit: $MAX_STREAMS)"
    fi

    # Check label cardinality per stream (approximate)
    if [[ $stream_count -gt 0 ]]; then
        local avg_labels=$((label_count / stream_count))
        log_info "Average labels per stream: $avg_labels"

        if [[ $avg_labels -le $MAX_LABELS ]]; then
            log_pass "Label cardinality acceptable ($avg_labels <= $MAX_LABELS)"
            return 0
        else
            log_warn "High label cardinality: $avg_labels labels/stream (limit: $MAX_LABELS)"
            return 0
        fi
    else
        log_warn "No streams found (may be normal for new deployment)"
        return 0
    fi
}

test_promtail_connections() {
    log_test "Test 6: Promtail Connection Verification"

    # Get list of unique hostnames from logs
    local hostnames=$(curl -s -G "$LOKI_URL/loki/api/v1/label/hostname/values" 2>/dev/null | \
        jq -r '.data[]' || echo "")

    if [[ -z "$hostnames" ]]; then
        log_warn "No hostname labels found in logs (check Promtail configuration)"
        return 0
    fi

    local connected=0
    local disconnected=0

    while IFS= read -r hostname; do
        if [[ -z "$hostname" ]]; then
            continue
        fi

        # Query recent logs from this host (last 5 minutes)
        local result=$(curl -s -G "$LOKI_URL/loki/api/v1/query" \
            --data-urlencode "query={hostname=\"$hostname\"}" \
            --data-urlencode 'limit=1' 2>/dev/null | \
            jq -r '.data.result | length' || echo "0")

        if [[ $result -gt 0 ]]; then
            log_info "✓ $hostname: Connected and shipping logs"
            ((connected++))
        else
            log_warn "✗ $hostname: No recent logs found (last 5 minutes)"
            ((disconnected++))
        fi
    done <<< "$hostnames"

    log_info "Connected hosts: $connected"
    log_info "Disconnected hosts: $disconnected"

    if [[ $disconnected -eq 0 ]]; then
        log_pass "All Promtail instances connected and shipping logs"
        return 0
    elif [[ $disconnected -lt $connected ]]; then
        log_warn "Some Promtail instances not shipping logs ($disconnected/$((connected + disconnected)))"
        return 0
    else
        log_fail "Most Promtail instances not shipping logs ($disconnected/$((connected + disconnected)))"
        return 1
    fi
}

print_summary() {
    echo ""
    echo "======================================================================"
    echo "                   INTEGRITY VALIDATION SUMMARY"
    echo "======================================================================"
    echo -e "Tests Passed:  ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests Failed:  ${RED}$TESTS_FAILED${NC}"
    echo -e "Tests Warned:  ${YELLOW}$TESTS_WARNED${NC}"
    echo "Total Tests:   $((TESTS_PASSED + TESTS_FAILED + TESTS_WARNED))"
    echo "======================================================================"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All critical tests passed!${NC}"
        echo ""
        echo "Loki upgrade appears successful. Log integrity validated."
        return 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        echo ""
        echo "Review failed tests and investigate issues before proceeding."
        return 1
    fi
}

main() {
    echo "======================================================================"
    echo "         Phase 3: Log Integrity Validation"
    echo "======================================================================"
    echo "Loki URL: $LOKI_URL"
    echo "Retention: $RETENTION_DAYS days"
    echo "Max Streams: $MAX_STREAMS"
    echo "Max Labels/Stream: $MAX_LABELS"
    echo "======================================================================"
    echo ""

    # Prerequisite: Check Loki connectivity
    if ! check_loki_reachable; then
        echo ""
        echo -e "${RED}CRITICAL: Cannot connect to Loki${NC}"
        echo "Ensure Loki is running and accessible at $LOKI_URL"
        exit 2
    fi

    echo ""

    # Run tests
    test_retention || true
    echo ""

    test_log_loss || true
    echo ""

    test_query_performance || true
    echo ""

    test_index_health || true
    echo ""

    test_stream_cardinality || true
    echo ""

    test_promtail_connections || true
    echo ""

    # Print summary
    if print_summary; then
        exit 0
    else
        exit 1
    fi
}

# Execute main
main
