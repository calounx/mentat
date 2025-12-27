# Version Management System - Quick Reference

## Overview

This is a quick reference guide for the dynamic version management system. For detailed architecture, see [DYNAMIC_VERSION_MANAGEMENT_DESIGN.md](DYNAMIC_VERSION_MANAGEMENT_DESIGN.md).

---

## Architecture at a Glance

```
┌─────────────────────────────────────────────────┐
│         Version Management System               │
├─────────────────────────────────────────────────┤
│                                                   │
│  [GitHub API] → [Version Resolution]             │
│       ↓              ↓                            │
│  [Cache Layer] ← [Safety Checks]                 │
│       ↓              ↓                            │
│  [State DB] → [Upgrade Decision]                 │
│       ↓              ↓                            │
│  [Rollback] ← [Installation]                     │
│                                                   │
└─────────────────────────────────────────────────┘
```

**Key Components:**
- **Version Discovery**: Fetch latest versions from GitHub API
- **Safety Checks**: Compatibility, breaking changes, security advisories
- **Upgrade Decision**: Risk assessment and approval logic
- **State Management**: SQLite database tracking installations and history
- **Rollback**: Automatic rollback on failure with point-in-time recovery

---

## Common Commands

### Check for Upgrades

```bash
# Check all components
./scripts/version-management/check-upgrades.sh

# Check specific component
./scripts/version-management/check-upgrades.sh node_exporter
```

### Upgrade Component

```bash
# Upgrade to latest
sudo ./scripts/version-management/upgrade-component.sh node_exporter

# Upgrade to specific version
sudo ./scripts/version-management/upgrade-component.sh node_exporter 1.8.0

# Dry run (simulate upgrade)
./scripts/version-management/upgrade-component.sh node_exporter --dry-run

# Force upgrade (skip safety checks)
sudo ./scripts/version-management/upgrade-component.sh node_exporter --force
```

### Rollback

```bash
# List rollback points
./scripts/version-management/rollback-component.sh node_exporter --list

# Execute rollback
sudo ./scripts/version-management/rollback-component.sh node_exporter <rollback_id>

# Rollback to specific version
sudo ./scripts/version-management/rollback-component.sh node_exporter --version 1.7.0
```

### Version Information

```bash
# List installed versions
./scripts/version-management/list-versions.sh

# Show version details
./scripts/version-management/list-versions.sh node_exporter

# Show upgrade history
sqlite3 /var/lib/observability-stack/state.db \
    "SELECT * FROM upgrade_history WHERE component='node_exporter' ORDER BY upgraded_at DESC LIMIT 5;"
```

### Cache Management

```bash
# Update version cache
./scripts/version-management/update-cache.sh

# Clear cache
rm -rf ~/.cache/observability-stack/versions/*

# Force refresh (bypass cache)
VERSION_CACHE_TTL=0 ./scripts/version-management/check-upgrades.sh
```

---

## Configuration

### Environment Variables

```bash
# GitHub API token (increases rate limit)
export GITHUB_TOKEN="ghp_xxx"

# Offline mode (no API calls)
export VERSION_OFFLINE_MODE=true

# Cache settings
export VERSION_CACHE_TTL=900          # 15 minutes
export VERSION_CACHE_DIR=~/.cache/observability-stack/versions

# State database
export STATE_DB_PATH=/var/lib/observability-stack/state.db

# Debug mode
export VERSION_DEBUG=true
```

### Configuration File (config/versions.yaml)

```yaml
# Global defaults
global:
  default_strategy: latest  # latest|pinned|lts|range
  offline_mode: false

# Component-specific settings
components:
  node_exporter:
    strategy: latest
    github_repo: prometheus/node_exporter
    fallback_version: "1.7.0"
    minimum_version: "1.5.0"

# Environment overrides
environments:
  production:
    default_strategy: pinned
    offline_mode: true
```

---

## Version Strategies

| Strategy | Description | Use Case |
|----------|-------------|----------|
| **latest** | Always use latest stable release | Development, staying current |
| **pinned** | Use exact version from config | Production stability |
| **lts** | Use latest LTS version | Conservative deployments |
| **range** | Match semver range (e.g., ">=1.7.0 <2.0.0") | Compatibility testing |
| **locked** | Only use cached versions | Air-gapped environments |

---

## Safety Checks

### Automatic Checks Performed

1. **Version Comparison**: Detect upgrades vs. downgrades
2. **Compatibility Check**: Verify component dependencies
3. **Breaking Changes**: Detect major version bumps and known breaking changes
4. **Security Advisories**: Check for known vulnerabilities
5. **Disk Space**: Ensure sufficient space for installation
6. **Service Health**: Verify service can restart

### Risk Levels

- **Low**: Patch version bump, no breaking changes, auto-approved
- **Medium**: Minor version bump, may require manual approval
- **High**: Major version bump, always requires manual approval

### Override Safety Checks

```bash
# Skip all safety checks (dangerous!)
sudo ./scripts/version-management/upgrade-component.sh node_exporter --skip-safety

# Force upgrade despite high risk
sudo ./scripts/version-management/upgrade-component.sh node_exporter --force
```

---

## Rollback Mechanism

### How Rollback Works

1. **Before Upgrade**: Create rollback point
   - Backup binary to `/var/lib/observability-stack/rollback/<component>/<version>/`
   - Backup configuration
   - Record state in database

2. **On Failure**: Automatic rollback
   - Restore binary from rollback point
   - Restore configuration
   - Restart service
   - Verify health

3. **Manual Rollback**: Execute anytime
   - List available rollback points
   - Select version to rollback to
   - Execute rollback procedure

### Rollback Retention

```yaml
# In config/versions.yaml
global:
  rollback:
    retention_count: 3      # Keep last 3 rollback points
    retention_days: 30      # Delete after 30 days
    max_size_mb: 1000       # Max total size
```

### Cleanup Old Rollback Points

```bash
# Manual cleanup
./scripts/version-management/cleanup-rollback.sh

# Automated (cron)
0 3 * * 0 /path/to/scripts/version-management/cleanup-rollback.sh
```

---

## State Database

### Location

```
/var/lib/observability-stack/state.db
```

### Schema

**Tables:**
- `installed_components`: Current installation state
- `upgrade_history`: Historical upgrade records
- `rollback_points`: Available rollback snapshots
- `version_cache`: Cached version information
- `compatibility_matrix`: Component compatibility rules
- `breaking_changes`: Known breaking changes database

### Query Examples

```bash
# Current installations
sqlite3 /var/lib/observability-stack/state.db \
    "SELECT component, version, installed_at FROM installed_components;"

# Recent upgrades
sqlite3 /var/lib/observability-stack/state.db \
    "SELECT component, from_version, to_version, success, upgraded_at
     FROM upgrade_history ORDER BY upgraded_at DESC LIMIT 10;"

# Success rate per component
sqlite3 /var/lib/observability-stack/state.db \
    "SELECT component,
            COUNT(*) as total_upgrades,
            SUM(success) as successful,
            ROUND(100.0 * SUM(success) / COUNT(*), 2) as success_rate
     FROM upgrade_history GROUP BY component;"

# Available rollback points
sqlite3 /var/lib/observability-stack/state.db \
    "SELECT component, version, created_at, expires_at
     FROM rollback_points ORDER BY created_at DESC;"
```

### Backup Database

```bash
# Backup
cp /var/lib/observability-stack/state.db \
   /var/backups/observability-state-$(date +%Y%m%d).db

# Restore
sudo systemctl stop observability-*
cp /var/backups/observability-state-20240115.db \
   /var/lib/observability-stack/state.db
sudo systemctl start observability-*
```

---

## API Integration

### GitHub API

**Rate Limits:**
- Unauthenticated: 60 requests/hour
- Authenticated (with token): 5000 requests/hour

**Set Token:**
```bash
export GITHUB_TOKEN="ghp_your_token_here"
```

**Endpoints Used:**
- `GET /repos/{owner}/{repo}/releases/latest` - Latest release
- `GET /repos/{owner}/{repo}/releases` - All releases
- `GET /repos/{owner}/{repo}/releases/tags/{tag}` - Specific release
- `GET /rate_limit` - Check rate limit status

### Caching Strategy

**Three-Tier Cache:**

1. **Memory Cache**: Session lifetime, instant access
2. **File Cache**: 15 minutes TTL, fast local access
3. **Database Cache**: 24 hours TTL, persistent across sessions

**Cache Locations:**
```
~/.cache/observability-stack/versions/
├── index.json
├── node_exporter/
│   ├── latest.json
│   ├── releases.json
│   └── metadata.json
└── ...
```

---

## Upgrade Workflow

### Standard Upgrade Flow

```
1. Resolve Target Version
   ├─ Check environment override
   ├─ Check config file
   ├─ Fetch from GitHub API
   └─ Use cached version

2. Safety Checks
   ├─ Compare versions (prevent downgrade)
   ├─ Check compatibility
   ├─ Detect breaking changes
   ├─ Check security advisories
   └─ Verify disk space

3. Create Rollback Point
   ├─ Backup binary
   ├─ Backup configuration
   └─ Record in database

4. Download & Verify
   ├─ Download binary
   ├─ Verify checksum
   └─ Extract archive

5. Atomic Installation
   ├─ Stop service
   ├─ Replace binary
   ├─ Update configuration
   └─ Start service

6. Validation
   ├─ Verify service status
   ├─ Check metrics endpoint
   ├─ Verify version
   └─ On failure → Rollback

7. Record Success
   ├─ Update installed_components
   ├─ Record in upgrade_history
   └─ Cleanup old rollback points
```

### Failure Handling

**Automatic Rollback Triggers:**
- Download failure
- Checksum verification failure
- Service start failure
- Health check failure
- Metrics endpoint unreachable

**Manual Intervention Required:**
- Rollback itself fails
- Multiple consecutive upgrade failures
- Incompatible configuration changes

---

## Monitoring & Alerts

### Metrics to Track

```bash
# Version resolution time
version_resolution_duration_seconds{component="node_exporter"}

# Cache hit ratio
version_cache_hit_ratio{cache_type="memory|file|db"}

# GitHub API usage
github_api_requests_total{result="success|failure"}
github_api_rate_limit_remaining

# Upgrade metrics
upgrade_attempts_total{component="",result="success|failure"}
upgrade_duration_seconds{component=""}
rollback_executions_total{component=""}
```

### Log Files

```bash
# Upgrade logs
/var/log/observability-stack/upgrades.log

# Version management logs
/var/log/observability-stack/version-mgmt.log

# Rollback logs
/var/log/observability-stack/rollback.log
```

### Alerts

**Recommended Prometheus Alerts:**
```yaml
- alert: ComponentUpgradeFailed
  expr: upgrade_attempts_total{result="failure"} > 0
  annotations:
    summary: "Component upgrade failed: {{ $labels.component }}"

- alert: RollbackExecuted
  expr: rollback_executions_total > 0
  annotations:
    summary: "Rollback executed for {{ $labels.component }}"

- alert: GitHubRateLimitLow
  expr: github_api_rate_limit_remaining < 10
  annotations:
    summary: "GitHub API rate limit nearly exceeded"
```

---

## Troubleshooting

### Common Issues

#### Issue: "Rate limit exceeded"

**Cause:** Too many GitHub API calls without authentication

**Solution:**
```bash
# Set GitHub token
export GITHUB_TOKEN="ghp_xxx"

# Or enable offline mode
export VERSION_OFFLINE_MODE=true

# Use cached versions
./scripts/version-management/check-upgrades.sh
```

#### Issue: "Checksum verification failed"

**Cause:** Downloaded binary doesn't match expected checksum

**Solution:**
```bash
# Check network stability
ping -c 5 github.com

# Clear download cache
rm -rf /tmp/observability-downloads/*

# Retry download
sudo ./scripts/version-management/upgrade-component.sh <component>

# If persists, verify checksum URL in config
```

#### Issue: "Service failed health check"

**Cause:** Service doesn't start after upgrade

**Solution:**
```bash
# Check service status
systemctl status <component>

# View logs
journalctl -u <component> -n 50

# Manual rollback
sudo ./scripts/version-management/rollback-component.sh <component> <rollback_id>
```

#### Issue: "Compatibility check failed"

**Cause:** Target version incompatible with other components

**Solution:**
```bash
# Check installed versions
./scripts/version-management/list-versions.sh

# Update dependencies first
sudo ./scripts/version-management/upgrade-component.sh <dependency>

# Then retry upgrade
sudo ./scripts/version-management/upgrade-component.sh <component>

# Or force upgrade (risky!)
sudo ./scripts/version-management/upgrade-component.sh <component> --force
```

### Debug Mode

```bash
# Enable verbose logging
export VERSION_DEBUG=true

# Run upgrade with debug
./scripts/version-management/upgrade-component.sh node_exporter --dry-run

# Check what version would be resolved
source scripts/lib/versions.sh
resolve_version "node_exporter"
```

---

## Best Practices

### Production Deployments

1. **Always test in staging first**
   ```bash
   OBSERVABILITY_ENV=staging ./scripts/version-management/upgrade-component.sh <component>
   ```

2. **Use pinned versions in production**
   ```yaml
   environments:
     production:
       default_strategy: pinned
   ```

3. **Create rollback points**
   ```bash
   # Rollback points are created automatically unless --no-rollback
   ```

4. **Monitor upgrades**
   ```bash
   # Set up Prometheus alerts for upgrade failures
   ```

5. **Schedule upgrades during maintenance windows**
   ```bash
   # Use cron for scheduled upgrades
   0 3 * * 0 /path/to/upgrade-all.sh --auto-approve-low-risk
   ```

### Development Environments

1. **Use latest strategy**
   ```yaml
   environments:
     development:
       default_strategy: latest
   ```

2. **Enable pre-releases**
   ```yaml
   constraints:
     exclude_prereleases: false
   ```

3. **Shorter cache TTL**
   ```bash
   export VERSION_CACHE_TTL=300  # 5 minutes
   ```

### Version Pinning

```yaml
# Pin specific versions for production
environments:
  production:
    component_overrides:
      node_exporter:
        strategy: pinned
        version: "1.7.0"

      promtail:
        strategy: pinned
        version: "2.9.3"
```

---

## File Locations

### Configuration
- `/home/calounx/repositories/mentat/observability-stack/config/versions.yaml` - Version configuration
- `/home/calounx/repositories/mentat/observability-stack/config/global.yaml` - Global configuration

### Scripts
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/versions.sh` - Core version library
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/github-api.sh` - GitHub API client
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/state-db.sh` - Database operations
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/rollback.sh` - Rollback functions

### State & Data
- `/var/lib/observability-stack/state.db` - State database
- `/var/lib/observability-stack/rollback/` - Rollback point storage
- `~/.cache/observability-stack/versions/` - Version cache

### Logs
- `/var/log/observability-stack/upgrades.log` - Upgrade logs
- `/var/log/observability-stack/version-mgmt.log` - Version management logs

---

## Related Documentation

- **[DYNAMIC_VERSION_MANAGEMENT_DESIGN.md](DYNAMIC_VERSION_MANAGEMENT_DESIGN.md)** - Comprehensive architecture design
- **[VERSION_MANAGEMENT_IMPLEMENTATION_GUIDE.md](VERSION_MANAGEMENT_IMPLEMENTATION_GUIDE.md)** - Step-by-step implementation
- **[VERSION_MANAGEMENT_ARCHITECTURE.md](VERSION_MANAGEMENT_ARCHITECTURE.md)** - Base architecture
- **[versions.yaml](../config/versions.yaml)** - Configuration reference

---

## Quick Start

### 1. Initialize System

```bash
# Initialize state database
sudo ./scripts/init-state-db.sh

# Update version cache
./scripts/version-management/update-cache.sh
```

### 2. Check Current State

```bash
# List installed components
./scripts/version-management/list-versions.sh

# Check for upgrades
./scripts/version-management/check-upgrades.sh
```

### 3. Perform First Upgrade

```bash
# Dry run first
./scripts/version-management/upgrade-component.sh nginx_exporter --dry-run

# Actual upgrade
sudo ./scripts/version-management/upgrade-component.sh nginx_exporter

# Verify
systemctl status nginx_exporter
```

### 4. Test Rollback

```bash
# List rollback points
./scripts/version-management/rollback-component.sh nginx_exporter --list

# Test rollback
sudo ./scripts/version-management/rollback-component.sh nginx_exporter <rollback_id>
```

---

## Support

For issues or questions:
1. Check this quick reference
2. Review detailed architecture: [DYNAMIC_VERSION_MANAGEMENT_DESIGN.md](DYNAMIC_VERSION_MANAGEMENT_DESIGN.md)
3. Enable debug mode: `export VERSION_DEBUG=true`
4. Check logs: `journalctl -xe`

---

**Last Updated:** 2024-01-15
**Version:** 1.0.0
