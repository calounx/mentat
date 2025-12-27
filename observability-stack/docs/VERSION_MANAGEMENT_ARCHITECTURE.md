# Version Management System - Architectural Design

## Executive Summary

This document describes the architecture for a robust version management system that eliminates hardcoded versions from the observability-stack and provides flexible version resolution strategies.

## Problem Statement

**Current State:**
- Versions hardcoded in module.yaml files (e.g., `version: "1.7.0"`)
- Versions duplicated in install scripts as fallbacks
- No automatic version detection from upstream sources
- Manual updates required for each component
- No version compatibility checking
- No support for different deployment strategies (latest vs. pinned)

**Pain Points:**
1. Maintenance burden: Every upstream release requires manual updates
2. Outdated versions: Easy to forget updating versions
3. No flexibility: Production environments may want pinned versions, dev wants latest
4. No offline support: Cannot install without internet when GitHub API is unavailable
5. No version constraints: Cannot specify version ranges or compatibility

## Architectural Design

### Service Boundaries

The version management system is organized into distinct service boundaries:

```
┌─────────────────────────────────────────────────────────────┐
│                    Version Management Layer                  │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   Version    │  │   Strategy   │  │   Version    │      │
│  │  Resolution  │  │   Selector   │  │  Validator   │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│         │                  │                  │              │
│         └──────────────────┴──────────────────┘              │
│                            │                                 │
├────────────────────────────┼─────────────────────────────────┤
│                            ▼                                 │
│  ┌──────────────────────────────────────────────────────┐   │
│  │           Version Source Abstraction Layer           │   │
│  └──────────────────────────────────────────────────────┘   │
│         │              │              │              │       │
│         ▼              ▼              ▼              ▼       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │  GitHub  │  │  Config  │  │  Cache   │  │  Module  │   │
│  │   API    │  │   File   │  │  Layer   │  │ Manifest │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

### Core Components

#### 1. Version Resolution Service
**Responsibility:** Determine which version to use for a component

**API:**
```bash
resolve_version <component> [strategy]
  Returns: version string (e.g., "1.7.0")

  Fallback chain:
  1. Environment variable override (VERSION_OVERRIDE_<component>)
  2. Strategy-based resolution (latest/pinned/lts/range)
  3. Config file fallback
  4. Module manifest default
```

#### 2. Version Source Abstraction
**Responsibility:** Fetch version information from various sources

**Sources (in priority order):**
```bash
1. GitHub API (latest releases)
   - Respects rate limiting (60 req/hr unauthenticated, 5000 with token)
   - Caches responses (15 min TTL)
   - Supports pre-release filtering

2. Configuration File (config/versions.yaml)
   - Pinned versions for production stability
   - Version constraints/ranges
   - Per-environment overrides

3. Cache Layer (~/.cache/observability-stack/versions/)
   - Offline support
   - Reduces API calls
   - Configurable TTL

4. Module Manifest Fallback (module.yaml)
   - Ultimate fallback if all else fails
   - Ensures installation always possible
```

#### 3. Version Strategy Selector
**Responsibility:** Apply version selection logic based on strategy

**Strategies:**
```yaml
latest:
  description: Always fetch latest stable release from upstream
  use_case: Development environments, staying current
  fallback: Config file version

pinned:
  description: Use exact version from config file
  use_case: Production stability, compliance requirements
  fallback: Module manifest version

lts:
  description: Use latest LTS/stable version
  use_case: Conservative deployments
  fallback: Latest stable, then config

range:
  description: Any version matching semver range
  use_case: Compatibility testing, gradual upgrades
  example: ">=1.7.0 <2.0.0"
  fallback: Latest in range, then config

locked:
  description: Use only cached/offline versions
  use_case: Air-gapped environments
  fallback: None - fail if not cached
```

#### 4. Version Validator
**Responsibility:** Ensure version compatibility and validity

**Checks:**
```bash
- Semantic version format validation
- Compatibility matrix verification
- Minimum version requirements
- Breaking change detection
- Architecture compatibility (linux-amd64, etc.)
```

### Data Model

#### Configuration Schema (config/versions.yaml)

```yaml
# Global version management settings
global:
  # Default strategy for all components
  default_strategy: latest

  # GitHub API configuration
  github_api:
    enabled: true
    token_env: GITHUB_TOKEN  # Optional: increases rate limit
    timeout: 10
    cache_ttl: 900  # 15 minutes

  # Cache configuration
  cache:
    enabled: true
    directory: ~/.cache/observability-stack/versions
    ttl: 86400  # 24 hours
    max_age: 604800  # 7 days before forced refresh

  # Offline mode
  offline_mode: false  # If true, only use cache and config

  # Compatibility checking
  compatibility_check: true

# Component version configuration
components:
  node_exporter:
    strategy: latest
    github_repo: prometheus/node_exporter
    fallback_version: "1.7.0"
    minimum_version: "1.5.0"

    # Version constraints
    constraints:
      architecture: linux-amd64
      exclude_prereleases: true

    # Compatibility matrix
    compatible_with:
      prometheus: ">=2.0.0"

  mysqld_exporter:
    strategy: pinned
    version: "0.15.1"  # Exact version for pinned strategy
    github_repo: prometheus/mysqld_exporter
    fallback_version: "0.15.1"

  promtail:
    strategy: range
    version_range: ">=2.9.0 <3.0.0"
    github_repo: grafana/loki
    release_asset_pattern: "promtail-linux-amd64.zip"
    fallback_version: "2.9.3"

  nginx_exporter:
    strategy: latest
    github_repo: nginxinc/nginx-prometheus-exporter
    fallback_version: "1.1.0"

  phpfpm_exporter:
    strategy: latest
    github_repo: hipages/php-fpm_exporter
    fallback_version: "2.2.0"

  fail2ban_exporter:
    strategy: latest
    github_repo: jangrewe/prometheus-fail2ban-exporter
    fallback_version: "0.10.3"

# Environment-specific overrides
environments:
  production:
    default_strategy: pinned
    offline_mode: true  # Production should not call external APIs

  staging:
    default_strategy: latest

  development:
    default_strategy: latest
    github_api:
      cache_ttl: 300  # 5 minutes for faster updates

# Compatibility matrix (global cross-component compatibility)
compatibility_matrix:
  - component: promtail
    requires:
      loki: ">=2.9.0"

  - component: prometheus
    compatible_versions:
      - "2.45.0"
      - "2.46.0"
      - "2.47.0"
```

#### Cache Structure

```
~/.cache/observability-stack/versions/
├── index.json                    # Cache index with metadata
├── node_exporter/
│   ├── latest.json              # Latest version info
│   ├── releases.json            # All releases (limited to last 50)
│   └── metadata.json            # Fetch timestamp, TTL, etc.
├── mysqld_exporter/
│   └── ...
└── promtail/
    └── ...
```

### API Design

#### Core Functions (scripts/lib/versions.sh)

```bash
#==============================================================================
# VERSION RESOLUTION
#==============================================================================

# Resolve version for a component using configured strategy
# Usage: resolve_version <component> [strategy_override]
# Returns: version string (e.g., "1.7.0")
# Exit codes: 0=success, 1=error, 2=not found
resolve_version()

# Get latest version from GitHub API
# Usage: get_latest_version <component>
# Returns: version string
get_latest_version()

# Get version from config file
# Usage: get_config_version <component>
# Returns: version string from config
get_config_version()

# Get fallback version from module manifest
# Usage: get_manifest_version <component>
# Returns: version string from module.yaml
get_manifest_version()

#==============================================================================
# VERSION COMPARISON
#==============================================================================

# Compare two semantic versions
# Usage: compare_versions <version1> <version2>
# Returns: -1 (v1 < v2), 0 (v1 == v2), 1 (v1 > v2)
compare_versions()

# Check if version satisfies constraints
# Usage: version_satisfies <version> <constraint>
# Example: version_satisfies "1.8.0" ">=1.7.0 <2.0.0"
# Returns: 0 if satisfied, 1 otherwise
version_satisfies()

# Check if version is compatible with other components
# Usage: is_version_compatible <component> <version>
# Returns: 0 if compatible, 1 otherwise
is_version_compatible()

#==============================================================================
# VERSION VALIDATION
#==============================================================================

# Validate semantic version format
# Usage: validate_version <version>
# Returns: 0 if valid, 1 otherwise
validate_version()

# Validate component configuration
# Usage: validate_component_config <component>
# Returns: 0 if valid, 1 otherwise
validate_component_config()

#==============================================================================
# GITHUB API INTEGRATION
#==============================================================================

# Fetch latest release from GitHub
# Usage: github_latest_release <repo>
# Example: github_latest_release "prometheus/node_exporter"
# Returns: JSON response
github_latest_release()

# Fetch all releases from GitHub
# Usage: github_list_releases <repo> [limit]
# Returns: JSON array of releases
github_list_releases()

# Filter releases by criteria
# Usage: github_filter_releases <json> <criteria>
# Returns: Filtered JSON array
github_filter_releases()

#==============================================================================
# CACHE MANAGEMENT
#==============================================================================

# Get cached version info
# Usage: cache_get <component> <key>
# Returns: cached value or empty if not found/expired
cache_get()

# Set cached version info
# Usage: cache_set <component> <key> <value> [ttl]
cache_set()

# Invalidate cache for component
# Usage: cache_invalidate <component>
cache_invalidate()

# Clean expired cache entries
# Usage: cache_cleanup
cache_cleanup()

#==============================================================================
# DOWNLOAD HELPERS
#==============================================================================

# Download component binary at specific version
# Usage: download_component <component> <version> <dest_dir>
# Returns: 0 on success, 1 on failure
download_component()

# Verify downloaded binary checksum
# Usage: verify_checksum <file> <checksum_url>
# Returns: 0 if valid, 1 otherwise
verify_checksum()

#==============================================================================
# UTILITY FUNCTIONS
#==============================================================================

# Load version configuration
# Usage: load_version_config
load_version_config()

# Get version strategy for component
# Usage: get_version_strategy <component>
# Returns: strategy name (latest/pinned/lts/range)
get_version_strategy()

# Print version information
# Usage: print_version_info <component>
print_version_info()

# Update version cache from GitHub
# Usage: update_version_cache <component>
update_version_cache()
```

### Error Handling Strategy

```bash
Error Levels:
  FATAL    - Cannot proceed (exit 1)
  ERROR    - Operation failed, try fallback
  WARN     - Non-critical issue
  INFO     - Informational message
  DEBUG    - Verbose output (if enabled)

Fallback Chain on Failure:
  GitHub API → Config File → Cache → Module Manifest → FAIL

Rate Limit Handling:
  - Detect GitHub rate limit errors (HTTP 403)
  - Auto-switch to cache/config fallback
  - Display warning with reset time
  - Continue installation with fallback version

Network Error Handling:
  - Timeout after configurable duration (default 10s)
  - Retry with exponential backoff (3 attempts)
  - Fallback to cache/config
  - Support offline mode flag
```

### Security Considerations

1. **GitHub Token Storage**
   - Never hardcode tokens
   - Read from environment variable only
   - Optional - system works without token
   - Document rate limit implications

2. **Checksum Verification**
   - Always verify downloaded binaries
   - Use official checksum files from GitHub releases
   - Fail if checksum unavailable/mismatch

3. **Cache Validation**
   - Verify cache file integrity
   - Implement cache poisoning protection
   - Use secure cache directory permissions (700)

4. **API Response Validation**
   - Parse JSON safely
   - Validate response structure
   - Sanitize version strings

### Performance Optimization

1. **Caching Strategy**
   - Cache GitHub API responses (15 min TTL)
   - Cache component metadata (24 hour TTL)
   - Lazy loading - only fetch when needed
   - Background cache refresh (async)

2. **Parallel Resolution**
   - Resolve multiple component versions concurrently
   - Use background jobs for non-critical updates
   - Batch API requests when possible

3. **Rate Limit Optimization**
   - Use conditional requests (If-None-Match headers)
   - Prefer cached data when fresh
   - Use GitHub tokens when available (5000 req/hr)

### Backward Compatibility

The system maintains full backward compatibility:

1. **Module Manifests**
   - `module.version` field still works as fallback
   - No breaking changes to module.yaml schema
   - Optional migration path

2. **Environment Variables**
   - `MODULE_VERSION` still works (highest priority)
   - New: `VERSION_STRATEGY` for override
   - New: `VERSION_CONFIG` for config file path

3. **Migration Strategy**
   - Gradual adoption - components can opt-in
   - Old install scripts continue working
   - New scripts prefer version management system
   - Backward-compatible defaults

### Deployment Strategies

#### Development Environment
```yaml
global:
  default_strategy: latest
  github_api:
    enabled: true
    cache_ttl: 300  # 5 min for rapid iteration
```

#### Production Environment
```yaml
global:
  default_strategy: pinned
  offline_mode: true  # No external API calls

components:
  node_exporter:
    strategy: pinned
    version: "1.7.0"  # Locked version
```

#### Staging Environment
```yaml
global:
  default_strategy: latest

environments:
  staging:
    # Test latest versions before production
    default_strategy: latest
```

## Implementation Plan

### Phase 1: Core Infrastructure (Week 1)
- [ ] Create scripts/lib/versions.sh skeleton
- [ ] Implement version comparison functions
- [ ] Implement config file parser
- [ ] Basic cache implementation

### Phase 2: GitHub API Integration (Week 1-2)
- [ ] GitHub API client functions
- [ ] Rate limit handling
- [ ] Response parsing and validation
- [ ] Cache integration

### Phase 3: Strategy Implementation (Week 2)
- [ ] Latest strategy
- [ ] Pinned strategy
- [ ] Range strategy
- [ ] LTS strategy

### Phase 4: Integration (Week 2-3)
- [ ] Update module-loader.sh
- [ ] Migrate module manifests
- [ ] Update install scripts
- [ ] Backward compatibility layer

### Phase 5: Testing & Documentation (Week 3)
- [ ] Unit tests for version functions
- [ ] Integration tests
- [ ] Migration guide
- [ ] User documentation

## Testing Strategy

### Unit Tests
```bash
test_version_comparison()
  - Compare semantic versions
  - Handle edge cases (pre-release, build metadata)

test_version_validation()
  - Valid formats accepted
  - Invalid formats rejected

test_strategy_selection()
  - Each strategy returns correct version
  - Fallbacks work correctly
```

### Integration Tests
```bash
test_github_api_integration()
  - Fetch real versions from GitHub
  - Handle rate limits
  - Cache responses

test_offline_mode()
  - Works without internet
  - Uses cached/config versions

test_full_installation()
  - Install component with version management
  - Verify correct version installed
```

### Performance Tests
```bash
test_cache_performance()
  - Measure cache hit/miss rates
  - Verify TTL expiration

test_concurrent_resolution()
  - Multiple components resolved in parallel
  - No race conditions
```

## Metrics and Monitoring

Track these metrics:
- Version resolution time
- Cache hit/miss ratio
- GitHub API call count
- Rate limit status
- Version update frequency
- Failed version resolutions

## Future Enhancements

1. **Version Update Notifications**
   - Notify when newer versions available
   - Changelog integration
   - Security advisory checking

2. **Automated Updates**
   - Scheduled version checks
   - Automated PR creation for updates
   - Rollback capability

3. **Version Pinning Service**
   - Centralized version registry
   - Organization-wide version standards
   - Approval workflows

4. **Advanced Compatibility**
   - Runtime compatibility testing
   - Automatic version conflict resolution
   - Dependency graph visualization

## Conclusion

This version management system provides:
- **Flexibility**: Multiple version strategies for different needs
- **Reliability**: Robust fallback chain ensures installation always succeeds
- **Performance**: Caching and optimizations minimize latency
- **Maintainability**: Centralized version configuration
- **Backward Compatibility**: No breaking changes to existing deployments

The architecture is extensible and can evolve with future requirements while maintaining stability and ease of use.
