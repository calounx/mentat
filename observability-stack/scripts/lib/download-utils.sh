#!/bin/bash
#===============================================================================
# Download Utilities - Safe downloads with timeouts and retries
#===============================================================================

# Guard against multiple sourcing
[[ -n "${DOWNLOAD_UTILS_LOADED:-}" ]] && return 0
DOWNLOAD_UTILS_LOADED=1

# Source common if available
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/common.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
else
    # Minimal fallback logging
    log_debug() { [[ "${DEBUG:-false}" == "true" ]] && echo "[DEBUG] $1" >&2; }
    log_error() { echo "[ERROR] $1" >&2; }
fi

#===============================================================================
# DOWNLOAD FUNCTIONS
#===============================================================================

# Safe download with timeouts and retries
# Usage: safe_download "url" "output_file" [timeout] [retries]
# Returns: 0 on success, 1 on failure
safe_download() {
    local url="$1"
    local output="$2"
    local timeout="${3:-30}"
    local retries="${4:-3}"

    if [[ -z "$url" ]] || [[ -z "$output" ]]; then
        log_error "safe_download: URL and output file required"
        return 1
    fi

    log_debug "Downloading $url to $output (timeout=${timeout}s, retries=$retries)"

    # Prefer wget
    if command -v wget &>/dev/null; then
        if wget --timeout="$timeout" --tries="$retries" --progress=bar:force \
               "$url" -O "$output" 2>&1; then
            log_debug "Download successful: $output"
            return 0
        else
            log_error "wget failed to download $url"
            rm -f "$output"
            return 1
        fi
    # Fallback to curl
    elif command -v curl &>/dev/null; then
        if curl --max-time "$timeout" --retry "$((retries - 1))" --retry-delay 2 \
               --progress-bar --location "$url" -o "$output" 2>&1; then
            log_debug "Download successful: $output"
            return 0
        else
            log_error "curl failed to download $url"
            rm -f "$output"
            return 1
        fi
    else
        log_error "Neither wget nor curl available for download"
        return 1
    fi
}

# Quiet download (no progress output)
# Usage: quiet_download "url" "output_file" [timeout] [retries]
quiet_download() {
    local url="$1"
    local output="$2"
    local timeout="${3:-30}"
    local retries="${4:-3}"

    if [[ -z "$url" ]] || [[ -z "$output" ]]; then
        log_error "quiet_download: URL and output file required"
        return 1
    fi

    log_debug "Downloading $url to $output (quiet mode)"

    # Prefer wget
    if command -v wget &>/dev/null; then
        if wget --quiet --timeout="$timeout" --tries="$retries" \
               "$url" -O "$output" 2>&1; then
            return 0
        else
            rm -f "$output"
            return 1
        fi
    # Fallback to curl
    elif command -v curl &>/dev/null; then
        if curl --silent --max-time "$timeout" --retry "$((retries - 1))" \
               --retry-delay 2 --location "$url" -o "$output" 2>&1; then
            return 0
        else
            rm -f "$output"
            return 1
        fi
    else
        log_error "Neither wget nor curl available for download"
        return 1
    fi
}

# Check URL accessibility
# Usage: check_url "url" [timeout]
# Returns: 0 if accessible, 1 otherwise
check_url() {
    local url="$1"
    local timeout="${2:-10}"

    if command -v curl &>/dev/null; then
        curl --silent --head --fail --max-time "$timeout" "$url" &>/dev/null
        return $?
    elif command -v wget &>/dev/null; then
        wget --spider --quiet --timeout="$timeout" "$url" &>/dev/null
        return $?
    else
        log_error "Neither wget nor curl available for URL check"
        return 1
    fi
}
