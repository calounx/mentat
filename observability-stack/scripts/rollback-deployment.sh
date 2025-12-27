#!/bin/bash
#===============================================================================
# Automated Deployment Rollback Script
# Restores observability stack to previous working state
#
# Usage:
#   ./rollback-deployment.sh [OPTIONS]
#   ./rollback-deployment.sh --backup TIMESTAMP
#   ./rollback-deployment.sh --auto  # Use latest backup
#   ./rollback-deployment.sh --list  # List available backups
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_BASE="/var/backups/observability-stack"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Flags
AUTO_MODE=false
LIST_MODE=false
BACKUP_DIR=""
FORCE_MODE=false
DRY_RUN=false

#===============================================================================
# LOGGING
#===============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

log_step() {
    echo ""
    echo -e "${CYAN}==>${NC} ${BOLD}$1${NC}"
}

#===============================================================================
# HELPER FUNCTIONS
#===============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
    fi
}

show_help() {
    cat << 'EOF'
Automated Deployment Rollback Script

USAGE:
    ./rollback-deployment.sh [OPTIONS]

OPTIONS:
    --auto                  Use latest backup automatically
    --backup TIMESTAMP      Specify backup to restore (e.g., 20251227_143000)
    --list                  List available backups
    --force                 Skip confirmation prompts
    --dry-run               Show what would be done without executing
    --help, -h              Show this help message

EXAMPLES:
    # List available backups
    ./rollback-deployment.sh --list

    # Automatic rollback to latest backup
    ./rollback-deployment.sh --auto

    # Rollback to specific backup
    ./rollback-deployment.sh --backup 20251227_143000

    # Dry run (no changes)
    ./rollback-deployment.sh --auto --dry-run

BACKUP LOCATION:
    /var/backups/observability-stack/

ROLLBACK PROCESS:
    1. Verify backup exists and is complete
    2. Create safety backup of current state
    3. Stop all services
    4. Restore configurations from backup
    5. Restore previous code version (git)
    6. Restart services
    7. Verify health

SAFETY:
    - Current state is backed up before rollback
    - Data directories (/var/lib/*) are preserved
    - Rollback can be reverted if needed
EOF
}

list_backups() {
    echo ""
    echo "=========================================="
    echo "Available Backups"
    echo "=========================================="
    echo ""

    if [[ ! -d "$BACKUP_BASE" ]]; then
        echo "No backup directory found at: $BACKUP_BASE"
        return
    fi

    local count=0
    local backups=()

    # Find all backup directories
    while IFS= read -r -d '' backup; do
        backups+=("$backup")
    done < <(find "$BACKUP_BASE" -maxdepth 1 -type d -name "*-*" -print0 | sort -z -r)

    if [[ ${#backups[@]} -eq 0 ]]; then
        echo "No backups found"
        return
    fi

    printf "%-5s %-25s %-20s %-15s\n" "No." "Backup ID" "Created" "Size"
    echo "--------------------------------------------------------------------------------"

    for backup in "${backups[@]}"; do
        ((count++))
        local backup_id=$(basename "$backup")
        local created=$(stat -c %y "$backup" | cut -d'.' -f1)
        local size=$(du -sh "$backup" 2>/dev/null | cut -f1)

        # Check if has git commit info
        local git_info=""
        if [[ -f "$backup/git-commit.txt" ]]; then
            local commit=$(cat "$backup/git-commit.txt" | cut -c1-8)
            git_info=" (git: $commit)"
        fi

        printf "%-5d %-25s %-20s %-15s %s\n" "$count" "$backup_id" "$created" "$size" "$git_info"
    done

    echo ""
    echo "Total backups: $count"
    echo ""
    echo "To restore a backup, use:"
    echo "  ./rollback-deployment.sh --backup BACKUP_ID"
    echo ""
}

find_latest_backup() {
    if [[ ! -d "$BACKUP_BASE" ]]; then
        log_error "No backup directory found at: $BACKUP_BASE"
    fi

    local latest
    latest=$(find "$BACKUP_BASE" -maxdepth 1 -type d -name "*-*" -printf "%T@ %p\n" | sort -n -r | head -1 | cut -d' ' -f2)

    if [[ -z "$latest" ]]; then
        log_error "No backups found in $BACKUP_BASE"
    fi

    echo "$latest"
}

verify_backup() {
    local backup_dir="$1"

    log_step "Verifying backup integrity"

    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup directory does not exist: $backup_dir"
    fi

    # Check for required backup components
    local missing=()

    [[ ! -f "$backup_dir/git-commit.txt" ]] && missing+=("git-commit.txt")

    # Check for at least one service config
    local has_config=false
    for service in prometheus grafana loki alertmanager; do
        if [[ -d "$backup_dir/$service" ]] || [[ -f "$backup_dir/${service}.yml" ]] || [[ -f "$backup_dir/${service}.yaml" ]]; then
            has_config=true
            break
        fi
    done

    if [[ "$has_config" == "false" ]]; then
        missing+=("service-configs")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warn "Backup may be incomplete. Missing:"
        for item in "${missing[@]}"; do
            echo "  - $item"
        done

        if [[ "$FORCE_MODE" != "true" ]]; then
            echo ""
            read -p "Continue anyway? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_error "Rollback cancelled"
            fi
        fi
    else
        log_success "Backup verification passed"
    fi
}

create_safety_backup() {
    log_step "Creating safety backup of current state"

    local safety_backup="${BACKUP_BASE}/pre-rollback-$(date +%Y%m%d_%H%M%S)"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create safety backup at: $safety_backup"
        return
    fi

    mkdir -p "$safety_backup"

    # Backup current configurations
    for dir in /etc/prometheus /etc/grafana /etc/loki /etc/alertmanager; do
        if [[ -d "$dir" ]]; then
            cp -r "$dir" "$safety_backup/" 2>/dev/null || true
        fi
    done

    # Backup Nginx config
    if [[ -f "/etc/nginx/sites-available/observability" ]]; then
        mkdir -p "$safety_backup/nginx"
        cp "/etc/nginx/sites-available/observability" "$safety_backup/nginx/"
    fi

    # Save current git state
    cd "$BASE_DIR"
    git rev-parse HEAD > "$safety_backup/git-commit.txt" 2>/dev/null || echo "unknown" > "$safety_backup/git-commit.txt"

    log_success "Safety backup created at: $safety_backup"
    echo "  (Can be used to revert this rollback if needed)"
}

stop_services() {
    log_step "Stopping services"

    local services=(
        "prometheus"
        "grafana-server"
        "loki"
        "alertmanager"
        "nginx"
        "node_exporter"
        "nginx_exporter"
        "phpfpm_exporter"
        "promtail"
    )

    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would stop: $service"
            else
                log_info "Stopping $service..."
                systemctl stop "$service" || log_warn "Failed to stop $service"
            fi
        fi
    done

    if [[ "$DRY_RUN" != "true" ]]; then
        sleep 3
        log_success "Services stopped"
    fi
}

restore_configurations() {
    local backup_dir="$1"

    log_step "Restoring configurations from backup"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restore from: $backup_dir"
        ls -la "$backup_dir"
        return
    fi

    # Restore service configurations
    for service_dir in prometheus grafana loki alertmanager; do
        if [[ -d "$backup_dir/$service_dir" ]]; then
            log_info "Restoring $service_dir configuration..."
            rm -rf "/etc/$service_dir"
            cp -r "$backup_dir/$service_dir" "/etc/"

            # Restore ownership
            case "$service_dir" in
                prometheus)
                    chown -R prometheus:prometheus "/etc/prometheus"
                    ;;
                grafana)
                    chown -R grafana:grafana "/etc/grafana"
                    ;;
                loki)
                    chown -R loki:loki "/etc/loki"
                    ;;
                alertmanager)
                    chown -R alertmanager:alertmanager "/etc/alertmanager"
                    ;;
            esac

            log_success "$service_dir configuration restored"
        fi
    done

    # Restore Nginx configuration
    if [[ -f "$backup_dir/nginx/observability" ]]; then
        log_info "Restoring Nginx configuration..."
        cp "$backup_dir/nginx/observability" "/etc/nginx/sites-available/"
        log_success "Nginx configuration restored"
    elif [[ -f "$backup_dir/observability" ]]; then
        log_info "Restoring Nginx configuration..."
        cp "$backup_dir/observability" "/etc/nginx/sites-available/"
        log_success "Nginx configuration restored"
    fi

    # Restore systemd service files
    for service_file in "$backup_dir"/*.service; do
        if [[ -f "$service_file" ]]; then
            local service_name=$(basename "$service_file")
            log_info "Restoring systemd service: $service_name"
            cp "$service_file" "/etc/systemd/system/"
        fi
    done

    # Reload systemd
    systemctl daemon-reload
}

restore_code_version() {
    local backup_dir="$1"

    log_step "Restoring code version"

    if [[ ! -f "$backup_dir/git-commit.txt" ]]; then
        log_warn "No git commit info in backup, skipping code restore"
        return
    fi

    local target_commit
    target_commit=$(cat "$backup_dir/git-commit.txt")

    if [[ -z "$target_commit" ]] || [[ "$target_commit" == "unknown" ]]; then
        log_warn "Invalid git commit in backup, skipping code restore"
        return
    fi

    cd "$BASE_DIR"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would checkout git commit: $target_commit"
        return
    fi

    log_info "Checking out git commit: $target_commit"

    if ! git checkout "$target_commit" 2>/dev/null; then
        log_warn "Failed to checkout commit, attempting fetch..."
        git fetch --all
        git checkout "$target_commit" || log_error "Failed to restore code version"
    fi

    local version
    version=$(git describe --tags 2>/dev/null || echo "$target_commit")
    log_success "Code restored to version: $version"
}

start_services() {
    log_step "Starting services"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would start all services"
        return
    fi

    local services=(
        "prometheus"
        "loki"
        "alertmanager"
        "grafana-server"
        "nginx"
        "node_exporter"
        "nginx_exporter"
        "phpfpm_exporter"
        "promtail"
    )

    for service in "${services[@]}"; do
        if systemctl list-unit-files "$service.service" &>/dev/null; then
            log_info "Starting $service..."
            systemctl start "$service" || log_warn "Failed to start $service"
        fi
    done

    log_success "Services started"
}

verify_health() {
    log_step "Verifying system health"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would run health checks"
        return
    fi

    # Wait for services to stabilize
    log_info "Waiting 30 seconds for services to stabilize..."
    sleep 30

    # Run health check script if available
    if [[ -f "$SCRIPT_DIR/health-check.sh" ]]; then
        log_info "Running health check script..."
        if "$SCRIPT_DIR/health-check.sh"; then
            log_success "Health check passed"
        else
            log_warn "Health check reported issues - manual verification recommended"
        fi
    else
        # Manual health checks
        local failed_services=()

        for service in prometheus grafana-server loki alertmanager nginx; do
            if systemctl list-unit-files "$service.service" &>/dev/null; then
                if ! systemctl is-active --quiet "$service"; then
                    failed_services+=("$service")
                fi
            fi
        done

        if [[ ${#failed_services[@]} -eq 0 ]]; then
            log_success "All services running"
        else
            log_warn "Some services failed to start:"
            for service in "${failed_services[@]}"; do
                echo "  - $service (check logs: journalctl -u $service)"
            done
        fi
    fi
}

#===============================================================================
# MAIN ROLLBACK PROCEDURE
#===============================================================================

execute_rollback() {
    local backup_dir="$1"

    echo ""
    echo "=========================================="
    echo -e "${BOLD}${YELLOW}DEPLOYMENT ROLLBACK${NC}"
    echo "=========================================="
    echo ""
    echo "Backup source: $backup_dir"

    if [[ -f "$backup_dir/git-commit.txt" ]]; then
        local commit=$(cat "$backup_dir/git-commit.txt")
        echo "Target version: $commit"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        echo -e "${YELLOW}>>> DRY RUN MODE - No changes will be made <<<${NC}"
    fi

    echo ""

    # Confirmation prompt
    if [[ "$FORCE_MODE" != "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
        echo -e "${YELLOW}WARNING:${NC} This will:"
        echo "  1. Stop all observability services"
        echo "  2. Restore configurations from backup"
        echo "  3. Restore previous code version"
        echo "  4. Restart all services"
        echo ""
        echo "Data directories (/var/lib/*) will NOT be affected."
        echo ""
        read -p "Continue with rollback? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Rollback cancelled by user"
        fi
        echo ""
    fi

    # Execute rollback steps
    verify_backup "$backup_dir"
    create_safety_backup
    stop_services
    restore_configurations "$backup_dir"
    restore_code_version "$backup_dir"
    start_services
    verify_health

    # Summary
    echo ""
    echo "=========================================="
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${BLUE}${BOLD}DRY RUN COMPLETE${NC}"
        echo ""
        echo "No changes were made. Remove --dry-run to execute."
    else
        echo -e "${GREEN}${BOLD}ROLLBACK COMPLETE${NC}"
        echo ""
        echo "System has been rolled back to:"
        echo "  Backup: $(basename "$backup_dir")"
        if [[ -f "$backup_dir/git-commit.txt" ]]; then
            local commit=$(cat "$backup_dir/git-commit.txt")
            local version=$(cd "$BASE_DIR" && git describe --tags 2>/dev/null || echo "$commit")
            echo "  Version: $version"
        fi
        echo ""
        echo "Next steps:"
        echo "  1. Verify Grafana is accessible"
        echo "  2. Check dashboards are displaying data"
        echo "  3. Review logs for any errors"
        echo "  4. Notify stakeholders of rollback"
        echo "  5. Investigate root cause of deployment issue"
    fi
    echo "=========================================="
    echo ""
}

#===============================================================================
# ARGUMENT PARSING
#===============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --auto)
                AUTO_MODE=true
                shift
                ;;
            --backup)
                BACKUP_DIR="$BACKUP_BASE/$2"
                shift 2
                ;;
            --list)
                LIST_MODE=true
                shift
                ;;
            --force)
                FORCE_MODE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    parse_args "$@"

    # Check root
    check_root

    # List mode
    if [[ "$LIST_MODE" == "true" ]]; then
        list_backups
        exit 0
    fi

    # Determine backup to use
    if [[ "$AUTO_MODE" == "true" ]]; then
        BACKUP_DIR=$(find_latest_backup)
        log_info "Auto-selected latest backup: $(basename "$BACKUP_DIR")"
    elif [[ -z "$BACKUP_DIR" ]]; then
        echo "Error: Must specify --auto or --backup TIMESTAMP"
        echo ""
        echo "Available backups:"
        list_backups
        exit 1
    fi

    # Execute rollback
    execute_rollback "$BACKUP_DIR"
}

main "$@"
