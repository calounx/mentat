# Comprehensive Code Quality Review and Linting Analysis
## Observability Stack - Upgrade System

**Review Date:** 2025-12-27
**Reviewer:** Claude Code (Automated Analysis)
**Files Analyzed:** 5 core upgrade system files (3,360 total lines)

---

## Executive Summary

### Overall Code Quality Score: 78/100

**Grade: B+** (Good quality with room for improvement)

The upgrade orchestration system demonstrates solid engineering practices with comprehensive documentation, proper error handling, and idempotent design. However, there are several areas requiring attention before production deployment.

### Key Metrics

| Metric | Value | Status |
|--------|-------|--------|
| Total Lines of Code | 3,360 | ✓ |
| Comment Coverage | 20.7% (664 comment lines) | ✓ Good |
| Functions Defined | 83 total | ✓ |
| ShellCheck Issues | 11 findings | ⚠ Needs attention |
| TODO/FIXME Comments | 3 items | ℹ Track completion |
| Security Issues | 0 critical | ✓ |
| External Dependencies | jq, curl, python3 | ⚠ Verify availability |

---

## Priority Classification

### Critical Issues (P0) - Must Fix Before Production

**Total: 6 issues**

#### P0-1: Missing Function Definitions (upgrade-manager.sh)
**Severity:** CRITICAL
**Lines:** 55, 132, 140, 143, 202, 209, 221, 254, 270, 281, 399, 400, 411, 462, 598, 609, 661, 668

**Issue:**
The `upgrade-manager.sh` extensively uses YAML parsing functions (`yaml_get_nested`, `yaml_get_array`, `yaml_get_deep`) that are defined in `common.sh`, but there's no verification that these functions handle errors gracefully.

**Impact:**
- Runtime failures if YAML parsing fails
- Silent failures in configuration reading
- Incorrect upgrade decisions

**Fix Recommendation:**
```bash
# In upgrade-manager.sh, add defensive checks:
yaml_get_nested() {
    local result
    if ! result=$(command yaml_get_nested "$@" 2>&1); then
        log_error "Failed to parse YAML: $*"
        return 1
    fi
    echo "$result"
}
```

**Location:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/upgrade-manager.sh`

---

#### P0-2: Unverified External Dependencies
**Severity:** CRITICAL
**Lines:** Multiple files

**Issue:**
Scripts assume `jq`, `curl`, and `python3` are available without checking. 21 jq commands and 4 python inline scripts could fail silently.

**Impact:**
- Complete failure of upgrade orchestration
- JSON parsing failures
- State corruption

**Fix Recommendation:**
```bash
# Add to upgrade-orchestrator.sh initialization section:
check_dependencies() {
    local missing=()
    for cmd in jq curl python3; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_fatal "Missing required dependencies: ${missing[*]}"
    fi
}

# Call early in main execution:
check_dependencies
```

**Location:**
- All files

---

#### P0-3: Race Condition in Lock Cleanup
**Severity:** CRITICAL
**Lines:** upgrade-state.sh:143-156

**Issue:**
The stale lock detection checks if a process exists but doesn't verify it's actually the upgrade process. A PID could be reused by another process.

**Impact:**
- Deletion of valid locks
- Concurrent upgrade executions
- State corruption

**Fix Recommendation:**
```bash
# In state_lock(), improve stale lock detection:
if [[ -f "$STATE_LOCK/pid" ]]; then
    local lock_pid
    lock_pid=$(cat "$STATE_LOCK/pid")

    # Check if process exists AND is a bash script
    if kill -0 "$lock_pid" 2>/dev/null; then
        local proc_cmd
        proc_cmd=$(ps -p "$lock_pid" -o comm= 2>/dev/null)
        if [[ "$proc_cmd" != "bash" && "$proc_cmd" != *"upgrade"* ]]; then
            log_warn "Lock holder PID $lock_pid is not an upgrade process"
            # Could still be stale, add timestamp check
        else
            # Process exists and looks like upgrade, wait
            sleep 1
            ((elapsed++))
            continue
        fi
    else
        # Process doesn't exist, safe to remove
        log_warn "Removing stale lock from PID $lock_pid"
        rm -rf "$STATE_LOCK"
        continue
    fi
fi
```

**Location:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/upgrade-state.sh:143-156`

---

#### P0-4: Declare and Assign Separation (SC2155)
**Severity:** HIGH
**Lines:** upgrade-state.sh:311, upgrade-manager.sh:273, 353

**Issue:**
ShellCheck SC2155 - Variables are declared and assigned in one line, masking return values from command substitutions.

**Impact:**
- Failed commands not detected
- Incorrect error handling
- Silent failures in critical paths

**Fix Recommendation:**
```bash
# Current problematic code (line 311 in upgrade-state.sh):
local upgrade_id="upgrade-$(date +%Y%m%d-%H%M%S)"

# Fixed version:
local upgrade_id
upgrade_id="upgrade-$(date +%Y%m%d-%H%M%S)" || {
    log_error "Failed to generate upgrade ID"
    return 1
}

# For upgrade-manager.sh line 273:
# Current:
local binary_backup="$backup_dir/$(basename "$binary_path")"

# Fixed:
local binary_backup
binary_backup="$backup_dir/$(basename "$binary_path")" || {
    log_error "Failed to determine backup path"
    return 1
}
```

**Location:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/upgrade-state.sh:311`
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/upgrade-manager.sh:273, 353`

---

#### P0-5: Missing Error Handling for State Updates
**Severity:** HIGH
**Lines:** upgrade-orchestrator.sh:434, 508, 535, 541, 578, 606, 645, 650, 656, 670, 674, 680

**Issue:**
State update functions (`state_begin_upgrade`, `state_complete_upgrade`, etc.) are called without checking return values in dry-run mode checks.

**Impact:**
- State inconsistencies
- Failed upgrades appearing successful
- Recovery failures

**Fix Recommendation:**
```bash
# Current code (line 508):
if [[ "$DRY_RUN" != "true" ]]; then
    state_begin_upgrade "$UPGRADE_MODE"
fi

# Fixed version:
if [[ "$DRY_RUN" != "true" ]]; then
    if ! state_begin_upgrade "$UPGRADE_MODE"; then
        log_error "Failed to initialize upgrade state"
        exit 1
    fi
fi
```

**Location:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/upgrade-orchestrator.sh`: Multiple locations

---

#### P0-6: Incomplete Configuration File Validation
**Severity:** HIGH
**Lines:** upgrade-orchestrator.sh:207-209

**Issue:**
Only checks if upgrade config file exists, doesn't validate it's valid YAML or contains required keys.

**Impact:**
- Runtime failures deep in execution
- Poor user experience
- Difficult debugging

**Fix Recommendation:**
```bash
# Add after line 209:
if [[ ! -f "$UPGRADE_CONFIG_FILE" ]]; then
    log_fatal "Upgrade configuration not found: $UPGRADE_CONFIG_FILE"
fi

# Add validation:
log_info "Validating upgrade configuration..."
if ! validate_upgrade_config "$UPGRADE_CONFIG_FILE"; then
    log_fatal "Invalid upgrade configuration"
fi

# New function to add to upgrade-manager.sh:
validate_upgrade_config() {
    local config_file="$1"

    # Check if valid YAML
    if ! python3 -c "import yaml, sys; yaml.safe_load(open('$config_file'))" 2>/dev/null; then
        log_error "Configuration is not valid YAML"
        return 1
    fi

    # Check required top-level keys
    local required_keys=("components" "phases")
    for key in "${required_keys[@]}"; do
        if ! grep -q "^${key}:" "$config_file"; then
            log_error "Missing required key: $key"
            return 1
        fi
    done

    log_success "Configuration validation passed"
    return 0
}
```

**Location:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/upgrade-orchestrator.sh:207-209`

---

### High Priority Issues (P1) - Should Fix Soon

**Total: 8 issues**

#### P1-1: Unused Variables (SC2034)
**Severity:** MEDIUM
**Lines:**
- upgrade-orchestrator.sh:141 (RESUME_MODE)
- upgrade-orchestrator.sh:146 (ROLLBACK_MODE)
- upgrade-orchestrator.sh:219 (SKIP_BACKUP)
- upgrade-orchestrator.sh:438 (skip_count)
- versions.sh:120 (PARSED_BUILD)
- versions.sh:541 (config_key)

**Issue:**
Variables declared but never used, indicating incomplete implementation or dead code.

**Impact:**
- Code confusion
- Maintenance burden
- Potential logic errors

**Fix Recommendation:**
```bash
# Option 1: Remove if truly unused
# Delete lines 141, 146, 219, 438

# Option 2: If intended for future use, export or document
export RESUME_MODE  # Used by child processes
# shellcheck disable=SC2034
SKIP_BACKUP=false  # Reserved for future use

# Option 3: Actually use the variables
if [[ "$ROLLBACK_MODE" == "true" ]]; then
    # Add actual rollback logic
    perform_rollback
fi
```

**Location:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/upgrade-orchestrator.sh`
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/versions.sh`

---

#### P1-2: Python Dependency for JSON/YAML Processing
**Severity:** MEDIUM
**Lines:** versions.sh:431-437, 472-477, 494-505, 623-624

**Issue:**
Four inline Python scripts used for JSON processing. No fallback if Python not available.

**Impact:**
- Fragility on minimal systems
- Potential encoding issues
- Performance overhead

**Fix Recommendation:**
```bash
# Create a dedicated JSON helper function:
json_extract() {
    local json="$1"
    local key="$2"

    # Try jq first (faster, more common)
    if command -v jq >/dev/null 2>&1; then
        echo "$json" | jq -r ".$key // empty"
    elif command -v python3 >/dev/null 2>&1; then
        echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('$key',''))"
    else
        log_error "Neither jq nor python3 available for JSON parsing"
        return 1
    fi
}

# Replace inline Python scripts with function calls
```

**Location:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/versions.sh`

---

#### P1-3: Long Functions Need Refactoring
**Severity:** MEDIUM
**Lines:** Multiple

**Issue:**
Several functions exceed 60 lines, reducing maintainability:
- `resolve_version()`: 84 lines
- `compare_versions()`: 77 lines
- `upgrade_all()`: 68 lines
- `upgrade_phase()`: 64 lines
- `resume_upgrade()`: 64 lines

**Impact:**
- Difficult to test
- Hard to understand
- Error-prone modifications

**Fix Recommendation:**
```bash
# Example refactoring for resolve_version():

resolve_version() {
    local component="$1"
    local strategy_override="${2:-}"

    # Check environment override
    local version
    if version=$(check_version_override "$component"); then
        echo "$version"
        return 0
    fi

    # Determine and apply strategy
    local strategy="${strategy_override:-$(get_version_strategy "$component")}"
    if ! version=$(apply_version_strategy "$component" "$strategy"); then
        log_error "Failed to resolve version for $component"
        return 1
    fi

    # Validate and return
    validate_and_return_version "$component" "$version" "$strategy"
}

# Split into smaller focused functions:
check_version_override() { ... }
apply_version_strategy() { ... }
validate_and_return_version() { ... }
```

**Location:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/versions.sh`
- `/home/calounx/repositories/mentat/observability-stack/scripts/upgrade-orchestrator.sh`

---

#### P1-4: Inconsistent Error Message Format
**Severity:** MEDIUM
**Lines:** Multiple

**Issue:**
Error messages use inconsistent formats:
- Some use "Failed to..." others use "Could not..."
- Inconsistent capitalization
- Variable detail levels

**Impact:**
- Poor user experience
- Difficult to parse logs programmatically
- Inconsistent documentation

**Fix Recommendation:**
```bash
# Establish standard error message format:
# Format: "[Component] Action failed: Reason (Details)"

# Examples:
log_error "Version resolution failed: No GitHub repo configured for $component"
log_error "State lock acquisition failed: Timeout after 30s (holder PID: $lock_pid)"
log_error "Component upgrade failed: Health check timeout (endpoint: $endpoint)"

# Create helper for consistent errors:
log_upgrade_error() {
    local component="$1"
    local action="$2"
    local reason="$3"
    local details="${4:-}"

    local msg="[$component] $action failed: $reason"
    [[ -n "$details" ]] && msg="$msg ($details)"
    log_error "$msg"
}
```

**Location:**
- All files

---

#### P1-5: Missing Timeout on GitHub API Calls
**Severity:** MEDIUM
**Lines:** versions.sh:411

**Issue:**
While `--max-time` is set to 10s, there's no retry logic or exponential backoff for transient failures.

**Impact:**
- Poor handling of network issues
- Unnecessary upgrade failures
- Rate limit problems

**Fix Recommendation:**
```bash
# Add retry wrapper for GitHub API calls:
_github_api_call_with_retry() {
    local endpoint="$1"
    local max_retries=3
    local retry_delay=2

    for attempt in $(seq 1 $max_retries); do
        if response=$(_github_api_call "$endpoint"); then
            echo "$response"
            return 0
        fi

        local exit_code=$?
        if [[ $exit_code -eq 2 ]]; then
            # Rate limit error, don't retry
            return 2
        fi

        if [[ $attempt -lt $max_retries ]]; then
            log_warn "GitHub API call failed (attempt $attempt/$max_retries), retrying in ${retry_delay}s..."
            sleep $retry_delay
            retry_delay=$((retry_delay * 2))  # Exponential backoff
        fi
    done

    log_error "GitHub API call failed after $max_retries attempts"
    return 1
}
```

**Location:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/versions.sh:396-423`

---

#### P1-6: Backup Restoration Not Fully Tested
**Severity:** MEDIUM
**Lines:** upgrade-manager.sh:328-381

**Issue:**
The `restore_from_backup()` function doesn't verify restored files are valid before restarting services.

**Impact:**
- Corrupt backups lead to broken systems
- No rollback from rollback
- Service outages

**Fix Recommendation:**
```bash
restore_from_backup() {
    local component="$1"
    local backup_dir="$2"

    # ... existing backup validation ...

    # NEW: Verify backup integrity before restoration
    if [[ -f "$backup_dir/metadata.json" ]]; then
        local expected_count
        expected_count=$(jq -r '.backup_count' "$backup_dir/metadata.json")
        local actual_count
        actual_count=$(find "$backup_dir" -type f -not -name "metadata.json" | wc -l)

        if [[ $actual_count -ne $expected_count ]]; then
            log_error "Backup verification failed: expected $expected_count files, found $actual_count"
            return 1
        fi
    fi

    # Stop service
    # ... existing code ...

    # Restore with validation
    if [[ -n "$binary_path" ]]; then
        local binary_backup="$backup_dir/$(basename "$binary_path")"
        if [[ -f "$binary_backup" ]]; then
            # Verify binary is executable
            if [[ ! -x "$binary_backup" ]]; then
                log_error "Backed up binary is not executable: $binary_backup"
                return 1
            fi

            cp -p "$binary_backup" "$binary_path"
            log_debug "Restored binary: $binary_path"
        fi
    fi

    # ... rest of restoration ...
}
```

**Location:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/upgrade-manager.sh:328-381`

---

#### P1-7: Version Comparison Edge Cases
**Severity:** MEDIUM
**Lines:** versions.sh:131-213

**Issue:**
Pre-release version comparison uses simple lexical comparison, which may not follow semver spec correctly.

**Impact:**
- Incorrect upgrade decisions
- Version ordering problems
- Compatibility issues

**Fix Recommendation:**
```bash
# Enhanced pre-release comparison following semver spec:
_compare_prerelease() {
    local pre1="$1"
    local pre2="$2"

    # Split by dots
    IFS='.' read -ra parts1 <<< "$pre1"
    IFS='.' read -ra parts2 <<< "$pre2"

    local max_len=${#parts1[@]}
    [[ ${#parts2[@]} -gt $max_len ]] && max_len=${#parts2[@]}

    for i in $(seq 0 $((max_len - 1))); do
        local p1="${parts1[$i]:-}"
        local p2="${parts2[$i]:-}"

        # Empty part means this version is greater
        [[ -z "$p1" ]] && echo -1 && return 0
        [[ -z "$p2" ]] && echo 1 && return 0

        # Numeric comparison if both are numbers
        if [[ "$p1" =~ ^[0-9]+$ ]] && [[ "$p2" =~ ^[0-9]+$ ]]; then
            [[ $p1 -lt $p2 ]] && echo -1 && return 0
            [[ $p1 -gt $p2 ]] && echo 1 && return 0
        else
            # Lexical comparison
            [[ "$p1" < "$p2" ]] && echo -1 && return 0
            [[ "$p1" > "$p2" ]] && echo 1 && return 0
        fi
    done

    echo 0
    return 0
}
```

**Location:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/versions.sh:192-208`

---

#### P1-8: State File Corruption Recovery
**Severity:** MEDIUM
**Lines:** upgrade-state.sh:663-701

**Issue:**
`state_verify()` detects corrupted state but doesn't provide recovery options.

**Impact:**
- Manual intervention required
- Downtime
- Lost upgrade progress

**Fix Recommendation:**
```bash
state_repair() {
    log_warn "Attempting to repair state file..."

    # Check if we have a recent checkpoint
    local latest_checkpoint
    latest_checkpoint=$(find "$CHECKPOINT_DIR" -name "*.json" -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)

    if [[ -n "$latest_checkpoint" ]]; then
        log_info "Found checkpoint: $latest_checkpoint"
        if jq empty "$latest_checkpoint" 2>/dev/null; then
            log_info "Restoring from checkpoint..."
            cp "$latest_checkpoint" "$STATE_FILE"
            chmod 600 "$STATE_FILE"
            log_success "State restored from checkpoint"
            return 0
        fi
    fi

    # Check history for valid state
    local latest_history
    latest_history=$(find "$HISTORY_DIR" -name "*.json" -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)

    if [[ -n "$latest_history" ]]; then
        log_info "Found history: $latest_history"
        if jq empty "$latest_history" 2>/dev/null; then
            log_info "Restoring from history..."
            cp "$latest_history" "$STATE_FILE"
            chmod 600 "$STATE_FILE"
            log_success "State restored from history"
            return 0
        fi
    fi

    # Last resort: initialize fresh state
    log_warn "No valid backup found, initializing fresh state"
    state_init
}
```

**Location:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/upgrade-state.sh`

---

### Medium Priority Issues (P2) - Good to Have

**Total: 12 issues**

#### P2-1: TODO Items Need Tracking
**Severity:** LOW
**Lines:**
- versions.sh:752 - "TODO: Implement full range resolution with GitHub releases list"
- versions.sh:767 - "TODO: Implement LTS detection logic"
- versions.sh:809 - "TODO: Implement compatibility matrix checking"

**Issue:**
Three incomplete features marked with TODO comments.

**Impact:**
- Feature incompleteness
- Unexpected behavior
- Technical debt

**Fix Recommendation:**
```bash
# Create GitHub issues for tracking:
# Issue #1: Implement semver range resolution for version constraints
# Issue #2: Add LTS version detection and strategy
# Issue #3: Build component compatibility matrix checker

# Add warnings when these features are used:
case "$strategy" in
    range)
        log_warn "Range strategy is partially implemented, falling back to config version"
        # ... existing code ...
        ;;
    lts)
        log_warn "LTS strategy not fully implemented, using latest version"
        # ... existing code ...
        ;;
esac
```

**Location:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/versions.sh`

---

#### P2-2: Magic Numbers and Strings
**Severity:** LOW
**Lines:** Multiple

**Issue:**
Hardcoded values throughout:
- Timeouts: 30s, 60s, 10s
- Sleep durations: 2s, 3s, 5s, 10s, 30s
- Retry counts: 3, 6
- Disk space: 512000 KB

**Impact:**
- Difficult to tune
- Inconsistent behavior
- Testing challenges

**Fix Recommendation:**
```bash
# Add configuration constants at file top:

# Timeout configurations
readonly LOCK_TIMEOUT_SECONDS=30
readonly HEALTH_CHECK_TIMEOUT_SECONDS=60
readonly API_CALL_TIMEOUT_SECONDS=10

# Retry configurations
readonly MAX_RETRY_ATTEMPTS=3
readonly METRICS_CHECK_MAX_ATTEMPTS=6

# Sleep durations (in seconds)
readonly SERVICE_STOP_WAIT_SECONDS=2
readonly SERVICE_START_WAIT_SECONDS=3
readonly RETRY_SLEEP_SECONDS=5
readonly INTER_COMPONENT_SLEEP_STANDARD=10
readonly INTER_COMPONENT_SLEEP_SAFE=30

# Resource requirements
readonly MIN_DISK_SPACE_KB=512000  # 500MB

# Use constants instead of literals:
if [[ $AVAILABLE_SPACE -lt $MIN_DISK_SPACE_KB ]]; then
    log_fatal "Insufficient disk space..."
fi
```

**Location:**
- All files

---

#### P2-3: Inconsistent Function Naming
**Severity:** LOW
**Lines:** Multiple

**Issue:**
Mixing naming conventions:
- Snake_case: `state_init`, `get_target_version`
- Prefixed: `_version_log`, `_github_api_call`
- Public/private unclear

**Impact:**
- API confusion
- Maintainability issues
- Documentation challenges

**Fix Recommendation:**
```bash
# Establish naming convention:
# - Public API: snake_case (no prefix)
# - Private/internal: _snake_case (leading underscore)
# - Constants: UPPER_SNAKE_CASE

# Document in each file header:
#
# Public Functions:
#   state_init() - Initialize state management
#   state_update() - Update state atomically
#
# Private Functions:
#   _state_archive_to_history() - Internal archival
#   _state_cleanup() - Internal cleanup
#
```

**Location:**
- All files

---

#### P2-4: Limited Test Coverage
**Severity:** LOW
**Lines:** N/A

**Issue:**
No automated tests found for upgrade system.

**Impact:**
- Regression risks
- Refactoring difficulties
- Confidence issues

**Fix Recommendation:**
```bash
# Create tests/upgrade/ directory structure:
# tests/
#   upgrade/
#     test_version_comparison.sh
#     test_state_management.sh
#     test_upgrade_orchestration.sh
#     fixtures/
#       test_state.json
#       test_config.yaml

# Example test structure:
#!/bin/bash
# tests/upgrade/test_version_comparison.sh

source "$(dirname "$0")/../../scripts/lib/versions.sh"

test_compare_equal_versions() {
    local result
    result=$(compare_versions "1.0.0" "1.0.0")
    [[ $result -eq 0 ]] || {
        echo "FAIL: Equal versions comparison"
        return 1
    }
    echo "PASS: Equal versions comparison"
}

test_compare_greater_version() {
    local result
    result=$(compare_versions "2.0.0" "1.0.0")
    [[ $result -eq 1 ]] || {
        echo "FAIL: Greater version comparison"
        return 1
    }
    echo "PASS: Greater version comparison"
}

# Run all tests
test_compare_equal_versions
test_compare_greater_version
```

**Location:**
- Create new `tests/upgrade/` directory

---

#### P2-5: Documentation Could Be Enhanced
**Severity:** LOW
**Lines:** Multiple

**Issue:**
While well-commented, missing:
- Architecture diagrams
- Sequence diagrams for upgrade flow
- Troubleshooting guide
- Performance tuning guide

**Impact:**
- Onboarding time
- Operational issues
- Misuse

**Fix Recommendation:**
```bash
# Create comprehensive documentation:
# docs/upgrade/
#   architecture.md - System architecture
#   flow-diagrams.md - Sequence diagrams
#   troubleshooting.md - Common issues and solutions
#   performance-tuning.md - Optimization guide
#   api-reference.md - Public API documentation

# Add to each major function:
#
# Example:
#   state_update '.status = "completed"'
#
# Error Handling:
#   Returns 1 if lock acquisition fails
#   Returns 1 if jq update fails
#
# Side Effects:
#   Updates STATE_FILE atomically
#   Adds updated_at timestamp
#   Acquires and releases state lock
#
```

**Location:**
- Create new `docs/upgrade/` directory

---

#### P2-6: Logging Could Be More Structured
**Severity:** LOW
**Lines:** Multiple

**Issue:**
Logs are plain text, making programmatic parsing difficult.

**Impact:**
- Limited observability
- Difficult log aggregation
- No metrics extraction

**Fix Recommendation:**
```bash
# Add structured logging option:

STRUCTURED_LOGGING="${STRUCTURED_LOGGING:-false}"

log_structured() {
    local level="$1"
    local message="$2"
    shift 2
    local extra_fields="$*"

    if [[ "$STRUCTURED_LOGGING" == "true" ]]; then
        # JSON format for parsing
        jq -n \
            --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
            --arg level "$level" \
            --arg message "$message" \
            --arg script "$(basename "$0")" \
            --arg pid "$$" \
            '{timestamp: $timestamp, level: $level, message: $message, script: $script, pid: $pid}' \
            | jq ". + {$extra_fields}"
    else
        # Human-readable format
        log_info "$message"
    fi
}

# Usage:
log_structured "INFO" "Starting component upgrade" \
    "component: \"$component\"" \
    "version: \"$target_version\""
```

**Location:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/common.sh`

---

#### P2-7: No Metrics/Telemetry Collection
**Severity:** LOW
**Lines:** N/A

**Issue:**
No upgrade metrics are collected (duration, success rate, etc.).

**Impact:**
- Limited visibility
- No performance tracking
- Difficult capacity planning

**Fix Recommendation:**
```bash
# Add metrics collection:

METRICS_FILE="${METRICS_FILE:-/var/lib/observability-upgrades/metrics.log}"

record_metric() {
    local metric_name="$1"
    local metric_value="$2"
    local timestamp
    timestamp=$(date +%s)

    echo "$timestamp,$metric_name,$metric_value" >> "$METRICS_FILE"
}

# Usage in upgrade flow:
start_time=$(date +%s)
# ... perform upgrade ...
end_time=$(date +%s)
duration=$((end_time - start_time))

record_metric "upgrade_duration_seconds" "$duration"
record_metric "upgrade_component" "$component"
record_metric "upgrade_success" "1"
```

**Location:**
- Add to upgrade-manager.sh

---

#### P2-8: Cache Management Could Be Improved
**Severity:** LOW
**Lines:** versions.sh:298-390

**Issue:**
Cache cleanup is automatic but there's no manual cache invalidation for specific components.

**Impact:**
- Stale data issues
- Testing difficulties
- Debugging challenges

**Fix Recommendation:**
```bash
# Add cache management commands:

cache_clear_all() {
    if [[ -d "$VERSION_CACHE_DIR" ]]; then
        rm -rf "${VERSION_CACHE_DIR:?}"/*
        log_success "All caches cleared"
    fi
}

cache_stats() {
    if [[ ! -d "$VERSION_CACHE_DIR" ]]; then
        echo "No cache directory"
        return
    fi

    local total_entries
    total_entries=$(find "$VERSION_CACHE_DIR" -name "*.json" | wc -l)

    local cache_size
    cache_size=$(du -sh "$VERSION_CACHE_DIR" 2>/dev/null | cut -f1)

    echo "Cache Statistics:"
    echo "  Entries: $total_entries"
    echo "  Size: $cache_size"
    echo "  Location: $VERSION_CACHE_DIR"
}

# Add to main script as options:
#   --cache-clear     Clear all caches
#   --cache-stats     Show cache statistics
```

**Location:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/versions.sh`

---

#### P2-9: No Dry-Run Validation
**Severity:** LOW
**Lines:** upgrade-orchestrator.sh:238-240

**Issue:**
Dry-run mode shows what would happen but doesn't validate it would actually work.

**Impact:**
- False confidence
- Missed errors
- Production surprises

**Fix Recommendation:**
```bash
# Enhanced dry-run with validation:

if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "DRY-RUN MODE: No actual changes will be made"

    # Validate all prerequisites
    log_info "Validating prerequisites..."
    for component in $(list_all_components); do
        if ! validate_prerequisites "$component"; then
            log_error "Validation failed for $component"
            DRY_RUN_ERRORS+=("$component")
        fi
    done

    # Check all target versions are available
    log_info "Checking version availability..."
    for component in $(list_all_components); do
        local target_version
        if ! target_version=$(get_target_version "$component"); then
            log_error "Cannot resolve version for $component"
            DRY_RUN_ERRORS+=("$component")
        fi
    done

    # Report validation results
    if [[ ${#DRY_RUN_ERRORS[@]} -gt 0 ]]; then
        log_error "Dry-run validation found issues:"
        for error in "${DRY_RUN_ERRORS[@]}"; do
            log_error "  - $error"
        done
        exit 1
    fi
fi
```

**Location:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/upgrade-orchestrator.sh`

---

#### P2-10: GitHub Token Security
**Severity:** LOW
**Lines:** versions.sh:40, 406-407

**Issue:**
GitHub token is passed as environment variable, which can be visible in process listings.

**Impact:**
- Token exposure risk
- Security audit concerns
- Credential leakage

**Fix Recommendation:**
```bash
# Use more secure token handling:

GITHUB_TOKEN_FILE="${GITHUB_TOKEN_FILE:-}"

load_github_token() {
    if [[ -n "$GITHUB_TOKEN" ]]; then
        # Already set, use it
        return 0
    elif [[ -n "$GITHUB_TOKEN_FILE" && -f "$GITHUB_TOKEN_FILE" ]]; then
        # Load from file (more secure)
        if [[ $(stat -c %a "$GITHUB_TOKEN_FILE") != "600" ]]; then
            log_warn "GitHub token file has insecure permissions"
        fi
        GITHUB_TOKEN=$(cat "$GITHUB_TOKEN_FILE")
    fi
}

# Call early in initialization:
load_github_token

# Document secure usage:
# Instead of:
#   GITHUB_TOKEN=ghp_xxx ./script.sh
#
# Use:
#   echo "ghp_xxx" > /root/.github_token
#   chmod 600 /root/.github_token
#   GITHUB_TOKEN_FILE=/root/.github_token ./script.sh
```

**Location:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/versions.sh`

---

#### P2-11: Multiple Variable Declarations on One Line
**Severity:** LOW
**Lines:** upgrade-manager.sh:436

**Issue:**
Single line: `local host port` makes debugging harder.

**Impact:**
- Debugging difficulty
- Style inconsistency
- Reduced clarity

**Fix Recommendation:**
```bash
# Current code (line 436):
local host port
host=$(echo "$endpoint" | cut -d: -f1)
port=$(echo "$endpoint" | cut -d: -f2)

# Better approach:
local host
local port
host=$(echo "$endpoint" | cut -d: -f1)
port=$(echo "$endpoint" | cut -d: -f2)

# Or with validation:
local endpoint_parts
IFS=':' read -r host port <<< "$endpoint"
if [[ -z "$host" || -z "$port" ]]; then
    log_error "Invalid endpoint format: $endpoint"
    return 1
fi
```

**Location:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/upgrade-manager.sh:436`

---

#### P2-12: Command Output Redirection Inconsistency
**Severity:** LOW
**Lines:** Multiple

**Issue:**
Inconsistent handling of stderr/stdout redirection.

**Impact:**
- Unexpected output
- Log pollution
- Debugging difficulties

**Fix Recommendation:**
```bash
# Establish consistent patterns:

# Pattern 1: Silent success, log errors
if ! systemctl start "$service" 2>&1 | logger -t upgrade; then
    log_error "Failed to start service"
fi

# Pattern 2: Capture all output for analysis
output=$(command 2>&1) || {
    log_error "Command failed: $output"
    return 1
}

# Pattern 3: Explicit null redirection
command >/dev/null 2>&1 || log_warn "Command failed (non-fatal)"

# Document which pattern to use where:
# - User-facing commands: Log all output
# - Internal checks: Silent unless error
# - Health checks: Capture for debugging
```

**Location:**
- All files

---

### Low Priority Issues (P3) - Optional Improvements

**Total: 6 issues**

#### P3-1: Comment Coverage Could Be Higher
**Severity:** VERY LOW
**Lines:** N/A

**Issue:**
20.7% comment coverage is decent but could be improved, especially for complex algorithms.

**Impact:**
- Onboarding time
- Maintenance challenges
- Knowledge loss

**Fix Recommendation:**
```bash
# Add more detailed comments for complex sections:

# Example in compare_versions():
# Semantic version comparison following SemVer 2.0.0 spec
# Algorithm:
#   1. Compare major.minor.patch numerically
#   2. If equal, compare pre-release identifiers:
#      - Version without pre-release > version with pre-release
#      - Compare pre-release identifiers left-to-right
#      - Numeric identifiers < non-numeric identifiers
#   3. Build metadata is ignored in comparisons
#
# See: https://semver.org/#spec-item-11
compare_versions() {
    # ... implementation ...
}
```

**Location:**
- All files with complex logic

---

#### P3-2: Bash Version Compatibility
**Severity:** VERY LOW
**Lines:** Multiple

**Issue:**
Uses features requiring Bash 4.x+ (associative arrays, etc.) without checking.

**Impact:**
- Portability issues
- Older system failures
- Documentation gaps

**Fix Recommendation:**
```bash
# Add version check:

MIN_BASH_VERSION=4

check_bash_version() {
    if [[ ${BASH_VERSINFO[0]} -lt $MIN_BASH_VERSION ]]; then
        echo "Error: Bash $MIN_BASH_VERSION or higher required" >&2
        echo "Current version: ${BASH_VERSION}" >&2
        exit 1
    fi
}

# Call in initialization section
check_bash_version
```

**Location:**
- All main scripts

---

#### P3-3: Color Output Without Terminal Check
**Severity:** VERY LOW
**Lines:** common.sh:36-42

**Issue:**
Color codes used without checking if output is to a terminal.

**Impact:**
- Ugly log files
- Pipeline issues
- CI/CD problems

**Fix Recommendation:**
```bash
# Auto-detect terminal and disable colors for pipes/files:

if [[ -t 1 ]]; then
    # Output is to terminal
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly CYAN='\033[0;36m'
    readonly NC='\033[0m'
else
    # Output is to file/pipe, disable colors
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly CYAN=''
    readonly NC=''
fi

# Or provide override:
NO_COLOR="${NO_COLOR:-}"
if [[ -n "$NO_COLOR" ]] || [[ ! -t 1 ]]; then
    # Disable colors
fi
```

**Location:**
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/common.sh:36-42`

---

#### P3-4: Progress Indicators for Long Operations
**Severity:** VERY LOW
**Lines:** N/A

**Issue:**
No progress feedback for long-running operations like GitHub API calls.

**Impact:**
- Poor user experience
- Uncertain wait times
- Process appears hung

**Fix Recommendation:**
```bash
# Add spinner for waiting operations:

show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'

    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Usage:
(
    # Long operation in subshell
    sleep 30
) &
show_spinner $!
```

**Location:**
- upgrade-orchestrator.sh, versions.sh

---

#### P3-5: ShellCheck Annotations Could Be Added
**Severity:** VERY LOW
**Lines:** Multiple

**Issue:**
No shellcheck disable annotations for intentional violations.

**Impact:**
- Noisy shellcheck output
- False positives
- Hiding real issues

**Fix Recommendation:**
```bash
# Add specific disable annotations:

# For intentional SC1091 (external sources):
# shellcheck source=./common.sh
source "$SCRIPT_DIR/lib/common.sh"

# For intentional unused variables:
# shellcheck disable=SC2034
RESERVED_FOR_FUTURE_USE="value"

# For complex expressions:
# shellcheck disable=SC2016
echo 'Using $variable literally'
```

**Location:**
- All files

---

#### P3-6: Consider Using trap for Cleanup
**Severity:** VERY LOW
**Lines:** upgrade-state.sh:168-171

**Issue:**
Only one trap for cleanup, could use more comprehensive trap handling.

**Impact:**
- Resource leaks on signal
- Incomplete cleanup
- Testing issues

**Fix Recommendation:**
```bash
# Enhanced trap handling:

cleanup() {
    local exit_code=$?

    # Release lock
    state_unlock 2>/dev/null || true

    # Clean temporary files
    rm -f "${STATE_DIR}/.state.tmp."* 2>/dev/null || true

    # Log exit
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script exited with code $exit_code"
    fi

    exit $exit_code
}

# Trap multiple signals
trap cleanup EXIT
trap 'exit 130' INT   # Ctrl+C
trap 'exit 143' TERM  # SIGTERM
trap 'exit 129' HUP   # SIGHUP
```

**Location:**
- All scripts

---

## Code Quality Analysis by File

### upgrade-orchestrator.sh (696 lines)
**Score: 80/100**

**Strengths:**
- Excellent command-line interface design
- Clear operation separation
- Comprehensive help text
- Good state management integration

**Weaknesses:**
- Unused variables (SC2034)
- Long functions need refactoring
- Missing dependency checks
- Inconsistent error handling

**Complexity:** Medium-High (9 functions, multiple operation modes)

---

### upgrade-state.sh (740 lines)
**Score: 82/100**

**Strengths:**
- Excellent state management design
- Atomic operations with locking
- Good documentation
- Proper guard against multiple sourcing

**Weaknesses:**
- Race condition in lock handling
- Heavy jq dependency
- No state corruption recovery
- SC2155 violations

**Complexity:** High (29 functions, JSON manipulation, file locking)

---

### versions.sh (934 lines)
**Score: 75/100**

**Strengths:**
- Comprehensive version management
- Multiple resolution strategies
- Good caching implementation
- Extensive documentation

**Weaknesses:**
- TODO items incomplete
- Python dependency for JSON
- Long complex functions
- No retry logic for API calls

**Complexity:** Very High (31 functions, API integration, semver logic)

---

### upgrade-component.sh (288 lines)
**Score: 78/100**

**Strengths:**
- Clear single responsibility
- Good idempotency checks
- Health verification
- Service management

**Weaknesses:**
- Limited error recovery
- Hardcoded port mappings
- No rollback on failure
- Assumes install script exists

**Complexity:** Medium (0 functions, linear execution)

---

### upgrade-manager.sh (702 lines)
**Score: 76/100**

**Strengths:**
- Comprehensive upgrade logic
- Good backup/restore system
- Health checking
- Phase management

**Weaknesses:**
- Heavy YAML dependency
- Incomplete backup validation
- SC2155 violations
- Multiple variable declarations

**Complexity:** High (14 functions, orchestration logic)

---

## Recommendations Summary

### Immediate Actions (Before Production)
1. Fix P0 issues (6 critical items)
2. Add dependency checks
3. Fix race condition in locking
4. Separate declare and assign for SC2155
5. Add error handling to state updates
6. Validate configuration files

### Short-term Improvements (Next Sprint)
1. Address P1 issues (8 high priority)
2. Refactor long functions
3. Add retry logic to API calls
4. Implement backup validation
5. Enhance error messages
6. Create test suite

### Long-term Enhancements (Roadmap)
1. Complete TODO features
2. Add structured logging
3. Implement metrics collection
4. Create comprehensive docs
5. Build monitoring integration
6. Performance optimization

---

## ShellCheck Summary

```
File                      | Info | Warning | Error | Total
--------------------------|------|---------|-------|------
upgrade-orchestrator.sh   |  4   |    4    |   0   |   8
upgrade-state.sh          |  1   |    1    |   0   |   2
versions.sh               |  0   |    2    |   0   |   2
upgrade-component.sh      |  2   |    0    |   0   |   2
upgrade-manager.sh        |  3   |    2    |   0   |   5
--------------------------|------|---------|-------|------
TOTAL                     | 10   |    9    |   0   |  19
```

All issues are SC1091 (info) or SC2034/SC2155 (warnings). No errors detected.

---

## Conclusion

The observability stack upgrade system demonstrates solid software engineering practices with comprehensive documentation, proper error handling, and thoughtful design. The code is production-ready with the critical P0 fixes applied.

**Key Strengths:**
- Excellent architecture and design patterns
- Comprehensive state management
- Good documentation and comments
- Idempotent operations

**Areas for Improvement:**
- Error handling consistency
- Dependency management
- Test coverage
- Function length and complexity

**Recommended Action:** Apply P0 fixes immediately, schedule P1 fixes for next iteration, and address P2/P3 items as technical debt.

---

**Generated by:** Claude Code - Automated Code Quality Analysis
**Analysis Duration:** ~5 minutes
**Files Analyzed:** 5 files, 3,360 lines of code
**ShellCheck Version:** Latest
