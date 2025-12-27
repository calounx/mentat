# Dynamic Version Management - Implementation Guide

## Overview

This guide provides step-by-step instructions for implementing the dynamic version management system. It complements the architecture document with practical implementation details.

---

## File Structure

```
observability-stack/
├── config/
│   ├── global.yaml                    # Existing global config
│   └── versions.yaml                  # Version management config (EXISTING)
│
├── scripts/
│   ├── lib/
│   │   ├── versions.sh               # Core version library (EXISTING - ENHANCE)
│   │   ├── github-api.sh             # GitHub API client (NEW)
│   │   ├── safety-checks.sh          # Safety validation (NEW)
│   │   ├── rollback.sh               # Rollback functions (NEW)
│   │   └── state-db.sh               # Database operations (NEW)
│   │
│   ├── version-management/
│   │   ├── check-upgrades.sh         # Check for available upgrades (NEW)
│   │   ├── upgrade-component.sh      # Upgrade single component (NEW)
│   │   ├── upgrade-all.sh            # Upgrade all components (NEW)
│   │   ├── rollback-component.sh     # Execute rollback (NEW)
│   │   ├── list-versions.sh          # List installed/available versions (NEW)
│   │   ├── update-cache.sh           # Update version cache (NEW)
│   │   └── cleanup-rollback.sh       # Cleanup old rollback points (NEW)
│   │
│   ├── init-state-db.sh              # Initialize state database (NEW)
│   └── setup-observability.sh        # Existing - UPDATE to use version lib
│
├── state/                             # NEW directory
│   ├── state.db                      # SQLite database (auto-created)
│   └── rollback/                     # Rollback point storage
│       ├── node_exporter/
│       │   ├── 1.7.0/
│       │   │   ├── binary
│       │   │   ├── config.yaml
│       │   │   └── metadata.json
│       │   └── 1.6.0/
│       │       └── ...
│       └── promtail/
│           └── ...
│
├── cache/                            # Cache directory (can be ~/.cache)
│   └── versions/
│       ├── index.json
│       ├── node_exporter/
│       │   ├── latest.json
│       │   ├── releases.json
│       │   └── metadata.json
│       └── ...
│
└── docs/
    ├── DYNAMIC_VERSION_MANAGEMENT_DESIGN.md        # Architecture (THIS DOC)
    ├── VERSION_MANAGEMENT_IMPLEMENTATION_GUIDE.md  # This guide
    └── VERSION_MANAGEMENT_ARCHITECTURE.md          # Existing base architecture
```

---

## Implementation Phases

### Phase 1: Core Infrastructure (Week 1)

#### Task 1.1: Enhance Version Library

**File:** `/home/calounx/repositories/mentat/observability-stack/scripts/lib/versions.sh`

**Status:** EXISTS - Needs enhancement

**Enhancements needed:**
```bash
# Add to existing versions.sh

#===============================================================================
# UPGRADE DECISION ENGINE
#===============================================================================

assess_upgrade_risk() {
    local component="$1"
    local current="$2"
    local target="$3"

    # Parse version components
    parse_version "$current"
    local current_major="$PARSED_MAJOR"
    local current_minor="$PARSED_MINOR"

    parse_version "$target"
    local target_major="$PARSED_MAJOR"
    local target_minor="$PARSED_MINOR"

    # Determine risk level
    if [[ $target_major -gt $current_major ]]; then
        echo "high"
    elif [[ $target_minor -gt $current_minor ]]; then
        echo "medium"
    else
        echo "low"
    fi
}

check_upgrade_safety() {
    local component="$1"
    local current_version="$2"
    local target_version="$3"

    local result='{"approved": false, "risk_level": "unknown", "checks": []}'

    # Risk assessment
    local risk_level
    risk_level=$(assess_upgrade_risk "$component" "$current_version" "$target_version")
    result=$(echo "$result" | jq --arg risk "$risk_level" '.risk_level = $risk')

    # Compatibility check
    if check_compatibility "$component" "$target_version"; then
        result=$(echo "$result" | jq '.checks += [{"name": "compatibility", "passed": true}]')
    else
        result=$(echo "$result" | jq '.checks += [{"name": "compatibility", "passed": false}]')
        echo "$result"
        return 1
    fi

    # Breaking changes check
    local breaking_changes
    breaking_changes=$(detect_breaking_changes "$component" "$current_version" "$target_version")
    if [[ -n "$breaking_changes" ]]; then
        result=$(echo "$result" | jq --arg changes "$breaking_changes" \
            '.checks += [{"name": "breaking_changes", "passed": false, "details": $changes}]')

        # High risk if breaking changes found
        if [[ "$risk_level" == "low" ]]; then
            risk_level="medium"
            result=$(echo "$result" | jq '.risk_level = "medium"')
        fi
    else
        result=$(echo "$result" | jq '.checks += [{"name": "breaking_changes", "passed": true}]')
    fi

    # Auto-approve low risk upgrades
    if [[ "$risk_level" == "low" ]]; then
        result=$(echo "$result" | jq '.approved = true')
    fi

    echo "$result"
    return 0
}
```

#### Task 1.2: Create GitHub API Client

**File:** `/home/calounx/repositories/mentat/observability-stack/scripts/lib/github-api.sh`

**Status:** NEW

**Implementation:**
```bash
#!/bin/bash
#===============================================================================
# GitHub API Client Library
# Handles rate limiting, caching, and error handling
#===============================================================================

set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/versions.sh"

#===============================================================================
# CONFIGURATION
#===============================================================================

GITHUB_API_BASE="https://api.github.com"
GITHUB_API_TIMEOUT="${GITHUB_API_TIMEOUT:-10}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

#===============================================================================
# RATE LIMIT MANAGEMENT
#===============================================================================

check_rate_limit() {
    local rate_limit_url="${GITHUB_API_BASE}/rate_limit"
    local headers=()

    if [[ -n "$GITHUB_TOKEN" ]]; then
        headers=(-H "Authorization: token $GITHUB_TOKEN")
    fi

    local response
    response=$(curl -s --max-time "$GITHUB_API_TIMEOUT" "${headers[@]}" "$rate_limit_url" 2>/dev/null || echo "{}")

    local remaining
    local reset_time
    remaining=$(echo "$response" | jq -r '.rate.remaining // 0')
    reset_time=$(echo "$response" | jq -r '.rate.reset // 0')

    if [[ "$remaining" -lt 5 ]]; then
        local reset_in=$((reset_time - $(date +%s)))
        _version_log WARN "GitHub API rate limit low: $remaining requests remaining"
        _version_log WARN "Resets in $((reset_in / 60)) minutes"
        return 1
    fi

    _version_log DEBUG "GitHub API rate limit: $remaining requests remaining"
    return 0
}

#===============================================================================
# API REQUESTS
#===============================================================================

github_api_get() {
    local endpoint="$1"
    local url="${GITHUB_API_BASE}${endpoint}"

    local headers=()
    if [[ -n "$GITHUB_TOKEN" ]]; then
        headers=(-H "Authorization: token $GITHUB_TOKEN")
    fi

    headers+=(-H "Accept: application/vnd.github+json")

    local response
    local http_code

    # Make request with timeout
    response=$(curl -s -w "\n%{http_code}" --max-time "$GITHUB_API_TIMEOUT" \
        "${headers[@]}" "$url" 2>/dev/null || echo -e "\n000")

    http_code=$(echo "$response" | tail -1)
    response=$(echo "$response" | sed '$d')

    case "$http_code" in
        200)
            echo "$response"
            return 0
            ;;
        403)
            _version_log ERROR "GitHub API rate limited or forbidden"
            return 1
            ;;
        404)
            _version_log ERROR "GitHub API endpoint not found: $endpoint"
            return 1
            ;;
        000)
            _version_log ERROR "GitHub API request timeout or network error"
            return 1
            ;;
        *)
            _version_log ERROR "GitHub API returned HTTP $http_code"
            return 1
            ;;
    esac
}

#===============================================================================
# VERSION DISCOVERY
#===============================================================================

github_get_latest_release() {
    local repo="$1"
    local endpoint="/repos/${repo}/releases/latest"

    # Check cache first
    local cache_key="latest_release"
    local cached
    cached=$(get_from_file_cache "github_${repo//\//_}" "$cache_key" 2>/dev/null || echo "")

    if [[ -n "$cached" ]]; then
        _version_log DEBUG "Using cached latest release for $repo"
        echo "$cached"
        return 0
    fi

    # Check rate limit before API call
    if ! check_rate_limit; then
        _version_log WARN "Rate limit exceeded, using cached data only"
        return 1
    fi

    # Fetch from API
    local response
    if response=$(github_api_get "$endpoint"); then
        # Cache the response
        set_file_cache "github_${repo//\//_}" "$cache_key" "$response"
        echo "$response"
        return 0
    fi

    return 1
}

github_list_releases() {
    local repo="$1"
    local per_page="${2:-30}"
    local endpoint="/repos/${repo}/releases?per_page=${per_page}"

    # Check cache
    local cache_key="releases_list"
    local cached
    cached=$(get_from_file_cache "github_${repo//\//_}" "$cache_key" 2>/dev/null || echo "")

    if [[ -n "$cached" ]]; then
        _version_log DEBUG "Using cached releases list for $repo"
        echo "$cached"
        return 0
    fi

    # Check rate limit
    if ! check_rate_limit; then
        return 1
    fi

    # Fetch from API
    local response
    if response=$(github_api_get "$endpoint"); then
        # Cache the response
        set_file_cache "github_${repo//\//_}" "$cache_key" "$response"
        echo "$response"
        return 0
    fi

    return 1
}

github_get_release_by_tag() {
    local repo="$1"
    local tag="$2"
    local endpoint="/repos/${repo}/releases/tags/${tag}"

    # Fetch from API
    github_api_get "$endpoint"
}

#===============================================================================
# VERSION EXTRACTION
#===============================================================================

extract_version_from_release() {
    local release_json="$1"

    # Extract tag_name and remove 'v' prefix
    local version
    version=$(echo "$release_json" | jq -r '.tag_name // empty')

    if [[ -z "$version" ]]; then
        return 1
    fi

    # Remove 'v' prefix if present
    version="${version#v}"

    echo "$version"
}

filter_stable_releases() {
    local releases_json="$1"

    # Filter out pre-releases and drafts
    echo "$releases_json" | jq '[.[] | select(.prerelease == false and .draft == false)]'
}

get_download_url_from_release() {
    local release_json="$1"
    local pattern="$2"

    # Find matching asset
    echo "$release_json" | jq -r \
        --arg pattern "$pattern" \
        '.assets[] | select(.name | test($pattern)) | .browser_download_url'
}

get_checksum_url_from_release() {
    local release_json="$1"

    # Look for common checksum file names
    echo "$release_json" | jq -r \
        '.assets[] | select(.name | test("sha256|checksums|SHA256SUMS")) | .browser_download_url' \
        | head -1
}

#===============================================================================
# CHANGELOG EXTRACTION
#===============================================================================

get_release_notes() {
    local release_json="$1"

    echo "$release_json" | jq -r '.body // empty'
}

get_changelog_between_versions() {
    local repo="$1"
    local from_version="$2"
    local to_version="$3"

    # Fetch all releases
    local releases
    releases=$(github_list_releases "$repo" 100)

    if [[ -z "$releases" ]]; then
        return 1
    fi

    # Extract releases between versions
    local changelog=""
    local in_range=false

    while read -r release; do
        local version
        version=$(extract_version_from_release "$release")

        # Check if we're in the range
        if [[ "$version" == "$to_version" ]]; then
            in_range=true
        fi

        if [[ "$in_range" == "true" ]]; then
            local notes
            notes=$(get_release_notes "$release")
            changelog+="## Version $version\n$notes\n\n"
        fi

        if [[ "$version" == "$from_version" ]]; then
            break
        fi
    done < <(echo "$releases" | jq -c '.[]')

    if [[ -n "$changelog" ]]; then
        echo -e "$changelog"
        return 0
    fi

    return 1
}
```

#### Task 1.3: Create State Database Library

**File:** `/home/calounx/repositories/mentat/observability-stack/scripts/lib/state-db.sh`

**Status:** NEW

**Implementation:**
```bash
#!/bin/bash
#===============================================================================
# State Database Management Library
# Handles all database operations for version state tracking
#===============================================================================

set -euo pipefail

#===============================================================================
# CONFIGURATION
#===============================================================================

STATE_DB_DIR="${STATE_DB_DIR:-/var/lib/observability-stack}"
STATE_DB_PATH="${STATE_DB_PATH:-${STATE_DB_DIR}/state.db}"

#===============================================================================
# DATABASE INITIALIZATION
#===============================================================================

init_state_database() {
    # Create directory
    mkdir -p "$STATE_DB_DIR"

    # Create database if not exists
    if [[ ! -f "$STATE_DB_PATH" ]]; then
        _version_log INFO "Initializing state database: $STATE_DB_PATH"
        create_database_schema
    else
        _version_log DEBUG "State database exists: $STATE_DB_PATH"
    fi
}

create_database_schema() {
    sqlite3 "$STATE_DB_PATH" <<'SQL'
-- Installed components
CREATE TABLE IF NOT EXISTS installed_components (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    component TEXT NOT NULL UNIQUE,
    version TEXT NOT NULL,
    installed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    install_method TEXT,
    binary_path TEXT,
    config_path TEXT,
    service_name TEXT,
    checksum TEXT,
    metadata JSON
);

CREATE INDEX IF NOT EXISTS idx_component ON installed_components(component);

-- Upgrade history
CREATE TABLE IF NOT EXISTS upgrade_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    component TEXT NOT NULL,
    from_version TEXT,
    to_version TEXT NOT NULL,
    upgraded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    upgrade_method TEXT,
    success BOOLEAN NOT NULL,
    error_message TEXT,
    downtime_seconds INTEGER,
    rollback_point_id INTEGER,
    changelog TEXT
);

CREATE INDEX IF NOT EXISTS idx_upgrade_history ON upgrade_history(component, upgraded_at DESC);

-- Rollback points
CREATE TABLE IF NOT EXISTS rollback_points (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    component TEXT NOT NULL,
    version TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    binary_backup_path TEXT NOT NULL,
    config_backup_path TEXT,
    state_snapshot JSON,
    expires_at TIMESTAMP,
    size_bytes INTEGER
);

CREATE INDEX IF NOT EXISTS idx_rollback ON rollback_points(component, created_at DESC);

-- Version cache
CREATE TABLE IF NOT EXISTS version_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    component TEXT NOT NULL,
    cache_key TEXT NOT NULL,
    cache_value TEXT,
    cached_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ttl INTEGER NOT NULL,
    expires_at TIMESTAMP,
    UNIQUE(component, cache_key)
);

CREATE INDEX IF NOT EXISTS idx_cache ON version_cache(component, cache_key);
CREATE INDEX IF NOT EXISTS idx_cache_expires ON version_cache(expires_at);

-- Compatibility matrix
CREATE TABLE IF NOT EXISTS compatibility_matrix (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    component TEXT NOT NULL,
    version_constraint TEXT NOT NULL,
    requires_component TEXT NOT NULL,
    requires_version_constraint TEXT NOT NULL,
    reason TEXT
);

-- Breaking changes
CREATE TABLE IF NOT EXISTS breaking_changes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    component TEXT NOT NULL,
    from_version TEXT NOT NULL,
    to_version TEXT NOT NULL,
    change_type TEXT,
    description TEXT NOT NULL,
    migration_guide TEXT,
    severity TEXT
);

CREATE INDEX IF NOT EXISTS idx_breaking ON breaking_changes(component, from_version, to_version);
SQL

    _version_log INFO "Database schema created successfully"
}

#===============================================================================
# INSTALLED COMPONENTS
#===============================================================================

record_installation() {
    local component="$1"
    local version="$2"
    local metadata="${3:-{}}"

    init_state_database

    sqlite3 "$STATE_DB_PATH" <<SQL
INSERT OR REPLACE INTO installed_components (
    component, version, install_method,
    binary_path, config_path, service_name, metadata
) VALUES (
    '$component',
    '$version',
    'manual',
    '$(get_install_path "$component")',
    '$(get_config_path "$component")',
    '${component}',
    '$metadata'
);
SQL

    _version_log INFO "Recorded installation: $component $version"
}

get_installed_version_from_db() {
    local component="$1"

    init_state_database

    sqlite3 "$STATE_DB_PATH" \
        "SELECT version FROM installed_components WHERE component = '$component';"
}

#===============================================================================
# UPGRADE HISTORY
#===============================================================================

record_upgrade() {
    local component="$1"
    local from_version="$2"
    local to_version="$3"
    local success="$4"
    local error_msg="${5:-}"

    init_state_database

    sqlite3 "$STATE_DB_PATH" <<SQL
INSERT INTO upgrade_history (
    component, from_version, to_version,
    upgrade_method, success, error_message
) VALUES (
    '$component', '$from_version', '$to_version',
    'manual', $success, '$error_msg'
);
SQL
}

get_upgrade_history() {
    local component="$1"
    local limit="${2:-10}"

    init_state_database

    sqlite3 "$STATE_DB_PATH" -json <<SQL
SELECT * FROM upgrade_history
WHERE component = '$component'
ORDER BY upgraded_at DESC
LIMIT $limit;
SQL
}

#===============================================================================
# ROLLBACK POINTS
#===============================================================================

record_rollback_point() {
    local component="$1"
    local version="$2"
    local binary_path="$3"
    local config_path="$4"
    local metadata="${5:-{}}"

    init_state_database

    local rollback_id
    rollback_id=$(sqlite3 "$STATE_DB_PATH" <<SQL
INSERT INTO rollback_points (
    component, version,
    binary_backup_path, config_backup_path,
    state_snapshot, expires_at
) VALUES (
    '$component', '$version',
    '$binary_path', '$config_path',
    '$metadata',
    datetime('now', '+30 days')
);
SELECT last_insert_rowid();
SQL
)

    echo "$rollback_id"
}

get_rollback_point() {
    local rollback_id="$1"

    init_state_database

    sqlite3 "$STATE_DB_PATH" -json <<SQL
SELECT * FROM rollback_points WHERE id = $rollback_id;
SQL
}

list_rollback_points() {
    local component="$1"

    init_state_database

    sqlite3 "$STATE_DB_PATH" -json <<SQL
SELECT * FROM rollback_points
WHERE component = '$component'
ORDER BY created_at DESC;
SQL
}

cleanup_expired_rollback_points() {
    init_state_database

    # Get expired rollback points
    local expired
    expired=$(sqlite3 "$STATE_DB_PATH" -json <<SQL
SELECT * FROM rollback_points
WHERE datetime('now') > expires_at;
SQL
)

    # Delete files and database records
    local deleted_count=0

    while read -r point; do
        local binary_path config_path
        binary_path=$(echo "$point" | jq -r '.binary_backup_path')
        config_path=$(echo "$point" | jq -r '.config_backup_path')
        local rollback_id
        rollback_id=$(echo "$point" | jq -r '.id')

        # Delete files
        rm -f "$binary_path" "$config_path"

        # Delete directory if empty
        local rollback_dir
        rollback_dir=$(dirname "$binary_path")
        if [[ -d "$rollback_dir" ]] && [[ -z "$(ls -A "$rollback_dir")" ]]; then
            rmdir "$rollback_dir"
        fi

        # Delete from database
        sqlite3 "$STATE_DB_PATH" "DELETE FROM rollback_points WHERE id = $rollback_id;"

        ((deleted_count++))
    done < <(echo "$expired" | jq -c '.[]')

    _version_log INFO "Cleaned up $deleted_count expired rollback points"
}
```

---

## Implementation Steps

### Step 1: Setup Infrastructure

```bash
# 1. Create new directories
mkdir -p /var/lib/observability-stack/rollback
mkdir -p ~/.cache/observability-stack/versions

# 2. Initialize state database
./scripts/init-state-db.sh

# 3. Verify structure
tree /var/lib/observability-stack
tree ~/.cache/observability-stack
```

### Step 2: Test Version Resolution

```bash
# Test basic version resolution
source scripts/lib/versions.sh

# Resolve latest version
version=$(resolve_version "node_exporter")
echo "Latest node_exporter: $version"

# Check with constraints
version=$(get_latest_version "node_exporter" ">=1.7.0 <2.0.0")
echo "Constrained version: $version"
```

### Step 3: Test GitHub API Integration

```bash
# Source GitHub API library
source scripts/lib/github-api.sh

# Test rate limit check
if check_rate_limit; then
    echo "Rate limit OK"
fi

# Test fetching latest release
release=$(github_get_latest_release "prometheus/node_exporter")
echo "$release" | jq '.tag_name'

# Extract version
version=$(extract_version_from_release "$release")
echo "Version: $version"
```

### Step 4: Test State Database

```bash
# Source database library
source scripts/lib/state-db.sh

# Initialize database
init_state_database

# Record installation
record_installation "node_exporter" "1.7.0" '{"method": "manual"}'

# Get installed version
installed=$(get_installed_version_from_db "node_exporter")
echo "Installed: $installed"

# List rollback points
rollback_points=$(list_rollback_points "node_exporter")
echo "$rollback_points" | jq .
```

### Step 5: Create CLI Tools

#### Tool 1: Check for Upgrades

**File:** `/home/calounx/repositories/mentat/observability-stack/scripts/version-management/check-upgrades.sh`

```bash
#!/bin/bash
#===============================================================================
# Check for Available Upgrades
#===============================================================================

set -euo pipefail

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "${BASE_DIR}/scripts/lib/versions.sh"
source "${BASE_DIR}/scripts/lib/github-api.sh"
source "${BASE_DIR}/scripts/lib/state-db.sh"

#===============================================================================
# MAIN
#===============================================================================

main() {
    local component="${1:-all}"

    echo "Checking for available upgrades..."
    echo ""

    # Get list of installed components
    local components=()

    if [[ "$component" == "all" ]]; then
        # Get all installed components
        components=($(sqlite3 "$STATE_DB_PATH" "SELECT component FROM installed_components;"))
    else
        components=("$component")
    fi

    # Check each component
    local upgrades_available=0

    for comp in "${components[@]}"; do
        local current_version
        current_version=$(get_installed_version "$comp")

        if [[ -z "$current_version" ]]; then
            echo "  $comp: Not installed"
            continue
        fi

        local latest_version
        latest_version=$(resolve_version "$comp")

        if [[ -z "$latest_version" ]]; then
            echo "  $comp: Unable to determine latest version"
            continue
        fi

        # Compare versions
        local comparison
        comparison=$(compare_versions "$latest_version" "$current_version")

        if [[ "$comparison" == "1" ]]; then
            # Upgrade available
            echo "  $comp: $current_version → $latest_version (upgrade available)"

            # Check safety
            local safety
            safety=$(check_upgrade_safety "$comp" "$current_version" "$latest_version")
            local risk
            risk=$(echo "$safety" | jq -r '.risk_level')

            echo "    Risk level: $risk"

            ((upgrades_available++))
        elif [[ "$comparison" == "0" ]]; then
            echo "  $comp: $current_version (up to date)"
        else
            echo "  $comp: $current_version (newer than latest $latest_version)"
        fi
    done

    echo ""
    echo "Summary: $upgrades_available upgrade(s) available"
}

main "$@"
```

#### Tool 2: Upgrade Component

**File:** `/home/calounx/repositories/mentat/observability-stack/scripts/version-management/upgrade-component.sh`

```bash
#!/bin/bash
#===============================================================================
# Upgrade Component
#===============================================================================

set -euo pipefail

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "${BASE_DIR}/scripts/lib/versions.sh"
source "${BASE_DIR}/scripts/lib/github-api.sh"
source "${BASE_DIR}/scripts/lib/state-db.sh"
source "${BASE_DIR}/scripts/lib/rollback.sh"

#===============================================================================
# CONFIGURATION
#===============================================================================

FORCE_UPGRADE=false
DRY_RUN=false
SKIP_SAFETY=false
NO_ROLLBACK=false

#===============================================================================
# ARGUMENT PARSING
#===============================================================================

usage() {
    cat <<EOF
Usage: $0 <component> [target_version] [options]

Options:
    --force         Force upgrade even if risky
    --dry-run       Show what would be done without making changes
    --skip-safety   Skip safety checks (dangerous!)
    --no-rollback   Don't create rollback point
    --help          Show this help

Examples:
    $0 node_exporter
    $0 node_exporter 1.8.0
    $0 node_exporter --force
    $0 node_exporter 1.8.0 --dry-run
EOF
}

parse_args() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi

    COMPONENT="$1"
    shift

    # Optional version
    if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^-- ]]; then
        TARGET_VERSION="$1"
        shift
    else
        TARGET_VERSION="latest"
    fi

    # Options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                FORCE_UPGRADE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-safety)
                SKIP_SAFETY=true
                shift
                ;;
            --no-rollback)
                NO_ROLLBACK=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

#===============================================================================
# MAIN UPGRADE LOGIC
#===============================================================================

main() {
    parse_args "$@"

    echo "=========================================="
    echo "Component Upgrade"
    echo "=========================================="
    echo ""
    echo "Component: $COMPONENT"
    echo "Target:    $TARGET_VERSION"
    echo ""

    # Get current version
    local current_version
    current_version=$(get_installed_version "$COMPONENT")

    if [[ -z "$current_version" ]]; then
        echo "Error: $COMPONENT is not installed"
        exit 1
    fi

    echo "Current:   $current_version"
    echo ""

    # Resolve target version
    if [[ "$TARGET_VERSION" == "latest" ]]; then
        TARGET_VERSION=$(resolve_version "$COMPONENT")
    fi

    echo "Resolved target: $TARGET_VERSION"
    echo ""

    # Version comparison
    local comparison
    comparison=$(compare_versions "$TARGET_VERSION" "$current_version")

    if [[ "$comparison" == "0" ]]; then
        echo "Already at target version. Nothing to do."
        exit 0
    elif [[ "$comparison" == "-1" ]] && [[ "$FORCE_UPGRADE" != "true" ]]; then
        echo "Error: Downgrade not allowed (use --force to override)"
        exit 1
    fi

    # Safety checks
    if [[ "$SKIP_SAFETY" != "true" ]]; then
        echo "Running safety checks..."
        local safety
        safety=$(check_upgrade_safety "$COMPONENT" "$current_version" "$TARGET_VERSION")

        local approved risk_level
        approved=$(echo "$safety" | jq -r '.approved')
        risk_level=$(echo "$safety" | jq -r '.risk_level')

        echo "  Risk level: $risk_level"

        # Display check results
        echo "$safety" | jq -r '.checks[] | "  \(.name): \(if .passed then "✓" else "✗" end)"'

        if [[ "$approved" != "true" ]] && [[ "$FORCE_UPGRADE" != "true" ]]; then
            echo ""
            echo "Upgrade not approved. Use --force to override."
            exit 1
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        echo "[DRY RUN] Would upgrade $COMPONENT from $current_version to $TARGET_VERSION"
        exit 0
    fi

    # Create rollback point
    local rollback_id=""
    if [[ "$NO_ROLLBACK" != "true" ]]; then
        echo ""
        echo "Creating rollback point..."
        rollback_id=$(create_rollback_point "$COMPONENT" "$current_version")
        echo "  Rollback point ID: $rollback_id"
    fi

    # Perform upgrade
    echo ""
    echo "Upgrading $COMPONENT..."

    if perform_upgrade "$COMPONENT" "$TARGET_VERSION"; then
        echo ""
        echo "✓ Upgrade successful!"

        # Record in database
        record_upgrade "$COMPONENT" "$current_version" "$TARGET_VERSION" 1 ""

        # Update installed version
        record_installation "$COMPONENT" "$TARGET_VERSION"

    else
        echo ""
        echo "✗ Upgrade failed!"

        # Auto-rollback if enabled
        if [[ -n "$rollback_id" ]] && [[ "$NO_ROLLBACK" != "true" ]]; then
            echo ""
            echo "Initiating automatic rollback..."
            if execute_rollback "$COMPONENT" "$rollback_id"; then
                echo "✓ Rollback successful"
            else
                echo "✗ Rollback failed - manual intervention required!"
            fi
        fi

        # Record failure
        record_upgrade "$COMPONENT" "$current_version" "$TARGET_VERSION" 0 "Upgrade failed"

        exit 1
    fi
}

main "$@"
```

---

## Testing Strategy

### Unit Tests

```bash
# scripts/test/test-version-comparison.sh
#!/bin/bash

source scripts/lib/versions.sh

test_version_comparison() {
    local result

    # Test equal versions
    result=$(compare_versions "1.7.0" "1.7.0")
    [[ "$result" == "0" ]] || { echo "FAIL: equal versions"; return 1; }

    # Test greater than
    result=$(compare_versions "1.8.0" "1.7.0")
    [[ "$result" == "1" ]] || { echo "FAIL: greater than"; return 1; }

    # Test less than
    result=$(compare_versions "1.6.0" "1.7.0")
    [[ "$result" == "-1" ]] || { echo "FAIL: less than"; return 1; }

    # Test pre-release
    result=$(compare_versions "1.7.0" "1.7.0-rc1")
    [[ "$result" == "1" ]] || { echo "FAIL: pre-release"; return 1; }

    echo "✓ All version comparison tests passed"
}

test_version_comparison
```

### Integration Tests

```bash
# scripts/test/test-github-integration.sh
#!/bin/bash

source scripts/lib/github-api.sh

test_github_integration() {
    # Test rate limit check
    if ! check_rate_limit; then
        echo "WARN: Rate limit check failed"
    fi

    # Test fetching latest release
    local release
    release=$(github_get_latest_release "prometheus/node_exporter")

    if [[ -z "$release" ]]; then
        echo "FAIL: Could not fetch latest release"
        return 1
    fi

    # Extract version
    local version
    version=$(extract_version_from_release "$release")

    if [[ -z "$version" ]]; then
        echo "FAIL: Could not extract version"
        return 1
    fi

    echo "✓ GitHub integration test passed (version: $version)"
}

test_github_integration
```

---

## Deployment Steps

### Production Deployment

```bash
# 1. Backup existing installation
sudo ./scripts/backup-all.sh

# 2. Initialize state database
sudo ./scripts/init-state-db.sh

# 3. Import existing installations into state DB
sudo ./scripts/import-existing-installations.sh

# 4. Test version resolution
./scripts/version-management/check-upgrades.sh

# 5. Perform first upgrade (non-critical component)
sudo ./scripts/version-management/upgrade-component.sh nginx_exporter --dry-run

# 6. Actual upgrade
sudo ./scripts/version-management/upgrade-component.sh nginx_exporter

# 7. Verify
systemctl status nginx_exporter
curl http://localhost:9113/metrics

# 8. Setup automated checks (cron)
sudo crontab -e
# Add: 0 2 * * * /path/to/scripts/version-management/check-upgrades.sh >> /var/log/version-checks.log 2>&1
```

---

## Maintenance

### Daily Tasks

```bash
# Check for updates
./scripts/version-management/check-upgrades.sh
```

### Weekly Tasks

```bash
# Cleanup old rollback points
./scripts/version-management/cleanup-rollback.sh

# Update version cache
./scripts/version-management/update-cache.sh

# Backup state database
cp /var/lib/observability-stack/state.db /var/backups/
```

### Monthly Tasks

```bash
# Review upgrade history
sqlite3 /var/lib/observability-stack/state.db \
    "SELECT * FROM upgrade_history ORDER BY upgraded_at DESC LIMIT 20;"

# Analyze upgrade success rate
sqlite3 /var/lib/observability-stack/state.db \
    "SELECT component, COUNT(*) as total, SUM(success) as successful
     FROM upgrade_history GROUP BY component;"
```

---

## Troubleshooting

### Issue: GitHub API Rate Limit

**Symptom:** "Rate limit exceeded" errors

**Solution:**
```bash
# Set GitHub token
export GITHUB_TOKEN="your_token_here"

# Or enable offline mode
export VERSION_OFFLINE_MODE=true

# Force use of cache
./scripts/version-management/check-upgrades.sh
```

### Issue: Upgrade Fails

**Symptom:** Upgrade fails, service doesn't start

**Solution:**
```bash
# Check rollback points
./scripts/version-management/rollback-component.sh <component> --list

# Execute rollback
sudo ./scripts/version-management/rollback-component.sh <component> <rollback_id>

# Check logs
journalctl -u <component> -n 50
```

### Issue: Version Mismatch

**Symptom:** State DB shows different version than actual binary

**Solution:**
```bash
# Verify binary version
/usr/local/bin/node_exporter --version

# Sync state DB
source scripts/lib/state-db.sh
record_installation "node_exporter" "actual_version"
```

---

## Related Documentation

- [DYNAMIC_VERSION_MANAGEMENT_DESIGN.md](/home/calounx/repositories/mentat/observability-stack/docs/DYNAMIC_VERSION_MANAGEMENT_DESIGN.md) - Architecture design
- [VERSION_MANAGEMENT_ARCHITECTURE.md](/home/calounx/repositories/mentat/observability-stack/docs/VERSION_MANAGEMENT_ARCHITECTURE.md) - Base architecture
- [versions.yaml](/home/calounx/repositories/mentat/observability-stack/config/versions.yaml) - Configuration reference

---

**Next Steps:**
1. Review architecture design
2. Implement core libraries (github-api.sh, state-db.sh)
3. Create CLI tools
4. Test in staging environment
5. Deploy to production with monitoring
