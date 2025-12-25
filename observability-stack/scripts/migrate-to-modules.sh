#!/bin/bash
#===============================================================================
# Migration Script
# Migrates existing global.yaml configuration to per-host config files
#
# Usage:
#   ./migrate-to-modules.sh [--dry-run]
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/module-loader.sh"

STACK_ROOT=$(get_stack_root)
GLOBAL_CONFIG="$STACK_ROOT/config/global.yaml"
HOSTS_DIR="$STACK_ROOT/config/hosts"

DRY_RUN=false
for arg in "$@"; do
    [[ "$arg" == "--dry-run" ]] && DRY_RUN=true
done

#===============================================================================
# MIGRATION
#===============================================================================

extract_hosts() {
    # Parse monitored_hosts from global.yaml
    awk '
        /^monitored_hosts:/ { in_hosts = 1; next }
        in_hosts && /^[a-zA-Z]/ && !/^  / { in_hosts = 0 }
        in_hosts && /^  - name:/ {
            name = $3
            gsub(/["'\'']/, "", name)
            current_host = name
        }
        in_hosts && /^    ip:/ {
            ip = $2
            gsub(/["'\'']/, "", ip)
            hosts[current_host] = ip
        }
        in_hosts && /^    description:/ {
            $1 = ""
            desc = $0
            gsub(/^[[:space:]]*/, "", desc)
            gsub(/["'\'']/, "", desc)
            descs[current_host] = desc
        }
        in_hosts && /^    exporters:/ {
            in_exporters = 1
            next
        }
        in_hosts && in_exporters && /^      - / {
            exp = $2
            exporters[current_host] = exporters[current_host] " " exp
        }
        in_hosts && in_exporters && /^    [a-z]/ && !/^      / {
            in_exporters = 0
        }
        END {
            for (host in hosts) {
                print host "|" hosts[host] "|" descs[host] "|" exporters[host]
            }
        }
    ' "$GLOBAL_CONFIG"
}

generate_host_config() {
    local name="$1"
    local ip="$2"
    local description="$3"
    local exporters="$4"

    cat << EOF
# Host Configuration for $name
# Migrated from global.yaml on $(date)

host:
  name: "$name"
  ip: "$ip"
  description: "${description:-$name}"
  environment: "production"
  labels:
    tier: "unknown"

modules:
EOF

    # Generate module entries based on exporters list
    local all_modules="node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter promtail"

    for module in $all_modules; do
        local enabled="false"

        # Check if this exporter was listed
        if echo "$exporters" | grep -qw "$module"; then
            enabled="true"
        fi

        cat << EOF
  $module:
    enabled: $enabled
EOF

        # Add module-specific placeholders
        case "$module" in
            mysqld_exporter)
                if [[ "$enabled" == "true" ]]; then
                    cat << EOF
    config:
      credentials:
        username: "exporter"
        password: "CHANGE_ME"
      host: "127.0.0.1"
      port: 3306
EOF
                fi
                ;;
            promtail)
                if [[ "$enabled" == "true" ]]; then
                    cat << EOF
    config:
      loki_url: "https://mentat.arewel.com"
      loki_user: "loki"
      loki_password: "CHANGE_ME"
EOF
                fi
                ;;
        esac

        echo ""
    done
}

migrate() {
    log_info "Migrating global.yaml to per-host configurations..."
    echo ""

    if [[ ! -f "$GLOBAL_CONFIG" ]]; then
        log_error "Global config not found: $GLOBAL_CONFIG"
        exit 1
    fi

    # Create hosts directory
    if [[ "$DRY_RUN" != "true" ]]; then
        mkdir -p "$HOSTS_DIR"
    fi

    # Extract and process hosts
    local host_count=0

    while IFS='|' read -r name ip description exporters; do
        [[ -z "$name" ]] && continue

        local output_file="$HOSTS_DIR/${name}.yaml"

        echo "Processing: $name ($ip)"
        echo "  Exporters: $exporters"

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  Would create: $output_file"
            echo ""
            echo "  --- Preview ---"
            generate_host_config "$name" "$ip" "$description" "$exporters" | head -30
            echo "  ..."
            echo ""
        else
            generate_host_config "$name" "$ip" "$description" "$exporters" > "$output_file"
            log_success "Created: $output_file"
        fi

        ((host_count++))
    done < <(extract_hosts)

    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run complete. Would migrate $host_count hosts."
        log_info "Run without --dry-run to perform migration."
    else
        log_success "Migration complete! Created $host_count host configurations."
        echo ""
        echo "Next steps:"
        echo "  1. Review generated configs in $HOSTS_DIR/"
        echo "  2. Update credentials (MySQL exporter, Promtail)"
        echo "  3. Generate Prometheus config: ./module-manager.sh generate-config"
    fi
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    echo ""
    echo "========================================"
    echo "Migration: global.yaml to Module System"
    echo "========================================"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY RUN MODE - No changes will be made"
        echo ""
    fi

    migrate
}

main "$@"
