# Version Management System - Complete Implementation

## Overview

A robust version management system for the observability-stack that eliminates hardcoded versions and provides flexible version resolution strategies with GitHub API integration, caching, and offline support.

## Features

- **Multiple Version Strategies**: latest, pinned, lts, range
- **GitHub API Integration**: Automatic version detection from releases
- **Multi-Layer Caching**: Reduces API calls and supports offline mode
- **Semantic Version Comparison**: Full semver support
- **Backward Compatible**: Works with existing scripts without modification
- **Offline Mode**: No internet required when using cached/config versions
- **Rate Limit Handling**: Automatic fallback when GitHub rate limit hit
- **Environment Overrides**: Easy version pinning via environment variables
- **Production Ready**: Robust fallback chain ensures reliability

## Quick Start

### 1. Use the CLI Tool

```bash
# Resolve version for a component
./scripts/version-manager resolve node_exporter

# Show detailed information
./scripts/version-manager info node_exporter

# List all components
./scripts/version-manager list

# Update cache
./scripts/version-manager update-cache node_exporter
```

### 2. Use in Scripts

```bash
#!/bin/bash

# Source the library
source scripts/lib/versions.sh

# Resolve version
version=$(resolve_version "node_exporter")

# Use the version
echo "Installing $version"
```

### 3. Configure Strategy

Edit `config/versions.yaml`:

```yaml
components:
  node_exporter:
    strategy: latest  # or pinned, lts, range
    github_repo: prometheus/node_exporter
    fallback_version: "1.7.0"
```

## Architecture

### Service Boundaries

```
┌─────────────────────────────────────────────────────────────┐
│                  Version Management Layer                    │
├─────────────────────────────────────────────────────────────┤
│  Version Resolution → Strategy Selection → Validation       │
├─────────────────────────────────────────────────────────────┤
│              Version Source Abstraction Layer                │
├─────────────────────────────────────────────────────────────┤
│  GitHub API → Config File → Cache → Module Manifest         │
└─────────────────────────────────────────────────────────────┘
```

### Version Resolution Priority

1. **Environment Override** (highest)
   ```bash
   export VERSION_OVERRIDE_NODE_EXPORTER="1.8.0"
   ```

2. **Strategy-Based Resolution**
   - `latest` → GitHub API → Cache → Config → Manifest
   - `pinned` → Config → Manifest
   - `range` → GitHub API (filtered) → Config → Manifest
   - `lts` → GitHub API (LTS) → Config → Manifest

3. **Config Fallback**
   ```yaml
   fallback_version: "1.7.0"
   ```

4. **Module Manifest** (lowest)
   ```yaml
   module:
     version: "1.7.0"
   ```

## File Structure

```
observability-stack/
├── config/
│   └── versions.yaml                 # Version configuration
├── scripts/
│   ├── lib/
│   │   └── versions.sh              # Core library
│   └── version-manager              # CLI tool
├── tests/
│   └── test-version-management.sh   # Test suite
└── docs/
    ├── VERSION_MANAGEMENT_ARCHITECTURE.md
    ├── VERSION_MANAGEMENT_MIGRATION.md
    ├── VERSION_MANAGEMENT_INTEGRATION.md
    ├── VERSION_MANAGEMENT_QUICKSTART.md
    └── VERSION_MANAGEMENT_README.md
```

## Components

### 1. Core Library (scripts/lib/versions.sh)

Main functions:

```bash
# Version resolution
resolve_version <component> [strategy]
get_latest_version <component>
get_config_version <component>
get_manifest_version <component>

# Version comparison
compare_versions <v1> <v2>
version_satisfies <version> <constraint>
version_in_range <version> <range>

# Validation
validate_version <version>
validate_component_config <component>
is_version_compatible <component> <version>

# Cache management
cache_get <component> <key>
cache_set <component> <key> <value>
cache_invalidate <component>
cache_cleanup

# GitHub API
github_latest_release <repo>
github_list_releases <repo> [limit]
github_extract_version <json>
github_rate_limit_status

# Utilities
print_version_info <component>
update_version_cache <component>
get_version_strategy <component>
load_version_config
```

### 2. Configuration (config/versions.yaml)

```yaml
global:
  default_strategy: latest
  github_api:
    enabled: true
    timeout: 10
    cache_ttl: 900
  cache:
    enabled: true
    directory: ~/.cache/observability-stack/versions
    ttl: 900
  offline_mode: false

components:
  node_exporter:
    strategy: latest
    github_repo: prometheus/node_exporter
    fallback_version: "1.7.0"
    minimum_version: "1.5.0"

environments:
  production:
    default_strategy: pinned
    offline_mode: true
  development:
    default_strategy: latest
```

### 3. CLI Tool (scripts/version-manager)

Commands:
- `resolve <component>` - Resolve version
- `info <component>` - Show version info
- `list` - List all components
- `update-cache <component>` - Update cache
- `clear-cache [component]` - Clear cache
- `validate <component>` - Validate config
- `compare <v1> <v2>` - Compare versions
- `rate-limit` - Show API rate limit

### 4. Test Suite (tests/test-version-management.sh)

Comprehensive tests:
- Version validation
- Version comparison
- Version constraints
- Cache operations
- Version resolution
- GitHub API integration
- Full workflow integration

## Usage Examples

### Example 1: Basic Version Resolution

```bash
#!/bin/bash
source scripts/lib/versions.sh

# Get version
version=$(resolve_version "node_exporter")
echo "Version: $version"

# Validate
if validate_version "$version"; then
    echo "Valid version"
fi

# Use it
MODULE_VERSION="$version" ./install.sh
```

### Example 2: Version Comparison

```bash
source scripts/lib/versions.sh

current="1.7.0"
latest=$(get_latest_version "node_exporter")

if [[ $(compare_versions "$latest" "$current") -eq 1 ]]; then
    echo "Update available: $current → $latest"
fi
```

### Example 3: Environment Override

```bash
# Pin specific version for testing
export VERSION_OVERRIDE_NODE_EXPORTER="1.8.0"

# Resolve (will use override)
version=$(resolve_version "node_exporter")
echo "$version"  # Output: 1.8.0
```

### Example 4: Offline Mode

```bash
# Enable offline mode
export VERSION_OFFLINE_MODE=true

# Resolve (will use cache/config/manifest only)
version=$(resolve_version "node_exporter")
```

### Example 5: Custom Strategy

```bash
# Resolve with specific strategy
version=$(resolve_version "node_exporter" "pinned")

# Or configure in config/versions.yaml
```

## Integration Guide

### Module Loader Integration

Add to `scripts/lib/module-loader.sh`:

```bash
# After line 21 (after LIB_DIR definition)
VERSION_MANAGEMENT_AVAILABLE=false
if [[ -f "$LIB_DIR/versions.sh" ]]; then
    if source "$LIB_DIR/versions.sh" 2>/dev/null; then
        VERSION_MANAGEMENT_AVAILABLE=true
    fi
fi

# Update module_version function (around line 151)
module_version() {
    local module_name="$1"

    # Try environment override
    local env_var="VERSION_OVERRIDE_${module_name^^}"
    env_var="${env_var//-/_}"
    [[ -n "${!env_var:-}" ]] && { echo "${!env_var}"; return 0; }

    # Try MODULE_VERSION
    [[ -n "${MODULE_VERSION:-}" ]] && { echo "$MODULE_VERSION"; return 0; }

    # Try version management
    if [[ "$VERSION_MANAGEMENT_AVAILABLE" == "true" ]]; then
        local version
        if version=$(resolve_version "$module_name" 2>/dev/null); then
            echo "$version"
            return 0
        fi
    fi

    # Fallback to manifest
    module_get_nested "$module_name" "module" "version"
}
```

### Install Script Integration

Minimal change pattern:

```bash
# Before (hardcoded)
MODULE_VERSION="${MODULE_VERSION:-1.7.0}"

# After (with fallback)
if [[ -f "$LIB_DIR/versions.sh" ]]; then
    source "$LIB_DIR/versions.sh"
    MODULE_VERSION="${MODULE_VERSION:-$(resolve_version "$MODULE_NAME" 2>/dev/null || echo "1.7.0")}"
else
    MODULE_VERSION="${MODULE_VERSION:-1.7.0}"
fi
```

## Configuration Strategies

### Development Environment

```yaml
global:
  default_strategy: latest
  github_api:
    cache_ttl: 300  # 5 minutes
  offline_mode: false
```

### Staging Environment

```yaml
global:
  default_strategy: latest
  github_api:
    cache_ttl: 1800  # 30 minutes
  exclude_prereleases: false  # Test pre-releases
```

### Production Environment

```yaml
global:
  default_strategy: pinned
  offline_mode: true  # No external API calls

components:
  node_exporter:
    strategy: pinned
    version: "1.7.0"  # Locked version
```

## Performance

### Caching Strategy

- **GitHub API responses**: 15 min TTL (configurable)
- **Component metadata**: 24 hour TTL (configurable)
- **Cache directory**: `~/.cache/observability-stack/versions/`
- **Automatic cleanup**: Removes entries older than max_age

### Rate Limit Optimization

- Conditional requests (If-None-Match)
- Aggressive caching
- Automatic fallback on rate limit
- GitHub token support (5000 req/hr vs 60)

### Offline Support

Works without internet:
1. Uses cached data (if available)
2. Falls back to config file
3. Falls back to module manifest
4. Never blocks installation

## Security

### GitHub Token

Optional but recommended:

```bash
export GITHUB_TOKEN="ghp_your_token_here"
```

Benefits:
- Higher rate limit (5000/hr)
- Access to private repos (if needed)

### Checksum Verification

Version management integrates with existing checksum verification:

```bash
# Downloads still verify checksums
download_and_verify "$url" "$file" "$checksum_url"
```

### Cache Security

- Cache directory permissions: 700
- JSON validation
- Version format validation

## Troubleshooting

### Rate Limit Hit

```bash
# Check status
./scripts/version-manager rate-limit

# Solution 1: Use token
export GITHUB_TOKEN="your_token"

# Solution 2: Wait
# Rate limit resets every hour

# Solution 3: Offline mode
export VERSION_OFFLINE_MODE=true
```

### Version Resolution Fails

```bash
# Enable debug
export VERSION_DEBUG=true
./scripts/version-manager resolve node_exporter

# Check config
./scripts/version-manager validate node_exporter

# Manual fallback
export VERSION_OVERRIDE_NODE_EXPORTER="1.7.0"
```

### Cache Issues

```bash
# Clear cache
./scripts/version-manager clear-cache

# Force refresh
./scripts/version-manager update-cache node_exporter

# Check cache directory
ls -la ~/.cache/observability-stack/versions/
```

## Testing

### Run Test Suite

```bash
# All tests
./tests/test-version-management.sh

# With debug output
export VERSION_DEBUG=true
./tests/test-version-management.sh

# Offline mode tests
export VERSION_OFFLINE_MODE=true
./tests/test-version-management.sh
```

### Manual Testing

```bash
# Test version resolution
./scripts/version-manager resolve node_exporter

# Test comparison
./scripts/version-manager compare 1.8.0 1.7.0

# Test cache
./scripts/version-manager update-cache node_exporter
./scripts/version-manager info node_exporter
```

## Migration

### Phase 1: Install (Done)
- Files in place
- No changes to existing scripts

### Phase 2: Test
```bash
# Test resolution
./scripts/version-manager info node_exporter

# Run test suite
./tests/test-version-management.sh
```

### Phase 3: Gradual Adoption
- Update one component at a time
- Test thoroughly
- Keep backward compatibility

### Phase 4: Production
- Use pinned strategy
- Enable offline mode
- Lock versions in config

## Best Practices

1. **Always provide fallbacks**: Config and manifest versions
2. **Cache aggressively**: Reduce API calls
3. **Use offline mode in production**: No external dependencies
4. **Pin versions for production**: Stability over features
5. **Test in staging first**: Validate new versions
6. **Monitor rate limits**: Use GitHub token if needed
7. **Keep cache fresh**: Update regularly
8. **Validate configuration**: Before deployment
9. **Log version decisions**: Audit trail
10. **Document overrides**: When using env vars

## Documentation

- [Architecture](VERSION_MANAGEMENT_ARCHITECTURE.md) - Detailed design
- [Migration Guide](VERSION_MANAGEMENT_MIGRATION.md) - Step-by-step migration
- [Integration Guide](VERSION_MANAGEMENT_INTEGRATION.md) - How to integrate
- [Quick Start](VERSION_MANAGEMENT_QUICKSTART.md) - Get started fast
- [README](VERSION_MANAGEMENT_README.md) - This document

## Support

### Debug Mode

```bash
export VERSION_DEBUG=true
```

### Check Configuration

```bash
./scripts/version-manager validate node_exporter
```

### Get Help

```bash
./scripts/version-manager --help
```

## Future Enhancements

Planned features:
- Version update notifications
- Automated update PRs
- Security advisory checking
- Dependency graph visualization
- LTS detection logic
- Advanced compatibility testing
- Metrics and monitoring
- Web UI for version management

## License

Part of the observability-stack project.

## Summary

The version management system provides a robust, flexible, and production-ready solution for managing component versions with:

- **Zero Breaking Changes**: 100% backward compatible
- **Multiple Strategies**: latest, pinned, lts, range
- **Offline Support**: Works without internet
- **GitHub Integration**: Automatic version detection
- **Caching**: Performance optimization
- **Production Ready**: Robust fallback chain

Start using it today with zero changes to existing code!
