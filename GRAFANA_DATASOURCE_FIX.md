# Grafana Datasource Configuration Fix

## Problem Summary

Grafana service was crashing on startup due to multiple datasource configuration files each marking Prometheus as the default datasource.

### Symptoms
- Grafana service fails to start
- Error in logs: `Datasource provisioning error: datasource.yaml config is invalid. Only one datasource per organization can be marked as default`
- Service enters crash loop: "Start request repeated too quickly"
- HTTPS returns 502 Bad Gateway (nginx can't reach Grafana on port 3000)

### Root Cause

**Multiple Conflicting Datasource Files**:

1. **Grafana apt package** creates: `/etc/grafana/provisioning/datasources/datasources.yaml`
   - Contains Prometheus with `isDefault: true`

2. **Our deployment script** creates: `/etc/grafana/provisioning/datasources/observability.yaml`
   - Also contains Prometheus with `isDefault: true`

Result: Grafana finds TWO default datasources and refuses to start.

### Error Log Evidence

```
logger=provisioning level=error msg="Failed to provision data sources"
error="Datasource provisioning error: datasource.yaml config is invalid.
Only one datasource per organization can be marked as default"

systemd[1]: grafana-server.service: Main process exited, code=exited, status=1/FAILURE
systemd[1]: grafana-server.service: Start request repeated too quickly.
systemd[1]: grafana-server.service: Failed with result 'exit-code'.
```

## Solution

### Fix 1: Safely Handle Existing Datasource Configs

**File**: `observability-stack/deploy/lib/config.sh`

Before creating our datasource configuration, BACKUP (don't delete) existing files:

```bash
# Handle existing datasource configurations to prevent conflicts
local ds_dir="/etc/grafana/provisioning/datasources"
local our_config="$ds_dir/datasources.yaml"

# If our config doesn't exist yet (first install)
if [[ ! -f "$our_config" ]]; then
    log_info "First-time datasource configuration..."

    # Backup any existing files (may be from Grafana apt package or previous manual config)
    local backup_count=0
    for file in "$ds_dir"/*.yaml "$ds_dir"/*.yml; do
        [[ -f "$file" ]] || continue
        local backup="${file}.bak.$(date +%Y%m%d_%H%M%S)"
        log_info "Backing up existing config: $(basename "$file") -> $(basename "$backup")"
        mv "$file" "$backup"
        backup_count=$((backup_count + 1))
    done

    if [[ $backup_count -gt 0 ]]; then
        log_info "Backed up $backup_count existing datasource config(s)"
    fi
else
    log_info "Updating existing datasource configuration..."
fi
```

**Benefits**:
- Preserves user customizations (moved to .bak files)
- Safe for re-installation / updates
- Timestamped backups for recovery
- Only our `datasources.yaml` is updated on re-runs

### Fix 2: Use Standard Filename

Changed from `observability.yaml` to `datasources.yaml` (standard Grafana naming):

```bash
# Create our datasource configuration
cat > /etc/grafana/provisioning/datasources/datasources.yaml << EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true      # Only ONE datasource has this
    editable: false

  - name: Loki
    type: loki
    access: proxy
    url: http://localhost:3100
    editable: false
    # No isDefault: true

  - name: Tempo
    type: tempo
    access: proxy
    url: http://localhost:3200
    uid: tempo
    editable: false
    # No isDefault: true
EOF
```

### Fix 3: Validate Configuration

Added validation to catch this error before Grafana starts:

```bash
# Validate datasource configuration
local default_count
default_count=$(grep -c "isDefault: true" /etc/grafana/provisioning/datasources/*.yaml 2>/dev/null || echo "0")
if [[ $default_count -gt 1 ]]; then
    log_error "Multiple datasources marked as default (found $default_count)"
    log_error "This will prevent Grafana from starting"
    return 1
elif [[ $default_count -eq 0 ]]; then
    log_warn "No default datasource configured"
else
    log_info "Datasource configuration validated (1 default datasource)"
fi
```

**Benefits**:
- Catches configuration errors before Grafana crashes
- Clear error messages for debugging
- Prevents silent failures

## Immediate Fix for Existing Installations

If you encounter this issue on an already-deployed server:

```bash
# SSH to the affected server

# Remove conflicting datasource files
sudo rm -f /etc/grafana/provisioning/datasources/observability.yaml

# Keep only datasources.yaml (or recreate it if needed)
# Ensure only ONE datasource has isDefault: true

# Restart Grafana
sudo systemctl restart grafana-server

# Verify it started
sudo systemctl status grafana-server

# Check logs if it still fails
sudo journalctl -u grafana-server -n 50 --no-pager
```

## Prevention in Deployment Script

The updated deployment script now:

1. **Removes all existing datasource configs** before creating ours
2. **Uses standard filename** (`datasources.yaml`)
3. **Validates configuration** before proceeding
4. **Logs clearly** what it's doing

### Updated Workflow

```
generate_grafana_config():
  ├─ Set admin password in grafana.ini
  ├─ Configure domain/URL in grafana.ini
  ├─ Create provisioning directory
  ├─ Remove existing datasources/*.yaml   ← NEW
  ├─ Create fresh datasources.yaml        ← RENAMED
  ├─ Create dashboard provisioning
  ├─ Copy dashboard JSON files
  ├─ Set ownership to grafana:grafana
  ├─ Validate default datasource count    ← NEW
  └─ Success
```

## Testing

### Test Case 1: Fresh Installation

```bash
# Run deployment on clean system
sudo ./observability-stack/deploy/install.sh

# Expected: Grafana starts successfully
sudo systemctl status grafana-server  # Should show "active (running)"
curl -I https://your-domain.com/       # Should return HTTP 200
```

### Test Case 2: Reinstallation (Grafana Already Installed)

```bash
# Grafana apt package creates default datasources.yaml
# Re-run deployment
sudo ./observability-stack/deploy/install.sh

# Expected:
# - Old datasources.yaml removed
# - New datasources.yaml created
# - Grafana starts successfully
```

### Test Case 3: Validation Catches Error

```bash
# Manually create conflicting config
echo "isDefault: true" | sudo tee -a /etc/grafana/provisioning/datasources/test.yaml

# Run configuration
generate_grafana_config

# Expected: Error message and function returns 1
# [ERROR] Multiple datasources marked as default (found 2)
# [ERROR] This will prevent Grafana from starting
```

## Files Modified

**`observability-stack/deploy/lib/config.sh`**:
- Lines 271-275: Added cleanup of existing datasource configs
- Line 278: Changed filename from `observability.yaml` to `datasources.yaml`
- Lines 334-345: Added datasource validation

## Related Issues

This fix also prevents:
- Grafana crash loops during installation
- 502 Bad Gateway errors when accessing Grafana via HTTPS
- Mysterious "Start request repeated too quickly" systemd errors
- Silent failures where Grafana appears configured but won't start

## Verification Commands

After deployment, verify datasource configuration:

```bash
# Check datasource files exist
ls -la /etc/grafana/provisioning/datasources/

# Count default datasources (should be exactly 1)
grep -c "isDefault: true" /etc/grafana/provisioning/datasources/*.yaml

# View the datasource configuration
sudo cat /etc/grafana/provisioning/datasources/datasources.yaml

# Check Grafana is running
sudo systemctl status grafana-server

# Test web access
curl -I https://your-domain.com/
```

## Design Philosophy

The fix follows these principles:

1. **Idempotency**: Safe to run multiple times
2. **Transparency**: Clear logging of all actions
3. **Early Validation**: Catch errors before services fail
4. **Clean State**: Remove conflicts before creating new config
5. **User-Friendly**: No manual intervention required
