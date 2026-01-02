#!/bin/bash
# ============================================================================
# Docker Environment Cleanup Script
# ============================================================================
# Cleanup script to reset all Docker test environments
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Compose file paths
COMPOSE_MAIN="${REPO_ROOT}/docker/docker-compose.yml"
COMPOSE_VPS="${REPO_ROOT}/docker/docker-compose.vps.yml"
COMPOSE_DEV="${REPO_ROOT}/chom/docker-compose.yml"

# Colors
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"
}

log_success() {
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $*"
}

log_warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*"
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*"
}

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Cleanup Docker test environments.

OPTIONS:
    -h, --help              Show this help message
    --all                   Clean up all environments (default)
    --main                  Clean up main test environment only
    --vps                   Clean up VPS simulation only
    --dev                   Clean up development environment only
    --volumes               Remove volumes (WARNING: deletes all data)
    --prune                 Prune unused Docker resources
    --force                 Skip confirmation prompts

EXAMPLES:
    # Clean up all environments (keeps volumes)
    $0 --all

    # Clean up main environment including volumes
    $0 --main --volumes

    # Full cleanup including system prune
    $0 --all --volumes --prune --force

EOF
    exit 0
}

cleanup_environment() {
    local compose_file="$1"
    local name="$2"
    local remove_volumes="${3:-false}"

    if [[ ! -f "${compose_file}" ]]; then
        log_warn "${name} compose file not found: ${compose_file}"
        return 0
    fi

    log_info "Cleaning up ${name}..."

    # Stop containers
    if docker compose -f "${compose_file}" ps --format json 2>/dev/null | jq -e '.[].Name' &>/dev/null; then
        log_info "Stopping containers..."
        docker compose -f "${compose_file}" down --remove-orphans

        if [[ "${remove_volumes}" == "true" ]]; then
            log_warn "Removing volumes (data will be lost)..."
            docker compose -f "${compose_file}" down -v --remove-orphans
        fi

        log_success "${name} cleaned up"
    else
        log_info "${name} is not running"
    fi
}

prune_docker_resources() {
    log_warn "Pruning Docker resources..."

    # Prune containers
    log_info "Removing stopped containers..."
    docker container prune -f

    # Prune networks
    log_info "Removing unused networks..."
    docker network prune -f

    # Prune images
    log_info "Removing dangling images..."
    docker image prune -f

    # Prune build cache
    log_info "Removing build cache..."
    docker builder prune -f

    log_success "Docker resources pruned"
}

list_volumes() {
    log_info "Docker volumes created by test environments:"
    echo ""

    # List volumes
    docker volume ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}" | grep -E "chom|mentat|landsraad|richese|prometheus|loki|grafana|mysql|redis" || \
        log_info "No test volumes found"

    echo ""
}

confirm_action() {
    local message="$1"

    if [[ "${FORCE}" == "true" ]]; then
        return 0
    fi

    read -p "${message} (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    local clean_all=true
    local clean_main=false
    local clean_vps=false
    local clean_dev=false
    local remove_volumes=false
    local prune=false
    FORCE=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            --all)
                clean_all=true
                shift
                ;;
            --main)
                clean_all=false
                clean_main=true
                shift
                ;;
            --vps)
                clean_all=false
                clean_vps=true
                shift
                ;;
            --dev)
                clean_all=false
                clean_dev=true
                shift
                ;;
            --volumes)
                remove_volumes=true
                shift
                ;;
            --prune)
                prune=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    log_info "========================================================================"
    log_info "Docker Environment Cleanup"
    log_info "========================================================================"
    echo ""

    # Show current state
    list_volumes

    # Confirm if removing volumes
    if [[ "${remove_volumes}" == "true" ]]; then
        if ! confirm_action "WARNING: This will delete all data in volumes. Continue?"; then
            log_info "Cleanup cancelled"
            exit 0
        fi
    fi

    # Clean up environments
    if [[ "${clean_all}" == "true" ]] || [[ "${clean_main}" == "true" ]]; then
        cleanup_environment "${COMPOSE_MAIN}" "Main Test Environment" "${remove_volumes}"
    fi

    if [[ "${clean_all}" == "true" ]] || [[ "${clean_vps}" == "true" ]]; then
        cleanup_environment "${COMPOSE_VPS}" "VPS Simulation" "${remove_volumes}"
    fi

    if [[ "${clean_all}" == "true" ]] || [[ "${clean_dev}" == "true" ]]; then
        cleanup_environment "${COMPOSE_DEV}" "Development Environment" "${remove_volumes}"
    fi

    # Prune if requested
    if [[ "${prune}" == "true" ]]; then
        if confirm_action "Prune unused Docker resources?"; then
            prune_docker_resources
        fi
    fi

    echo ""
    log_info "========================================================================"
    log_success "Cleanup complete"
    log_info "========================================================================"
}

main "$@"
