# Service Detection Fix Documentation

## Problem Summary

Services (Prometheus, Loki, etc.) were starting successfully but being incorrectly reported as failed by `enable_and_start()`.

### Symptoms
- Prometheus WAS running (generating logs about alert manager connections)
- Loki WAS running (generating logs about index uploads)
- But `enable_and_start` reported: "Service prometheus:10 not available after 30 attempts"
- Error: "prometheus failed to start"

### Error Message Analysis
The error format "Service prometheus:10" indicated the function was treating "prometheus" as a hostname and "10" as a port number, which was the critical clue.

## Root Cause

**Function Signature Conflict** between two different implementations of `wait_for_service()`:

### Deploy Library Implementation
Located in:
- `/home/calounx/repositories/mentat/observability-stack/deploy/lib/common.sh`
- `/home/calounx/repositories/mentat/observability-stack/deploy/lib/shared.sh`

Signature: `wait_for_service "service_name" [max_wait_seconds]`
- Checks: systemctl is-active status
- Purpose: Wait for systemd service to become active

### Scripts Library Implementation
Located in:
- `/home/calounx/repositories/mentat/observability-stack/scripts/lib/common.sh`

Signature: `wait_for_service "host" "port" [max_attempts] [delay]`
- Checks: TCP port connectivity using `check_port()`
- Purpose: Wait for network service to be listening on a port

### Loading Chain

The scripts library version was overriding the deploy version due to this dependency chain:

1. `deploy/install.sh` sources `deploy/lib/common.sh` (line 17)
2. `deploy/lib/common.sh` sources `deploy/lib/shared.sh` (line 35)
3. `deploy/lib/shared.sh` sources `scripts/lib/validation.sh` (line 38)
4. `scripts/lib/validation.sh` sources `scripts/lib/common.sh` (line 14)
5. **`scripts/lib/common.sh`** defines `wait_for_service(host, port)` which **OVERRIDES** the fallback

### The Bug

When `enable_and_start()` called:
```bash
wait_for_service "$service" 10
```

With the scripts library version loaded, this was interpreted as:
- `host = "prometheus"`
- `port = 10`
- Result: Attempted to connect to host "prometheus" on port 10
- This check failed even though the systemd service was running correctly

The error message confirmed this:
```
Service prometheus:10 not available after 30 attempts
```

This is the EXACT format from `scripts/lib/common.sh` line 649:
```bash
log_error "Service $host:$port not available after $max_attempts attempts"
```

## Solution

### 1. Renamed Function to Avoid Conflict

Changed the systemd service checker from `wait_for_service()` to `wait_for_systemd_service()`:

**In `/observability-stack/deploy/lib/common.sh`:**
```bash
# Service wait (renamed to avoid conflict with scripts/lib/common.sh)
# Note: scripts/lib/common.sh has wait_for_service(host, port) for TCP checks
#       This function is for systemd service status checking
if ! declare -f wait_for_systemd_service >/dev/null 2>&1; then
    wait_for_systemd_service() {
        local service="$1"
        local max_wait="${2:-30}"
        local count=0

        while ! systemctl is-active --quiet "$service" 2>/dev/null; do
            sleep 1
            count=$((count + 1))
            if [[ $count -ge $max_wait ]]; then
                log_error "Service $service did not become active after $max_wait seconds"
                return 1
            fi
        done
        return 0
    }
fi
```

**Also updated in `/observability-stack/deploy/lib/shared.sh`** with the same implementation.

### 2. Updated enable_and_start() Function

**In `/observability-stack/deploy/lib/common.sh`:**

```bash
enable_and_start() {
    local service="$1"

    log_info "Starting service: $service"

    systemctl enable "$service" 2>&1 | grep -v "Created symlink" || true
    systemctl start "$service"

    # Use systemd-specific wait function (not the TCP port checker)
    if wait_for_systemd_service "$service" 10; then
        log_success "$service started successfully"
    else
        log_error "$service failed to start"
        log_error "Recent logs from $service:"
        journalctl -u "$service" --no-pager -n 20
        return 1
    fi
}
```

**Improvements:**
- Uses `wait_for_systemd_service` instead of `wait_for_service`
- Adds `log_info "Starting service: $service"` to show which service is being started
- Filters out noise from `systemctl enable` symlink messages
- Better error logging with "Recent logs from $service:"

### 3. Improved Color Detection

**In `/observability-stack/deploy/lib/common.sh`:**

```bash
# Detect if terminal supports colors
supports_colors() {
    # Disable colors if NO_COLOR is set or TERM is dumb
    if [[ -n "${NO_COLOR:-}" ]] || [[ "${TERM:-}" == "dumb" ]]; then
        return 1
    fi

    # Check if stdout is a terminal and supports colors
    if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
        local colors
        colors=$(tput colors 2>/dev/null || echo 0)
        [[ $colors -ge 8 ]]
    else
        return 1
    fi
}
```

This respects the `NO_COLOR` environment variable and checks for dumb terminals.

## Testing

Created test script at `/home/calounx/repositories/mentat/test-service-detection.sh` that verifies:

1. `wait_for_systemd_service` function exists
2. Function works with active services
3. `wait_for_service` still exists for TCP checks (from scripts/lib)
4. `enable_and_start` uses the correct function
5. Improved logging is present

All tests pass successfully.

## Files Modified

1. `/home/calounx/repositories/mentat/observability-stack/deploy/lib/common.sh`
   - Renamed `wait_for_service` → `wait_for_systemd_service`
   - Updated `enable_and_start()` to use new function
   - Added better logging
   - Improved color detection

2. `/home/calounx/repositories/mentat/observability-stack/deploy/lib/shared.sh`
   - Renamed `wait_for_service` → `wait_for_systemd_service`
   - Added clarifying comments

## Verification

To verify services are now properly detected:

```bash
# Run the test script
./test-service-detection.sh

# Or test manually with a real deployment
sudo ./observability-stack/deploy/install.sh
```

When services start, you should now see:
```
[INFO] Starting service: prometheus
[SUCCESS] prometheus started successfully
[INFO] Starting service: loki
[SUCCESS] loki started successfully
```

## Design Considerations

### Why Not Just Fix the Call Site?

We could have changed `enable_and_start()` to pass the correct parameters for the TCP-based `wait_for_service()`, but this would be wrong because:

1. **Semantic mismatch**: We want to check if the systemd service is active, not if a port is listening
2. **Port knowledge required**: We'd need to know which port each service uses
3. **Timing issues**: A port might be listening before the service is fully initialized
4. **Single responsibility**: `enable_and_start()` should check service status, not network connectivity

### Why Keep Both Functions?

The two functions serve different purposes:

- `wait_for_systemd_service()`: For deployment scripts checking if a systemd service started
- `wait_for_service(host, port)`: For runtime scripts checking if a network service is reachable

Both are valid and useful in their respective contexts.

## Prevention

To prevent similar issues in the future:

1. **Function naming**: Use descriptive names that indicate the specific type of check
2. **Guard clauses**: The `if ! declare -f ... >/dev/null 2>&1; then` pattern prevents redefinition
3. **Documentation**: Clear comments explaining the purpose and signature of functions
4. **Testing**: The test script can be run to verify no regressions

## Related Functions

Other functions in the codebase that might have similar patterns:

- `check_port()` - TCP connectivity check (scripts/lib)
- `check_port_available()` - Port availability check (deploy/lib)
- `safe_stop_service()` - Service stopping (scripts/lib)

These should be reviewed to ensure no similar conflicts exist.
