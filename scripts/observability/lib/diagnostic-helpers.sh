#!/bin/bash
#===============================================================================
# Diagnostic Helper Library
#===============================================================================
# Common diagnostic functions used by troubleshooting scripts
#===============================================================================

#===============================================================================
# Color Functions
#===============================================================================

declare -A COLORS=(
    [RED]='\033[0;31m'
    [GREEN]='\033[0;32m'
    [YELLOW]='\033[1;33m'
    [BLUE]='\033[0;34m'
    [CYAN]='\033[0;36m'
    [GRAY]='\033[0;37m'
    [NC]='\033[0m'  # No Color
)

colorize() {
    local color="$1"
    local text="$2"
    echo -e "${COLORS[$color]}${text}${COLORS[NC]}"
}

#===============================================================================
# Service Diagnostics
#===============================================================================

check_service_status() {
    local service="$1"
    local host="${2:-localhost}"

    if [[ "$host" == "localhost" ]]; then
        systemctl is-active "$service" 2>/dev/null || echo "inactive"
    else
        ssh "${host}" "systemctl is-active ${service}" 2>/dev/null || echo "inactive"
    fi
}

check_service_enabled() {
    local service="$1"
    local host="${2:-localhost}"

    if [[ "$host" == "localhost" ]]; then
        systemctl is-enabled "$service" 2>/dev/null
    else
        ssh "${host}" "systemctl is-enabled ${service}" 2>/dev/null
    fi
}

check_auto_start() {
    local service="$1"
    local host="${2:-localhost}"

    local enabled=$(check_service_enabled "$service" "$host")
    [[ "$enabled" == "enabled" ]]
}

check_crash_logs() {
    local service="$1"
    local host="${2:-localhost}"

    local log_cmd="journalctl -u ${service} -n 50 --no-pager -o short"

    if [[ "$host" == "localhost" ]]; then
        local logs=$($log_cmd 2>/dev/null)
    else
        local logs=$(ssh "${host}" "$log_cmd" 2>/dev/null)
    fi

    # Look for common crash indicators
    if echo "$logs" | grep -qi "segmentation fault\|core dumped\|killed\|oom\|panic"; then
        echo "$logs" | grep -i "segmentation fault\|core dumped\|killed\|oom\|panic" | tail -1
        return 0
    fi

    # Check for exits with non-zero status
    if echo "$logs" | grep -q "Main process exited.*code=exited.*status=[^0]"; then
        echo "$logs" | grep "Main process exited.*code=exited.*status=[^0]" | tail -1
        return 0
    fi

    return 1
}

check_resource_usage() {
    local service="$1"
    local host="${2:-localhost}"

    # Get PID
    local pid_cmd="systemctl show ${service} -p MainPID --value"

    if [[ "$host" == "localhost" ]]; then
        local pid=$($pid_cmd 2>/dev/null)
    else
        local pid=$(ssh "${host}" "$pid_cmd" 2>/dev/null)
    fi

    if [[ -z "$pid" ]] || [[ "$pid" == "0" ]]; then
        return 1
    fi

    # Get resource usage
    local ps_cmd="ps -p ${pid} -o %cpu,%mem,rss --no-headers"

    if [[ "$host" == "localhost" ]]; then
        local usage=$($ps_cmd 2>/dev/null)
    else
        local usage=$(ssh "${host}" "$ps_cmd" 2>/dev/null)
    fi

    if [[ -z "$usage" ]]; then
        return 1
    fi

    read -r cpu mem rss <<< "$usage"

    # Check thresholds
    local issues=""

    if (( $(echo "$cpu > 80" | bc -l 2>/dev/null || echo 0) )); then
        issues+="High CPU: ${cpu}% "
    fi

    if (( $(echo "$mem > 80" | bc -l 2>/dev/null || echo 0) )); then
        issues+="High Memory: ${mem}% "
    fi

    if [[ -n "$issues" ]]; then
        echo "$issues"
        return 0
    fi

    return 1
}

#===============================================================================
# Binary and File Checks
#===============================================================================

check_binary_exists() {
    local binary="$1"
    local host="${2:-localhost}"

    if [[ "$host" == "localhost" ]]; then
        [[ -f "$binary" ]] || command -v "$(basename "$binary")" &>/dev/null
    else
        ssh "${host}" "[[ -f ${binary} ]] || command -v $(basename "$binary") &>/dev/null"
    fi
}

check_file_readable() {
    local file="$1"
    local user="${2:-prometheus}"
    local host="${3:-localhost}"

    if [[ "$host" == "localhost" ]]; then
        sudo -u "$user" test -r "$file" 2>/dev/null
    else
        ssh "${host}" "sudo -u ${user} test -r ${file}" 2>/dev/null
    fi
}

check_directory_accessible() {
    local dir="$1"
    local user="${2:-prometheus}"
    local host="${3:-localhost}"

    if [[ "$host" == "localhost" ]]; then
        sudo -u "$user" test -x "$dir" 2>/dev/null
    else
        ssh "${host}" "sudo -u ${user} test -x ${dir}" 2>/dev/null
    fi
}

#===============================================================================
# Network Diagnostics
#===============================================================================

check_port_listening() {
    local port="$1"
    local host="${2:-localhost}"

    if [[ "$host" == "localhost" ]]; then
        netstat -tuln 2>/dev/null | grep -q ":${port} " || \
        ss -tuln 2>/dev/null | grep -q ":${port} "
    else
        ssh "${host}" "netstat -tuln 2>/dev/null | grep -q ':${port} ' || ss -tuln 2>/dev/null | grep -q ':${port} '"
    fi
}

check_port_accessible() {
    local port="$1"
    local host="${2:-localhost}"

    # Try to connect to the port
    timeout 2 bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" 2>/dev/null
}

check_metrics_endpoint() {
    local host="$1"
    local port="$2"
    local path="${3:-/metrics}"

    local url="http://${host}:${port}${path}"

    local response=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null)

    [[ "$response" == "200" ]]
}

check_bind_address() {
    local port="$1"
    local host="${2:-localhost}"

    # Check if bound to 0.0.0.0 or specific IP
    local bind_cmd="netstat -tuln 2>/dev/null | grep ':${port} ' | awk '{print \$4}' || ss -tuln 2>/dev/null | grep ':${port} ' | awk '{print \$5}'"

    if [[ "$host" == "localhost" ]]; then
        local bind_addr=$(eval "$bind_cmd")
    else
        local bind_addr=$(ssh "${host}" "$bind_cmd")
    fi

    if echo "$bind_addr" | grep -q "127.0.0.1"; then
        echo "localhost"
        return 1
    elif echo "$bind_addr" | grep -q "0.0.0.0\|\[::\]"; then
        echo "all"
        return 0
    else
        echo "$bind_addr"
        return 2
    fi
}

check_firewall_port() {
    local port="$1"
    local host="${2:-localhost}"

    # Check firewalld
    if command -v firewall-cmd &>/dev/null; then
        if [[ "$host" == "localhost" ]]; then
            firewall-cmd --list-ports 2>/dev/null | grep -q "${port}/tcp"
        else
            ssh "${host}" "firewall-cmd --list-ports 2>/dev/null | grep -q '${port}/tcp'"
        fi
        return $?
    fi

    # Check UFW
    if command -v ufw &>/dev/null; then
        if [[ "$host" == "localhost" ]]; then
            ufw status 2>/dev/null | grep -q "${port}/tcp.*ALLOW"
        else
            ssh "${host}" "ufw status 2>/dev/null | grep -q '${port}/tcp.*ALLOW'"
        fi
        return $?
    fi

    # Check iptables
    if command -v iptables &>/dev/null; then
        if [[ "$host" == "localhost" ]]; then
            iptables -L INPUT -n 2>/dev/null | grep -q "dpt:${port}"
        else
            ssh "${host}" "iptables -L INPUT -n 2>/dev/null | grep -q 'dpt:${port}'"
        fi
        return $?
    fi

    # No firewall detected
    return 0
}

check_dns_resolution() {
    local hostname="$1"

    if host "$hostname" &>/dev/null || nslookup "$hostname" &>/dev/null || dig "$hostname" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

#===============================================================================
# Permission Diagnostics
#===============================================================================

check_permissions() {
    local exporter="$1"
    local service="$2"
    local host="${3:-localhost}"

    local issues=""

    # Get service user
    local user_cmd="systemctl show ${service} -p User --value"

    if [[ "$host" == "localhost" ]]; then
        local user=$($user_cmd 2>/dev/null)
    else
        local user=$(ssh "${host}" "$user_cmd" 2>/dev/null)
    fi

    if [[ -z "$user" ]] || [[ "$user" == "root" ]]; then
        user="prometheus"  # Default assumption
    fi

    # Check specific permissions based on exporter type
    case "$exporter" in
        node_exporter)
            # Node exporter needs access to /proc, /sys
            if ! check_directory_accessible "/proc" "$user" "$host"; then
                issues+="/proc not accessible "
            fi
            if ! check_directory_accessible "/sys" "$user" "$host"; then
                issues+="/sys not accessible "
            fi
            ;;

        mysqld_exporter|mysql_exporter)
            # MySQL exporter needs access to .my.cnf or credentials
            local cnf_files=("/etc/.mysqld_exporter.cnf" "/etc/.mysql_exporter.cnf" "${HOME}/.my.cnf")
            local found=false
            for cnf in "${cnf_files[@]}"; do
                if check_file_readable "$cnf" "$user" "$host"; then
                    found=true
                    break
                fi
            done
            if [[ "$found" == "false" ]]; then
                issues+="MySQL credentials file not readable "
            fi
            ;;

        nginx_exporter)
            # Nginx exporter needs access to stub_status
            if ! curl -s http://localhost/nginx_status &>/dev/null; then
                issues+="Nginx stub_status not accessible "
            fi
            ;;

        phpfpm_exporter)
            # PHP-FPM exporter needs access to status page
            if ! check_file_readable "/var/run/php-fpm/www.sock" "$user" "$host" 2>/dev/null; then
                # Check if using TCP instead
                if ! check_port_listening 9000 "$host"; then
                    issues+="PHP-FPM status not accessible "
                fi
            fi
            ;;
    esac

    # Check SELinux
    if command -v getenforce &>/dev/null; then
        local selinux_status=$(getenforce 2>/dev/null)
        if [[ "$selinux_status" == "Enforcing" ]]; then
            # Check for denials
            local denials=$(ausearch -m avc -c "$service" 2>/dev/null | tail -5)
            if [[ -n "$denials" ]]; then
                issues+="SELinux denials detected "
            fi
        fi
    fi

    # Check AppArmor
    if command -v aa-status &>/dev/null; then
        local aa_profiles=$(aa-status 2>/dev/null | grep -i "$service")
        if [[ -n "$aa_profiles" ]]; then
            issues+="AppArmor profile active "
        fi
    fi

    echo "$issues"
}

#===============================================================================
# Configuration Diagnostics
#===============================================================================

check_prometheus_target() {
    local exporter="$1"
    local host="$2"
    local port="$3"

    # Find Prometheus configuration
    local prom_configs=(
        "/etc/prometheus/prometheus.yml"
        "/home/calounx/repositories/mentat/docker/observability/prometheus/prometheus.yml"
        "/home/calounx/repositories/mentat/chom/docker/prometheus/prometheus.yml"
    )

    for config in "${prom_configs[@]}"; do
        if [[ -f "$config" ]]; then
            # Check if this exporter is configured
            if grep -q "${host}:${port}" "$config"; then
                return 0
            fi
        fi
    done

    return 1
}

get_prometheus_config_path() {
    local prom_configs=(
        "/etc/prometheus/prometheus.yml"
        "/home/calounx/repositories/mentat/docker/observability/prometheus/prometheus.yml"
        "/home/calounx/repositories/mentat/chom/docker/prometheus/prometheus.yml"
    )

    for config in "${prom_configs[@]}"; do
        if [[ -f "$config" ]]; then
            echo "$config"
            return 0
        fi
    done

    return 1
}

check_exporter_flags() {
    local service="$1"
    local host="${2:-localhost}"

    # Get service ExecStart
    local exec_cmd="systemctl cat ${service} 2>/dev/null | grep '^ExecStart=' | cut -d'=' -f2-"

    if [[ "$host" == "localhost" ]]; then
        local exec_start=$(eval "$exec_cmd")
    else
        local exec_start=$(ssh "${host}" "$exec_cmd")
    fi

    echo "$exec_start"
}

#===============================================================================
# Remediation Functions
#===============================================================================

run_command() {
    local cmd="$1"
    local host="${2:-localhost}"

    if [[ "$host" == "localhost" ]]; then
        eval "$cmd"
    else
        ssh "${host}" "$cmd"
    fi
}

firewall_allow_port() {
    local port="$1"

    # Try firewalld
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port="${port}/tcp"
        firewall-cmd --reload
        return $?
    fi

    # Try UFW
    if command -v ufw &>/dev/null; then
        ufw allow "${port}/tcp"
        return $?
    fi

    # Try iptables
    if command -v iptables &>/dev/null; then
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
        # Try to persist
        if command -v iptables-save &>/dev/null; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || \
            iptables-save > /etc/sysconfig/iptables 2>/dev/null
        fi
        return $?
    fi

    return 1
}

add_prometheus_target() {
    local exporter="$1"
    local host="$2"
    local port="$3"

    local config=$(get_prometheus_config_path)
    if [[ -z "$config" ]]; then
        echo "ERROR: Prometheus config not found"
        return 1
    fi

    # Backup config
    cp "$config" "${config}.bak.$(date +%s)"

    # Determine job name based on exporter
    local job_name="${exporter/_/-}"

    # Check if job already exists
    if grep -q "job_name.*${job_name}" "$config"; then
        # Add target to existing job
        # This is complex - for now, log it
        echo "WARN: Job ${job_name} already exists, manual intervention required"
        return 1
    else
        # Add new job
        cat >> "$config" <<EOF

  # ========================================================================
  # ${exporter} - Auto-added by troubleshooter
  # ========================================================================
  - job_name: '${job_name}'
    static_configs:
      - targets: ['${host}:${port}']
        labels:
          service: '${exporter}'
          tier: 'application'
EOF

        # Reload Prometheus
        if systemctl is-active prometheus &>/dev/null; then
            systemctl reload prometheus
        elif curl -X POST http://localhost:9090/-/reload &>/dev/null; then
            # Reload via API
            :
        fi

        return 0
    fi
}

fix_bind_address() {
    local exporter="$1"

    # Find systemd service file
    local service_file="/etc/systemd/system/${exporter}.service"

    if [[ ! -f "$service_file" ]]; then
        service_file="/lib/systemd/system/${exporter}.service"
    fi

    if [[ ! -f "$service_file" ]]; then
        echo "ERROR: Service file not found for ${exporter}"
        return 1
    fi

    # Backup service file
    cp "$service_file" "${service_file}.bak.$(date +%s)"

    # Update bind address from 127.0.0.1 to 0.0.0.0
    sed -i 's/--web.listen-address=127.0.0.1:/--web.listen-address=0.0.0.0:/g' "$service_file"
    sed -i 's/--web.listen-address=localhost:/--web.listen-address=0.0.0.0:/g' "$service_file"

    # Reload systemd
    systemctl daemon-reload

    # Restart service
    systemctl restart "${exporter}"

    return 0
}

fix_permissions() {
    local exporter="$1"

    # Get service user
    local service="${exporter}"
    local user=$(systemctl show "${service}" -p User --value 2>/dev/null)

    if [[ -z "$user" ]] || [[ "$user" == "root" ]]; then
        user="prometheus"
    fi

    case "$exporter" in
        mysqld_exporter|mysql_exporter)
            # Fix MySQL credentials file permissions
            local cnf="/etc/.mysqld_exporter.cnf"
            if [[ -f "$cnf" ]]; then
                chown "${user}:${user}" "$cnf"
                chmod 600 "$cnf"
            fi
            ;;

        node_exporter)
            # Ensure user can access /proc, /sys
            # Usually this is fine, but check for AppArmor/SELinux
            if command -v aa-complain &>/dev/null; then
                aa-complain /usr/local/bin/node_exporter 2>/dev/null
            fi
            ;;

        nginx_exporter)
            # Ensure nginx stub_status is accessible
            # This usually requires nginx config changes
            echo "WARN: Manual nginx configuration required for stub_status"
            return 1
            ;;
    esac

    return 0
}

install_exporter() {
    local exporter="$1"

    echo "INFO: Installing ${exporter}"

    # This is a placeholder - actual installation would be complex
    # For now, just log what would be done

    case "$exporter" in
        node_exporter)
            echo "Would download and install node_exporter from GitHub releases"
            ;;
        nginx_exporter)
            echo "Would download and install nginx_exporter from GitHub releases"
            ;;
        mysqld_exporter|mysql_exporter)
            echo "Would download and install mysqld_exporter from GitHub releases"
            ;;
        *)
            echo "Would download and install ${exporter} from GitHub releases"
            ;;
    esac

    echo "WARN: Auto-installation not yet implemented"
    return 1
}

#===============================================================================
# Utility Functions
#===============================================================================

get_exporter_version() {
    local binary="$1"

    if [[ ! -f "$binary" ]]; then
        echo "not installed"
        return 1
    fi

    # Try to get version
    local version=$("$binary" --version 2>&1 | head -1 | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
    echo "$version"
}

check_connectivity() {
    local host="$1"

    ping -c 1 -W 1 "$host" &>/dev/null
}

test_ssh_connection() {
    local host="$1"

    ssh -o ConnectTimeout=5 -o BatchMode=yes "${host}" "echo ok" &>/dev/null
}

#===============================================================================
# Export Functions
#===============================================================================

# Export all functions for use by other scripts
export -f colorize
export -f check_service_status check_service_enabled check_auto_start
export -f check_crash_logs check_resource_usage
export -f check_binary_exists check_file_readable check_directory_accessible
export -f check_port_listening check_port_accessible check_metrics_endpoint
export -f check_bind_address check_firewall_port check_dns_resolution
export -f check_permissions
export -f check_prometheus_target get_prometheus_config_path check_exporter_flags
export -f run_command firewall_allow_port add_prometheus_target
export -f fix_bind_address fix_permissions install_exporter
export -f get_exporter_version check_connectivity test_ssh_connection
