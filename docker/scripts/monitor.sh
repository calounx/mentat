#!/usr/bin/env bash
# ============================================================================
# Monitor Script - Real-time Service Monitoring
# ============================================================================
# This script shows real-time stats for all services
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Function to show container stats
show_stats() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}CHOM Docker Environment - Live Monitor${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    # Get container stats
    echo -e "${CYAN}Container Resource Usage:${NC}"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" \
        chom_web chom_observability 2>/dev/null || echo "Containers not running"

    echo ""
    echo -e "${CYAN}Container Status:${NC}"
    docker ps --filter "name=chom_" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "No containers found"

    echo ""
    echo -e "${CYAN}Volume Usage:${NC}"
    docker system df -v | grep -E "VOLUME NAME|chom_" | head -10

    echo ""
    echo -e "${GREEN}Press Ctrl+C to exit${NC}"
    echo ""
}

# Show stats once or continuously
if [ "${1:-}" = "--once" ]; then
    show_stats
else
    while true; do
        show_stats
        sleep 5
    done
fi
