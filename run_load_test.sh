#!/bin/bash

# CHOM API Load Testing Script
#
# This script runs load tests using Locust.
#
# Usage:
#   ./run_load_test.sh              # Start Locust web UI
#   ./run_load_test.sh --headless   # Run headless with default config
#   ./run_load_test.sh --users 50   # Custom user count

set -e

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default values
HEADLESS=false
USERS=${LOAD_TEST_USERS:-10}
SPAWN_RATE=${LOAD_TEST_SPAWN_RATE:-2}
DURATION=${LOAD_TEST_DURATION:-60}
HOST="${API_BASE_URL:-http://localhost:8000}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --headless)
            HEADLESS=true
            shift
            ;;
        --users)
            USERS=$2
            shift 2
            ;;
        --spawn-rate)
            SPAWN_RATE=$2
            shift 2
            ;;
        --duration)
            DURATION=$2
            shift 2
            ;;
        --host)
            HOST=$2
            shift 2
            ;;
        -h|--help)
            echo "CHOM API Load Testing Script"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --headless           Run without web UI"
            echo "  --users NUM          Number of simulated users (default: 10)"
            echo "  --spawn-rate NUM     Users spawned per second (default: 2)"
            echo "  --duration SEC       Test duration in seconds (default: 60)"
            echo "  --host URL           Target host (default: http://localhost:8000)"
            echo "  -h, --help           Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                          # Start web UI"
            echo "  $0 --headless               # Run with defaults"
            echo "  $0 --users 50 --duration 300  # 50 users for 5 minutes"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Print banner
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║                     CHOM API Load Testing                             ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo -e "${YELLOW}Virtual environment not found. Creating...${NC}"
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements-test.txt
else
    source venv/bin/activate
fi

# Check if locust is installed
if ! python -c "import locust" 2>/dev/null; then
    echo -e "${YELLOW}Installing locust...${NC}"
    pip install locust
fi

# Check API accessibility
echo -e "${BLUE}Checking API connectivity at $HOST/api/v1/health...${NC}"

if curl -s -f "$HOST/api/v1/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ API is accessible${NC}"
else
    echo -e "${YELLOW}⚠ Warning: API may not be accessible${NC}"
    echo -e "${YELLOW}  Make sure the API server is running at $HOST${NC}"
    echo ""
fi

# Print configuration
echo ""
echo -e "${GREEN}Load Test Configuration:${NC}"
echo "  Target Host: $HOST"
echo "  Users: $USERS"
echo "  Spawn Rate: $SPAWN_RATE/sec"
echo "  Duration: ${DURATION}s"
echo "  Mode: $([ "$HEADLESS" = true ] && echo "Headless" || echo "Web UI")"
echo ""

# Create reports directory
mkdir -p reports/load

if [ "$HEADLESS" = true ]; then
    # Run headless
    echo -e "${BLUE}Starting load test (headless mode)...${NC}"
    echo ""

    locust \
        -f tests/api/load/locustfile.py \
        --host="$HOST" \
        --users "$USERS" \
        --spawn-rate "$SPAWN_RATE" \
        --run-time "${DURATION}s" \
        --headless \
        --html reports/load/load_test_report.html \
        --csv reports/load/load_test

    echo ""
    echo -e "${GREEN}Load test complete!${NC}"
    echo -e "${BLUE}Reports generated:${NC}"
    echo "  HTML Report: reports/load/load_test_report.html"
    echo "  CSV Stats: reports/load/load_test_stats.csv"

else
    # Run with web UI
    echo -e "${BLUE}Starting Locust web UI...${NC}"
    echo ""
    echo -e "${GREEN}Web UI available at: http://localhost:8089${NC}"
    echo ""
    echo "Press Ctrl+C to stop"
    echo ""

    locust \
        -f tests/api/load/locustfile.py \
        --host="$HOST"
fi
