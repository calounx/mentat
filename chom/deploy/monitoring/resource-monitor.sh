#!/bin/bash

###############################################################################
# CHOM Resource Monitoring Tool
# Monitors server resources and alerts on threshold violations
###############################################################################

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration
DEPLOY_USER="stilgar"
APP_SERVER="landsraad.arewel.com"

# Thresholds
CPU_WARN_THRESHOLD=70
CPU_CRIT_THRESHOLD=90
MEM_WARN_THRESHOLD=75
MEM_CRIT_THRESHOLD=90
DISK_WARN_THRESHOLD=80
DISK_CRIT_THRESHOLD=90

# Colors based on status
get_status_color() {
    local value="$1"
    local warn_threshold="$2"
    local crit_threshold="$3"

    if (( $(awk "BEGIN {print ($value >= $crit_threshold)}") )); then
        echo "$RED"
    elif (( $(awk "BEGIN {print ($value >= $warn_threshold)}") )); then
        echo "$YELLOW"
    else
        echo "$GREEN"
    fi
}

create_bar() {
    local percent="$1"
    local width=50
    local filled=$(awk "BEGIN {printf \"%.0f\", ($percent / 100) * $width}")
    local empty=$((width - filled))

    local bar=""
    for ((i=0; i<filled; i++)); do
        bar="${bar}█"
    done
    for ((i=0; i<empty; i++)); do
        bar="${bar}░"
    done

    echo "$bar"
}

monitor_cpu() {
    echo -e "${BOLD}${BLUE}━━━ CPU Usage ━━━${NC}"

    # Get CPU info
    local cpu_count=$(ssh "$DEPLOY_USER@$APP_SERVER" "nproc" 2>/dev/null || echo "1")
    local cpu_model=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep 'model name' /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs" 2>/dev/null || echo "Unknown")

    echo -e "  CPU Model: ${cpu_model}"
    echo -e "  CPU Cores: ${cpu_count}"
    echo ""

    # Overall CPU usage
    local cpu_usage=$(ssh "$DEPLOY_USER@$APP_SERVER" "top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'%' -f1" 2>/dev/null || echo "0")
    local cpu_color=$(get_status_color "$cpu_usage" "$CPU_WARN_THRESHOLD" "$CPU_CRIT_THRESHOLD")
    local cpu_bar=$(create_bar "$cpu_usage")

    echo -e "  Overall: ${cpu_color}${cpu_bar}${NC} ${cpu_usage}%"

    if (( $(awk "BEGIN {print ($cpu_usage >= $CPU_CRIT_THRESHOLD)}") )); then
        echo -e "  ${RED}⚠ CRITICAL: CPU usage is very high!${NC}"
    elif (( $(awk "BEGIN {print ($cpu_usage >= $CPU_WARN_THRESHOLD)}") )); then
        echo -e "  ${YELLOW}⚠ WARNING: CPU usage is high${NC}"
    fi

    echo ""

    # Per-core usage (if mpstat available)
    if ssh "$DEPLOY_USER@$APP_SERVER" "command -v mpstat &>/dev/null"; then
        echo -e "  Per-Core Usage:"
        ssh "$DEPLOY_USER@$APP_SERVER" "mpstat -P ALL 1 1 2>/dev/null | grep -v 'Average' | tail -n +4" | while read -r line; do
            local cpu=$(echo "$line" | awk '{print $2}')
            local usage=$(echo "$line" | awk '{print 100-$NF}')
            local core_bar=$(create_bar "$usage")
            local core_color=$(get_status_color "$usage" "$CPU_WARN_THRESHOLD" "$CPU_CRIT_THRESHOLD")

            printf "    CPU%-2s ${core_color}%-52s${NC} %.1f%%\n" "$cpu" "$core_bar" "$usage"
        done
        echo ""
    fi

    # Top CPU processes
    echo -e "  Top CPU Processes:"
    ssh "$DEPLOY_USER@$APP_SERVER" "ps aux --sort=-%cpu | head -6 | tail -5" | while read -r line; do
        local user=$(echo "$line" | awk '{print $1}')
        local pid=$(echo "$line" | awk '{print $2}')
        local cpu=$(echo "$line" | awk '{print $3}')
        local cmd=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf $i" "}' | cut -c1-40)

        printf "    %-10s PID:%-6s CPU:${BOLD}%5s%%${NC} %s\n" "$user" "$pid" "$cpu" "$cmd"
    done

    echo ""
}

monitor_memory() {
    echo -e "${BOLD}${BLUE}━━━ Memory Usage ━━━${NC}"

    # Get memory info
    local mem_info=$(ssh "$DEPLOY_USER@$APP_SERVER" "free -h" 2>/dev/null || echo "")

    if [[ -z "$mem_info" ]]; then
        echo -e "  ${RED}Cannot retrieve memory information${NC}"
        return
    fi

    # Parse memory info
    local mem_total=$(echo "$mem_info" | grep Mem: | awk '{print $2}')
    local mem_used=$(echo "$mem_info" | grep Mem: | awk '{print $3}')
    local mem_free=$(echo "$mem_info" | grep Mem: | awk '{print $4}')
    local mem_available=$(echo "$mem_info" | grep Mem: | awk '{print $7}')

    # Calculate percentage
    local mem_total_kb=$(ssh "$DEPLOY_USER@$APP_SERVER" "free | grep Mem: | awk '{print \$2}'" 2>/dev/null || echo "1")
    local mem_used_kb=$(ssh "$DEPLOY_USER@$APP_SERVER" "free | grep Mem: | awk '{print \$3}'" 2>/dev/null || echo "0")
    local mem_percent=$(awk "BEGIN {printf \"%.1f\", ($mem_used_kb / $mem_total_kb) * 100}")

    local mem_color=$(get_status_color "$mem_percent" "$MEM_WARN_THRESHOLD" "$MEM_CRIT_THRESHOLD")
    local mem_bar=$(create_bar "$mem_percent")

    echo -e "  Total:     ${mem_total}"
    echo -e "  Used:      ${mem_used}"
    echo -e "  Free:      ${mem_free}"
    echo -e "  Available: ${mem_available}"
    echo ""
    echo -e "  Usage: ${mem_color}${mem_bar}${NC} ${mem_percent}%"

    if (( $(awk "BEGIN {print ($mem_percent >= $MEM_CRIT_THRESHOLD)}") )); then
        echo -e "  ${RED}⚠ CRITICAL: Memory usage is very high!${NC}"
    elif (( $(awk "BEGIN {print ($mem_percent >= $MEM_WARN_THRESHOLD)}") )); then
        echo -e "  ${YELLOW}⚠ WARNING: Memory usage is high${NC}"
    fi

    echo ""

    # Swap usage
    local swap_total=$(echo "$mem_info" | grep Swap: | awk '{print $2}')
    local swap_used=$(echo "$mem_info" | grep Swap: | awk '{print $3}')

    if [[ "$swap_total" != "0B" ]]; then
        echo -e "  Swap Total: ${swap_total}"
        echo -e "  Swap Used:  ${swap_used}"
        echo ""
    fi

    # Top memory processes
    echo -e "  Top Memory Processes:"
    ssh "$DEPLOY_USER@$APP_SERVER" "ps aux --sort=-%mem | head -6 | tail -5" | while read -r line; do
        local user=$(echo "$line" | awk '{print $1}')
        local pid=$(echo "$line" | awk '{print $2}')
        local mem=$(echo "$line" | awk '{print $4}')
        local vsz=$(echo "$line" | awk '{print $5}')
        local cmd=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf $i" "}' | cut -c1-35)

        printf "    %-10s PID:%-6s MEM:${BOLD}%5s%%${NC} VSZ:%-8s %s\n" "$user" "$pid" "$mem" "$vsz" "$cmd"
    done

    echo ""
}

monitor_disk() {
    echo -e "${BOLD}${BLUE}━━━ Disk Usage ━━━${NC}"

    # Get disk usage for all mount points
    ssh "$DEPLOY_USER@$APP_SERVER" "df -h --output=source,size,used,avail,pcent,target 2>/dev/null | grep -v 'tmpfs\|devtmpfs\|Filesystem'" | while read -r line; do
        local device=$(echo "$line" | awk '{print $1}')
        local size=$(echo "$line" | awk '{print $2}')
        local used=$(echo "$line" | awk '{print $3}')
        local avail=$(echo "$line" | awk '{print $4}')
        local percent=$(echo "$line" | awk '{print $5}' | sed 's/%//')
        local mount=$(echo "$line" | awk '{print $6}')

        local disk_color=$(get_status_color "$percent" "$DISK_WARN_THRESHOLD" "$DISK_CRIT_THRESHOLD")
        local disk_bar=$(create_bar "$percent")

        echo -e "  ${BOLD}$mount${NC} ($device)"
        echo -e "    Size: $size | Used: $used | Available: $avail"
        echo -e "    ${disk_color}${disk_bar}${NC} ${percent}%"

        if [[ "$percent" -ge "$DISK_CRIT_THRESHOLD" ]]; then
            echo -e "    ${RED}⚠ CRITICAL: Disk space very low!${NC}"
        elif [[ "$percent" -ge "$DISK_WARN_THRESHOLD" ]]; then
            echo -e "    ${YELLOW}⚠ WARNING: Disk space running low${NC}"
        fi

        echo ""
    done

    # Disk I/O if iostat available
    if ssh "$DEPLOY_USER@$APP_SERVER" "command -v iostat &>/dev/null"; then
        echo -e "  Disk I/O Statistics:"
        ssh "$DEPLOY_USER@$APP_SERVER" "iostat -x 1 2 | tail -n +7 | grep -v '^$' | tail -n +2" | while read -r line; do
            local device=$(echo "$line" | awk '{print $1}')
            local tps=$(echo "$line" | awk '{print $2}')
            local read_kb=$(echo "$line" | awk '{print $3}')
            local write_kb=$(echo "$line" | awk '{print $4}')

            printf "    %-10s TPS:%-8s Read:%-10s Write:%-10s\n" "$device" "$tps" "${read_kb}kB/s" "${write_kb}kB/s"
        done
        echo ""
    fi
}

monitor_network() {
    echo -e "${BOLD}${BLUE}━━━ Network Statistics ━━━${NC}"

    # Network interfaces
    local interfaces=$(ssh "$DEPLOY_USER@$APP_SERVER" "ip -o link show | awk -F': ' '{print \$2}' | grep -v lo" 2>/dev/null || echo "")

    for iface in $interfaces; do
        # Get RX/TX bytes
        local rx_bytes=$(ssh "$DEPLOY_USER@$APP_SERVER" "cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null" || echo "0")
        local tx_bytes=$(ssh "$DEPLOY_USER@$APP_SERVER" "cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null" || echo "0")

        local rx_mb=$(awk "BEGIN {printf \"%.2f\", $rx_bytes / 1024 / 1024}")
        local tx_mb=$(awk "BEGIN {printf \"%.2f\", $tx_bytes / 1024 / 1024}")

        # Get IP address
        local ip=$(ssh "$DEPLOY_USER@$APP_SERVER" "ip addr show $iface | grep 'inet ' | awk '{print \$2}' | cut -d'/' -f1" 2>/dev/null || echo "N/A")

        echo -e "  ${BOLD}$iface${NC} ($ip)"
        echo -e "    RX: ${rx_mb} MB"
        echo -e "    TX: ${tx_mb} MB"
        echo ""
    done

    # Connection count
    local tcp_connections=$(ssh "$DEPLOY_USER@$APP_SERVER" "ss -tan | grep -c ESTAB || echo '0'" 2>/dev/null || echo "0")
    echo -e "  Active TCP Connections: ${BOLD}$tcp_connections${NC}"

    echo ""
}

monitor_processes() {
    echo -e "${BOLD}${BLUE}━━━ Process Information ━━━${NC}"

    # Process count
    local total_processes=$(ssh "$DEPLOY_USER@$APP_SERVER" "ps aux | wc -l" 2>/dev/null || echo "0")
    local running_processes=$(ssh "$DEPLOY_USER@$APP_SERVER" "ps aux | grep -c ' R ' || echo '0'" 2>/dev/null || echo "0")

    echo -e "  Total Processes: ${BOLD}$total_processes${NC}"
    echo -e "  Running:         ${BOLD}$running_processes${NC}"
    echo ""

    # Load average
    local load_avg=$(ssh "$DEPLOY_USER@$APP_SERVER" "uptime | awk -F'load average:' '{print \$2}'" 2>/dev/null || echo "unknown")
    echo -e "  Load Average:    ${BOLD}$load_avg${NC}"
    echo ""

    # Open file descriptors
    local open_files=$(ssh "$DEPLOY_USER@$APP_SERVER" "lsof 2>/dev/null | wc -l || echo '0'" 2>/dev/null || echo "0")
    local max_files=$(ssh "$DEPLOY_USER@$APP_SERVER" "sysctl fs.file-max 2>/dev/null | awk '{print \$3}' || echo '0'" 2>/dev/null || echo "0")

    if [[ "$max_files" != "0" ]]; then
        local fd_percent=$(awk "BEGIN {printf \"%.1f\", ($open_files / $max_files) * 100}")
        echo -e "  Open File Descriptors: ${BOLD}$open_files${NC} / $max_files (${fd_percent}%)"
    else
        echo -e "  Open File Descriptors: ${BOLD}$open_files${NC}"
    fi

    echo ""
}

generate_alert_summary() {
    echo -e "${BOLD}${BLUE}━━━ Alert Summary ━━━${NC}"

    local alerts=()

    # Check CPU
    local cpu_usage=$(ssh "$DEPLOY_USER@$APP_SERVER" "top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'%' -f1" 2>/dev/null || echo "0")
    if (( $(awk "BEGIN {print ($cpu_usage >= $CPU_CRIT_THRESHOLD)}") )); then
        alerts+=("${RED}CRITICAL: CPU usage at ${cpu_usage}%${NC}")
    elif (( $(awk "BEGIN {print ($cpu_usage >= $CPU_WARN_THRESHOLD)}") )); then
        alerts+=("${YELLOW}WARNING: CPU usage at ${cpu_usage}%${NC}")
    fi

    # Check Memory
    local mem_total_kb=$(ssh "$DEPLOY_USER@$APP_SERVER" "free | grep Mem: | awk '{print \$2}'" 2>/dev/null || echo "1")
    local mem_used_kb=$(ssh "$DEPLOY_USER@$APP_SERVER" "free | grep Mem: | awk '{print \$3}'" 2>/dev/null || echo "0")
    local mem_percent=$(awk "BEGIN {printf \"%.1f\", ($mem_used_kb / $mem_total_kb) * 100}")

    if (( $(awk "BEGIN {print ($mem_percent >= $MEM_CRIT_THRESHOLD)}") )); then
        alerts+=("${RED}CRITICAL: Memory usage at ${mem_percent}%${NC}")
    elif (( $(awk "BEGIN {print ($mem_percent >= $MEM_WARN_THRESHOLD)}") )); then
        alerts+=("${YELLOW}WARNING: Memory usage at ${mem_percent}%${NC}")
    fi

    # Check Disk
    local max_disk_usage=0
    while IFS= read -r percent; do
        if [[ "$percent" -gt "$max_disk_usage" ]]; then
            max_disk_usage="$percent"
        fi
    done < <(ssh "$DEPLOY_USER@$APP_SERVER" "df --output=pcent 2>/dev/null | grep -v 'Use%' | sed 's/%//'" 2>/dev/null || echo "0")

    if [[ "$max_disk_usage" -ge "$DISK_CRIT_THRESHOLD" ]]; then
        alerts+=("${RED}CRITICAL: Disk usage at ${max_disk_usage}%${NC}")
    elif [[ "$max_disk_usage" -ge "$DISK_WARN_THRESHOLD" ]]; then
        alerts+=("${YELLOW}WARNING: Disk usage at ${max_disk_usage}%${NC}")
    fi

    # Display alerts
    if [[ ${#alerts[@]} -eq 0 ]]; then
        echo -e "  ${GREEN}✓ No alerts - all resources within normal limits${NC}"
    else
        for alert in "${alerts[@]}"; do
            echo -e "  $alert"
        done
    fi

    echo ""
}

###############################################################################
# MAIN EXECUTION
###############################################################################

main() {
    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║            CHOM Resource Monitor                              ║"
    echo "║            Server: $APP_SERVER"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    monitor_cpu
    monitor_memory
    monitor_disk
    monitor_network
    monitor_processes
    generate_alert_summary

    echo -e "${GREEN}Resource monitoring complete${NC}"
}

main "$@"
