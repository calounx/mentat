# Incident Runbook: Disk Space Exhaustion

**Severity:** SEV1 (Critical)
**Impact:** Application failure, data loss risk
**Expected Resolution Time:** 10-20 minutes

## Detection
- Alert: `DiskSpaceLow` (< 20% free)
- Alert: `DiskSpaceCritical` (< 10% free)
- Errors: "No space left on device"
- Database write failures

## Quick Triage
```bash
# Check disk usage
ssh deploy@landsraad.arewel.com "df -h"
ssh deploy@landsraad.arewel.com "du -sh /var/lib/docker/* | sort -h | tail -10"
ssh deploy@landsraad.arewel.com "du -sh /opt/chom/* | sort -h | tail -10"
```

## Resolution

### Emergency Cleanup (< 5 minutes)
```bash
# 1. Clear Docker system
ssh deploy@landsraad.arewel.com "docker system prune -af --volumes"

# 2. Clear old logs
ssh deploy@landsraad.arewel.com << 'EOF'
journalctl --vacuum-time=3d
find /opt/chom/storage/logs -name "*.log" -mtime +7 -delete
truncate -s 0 /opt/chom/storage/logs/laravel.log
EOF

# 3. Clear old backups
ssh deploy@landsraad.arewel.com << 'EOF'
find /opt/backups/chom -name "*.tar.gz" -mtime +7 -delete
EOF

# 4. Restart services if they failed
ssh deploy@landsraad.arewel.com "docker compose -f /opt/chom/docker-compose.production.yml restart"
```

### Verify Recovery
```bash
ssh deploy@landsraad.arewel.com "df -h"
# Expected: > 20% free space
curl -s https://landsraad.arewel.com/health/ready | jq '.'
```

## Prevention
- Automated log rotation: daily
- Backup cleanup: weekly
- Docker prune: weekly
- Monitoring: < 80% threshold alert

---

**Version:** 1.0 | **Updated:** 2026-01-02
