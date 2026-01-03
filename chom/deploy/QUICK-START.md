# CHOM Deployment Tools - Quick Start Guide

## Pre-Deployment (Before deploying)

```bash
# Run all pre-deployment checks
./deploy/validation/pre-deployment-check.sh

# If any check fails, fix the issue before proceeding
```

---

## During Deployment

```bash
# In a separate terminal, monitor deployment status
./deploy/monitoring/deployment-status.sh --watch
```

---

## Post-Deployment (After deploying)

```bash
# 1. Run comprehensive post-deployment validation
./deploy/validation/post-deployment-check.sh

# 2. Run quick smoke tests (under 60 seconds)
./deploy/validation/smoke-tests.sh

# 3. Verify performance hasn't degraded
./deploy/validation/performance-check.sh

# 4. Check security configuration
./deploy/validation/security-check.sh

# 5. Verify observability stack
./deploy/validation/observability-check.sh
```

---

## If Something Goes Wrong

```bash
# 1. Capture emergency diagnostics (under 30 seconds)
./deploy/troubleshooting/emergency-diagnostics.sh

# 2. Analyze recent logs
./deploy/troubleshooting/analyze-logs.sh --minutes 30

# 3. Test all connections
./deploy/troubleshooting/test-connections.sh

# 4. Check resource usage
./deploy/monitoring/resource-monitor.sh

# 5. Review deployment history
./deploy/monitoring/deployment-history.sh

# 6. Test rollback capability
./deploy/validation/rollback-test.sh
```

---

## Daily Monitoring

```bash
# View service status
./deploy/monitoring/service-status.sh

# Monitor resources
./deploy/monitoring/resource-monitor.sh

# Check deployment status
./deploy/monitoring/deployment-status.sh
```

---

## Complete Deployment Workflow

```bash
#!/bin/bash
set -e

echo "=== CHOM Deployment ==="

# 1. Pre-deployment validation
echo "[1/6] Pre-deployment checks..."
./deploy/validation/pre-deployment-check.sh || exit 1

# 2. Deploy application
echo "[2/6] Deploying application..."
# YOUR DEPLOYMENT COMMANDS HERE

# 3. Post-deployment validation
echo "[3/6] Post-deployment checks..."
./deploy/validation/post-deployment-check.sh || exit 1

# 4. Smoke tests
echo "[4/6] Running smoke tests..."
./deploy/validation/smoke-tests.sh || exit 1

# 5. Performance validation
echo "[5/6] Checking performance..."
./deploy/validation/performance-check.sh

# 6. Security validation
echo "[6/6] Security validation..."
./deploy/validation/security-check.sh

echo "✓ Deployment complete and validated!"
```

---

## Command Reference

### Validation
| Script | Purpose | Time |
|--------|---------|------|
| `pre-deployment-check.sh` | Check prerequisites before deploying | 30s |
| `post-deployment-check.sh` | Validate deployment success | 45s |
| `smoke-tests.sh` | Quick critical path tests | <60s |
| `performance-check.sh` | Performance validation | 60s |
| `security-check.sh` | Security configuration check | 30s |
| `observability-check.sh` | Monitoring stack validation | 45s |
| `migration-check.sh` | Database migration validation | 30s |
| `rollback-test.sh` | Test rollback capability | 20s |

### Monitoring
| Script | Purpose | Mode |
|--------|---------|------|
| `deployment-status.sh` | Real-time deployment dashboard | Live/Snapshot |
| `service-status.sh` | All service statuses | Live/Snapshot |
| `resource-monitor.sh` | Server resource usage | Snapshot |
| `deployment-history.sh` | Deployment history | Snapshot |

### Troubleshooting
| Script | Purpose | Time |
|--------|---------|------|
| `analyze-logs.sh` | Analyze logs for errors | 15s |
| `test-connections.sh` | Test all connections | 30s |
| `emergency-diagnostics.sh` | Capture full diagnostics | <30s |

---

## Common Options

All validation scripts support:
- `--json` - JSON output for automation
- `--quiet` - Suppress progress output

Monitoring scripts support:
- `--watch` - Auto-refresh mode

Analysis scripts support:
- `--minutes N` - Time window for analysis

---

## Exit Codes

- **0** - Success, all checks passed
- **1** - Failure, one or more checks failed

Use in scripts:
```bash
if ./deploy/validation/pre-deployment-check.sh; then
    echo "Safe to deploy"
else
    echo "Fix issues before deploying"
    exit 1
fi
```

---

## Environment Variables

Override defaults:
```bash
export DEPLOY_USER="your_user"
export APP_SERVER="your.server.com"
export MONITORING_SERVER="monitoring.server.com"
```

---

## Getting Help

```bash
# Most scripts support --help
./deploy/validation/pre-deployment-check.sh --help
```

---

## Integration with CI/CD

### GitHub Actions
```yaml
- name: Pre-Deployment Validation
  run: ./deploy/validation/pre-deployment-check.sh

- name: Post-Deployment Validation
  run: ./deploy/validation/post-deployment-check.sh
```

### GitLab CI
```yaml
validate:
  script:
    - ./deploy/validation/pre-deployment-check.sh
```

---

## Tips

1. **Run pre-deployment check every time** - catches issues early
2. **Use --watch during deployment** - see issues as they happen
3. **Save performance baselines** - detect degradation over time
4. **Keep diagnostics tarballs** - helpful for post-incident analysis
5. **Test rollback regularly** - ensure you can recover
6. **Monitor resource usage** - prevent capacity issues
7. **Review deployment history** - track deployment frequency

---

## Example: Full Production Deployment

```bash
# Terminal 1: Run deployment
./deploy/validation/pre-deployment-check.sh && \
./deploy/production/deploy.sh && \
./deploy/validation/post-deployment-check.sh && \
./deploy/validation/smoke-tests.sh

# Terminal 2: Monitor in real-time
./deploy/monitoring/deployment-status.sh --watch

# Terminal 3: Watch logs
./deploy/troubleshooting/analyze-logs.sh --minutes 5

# After deployment completes
./deploy/validation/performance-check.sh --save-baseline
./deploy/validation/security-check.sh
```

---

## Troubleshooting Scenarios

### Scenario 1: High Memory Usage
```bash
./deploy/monitoring/resource-monitor.sh
./deploy/troubleshooting/analyze-logs.sh --minutes 30
# Review top memory processes
```

### Scenario 2: 5xx Errors
```bash
./deploy/troubleshooting/emergency-diagnostics.sh
./deploy/troubleshooting/analyze-logs.sh --minutes 15
./deploy/validation/post-deployment-check.sh
```

### Scenario 3: Slow Response Times
```bash
./deploy/validation/performance-check.sh
./deploy/troubleshooting/analyze-logs.sh --minutes 60
# Check for N+1 queries and slow database queries
```

### Scenario 4: Deployment Failed
```bash
./deploy/troubleshooting/emergency-diagnostics.sh
./deploy/monitoring/deployment-history.sh
./deploy/validation/rollback-test.sh
# Consider rollback if critical
```

---

## Production Checklist

Before every deployment:
- [ ] Pre-deployment check passes
- [ ] Database backup recent (<24h)
- [ ] Previous release available for rollback
- [ ] Monitoring dashboard accessible
- [ ] No active incidents

After every deployment:
- [ ] Post-deployment check passes
- [ ] Smoke tests pass
- [ ] Performance acceptable
- [ ] No new errors in logs
- [ ] Monitoring shows healthy metrics
- [ ] Save performance baseline

---

**Need more details? See [DEPLOYMENT-TOOLS-README.md](DEPLOYMENT-TOOLS-README.md)**
