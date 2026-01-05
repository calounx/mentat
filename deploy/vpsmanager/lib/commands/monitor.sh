#!/usr/bin/env bash
# Monitoring commands for vpsmanager

# Check if a service is running
service_status() {
    local service="$1"

    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo "running"
        return 0
    else
        echo "stopped"
        return 1
    fi
}

# Get service memory usage
service_memory() {
    local service="$1"
    local pid

    pid=$(systemctl show --property MainPID --value "$service" 2>/dev/null)

    if [[ -n "$pid" && "$pid" != "0" ]]; then
        # Get RSS in KB and convert to MB
        local rss_kb
        rss_kb=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
        if [[ -n "$rss_kb" ]]; then
            echo "$((rss_kb / 1024))"
            return 0
        fi
    fi

    echo "0"
    return 1
}

# ============================================================================
# Command handlers
# ============================================================================

# monitor:health command
cmd_monitor_health() {
    log_info "Running health check"

    local issues=()
    local services_json="{"
    local first=true

    # Check nginx
    local nginx_status
    nginx_status=$(service_status "nginx")
    if [[ "$nginx_status" != "running" ]]; then
        issues+=("nginx is not running")
    fi
    services_json+="\"nginx\":{\"status\":\"${nginx_status}\",\"memory_mb\":$(service_memory nginx)}"
    first=false

    # Check PHP-FPM
    local php_version="${PHP_VERSION:-8.2}"
    local php_service="php${php_version}-fpm"
    local php_status
    php_status=$(service_status "$php_service")
    if [[ "$php_status" != "running" ]]; then
        issues+=("${php_service} is not running")
    fi
    services_json+=",\"php_fpm\":{\"status\":\"${php_status}\",\"memory_mb\":$(service_memory "$php_service")}"

    # Check MariaDB
    local mariadb_status
    mariadb_status=$(service_status "mariadb")
    if [[ "$mariadb_status" != "running" ]]; then
        mariadb_status=$(service_status "mysql")
    fi
    if [[ "$mariadb_status" != "running" ]]; then
        issues+=("MariaDB/MySQL is not running")
    fi
    services_json+=",\"mariadb\":{\"status\":\"${mariadb_status}\",\"memory_mb\":$(service_memory mariadb)}"

    services_json+="}"

    # Check disk space
    local disk_usage disk_total disk_used disk_available disk_percent
    disk_usage=$(df -B1 /var/www 2>/dev/null | tail -1)
    disk_total=$(echo "$disk_usage" | awk '{print $2}')
    disk_used=$(echo "$disk_usage" | awk '{print $3}')
    disk_available=$(echo "$disk_usage" | awk '{print $4}')
    disk_percent=$(echo "$disk_usage" | awk '{print $5}' | tr -d '%')

    if [[ "$disk_percent" -gt 90 ]]; then
        issues+=("Disk usage is above 90%: ${disk_percent}%")
    fi

    local disk_json
    disk_json=$(json_object \
        "total_bytes" "${disk_total:-0}" \
        "used_bytes" "${disk_used:-0}" \
        "available_bytes" "${disk_available:-0}" \
        "percent_used" "${disk_percent:-0}")

    # Check memory
    local mem_total mem_used mem_available mem_percent
    mem_total=$(free -b | awk '/^Mem:/{print $2}')
    mem_used=$(free -b | awk '/^Mem:/{print $3}')
    mem_available=$(free -b | awk '/^Mem:/{print $7}')
    mem_percent=$((mem_used * 100 / mem_total))

    if [[ "$mem_percent" -gt 90 ]]; then
        issues+=("Memory usage is above 90%: ${mem_percent}%")
    fi

    local memory_json
    memory_json=$(json_object \
        "total_bytes" "${mem_total:-0}" \
        "used_bytes" "${mem_used:-0}" \
        "available_bytes" "${mem_available:-0}" \
        "percent_used" "${mem_percent:-0}")

    # Check load average
    local load_1 load_5 load_15
    read -r load_1 load_5 load_15 _ < /proc/loadavg
    local cpu_count
    cpu_count=$(nproc)

    # Convert to integer for comparison (multiply by 100)
    local load_1_int
    load_1_int=$(echo "$load_1 * 100" | bc 2>/dev/null || echo "0")
    local threshold=$((cpu_count * 100))

    if [[ "${load_1_int%.*}" -gt "$threshold" ]]; then
        issues+=("Load average is high: ${load_1}")
    fi

    local load_json
    load_json=$(json_object \
        "load_1m" "$load_1" \
        "load_5m" "$load_5" \
        "load_15m" "$load_15" \
        "cpu_count" "$cpu_count")

    # Determine overall health
    local healthy="true"
    local issues_json="[]"
    if [[ ${#issues[@]} -gt 0 ]]; then
        healthy="false"
        issues_json=$(json_array "${issues[@]}")
    fi

    # Build response
    local response_data
    response_data=$(json_object \
        "healthy" "$healthy" \
        "timestamp" "$(date -Iseconds)" \
        "services" "$services_json" \
        "disk" "$disk_json" \
        "memory" "$memory_json" \
        "load" "$load_json" \
        "issues" "$issues_json")

    if [[ "$healthy" == "true" ]]; then
        json_success "System is healthy" "$response_data"
    else
        json_success "System has issues" "$response_data"
    fi

    return 0
}

# monitor:stats command
cmd_monitor_stats() {
    log_info "Gathering system stats"

    # Uptime
    local uptime_seconds
    uptime_seconds=$(cat /proc/uptime | cut -d' ' -f1 | cut -d'.' -f1)

    # CPU usage (1 second sample)
    local cpu_idle cpu_usage
    cpu_idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | cut -d'%' -f1)
    cpu_usage=$(echo "100 - ${cpu_idle:-0}" | bc 2>/dev/null || echo "0")

    # Network stats
    local net_rx_bytes net_tx_bytes
    net_rx_bytes=$(cat /sys/class/net/eth0/statistics/rx_bytes 2>/dev/null || echo "0")
    net_tx_bytes=$(cat /sys/class/net/eth0/statistics/tx_bytes 2>/dev/null || echo "0")

    # Count sites
    local sites_count=0
    if command -v jq &> /dev/null && [[ -f "$SITES_REGISTRY" ]]; then
        sites_count=$(jq '.sites | length' "$SITES_REGISTRY" 2>/dev/null || echo "0")
    fi

    # Disk I/O
    local disk_reads disk_writes
    disk_reads=$(cat /sys/block/sda/stat 2>/dev/null | awk '{print $1}' || echo "0")
    disk_writes=$(cat /sys/block/sda/stat 2>/dev/null | awk '{print $5}' || echo "0")

    # Process count
    local process_count
    process_count=$(ps aux | wc -l)

    # Build response
    local response_data
    response_data=$(json_object \
        "timestamp" "$(date -Iseconds)" \
        "uptime_seconds" "$uptime_seconds" \
        "cpu_usage_percent" "$cpu_usage" \
        "sites_count" "$sites_count" \
        "process_count" "$process_count" \
        "network" "$(json_object "rx_bytes" "$net_rx_bytes" "tx_bytes" "$net_tx_bytes")" \
        "disk_io" "$(json_object "reads" "$disk_reads" "writes" "$disk_writes")")

    json_success "Stats retrieved" "$response_data"
    return 0
}
