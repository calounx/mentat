# Quick Start Guide - Observability Stack Upgrade

**Date:** 2025-12-27
**Status:** READY FOR DEPLOYMENT

## Pre-Validation Complete

All pre-upgrade validation checks have passed. The system is ready for the observability stack deployment.

## Important Note: Fresh Installation

This system has **no existing components installed**. While the upgrade orchestrator is designed for upgrades, it can also handle fresh installations with proper version management.

## Recommended Next Steps

### Option 1: Use Upgrade Orchestrator (Recommended)

The upgrade orchestrator provides automated installation with all safety features:

```bash
# 1. Preview what will be installed (dry-run)
cd /home/calounx/repositories/mentat/observability-stack
sudo ./scripts/upgrade-orchestrator.sh --phase 1 --dry-run

# 2. Install Phase 1 components (exporters)
sudo ./scripts/upgrade-orchestrator.sh --phase 1 --mode standard

# 3. Verify installation
sudo ./scripts/upgrade-orchestrator.sh --status

# 4. Check services
systemctl status node_exporter nginx_exporter mysqld_exporter

# 5. Test metrics endpoints
curl http://localhost:9100/metrics | head -20
```

### Option 2: Use Traditional Setup Scripts

If you prefer the traditional installation method:

```bash
# Run the observability setup script
sudo ./scripts/observability-upgrade.sh
```

## Phase Breakdown

### Phase 1: Low-Risk Exporters (5-10 minutes)
- node_exporter → 1.9.1
- nginx_exporter → 1.5.1
- mysqld_exporter → 0.18.0
- phpfpm_exporter → 2.3.0
- fail2ban_exporter → 0.5.0

**Command:**
```bash
sudo ./scripts/upgrade-orchestrator.sh --phase 1
```

### Phase 2: Prometheus (15-20 minutes)
- prometheus → 2.55.1 → 3.8.1 (two-stage)

**Command:**
```bash
sudo ./scripts/upgrade-orchestrator.sh --phase 2 --mode safe
```

### Phase 3: Logging Stack (10-15 minutes)
- loki → 3.6.3
- promtail → 3.6.3

**Command:**
```bash
sudo ./scripts/upgrade-orchestrator.sh --phase 3
```

## Validation Commands

### Before Starting
```bash
# Verify system readiness
sudo ./scripts/preflight-check.sh --observability-vps

# Check configuration
python3 -c "import yaml; yaml.safe_load(open('config/upgrade.yaml'))"

# Verify disk space
df -h /var/lib
```

### During Installation
```bash
# Monitor logs
journalctl -f

# Check upgrade status
sudo ./scripts/upgrade-orchestrator.sh --status

# Watch specific service
journalctl -f -u node_exporter
```

### After Installation
```bash
# Verify all services
for svc in node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter; do
    systemctl status $svc
done

# Test metrics endpoints
curl -s http://localhost:9100/metrics | grep "node_cpu_seconds_total"
curl -s http://localhost:9113/metrics | grep "nginx_up"
curl -s http://localhost:9104/metrics | grep "mysql_up"
```

## Rollback Procedure

If anything goes wrong:

```bash
# Automatic rollback (if health checks fail)
# The orchestrator will rollback automatically

# Manual rollback
sudo ./scripts/upgrade-orchestrator.sh --rollback

# Resume after fixing issues
sudo ./scripts/upgrade-orchestrator.sh --resume
```

## Key Features

1. **Idempotent**: Safe to run multiple times
2. **Crash Recovery**: Automatically resumes from last checkpoint
3. **Automatic Backups**: All components backed up before changes
4. **Health Checks**: Validates each component after upgrade
5. **Auto-Rollback**: Reverts on failure
6. **Version Management**: Dynamic version resolution from GitHub

## Configuration Files

All validated and ready:
- `config/upgrade.yaml` - Upgrade orchestration settings
- `config/versions.yaml` - Version management (9 components)
- `config/global.yaml` - Global observability settings
- `config/compatibility-matrix.yaml` - Component compatibility rules

## Backup Location

Pre-upgrade backup created at:
```
/var/lib/observability-upgrades/backups/pre-upgrade-20251227-151610/
```

## System Requirements (All Met)

- Disk Space: 54 GB available (20 GB required)
- Memory: 4096 MB (2048 MB required)
- Ports: All required ports available (9100, 9113, 9104, 9253, 9191, 9090, 3100, 9080, 3000)
- Network: GitHub and GitHub API accessible
- Dependencies: All required tools installed

## Monitoring

Open these URLs after installation:
- Node Exporter: http://localhost:9100/metrics
- Nginx Exporter: http://localhost:9113/metrics
- MySQL Exporter: http://localhost:9104/metrics
- PHP-FPM Exporter: http://localhost:9253/metrics
- Fail2ban Exporter: http://localhost:9191/metrics
- Prometheus: http://localhost:9090
- Loki: http://localhost:3100
- Grafana: http://localhost:3000

## Support Documentation

Detailed documentation available:
- Full validation report: `PRE_UPGRADE_VALIDATION_REPORT.md`
- Phase 1 execution plan: `docs/PHASE_1_EXECUTION_PLAN.md`
- Preflight checklist: `docs/PHASE_1_PREFLIGHT_CHECKLIST.md`
- Architecture review: `ARCHITECTURE_REVIEW.md`

## Troubleshooting

### If Installation Fails

1. Check logs:
   ```bash
   journalctl -xe
   sudo ./scripts/upgrade-orchestrator.sh --status
   ```

2. Verify connectivity:
   ```bash
   curl -I https://github.com
   curl -s https://api.github.com/zen
   ```

3. Check disk space:
   ```bash
   df -h /var/lib
   ```

4. Resume or rollback:
   ```bash
   sudo ./scripts/upgrade-orchestrator.sh --resume
   # or
   sudo ./scripts/upgrade-orchestrator.sh --rollback
   ```

### Common Issues

**GitHub API Rate Limit:**
```bash
export GITHUB_TOKEN="your_token_here"
```

**Port Already in Use:**
```bash
sudo ss -tulpn | grep :9100
```

**Service Won't Start:**
```bash
systemctl status node_exporter
journalctl -u node_exporter -n 50
```

## Getting Started Now

**Single command to start:**
```bash
cd /home/calounx/repositories/mentat/observability-stack && \
sudo ./scripts/upgrade-orchestrator.sh --phase 1 --dry-run
```

Review the dry-run output, then execute:
```bash
sudo ./scripts/upgrade-orchestrator.sh --phase 1
```

**That's it!** The orchestrator will handle everything automatically.

---

**Pre-Validation Status:** COMPLETE ✓
**System Status:** READY FOR DEPLOYMENT ✓
**Recommendation:** Proceed with Phase 1 installation
