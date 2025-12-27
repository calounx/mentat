# Version Management System - Quick Start Guide

## 5-Minute Quick Start

### Installation

The version management system is already installed. Just verify:

```bash
# Check library exists
ls -l scripts/lib/versions.sh

# Check config exists
ls -l config/versions.yaml

# Test CLI tool
./scripts/version-manager --help
```

### Basic Usage

```bash
# 1. Resolve a version (uses default strategy from config)
./scripts/version-manager resolve node_exporter

# 2. Show detailed version information
./scripts/version-manager info node_exporter

# 3. List all component versions
./scripts/version-manager list

# 4. Check GitHub API rate limit
./scripts/version-manager rate-limit
```

### In Your Scripts

```bash
#!/bin/bash

# Source the library
source scripts/lib/versions.sh

# Resolve version
version=$(resolve_version "node_exporter")
echo "Installing version: $version"

# Use it
MODULE_VERSION="$version" ./modules/_core/node_exporter/install.sh
```

## Common Tasks

### Pin a Specific Version (Production)

```bash
# Method 1: Environment variable (temporary)
export VERSION_OVERRIDE_NODE_EXPORTER="1.7.0"

# Method 2: Edit config file (permanent)
vim config/versions.yaml
# Change strategy to 'pinned' and set version: "1.7.0"
```

### Always Use Latest Version (Development)

```bash
# Edit config/versions.yaml
components:
  node_exporter:
    strategy: latest  # Always fetch from GitHub
```

### Work Offline

```bash
# Set offline mode
export VERSION_OFFLINE_MODE=true

# Or in config
vim config/versions.yaml
# Set: offline_mode: true
```

### Check What Version Will Be Used

```bash
./scripts/version-manager info node_exporter
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

### Update Cache Manually

```bash
# Update cache for one component
./scripts/version-manager update-cache node_exporter

# Clear all cache
./scripts/version-manager clear-cache
```

## Version Resolution Priority

The system resolves versions in this order:

1. **Environment Override** (highest priority)
   ```bash
   export VERSION_OVERRIDE_NODE_EXPORTER="1.8.0"
   ```

2. **Strategy-Based Resolution**
   - `latest` → Fetch from GitHub API
   - `pinned` → Use exact version from config
   - `lts` → Use latest LTS version
   - `range` → Match version range

3. **Config Fallback**
   ```yaml
   fallback_version: "1.7.0"
   ```

4. **Module Manifest** (lowest priority)
   ```yaml
   module:
     version: "1.7.0"
   ```

## Configuration Files

### Main Configuration: config/versions.yaml

```yaml
global:
  default_strategy: latest  # Change to 'pinned' for production

components:
  node_exporter:
    strategy: latest
    github_repo: prometheus/node_exporter
    fallback_version: "1.7.0"
```

### Environment-Specific Settings

```bash
# Development (always latest)
export OBSERVABILITY_ENV=development

# Production (pinned versions)
export OBSERVABILITY_ENV=production

# Staging (test latest)
export OBSERVABILITY_ENV=staging
```

## Strategies Explained

### 1. Latest (default)
- Always fetches newest stable release from GitHub
- Best for: Development, staying current
- Fallback: Config version if GitHub unavailable

```yaml
strategy: latest
```

### 2. Pinned
- Uses exact version from config
- Best for: Production stability
- Fallback: Module manifest version

```yaml
strategy: pinned
version: "1.7.0"  # Exact version
```

### 3. Range
- Matches semantic version range
- Best for: Compatibility testing
- Example: ">=1.7.0 <2.0.0"

```yaml
strategy: range
version_range: ">=1.7.0 <2.0.0"
```

### 4. LTS
- Uses latest Long-Term Support version
- Best for: Conservative deployments
- Note: Not all projects have explicit LTS releases

```yaml
strategy: lts
```

## Troubleshooting

### Rate Limit Errors

```bash
# Check rate limit status
./scripts/version-manager rate-limit

# Solution 1: Wait for reset
# Solution 2: Use GitHub token
export GITHUB_TOKEN="your_github_token"

# Solution 3: Use offline mode
export VERSION_OFFLINE_MODE=true
```

### Version Resolution Fails

```bash
# Enable debug output
export VERSION_DEBUG=true
./scripts/version-manager resolve node_exporter

# Check configuration
./scripts/version-manager validate node_exporter

# Try offline mode (uses cache/config)
export VERSION_OFFLINE_MODE=true
./scripts/version-manager resolve node_exporter
```

### Cache Issues

```bash
# Clear cache
./scripts/version-manager clear-cache

# Force refresh
./scripts/version-manager update-cache node_exporter
```

## CLI Reference

```bash
# Version resolution
./scripts/version-manager resolve <component>
./scripts/version-manager resolve <component> --strategy pinned
./scripts/version-manager resolve <component> --offline

# Information
./scripts/version-manager info <component>
./scripts/version-manager list
./scripts/version-manager rate-limit

# Cache management
./scripts/version-manager update-cache <component>
./scripts/version-manager clear-cache [component]
./scripts/version-manager cleanup

# Version comparison
./scripts/version-manager compare 1.8.0 1.7.0

# Validation
./scripts/version-manager validate <component>
```

## Integration Examples

### In Bash Scripts

```bash
#!/bin/bash
source scripts/lib/versions.sh

# Get version
version=$(resolve_version "node_exporter")

# Compare versions
if [[ $(compare_versions "$version" "1.7.0") -eq 1 ]]; then
    echo "Newer than 1.7.0"
fi

# Check constraints
if version_satisfies "$version" ">=1.7.0 <2.0.0"; then
    echo "Version is in range"
fi
```

### In Makefiles

```makefile
.PHONY: install
install:
	@version=$$(./scripts/version-manager resolve node_exporter); \
	echo "Installing $$version"; \
	MODULE_VERSION=$$version ./modules/_core/node_exporter/install.sh
```

### In CI/CD Pipelines

```yaml
# .github/workflows/deploy.yml
- name: Resolve versions
  run: |
    export VERSION_OFFLINE_MODE=true  # Don't call GitHub in CI
    version=$(./scripts/version-manager resolve node_exporter)
    echo "NODE_EXPORTER_VERSION=$version" >> $GITHUB_ENV

- name: Deploy
  run: |
    MODULE_VERSION=$NODE_EXPORTER_VERSION ./deploy.sh
```

## Best Practices

1. **Production**: Use `pinned` strategy with exact versions
2. **Staging**: Use `latest` to test before production
3. **Development**: Use `latest` to stay current
4. **CI/CD**: Use offline mode to avoid external dependencies
5. **Always have fallbacks**: Config and manifest versions
6. **Cache aggressively**: Reduce API calls
7. **Monitor rate limits**: Use GitHub token if needed

## Migration from Hardcoded Versions

### Current Code
```bash
MODULE_VERSION="${MODULE_VERSION:-1.7.0}"
```

### New Code (Backward Compatible)
```bash
if [[ -f "$LIB_DIR/versions.sh" ]]; then
    source "$LIB_DIR/versions.sh"
    MODULE_VERSION="${MODULE_VERSION:-$(resolve_version "$MODULE_NAME" 2>/dev/null || echo "1.7.0")}"
else
    MODULE_VERSION="${MODULE_VERSION:-1.7.0}"
fi
```

## Testing

```bash
# Run test suite
./tests/test-version-management.sh

# Test specific component
export VERSION_DEBUG=true
./scripts/version-manager info node_exporter

# Test offline mode
export VERSION_OFFLINE_MODE=true
./scripts/version-manager resolve node_exporter
```

## FAQ

**Q: Does this break existing scripts?**
A: No! It's 100% backward compatible. Old scripts continue working.

**Q: What if GitHub is down?**
A: System automatically falls back to cache, config, then manifest versions.

**Q: Can I disable version management?**
A: Yes, just don't source the library. Everything works as before.

**Q: How do I pin versions for production?**
A: Set strategy to `pinned` in config or use environment variable.

**Q: Does this work offline?**
A: Yes! Set `VERSION_OFFLINE_MODE=true` or configure in config file.

## Getting Help

```bash
# Show help
./scripts/version-manager --help

# Enable debug output
export VERSION_DEBUG=true

# Check configuration
vim config/versions.yaml

# Review documentation
cat docs/VERSION_MANAGEMENT_ARCHITECTURE.md
cat docs/VERSION_MANAGEMENT_MIGRATION.md
cat docs/VERSION_MANAGEMENT_INTEGRATION.md
```

## Summary

The version management system provides:
- Flexible version strategies (latest/pinned/range)
- Automatic version resolution from GitHub
- Offline support with caching
- 100% backward compatibility
- Production-ready fallback chain

Start with the default configuration and customize as needed!
