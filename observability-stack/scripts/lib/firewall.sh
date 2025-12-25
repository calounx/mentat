#!/bin/bash
#===============================================================================
# Firewall Management Library
# Abstract firewall operations across ufw, firewalld, and iptables
#===============================================================================

[[ -n "${FIREWALL_SH_LOADED:-}" ]] && return 0
FIREWALL_SH_LOADED=1

_FIREWALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${COMMON_SH_LOADED:-}" ]] && source "$_FIREWALL_DIR/common.sh"
[[ -z "${ERRORS_SH_LOADED:-}" ]] && source "$_FIREWALL_DIR/errors.sh"
[[ -z "${VALIDATION_SH_LOADED:-}" ]] && source "$_FIREWALL_DIR/validation.sh"

# Detect firewall backend
# Usage: firewall_detect
firewall_detect() {
    if command -v ufw &>/dev/null && systemctl is-active --quiet ufw 2>/dev/null; then
        echo "ufw"
    elif command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        echo "firewalld"
    elif command -v iptables &>/dev/null; then
        echo "iptables"
    else
        echo "none"
    fi
}

# Allow incoming port
# Usage: firewall_allow_port "port" [protocol] [source_ip]
firewall_allow_port() {
    local port="$1"
    local protocol="${2:-tcp}"
    local source="${3:-any}"
    
    validate_port "$port" || return 1
    
    local backend
    backend=$(firewall_detect)
    
    log_info "Allowing port $port/$protocol from $source (backend: $backend)"
    
    case "$backend" in
        ufw)
            if [[ "$source" == "any" ]]; then
                ufw allow "$port/$protocol"
            else
                ufw allow from "$source" to any port "$port" proto "$protocol"
            fi
            ;;
        firewalld)
            if [[ "$source" == "any" ]]; then
                firewall-cmd --permanent --add-port="$port/$protocol"
            else
                firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=$source port port=$port protocol=$protocol accept"
            fi
            firewall-cmd --reload
            ;;
        iptables)
            if [[ "$source" == "any" ]]; then
                iptables -A INPUT -p "$protocol" --dport "$port" -j ACCEPT
            else
                iptables -A INPUT -p "$protocol" -s "$source" --dport "$port" -j ACCEPT
            fi
            service iptables save 2>/dev/null || true
            ;;
        *)
            error_report "No firewall backend detected" "$E_DEPENDENCY_MISSING"
            return 1
            ;;
    esac
    
    log_success "Firewall rule added: $port/$protocol from $source"
}

# Block incoming port
# Usage: firewall_block_port "port" [protocol]
firewall_block_port() {
    local port="$1"
    local protocol="${2:-tcp}"
    
    validate_port "$port" || return 1
    
    local backend
    backend=$(firewall_detect)
    
    log_info "Blocking port $port/$protocol (backend: $backend)"
    
    case "$backend" in
        ufw)
            ufw deny "$port/$protocol"
            ;;
        firewalld)
            firewall-cmd --permanent --remove-port="$port/$protocol" 2>/dev/null || true
            firewall-cmd --reload
            ;;
        iptables)
            iptables -A INPUT -p "$protocol" --dport "$port" -j DROP
            service iptables save 2>/dev/null || true
            ;;
        *)
            error_report "No firewall backend detected" "$E_DEPENDENCY_MISSING"
            return 1
            ;;
    esac
    
    log_success "Firewall rule removed: $port/$protocol"
}

# Test if port is accessible from source
# Usage: firewall_test_port "host" "port" [timeout]
firewall_test_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"
    
    if timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
        log_success "Port $host:$port is accessible"
        return 0
    else
        log_error "Port $host:$port is not accessible"
        return 1
    fi
}

# List firewall rules
# Usage: firewall_list
firewall_list() {
    local backend
    backend=$(firewall_detect)
    
    echo "Firewall rules (backend: $backend):"
    
    case "$backend" in
        ufw)
            ufw status numbered
            ;;
        firewalld)
            firewall-cmd --list-all
            ;;
        iptables)
            iptables -L -n -v
            ;;
        *)
            echo "No firewall backend detected"
            return 1
            ;;
    esac
}

# Validate firewall rule before applying
# Usage: firewall_validate_rule "port" [protocol] [source]
firewall_validate_rule() {
    local port="$1"
    local protocol="${2:-tcp}"
    local source="${3:-any}"
    
    validate_port "$port" || return 1
    
    if [[ "$source" != "any" ]]; then
        validate_ip "$source" || return 1
    fi
    
    validate_in_list "$protocol" "tcp" "udp" || return 1
    
    return 0
}

