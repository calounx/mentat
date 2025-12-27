# Version Management System - Migration Guide

## Overview

This guide provides step-by-step instructions for migrating from hardcoded versions to the new version management system.

## Table of Contents

1. [Pre-Migration Checklist](#pre-migration-checklist)
2. [Backward Compatibility](#backward-compatibility)
3. [Migration Steps](#migration-steps)
4. [Module Update Guide](#module-update-guide)
5. [Script Update Guide](#script-update-guide)
6. [Testing & Validation](#testing--validation)
7. [Rollback Plan](#rollback-plan)
8. [FAQ](#faq)

## Pre-Migration Checklist

Before migrating, ensure you have:

- [ ] Backed up current configuration
- [ ] Reviewed current hardcoded versions
- [ ] Tested version management system in non-production
- [ ] Documented current version inventory
- [ ] Planned maintenance window (if needed)

## Backward Compatibility

The version management system is designed to be **100% backward compatible**:

### What Continues to Work

1. **Environment Variables**
   ```bash
   # Old way (still works)
   export MODULE_VERSION="1.7.0"

   # New way (recommended)
   export VERSION_OVERRIDE_NODE_EXPORTER="1.7.0"
   ```

2. **Module Manifests**
   ```yaml
   # module.yaml - version field still works as fallback
   module:
     version: "1.7.0"
   ```

3. **Install Scripts**
   ```bash
   # Old install scripts with hardcoded versions continue to work
   MODULE_VERSION="${MODULE_VERSION:-1.7.0}"
   ```

### What Changes (Optional Improvements)

1. **Version Configuration**
   - New: Centralized in `config/versions.yaml`
   - Old: Scattered across multiple files

2. **Version Resolution**
   - New: Automatic from GitHub API
   - Old: Manual updates required

3. **Flexibility**
   - New: Multiple strategies (latest, pinned, range)
   - Old: Single hardcoded version

## Migration Steps

### Phase 1: Installation (No Changes Required)

Install the version management system files:

```bash
# Files are already in place:
# - scripts/lib/versions.sh
# - config/versions.yaml
# - docs/VERSION_MANAGEMENT_ARCHITECTURE.md
# - docs/VERSION_MANAGEMENT_MIGRATION.md

# Make versions.sh executable
chmod +x scripts/lib/versions.sh
```

### Phase 2: Configuration Review

1. **Review default configuration:**
   ```bash
   cat config/versions.yaml
   ```

2. **Customize for your environment:**
   ```bash
   # Copy and customize if needed
   cp config/versions.yaml config/versions.yaml.backup

   # Edit global settings
   vim config/versions.yaml
   ```

3. **Set environment (optional):**
   ```bash
   # For production
   export OBSERVABILITY_ENV=production

   # For staging
   export OBSERVABILITY_ENV=staging

   # For development
   export OBSERVABILITY_ENV=development
   ```

### Phase 3: Gradual Adoption (Recommended)

You can adopt the version management system gradually, one component at a time:

#### Step 1: Test with a Single Component

```bash
# Source the library
source scripts/lib/versions.sh

# Test version resolution for node_exporter
version=$(resolve_version "node_exporter")
echo "Resolved version: $version"

# Compare with current version
current_version=$(cat modules/_core/node_exporter/module.yaml | grep 'version:' | awk '{print $2}' | tr -d '"')
echo "Current version: $current_version"
```

#### Step 2: Update Module Loader (Already Done)

The module loader in `scripts/lib/module-loader.sh` can be enhanced to use version management:

```bash
# Add to module-loader.sh (after line 21)
# Source version management library if available
if [[ -f "$LIB_DIR/versions.sh" ]]; then
    source "$LIB_DIR/versions.sh"
    VERSION_MANAGEMENT_AVAILABLE=true
else
    VERSION_MANAGEMENT_AVAILABLE=false
fi
```

```bash
# Update module_version function (around line 151)
module_version() {
    local module_name="$1"

    # Try version management system first
    if [[ "$VERSION_MANAGEMENT_AVAILABLE" == "true" ]]; then
        local resolved_version
        if resolved_version=$(resolve_version "$module_name" 2>/dev/null); then
            echo "$resolved_version"
            return 0
        fi
    fi

    # Fallback to manifest
    module_get_nested "$module_name" "module" "version"
}
```

#### Step 3: Test Installation

```bash
# Test installation with version management
./scripts/setup-monitored-host.sh --modules node_exporter --dry-run

# Verify version resolution
print_version_info node_exporter
```

### Phase 4: Production Deployment

#### Option A: Keep Everything As-Is (Zero Changes)

The system works with existing configurations:

```bash
# No changes needed - system uses fallback chain:
# 1. Environment variables (if set)
# 2. Module manifest versions
# 3. Everything continues working as before
```

#### Option B: Enable Version Management (Recommended)

```bash
# 1. Set desired strategy in config/versions.yaml
# Components will automatically use latest versions

# 2. For production stability, use pinned strategy:
vim config/versions.yaml
# Set: default_strategy: pinned

# 3. Deploy and test
./scripts/setup-monitored-host.sh --modules node_exporter
```

## Module Update Guide

### Current Module Structure

```yaml
# modules/_core/node_exporter/module.yaml
module:
  name: node_exporter
  version: "1.7.0"  # Hardcoded version
```

### Updated Module Structure (Optional)

```yaml
# modules/_core/node_exporter/module.yaml
module:
  name: node_exporter
  version: "1.7.0"  # Kept as fallback

  # NEW: Version management metadata (optional)
  version_management:
    github_repo: prometheus/node_exporter
    strategy: latest  # Override global strategy
    minimum_version: "1.5.0"
```

### Migration Script for Modules

```bash
#!/bin/bash
# migrate-module-versions.sh

# This script is OPTIONAL - modules work fine as-is
# Use this if you want to add version management metadata to module manifests

for module_dir in modules/_core/*; do
    module_name=$(basename "$module_dir")
    manifest="$module_dir/module.yaml"

    [[ ! -f "$manifest" ]] && continue

    echo "Processing $module_name..."

    # Add version_management section if not present
    if ! grep -q "version_management:" "$manifest"; then
        cat >> "$manifest" << 'EOF'

# Version management configuration (optional)
# Overrides global settings from config/versions.yaml
#version_management:
#  strategy: latest
#  github_repo: org/repo
#  minimum_version: "1.0.0"
EOF
        echo "  Added version_management section (commented out)"
    fi
done

echo "Module migration complete!"
```

## Script Update Guide

### Install Script Pattern (Current)

```bash
# modules/_core/node_exporter/install.sh (lines 36-37)
MODULE_NAME="${MODULE_NAME:-node_exporter}"
MODULE_VERSION="${MODULE_VERSION:-1.7.0}"  # Hardcoded fallback
```

### Install Script Pattern (Updated - Backward Compatible)

```bash
# modules/_core/node_exporter/install.sh
MODULE_NAME="${MODULE_NAME:-node_exporter}"

# Try version management system first, fallback to hardcoded
if [[ -f "$LIB_DIR/versions.sh" ]]; then
    source "$LIB_DIR/versions.sh"
    MODULE_VERSION="${MODULE_VERSION:-$(resolve_version "$MODULE_NAME" 2>/dev/null || echo "1.7.0")}"
else
    MODULE_VERSION="${MODULE_VERSION:-1.7.0}"
fi
```

### Automated Script Update

```bash
#!/bin/bash
# update-install-scripts.sh

for install_script in modules/_core/*/install.sh; do
    module_name=$(basename "$(dirname "$install_script")")

    echo "Updating $install_script..."

    # Backup original
    cp "$install_script" "$install_script.backup"

    # Update MODULE_VERSION line
    sed -i.bak '/^MODULE_VERSION=/ {
        # Read the hardcoded fallback version
        s/MODULE_VERSION="${MODULE_VERSION:-\([^}]*\)}"/MODULE_VERSION="${MODULE_VERSION:-$(resolve_version "$MODULE_NAME" 2>\/dev\/null || echo "\1")}"/
    }' "$install_script"

    # Add version.sh sourcing after LIB_DIR definition
    sed -i.bak '/^LIB_DIR=/a\
# Source version management library if available\
if [[ -f "$LIB_DIR/versions.sh" ]]; then\
    source "$LIB_DIR/versions.sh"\
fi' "$install_script"
done

echo "Install scripts updated!"
```

## Testing & Validation

### Unit Tests

```bash
#!/bin/bash
# tests/test-version-management.sh

source scripts/lib/versions.sh

test_version_comparison() {
    echo "Testing version comparison..."

    local result
    result=$(compare_versions "1.8.0" "1.7.0")
    [[ $result -eq 1 ]] || { echo "FAIL: 1.8.0 > 1.7.0"; return 1; }

    result=$(compare_versions "1.7.0" "1.7.0")
    [[ $result -eq 0 ]] || { echo "FAIL: 1.7.0 == 1.7.0"; return 1; }

    result=$(compare_versions "1.6.0" "1.7.0")
    [[ $result -eq -1 ]] || { echo "FAIL: 1.6.0 < 1.7.0"; return 1; }

    echo "PASS: version comparison"
}

test_version_validation() {
    echo "Testing version validation..."

    validate_version "1.7.0" || { echo "FAIL: valid version"; return 1; }
    validate_version "1.7" && { echo "FAIL: invalid version"; return 1; }

    echo "PASS: version validation"
}

test_version_resolution() {
    echo "Testing version resolution..."

    # Test with environment override
    export VERSION_OVERRIDE_NODE_EXPORTER="1.8.0"
    local version
    version=$(resolve_version "node_exporter")
    [[ "$version" == "1.8.0" ]] || { echo "FAIL: env override"; return 1; }
    unset VERSION_OVERRIDE_NODE_EXPORTER

    echo "PASS: version resolution"
}

# Run tests
test_version_comparison || exit 1
test_version_validation || exit 1
test_version_resolution || exit 1

echo "All tests passed!"
```

### Integration Tests

```bash
#!/bin/bash
# tests/test-integration.sh

source scripts/lib/versions.sh

echo "Testing GitHub API integration..."

# Test rate limit status
echo "Rate limit status:"
github_rate_limit_status

# Test fetching latest version
echo ""
echo "Testing latest version fetch for node_exporter:"
version=$(get_latest_version "node_exporter")
if [[ -n "$version" ]]; then
    echo "SUCCESS: Got version $version"
else
    echo "FAIL: Could not fetch version"
    exit 1
fi

# Test cache
echo ""
echo "Testing cache (should hit cache on second call):"
version2=$(get_latest_version "node_exporter")
[[ "$version" == "$version2" ]] || { echo "FAIL: cache mismatch"; exit 1; }

echo ""
echo "Integration tests passed!"
```

### Smoke Tests

```bash
#!/bin/bash
# tests/smoke-test.sh

echo "Running smoke tests for version management..."

# Test 1: Library loads without errors
source scripts/lib/versions.sh || { echo "FAIL: Library load"; exit 1; }

# Test 2: Config file exists and is valid
[[ -f config/versions.yaml ]] || { echo "FAIL: Config missing"; exit 1; }

# Test 3: Can resolve all configured components
for component in node_exporter mysqld_exporter nginx_exporter phpfpm_exporter fail2ban_exporter promtail; do
    echo "Resolving $component..."
    version=$(resolve_version "$component")
    [[ -n "$version" ]] || { echo "FAIL: $component resolution"; exit 1; }
    echo "  $component: $version"
done

echo "All smoke tests passed!"
```

## Rollback Plan

If you encounter issues, you can easily roll back:

### Step 1: Stop Using Version Management

```bash
# Simply don't source the library
# Old behavior is preserved automatically

# If module-loader.sh was updated, revert:
git checkout scripts/lib/module-loader.sh
```

### Step 2: Remove Configuration

```bash
# Optional: Remove version config
mv config/versions.yaml config/versions.yaml.disabled

# Remove cache
rm -rf ~/.cache/observability-stack/versions
```

### Step 3: Restore Original Scripts

```bash
# If install scripts were updated, restore backups:
for backup in modules/_core/*/install.sh.backup; do
    original="${backup%.backup}"
    cp "$backup" "$original"
done
```

## FAQ

### Q: Do I need to update all my modules immediately?

**A:** No! The system is fully backward compatible. Modules will continue using their hardcoded versions until you explicitly opt into version management.

### Q: What happens if GitHub API is down?

**A:** The system automatically falls back to:
1. Cached versions (if available)
2. Config file versions
3. Module manifest versions

Your installation will never fail due to GitHub API issues.

### Q: Can I use different strategies for different environments?

**A:** Yes! Set the `OBSERVABILITY_ENV` environment variable:
```bash
export OBSERVABILITY_ENV=production  # Uses pinned versions
export OBSERVABILITY_ENV=development # Uses latest versions
```

### Q: How do I pin a specific version?

**A:** Three ways:

1. **Environment variable (highest priority):**
   ```bash
   export VERSION_OVERRIDE_NODE_EXPORTER="1.7.0"
   ```

2. **Config file:**
   ```yaml
   components:
     node_exporter:
       strategy: pinned
       version: "1.7.0"
   ```

3. **Module manifest (fallback):**
   ```yaml
   module:
     version: "1.7.0"
   ```

### Q: Does this work offline?

**A:** Yes! Set offline mode:
```bash
export VERSION_OFFLINE_MODE=true
```

Or in config:
```yaml
global:
  offline_mode: true
```

### Q: How do I update to latest versions?

**A:** Two ways:

1. **Automatic (strategy: latest):**
   ```yaml
   components:
     node_exporter:
       strategy: latest
   ```

2. **Manual cache refresh:**
   ```bash
   source scripts/lib/versions.sh
   update_version_cache node_exporter
   ```

### Q: Can I test a specific version before committing?

**A:** Yes:
```bash
# Override for testing
export VERSION_OVERRIDE_NODE_EXPORTER="1.8.0"

# Install and test
./scripts/setup-monitored-host.sh --modules node_exporter

# If satisfied, update config:
vim config/versions.yaml
```

### Q: What about rate limiting?

**A:** The system handles GitHub rate limits automatically:
- Caches responses (15 min TTL by default)
- Falls back to config/manifest on rate limit
- Supports GitHub token for higher limits (5000/hour)

Set token:
```bash
export GITHUB_TOKEN="your_github_token"
```

### Q: How do I verify what version will be installed?

**A:**
```bash
source scripts/lib/versions.sh
print_version_info node_exporter
```

Output:
```
Version Information for: node_exporter
========================================
Strategy: latest
Resolved: 1.7.0
Config:   1.7.0
Manifest: 1.7.0
Latest:   1.7.0
```

## Summary

The version management system is designed for **zero-friction adoption**:

1. **No breaking changes** - Everything works as before
2. **Gradual migration** - Adopt component by component
3. **Easy rollback** - Revert anytime without data loss
4. **Flexible strategies** - Choose what works for your environment
5. **Robust fallbacks** - Never blocks installation

Start with testing in development, gain confidence, then gradually roll out to production.
