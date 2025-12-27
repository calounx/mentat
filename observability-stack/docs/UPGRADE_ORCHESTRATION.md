# Upgrade Orchestration System

Complete idempotent upgrade system for the observability stack with automatic rollback, state management, and crash recovery.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Usage Examples](#usage-examples)
- [Idempotency Guarantees](#idempotency-guarantees)
- [State Management](#state-management)
- [Safety Features](#safety-features)
- [Configuration](#configuration)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)

## Overview

The upgrade orchestration system provides safe, automated upgrades for all observability stack components with the following guarantees:

1. **Idempotent**: Safe to run multiple times without side effects
2. **Resumable**: Recovers from crashes and failures
3. **Safe**: Automatic backups and rollback on failure
4. **Transparent**: Full state tracking and upgrade history
5. **Flexible**: Dry-run mode, phase-based upgrades, component-specific upgrades

## Features

### Idempotency
- Detects already-upgraded components and skips them
- Can be run multiple times without duplicate work
- Resumes from failure point if interrupted
- State tracking prevents duplicate operations

### Version Management
- Auto-detects currently installed versions
- Compares with target versions from configuration
- Skips upgrades if already at target version
- Supports two-stage upgrades for major version bumps (e.g., Prometheus 2.x → 3.x)
- Version pinning and constraint support

### Safety & Reliability
- Pre-upgrade validation (disk space, dependencies, configuration)
- Automatic backups before each component upgrade
- Health checks after upgrade completion
- Automatic rollback on health check failure
- Transactional state updates with file locking
- State persistence for crash recovery

### Upgrade Strategy
- Smart component ordering based on dependencies
- Phased upgrades (Low Risk → High Risk → Medium Risk)
- Parallel execution support for independent components
- Pause-and-resume capability
- Multiple modes: safe, standard, fast, dry-run

## Architecture

### Component Hierarchy

```
scripts/
├── upgrade-orchestrator.sh       # Main entry point
├── upgrade-component.sh          # Component upgrade executor
└── lib/
    ├── upgrade-state.sh          # State management
    ├── upgrade-manager.sh        # Core upgrade logic
    ├── versions.sh               # Version comparison
    └── common.sh                 # Shared utilities

config/
└── upgrade.yaml                  # Upgrade configuration

/var/lib/observability-upgrades/
├── state.json                    # Current upgrade state
├── history/                      # Completed upgrade logs
├── backups/                      # Pre-upgrade backups
└── checkpoints/                  # Rollback points
```

### Upgrade Phases

**Phase 1: Low Risk (Exporters)**
- node_exporter: 1.7.0 → 1.9.1
- nginx_exporter: 1.1.0 → 1.5.1
- mysqld_exporter: 0.15.1 → 0.18.0
- phpfpm_exporter: 2.2.0 → 2.3.0
- fail2ban_exporter: 0.4.1 → 0.5.0

**Phase 2: High Risk (Core Services - Two-Stage)**
- prometheus: 2.48.1 → 2.55.1 → 3.8.1

**Phase 3: Medium Risk (Logging Stack)**
- loki: 2.9.3 → 3.6.3
- promtail: 2.9.3 → 3.6.3

## Quick Start

### Prerequisites

- Root access on the observability server
- `jq` installed for JSON processing
- Active internet connection (for downloading binaries)
- Minimum 1GB free disk space

### Installation

The upgrade orchestration system is included in the observability stack repository:

```bash
cd observability-stack
ls -l scripts/upgrade-orchestrator.sh
```

### Basic Usage

```bash
# 1. Dry run to see what would be upgraded
sudo ./scripts/upgrade-orchestrator.sh --all --dry-run

# 2. Check current status
sudo ./scripts/upgrade-orchestrator.sh --status

# 3. Upgrade all components (interactive)
sudo ./scripts/upgrade-orchestrator.sh --all

# 4. Upgrade specific phase (e.g., low-risk exporters only)
sudo ./scripts/upgrade-orchestrator.sh --phase 1

# 5. Upgrade specific component
sudo ./scripts/upgrade-orchestrator.sh --component node_exporter
```

## Usage Examples

### Example 1: Safe Upgrade with Manual Confirmation

Upgrade all components with maximum safety (manual confirmations at each step):

```bash
sudo ./scripts/upgrade-orchestrator.sh --all --mode safe
```

**Output:**
```
Observability Stack Upgrade Orchestrator
========================================

Mode: SAFE (maximum safety, manual confirmations)

=== UPGRADING ALL COMPONENTS ===

Upgrade Plan:
=============

Phase 1:
  node_exporter: 1.7.0 -> 1.9.1
  nginx_exporter: 1.1.0 -> 1.5.1
  mysqld_exporter: 0.15.1 -> 0.18.0

Phase 2:
  prometheus: 2.48.1 -> 2.55.1

Phase 3:
  loki: 2.9.3 -> 3.6.3
  promtail: 2.9.3 -> 3.6.3

Proceed with full upgrade? [y/N]
```

### Example 2: Automated CI/CD Upgrade

Fast upgrade for automated environments (no confirmations):

```bash
sudo ./scripts/upgrade-orchestrator.sh --all --mode fast --yes
```

### Example 3: Single Component Upgrade

Upgrade just Node Exporter:

```bash
sudo ./scripts/upgrade-orchestrator.sh --component node_exporter
```

**What happens:**
1. Detects current version (1.7.0)
2. Compares with target (1.9.1)
3. Creates backup of current binary and config
4. Downloads and verifies new version
5. Stops service
6. Installs new binary
7. Restarts service
8. Performs health check
9. Verifies metrics endpoint
10. Marks upgrade as complete

### Example 4: Resume After Failure

If an upgrade fails or is interrupted:

```bash
# Check what happened
sudo ./scripts/upgrade-orchestrator.sh --status

# Resume from where it left off
sudo ./scripts/upgrade-orchestrator.sh --resume
```

### Example 5: Rollback

If you need to revert an upgrade:

```bash
sudo ./scripts/upgrade-orchestrator.sh --rollback
```

### Example 6: Dry-Run Before Actual Upgrade

Test the upgrade without making changes:

```bash
sudo ./scripts/upgrade-orchestrator.sh --all --dry-run

# Review the output, then run for real:
sudo ./scripts/upgrade-orchestrator.sh --all
```

### Example 7: Force Re-Upgrade

Force upgrade even if already at target version:

```bash
sudo ./scripts/upgrade-orchestrator.sh --component node_exporter --force
```

## Idempotency Guarantees

The system guarantees idempotent operation in these scenarios:

### Scenario 1: Double-Run

```bash
# First run
sudo ./scripts/upgrade-orchestrator.sh --all
# [Upgrades everything]

# Second run immediately after
sudo ./scripts/upgrade-orchestrator.sh --all
# [Detects all components at target version, skips all]
```

**Expected Output:**
```
[SKIP] Component node_exporter already at target version: 1.9.1
[SKIP] Component nginx_exporter already at target version: 1.5.1
...
All components already upgraded
```

### Scenario 2: Crash During Upgrade

```bash
# Start upgrade
sudo ./scripts/upgrade-orchestrator.sh --all
# [Upgrades component 1, component 2]
# [System crashes or network fails during component 3]

# After reboot/recovery
sudo ./scripts/upgrade-orchestrator.sh --resume
# [Detects components 1 & 2 complete, resumes from component 3]
```

### Scenario 3: Partial Failure

```bash
# Start upgrade
sudo ./scripts/upgrade-orchestrator.sh --all
# [Component 1: SUCCESS]
# [Component 2: FAILED]
# [Stops with error]

# Fix the issue, then:
sudo ./scripts/upgrade-orchestrator.sh --resume
# [Skips component 1, retries component 2]
```

### Scenario 4: Manual Intervention

```bash
# Start automated upgrade
sudo ./scripts/upgrade-orchestrator.sh --all --yes

# Manually upgrade one component
sudo systemctl stop node_exporter
sudo wget ... && tar ...
sudo systemctl start node_exporter

# Resume automated upgrade
sudo ./scripts/upgrade-orchestrator.sh --resume
# [Detects manual upgrade, skips that component]
```

### Scenario 5: Mixed Environments

```bash
# On server A (already partially upgraded)
node_exporter: 1.9.1 (already upgraded manually)
nginx_exporter: 1.1.0 (old)

# Run orchestrator
sudo ./scripts/upgrade-orchestrator.sh --all
# [Skips node_exporter, upgrades nginx_exporter]

# On server B (fresh install)
# [Upgrades everything]
```

## State Management

### State File Structure

The state is stored in `/var/lib/observability-upgrades/state.json`:

```json
{
  "version": "1.0.0",
  "upgrade_id": "upgrade-20250101-120000",
  "status": "in_progress",
  "started_at": "2025-01-01T12:00:00Z",
  "updated_at": "2025-01-01T12:05:00Z",
  "current_phase": 1,
  "current_component": "node_exporter",
  "mode": "standard",
  "components": {
    "node_exporter": {
      "status": "completed",
      "from_version": "1.7.0",
      "to_version": "1.9.1",
      "started_at": "2025-01-01T12:01:00Z",
      "completed_at": "2025-01-01T12:02:30Z",
      "attempts": 1,
      "backup_path": "/var/lib/observability-upgrades/backups/node_exporter/20250101_120100",
      "rollback_available": true,
      "health_check_passed": true,
      "checksum": "sha256:abc123..."
    },
    "nginx_exporter": {
      "status": "in_progress",
      "from_version": "1.1.0",
      "to_version": "1.5.1",
      "started_at": "2025-01-01T12:03:00Z",
      "attempts": 1
    }
  },
  "errors": [],
  "checkpoints": []
}
```

### State Operations

```bash
# View current state
sudo ./scripts/upgrade-orchestrator.sh --status

# Verify state consistency
sudo ./scripts/upgrade-orchestrator.sh --verify

# View upgrade history
sudo cat /var/lib/observability-upgrades/history/upgrade-*.json | jq '.'
```

### State Transitions

```
idle → in_progress → completed
       ↓
       failed → in_progress (resume)
       ↓
       rolled_back
```

## Safety Features

### Pre-Upgrade Validation

Before any upgrade:

1. **Disk Space Check**: Ensures minimum 1GB free
2. **Dependency Check**: Verifies dependencies are satisfied
3. **Version Validation**: Confirms target version is valid
4. **Service Status**: Checks if services are running
5. **Configuration Validation**: Runs config checks (e.g., `promtool check config`)

### Automatic Backups

Each component upgrade creates a backup:

```
/var/lib/observability-upgrades/backups/
└── node_exporter/
    └── 20250101_120100/
        ├── node_exporter          # Binary backup
        ├── node_exporter.service  # Service file backup
        └── metadata.json          # Backup metadata
```

### Health Checks

After upgrade, automated health checks:

1. **Service Status**: `systemctl is-active <service>`
2. **HTTP Endpoint**: Check metrics endpoint responds
3. **Metrics Validation**: Verify metrics are being exported
4. **Response Time**: Ensure timely responses

### Automatic Rollback

If health checks fail:

```
[ERROR] Health check failed for node_exporter
[WARN] Attempting automatic rollback...
[INFO] Restoring from backup: /var/lib/observability-upgrades/backups/...
[INFO] Restarting service: node_exporter
[SUCCESS] Rollback successful for node_exporter
```

## Configuration

### Upgrade Configuration File

Edit `config/upgrade.yaml` to customize:

```yaml
# Change target versions
components:
  node_exporter:
    target_version: "1.10.0"  # Update to newer version

# Adjust safety settings
global:
  validation:
    min_disk_space: 2048  # Require 2GB instead of 1GB
    health_check_timeout: 90  # 90 seconds instead of 60

# Configure two-stage upgrades
components:
  prometheus:
    upgrade_strategy: "two-stage"
    intermediate_version: "2.55.1"
    target_version: "3.8.1"
```

### Environment Variables

Override behavior with environment variables:

```bash
# Use custom state directory
export STATE_DIR=/custom/path
sudo ./scripts/upgrade-orchestrator.sh --all

# Enable debug logging
export DEBUG=true
sudo ./scripts/upgrade-orchestrator.sh --component node_exporter

# Skip version checks (dangerous!)
export VERSION_OVERRIDE_NODE_EXPORTER=1.9.1
```

## Testing

### Run Idempotency Tests

```bash
# Run all tests
sudo ./tests/test-upgrade-idempotency.sh

# Run specific test
sudo ./tests/test-upgrade-idempotency.sh --test test_double_run_idempotency

# Verbose output
sudo ./tests/test-upgrade-idempotency.sh --verbose
```

**Test Coverage:**

1. State initialization
2. Double-run idempotency
3. Crash recovery
4. Version comparison
5. State locking
6. Checkpoint management
7. Failure handling
8. Skip detection

### Manual Testing Procedure

1. **Test dry-run mode**:
   ```bash
   sudo ./scripts/upgrade-orchestrator.sh --all --dry-run
   ```

2. **Test single component**:
   ```bash
   sudo ./scripts/upgrade-orchestrator.sh --component node_exporter
   ```

3. **Test idempotency** (run twice):
   ```bash
   sudo ./scripts/upgrade-orchestrator.sh --component node_exporter
   sudo ./scripts/upgrade-orchestrator.sh --component node_exporter
   # Second run should skip
   ```

4. **Test resume**:
   ```bash
   # Start upgrade and interrupt it (Ctrl+C)
   sudo ./scripts/upgrade-orchestrator.sh --all
   # Resume
   sudo ./scripts/upgrade-orchestrator.sh --resume
   ```

5. **Test rollback**:
   ```bash
   sudo ./scripts/upgrade-orchestrator.sh --component node_exporter
   sudo ./scripts/upgrade-orchestrator.sh --rollback
   ```

## Troubleshooting

### Issue: Upgrade Fails with "Lock acquisition failed"

**Cause**: Another upgrade process is running or previous process crashed

**Solution**:
```bash
# Check for running processes
ps aux | grep upgrade-orchestrator

# Remove stale lock if no process running
sudo rm -rf /var/lib/observability-upgrades/.state.lock

# Retry
sudo ./scripts/upgrade-orchestrator.sh --resume
```

### Issue: Component shows as "in_progress" but upgrade not running

**Cause**: Previous upgrade crashed mid-component

**Solution**:
```bash
# Check state
sudo ./scripts/upgrade-orchestrator.sh --status

# Resume to continue
sudo ./scripts/upgrade-orchestrator.sh --resume

# Or force reset (loses resume capability)
sudo rm /var/lib/observability-upgrades/state.json
sudo ./scripts/upgrade-orchestrator.sh --all
```

### Issue: Health check fails after upgrade

**Cause**: Service not starting or configuration issue

**Solution**:
```bash
# Check service logs
sudo journalctl -u node_exporter -n 50

# Check service status
sudo systemctl status node_exporter

# Manual rollback if automatic failed
sudo ./scripts/upgrade-orchestrator.sh --rollback

# Or restore from backup manually
BACKUP=/var/lib/observability-upgrades/backups/node_exporter/latest
sudo cp $BACKUP/node_exporter /usr/local/bin/
sudo systemctl restart node_exporter
```

### Issue: "No target version defined"

**Cause**: Component not configured in upgrade.yaml

**Solution**:
```bash
# Check configuration
grep -A 10 "component_name:" config/upgrade.yaml

# Add missing configuration
sudo nano config/upgrade.yaml
# Add:
#   component_name:
#     target_version: "x.y.z"
#     github_repo: "org/repo"
```

### Issue: Download fails with checksum mismatch

**Cause**: Corrupted download or incorrect checksum

**Solution**:
```bash
# Clear download cache
sudo rm -rf /tmp/*exporter*

# Retry upgrade
sudo ./scripts/upgrade-orchestrator.sh --component node_exporter

# If persistent, check GitHub releases manually
# Update checksums in config if needed
```

### Debug Mode

Enable detailed logging:

```bash
# Set debug mode
export DEBUG=true
export VERSION_DEBUG=true

# Run upgrade with verbose output
sudo -E ./scripts/upgrade-orchestrator.sh --component node_exporter 2>&1 | tee upgrade.log

# Review logs
less upgrade.log
```

## Advanced Topics

### Custom Components

To add a new component to the upgrade system:

1. **Update config/upgrade.yaml**:
   ```yaml
   components:
     custom_exporter:
       current_version: "1.0.0"
       target_version: "2.0.0"
       github_repo: "org/custom_exporter"
       phase: 1
       risk_level: low
       service: "custom_exporter"
       binary_path: "/usr/local/bin/custom_exporter"
       health_check:
         type: "http"
         endpoint: "http://localhost:9999/metrics"
         expected_status: 200
   ```

2. **Ensure install script exists**:
   ```bash
   modules/_core/custom_exporter/install.sh
   ```

3. **Test**:
   ```bash
   sudo ./scripts/upgrade-orchestrator.sh --component custom_exporter --dry-run
   ```

### Scheduled Upgrades

Set up automatic upgrades with cron:

```bash
# Create cron job for monthly upgrades
sudo crontab -e

# Add:
# Monthly upgrade check (1st of month at 2 AM)
0 2 1 * * /path/to/observability-stack/scripts/upgrade-orchestrator.sh --all --mode standard --yes >> /var/log/observability-upgrade.log 2>&1
```

### Integration with CI/CD

```yaml
# GitHub Actions example
name: Upgrade Observability Stack

on:
  schedule:
    - cron: '0 2 * * 0'  # Weekly on Sunday 2 AM

jobs:
  upgrade:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v2

      - name: Run upgrade
        run: |
          sudo ./scripts/upgrade-orchestrator.sh --all --mode fast --yes

      - name: Verify health
        run: |
          ./scripts/health-check.sh
```

## Best Practices

1. **Always dry-run first**: Test with `--dry-run` before actual upgrade
2. **Use safe mode for production**: `--mode safe` for critical systems
3. **Monitor during upgrades**: Watch logs and metrics during upgrade
4. **Backup before major versions**: Extra backups for Prometheus 2→3
5. **Test in staging first**: Validate in non-production environment
6. **Schedule during low-traffic**: Run upgrades during maintenance windows
7. **Keep state backups**: Backup `/var/lib/observability-upgrades/`
8. **Review history regularly**: Check upgrade history for patterns
9. **Update configurations**: Keep `upgrade.yaml` current with new versions
10. **Test rollback procedure**: Periodically test rollback functionality

## Reference

### Exit Codes

- `0`: Success
- `1`: General failure
- `2`: Validation failed
- `3`: User canceled

### Component Status Values

- `pending`: Not yet started
- `in_progress`: Currently upgrading
- `completed`: Successfully upgraded
- `failed`: Upgrade failed
- `skipped`: Skipped (already at target version)

### Upgrade Modes

- `safe`: Maximum safety, manual confirmations
- `standard`: Balanced (default)
- `fast`: Minimal pauses, for CI/CD
- `dry_run`: Simulation only

### File Locations

- Config: `/config/upgrade.yaml`
- State: `/var/lib/observability-upgrades/state.json`
- Backups: `/var/lib/observability-upgrades/backups/`
- History: `/var/lib/observability-upgrades/history/`
- Logs: `/var/log/observability-setup.log`

## Support

For issues or questions:

1. Check this documentation
2. Review `/var/log/observability-setup.log`
3. Run `--verify` to check state consistency
4. Check GitHub issues for the observability-stack repository
5. Run tests: `./tests/test-upgrade-idempotency.sh`
