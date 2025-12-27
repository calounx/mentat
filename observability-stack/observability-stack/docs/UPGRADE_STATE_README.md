# Upgrade State Machine - Quick Start Guide

## Overview

The upgrade state machine provides enterprise-grade upgrade management with:

- **State Tracking**: Complete audit trail of upgrade progress
- **Idempotency**: Safe to run multiple times, skips completed work
- **Crash Recovery**: Resume from last checkpoint after interruptions
- **Concurrency Safety**: Prevents multiple simultaneous upgrades
- **Rollback Support**: Track backup points for safe rollback

## Quick Start

### 1. Basic Usage

```bash
#!/usr/bin/env bash
source /path/to/scripts/lib/upgrade-state.sh

# Initialize upgrade
upgrade_id=$(upgrade_state_init)

# Acquire exclusive lock
upgrade_lock_acquire || exit 1

# Transition through states
upgrade_state_set "PLANNING"
upgrade_state_set "UPGRADING"

# Upgrade components
upgrade_phase_start "exporters"
upgrade_component_start "node_exporter" "1.7.0" "1.9.1"
# ... perform upgrade ...
upgrade_component_complete "node_exporter"
upgrade_phase_complete "exporters"

# Finish
upgrade_state_set "VALIDATING"
upgrade_state_set "COMPLETED"
upgrade_cleanup
```

### 2. With Idempotency

```bash
#!/usr/bin/env bash
source /path/to/scripts/lib/upgrade-state.sh

upgrade_component_safe() {
    local component="$1"

    # Skip if already upgraded
    if upgrade_component_is_upgraded "$component"; then
        echo "$component already upgraded"
        return 0
    fi

    # Perform upgrade
    upgrade_component_start "$component" "1.0.0" "2.0.0"
    # ... actual upgrade work ...
    upgrade_component_complete "$component"
}

# Safe to run multiple times
upgrade_component_safe "node_exporter"
```

### 3. With Crash Recovery

```bash
#!/usr/bin/env bash
source /path/to/scripts/lib/upgrade-state.sh

# Check for existing upgrade
if upgrade_is_in_progress; then
    if upgrade_can_resume; then
        echo "Resuming previous upgrade"
        upgrade_resume
        # Continue from where it left off
    else
        echo "Cannot resume, manual intervention needed"
        exit 1
    fi
fi

# Start new upgrade if none in progress
upgrade_state_init
```

### 4. With Rollback Support

```bash
#!/usr/bin/env bash
source /path/to/scripts/lib/upgrade-state.sh

upgrade_with_backup() {
    local component="$1"

    upgrade_component_start "$component" "1.0.0" "2.0.0"

    # Create backup
    backup_path="/var/lib/observability-upgrades/backups/${component}.tar.gz"
    create_backup "$component" "$backup_path"

    # Mark rollback point
    upgrade_mark_rollback_point "$component" "$backup_path"

    # Upgrade
    # ... perform upgrade ...

    upgrade_component_complete "$component"
}

# Later, get rollback info
rollback_info=$(upgrade_get_rollback_info)
echo "$rollback_info" | jq '.components[]'
```

## State Flow

```
IDLE → PLANNING → BACKING_UP → UPGRADING → VALIDATING → COMPLETED
                                    ↓
                              ROLLING_BACK → ROLLED_BACK
                                    ↓
                                FAILED
```

## File Locations

```
/var/lib/observability-upgrades/
├── state.json              # Current state
├── upgrade.lock           # Concurrency lock
├── backups/               # Component backups
└── history/               # Completed upgrades
```

## Common Patterns

### Pattern 1: Simple Sequential Upgrade

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib/upgrade-state.sh"

main() {
    upgrade_state_init >/dev/null
    upgrade_lock_acquire || exit 1
    trap 'upgrade_cleanup' EXIT

    upgrade_state_set "UPGRADING"
    upgrade_phase_start "exporters"

    for component in node_exporter nginx_exporter mysqld_exporter; do
        upgrade_component_start "$component" "1.0.0" "2.0.0"
        perform_upgrade "$component"
        upgrade_component_complete "$component"
    done

    upgrade_phase_complete "exporters"
    upgrade_state_set "COMPLETED"
}

main "$@"
```

### Pattern 2: Resumable Multi-Phase Upgrade

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib/upgrade-state.sh"

upgrade_phase() {
    local phase="$1"
    shift
    local components=("$@")

    upgrade_phase_start "$phase"

    for component in "${components[@]}"; do
        if upgrade_component_is_upgraded "$component"; then
            continue  # Skip already upgraded
        fi

        upgrade_component_start "$component" "1.0.0" "2.0.0"

        if perform_upgrade "$component"; then
            upgrade_component_complete "$component"
        else
            upgrade_component_fail "$component" "Upgrade failed"
            return 1
        fi
    done

    upgrade_phase_complete "$phase"
}

main() {
    # Resume or start new
    if ! upgrade_is_in_progress; then
        upgrade_state_init >/dev/null
    fi

    upgrade_lock_acquire || exit 1
    trap 'upgrade_cleanup' EXIT

    upgrade_state_set "UPGRADING"

    # Each phase is resumable
    upgrade_phase "exporters" node_exporter nginx_exporter
    upgrade_phase "prometheus" prometheus alertmanager
    upgrade_phase "visualization" grafana

    upgrade_state_set "COMPLETED"
}

main "$@"
```

### Pattern 3: Progress Monitoring

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib/upgrade-state.sh"

monitor_upgrade() {
    while upgrade_is_in_progress; do
        clear
        echo "=== Upgrade Progress ==="

        # Show summary
        upgrade_get_summary

        # Show progress bar
        progress=$(upgrade_get_progress_percent)
        echo ""
        echo "Progress: ${progress}%"

        # Visual bar
        local filled=$((progress / 2))
        printf "["
        printf "%${filled}s" | tr ' ' '█'
        printf "%$((50 - filled))s" | tr ' ' '░'
        printf "]\n"

        sleep 2
    done

    echo "Upgrade complete!"
}

# Run in background
upgrade_script.sh &
monitor_upgrade
```

### Pattern 4: Error Handling with Retry

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib/upgrade-state.sh"

upgrade_with_retry() {
    local component="$1"
    local max_attempts=3

    if upgrade_component_is_upgraded "$component"; then
        return 0
    fi

    upgrade_component_start "$component" "1.0.0" "2.0.0"

    for attempt in $(seq 1 $max_attempts); do
        if perform_upgrade "$component"; then
            upgrade_component_complete "$component"
            return 0
        fi

        echo "Attempt $attempt failed, retrying..."
        sleep 5
    done

    upgrade_component_fail "$component" "Failed after $max_attempts attempts"
    return 1
}
```

## Testing

### Run All Tests

```bash
# Unit tests
bash tests/test-upgrade-state.sh

# Concurrency tests
bash tests/test-concurrency.sh

# Full integration test
bash examples/upgrade-with-state.sh
```

### Run Specific Test Categories

```bash
# Test state transitions
bash tests/test-upgrade-state.sh | grep "State transitions"

# Test lock safety
bash tests/test-concurrency.sh | grep "Lock"

# Test crash recovery
bash tests/test-upgrade-state.sh | grep "recovery"
```

## API Quick Reference

### State Management
- `upgrade_state_init([id])` - Initialize new upgrade
- `upgrade_state_get_current()` - Get current state
- `upgrade_state_set(state)` - Set new state

### Phase Management
- `upgrade_phase_start(phase)` - Start phase
- `upgrade_phase_complete(phase)` - Complete phase
- `upgrade_phase_fail(phase, error)` - Mark failed

### Component Tracking
- `upgrade_component_start(comp, from, to)` - Start component upgrade
- `upgrade_component_complete(comp)` - Complete component
- `upgrade_component_fail(comp, error)` - Mark failed
- `upgrade_component_is_upgraded(comp)` - Check if upgraded

### Recovery
- `upgrade_can_resume()` - Check if resumable
- `upgrade_resume()` - Resume from checkpoint

### Locking
- `upgrade_lock_acquire()` - Get exclusive lock
- `upgrade_lock_release()` - Release lock
- `upgrade_lock_is_held()` - Check lock status

### Rollback
- `upgrade_mark_rollback_point(comp, path)` - Mark rollback
- `upgrade_get_rollback_info()` - Get rollback data

### Utilities
- `upgrade_is_in_progress()` - Check if running
- `upgrade_get_progress_percent()` - Get progress %
- `upgrade_get_summary()` - Get summary
- `upgrade_cleanup()` - Cleanup on completion

## Troubleshooting

### Upgrade Won't Start

```bash
# Check if upgrade is in progress
if upgrade_is_in_progress; then
    # Check if can resume
    if upgrade_can_resume; then
        upgrade_resume
    else
        echo "Manual intervention needed"
        upgrade_get_summary
    fi
fi

# Check for stale lock
upgrade_lock_check_stale
```

### Corrupted State File

```bash
# Restore from history
latest=$(ls -t /var/lib/observability-upgrades/history/*.json | head -n1)
cp "$latest" /var/lib/observability-upgrades/state.json
```

### Reset to Clean State

```bash
# WARNING: Loses current upgrade progress
source /path/to/upgrade-state.sh
upgrade_state_init >/dev/null
upgrade_state_set "IDLE"
upgrade_lock_release
```

### Check What Failed

```bash
# Get current state
upgrade_get_summary

# Check specific component
component_status=$(upgrade_component_get_status "node_exporter")
echo "$component_status" | jq '.'

# See last error
jq '.phases[].components[] | select(.state == "FAILED") | {name: .key, error: .last_error}' \
    /var/lib/observability-upgrades/state.json
```

## Performance Tips

1. **Minimize State Writes**: Group operations, save state at checkpoints
2. **Use Phases**: Organize components into logical phases
3. **Check Before Upgrading**: Always use `upgrade_component_is_upgraded()`
4. **Lock Early**: Acquire lock before planning to prevent races
5. **Save to History**: Call `upgrade_save_to_history()` periodically

## Security Considerations

- State directory: `700` permissions (owner only)
- State files: `600` permissions
- Locks include PID, user, hostname for verification
- No secrets stored in state (only paths, versions, states)

## Best Practices

1. **Always use traps for cleanup**
   ```bash
   trap 'upgrade_cleanup' EXIT
   ```

2. **Check idempotency before operations**
   ```bash
   if upgrade_component_is_upgraded "$comp"; then
       return 0
   fi
   ```

3. **Create backups before upgrades**
   ```bash
   upgrade_mark_rollback_point "$comp" "$backup_path"
   ```

4. **Handle errors gracefully**
   ```bash
   if ! upgrade_component_start "$comp" "1.0" "2.0"; then
       upgrade_component_fail "$comp" "$error_msg"
       return 1
   fi
   ```

5. **Validate state transitions**
   ```bash
   # State machine automatically validates transitions
   upgrade_state_set "INVALID_STATE"  # Will fail with error
   ```

## Examples

Full working examples are available in:

- `examples/upgrade-with-state.sh` - Complete upgrade workflow
- `tests/test-upgrade-state.sh` - Unit tests with examples
- `tests/test-concurrency.sh` - Concurrency patterns

## Documentation

Full documentation:
- `docs/upgrade-state-machine.md` - Complete API reference
- `docs/UPGRADE_STATE_README.md` - This quick start guide

## Support

For issues or questions:
1. Check state with `upgrade_get_summary`
2. Review logs in `/var/log/observability/`
3. Inspect state file: `jq '.' /var/lib/observability-upgrades/state.json`
4. Check lock status: `cat /var/lib/observability-upgrades/upgrade.lock`

## License

MIT License - See project LICENSE file for details.
