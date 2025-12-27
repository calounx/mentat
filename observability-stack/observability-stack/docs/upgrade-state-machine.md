# Upgrade State Machine

## Overview

The upgrade state machine provides robust state tracking, idempotency, crash recovery, and concurrency safety for observability stack upgrades. It ensures that upgrades can be safely resumed after interruptions and prevents concurrent upgrade operations.

## Architecture

### State Flow Diagram

```
┌──────────────┐
│     IDLE     │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│   PLANNING   │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ BACKING_UP   │
└──────┬───────┘
       │
       ▼
┌──────────────┐     ┌──────────────┐
│  UPGRADING   │────▶│ROLLING_BACK  │
└──────┬───────┘     └──────┬───────┘
       │                    │
       │                    ▼
       │             ┌──────────────┐
       │             │ROLLED_BACK   │
       │             └──────────────┘
       │
       ▼
┌──────────────┐
│ VALIDATING   │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  COMPLETED   │
└──────────────┘
       │
       ▼
┌──────────────┐
│   FAILED     │
└──────────────┘
```

### State Definitions

| State | Description | Resumable | Next States |
|-------|-------------|-----------|-------------|
| `IDLE` | No upgrade in progress | No | `PLANNING` |
| `PLANNING` | Analyzing what needs upgrading | Yes | `BACKING_UP` |
| `BACKING_UP` | Creating backups before upgrade | Yes | `UPGRADING` |
| `UPGRADING` | Actively upgrading components | Yes | `VALIDATING`, `ROLLING_BACK`, `FAILED` |
| `VALIDATING` | Running post-upgrade validation | Yes | `COMPLETED`, `FAILED` |
| `COMPLETED` | Successfully completed | No | `IDLE` |
| `ROLLING_BACK` | Reverting changes | Yes | `ROLLED_BACK` |
| `ROLLED_BACK` | Successfully reverted | No | `IDLE` |
| `FAILED` | Upgrade failed | No | `IDLE` |

### Component States

| State | Description |
|-------|-------------|
| `PENDING` | Component queued for upgrade |
| `UPGRADING` | Component currently being upgraded |
| `COMPLETED` | Component successfully upgraded |
| `FAILED` | Component upgrade failed |
| `SKIPPED` | Component skipped (already at target version) |

## State Persistence

### State File Location

```
/var/lib/observability-upgrades/state.json
```

### State Schema

```json
{
  "upgrade_id": "upgrade-20251227-103000",
  "current_state": "UPGRADING",
  "started_at": "2025-12-27T10:30:00Z",
  "updated_at": "2025-12-27T10:35:15Z",
  "current_phase": "exporters",
  "current_component": "node_exporter",
  "phases": {
    "exporters": {
      "state": "IN_PROGRESS",
      "started_at": "2025-12-27T10:30:00Z",
      "components": {
        "node_exporter": {
          "state": "UPGRADING",
          "from_version": "1.7.0",
          "to_version": "1.9.1",
          "started_at": "2025-12-27T10:35:00Z",
          "backup_path": "/var/lib/observability-upgrades/backups/node_exporter-1.7.0-20251227.tar.gz",
          "attempts": 1,
          "last_error": null
        },
        "nginx_exporter": {
          "state": "PENDING",
          "from_version": "1.1.0",
          "to_version": "1.5.1"
        }
      }
    },
    "prometheus": {
      "state": "PENDING"
    }
  },
  "rollback_available": true,
  "can_resume": true,
  "metadata": {
    "hostname": "monitoring-server",
    "user": "root",
    "pid": "12345"
  }
}
```

## API Reference

### State Management Functions

#### `upgrade_state_init([upgrade_id])`

Initialize a new upgrade state.

**Parameters:**
- `upgrade_id` (optional): Custom upgrade ID. Auto-generated if not provided.

**Returns:**
- Upgrade ID on success
- Exit code 1 on failure

**Example:**
```bash
upgrade_id=$(upgrade_state_init)
echo "Started upgrade: $upgrade_id"
```

#### `upgrade_state_load()`

Load current upgrade state.

**Returns:**
- JSON state content on stdout
- Exit code 1 if no state exists

**Example:**
```bash
if state=$(upgrade_state_load); then
    echo "State loaded successfully"
fi
```

#### `upgrade_state_save(state_json)`

Save updated state.

**Parameters:**
- `state_json`: JSON content to save

**Returns:**
- Exit code 0 on success, 1 on failure

#### `upgrade_state_get_current()`

Get current state name.

**Returns:**
- State name on stdout
- Exit code 1 on failure

**Example:**
```bash
current_state=$(upgrade_state_get_current)
echo "Current state: $current_state"
```

#### `upgrade_state_set(new_state)`

Set upgrade state with validation.

**Parameters:**
- `new_state`: Target state name

**Returns:**
- Exit code 0 on success, 1 on invalid transition

**Example:**
```bash
if upgrade_state_set "UPGRADING"; then
    echo "Transitioned to UPGRADING"
else
    echo "Invalid state transition"
fi
```

### Phase Management Functions

#### `upgrade_phase_start(phase_name)`

Start a new upgrade phase.

**Parameters:**
- `phase_name`: Name of the phase (e.g., "exporters", "prometheus")

**Returns:**
- Exit code 0 on success, 1 on failure

**Example:**
```bash
upgrade_phase_start "exporters"
```

#### `upgrade_phase_complete(phase_name)`

Mark phase as completed.

**Parameters:**
- `phase_name`: Name of the phase

**Returns:**
- Exit code 0 on success, 1 on failure

#### `upgrade_phase_fail(phase_name, error_message)`

Mark phase as failed.

**Parameters:**
- `phase_name`: Name of the phase
- `error_message`: Error description

**Returns:**
- Exit code 0 on success, 1 on failure

#### `upgrade_phase_get_next()`

Get next pending phase.

**Returns:**
- Phase name on stdout, empty if none
- Exit code 0 on success

### Component Tracking Functions

#### `upgrade_component_start(component, from_version, to_version)`

Start upgrading a component.

**Parameters:**
- `component`: Component name
- `from_version`: Current version
- `to_version`: Target version

**Returns:**
- Exit code 0 on success, 1 on failure

**Example:**
```bash
upgrade_component_start "node_exporter" "1.7.0" "1.9.1"
```

#### `upgrade_component_complete(component)`

Mark component upgrade as complete.

**Parameters:**
- `component`: Component name

**Returns:**
- Exit code 0 on success, 1 on failure

#### `upgrade_component_fail(component, error_message)`

Mark component upgrade as failed.

**Parameters:**
- `component`: Component name
- `error_message`: Error description

**Returns:**
- Exit code 0 on success, 1 on failure

#### `upgrade_component_is_upgraded(component)`

Check if component is already upgraded.

**Parameters:**
- `component`: Component name

**Returns:**
- Exit code 0 if upgraded, 1 if not

**Example:**
```bash
if upgrade_component_is_upgraded "node_exporter"; then
    echo "Already upgraded, skipping"
    exit 0
fi
```

#### `upgrade_component_get_status(component)`

Get component status details.

**Parameters:**
- `component`: Component name

**Returns:**
- JSON object with component status

**Example:**
```bash
status=$(upgrade_component_get_status "node_exporter")
state=$(echo "$status" | jq -r '.state')
```

### Resume & Recovery Functions

#### `upgrade_can_resume()`

Check if upgrade can be resumed.

**Returns:**
- Exit code 0 if can resume, 1 if not

**Example:**
```bash
if upgrade_can_resume; then
    upgrade_resume
fi
```

#### `upgrade_get_resume_point()`

Get resume point information.

**Returns:**
- JSON with resume information

**Example:**
```bash
resume_info=$(upgrade_get_resume_point)
echo "$resume_info" | jq '.'
```

#### `upgrade_resume()`

Resume upgrade from last checkpoint.

**Returns:**
- Exit code 0 on success, 1 on failure

### Rollback Functions

#### `upgrade_mark_rollback_point(component, backup_path)`

Mark a rollback point for a component.

**Parameters:**
- `component`: Component name
- `backup_path`: Path to backup file

**Returns:**
- Exit code 0 on success, 1 on failure

**Example:**
```bash
backup_path="/var/lib/observability-upgrades/backups/node_exporter-1.7.0.tar.gz"
upgrade_mark_rollback_point "node_exporter" "$backup_path"
```

#### `upgrade_get_rollback_info()`

Get rollback information.

**Returns:**
- JSON with rollback data

**Example:**
```bash
rollback_info=$(upgrade_get_rollback_info)
echo "$rollback_info" | jq '.components[]'
```

#### `upgrade_clear_rollback_point()`

Clear rollback points.

**Returns:**
- Exit code 0 on success, 1 on failure

### Query Functions

#### `upgrade_is_in_progress()`

Check if upgrade is currently in progress.

**Returns:**
- Exit code 0 if in progress, 1 if not

#### `upgrade_get_progress_percent()`

Calculate upgrade progress percentage.

**Returns:**
- Progress percentage (0-100) on stdout

**Example:**
```bash
progress=$(upgrade_get_progress_percent)
echo "Progress: ${progress}%"
```

#### `upgrade_get_summary()`

Get human-readable upgrade summary.

**Returns:**
- Summary text on stdout

**Example:**
```bash
upgrade_get_summary
```

#### `upgrade_list_history([limit])`

List upgrade history.

**Parameters:**
- `limit` (optional): Number of results (default: 10)

**Returns:**
- List of historical upgrades

**Example:**
```bash
upgrade_list_history 5
```

### Lock Functions

#### `upgrade_lock_acquire()`

Acquire upgrade lock.

**Returns:**
- Exit code 0 on success, 1 if already locked

**Example:**
```bash
if ! upgrade_lock_acquire; then
    echo "Another upgrade is in progress"
    exit 1
fi
```

#### `upgrade_lock_release()`

Release upgrade lock.

**Returns:**
- Exit code 0 on success

#### `upgrade_lock_is_held()`

Check if lock is currently held.

**Returns:**
- Exit code 0 if locked, 1 if not

#### `upgrade_lock_check_stale()`

Check for and remove stale locks.

**Returns:**
- Exit code 0 on success

## Usage Examples

### Basic Upgrade Flow

```bash
#!/usr/bin/env bash
source /path/to/upgrade-state.sh

# Initialize upgrade
upgrade_id=$(upgrade_state_init)
echo "Starting upgrade: $upgrade_id"

# Acquire lock
if ! upgrade_lock_acquire; then
    echo "Another upgrade is in progress"
    exit 1
fi

# Transition through states
upgrade_state_set "PLANNING"
upgrade_state_set "BACKING_UP"
upgrade_state_set "UPGRADING"

# Start phase
upgrade_phase_start "exporters"

# Upgrade components
for component in node_exporter nginx_exporter mysqld_exporter; do
    if upgrade_component_is_upgraded "$component"; then
        echo "$component already upgraded, skipping"
        continue
    fi

    upgrade_component_start "$component" "1.0.0" "2.0.0"

    # Perform actual upgrade...
    if perform_upgrade "$component"; then
        upgrade_component_complete "$component"
    else
        upgrade_component_fail "$component" "Upgrade failed"
        exit 1
    fi
done

upgrade_phase_complete "exporters"

# Validate and complete
upgrade_state_set "VALIDATING"
# Run validation...
upgrade_state_set "COMPLETED"

# Cleanup
upgrade_cleanup
```

### Idempotent Upgrade

```bash
#!/usr/bin/env bash
source /path/to/upgrade-state.sh

upgrade_component() {
    local component="$1"
    local from_version="$2"
    local to_version="$3"

    # Check if already upgraded
    if upgrade_component_is_upgraded "$component"; then
        echo "$component already at version $to_version, skipping"
        return 0
    fi

    echo "Upgrading $component from $from_version to $to_version"
    upgrade_component_start "$component" "$from_version" "$to_version"

    # Create backup
    local backup_path="/var/lib/observability-upgrades/backups/${component}-${from_version}.tar.gz"
    create_backup "$component" "$backup_path"
    upgrade_mark_rollback_point "$component" "$backup_path"

    # Perform upgrade
    if download_and_install "$component" "$to_version"; then
        upgrade_component_complete "$component"
        echo "$component upgraded successfully"
        return 0
    else
        upgrade_component_fail "$component" "Download or installation failed"
        return 1
    fi
}

# Upgrade can be run multiple times - only pending components will be processed
upgrade_component "node_exporter" "1.7.0" "1.9.1"
upgrade_component "nginx_exporter" "1.1.0" "1.5.1"
```

### Crash Recovery

```bash
#!/usr/bin/env bash
source /path/to/upgrade-state.sh

# Check if there's an upgrade in progress
if upgrade_is_in_progress; then
    echo "Found upgrade in progress"

    if upgrade_can_resume; then
        echo "Resuming from previous state"

        resume_info=$(upgrade_get_resume_point)
        echo "Resume point: $(echo "$resume_info" | jq '.')"

        upgrade_resume

        # Continue upgrade from resume point
        current_state=$(upgrade_state_get_current)
        case "$current_state" in
            "UPGRADING")
                # Resume component upgrades
                ;;
            "VALIDATING")
                # Resume validation
                ;;
        esac
    else
        echo "Cannot resume, manual intervention required"
        exit 1
    fi
fi
```

### Progress Monitoring

```bash
#!/usr/bin/env bash
source /path/to/upgrade-state.sh

monitor_upgrade() {
    while upgrade_is_in_progress; do
        clear
        echo "=== Upgrade Progress ==="
        echo ""
        upgrade_get_summary
        echo ""

        progress=$(upgrade_get_progress_percent)
        echo "Overall Progress: ${progress}%"

        # Draw progress bar
        local filled=$((progress / 2))
        local empty=$((50 - filled))
        printf "["
        printf "%${filled}s" | tr ' ' '='
        printf "%${empty}s" | tr ' ' ' '
        printf "]\n"

        sleep 2
    done

    echo ""
    echo "Upgrade completed!"
}

monitor_upgrade
```

## File Locations

### State Directory Structure

```
/var/lib/observability-upgrades/
├── state.json              # Current upgrade state
├── upgrade.lock           # Concurrent execution lock
├── tmp/                   # Temporary files
├── backups/               # Component backups
│   ├── node_exporter-1.7.0-20251227.tar.gz
│   ├── nginx_exporter-1.1.0-20251227.tar.gz
│   └── ...
└── history/               # Completed upgrade records
    ├── upgrade-20251227-103000.json
    ├── upgrade-20251220-140000.json
    └── ...
```

## Error Handling

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| "Invalid state transition" | Attempted invalid state change | Check current state and valid transitions |
| "Upgrade lock held by PID X" | Another upgrade is running | Wait for completion or check if stale |
| "No state file exists" | State not initialized | Call `upgrade_state_init()` first |
| "Corrupted state file" | Invalid JSON in state file | Restore from history or reinitialize |
| "No active phase for component" | Component operation without phase | Call `upgrade_phase_start()` first |

### Recovery Procedures

#### Corrupted State File

```bash
# Restore from most recent history
latest_history=$(ls -t /var/lib/observability-upgrades/history/*.json | head -n1)
cp "$latest_history" /var/lib/observability-upgrades/state.json
```

#### Stale Lock

```bash
# Remove stale lock
source /path/to/upgrade-state.sh
upgrade_lock_check_stale
```

#### Manual State Reset

```bash
# Reset to IDLE (careful - loses current upgrade state)
source /path/to/upgrade-state.sh
state=$(upgrade_state_load)
echo "$state" | jq '.current_state = "IDLE"' | upgrade_state_save
```

## Testing

Run the test suite:

```bash
cd /path/to/observability-stack
bash tests/test-upgrade-state.sh
```

Test categories:
- **Basic Functionality**: State initialization, transitions, phase/component management
- **Idempotency & Recovery**: Crash recovery, resume capability, rollback tracking
- **Concurrency Safety**: Lock acquisition, concurrent prevention, stale lock handling
- **Utilities**: Progress calculation, history tracking, atomic writes

## Performance Considerations

### State File Size

- State files are typically < 100KB even with hundreds of components
- JSON compression can reduce size further if needed
- Automatic cleanup of old history files (retention: 30 days recommended)

### Lock Timeout

- Default: 4 hours
- Configurable via `LOCK_TIMEOUT` variable
- Stale locks automatically cleaned up

### Atomic Operations

- All state writes use atomic file operations (write to temp, then mv)
- Prevents corruption during crashes or interruptions
- Safe for concurrent readers

## Security

### File Permissions

- State directory: `700` (owner only)
- State files: `600` (owner read/write only)
- Lock files: `600` (owner read/write only)

### Lock Ownership

- Locks include PID, timestamp, hostname, and user
- Only lock owner can release lock
- Process existence verified before considering lock valid

## Integration

### With Existing Upgrade Scripts

```bash
#!/usr/bin/env bash
# Source the state machine
source "$(dirname "$0")/lib/upgrade-state.sh"

# Wrap existing upgrade logic
main() {
    local upgrade_id
    upgrade_id=$(upgrade_state_init)

    if ! upgrade_lock_acquire; then
        echo "Upgrade already in progress"
        exit 1
    fi

    trap 'upgrade_cleanup' EXIT

    # Your existing upgrade code here
    # ...
}

main "$@"
```

## Best Practices

1. **Always check for existing upgrades** before starting new ones
2. **Use idempotency checks** before each component upgrade
3. **Create backups** before making changes
4. **Mark rollback points** for critical components
5. **Save state frequently** during long-running operations
6. **Validate state transitions** to prevent invalid flows
7. **Monitor progress** with `upgrade_get_progress_percent()`
8. **Save to history** on completion or failure
9. **Release locks** in trap handlers to ensure cleanup
10. **Test recovery** by simulating crashes during development

## Troubleshooting

### Enable Debug Logging

```bash
# Add to your upgrade script
set -x  # Enable bash tracing
export UPGRADE_DEBUG=1
```

### Inspect State File

```bash
# Pretty-print current state
jq '.' /var/lib/observability-upgrades/state.json

# Check specific component
jq '.phases.exporters.components.node_exporter' /var/lib/observability-upgrades/state.json

# List all components and their states
jq '.phases[].components | to_entries[] | "\(.key): \(.value.state)"' \
    /var/lib/observability-upgrades/state.json -r
```

### Verify Lock Status

```bash
# Check if lock exists
ls -la /var/lib/observability-upgrades/upgrade.lock

# Read lock information
cat /var/lib/observability-upgrades/upgrade.lock
# Format: PID|TIMESTAMP|HOSTNAME|USER

# Check if process is still running
lock_pid=$(cut -d'|' -f1 /var/lib/observability-upgrades/upgrade.lock)
ps -p "$lock_pid"
```

## License

MIT License - See project LICENSE file for details.
