#!/bin/bash
#===============================================================================
# Shared Library Bridge
#
# This file bridges deploy scripts with the main scripts/lib libraries.
# It sources commonly needed utilities from scripts/lib while providing
# fallback implementations for standalone deployment scenarios.
#
# Usage: source "$DEPLOY_LIB_DIR/shared.sh"
#
# This approach:
# - Eliminates code duplication between deploy/ and scripts/
# - Provides fallbacks when scripts/lib is unavailable
# - Maintains a single source of truth for common functions
#===============================================================================

# Guard against multiple sourcing
[[ -n "${DEPLOY_SHARED_LOADED:-}" ]] && return 0
DEPLOY_SHARED_LOADED=1

# Determine paths
DEPLOY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$DEPLOY_LIB_DIR")"
STACK_DIR="$(dirname "$DEPLOY_DIR")"
SCRIPTS_LIB_DIR="$STACK_DIR/scripts/lib"

#===============================================================================
# SHARED LIBRARIES FROM scripts/lib
#===============================================================================

# List of libraries to source from scripts/lib (in dependency order)
# These provide the canonical implementations of common functions
declare -a SHARED_LIBRARIES=(
    # Core utilities (no dependencies)
    # "common.sh"  # Too large, we'll selectively use functions

    # Focused modules
    "validation.sh"     # Input validation functions
    "yaml-parser.sh"    # YAML parsing with fallbacks
)

# Try to source shared libraries
_source_shared_libraries() {
    for lib in "${SHARED_LIBRARIES[@]}"; do
        local lib_path="$SCRIPTS_LIB_DIR/$lib"
        if [[ -f "$lib_path" ]]; then
            # shellcheck source=/dev/null
            source "$lib_path"
        fi
    done
}

#===============================================================================
# FALLBACK IMPLEMENTATIONS
# Used when scripts/lib is not available (e.g., standalone deployment)
#===============================================================================

# These functions are only defined if not already provided by scripts/lib

# Logging fallbacks (simple colored output)
if ! declare -f log_info >/dev/null 2>&1; then
    _RED='\033[0;31m'
    _GREEN='\033[0;32m'
    _YELLOW='\033[1;33m'
    _BLUE='\033[0;34m'
    _NC='\033[0m'

    log_info()    { echo -e "${_GREEN}[INFO]${_NC} $1"; }
    log_warn()    { echo -e "${_YELLOW}[WARN]${_NC} $1"; }
    log_error()   { echo -e "${_RED}[ERROR]${_NC} $1" >&2; }
    log_step()    { echo -e "${_BLUE}[STEP]${_NC} $1"; }
    log_success() { echo -e "${_GREEN}[OK]${_NC} $1"; }
    log_debug()   { [[ "${DEBUG:-false}" == "true" ]] && echo -e "[DEBUG] $1"; }
fi

# Version comparison fallback
if ! declare -f version_compare >/dev/null 2>&1; then
    # Compare two version strings
    # Returns: 0 if v1 == v2, 1 if v1 > v2, 2 if v1 < v2
    version_compare() {
        if [[ "$1" == "$2" ]]; then
            return 0
        fi
        local IFS=.
        local i v1=($1) v2=($2)
        for ((i=${#v1[@]}; i<${#v2[@]}; i++)); do v1[i]=0; done
        for ((i=0; i<${#v1[@]}; i++)); do
            [[ -z ${v2[i]} ]] && v2[i]=0
            if ((10#${v1[i]} > 10#${v2[i]})); then return 1; fi
            if ((10#${v1[i]} < 10#${v2[i]})); then return 2; fi
        done
        return 0
    }
fi

# Architecture detection fallback
if ! declare -f get_architecture >/dev/null 2>&1; then
    get_architecture() {
        local arch
        arch=$(uname -m)
        case $arch in
            x86_64)  echo "amd64" ;;
            aarch64) echo "arm64" ;;
            armv7l)  echo "armv7" ;;
            *)       echo "$arch" ;;
        esac
    }
fi

# Port availability check fallback
if ! declare -f check_port_available >/dev/null 2>&1; then
    check_port_available() {
        local port="$1"
        if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
            return 1
        fi
        return 0
    }
fi

# Service wait fallback
if ! declare -f wait_for_service >/dev/null 2>&1; then
    wait_for_service() {
        local service="$1"
        local max_wait="${2:-30}"
        local count=0

        while ! systemctl is-active --quiet "$service" 2>/dev/null; do
            sleep 1
            count=$((count + 1))
            if [[ $count -ge $max_wait ]]; then
                return 1
            fi
        done
        return 0
    }
fi

#===============================================================================
# INITIALIZATION
#===============================================================================

# Source shared libraries if available
if [[ -d "$SCRIPTS_LIB_DIR" ]]; then
    _source_shared_libraries
fi

# Export STACK_DIR for use by other scripts
export STACK_DIR
