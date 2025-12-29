#!/bin/bash
#===============================================================================
# Monitored Host Agent Setup Script v2 (Module-Based)
# Installs exporters based on host configuration file
#
# Usage:
#   ./setup-monitored-host-v2.sh <OBSERVABILITY_VPS_IP> [OPTIONS]
#   ./setup-monitored-host-v2.sh --config /path/to/host.yaml [OPTIONS]
#   ./setup-monitored-host-v2.sh --uninstall [--purge]
#
# Options:
#   --force, -f     Force reinstall everything
#   --config        Use specific host config file
#   --uninstall     Remove all monitoring agents
#   --purge         Used with --uninstall to remove configs too
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/module-loader.sh"

# Mode flags
FORCE_MODE=false
UNINSTALL_MODE=false
PURGE_DATA=false
HOST_CONFIG=""
OBSERVABILITY_IP=""

# Promtail config (from host config or args)
LOKI_URL=""
LOKI_USER=""
LOKI_PASS=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force|-f)
            FORCE_MODE=true
            shift
            ;;
        --uninstall|--rollback)
            UNINSTALL_MODE=true
            shift
            ;;
        --purge)
            PURGE_DATA=true
            shift
            ;;
        --config=*)
            HOST_CONFIG="${1#*=}"
            shift
            ;;
        --config)
            HOST_CONFIG="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 <OBSERVABILITY_VPS_IP> [OPTIONS]"
            echo "       $0 --config /path/to/host.yaml [OPTIONS]"
            echo "       $0 --uninstall [--purge]"
            echo ""
            echo "Options:"
            echo "  --force, -f     Force reinstall everything"
            echo "  --config        Use specific host config file"
            echo "  --uninstall     Remove all monitoring agents"
            echo "  --purge         Remove configs too (with --uninstall)"
            exit 0
            ;;
        *)
            # First positional arg is OBSERVABILITY_IP
            if [[ -z "$OBSERVABILITY_IP" ]]; then
                OBSERVABILITY_IP="$1"
            elif [[ -z "$LOKI_URL" ]]; then
                LOKI_URL="$1"
            elif [[ -z "$LOKI_USER" ]]; then
                LOKI_USER="$1"
            elif [[ -z "$LOKI_PASS" ]]; then
                LOKI_PASS="$1"
            fi
            shift
            ;;
    esac
done

#===============================================================================
# UNINSTALL
#===============================================================================

run_uninstall() {
    echo ""
    echo "=========================================="
    echo "${RED}Uninstalling Monitoring Agents${NC}"
    echo "=========================================="
    echo ""

    check_root

    for module in promtail fail2ban_exporter phpfpm_exporter mysqld_exporter nginx_exporter node_exporter; do
        local module_dir
        if module_dir=$(get_module_dir "$module" 2>/dev/null); then
            local uninstall_script="$module_dir/uninstall.sh"
            if [[ -f "$uninstall_script" ]]; then
                log_info "Uninstalling $module..."
                # Properly quote variable expansion - use array for arguments
                local -a uninstall_args=()
                if [[ "$PURGE_DATA" == "true" ]]; then
                    uninstall_args=("--purge")
                fi
                bash "$uninstall_script" "${uninstall_args[@]+"${uninstall_args[@]}"}"
            fi
        fi
    done

    # Remove firewall rules
    if command -v ufw &>/dev/null; then
        for port in 9100 9113 9104 9253 9191; do
            ufw delete allow from any to any port "$port" proto tcp 2>/dev/null || true
        done
    fi

    systemctl daemon-reload

    echo ""
    echo "=========================================="
    echo "${GREEN}Uninstallation Complete${NC}"
    echo "=========================================="
}

#===============================================================================
# INSTALLATION
#===============================================================================

find_host_config() {
    if [[ -n "$HOST_CONFIG" ]] && [[ -f "$HOST_CONFIG" ]]; then
        echo "$HOST_CONFIG"
        return 0
    fi

    local hostname
    hostname=$(hostname -f 2>/dev/null || hostname)
    local short_hostname="${hostname%%.*}"

    # Check for config in standard location
    local config_dir
    config_dir=$(get_hosts_config_dir)

    for name in "$hostname" "$short_hostname"; do
        if [[ -f "$config_dir/${name}.yaml" ]]; then
            echo "$config_dir/${name}.yaml"
            return 0
        fi
    done

    return 1
}

prepare_system() {
    log_info "Preparing system..."
    apt-get update -qq
    apt-get install -y -qq wget curl unzip ufw
    log_success "System packages verified"
}

configure_firewall() {
    if [[ -z "$OBSERVABILITY_IP" ]]; then
        log_warn "OBSERVABILITY_IP not set, skipping firewall configuration"
        return
    fi

    log_info "Configuring firewall..."

    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp

    # Get enabled modules and configure ports
    local hostname
    hostname=$(hostname -f 2>/dev/null || hostname)
    local short_hostname="${hostname%%.*}"

    while IFS= read -r module; do
        local port
        port=$(module_port "$module")
        if [[ -n "$port" ]]; then
            if ! ufw status | grep -q "$OBSERVABILITY_IP.*$port"; then
                ufw allow from "$OBSERVABILITY_IP" to any port "$port" proto tcp
            fi
        fi
    done < <(get_host_enabled_modules "$short_hostname" 2>/dev/null || list_core_modules)

    ufw --force enable
    log_success "Firewall configured"
}

install_from_config() {
    local config_file="$1"
    local hostname
    hostname=$(basename "$config_file" .yaml)

    log_info "Installing from config: $config_file"
    echo ""

    # Get enabled modules
    local modules
    modules=$(get_host_enabled_modules "$hostname")

    if [[ -z "$modules" ]]; then
        log_warn "No modules enabled in config, installing defaults..."
        modules=$(list_core_modules)
    fi

    # Track installation results
    local -a successful_modules=()
    local -a failed_modules=()

    # Install each enabled module
    while IFS= read -r module; do
        [[ -z "$module" ]] && continue

        local display_name
        display_name=$(module_display_name "$module")
        log_info "Installing ${display_name:-$module}..."

        # Set environment variables for install script
        export MODULE_NAME="$module"
        export MODULE_VERSION
        MODULE_VERSION=$(module_version "$module")
        export MODULE_PORT
        MODULE_PORT=$(module_port "$module")
        export FORCE_MODE
        export OBSERVABILITY_IP

        # Special handling for promtail
        if [[ "$module" == "promtail" ]]; then
            export LOKI_URL
            export LOKI_USER
            export LOKI_PASS

            # Try to get from host config if not provided
            if [[ -z "$LOKI_URL" ]]; then
                LOKI_URL=$(get_host_module_config "$hostname" "promtail" "loki_url" 2>/dev/null || echo "")
            fi
            if [[ -z "$LOKI_USER" ]]; then
                LOKI_USER=$(get_host_module_config "$hostname" "promtail" "loki_user" 2>/dev/null || echo "")
            fi
            if [[ -z "$LOKI_PASS" ]]; then
                LOKI_PASS=$(get_host_module_config "$hostname" "promtail" "loki_password" 2>/dev/null || echo "")
            fi
        fi

        # Properly quote variable expansion - use array for arguments
        local -a install_args=()
        if [[ "$FORCE_MODE" == "true" ]]; then
            install_args=("--force")
        fi

        # Try to install module and track result
        if install_module "$module" "${install_args[@]+"${install_args[@]}"}"; then
            successful_modules+=("$module")
        else
            failed_modules+=("$module")
            log_error "Failed to install $module"
        fi
        echo ""
    done <<< "$modules"

    # Report summary
    echo ""
    echo "=========================================="
    echo "Installation Summary"
    echo "=========================================="
    echo ""
    if [[ ${#successful_modules[@]} -gt 0 ]]; then
        echo "Successfully installed (${#successful_modules[@]}):"
        for mod in "${successful_modules[@]}"; do
            echo "  - $mod"
        done
        echo ""
    fi

    if [[ ${#failed_modules[@]} -gt 0 ]]; then
        echo "Failed to install (${#failed_modules[@]}):"
        for mod in "${failed_modules[@]}"; do
            echo "  - $mod"
        done
        echo ""
        echo "Next steps:"
        echo "  1. Check logs for error details: journalctl -xe"
        echo "  2. Retry failed modules: ./scripts/module-manager.sh install <module>"
        echo "  3. Review module requirements: ./scripts/module-manager.sh show <module>"
        echo ""
        return 1
    fi

    return 0
}

install_all_modules() {
    log_info "Installing all core modules..."
    echo ""

    for module in node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter promtail; do
        local display_name
        display_name=$(module_display_name "$module")

        export MODULE_NAME="$module"
        export MODULE_VERSION
        MODULE_VERSION=$(module_version "$module")
        export MODULE_PORT
        MODULE_PORT=$(module_port "$module")
        export FORCE_MODE
        export OBSERVABILITY_IP

        if [[ "$module" == "promtail" ]]; then
            export LOKI_URL
            export LOKI_USER
            export LOKI_PASS
        fi

        # Properly quote variable expansion - use array for arguments
        local -a install_args=()
        if [[ "$FORCE_MODE" == "true" ]]; then
            install_args=("--force")
        fi
        install_module "$module" "${install_args[@]+"${install_args[@]}"}"
        echo ""
    done
}

print_summary() {
    local HOST_IP
    HOST_IP=$(hostname -I | awk '{print $1}')

    echo ""
    echo "=========================================="
    echo "${GREEN}Monitored Host Setup Complete!${NC}"
    echo "=========================================="
    echo ""
    echo "Host: $(hostname)"
    echo "IP:   $HOST_IP"
    echo ""

    "$SCRIPT_DIR/module-manager.sh" status
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    # Handle uninstall
    if [[ "$UNINSTALL_MODE" == "true" ]]; then
        run_uninstall
        exit 0
    fi

    echo ""
    echo "=========================================="
    echo "Monitored Host Agent Setup v2 (Modules)"
    echo "=========================================="
    if [[ "$FORCE_MODE" == "true" ]]; then
        echo "${YELLOW}>>> FORCE MODE <<<${NC}"
    fi
    echo ""

    check_root

    # Try to find host config
    local config_file
    if config_file=$(find_host_config 2>/dev/null); then
        log_info "Using host config: $config_file"
        echo ""
        prepare_system
        configure_firewall
        install_from_config "$config_file"
    else
        # No config found - install all modules
        log_warn "No host config found, installing all core modules"
        echo ""

        if [[ -z "$OBSERVABILITY_IP" ]]; then
            echo "Usage: $0 <OBSERVABILITY_VPS_IP> [LOKI_URL] [LOKI_USER] [LOKI_PASS]"
            exit 1
        fi

        prepare_system
        configure_firewall
        install_all_modules
    fi

    print_summary
}

main "$@"
