# CHOM Auto-Healing Deployment Orchestrator

Enhanced deployment script with automatic error recovery, retry logic, and minimal user input.

## Quick Start

### Basic Usage (Recommended)

```bash
# Deploy everything with auto-healing (no prompts)
./deploy-enhanced.sh all
```

That's it! The script will:
- ✓ Validate your environment
- ✓ Check SSH connectivity
- ✓ Auto-install missing dependencies
- ✓ Deploy to all VPS servers
- ✓ Auto-retry on failures
- ✓ Self-heal common errors

## Features

### Auto-Healing Capabilities

The script automatically handles and fixes:

| Issue | Auto-Recovery Action |
|-------|---------------------|
| **SSH Connection Failed** | Clear known_hosts, verify connectivity, retry with backoff |
| **Missing Dependencies** | Auto-install yq, jq, openssh-client |
| **Service Conflicts** | Stop conflicting services, clean up old installations |
| **Disk Space Low** | Clean apt cache, remove old logs, prune Docker containers |
| **Permission Errors** | Auto-fix file/directory permissions |
| **Network Timeouts** | Exponential backoff retry (2s → 4s → 8s → 16s → 32s) |

### Minimal User Input

**Non-interactive by default** - Just run and go!

```bash
# Zero prompts - just deploy
./deploy-enhanced.sh all

# Only observability stack
./deploy-enhanced.sh observability

# Only VPSManager
./deploy-enhanced.sh vpsmanager
```

### Safe and Idempotent

- **State tracking**: Automatically resumes from last successful step
- **Safe to re-run**: Won't duplicate or break existing deployments
- **Checkpoint recovery**: Failed deployment? Just re-run with `--resume`

```bash
# Resume from last successful checkpoint
./deploy-enhanced.sh --resume
```

## Usage Examples

### Validation

```bash
# Preview what will be deployed (dry-run)
./deploy-enhanced.sh --plan

# Run pre-flight checks only
./deploy-enhanced.sh --validate
```

### Interactive Mode

```bash
# Enable confirmations before each step
./deploy-enhanced.sh --interactive all
```

### Advanced Options

```bash
# Force deployment (skip validation)
./deploy-enhanced.sh --force all

# Verbose output with detailed logs
./deploy-enhanced.sh --verbose all

# Disable auto-retry (fail fast)
./deploy-enhanced.sh --no-retry all

# Custom retry attempts (1-10)
./deploy-enhanced.sh --max-retries 5 all

# Linear retry backoff instead of exponential
./deploy-enhanced.sh --retry-backoff linear all
```

### Troubleshooting

```bash
# Debug mode (verbose + debug logs)
./deploy-enhanced.sh --debug all

# Quiet mode (errors only)
./deploy-enhanced.sh --quiet all

# Disable auto-fix (manual error handling)
./deploy-enhanced.sh --no-auto-fix all
```

## Command Reference

### Targets

- `observability` - Deploy only Observability Stack (Prometheus, Grafana, Loki, etc.)
- `vpsmanager` - Deploy only VPSManager (Laravel, LEMP stack, exporters)
- `all` - Deploy both (default)

### Core Options

| Option | Description |
|--------|-------------|
| `-i, --interactive` | Enable interactive mode with confirmations |
| `--plan` | Dry-run mode (show plan without executing) |
| `--validate` | Run pre-flight checks only |
| `--force` | Skip validation and force deployment |
| `--resume` | Resume from last successful checkpoint |

### Auto-Healing Options

| Option | Default | Description |
|--------|---------|-------------|
| `--no-retry` | Enabled | Disable automatic retry (fail fast) |
| `--no-auto-fix` | Enabled | Disable automatic error fixing |
| `--max-retries N` | 3 | Set max retry attempts (1-10) |
| `--retry-backoff` | exponential | Retry strategy: exponential or linear |

### Output Options

| Option | Description |
|--------|-------------|
| `-v, --verbose` | Verbose output with detailed progress |
| `-q, --quiet` | Minimal output (errors only) |
| `--debug` | Enable debug logging |

## Deployment Flow

```
1. Parse & Validate Arguments
   ↓
2. Pre-flight Checks (with auto-healing)
   - Check local dependencies (auto-install if missing)
   - Validate inventory.yaml
   - Generate SSH keys if needed
   - Test SSH connectivity (auto-retry with backoff)
   - Validate remote VPS (Debian 13, disk space, RAM, network)
   ↓
3. Show Deployment Plan
   ↓
4. Execute Deployment (with auto-healing)
   - Deploy Observability Stack
     * Retry on failures (exponential backoff)
     * Auto-fix service conflicts
     * Health checks after each step
   - Deploy VPSManager
     * Retry on failures
     * Auto-fix disk space issues
     * Verify monitoring integration
   ↓
5. Show Deployment Summary
   - Access URLs
   - Next steps
```

## Auto-Healing Retry Logic

### Exponential Backoff (Default)

```
Attempt 1: Immediate
Attempt 2: Wait 2 seconds
Attempt 3: Wait 4 seconds
Attempt 4: Wait 8 seconds  (if max-retries > 3)
Attempt 5: Wait 16 seconds (if max-retries > 4)
```

### Linear Backoff

```
Attempt 1: Immediate
Attempt 2: Wait 2 seconds
Attempt 3: Wait 4 seconds
Attempt 4: Wait 6 seconds
Attempt 5: Wait 8 seconds
```

## Deployment State

State is tracked in `.deploy-state/deployment.state`:

```json
{
  "started_at": "2025-12-29T10:30:00Z",
  "status": "in_progress",
  "observability": {
    "status": "completed",
    "completed_at": "2025-12-29T10:35:00Z"
  },
  "vpsmanager": {
    "status": "in_progress",
    "updated_at": "2025-12-29T10:40:00Z"
  }
}
```

### State Management

```bash
# View current deployment state
cat .deploy-state/deployment.state | jq

# Resume interrupted deployment
./deploy-enhanced.sh --resume

# Reset state (start fresh)
rm -rf .deploy-state/
```

## Requirements

### Prerequisites

- **Control Machine**: Linux/macOS with bash, ssh, scp
- **Dependencies**: yq, jq (auto-installed if missing)
- **VPS Servers**: Vanilla Debian 13
- **Network**: Internet connectivity from all VPS servers

### Configuration

1. **Edit** `configs/inventory.yaml`:

```yaml
observability:
  ip: "192.168.1.100"
  ssh_user: "root"
  ssh_port: 22
  hostname: "monitoring.example.com"

vpsmanager:
  ip: "192.168.1.101"
  ssh_user: "root"
  ssh_port: 22
  hostname: "manager.example.com"
```

2. **SSH Keys** (auto-generated on first run):

```bash
# Script will generate keys/chom_deploy_key
# You'll need to add the public key to VPS servers:
cat keys/chom_deploy_key.pub

# Add to ~/.ssh/authorized_keys on each VPS
```

## Comparison: deploy.sh vs deploy-enhanced.sh

| Feature | deploy.sh | deploy-enhanced.sh |
|---------|-----------|-------------------|
| Auto-retry | ❌ No | ✅ Yes (exponential backoff) |
| Auto-fix errors | ❌ No | ✅ Yes (missing deps, SSH, services) |
| User input | 🟨 Some | ✅ Minimal (non-interactive by default) |
| State tracking | ❌ No | ✅ Yes (resume from checkpoint) |
| Progress indicators | 🟨 Basic | ✅ Detailed with status |
| Dry-run mode | ✅ Yes | ✅ Yes (--plan) |
| Pre-flight checks | 🟨 Basic | ✅ Comprehensive with auto-heal |
| Error messages | 🟨 Basic | ✅ Detailed with recovery suggestions |
| Dependency auto-install | ❌ No | ✅ Yes |
| Verbose/Debug modes | ❌ No | ✅ Yes |
| Idempotent | 🟨 Partial | ✅ Yes (safe to re-run) |

## Troubleshooting

### Common Issues

**SSH Connection Failed**
```bash
# Auto-recovery attempts:
# 1. Clear known_hosts
# 2. Verify host reachable (ping)
# 3. Check SSH port open
# 4. Retry with exponential backoff

# Manual verification:
ping <vps-ip>
ssh -p <port> <user>@<ip>
```

**Missing Dependencies**
```bash
# Auto-installed automatically
# Manual installation if needed:
sudo apt-get install -y jq
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq
```

**Disk Space Low**
```bash
# Auto-cleanup runs automatically:
# - Cleans apt cache
# - Removes old logs (7+ days)
# - Prunes Docker containers

# Manual cleanup:
sudo apt-get clean
sudo journalctl --vacuum-time=7d
sudo docker system prune -af
```

**Service Conflicts**
```bash
# Auto-fix stops conflicting services
# Manual resolution:
sudo systemctl stop <service>
sudo systemctl disable <service>
```

### Debug Mode

Enable detailed logging:

```bash
./deploy-enhanced.sh --debug all
```

Shows:
- Retry attempts with delays
- Auto-fix operations
- SSH command execution
- Remote command output
- State transitions

## Migration from deploy.sh

Simply use the new script - it's fully backward compatible:

```bash
# Old way (still works)
./deploy.sh all

# New way (recommended)
./deploy-enhanced.sh all
```

## Support

### Get Help

```bash
./deploy-enhanced.sh --help
```

### View Version

```bash
./deploy-enhanced.sh --version
```

## License

Same as CHOM project
