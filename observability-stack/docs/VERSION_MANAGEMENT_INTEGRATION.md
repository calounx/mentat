# Version Management System - Integration Guide

## Overview

This document describes how to integrate the version management system with existing scripts and modules.

## Integration with module-loader.sh

### Backward-Compatible Integration

Add the following code to `scripts/lib/module-loader.sh`:

```bash
# After line 21 (after LIB_DIR definition)

#===============================================================================
# VERSION MANAGEMENT INTEGRATION
#===============================================================================

# Source version management library if available
VERSION_MANAGEMENT_AVAILABLE=false
if [[ -f "$LIB_DIR/versions.sh" ]]; then
    if source "$LIB_DIR/versions.sh" 2>/dev/null; then
        VERSION_MANAGEMENT_AVAILABLE=true
        _log_debug "Version management system loaded"
    else
        _log_warn "Failed to load version management system, using fallback"
    fi
fi
```

### Enhanced module_version Function

Update the `module_version` function (around line 151):

```bash
# Get module version
# Usage: module_version "module_name"
module_version() {
    local module_name="$1"

    # Priority 1: Environment variable override
    local env_var="VERSION_OVERRIDE_${module_name^^}"
    env_var="${env_var//-/_}"  # Replace hyphens with underscores
    if [[ -n "${!env_var:-}" ]]; then
        echo "${!env_var}"
        return 0
    fi

    # Priority 2: MODULE_VERSION environment variable (backward compatibility)
    if [[ -n "${MODULE_VERSION:-}" ]]; then
        echo "$MODULE_VERSION"
        return 0
    fi

    # Priority 3: Version management system
    if [[ "$VERSION_MANAGEMENT_AVAILABLE" == "true" ]]; then
        local resolved_version
        if resolved_version=$(resolve_version "$module_name" 2>/dev/null); then
            echo "$resolved_version"
            return 0
        fi
    fi

    # Priority 4: Module manifest (fallback)
    module_get_nested "$module_name" "module" "version"
}
```

### Optional: Add Version Info Command

Add a new command to display version information:

```bash
# Show version information for a module
# Usage: show_module_version_info "module_name"
show_module_version_info() {
    local module_name="$1"

    if [[ "$VERSION_MANAGEMENT_AVAILABLE" != "true" ]]; then
        echo "Version management system not available"
        return 1
    fi

    print_version_info "$module_name"
}
```

## Integration with Install Scripts

### Pattern 1: Minimal Changes (Recommended)

This pattern requires minimal changes to existing install scripts:

```bash
#!/bin/bash
# modules/_core/node_exporter/install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../../../scripts/lib" 2>/dev/null && pwd)" || LIB_DIR="$(cd "$SCRIPT_DIR/../../scripts/lib" && pwd)"

# Source common library
if [[ -f "$LIB_DIR/common.sh" ]]; then
    source "$LIB_DIR/common.sh"
fi

# Source version management library
if [[ -f "$LIB_DIR/versions.sh" ]]; then
    source "$LIB_DIR/versions.sh"
fi

MODULE_NAME="${MODULE_NAME:-node_exporter}"

# Enhanced version resolution with fallback
if type resolve_version &>/dev/null; then
    MODULE_VERSION="${MODULE_VERSION:-$(resolve_version "$MODULE_NAME" 2>/dev/null || echo "1.7.0")}"
else
    MODULE_VERSION="${MODULE_VERSION:-1.7.0}"
fi

# Rest of install script continues as before...
```

### Pattern 2: Full Integration

This pattern provides complete integration with enhanced features:

```bash
#!/bin/bash
# modules/_core/node_exporter/install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../../../scripts/lib" 2>/dev/null && pwd)" || LIB_DIR="$(cd "$SCRIPT_DIR/../../scripts/lib" && pwd)"

# Source libraries
[[ -f "$LIB_DIR/common.sh" ]] && source "$LIB_DIR/common.sh"
[[ -f "$LIB_DIR/versions.sh" ]] && source "$LIB_DIR/versions.sh"

MODULE_NAME="${MODULE_NAME:-node_exporter}"

# Resolve version with full error handling
resolve_module_version() {
    local version=""

    # Try version management system
    if type resolve_version &>/dev/null; then
        if version=$(resolve_version "$MODULE_NAME" 2>&1); then
            log_info "Resolved version from version management: $version"
            echo "$version"
            return 0
        else
            log_warn "Version management resolution failed: $version"
        fi
    fi

    # Fallback to environment variable
    if [[ -n "${MODULE_VERSION:-}" ]]; then
        log_info "Using version from MODULE_VERSION: $MODULE_VERSION"
        echo "$MODULE_VERSION"
        return 0
    fi

    # Ultimate fallback
    local fallback_version="1.7.0"
    log_warn "Using hardcoded fallback version: $fallback_version"
    echo "$fallback_version"
}

MODULE_VERSION=$(resolve_module_version)

# Validate version
if type validate_version &>/dev/null; then
    if ! validate_version "$MODULE_VERSION"; then
        log_error "Invalid version: $MODULE_VERSION"
        exit 1
    fi
fi

log_info "Installing $MODULE_NAME version $MODULE_VERSION"

# Rest of install script...
```

## Integration with Setup Scripts

### setup-monitored-host.sh Integration

Add version management options to the setup script:

```bash
#!/bin/bash
# scripts/setup-monitored-host.sh

# After sourcing libraries, add:

# Source version management
if [[ -f "$LIB_DIR/versions.sh" ]]; then
    source "$LIB_DIR/versions.sh"
    VERSION_MANAGEMENT_ENABLED=true
else
    VERSION_MANAGEMENT_ENABLED=false
fi

# Add new command-line options
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version-strategy)
                VERSION_STRATEGY="$2"
                shift 2
                ;;
            --version-info)
                SHOW_VERSION_INFO=true
                shift
                ;;
            --update-cache)
                UPDATE_VERSION_CACHE=true
                shift
                ;;
            --offline)
                export VERSION_OFFLINE_MODE=true
                shift
                ;;
            *)
                # Other arguments
                shift
                ;;
        esac
    done
}

# Add version info display
show_versions() {
    if [[ "$VERSION_MANAGEMENT_ENABLED" != "true" ]]; then
        echo "Version management not available"
        return
    fi

    echo "Component Versions:"
    echo "===================="
    for module in "${MODULES[@]}"; do
        local version
        version=$(resolve_version "$module" 2>/dev/null || echo "unknown")
        printf "%-20s %s\n" "$module:" "$version"
    done
    echo ""
}

# Call in main function
main() {
    parse_arguments "$@"

    if [[ "${SHOW_VERSION_INFO:-false}" == "true" ]]; then
        show_versions
        exit 0
    fi

    if [[ "${UPDATE_VERSION_CACHE:-false}" == "true" ]]; then
        echo "Updating version cache..."
        for module in "${MODULES[@]}"; do
            update_version_cache "$module" 2>/dev/null || true
        done
        exit 0
    fi

    # Continue with normal installation...
}
```

## Integration with Module Manifests

### Enhanced module.yaml Schema

You can optionally extend module.yaml to include version management metadata:

```yaml
# modules/_core/node_exporter/module.yaml

module:
  name: node_exporter
  display_name: Node Exporter
  version: "1.7.0"  # Fallback version
  description: Exports system metrics

  # Optional: Version management configuration
  version_management:
    # Override global strategy for this module
    strategy: latest

    # GitHub repository for releases
    github_repo: prometheus/node_exporter

    # Minimum supported version
    minimum_version: "1.5.0"

    # Version constraints
    constraints:
      # Only allow stable releases
      exclude_prereleases: true

      # Architecture constraint
      architecture: linux-amd64

    # Download configuration
    download:
      url_template: "https://github.com/prometheus/node_exporter/releases/download/v{VERSION}/node_exporter-{VERSION}.linux-amd64.tar.gz"
      checksum_url: "https://github.com/prometheus/node_exporter/releases/download/v{VERSION}/sha256sums.txt"
      archive_type: tar.gz
      binary_path: "node_exporter-{VERSION}.linux-amd64/node_exporter"

    # Compatibility requirements
    compatible_with:
      prometheus: ">=2.0.0"

# Rest of module.yaml...
```

### Parsing Module Version Config

Add helper function to module-loader.sh:

```bash
# Get version management config from module manifest
# Usage: module_version_config "module_name" "key"
module_version_config() {
    local module_name="$1"
    local key="$2"

    module_get_nested "$module_name" "module" "version_management" "$key"
}

# Example usage:
# github_repo=$(module_version_config "node_exporter" "github_repo")
# strategy=$(module_version_config "node_exporter" "strategy")
```

## CLI Tool Integration

Create a standalone CLI tool for version management:

```bash
#!/bin/bash
# scripts/version-manager

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/versions.sh"

usage() {
    cat << EOF
Version Manager - Manage component versions

Usage: $0 <command> [options]

Commands:
    resolve <component>              Resolve version for component
    info <component>                 Show version information
    list                            List all components and versions
    update-cache <component>        Update version cache
    clear-cache [component]         Clear version cache
    validate <component>            Validate component configuration
    compare <v1> <v2>               Compare two versions
    check-compat <comp> <version>   Check version compatibility
    rate-limit                      Show GitHub API rate limit

Options:
    --strategy <strategy>           Override version strategy
    --offline                       Use offline mode
    --debug                         Enable debug output

Examples:
    $0 resolve node_exporter
    $0 info node_exporter
    $0 list
    $0 update-cache node_exporter
    $0 compare 1.8.0 1.7.0
    $0 rate-limit

EOF
}

cmd_resolve() {
    local component="$1"
    local strategy="${2:-}"

    if [[ -n "$strategy" ]]; then
        resolve_version "$component" "$strategy"
    else
        resolve_version "$component"
    fi
}

cmd_info() {
    local component="$1"
    print_version_info "$component"
}

cmd_list() {
    echo "Component Versions:"
    echo "===================="

    # List all components from config
    local components=(
        node_exporter
        mysqld_exporter
        nginx_exporter
        phpfpm_exporter
        fail2ban_exporter
        promtail
        prometheus
        loki
    )

    for component in "${components[@]}"; do
        local version
        version=$(resolve_version "$component" 2>/dev/null || echo "unknown")
        printf "%-20s %s\n" "$component:" "$version"
    done
}

cmd_update_cache() {
    local component="$1"
    update_version_cache "$component"
}

cmd_clear_cache() {
    local component="${1:-}"

    if [[ -n "$component" ]]; then
        cache_invalidate "$component"
        echo "Cache cleared for $component"
    else
        rm -rf "$VERSION_CACHE_DIR"
        echo "All version cache cleared"
    fi
}

cmd_validate() {
    local component="$1"
    if validate_component_config "$component"; then
        echo "Configuration valid for $component"
    else
        echo "Configuration invalid for $component"
        exit 1
    fi
}

cmd_compare() {
    local v1="$1"
    local v2="$2"

    local result
    result=$(compare_versions "$v1" "$v2")

    case $result in
        -1)
            echo "$v1 < $v2"
            ;;
        0)
            echo "$v1 == $v2"
            ;;
        1)
            echo "$v1 > $v2"
            ;;
    esac
}

cmd_check_compat() {
    local component="$1"
    local version="$2"

    if is_version_compatible "$component" "$version"; then
        echo "Version $version is compatible for $component"
    else
        echo "Version $version is NOT compatible for $component"
        exit 1
    fi
}

cmd_rate_limit() {
    github_rate_limit_status
}

# Main
main() {
    [[ $# -eq 0 ]] && { usage; exit 1; }

    local command="$1"
    shift

    # Parse global options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --strategy)
                STRATEGY="$2"
                shift 2
                ;;
            --offline)
                export VERSION_OFFLINE_MODE=true
                shift
                ;;
            --debug)
                export VERSION_DEBUG=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    case "$command" in
        resolve)
            cmd_resolve "$@"
            ;;
        info)
            cmd_info "$@"
            ;;
        list)
            cmd_list
            ;;
        update-cache)
            cmd_update_cache "$@"
            ;;
        clear-cache)
            cmd_clear_cache "$@"
            ;;
        validate)
            cmd_validate "$@"
            ;;
        compare)
            cmd_compare "$@"
            ;;
        check-compat)
            cmd_check_compat "$@"
            ;;
        rate-limit)
            cmd_rate_limit
            ;;
        *)
            echo "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
```

Make it executable:
```bash
chmod +x scripts/version-manager
```

## Usage Examples

### Using the CLI Tool

```bash
# Resolve version for a component
./scripts/version-manager resolve node_exporter

# Show detailed version info
./scripts/version-manager info node_exporter

# List all component versions
./scripts/version-manager list

# Update cache for a component
./scripts/version-manager update-cache node_exporter

# Compare versions
./scripts/version-manager compare 1.8.0 1.7.0

# Check rate limit
./scripts/version-manager rate-limit

# Use offline mode
./scripts/version-manager resolve node_exporter --offline
```

### Using in Scripts

```bash
# Source the library
source scripts/lib/versions.sh

# Resolve version
version=$(resolve_version "node_exporter")
echo "Will install: $version"

# Override with environment variable
export VERSION_OVERRIDE_NODE_EXPORTER="1.8.0"
version=$(resolve_version "node_exporter")
echo "Will install: $version"  # Output: 1.8.0

# Check version compatibility
if version_satisfies "1.8.0" ">=1.7.0"; then
    echo "Version meets requirements"
fi

# Compare versions
result=$(compare_versions "1.8.0" "1.7.0")
if [[ $result -eq 1 ]]; then
    echo "1.8.0 is newer than 1.7.0"
fi
```

### Integration in Makefiles

```makefile
# Makefile

.PHONY: install-node-exporter
install-node-exporter:
	@VERSION=$$(./scripts/version-manager resolve node_exporter); \
	echo "Installing node_exporter version $$VERSION"; \
	MODULE_VERSION=$$VERSION ./modules/_core/node_exporter/install.sh

.PHONY: list-versions
list-versions:
	@./scripts/version-manager list

.PHONY: update-caches
update-caches:
	@for comp in node_exporter mysqld_exporter nginx_exporter; do \
		./scripts/version-manager update-cache $$comp; \
	done
```

## Best Practices

1. **Always provide fallbacks**
   - Never rely solely on external APIs
   - Have hardcoded fallback versions

2. **Cache aggressively**
   - Reduce API calls
   - Support offline scenarios

3. **Validate before using**
   - Check version format
   - Verify compatibility

4. **Log version decisions**
   - Help with debugging
   - Audit trail for production

5. **Test integration thoroughly**
   - Unit tests for version functions
   - Integration tests for install flows
   - Smoke tests for all components

## Troubleshooting

### Version resolution fails

```bash
# Check what's happening
export VERSION_DEBUG=true
resolve_version node_exporter

# Check rate limit
./scripts/version-manager rate-limit

# Try offline mode
export VERSION_OFFLINE_MODE=true
resolve_version node_exporter
```

### Cache issues

```bash
# Clear cache
./scripts/version-manager clear-cache

# Or manually
rm -rf ~/.cache/observability-stack/versions
```

### Configuration errors

```bash
# Validate configuration
./scripts/version-manager validate node_exporter

# Check config file syntax
yamllint config/versions.yaml
```
