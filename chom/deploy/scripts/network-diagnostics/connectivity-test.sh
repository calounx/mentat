#!/bin/bash

##############################################################################
# Observability Integration - Connectivity Test Suite
# Tests network connectivity between mentat and landsraad VPS servers
#
# Usage: ./connectivity-test.sh [--target IP|HOSTNAME] [--verbose] [--quiet]
#
# Parameters:
#   --target     Remote server IP or hostname (default: auto-detect based on local server)
#   --verbose    Enable verbose output
#   --quiet      Minimal output
##############################################################################

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
MENTAT_IP="51.254.139.78"
MENTAT_HOSTNAME="mentat.arewel.com"
LANDSRAAD_IP="51.77.150.96"
LANDSRAAD_HOSTNAME="landsraad.arewel.com"

# Default values
TARGET_IP=""
VERBOSE=false
QUIET=false

# Test results tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

##############################################################################
# Helper Functions
##############################################################################

log_info() {
    if [ "$QUIET" = false ]; then
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
}

log_success() {
    if [ "$QUIET" = false ]; then
        echo -e "${GREEN}[PASS]${NC} $1"
    fi
}

log_error() {
    if [ "$QUIET" = false ]; then
        echo -e "${RED}[FAIL]${NC} $1"
    fi
}

log_warn() {
    if [ "$QUIET" = false ]; then
        echo -e "${YELLOW}[WARN]${NC} $1"
    fi
}

log_section() {
    if [ "$QUIET" = false ]; then
        echo ""
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}$1${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    fi
}

verbose_output() {
    if [ "$VERBOSE" = true ]; then
        echo "$1"
    fi
}

record_test() {
    local test_name="$1"
    local result="$2"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$result" = "PASS" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        log_success "$test_name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        log_error "$test_name"
    fi
}

get_local_hostname() {
    hostname -f 2>/dev/null || hostname
}

detect_remote_target() {
    local local_hostname=$(get_local_hostname)

    # Detect which server we're on and set target accordingly
    if [[ "$local_hostname" == *"mentat"* ]]; then
        echo "$LANDSRAAD_IP"
    else
        echo "$MENTAT_IP"
    fi
}

##############################################################################
# Connectivity Tests
##############################################################################

test_ping() {
    log_section "LAYER 3 CONNECTIVITY - PING TEST"

    log_info "Testing ICMP connectivity to $TARGET_IP..."

    if ping -c 3 -W 5 "$TARGET_IP" >/dev/null 2>&1; then
        record_test "Ping to $TARGET_IP" "PASS"

        # Get latency details
        local ping_output=$(ping -c 3 -W 5 "$TARGET_IP" 2>&1)
        verbose_output "$ping_output"
    else
        record_test "Ping to $TARGET_IP" "FAIL"
    fi
}

test_dns_resolution() {
    log_section "DNS RESOLUTION CHAIN"

    # Test DNS forward resolution
    log_info "Testing forward DNS resolution..."

    if [ "$TARGET_IP" = "$MENTAT_IP" ]; then
        test_hostname="$MENTAT_HOSTNAME"
    else
        test_hostname="$LANDSRAAD_HOSTNAME"
    fi

    log_info "Resolving $test_hostname..."
    if resolved_ip=$(nslookup "$test_hostname" 2>&1 | grep -A1 "Name:" | tail -1 | awk '{print $NF}'); then
        verbose_output "Resolved to: $resolved_ip"

        if [ "$resolved_ip" = "$TARGET_IP" ]; then
            record_test "DNS forward resolution for $test_hostname" "PASS"
        else
            record_test "DNS forward resolution for $test_hostname (resolved to $resolved_ip, expected $TARGET_IP)" "FAIL"
        fi
    else
        record_test "DNS forward resolution for $test_hostname" "FAIL"
    fi

    # Test reverse DNS
    log_info "Testing reverse DNS resolution..."
    if reverse_hostname=$(nslookup "$TARGET_IP" 2>&1 | grep -i "name =" | awk '{print $NF}' | sed 's/\.$//' | head -1); then
        verbose_output "Reverse resolved to: $reverse_hostname"
        record_test "DNS reverse resolution for $TARGET_IP" "PASS"
    else
        record_test "DNS reverse resolution for $TARGET_IP" "FAIL"
    fi
}

test_http_https() {
    log_section "HTTP/HTTPS CONNECTIVITY"

    # Test HTTP
    log_info "Testing HTTP connectivity (port 80)..."
    if timeout 5 bash -c "echo > /dev/tcp/$TARGET_IP/80" 2>/dev/null; then
        record_test "HTTP port 80 open on $TARGET_IP" "PASS"
    else
        record_test "HTTP port 80 open on $TARGET_IP" "FAIL"
    fi

    # Test HTTPS
    log_info "Testing HTTPS connectivity (port 443)..."
    if timeout 5 bash -c "echo > /dev/tcp/$TARGET_IP/443" 2>/dev/null; then
        record_test "HTTPS port 443 open on $TARGET_IP" "PASS"
    else
        record_test "HTTPS port 443 open on $TARGET_IP" "FAIL"
    fi

    # Test with curl if available
    if command -v curl &> /dev/null; then
        log_info "Testing HTTPS certificate with curl..."

        # Get certificate info
        if cert_info=$(echo | openssl s_client -servername "$test_hostname" -connect "$TARGET_IP:443" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null); then
            record_test "SSL/TLS certificate valid on $TARGET_IP" "PASS"
            verbose_output "$cert_info"
        else
            record_test "SSL/TLS certificate check on $TARGET_IP" "FAIL"
        fi
    fi
}

test_observability_ports() {
    log_section "OBSERVABILITY PORTS TEST"

    # Critical ports for observability
    declare -A ports=(
        ["Prometheus:9090"]="9090"
        ["Prometheus Remote Write:9009"]="9009"
        ["Node Exporter:9100"]="9100"
        ["Loki:3100"]="3100"
        ["Grafana:3000"]="3000"
    )

    for port_name in "${!ports[@]}"; do
        port="${ports[$port_name]}"
        log_info "Testing $port_name connectivity..."

        if timeout 5 bash -c "echo > /dev/tcp/$TARGET_IP/$port" 2>/dev/null; then
            record_test "$port_name ($TARGET_IP:$port)" "PASS"
        else
            record_test "$port_name ($TARGET_IP:$port)" "FAIL"
        fi
    done
}

test_application_ports() {
    log_section "APPLICATION PORTS TEST"

    # CHOM application ports
    declare -A app_ports=(
        ["HTTP:80"]="80"
        ["HTTPS:443"]="443"
        ["PHP-FPM:9000"]="9000"
    )

    for port_name in "${!app_ports[@]}"; do
        port="${app_ports[$port_name]}"
        log_info "Testing $port_name on application server..."

        if timeout 5 bash -c "echo > /dev/tcp/$TARGET_IP/$port" 2>/dev/null; then
            record_test "Application port $port_name ($TARGET_IP:$port)" "PASS"
        else
            record_test "Application port $port_name ($TARGET_IP:$port)" "FAIL"
        fi
    done
}

test_latency() {
    log_section "NETWORK LATENCY ANALYSIS"

    log_info "Running latency tests to $TARGET_IP..."

    if command -v ping &> /dev/null; then
        local latency_output=$(ping -c 10 -W 5 "$TARGET_IP" 2>&1)
        verbose_output "$latency_output"

        # Extract statistics
        if echo "$latency_output" | grep -q "min/avg/max"; then
            local stats=$(echo "$latency_output" | grep "min/avg/max" | awk '{print $4}')
            log_info "Ping statistics: $stats ms"
            record_test "Network latency measurement" "PASS"
        fi
    fi

    # MTU test
    log_info "Testing MTU (Maximum Transmission Unit)..."
    if command -v ping &> /dev/null; then
        # Try different packet sizes to find optimal MTU
        local mtu_test=$(ping -c 1 -M do -s 1472 "$TARGET_IP" 2>&1)
        if echo "$mtu_test" | grep -q "bytes from"; then
            record_test "MTU 1500 supported" "PASS"
        else
            log_warn "May have MTU issues - attempting smaller packet size"
        fi
    fi
}

test_bandwidth() {
    log_section "BANDWIDTH ESTIMATION"

    log_info "Running bandwidth estimation tests..."

    # Using simple HTTP transfer as bandwidth test
    if command -v curl &> /dev/null; then
        log_info "Testing download speed from http://$TARGET_IP/"

        # Create a test file locally if we can
        local test_file="/tmp/bandwidth-test-$RANDOM.bin"

        # Try to estimate bandwidth using curl
        if timeout 10 curl -o "$test_file" -w "Downloaded: %{size_download} bytes in %{time_total}s (Speed: %{speed_download} B/s)\n" -s "http://$TARGET_IP/" 2>/dev/null; then
            record_test "Bandwidth measurement attempt" "PASS"
            rm -f "$test_file" 2>/dev/null
        else
            log_info "Could not measure bandwidth (connection may be restricted)"
        fi
    fi
}

test_iperf3_if_available() {
    log_section "THROUGHPUT TEST (iperf3) - OPTIONAL"

    if command -v iperf3 &> /dev/null; then
        log_info "iperf3 found - would need server listening on remote end"
        log_info "To enable: Install iperf3 on remote server and run: iperf3 -s"
        log_info "Then run: iperf3 -c $TARGET_IP -t 10"
    else
        log_info "iperf3 not installed - install with: apt-get install iperf3"
    fi
}

test_traceroute() {
    log_section "ROUTE ANALYSIS - TRACEROUTE"

    if command -v traceroute &> /dev/null; then
        log_info "Tracing route to $TARGET_IP..."
        local route=$(traceroute -m 15 -w 2 "$TARGET_IP" 2>&1 | head -20)
        verbose_output "$route"
        record_test "Route tracing to $TARGET_IP" "PASS"
    else
        log_info "traceroute not installed - install with: apt-get install traceroute"
    fi
}

##############################################################################
# Performance Tests
##############################################################################

test_prometheus_scrape() {
    log_section "PROMETHEUS SCRAPE TEST"

    if [ "$TARGET_IP" = "$MENTAT_IP" ]; then
        log_info "Testing Prometheus API endpoint on mentat..."

        # Test if Prometheus is responding
        if curl -s "http://$TARGET_IP:9090/-/healthy" | grep -q "Prometheus"; then
            record_test "Prometheus health check" "PASS"
        else
            log_info "Prometheus health endpoint returned: $(curl -s "http://$TARGET_IP:9090/-/healthy")"
            record_test "Prometheus health check" "FAIL"
        fi

        # Test targets endpoint
        if curl -s "http://$TARGET_IP:9090/api/v1/targets" | grep -q "activeTargets"; then
            record_test "Prometheus targets endpoint" "PASS"
        else
            record_test "Prometheus targets endpoint" "FAIL"
        fi
    fi
}

test_loki_health() {
    log_section "LOKI HEALTH CHECK"

    if [ "$TARGET_IP" = "$MENTAT_IP" ]; then
        log_info "Testing Loki API endpoint on mentat..."

        if curl -s "http://$TARGET_IP:3100/ready" | grep -q "ready"; then
            record_test "Loki ready endpoint" "PASS"
        else
            record_test "Loki ready endpoint" "FAIL"
        fi

        # Test build info
        if curl -s "http://$TARGET_IP:3100/loki/api/v1/status/buildinfo" | grep -q "version"; then
            record_test "Loki build info endpoint" "PASS"
        else
            record_test "Loki build info endpoint" "FAIL"
        fi
    fi
}

##############################################################################
# Network Configuration Report
##############################################################################

generate_report() {
    log_section "CONNECTIVITY TEST SUMMARY"

    echo ""
    echo "Test Results:"
    echo "  Total Tests Run:    $TESTS_RUN"
    echo "  Tests Passed:       $TESTS_PASSED"
    echo "  Tests Failed:       $TESTS_FAILED"

    if [ $TESTS_FAILED -eq 0 ]; then
        echo ""
        echo -e "${GREEN}All connectivity tests passed!${NC}"
    else
        echo ""
        echo -e "${YELLOW}Some tests failed. Please review firewall rules and network configuration.${NC}"
    fi

    log_section "NETWORK CONFIGURATION DETAILS"

    echo ""
    echo "Local Server Information:"
    echo "  Hostname:      $(get_local_hostname)"
    echo "  IP Address:    $(hostname -I | awk '{print $1}')"
    echo ""

    echo "Remote Server Information:"
    echo "  Target IP:     $TARGET_IP"
    echo "  Target Host:   $test_hostname"
    echo ""

    echo "Network Interface Information:"
    ip addr show | grep -E "inet " | while read -r line; do
        echo "  $line"
    done
    echo ""

    echo "Routing Information:"
    ip route show | while read -r line; do
        echo "  $line"
    done
    echo ""

    echo "Firewall Status:"
    if command -v ufw &> /dev/null; then
        echo "  UFW Status: $(ufw status | head -1)"
    fi
    if command -v iptables &> /dev/null; then
        echo "  Iptables Rules Count: $(iptables -L -n | grep "Chain" | wc -l)"
    fi
    echo ""
}

##############################################################################
# Main Execution
##############################################################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --target)
                TARGET_IP="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --quiet)
                QUIET=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                echo "Usage: $0 [--target IP|HOSTNAME] [--verbose] [--quiet]"
                exit 1
                ;;
        esac
    done

    # Auto-detect target if not specified
    if [ -z "$TARGET_IP" ]; then
        TARGET_IP=$(detect_remote_target)
    fi

    log_section "OBSERVABILITY INTEGRATION - CONNECTIVITY TEST SUITE"
    echo "Starting comprehensive network connectivity tests..."
    echo "Test Start Time: $(date)"
    echo ""

    # Run all tests
    test_ping
    test_dns_resolution
    test_http_https
    test_observability_ports
    test_application_ports
    test_latency
    test_bandwidth
    test_iperf3_if_available
    test_traceroute
    test_prometheus_scrape
    test_loki_health

    # Generate final report
    generate_report

    log_section "TEST EXECUTION COMPLETED"
    echo "Test End Time: $(date)"

    # Exit with appropriate code
    if [ $TESTS_FAILED -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Execute main function
main "$@"
