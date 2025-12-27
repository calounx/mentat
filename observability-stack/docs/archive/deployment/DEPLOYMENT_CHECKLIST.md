# Production Deployment Checklist

**Version:** 3.0.0
**Last Updated:** 2025-12-27

This checklist ensures safe and reliable deployments of the observability stack to production environments.

---

## Pre-Deployment Phase

### T-7 Days: Planning

- [ ] **Review Release Notes**
  - Read RELEASE_NOTES.md for version being deployed
  - Identify breaking changes
  - Review new features and bug fixes
  - Check dependencies and version requirements

- [ ] **Schedule Maintenance Window**
  - Coordinate with stakeholders
  - Select low-traffic time window
  - Duration: 30-60 minutes recommended
  - Create calendar event with:
    - Start/end times
    - Rollback deadline
    - On-call personnel

- [ ] **Notify Stakeholders**
  ```
  Subject: [MAINTENANCE] Observability Stack Upgrade - [DATE]

  We will be upgrading the observability stack on [DATE] at [TIME] [TIMEZONE].

  Expected downtime: Up to 30 minutes
  Impact: Monitoring dashboards may be briefly unavailable
  Monitoring data: Will continue to be collected during upgrade

  Rollback plan: Available if issues occur
  Contact: [ON-CALL PERSON] at [PHONE/EMAIL]
  ```

- [ ] **Prepare Rollback Plan**
  - Document current version
  - Identify rollback trigger criteria
  - Assign rollback decision maker
  - Test rollback procedure on staging

### T-3 Days: Testing

- [ ] **Staging Environment Validation**
  - Deploy to staging environment
  - Run full test suite: `make test-all`
  - Verify health checks pass: `./scripts/health-check.sh`
  - Test monitoring functionality
  - Verify alert delivery
  - Performance test if load changes expected

- [ ] **Security Scan**
  - Run ShellCheck: `./tests/test-shellcheck.sh`
  - Check for hardcoded secrets
  - Review firewall rules
  - Verify SSL certificate configuration
  - Run security test suite: `make test-security`

- [ ] **Configuration Review**
  - Validate global.yaml: `./scripts/validate-config.sh`
  - Review monitored hosts list
  - Verify SMTP settings
  - Check retention policies
  - Confirm passwords are in secrets/ directory
  - No placeholder values in config

### T-1 Day: Final Preparation

- [ ] **Backup Current State**
  - Verify backup system is working
  - Test backup restoration procedure
  - Document current version/commit
  - Backup database (if applicable)
  - Export Grafana dashboards:
    ```bash
    curl -u admin:PASSWORD http://localhost:3000/api/dashboards/export > dashboards-backup.json
    ```

- [ ] **Verify Prerequisites**
  - Run preflight checks: `./scripts/preflight-check.sh --observability-vps`
  - Ensure sufficient disk space (20GB+ free)
  - Verify SSL certificates not expiring within 30 days
  - Check system resources (CPU, memory)
  - Confirm internet connectivity

- [ ] **Prepare Communication Channels**
  - Set up incident channel (Slack/Teams)
  - Verify on-call contact information
  - Prepare status page update templates
  - Test emergency notification system

---

## Deployment Phase

### T-0: Go/No-Go Decision

**Deployment Lead:** [NAME]
**Date/Time:** [YYYY-MM-DD HH:MM]

#### Go/No-Go Checklist
- [ ] All pre-deployment tasks complete
- [ ] Staging deployment successful
- [ ] No P0/P1 incidents in last 24h
- [ ] On-call team available
- [ ] Backup verified and tested
- [ ] Rollback plan documented
- [ ] Stakeholders notified

**Decision:** [ ] GO / [ ] NO-GO

**Signature:** _________________ **Time:** _______

### Deployment Execution (30-60 minutes)

#### Step 1: Pre-Deployment Verification (5 min)
```bash
# Connect to observability VPS
ssh root@observability-vps.example.com
cd /opt/observability-stack

# Verify current version
git describe --tags

# Run pre-flight checks
./scripts/preflight-check.sh --observability-vps

# Check current service status
./scripts/health-check.sh
```

- [ ] Services currently running healthy
- [ ] No active alerts firing
- [ ] Disk space sufficient (20GB+)
- [ ] Current version documented: `______________`

#### Step 2: Create Backup (5 min)
```bash
# Create timestamped backup
BACKUP_TIME=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/var/backups/observability-stack/manual-$BACKUP_TIME"
mkdir -p "$BACKUP_DIR"

# Backup configurations
cp -r /etc/prometheus "$BACKUP_DIR/"
cp -r /etc/grafana "$BACKUP_DIR/"
cp -r /etc/loki "$BACKUP_DIR/"
cp -r /etc/alertmanager "$BACKUP_DIR/"
cp -r /etc/nginx/sites-available/observability "$BACKUP_DIR/"

# Backup current git commit
git rev-parse HEAD > "$BACKUP_DIR/git-commit.txt"

# Verify backup
ls -lh "$BACKUP_DIR"
```

- [ ] Backup created successfully
- [ ] Backup location documented: `______________`
- [ ] Backup size reasonable: `_______ MB`

#### Step 3: Update Code (2 min)
```bash
# Fetch latest changes
git fetch --all --tags

# Checkout target version
git checkout v3.0.0  # Replace with actual version

# Verify version
git describe --tags
```

- [ ] Code updated to version: `______________`
- [ ] No local modifications (git status clean)

#### Step 4: Validate Configuration (3 min)
```bash
# Validate configuration file
./scripts/validate-config.sh

# Check for configuration changes
git diff v2.x.x v3.0.0 config/global.yaml.example
```

- [ ] Configuration valid
- [ ] Breaking changes reviewed
- [ ] Secrets properly configured
- [ ] No placeholder values present

#### Step 5: Run Deployment (15-30 min)
```bash
# Execute deployment
./scripts/setup-observability.sh 2>&1 | tee /var/log/observability-deploy-$BACKUP_TIME.log

# Monitor deployment logs in real-time
# Watch for errors or warnings
```

- [ ] Deployment started at: `_______ (time)`
- [ ] No errors during execution
- [ ] All services installed successfully
- [ ] SSL certificate renewed/valid
- [ ] Deployment completed at: `_______ (time)`
- [ ] Total duration: `_______ minutes`

#### Step 6: Service Verification (5 min)
```bash
# Wait for services to stabilize
sleep 30

# Check systemd services
systemctl status prometheus
systemctl status grafana-server
systemctl status loki
systemctl status alertmanager
systemctl status nginx

# Run health check
./scripts/health-check.sh
```

- [ ] Prometheus: Active and running
- [ ] Grafana: Active and running
- [ ] Loki: Active and running
- [ ] Alertmanager: Active and running
- [ ] Nginx: Active and running
- [ ] All health checks passing

#### Step 7: Functional Testing (5-10 min)
```bash
# Test Prometheus
curl -s http://localhost:9090/-/ready

# Test Grafana
curl -s http://localhost:3000/api/health

# Test Loki
curl -s http://localhost:3100/ready

# Test Alertmanager
curl -s http://localhost:9093/-/healthy
```

External access tests:
```bash
# From your workstation
DOMAIN="monitoring.example.com"  # Replace with actual domain

# Test Grafana access
curl -I https://$DOMAIN/

# Test Prometheus (with auth)
curl -u prometheus:PASSWORD -I https://$DOMAIN/prometheus/

# Test Loki (with auth)
curl -u loki:PASSWORD -I https://$DOMAIN/loki/
```

- [ ] All internal endpoints responding
- [ ] Grafana accessible externally
- [ ] Prometheus accessible with auth
- [ ] Loki accessible with auth
- [ ] SSL certificate valid
- [ ] No browser security warnings

#### Step 8: Data Validation (5 min)
- [ ] **Prometheus Targets**
  - Navigate to https://[domain]/prometheus/targets
  - All targets showing "UP" status
  - No stale metrics (check Last Scrape column)
  - Expected number of targets: `_______`

- [ ] **Grafana Dashboards**
  - Login to Grafana
  - Open system dashboard
  - Verify metrics displaying
  - Check for data gaps
  - All panels loading successfully

- [ ] **Loki Logs**
  - Navigate to Grafana > Explore
  - Select Loki data source
  - Query recent logs: `{job="syslog"}`
  - Verify logs are recent (within last 5 min)

- [ ] **Alertmanager**
  - Navigate to https://[domain]/alertmanager/
  - No unexpected alerts firing
  - Alert routing working
  - Email configuration valid

#### Step 9: Send Test Alert (3 min)
```bash
# Trigger test alert via Alertmanager
curl -X POST http://localhost:9093/api/v1/alerts -d '[
  {
    "labels": {
      "alertname": "DeploymentTest",
      "severity": "info",
      "instance": "test"
    },
    "annotations": {
      "summary": "Deployment test alert",
      "description": "This is a test alert sent after deployment"
    }
  }
]'
```

- [ ] Test alert sent successfully
- [ ] Email received within 2 minutes
- [ ] Alert visible in Grafana
- [ ] Alert routing correct

---

## Post-Deployment Phase

### Immediate Post-Deployment (15 min)

- [ ] **Update Status Page**
  - Mark maintenance window as complete
  - Update system status to operational
  - Post deployment summary

- [ ] **Monitor for Issues**
  - Watch metrics for anomalies (15 min)
  - Check error logs:
    ```bash
    journalctl -u prometheus -n 100 --no-pager
    journalctl -u grafana-server -n 100 --no-pager
    journalctl -u loki -n 100 --no-pager
    ```
  - Monitor Grafana for alerts
  - Verify no new critical alerts

- [ ] **Document Deployment**
  - Record actual deployment time
  - Note any issues encountered
  - Document version deployed
  - Save deployment logs
  - Update deployment history

- [ ] **Notify Stakeholders**
  ```
  Subject: [COMPLETE] Observability Stack Upgrade Successful

  The observability stack upgrade has been completed successfully.

  Deployed version: v3.0.0
  Deployment time: [START] - [END] ([DURATION] minutes)
  Status: All systems operational

  New features: [LIST]
  Changes: See RELEASE_NOTES.md

  No action required. Monitoring dashboards are fully operational.
  ```

### T+1 Hour: Short-term Monitoring

- [ ] Review metrics for past hour
- [ ] Check for any degraded performance
- [ ] Verify log ingestion rates normal
- [ ] Confirm alert delivery working
- [ ] No unexpected resource usage spikes

### T+24 Hours: Follow-up

- [ ] **Verify Stability**
  - Run health check: `./scripts/health-check.sh`
  - Review 24h metrics in Grafana
  - Check for any anomalies
  - Verify all monitored hosts reporting

- [ ] **Review Deployment**
  - Any issues encountered?
  - Deployment time as expected?
  - Any unexpected behavior?
  - User feedback received?

- [ ] **Update Documentation**
  - Update README if needed
  - Document any lessons learned
  - Update runbooks if procedures changed
  - Add to deployment history

- [ ] **Cleanup**
  - Review and cleanup old backups (keep last 5)
  - Archive deployment logs
  - Close deployment ticket
  - Update change management records

---

## Rollback Procedures

### Rollback Triggers

Execute rollback immediately if:
- [ ] Service fails to start after 3 restart attempts
- [ ] Critical alerts firing (P0/P1)
- [ ] Grafana unreachable for > 5 minutes
- [ ] Data loss detected
- [ ] SSL certificate issues preventing access
- [ ] Security vulnerability introduced
- [ ] More than 50% of monitored hosts failing

### Rollback Decision

**Time:** _______ **Decision Maker:** _____________

**Rollback Approved:** [ ] YES / [ ] NO

**Reason:** _________________________________________________

### Rollback Execution (15-20 min)

#### Method 1: Automated Rollback (Recommended)
```bash
cd /opt/observability-stack

# Find latest pre-deployment backup
LATEST_BACKUP=$(ls -t /var/backups/observability-stack/manual-* | head -1)
echo "Rollback target: $LATEST_BACKUP"

# Get previous version
PREV_VERSION=$(cat "$LATEST_BACKUP/git-commit.txt")

# Uninstall current version (keeps data)
./scripts/setup-observability.sh --uninstall

# Restore previous version
git checkout "$PREV_VERSION"

# Restore configurations
cp -r "$LATEST_BACKUP/prometheus" /etc/
cp -r "$LATEST_BACKUP/grafana" /etc/
cp -r "$LATEST_BACKUP/loki" /etc/
cp -r "$LATEST_BACKUP/alertmanager" /etc/
cp "$LATEST_BACKUP/observability" /etc/nginx/sites-available/

# Reinstall
./scripts/setup-observability.sh

# Verify
./scripts/health-check.sh
```

#### Method 2: Manual Rollback
```bash
# Stop services
systemctl stop prometheus grafana-server loki alertmanager

# Restore from backup
BACKUP_DIR="[path-to-backup]"
rsync -av "$BACKUP_DIR/prometheus/" /etc/prometheus/
rsync -av "$BACKUP_DIR/grafana/" /etc/grafana/
rsync -av "$BACKUP_DIR/loki/" /etc/loki/
rsync -av "$BACKUP_DIR/alertmanager/" /etc/alertmanager/

# Reload systemd
systemctl daemon-reload

# Start services
systemctl start prometheus grafana-server loki alertmanager

# Verify
systemctl status prometheus grafana-server loki alertmanager
```

#### Rollback Verification Checklist
- [ ] All services running
- [ ] Health checks passing
- [ ] Grafana accessible
- [ ] Metrics displaying
- [ ] Logs ingesting
- [ ] No critical alerts
- [ ] Rollback time: `_______ minutes`

#### Post-Rollback Actions
- [ ] Notify stakeholders of rollback
- [ ] Document rollback reason
- [ ] Create incident report
- [ ] Schedule post-mortem meeting
- [ ] Plan fix for next deployment

---

## Deployment History

| Date | Version | Duration | Deployed By | Status | Notes |
|------|---------|----------|-------------|--------|-------|
| 2025-12-27 | v3.0.0 | - | - | PENDING | Modular architecture release |
| | | | | | |
| | | | | | |

---

## Emergency Contacts

| Role | Name | Phone | Email | Backup |
|------|------|-------|-------|--------|
| Deployment Lead | | | | |
| System Administrator | | | | |
| Security Team | | | | |
| On-Call Engineer | | | | |
| Management Escalation | | | | |

---

## Rollback Decision Matrix

| Issue | Severity | Action | Timeline |
|-------|----------|--------|----------|
| Service won't start | P0 | Immediate rollback | < 5 min |
| Critical alerts firing | P0 | Investigate 10 min, then rollback | < 15 min |
| Data loss detected | P0 | Immediate rollback | < 5 min |
| Grafana unreachable | P1 | Investigate 5 min, then rollback | < 10 min |
| Performance degradation | P2 | Investigate 30 min | < 45 min |
| Non-critical bugs | P3 | Document for next release | N/A |

---

## Common Issues and Resolutions

### Issue: Service fails to start
**Symptoms:** systemctl status shows failed
**Resolution:**
```bash
# Check logs
journalctl -u [service] -n 50

# Common causes:
# - Port already in use: netstat -tulpn | grep [port]
# - Config error: Check syntax in /etc/[service]/
# - Permissions: chown [user]:[group] /etc/[service]/
```

### Issue: SSL certificate errors
**Symptoms:** Browser shows "Not Secure"
**Resolution:**
```bash
# Renew certificate
certbot renew --force-renewal -d [domain]

# Restart nginx
systemctl restart nginx
```

### Issue: Prometheus targets down
**Symptoms:** Targets showing as "DOWN" in Prometheus UI
**Resolution:**
```bash
# Check connectivity
telnet [host] [port]

# Check firewall
ufw status

# Verify exporter running on target
ssh [host] 'systemctl status node_exporter'
```

### Issue: No metrics in Grafana
**Symptoms:** Empty graphs, "No data"
**Resolution:**
```bash
# Check Prometheus data source
curl http://localhost:9090/api/v1/query?query=up

# Verify time range in Grafana
# Check Prometheus retention settings
```

---

## Post-Mortem Template

**Incident:** Deployment Issue - [Date]
**Severity:** [P0/P1/P2/P3]
**Duration:** [Start] - [End] ([Duration])

**Timeline:**
- [HH:MM] Deployment started
- [HH:MM] Issue detected
- [HH:MM] Incident declared
- [HH:MM] Rollback initiated
- [HH:MM] Services restored

**Root Cause:**
[Detailed explanation of what went wrong]

**Impact:**
- Systems affected:
- Users impacted:
- Data loss: Yes/No
- Downtime: [duration]

**Resolution:**
[What was done to fix the issue]

**Lessons Learned:**
1. What went well:
2. What could be improved:
3. Action items:

**Action Items:**
- [ ] [Action 1] - Assigned to: [Name] - Due: [Date]
- [ ] [Action 2] - Assigned to: [Name] - Due: [Date]

---

**Checklist Version:** 1.0
**Document Owner:** DevOps Team
**Review Frequency:** After each deployment
**Next Review:** After v3.0.1 deployment
