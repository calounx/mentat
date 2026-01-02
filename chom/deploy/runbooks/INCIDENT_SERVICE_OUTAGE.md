# Incident Runbook: Complete Service Outage

**Severity:** SEV1 (Critical)
**Impact:** Complete application unavailability
**Expected Resolution Time:** 15-60 minutes

## Detection
- Alert: `ApplicationDown`
- All health checks failing
- Website returns 502/503/504
- No response from application

## Quick Triage (2 minutes)
```bash
# 1. Verify outage from multiple locations
curl -I https://landsraad.arewel.com
# From external monitoring: https://downforeveryoneorjustme.com/landsraad.arewel.com

# 2. Check server accessibility
ping 51.77.150.96
ssh deploy@landsraad.arewel.com "echo 'Server reachable'"

# 3. If SSH works, check all services
ssh deploy@landsraad.arewel.com << 'EOF'
docker ps -a
systemctl status docker
df -h
free -h
uptime
EOF
```

## Determine Root Cause

### Scenario Matrix
| Symptom | Likely Cause | Go To |
|---------|-------------|-------|
| Server not pingable | Network/VPS down | A |
| SSH fails | Server crashed | B |
| Docker down | Docker daemon crashed | C |
| Containers stopped | Deployment issue | D |
| Containers running but 502 | Nginx/PHP-FPM issue | E |
| High load | Resource exhaustion | F |

---

## Resolution Procedures

### A: Network/VPS Down
```bash
# 1. Check OVH status
# Visit: https://status.ovh.com/

# 2. Access OVH Manager
# URL: https://www.ovh.com/manager/
# Check server status, console access

# 3. If hardware failure
# - Open emergency ticket with OVH
# - Prepare for VPS restoration
# - Follow: ../disaster-recovery/RECOVERY_RUNBOOK.md

# 4. If network issue
# - Check OVH routing
# - Verify DNS resolution
# - Contact OVH support: +33 9 72 10 10 07
```

### B: Server Crashed
```bash
# 1. Access via OVH KVM console

# 2. Check boot logs
dmesg | tail -50
journalctl -xb | tail -100

# 3. If kernel panic or filesystem corruption
# - Boot into rescue mode
# - Run fsck
# - Restore from backup if needed

# 4. Normal boot failed
systemctl status
systemctl list-units --failed

# 5. Restart critical services
systemctl restart docker
systemctl restart networking
```

### C: Docker Daemon Crashed
```bash
# 1. Check Docker status
ssh deploy@landsraad.arewel.com << 'EOF'
systemctl status docker
journalctl -u docker --since "10 minutes ago"
EOF

# 2. Restart Docker
ssh deploy@landsraad.arewel.com << 'EOF'
systemctl restart docker
systemctl status docker
EOF

# 3. Bring up application
ssh deploy@landsraad.arewel.com << 'EOF'
cd /opt/chom
docker compose -f docker-compose.production.yml up -d
EOF

# 4. Verify
sleep 30
curl -I https://landsraad.arewel.com
```

### D: Containers Stopped (Deployment Issue)
```bash
# 1. Check why containers stopped
ssh deploy@landsraad.arewel.com << 'EOF'
docker ps -a
docker logs chom-app --tail 100
docker logs chom-nginx --tail 100
EOF

# 2. Restart containers
ssh deploy@landsraad.arewel.com << 'EOF'
cd /opt/chom
docker compose -f docker-compose.production.yml up -d
EOF

# 3. If startup fails, check for:
# - Configuration errors in .env
# - Missing environment variables
# - Port conflicts
# - Volume mount issues

# 4. If recent deployment, ROLLBACK
# Follow: ROLLBACK_PROCEDURES.md
```

### E: Nginx/PHP-FPM Issues (502 Bad Gateway)
```bash
# 1. Check Nginx can reach PHP-FPM
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-nginx ping chom-app
docker logs chom-nginx --tail 50 | grep "upstream"
EOF

# 2. Restart PHP-FPM
ssh deploy@landsraad.arewel.com << 'EOF'
docker compose -f /opt/chom/docker-compose.production.yml restart app
EOF

# 3. Restart Nginx
ssh deploy@landsraad.arewel.com << 'EOF'
docker compose -f /opt/chom/docker-compose.production.yml restart nginx
EOF

# 4. Test
curl -I https://landsraad.arewel.com
```

### F: Resource Exhaustion
```bash
# Follow: INCIDENT_HIGH_RESOURCES.md
```

---

## Emergency Recovery (Last Resort)

### Complete Stack Restart
```bash
# ⚠️  WARNING: This will cause 2-3 minutes downtime

ssh deploy@landsraad.arewel.com << 'EOF'
cd /opt/chom

# Stop all
docker compose -f docker-compose.production.yml down

# Clean up
docker system prune -f

# Start all
docker compose -f docker-compose.production.yml up -d

# Watch logs
docker compose -f docker-compose.production.yml logs -f
EOF

# Verify
sleep 60
curl -I https://landsraad.arewel.com
```

### Nuclear Option: Restore from Backup
```bash
# Only if all else fails and corruption suspected

# 1. Document current state
ssh deploy@landsraad.arewel.com << 'EOF'
cd /opt/chom
docker compose -f docker-compose.production.yml logs > /tmp/failure-logs-$(date +%Y%m%d-%H%M%S).txt
docker ps -a > /tmp/container-state.txt
EOF

# 2. Restore
ssh deploy@landsraad.arewel.com << 'EOF'
cd /opt/backups/chom
./restore-chom.sh --full --latest
EOF

# 3. Start services
ssh deploy@landsraad.arewel.com << 'EOF'
cd /opt/chom
docker compose -f docker-compose.production.yml up -d
EOF
```

---

## Verification

```bash
# 1. Health checks
curl -s https://landsraad.arewel.com/health/ready | jq '.'
curl -s https://landsraad.arewel.com/health/live | jq '.'
curl -s https://landsraad.arewel.com/health/dependencies | jq '.'

# 2. All containers running
ssh deploy@landsraad.arewel.com "docker ps"
# Expected: All containers "Up" status

# 3. No errors in logs
ssh deploy@landsraad.arewel.com << 'EOF'
docker compose -f /opt/chom/docker-compose.production.yml logs --tail 100 | grep -i error
EOF

# 4. Application functional
curl -s https://landsraad.arewel.com | grep -q "<title>" && echo "OK"

# 5. Database connectivity
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-mysql mysqladmin ping
EOF

# 6. Monitor for 15 minutes
watch -n 60 'curl -s https://landsraad.arewel.com/health/ready | jq ".status"'
```

---

## Post-Incident

### Immediate Actions
1. Update #incidents Slack channel
2. Document exact timeline
3. Capture all relevant logs
4. Notify stakeholders

### Root Cause Analysis
```bash
# Gather evidence
ssh deploy@landsraad.arewel.com << 'EOF'
# System logs at time of incident
journalctl --since "1 hour ago" --until "now" > /tmp/system-logs.txt

# Docker logs
docker compose -f /opt/chom/docker-compose.production.yml logs --since 1h > /tmp/docker-logs.txt

# Resource usage history (if monitoring available)
# Check Grafana dashboards for the time period
EOF

# Analyze
# - What triggered the outage?
# - Could it have been prevented?
# - Was detection fast enough?
# - Was resolution efficient?
```

### Follow-up Actions
- [ ] Update monitoring to detect this failure mode
- [ ] Add automation to recover automatically if possible
- [ ] Schedule post-mortem meeting
- [ ] Update runbooks with any new findings
- [ ] Implement preventive measures

---

## Escalation

**Level 1 (0-10 min):** On-call engineer attempts quick recovery

**Level 2 (10-20 min):** DevOps lead if no progress

**Level 3 (20-30 min):** Engineering manager if extended outage

**Level 4 (30+ min):** CTO if major incident

---

**Version:** 1.0 | **Updated:** 2026-01-02
