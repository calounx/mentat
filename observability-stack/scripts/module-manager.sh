#!/bin/bash
#===============================================================================
# Module Manager CLI
# Central tool for managing exporter modules
#
# Usage:
#   module-manager.sh <command> [options]
#
# Commands:
#   list              List all available modules
#   show <module>     Show detailed module information
#   validate [module] Validate module manifest(s)
#   detect            Auto-detect applicable modules for current host
#   enable <module> <host>   Enable a module for a host
#   disable <module> <host>  Disable a module for a host
#   install <module>  Install a module on current host
#   uninstall <module> Uninstall a module
#   generate-config   Generate Prometheus/Grafana configs from modules
#   status            Show status of all modules on current host
#===============================================================================

set -euo pipefail

_MM_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_MM_SCRIPT_DIR/lib/common.sh"
source "$_MM_SCRIPT_DIR/lib/module-loader.sh"
source "$_MM_SCRIPT_DIR/lib/config-generator.sh"

#===============================================================================
# COMMANDS
#===============================================================================

cmd_list() {
    local filter="${1:-all}"

    echo ""
    echo "Available Modules"
    echo "================="
    echo ""

    case "$filter" in
        core)
            echo "Core Modules:"
            while IFS= read -r module; do
                local version port display_name
                display_name=$(module_display_name "$module")
                version=$(module_version "$module")
                port=$(module_port "$module")
                printf "  %-25s v%-10s port:%s\n" "${display_name:-$module}" "$version" "$port"
            done < <(list_core_modules)
            ;;
        available)
            echo "Available (Community) Modules:"
            while IFS= read -r module; do
                local version port display_name
                display_name=$(module_display_name "$module")
                version=$(module_version "$module")
                port=$(module_port "$module")
                printf "  %-25s v%-10s port:%s\n" "${display_name:-$module}" "$version" "$port"
            done < <(list_available_modules)
            ;;
        custom)
            echo "Custom Modules:"
            while IFS= read -r module; do
                local version port display_name
                display_name=$(module_display_name "$module")
                version=$(module_version "$module")
                port=$(module_port "$module")
                printf "  %-25s v%-10s port:%s\n" "${display_name:-$module}" "$version" "$port"
            done < <(list_custom_modules)
            ;;
        *)
            list_modules_status
            ;;
    esac

    echo ""
}

cmd_show() {
    local module="$1"

    if [[ -z "$module" ]]; then
        log_error "Module name required"
        echo ""
        echo "Usage: module-manager.sh show <module>"
        echo ""
        echo "Available modules:"
        list_core_modules | sed 's/^/  - /'
        echo ""
        echo "Example:"
        echo "  module-manager.sh show node_exporter"
        exit 1
    fi

    show_module_info "$module"
}

cmd_validate() {
    local module="${1:-}"

    if [[ -n "$module" ]]; then
        validate_module "$module"
    else
        echo "Validating all modules..."
        echo ""
        validate_all_modules
    fi
}

cmd_detect() {
    "$SCRIPT_DIR/auto-detect.sh" "$@"
}

cmd_enable() {
    local module="$1"
    local hostname="$2"

    if [[ -z "$module" ]] || [[ -z "$hostname" ]]; then
        log_error "Module and hostname required"
        echo ""
        echo "Usage: module-manager.sh enable <module> <hostname>"
        echo ""
        echo "Example:"
        echo "  module-manager.sh enable nginx_exporter webserver1"
        echo ""
        echo "To see available modules:"
        echo "  module-manager.sh list"
        exit 1
    fi

    if ! module_exists "$module"; then
        log_error "Module '$module' not found"
        echo ""
        echo "Available modules:"
        list_all_modules | sed 's/^/  - /'
        echo ""
        echo "To see module details:"
        echo "  module-manager.sh show <module>"
        exit 1
    fi

    local host_config
    host_config=$(get_host_config "$hostname")

    if [[ ! -f "$host_config" ]]; then
        log_error "Host config not found: $host_config"
        echo ""
        echo "Create host config first:"
        echo "  1. Auto-detect modules on the host:"
        echo "     ssh $hostname 'cd /path/to/observability-stack && ./scripts/auto-detect.sh --generate --output=config/hosts/${hostname}.yaml'"
        echo ""
        echo "  2. Or create it manually:"
        echo "     mkdir -p config/hosts"
        echo "     cp config/hosts/example.yaml config/hosts/${hostname}.yaml"
        echo "     vi config/hosts/${hostname}.yaml"
        exit 1
    fi

    # Update the enabled flag in the host config (idempotent)
    if grep -q "^  ${module}:" "$host_config"; then
        # Module exists - check if already has enabled flag
        if grep -A5 "^  ${module}:" "$host_config" | grep -q "^    enabled:"; then
            # Update existing enabled flag
            sed -i "/^  ${module}:/,/^  [a-z]/ s/^    enabled:.*/    enabled: true/" "$host_config"
            log_success "Updated $module to enabled for $hostname"
        else
            # Add enabled flag after module declaration
            sed -i "/^  ${module}:/a\\    enabled: true" "$host_config"
            log_success "Enabled $module for $hostname"
        fi
    else
        log_warn "Module $module not found in $hostname config. Adding..."
        echo "" >> "$host_config"
        echo "  ${module}:" >> "$host_config"
        echo "    enabled: true" >> "$host_config"
        log_success "Added and enabled $module for $hostname"
    fi

    # Trigger config regeneration
    log_info "Regenerating configurations..."
    "$_MM_SCRIPT_DIR/module-manager.sh" generate-config 2>/dev/null || true
}

cmd_disable() {
    local module="$1"
    local hostname="$2"

    if [[ -z "$module" ]] || [[ -z "$hostname" ]]; then
        log_error "Module and hostname required"
        echo ""
        echo "Usage: module-manager.sh disable <module> <hostname>"
        echo ""
        echo "Example:"
        echo "  module-manager.sh disable nginx_exporter webserver1"
        exit 1
    fi

    local host_config
    host_config=$(get_host_config "$hostname")

    if [[ ! -f "$host_config" ]]; then
        log_error "Host config not found: $host_config"
        echo ""
        echo "Expected location: $host_config"
        echo ""
        echo "To list existing host configs:"
        echo "  ls config/hosts/"
        exit 1
    fi

    # Update the enabled flag
    sed -i "/^  ${module}:/,/^  [a-z]/ s/enabled: true/enabled: false/" "$host_config"
    log_success "Disabled $module for $hostname"
}

cmd_install() {
    local module="$1"
    shift

    if [[ -z "$module" ]]; then
        log_error "Module name required"
        echo ""
        echo "Usage: module-manager.sh install <module> [--force]"
        echo ""
        echo "Available modules:"
        list_all_modules | sed 's/^/  - /'
        echo ""
        echo "Examples:"
        echo "  module-manager.sh install node_exporter"
        echo "  module-manager.sh install nginx_exporter --force"
        echo ""
        echo "To see module details:"
        echo "  module-manager.sh show <module>"
        exit 1
    fi

    install_module "$module" "$@"
}

cmd_uninstall() {
    local module="$1"
    shift

    if [[ -z "$module" ]]; then
        log_error "Module name required"
        echo ""
        echo "Usage: module-manager.sh uninstall <module> [--purge]"
        echo ""
        echo "Examples:"
        echo "  module-manager.sh uninstall nginx_exporter"
        echo "  module-manager.sh uninstall node_exporter --purge"
        echo ""
        echo "Note: --purge will also remove configuration files"
        echo ""
        echo "To see installed modules:"
        echo "  module-manager.sh status"
        exit 1
    fi

    uninstall_module "$module" "$@"
}

cmd_generate_config() {
    local dry_run=false

    for arg in "$@"; do
        [[ "$arg" == "--dry-run" ]] && dry_run=true
    done

    if [[ "$dry_run" == "true" ]]; then
        show_generation_plan
    else
        generate_all_configs
    fi
}

cmd_status() {
    echo ""
    echo "Module Status on $(hostname)"
    echo "=============================="
    echo ""

    printf "%-25s %-12s %-10s %s\n" "MODULE" "INSTALLED" "RUNNING" "PORT"
    printf "%-25s %-12s %-10s %s\n" "-------------------------" "------------" "----------" "----"

    while IFS= read -r module; do
        local display_name port installed running

        display_name=$(module_display_name "$module")
        port=$(module_port "$module")

        # Check if installed
        local install_path
        case "$module" in
            node_exporter) install_path="/usr/local/bin/node_exporter" ;;
            nginx_exporter) install_path="/usr/local/bin/nginx-prometheus-exporter" ;;
            mysqld_exporter) install_path="/usr/local/bin/mysqld_exporter" ;;
            phpfpm_exporter) install_path="/usr/local/bin/php-fpm_exporter" ;;
            fail2ban_exporter) install_path="/usr/local/bin/fail2ban-prometheus-exporter" ;;
            promtail) install_path="/usr/local/bin/promtail" ;;
            *) install_path="" ;;
        esac

        if [[ -x "$install_path" ]]; then
            installed="${GREEN}Yes${NC}"
        else
            installed="${RED}No${NC}"
        fi

        # Check if running
        local service_name="${module}"
        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
            running="${GREEN}Running${NC}"
        else
            running="${RED}Stopped${NC}"
        fi

        printf "%-25s %-12b %-10b %s\n" \
            "${display_name:-$module}" \
            "$installed" \
            "$running" \
            "$port"
    done < <(list_core_modules)

    echo ""
}

cmd_help() {
    cat << 'EOF'
Module Manager - Observability Stack Module Management

Usage:
  module-manager.sh <command> [options]

Commands:
  list [core|available|custom]
                    List modules (all by default, or filter by type)

  show <module>     Show detailed information about a module

  validate [module] Validate module manifest(s)
                    If no module specified, validates all

  detect [--generate] [--output=file]
                    Auto-detect applicable modules for current host
                    --generate: Create host config file
                    --output: Specify output file path

  enable <module> <host>
                    Enable a module for a specific host

  disable <module> <host>
                    Disable a module for a specific host

  install <module> [--force]
                    Install a module on the current host

  uninstall <module> [--purge]
                    Uninstall a module
                    --purge: Also remove configuration files

  generate-config [--dry-run]
                    Generate Prometheus/Grafana configs from enabled modules
                    --dry-run: Show what would be generated

  status            Show installation status of all modules

Examples:
  # List all available modules
  module-manager.sh list

  # Show node_exporter details
  module-manager.sh show node_exporter

  # Auto-detect and create host config
  module-manager.sh detect --generate --output=config/hosts/myhost.yaml

  # Install node_exporter
  module-manager.sh install node_exporter

  # Generate all configs after changing host configs
  module-manager.sh generate-config

EOF
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    local command="${1:-help}"
    shift 2>/dev/null || true

    case "$command" in
        list)           cmd_list "$@" ;;
        show)           cmd_show "$@" ;;
        validate)       cmd_validate "$@" ;;
        detect)         cmd_detect "$@" ;;
        enable)         cmd_enable "$@" ;;
        disable)        cmd_disable "$@" ;;
        install)        cmd_install "$@" ;;
        uninstall)      cmd_uninstall "$@" ;;
        generate-config|generate) cmd_generate_config "$@" ;;
        status)         cmd_status ;;
        help|--help|-h) cmd_help ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            echo "Available commands:"
            echo "  list              List all available modules"
            echo "  show <module>     Show module details"
            echo "  validate          Validate module manifests"
            echo "  detect            Auto-detect applicable modules"
            echo "  install <module>  Install a module"
            echo "  uninstall <module> Uninstall a module"
            echo "  status            Show module status"
            echo ""
            echo "Run 'module-manager.sh help' for detailed usage"
            exit 1
            ;;
    esac
}

main "$@"
