#!/bin/bash
#===============================================================================
# Version Management Library
# Part of the observability-stack
#
# Provides robust version resolution, caching, and GitHub API integration
# for component version management.
#
# Features:
#   - Multiple version strategies (latest, pinned, lts, range)
#   - GitHub API integration with rate limiting
#   - Multi-layer caching for performance
#   - Offline mode support
#   - Semantic version comparison
#   - Compatibility checking
#
# Usage:
#   source scripts/lib/versions.sh
#   version=$(resolve_version "node_exporter")
#===============================================================================

set -euo pipefail

# Library metadata
VERSION_LIB_VERSION="1.0.0"

#===============================================================================
# CONFIGURATION
#===============================================================================

# Default paths
VERSION_CONFIG_FILE="${VERSION_CONFIG_FILE:-config/versions.yaml}"
VERSION_CACHE_DIR="${VERSION_CACHE_DIR:-${HOME}/.cache/observability-stack/versions}"
VERSION_CACHE_TTL="${VERSION_CACHE_TTL:-900}"  # 15 minutes
VERSION_CACHE_MAX_AGE="${VERSION_CACHE_MAX_AGE:-86400}"  # 24 hours

# GitHub API configuration
GITHUB_API_BASE="https://api.github.com"
GITHUB_API_TIMEOUT="${GITHUB_API_TIMEOUT:-10}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"  # Optional: increases rate limit

# Global settings
VERSION_OFFLINE_MODE="${VERSION_OFFLINE_MODE:-false}"
VERSION_DEBUG="${VERSION_DEBUG:-false}"
VERSION_DEFAULT_STRATEGY="${VERSION_DEFAULT_STRATEGY:-latest}"

# Internal state
_VERSION_CONFIG_LOADED=false
declare -A _VERSION_CONFIG=()

#===============================================================================
# LOGGING
#===============================================================================

_version_log() {
    local level="$1"
    shift
    local msg="$*"

    case "$level" in
        DEBUG)
            [[ "$VERSION_DEBUG" == "true" ]] && echo "[VERSION:DEBUG] $msg" >&2
            ;;
        INFO)
            echo "[VERSION:INFO] $msg" >&2
            ;;
        WARN)
            echo "[VERSION:WARN] $msg" >&2
            ;;
        ERROR)
            echo "[VERSION:ERROR] $msg" >&2
            ;;
        *)
            echo "[VERSION] $msg" >&2
            ;;
    esac
}

#===============================================================================
# VERSION VALIDATION
#===============================================================================

# Validate semantic version format
# Usage: validate_version <version>
# Returns: 0 if valid, 1 otherwise
validate_version() {
    local version="$1"

    # Remove 'v' prefix if present
    version="${version#v}"

    # Semantic version regex: MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]
    local semver_regex='^([0-9]+)\.([0-9]+)\.([0-9]+)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'

    if [[ "$version" =~ $semver_regex ]]; then
        return 0
    else
        _version_log ERROR "Invalid version format: $version"
        return 1
    fi
}

# Parse version into components
# Usage: parse_version <version>
# Returns: Sets PARSED_MAJOR, PARSED_MINOR, PARSED_PATCH, PARSED_PRERELEASE, PARSED_BUILD
parse_version() {
    local version="$1"

    # Remove 'v' prefix
    version="${version#v}"

    # Extract components
    local semver_regex='^([0-9]+)\.([0-9]+)\.([0-9]+)(-([0-9A-Za-z.-]+))?(\+([0-9A-Za-z.-]+))?$'

    if [[ "$version" =~ $semver_regex ]]; then
        PARSED_MAJOR="${BASH_REMATCH[1]}"
        PARSED_MINOR="${BASH_REMATCH[2]}"
        PARSED_PATCH="${BASH_REMATCH[3]}"
        PARSED_PRERELEASE="${BASH_REMATCH[5]:-}"
        PARSED_BUILD="${BASH_REMATCH[7]:-}"
        return 0
    else
        return 1
    fi
}

#===============================================================================
# VERSION COMPARISON
#===============================================================================

# Compare two semantic versions
# Usage: compare_versions <version1> <version2>
# Returns: 0 and echoes -1 (v1 < v2), 0 (v1 == v2), 1 (v1 > v2)
# Exit code: Always 0 for success, 1 for invalid input
compare_versions() {
    local v1="$1"
    local v2="$2"

    # Remove 'v' prefix
    v1="${v1#v}"
    v2="${v2#v}"

    # Parse versions
    local maj1 min1 pat1 pre1
    local maj2 min2 pat2 pre2

    if ! parse_version "$v1"; then
        _version_log ERROR "Invalid version 1: $v1"
        return 1
    fi
    maj1="$PARSED_MAJOR"
    min1="$PARSED_MINOR"
    pat1="$PARSED_PATCH"
    pre1="$PARSED_PRERELEASE"

    if ! parse_version "$v2"; then
        _version_log ERROR "Invalid version 2: $v2"
        return 1
    fi
    maj2="$PARSED_MAJOR"
    min2="$PARSED_MINOR"
    pat2="$PARSED_PATCH"
    pre2="$PARSED_PRERELEASE"

    # Compare major
    if [[ $maj1 -lt $maj2 ]]; then
        echo -1
        return 0
    elif [[ $maj1 -gt $maj2 ]]; then
        echo 1
        return 0
    fi

    # Compare minor
    if [[ $min1 -lt $min2 ]]; then
        echo -1
        return 0
    elif [[ $min1 -gt $min2 ]]; then
        echo 1
        return 0
    fi

    # Compare patch
    if [[ $pat1 -lt $pat2 ]]; then
        echo -1
        return 0
    elif [[ $pat1 -gt $pat2 ]]; then
        echo 1
        return 0
    fi

    # Compare pre-release (version without pre-release > version with pre-release)
    if [[ -z "$pre1" ]] && [[ -n "$pre2" ]]; then
        echo 1
        return 0
    elif [[ -n "$pre1" ]] && [[ -z "$pre2" ]]; then
        echo -1
        return 0
    elif [[ -n "$pre1" ]] && [[ -n "$pre2" ]]; then
        # Lexical comparison of pre-release identifiers
        if [[ "$pre1" < "$pre2" ]]; then
            echo -1
            return 0
        elif [[ "$pre1" > "$pre2" ]]; then
            echo 1
            return 0
        fi
    fi

    # Versions are equal
    echo 0
    return 0
}

# Check if version satisfies constraint
# Usage: version_satisfies <version> <constraint>
# Example: version_satisfies "1.8.0" ">=1.7.0"
# Returns: 0 if satisfied, 1 otherwise
version_satisfies() {
    local version="$1"
    local constraint="$2"

    # Remove 'v' prefix
    version="${version#v}"
    constraint="${constraint#v}"

    # Parse constraint operator and version
    local operator target_version

    if [[ "$constraint" =~ ^(>=|<=|>|<|=|==)(.+)$ ]]; then
        operator="${BASH_REMATCH[1]}"
        target_version="${BASH_REMATCH[2]}"
    elif [[ "$constraint" =~ ^([0-9]+\.[0-9]+\.[0-9]+.*)$ ]]; then
        # Exact version match (no operator)
        operator="="
        target_version="${BASH_REMATCH[1]}"
    else
        _version_log ERROR "Invalid constraint format: $constraint"
        return 1
    fi

    # Get comparison result
    local cmp_result
    cmp_result=$(compare_versions "$version" "$target_version") || return 1

    # Apply operator
    case "$operator" in
        "="|"==")
            [[ $cmp_result -eq 0 ]]
            ;;
        ">")
            [[ $cmp_result -eq 1 ]]
            ;;
        "<")
            [[ $cmp_result -eq -1 ]]
            ;;
        ">=")
            [[ $cmp_result -ge 0 ]]
            ;;
        "<=")
            [[ $cmp_result -le 0 ]]
            ;;
        *)
            _version_log ERROR "Unknown operator: $operator"
            return 1
            ;;
    esac
}

# Check if version satisfies range constraint
# Usage: version_in_range <version> <range>
# Example: version_in_range "1.8.0" ">=1.7.0 <2.0.0"
# Returns: 0 if in range, 1 otherwise
version_in_range() {
    local version="$1"
    local range="$2"

    # Split range into multiple constraints (space or comma separated)
    local constraints
    IFS=' ,' read -ra constraints <<< "$range"

    # All constraints must be satisfied
    local constraint
    for constraint in "${constraints[@]}"; do
        [[ -z "$constraint" ]] && continue
        if ! version_satisfies "$version" "$constraint"; then
            return 1
        fi
    done

    return 0
}

#===============================================================================
# CACHE MANAGEMENT
#===============================================================================

# Initialize cache directory
_init_cache() {
    if [[ ! -d "$VERSION_CACHE_DIR" ]]; then
        mkdir -p "$VERSION_CACHE_DIR"
        chmod 700 "$VERSION_CACHE_DIR"
    fi
}

# Get cache file path
_cache_file() {
    local component="$1"
    local key="$2"
    echo "$VERSION_CACHE_DIR/${component}/${key}.json"
}

# Check if cache entry is expired
_cache_is_expired() {
    local cache_file="$1"
    local ttl="${2:-$VERSION_CACHE_TTL}"

    [[ ! -f "$cache_file" ]] && return 0

    local file_age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)))
    [[ $file_age -gt $ttl ]]
}

# Get cached version info
# Usage: cache_get <component> <key>
# Returns: cached value or empty if not found/expired
cache_get() {
    local component="$1"
    local key="$2"
    local cache_file

    _init_cache
    cache_file=$(_cache_file "$component" "$key")

    if [[ -f "$cache_file" ]] && ! _cache_is_expired "$cache_file"; then
        _version_log DEBUG "Cache hit: $component/$key"
        cat "$cache_file"
        return 0
    else
        _version_log DEBUG "Cache miss: $component/$key"
        return 1
    fi
}

# Set cached version info
# Usage: cache_set <component> <key> <value>
cache_set() {
    local component="$1"
    local key="$2"
    local value="$3"
    local cache_file

    _init_cache

    local component_cache_dir="$VERSION_CACHE_DIR/$component"
    mkdir -p "$component_cache_dir"

    cache_file=$(_cache_file "$component" "$key")
    echo "$value" > "$cache_file"

    _version_log DEBUG "Cache set: $component/$key"
}

# Invalidate cache for component
# Usage: cache_invalidate <component>
cache_invalidate() {
    local component="$1"
    local component_cache_dir="$VERSION_CACHE_DIR/$component"

    if [[ -d "$component_cache_dir" ]]; then
        rm -rf "$component_cache_dir"
        _version_log INFO "Cache invalidated: $component"
    fi
}

# Clean expired cache entries
# Usage: cache_cleanup
cache_cleanup() {
    _init_cache

    local cleaned=0
    while IFS= read -r -d '' cache_file; do
        if _cache_is_expired "$cache_file" "$VERSION_CACHE_MAX_AGE"; then
            rm -f "$cache_file"
            ((cleaned++)) || true
        fi
    done < <(find "$VERSION_CACHE_DIR" -type f -name "*.json" -print0 2>/dev/null)

    [[ $cleaned -gt 0 ]] && _version_log INFO "Cleaned $cleaned expired cache entries"
}

#===============================================================================
# GITHUB API INTEGRATION
#===============================================================================

# Call GitHub API
# Usage: _github_api_call <endpoint>
# Returns: JSON response
_github_api_call() {
    local endpoint="$1"
    local url="${GITHUB_API_BASE}${endpoint}"

    local curl_opts=(-fsSL --max-time "$GITHUB_API_TIMEOUT")

    # Add authentication if token available
    if [[ -n "$GITHUB_TOKEN" ]]; then
        curl_opts+=(-H "Authorization: token $GITHUB_TOKEN")
    fi

    local response
    if ! response=$(curl "${curl_opts[@]}" "$url" 2>&1); then
        _version_log ERROR "GitHub API call failed: $endpoint"
        return 1
    fi

    # Check for rate limit error
    if echo "$response" | grep -q '"message".*"rate limit"'; then
        _version_log WARN "GitHub API rate limit exceeded"
        return 2
    fi

    echo "$response"
}

# Get GitHub API rate limit status
# Usage: github_rate_limit_status
# Returns: Prints rate limit info
github_rate_limit_status() {
    local response
    if response=$(_github_api_call "/rate_limit"); then
        echo "$response" | python3 -c "
import sys, json
data = json.load(sys.stdin)
core = data.get('resources', {}).get('core', {})
print(f\"Rate Limit: {core.get('remaining', 0)}/{core.get('limit', 0)}\")
print(f\"Reset: {core.get('reset', 0)}\")
" 2>/dev/null || echo "$response"
    else
        echo "Unable to fetch rate limit status"
    fi
}

# Fetch latest release from GitHub
# Usage: github_latest_release <repo>
# Example: github_latest_release "prometheus/node_exporter"
# Returns: JSON response
github_latest_release() {
    local repo="$1"
    local endpoint="/repos/${repo}/releases/latest"

    _github_api_call "$endpoint"
}

# Fetch all releases from GitHub
# Usage: github_list_releases <repo> [limit]
# Returns: JSON array of releases
github_list_releases() {
    local repo="$1"
    local limit="${2:-50}"
    local endpoint="/repos/${repo}/releases?per_page=${limit}"

    _github_api_call "$endpoint"
}

# Extract version from GitHub release JSON
# Usage: github_extract_version <json>
# Returns: version string (without 'v' prefix)
github_extract_version() {
    local json="$1"

    local version
    version=$(echo "$json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
tag = data.get('tag_name', '')
print(tag.lstrip('v'))
" 2>/dev/null)

    if [[ -z "$version" ]]; then
        _version_log ERROR "Failed to extract version from GitHub response"
        return 1
    fi

    echo "$version"
}

# Filter releases by criteria
# Usage: _github_filter_releases <json> <exclude_prerelease>
# Returns: Filtered JSON array
_github_filter_releases() {
    local json="$1"
    local exclude_prerelease="${2:-true}"

    echo "$json" | python3 -c "
import sys, json
releases = json.load(sys.stdin)
exclude_pre = '$exclude_prerelease' == 'true'

filtered = [
    r for r in releases
    if not (exclude_pre and r.get('prerelease', False))
]

json.dump(filtered, sys.stdout)
" 2>/dev/null
}

#===============================================================================
# CONFIGURATION LOADING
#===============================================================================

# Load version configuration from YAML
# Usage: load_version_config
load_version_config() {
    [[ "$_VERSION_CONFIG_LOADED" == "true" ]] && return 0

    if [[ ! -f "$VERSION_CONFIG_FILE" ]]; then
        _version_log DEBUG "Version config file not found: $VERSION_CONFIG_FILE"
        _VERSION_CONFIG_LOADED=true
        return 0
    fi

    _version_log DEBUG "Loading version config: $VERSION_CONFIG_FILE"

    # Parse YAML (basic implementation - could use yq for complex cases)
    # For now, we'll use a simple grep-based parser for key values

    _VERSION_CONFIG_LOADED=true
}

# Get configuration value
# Usage: _config_get <component> <key> [default]
_config_get() {
    local component="$1"
    local key="$2"
    local default="${3:-}"

    load_version_config

    # Try component-specific config
    local config_key="components.${component}.${key}"
    local value

    # Simple YAML parser (works for basic key: value pairs)
    if [[ -f "$VERSION_CONFIG_FILE" ]]; then
        # Look for component section and key
        value=$(awk -v comp="$component" -v key="$key" '
            /^components:/ { in_components=1; next }
            in_components && $0 ~ "^  " comp ":" { in_component=1; next }
            in_component && $0 ~ "^    " key ":" {
                sub(/^    '"$key"': */, "")
                gsub(/^["'\'']|["'\'']$/, "")
                print
                exit
            }
            in_component && /^  [a-z]/ { in_component=0 }
            /^[a-z]/ { in_components=0 }
        ' "$VERSION_CONFIG_FILE")
    fi

    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# Get GitHub repo for component
# Usage: get_github_repo <component>
get_github_repo() {
    local component="$1"
    _config_get "$component" "github_repo" ""
}

# Get version strategy for component
# Usage: get_version_strategy <component>
# Returns: strategy name (latest/pinned/lts/range)
get_version_strategy() {
    local component="$1"
    _config_get "$component" "strategy" "$VERSION_DEFAULT_STRATEGY"
}

# Get fallback version from config
# Usage: get_config_version <component>
# Returns: version string from config
get_config_version() {
    local component="$1"

    local strategy
    strategy=$(get_version_strategy "$component")

    case "$strategy" in
        pinned)
            # For pinned strategy, use the exact version
            _config_get "$component" "version" ""
            ;;
        *)
            # For other strategies, use fallback_version
            _config_get "$component" "fallback_version" ""
            ;;
    esac
}

#===============================================================================
# VERSION RESOLUTION
#===============================================================================

# Get latest version from GitHub with caching
# Usage: get_latest_version <component>
# Returns: version string
get_latest_version() {
    local component="$1"

    # Check if offline mode
    if [[ "$VERSION_OFFLINE_MODE" == "true" ]]; then
        _version_log DEBUG "Offline mode: skipping GitHub API"
        return 1
    fi

    # Try cache first
    local cached_version
    if cached_version=$(cache_get "$component" "latest"); then
        local version
        version=$(echo "$cached_version" | python3 -c "import sys,json; print(json.load(sys.stdin).get('version',''))" 2>/dev/null)
        if [[ -n "$version" ]]; then
            _version_log DEBUG "Using cached latest version for $component: $version"
            echo "$version"
            return 0
        fi
    fi

    # Get GitHub repo
    local repo
    repo=$(get_github_repo "$component")
    if [[ -z "$repo" ]]; then
        _version_log WARN "No GitHub repo configured for $component"
        return 1
    fi

    # Fetch from GitHub API
    _version_log DEBUG "Fetching latest release for $component from GitHub"
    local release_json
    if ! release_json=$(github_latest_release "$repo"); then
        _version_log WARN "Failed to fetch latest release for $component"
        return 1
    fi

    # Extract version
    local version
    if ! version=$(github_extract_version "$release_json"); then
        return 1
    fi

    # Cache the result
    local cache_data
    cache_data=$(cat <<EOF
{
  "version": "$version",
  "fetched_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "source": "github"
}
EOF
)
    cache_set "$component" "latest" "$cache_data"

    echo "$version"
}

# Get version from module manifest
# Usage: get_manifest_version <component>
# Returns: version string from module.yaml
get_manifest_version() {
    local component="$1"

    # Try to find module manifest
    local module_manifest
    if [[ -f "modules/_core/${component}/module.yaml" ]]; then
        module_manifest="modules/_core/${component}/module.yaml"
    elif [[ -f "modules/${component}/module.yaml" ]]; then
        module_manifest="modules/${component}/module.yaml"
    else
        _version_log DEBUG "No module manifest found for $component"
        return 1
    fi

    # Extract version from manifest
    local version
    version=$(awk '/^module:/,/^[^ ]/ {
        if ($1 == "version:") {
            gsub(/^[" '\'']+|[" '\'']+$/, "", $2)
            print $2
            exit
        }
    }' "$module_manifest")

    if [[ -n "$version" ]]; then
        _version_log DEBUG "Manifest version for $component: $version"
        echo "$version"
        return 0
    fi

    return 1
}

# Resolve version for a component using configured strategy
# Usage: resolve_version <component> [strategy_override]
# Returns: version string (e.g., "1.7.0")
# Exit codes: 0=success, 1=error
resolve_version() {
    local component="$1"
    local strategy_override="${2:-}"

    # Check for environment variable override
    local env_var="VERSION_OVERRIDE_${component^^}"
    env_var="${env_var//-/_}"  # Replace hyphens with underscores
    if [[ -n "${!env_var:-}" ]]; then
        local override_version="${!env_var}"
        _version_log INFO "Using environment override for $component: $override_version"
        echo "$override_version"
        return 0
    fi

    # Determine strategy
    local strategy="${strategy_override:-$(get_version_strategy "$component")}"
    _version_log DEBUG "Resolving version for $component using strategy: $strategy"

    local version=""

    case "$strategy" in
        latest)
            # Try GitHub API, fallback to config, then manifest
            version=$(get_latest_version "$component") || \
            version=$(get_config_version "$component") || \
            version=$(get_manifest_version "$component")
            ;;

        pinned)
            # Use exact version from config, fallback to manifest
            version=$(get_config_version "$component") || \
            version=$(get_manifest_version "$component")
            ;;

        range)
            # Get range constraint and find matching version
            local range
            range=$(_config_get "$component" "version_range" "")
            if [[ -z "$range" ]]; then
                _version_log ERROR "No version_range specified for $component with range strategy"
                version=$(get_manifest_version "$component")
            else
                # For now, get latest and check if it matches range
                # TODO: Implement full range resolution with GitHub releases list
                local latest
                latest=$(get_latest_version "$component")
                if [[ -n "$latest" ]] && version_in_range "$latest" "$range"; then
                    version="$latest"
                else
                    _version_log WARN "Latest version $latest not in range $range"
                    version=$(get_config_version "$component") || \
                    version=$(get_manifest_version "$component")
                fi
            fi
            ;;

        lts)
            # For now, treat LTS same as latest
            # TODO: Implement LTS detection logic
            _version_log DEBUG "LTS strategy not fully implemented, using latest"
            version=$(get_latest_version "$component") || \
            version=$(get_config_version "$component") || \
            version=$(get_manifest_version "$component")
            ;;

        *)
            _version_log ERROR "Unknown version strategy: $strategy"
            version=$(get_manifest_version "$component")
            ;;
    esac

    if [[ -z "$version" ]]; then
        _version_log ERROR "Failed to resolve version for $component"
        return 1
    fi

    # Validate version format
    if ! validate_version "$version"; then
        _version_log ERROR "Resolved invalid version for $component: $version"
        return 1
    fi

    _version_log INFO "Resolved version for $component: $version (strategy: $strategy)"
    echo "$version"
    return 0
}

#===============================================================================
# COMPATIBILITY CHECKING
#===============================================================================

# Check if version is compatible with other components
# Usage: is_version_compatible <component> <version>
# Returns: 0 if compatible, 1 otherwise
is_version_compatible() {
    local component="$1"
    local version="$2"

    # Load compatibility matrix from config
    # For now, return success (assume compatible)
    # TODO: Implement compatibility matrix checking

    _version_log DEBUG "Compatibility check for $component $version: OK"
    return 0
}

#===============================================================================
# UTILITY FUNCTIONS
#===============================================================================

# Print version information
# Usage: print_version_info <component>
print_version_info() {
    local component="$1"

    echo "Version Information for: $component"
    echo "========================================"

    local strategy
    strategy=$(get_version_strategy "$component")
    echo "Strategy: $strategy"

    local resolved
    if resolved=$(resolve_version "$component"); then
        echo "Resolved: $resolved"
    else
        echo "Resolved: (failed)"
    fi

    local config_ver
    if config_ver=$(get_config_version "$component"); then
        echo "Config:   $config_ver"
    fi

    local manifest_ver
    if manifest_ver=$(get_manifest_version "$component"); then
        echo "Manifest: $manifest_ver"
    fi

    local latest_ver
    if latest_ver=$(get_latest_version "$component" 2>/dev/null); then
        echo "Latest:   $latest_ver"
    fi

    echo ""
}

# Update version cache from GitHub
# Usage: update_version_cache <component>
update_version_cache() {
    local component="$1"

    _version_log INFO "Updating version cache for $component"

    # Invalidate existing cache
    cache_invalidate "$component"

    # Fetch fresh data
    if get_latest_version "$component" >/dev/null 2>&1; then
        _version_log INFO "Cache updated successfully for $component"
        return 0
    else
        _version_log ERROR "Failed to update cache for $component"
        return 1
    fi
}

# Validate component configuration
# Usage: validate_component_config <component>
# Returns: 0 if valid, 1 otherwise
validate_component_config() {
    local component="$1"
    local errors=()

    # Check if strategy is valid
    local strategy
    strategy=$(get_version_strategy "$component")
    case "$strategy" in
        latest|pinned|lts|range)
            ;;
        *)
            errors+=("Invalid strategy: $strategy")
            ;;
    esac

    # Check strategy-specific requirements
    case "$strategy" in
        pinned)
            local version
            version=$(get_config_version "$component")
            if [[ -z "$version" ]]; then
                errors+=("Pinned strategy requires 'version' to be set")
            fi
            ;;
        range)
            local range
            range=$(_config_get "$component" "version_range" "")
            if [[ -z "$range" ]]; then
                errors+=("Range strategy requires 'version_range' to be set")
            fi
            ;;
    esac

    # Report errors
    if [[ ${#errors[@]} -gt 0 ]]; then
        _version_log ERROR "Configuration validation failed for $component:"
        for error in "${errors[@]}"; do
            _version_log ERROR "  - $error"
        done
        return 1
    fi

    _version_log DEBUG "Configuration valid for $component"
    return 0
}

#===============================================================================
# INITIALIZATION
#===============================================================================

# Auto-cleanup on load (if enabled)
if [[ "${VERSION_AUTO_CLEANUP:-true}" == "true" ]]; then
    cache_cleanup 2>/dev/null || true
fi

_version_log DEBUG "Version management library loaded (v${VERSION_LIB_VERSION})"
