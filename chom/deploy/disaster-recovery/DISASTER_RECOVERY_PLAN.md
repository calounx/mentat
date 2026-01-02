# CHOM Disaster Recovery Plan (DRP)

**Document Version:** 1.0
**Last Updated:** 2026-01-02
**Owner:** DevOps Team
**Review Cycle:** Quarterly

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Infrastructure Overview](#infrastructure-overview)
3. [Recovery Objectives](#recovery-objectives)
4. [Disaster Scenarios](#disaster-scenarios)
5. [Recovery Procedures](#recovery-procedures)
6. [Escalation Paths](#escalation-paths)
7. [Testing Schedule](#testing-schedule)
8. [Contact Information](#contact-information)

---

## Executive Summary

This Disaster Recovery Plan (DRP) defines procedures for recovering the CHOM production environment from various failure scenarios. The plan ensures business continuity and minimal data loss through automated backups, documented procedures, and tested recovery workflows.

### Critical Success Factors

- **Automated Backups:** Hourly incremental, daily full backups
- **Off-site Storage:** Backups stored on separate VPS and OVH Object Storage
- **Regular Testing:** Monthly backup restoration tests
- **Documentation:** Comprehensive runbooks for all scenarios
- **Monitoring:** Real-time alerting for backup failures

---

## Infrastructure Overview

### Production Environment

#### Observability VPS (mentat)
- **IP:** 51.254.139.78
- **Provider:** OVH
- **OS:** Debian 13
- **Services:**
  - Prometheus (metrics storage)
  - Loki (log aggregation)
  - Tempo (distributed tracing)
  - Grafana (visualization)
  - Alertmanager (alerting)
  - Alloy (telemetry collection)

#### Application VPS (landsraad)
- **IP:** 51.77.150.96
- **Provider:** OVH
- **OS:** Debian 13
- **Services:**
  - CHOM Application (Laravel/PHP-FPM)
  - Nginx (web server)
  - MariaDB 10.11 (database)
  - Redis 7 (cache/queue)
  - Grafana Alloy (local telemetry)

### Network Architecture

```
Internet
    |
    +-- mentat (51.254.139.78)
    |     |
    |     +-- Prometheus :9090
    |     +-- Grafana :3000
    |     +-- Loki :3100
    |     +-- Tempo :3200
    |
    +-- landsraad (51.77.150.96)
          |
          +-- HTTPS :443 (CHOM Application)
          +-- MariaDB :3306 (internal)
          +-- Redis :6379 (internal)
          +-- Exporters (metrics)
```

### Data Classification

| Data Type | Criticality | RPO | RTO | Backup Frequency |
|-----------|-------------|-----|-----|------------------|
| Database (MariaDB) | CRITICAL | 15 min | 30 min | Hourly incremental |
| Application Files | HIGH | 1 hour | 1 hour | Daily full |
| Configuration | HIGH | 1 hour | 1 hour | Daily full |
| SSL Certificates | HIGH | 24 hours | 2 hours | Daily |
| Logs (Loki) | MEDIUM | 4 hours | 4 hours | 6-hourly |
| Metrics (Prometheus) | LOW | 24 hours | 8 hours | Daily |
| Traces (Tempo) | LOW | 24 hours | N/A | Weekly |

---

## Recovery Objectives

### Recovery Time Objective (RTO)

Maximum acceptable time to restore service after an incident.

| Scenario | RTO Target | RTO Maximum |
|----------|------------|-------------|
| Database corruption | 30 minutes | 1 hour |
| Application container failure | 5 minutes | 15 minutes |
| Complete VPS failure (landsraad) | 2 hours | 4 hours |
| Complete VPS failure (mentat) | 4 hours | 8 hours |
| Network connectivity loss | 15 minutes | 30 minutes |
| Security breach | 1 hour | 4 hours |
| Data center outage | 8 hours | 24 hours |

### Recovery Point Objective (RPO)

Maximum acceptable data loss measured in time.

| Data Type | RPO Target | RPO Maximum |
|-----------|------------|-------------|
| Database transactions | 15 minutes | 1 hour |
| User uploads | 1 hour | 4 hours |
| Configuration changes | 1 hour | 24 hours |
| Application logs | 4 hours | 24 hours |
| Metrics data | 24 hours | 72 hours |

---

## Disaster Scenarios

### Scenario 1: Database Corruption

**Impact:** Application unavailable, data may be corrupted
**Likelihood:** Low
**Detection:** Health checks fail, application errors, Prometheus alerts

**Indicators:**
- MariaDB crashes or refuses connections
- Data integrity check failures
- Corruption error messages in logs
- Application 500 errors

**Immediate Actions:**
1. Stop application containers to prevent further writes
2. Assess corruption extent using `mysqlcheck`
3. Determine if repair possible or restoration required
4. Execute database restoration procedure

**Recovery Path:** See [Database Recovery](#database-recovery-procedure)

---

### Scenario 2: Application Corruption

**Impact:** Application unavailable or malfunctioning
**Likelihood:** Medium
**Detection:** Health checks fail, deployment errors, code integrity alerts

**Indicators:**
- PHP fatal errors
- Missing or corrupted application files
- Permission issues
- Container fails to start

**Immediate Actions:**
1. Verify corruption scope (code vs. storage)
2. Check Docker volume integrity
3. Determine if rollback or restore required
4. Execute application restoration

**Recovery Path:** See [Application Recovery](#application-recovery-procedure)

---

### Scenario 3: Complete VPS Failure (landsraad)

**Impact:** Complete application outage
**Likelihood:** Low
**Detection:** Server unreachable, all health checks fail

**Indicators:**
- SSH connection timeout
- HTTPS endpoints unresponsive
- Grafana shows all metrics down
- OVH control panel shows server offline

**Immediate Actions:**
1. Check OVH status dashboard
2. Attempt server restart via OVH console
3. If hardware failure, provision new VPS
4. Execute full VPS restoration

**Recovery Path:** See [VPS Restoration - landsraad](#vps-restoration-landsraad)

---

### Scenario 4: Complete VPS Failure (mentat)

**Impact:** Loss of monitoring, logs, and metrics
**Likelihood:** Low
**Detection:** Grafana unreachable, metrics collection stops

**Indicators:**
- Grafana dashboard inaccessible
- Prometheus unreachable
- Alloy cannot send data
- OVH shows server offline

**Immediate Actions:**
1. Application continues running (monitored systems unaffected)
2. Check OVH status dashboard
3. Provision new VPS if needed
4. Restore observability stack

**Recovery Path:** See [VPS Restoration - mentat](#vps-restoration-mentat)

---

### Scenario 5: Network Connectivity Loss

**Impact:** Intermittent service disruption
**Likelihood:** Medium
**Detection:** Increased latency, timeout errors, connectivity alerts

**Indicators:**
- HTTP 502/504 errors
- DNS resolution failures
- Packet loss in monitoring
- OVH network status warnings

**Immediate Actions:**
1. Verify issue is network (not application)
2. Check OVH network status
3. Test connectivity from multiple sources
4. Contact OVH support if provider issue

**Recovery Path:** See [Network Recovery](#network-recovery-procedure)

---

### Scenario 6: Security Breach

**Impact:** Potential data compromise, service disruption
**Likelihood:** Low-Medium
**Detection:** IDS alerts, unusual activity, failed login attempts

**Indicators:**
- Suspicious authentication attempts
- Unexpected file modifications
- Unusual network traffic patterns
- Malware detection alerts

**Immediate Actions:**
1. Isolate affected systems
2. Preserve evidence (logs, file states)
3. Assess breach scope
4. Execute incident response plan
5. Restore from clean backup

**Recovery Path:** See [Security Incident Response](#security-incident-response)

---

### Scenario 7: Data Center Outage

**Impact:** Complete infrastructure unavailable
**Likelihood:** Very Low
**Detection:** All services unreachable, OVH status page confirms

**Indicators:**
- All OVH services in region offline
- OVH status page shows outage
- Multiple customer reports
- No response from any service

**Immediate Actions:**
1. Confirm outage via OVH status page
2. Activate disaster recovery site (if available)
3. Wait for OVH restoration
4. Verify data integrity post-restoration

**Recovery Path:** See [Data Center Failover](#data-center-failover)

---

### Scenario 8: Accidental Data Deletion

**Impact:** Data loss, potential service disruption
**Likelihood:** Medium
**Detection:** User reports, missing data, application errors

**Indicators:**
- Database records missing
- File deletion logs
- User-reported data loss
- Incomplete query results

**Immediate Actions:**
1. Stop all write operations
2. Identify deletion scope and time
3. Locate nearest backup before deletion
4. Execute point-in-time recovery

**Recovery Path:** See [Point-in-Time Recovery](#point-in-time-recovery)

---

## Recovery Procedures

### Database Recovery Procedure

**RTO:** 30 minutes
**RPO:** 15 minutes (from last incremental backup)

#### Prerequisites
- Access to backup storage
- Database credentials
- Application stopped or in maintenance mode

#### Procedure

```bash
# 1. Stop application to prevent writes
cd /opt/chom/deploy/disaster-recovery/scripts
./health-check.sh --mode pre-recovery

# 2. Stop application containers
ssh deploy@51.77.150.96
cd /opt/chom
docker compose -f docker-compose.production.yml stop app queue scheduler

# 3. Backup current corrupted database (for forensics)
docker exec chom-mysql mysqldump --all-databases > /tmp/corrupted-$(date +%Y%m%d-%H%M%S).sql

# 4. Restore database from latest backup
cd /opt/backups/chom
./restore-chom.sh --component database --latest

# 5. Verify database integrity
docker exec chom-mysql mysqlcheck --all-databases --check --auto-repair

# 6. Restart application
docker compose -f docker-compose.production.yml start app queue scheduler

# 7. Verify functionality
cd /opt/chom/deploy/disaster-recovery/scripts
./health-check.sh --mode post-recovery

# 8. Monitor for 1 hour
watch -n 60 './health-check.sh --mode monitoring'
```

#### Validation Steps
1. Database connection successful
2. Application loads without errors
3. Recent data visible (check latest transactions)
4. No corruption errors in logs
5. Metrics show normal operation

#### Rollback Plan
If restoration fails:
1. Restore from previous backup (older)
2. Accept larger RPO
3. Consider manual data reconstruction

---

### Application Recovery Procedure

**RTO:** 1 hour
**RPO:** 1 hour (from last full backup)

#### Procedure

```bash
# 1. Stop affected containers
ssh deploy@51.77.150.96
cd /opt/chom
docker compose -f docker-compose.production.yml stop app nginx queue scheduler

# 2. Backup current state for analysis
tar czf /tmp/chom-corrupted-$(date +%Y%m%d-%H%M%S).tar.gz /opt/chom

# 3. Restore application files
cd /opt/backups/chom
./restore-chom.sh --component application --latest

# 4. Restore configuration files
./restore-chom.sh --component config --latest

# 5. Set correct permissions
chown -R deploy:deploy /opt/chom
chmod -R 755 /opt/chom
chmod -R 775 /opt/chom/storage /opt/chom/bootstrap/cache

# 6. Rebuild containers if needed
cd /opt/chom
docker compose -f docker-compose.production.yml build --no-cache

# 7. Start services
docker compose -f docker-compose.production.yml up -d

# 8. Verify health
./deploy/disaster-recovery/scripts/health-check.sh --mode post-recovery
```

---

### VPS Restoration - landsraad

**RTO:** 4 hours
**RPO:** 1 hour

#### Procedure

```bash
# 1. Provision new VPS at OVH
# - OS: Debian 13
# - RAM: 4GB minimum
# - Storage: 40GB SSD minimum
# - Network: Public IP assigned

# 2. Initial server setup
ssh root@NEW_IP_ADDRESS

# Update system
apt update && apt upgrade -y

# Create deploy user
useradd -m -s /bin/bash -G sudo deploy
mkdir -p /home/deploy/.ssh
# Copy SSH keys from backup

# 3. Install Docker
curl -fsSL https://get.docker.com | sh
usermod -aG docker deploy

# 4. Install required packages
apt install -y git curl wget vim htop ncdu net-tools

# 5. Restore CHOM application
su - deploy
cd /opt
git clone https://github.com/your-org/chom.git
cd chom

# 6. Restore from backup
# Download latest backup from OVH Object Storage or mentat
scp deploy@51.254.139.78:/backups/landsraad/latest/* /tmp/

# 7. Run full restoration
cd /opt/chom/deploy/disaster-recovery/scripts
./restore-chom.sh --full --source /tmp/backup-latest.tar.gz

# 8. Update DNS (if IP changed)
# Point chom.yourdomain.com to NEW_IP_ADDRESS

# 9. Configure SSL
./deploy/scripts/setup-ssl.sh

# 10. Start services
docker compose -f docker-compose.production.yml up -d

# 11. Comprehensive health check
./deploy/disaster-recovery/scripts/health-check.sh --mode full

# 12. Update monitoring
# Update landsraad IP in mentat Prometheus targets
```

#### Post-Restoration Verification
- [ ] Application accessible via HTTPS
- [ ] Database contains recent data
- [ ] User authentication working
- [ ] Metrics flowing to Prometheus
- [ ] Logs flowing to Loki
- [ ] SSL certificate valid
- [ ] All background jobs running

---

### VPS Restoration - mentat

**RTO:** 8 hours (monitoring only, app continues running)
**RPO:** 24 hours (metrics data)

#### Procedure

```bash
# 1. Provision new VPS
# OS: Debian 13, 2GB RAM, 20GB SSD

# 2. Install base system
ssh root@NEW_IP_ADDRESS
apt update && apt upgrade -y
apt install -y docker.io docker-compose git

# 3. Clone observability stack
cd /opt
git clone https://github.com/your-org/observability-stack.git
cd observability-stack

# 4. Restore configuration
scp deploy@BACKUP_SOURCE:/backups/mentat/config/* ./

# 5. Restore data volumes
# Download backup archives
./deploy/disaster-recovery/scripts/restore-observability.sh --full

# 6. Start services
./deploy/install.sh --role observability --restore-mode

# 7. Update data sources
# Point all Alloy instances to new mentat IP

# 8. Verify data ingestion
# Check Grafana dashboards for incoming metrics/logs
```

---

### Network Recovery Procedure

**RTO:** 30 minutes

#### Diagnostic Steps

```bash
# 1. Test connectivity from external source
ping 51.77.150.96
curl https://chom.yourdomain.com

# 2. Test from server
ssh deploy@51.77.150.96
ping 8.8.8.8
ping google.com
curl https://api.github.com

# 3. Check DNS resolution
dig chom.yourdomain.com
nslookup chom.yourdomain.com

# 4. Check firewall rules
iptables -L -n -v
ufw status verbose

# 5. Check Docker networking
docker network ls
docker network inspect chom-network

# 6. Check service status
docker ps -a
systemctl status docker
```

#### Resolution Steps

**If DNS Issue:**
```bash
# Update DNS records
# Verify propagation: https://www.whatsmydns.net/
```

**If Firewall Issue:**
```bash
# Allow required ports
ufw allow 80/tcp
ufw allow 443/tcp
ufw reload
```

**If Docker Network Issue:**
```bash
# Restart Docker
systemctl restart docker

# Recreate network if corrupted
docker network rm chom-network
docker network create chom-network

# Restart containers
docker compose -f docker-compose.production.yml down
docker compose -f docker-compose.production.yml up -d
```

---

### Security Incident Response

**RTO:** 4 hours (includes forensics)
**RPO:** Accept data loss to last clean backup

#### Phase 1: Containment (First 15 minutes)

```bash
# 1. Isolate affected system
# Block at firewall if possible
ufw deny in from any

# 2. Preserve evidence
tar czf /forensics/system-$(date +%Y%m%d-%H%M%S).tar.gz \
  /var/log \
  /opt/chom/storage/logs \
  /home/deploy/.bash_history

# 3. Snapshot current state
docker exec chom-mysql mysqldump --all-databases > /forensics/db-snapshot.sql
docker compose -f docker-compose.production.yml logs > /forensics/docker-logs.txt

# 4. Stop all services
docker compose -f docker-compose.production.yml down
```

#### Phase 2: Investigation (Next 1 hour)

```bash
# 1. Analyze logs for breach indicators
grep -r "suspicious_pattern" /var/log
grep -r "unauthorized" /opt/chom/storage/logs

# 2. Check for unauthorized changes
find /opt/chom -type f -mtime -1 -ls

# 3. Check for new users/keys
cat /etc/passwd
cat /home/deploy/.ssh/authorized_keys

# 4. Check network connections
netstat -tupln
lsof -i

# 5. Check running processes
ps auxf
docker ps -a
```

#### Phase 3: Eradication (Next 1 hour)

```bash
# 1. Identify breach timeline
# Find last known clean backup

# 2. Restore from clean backup
./restore-chom.sh --timestamp 20260101-120000

# 3. Apply security patches
apt update && apt upgrade -y
docker pull <all_images>

# 4. Rotate all credentials
# - Database passwords
# - Application keys
# - SSH keys
# - API tokens
```

#### Phase 4: Recovery (Next 1 hour)

```bash
# 1. Harden security
# Update firewall rules
# Enable fail2ban
# Update SSH config

# 2. Verify system clean
./health-check.sh --mode security

# 3. Restore service
docker compose -f docker-compose.production.yml up -d

# 4. Monitor closely
watch -n 10 'docker compose logs --tail=50'
```

#### Phase 5: Lessons Learned (Within 24 hours)

- Document breach timeline
- Update security procedures
- Implement additional monitoring
- Schedule security review

---

### Data Center Failover

**RTO:** 24 hours (depends on OVH)
**RPO:** Last successful backup

#### Scenario A: OVH Announces Maintenance

```bash
# 1. Week before: Take additional backups
./backup-chom.sh --full --verify
./backup-observability.sh --full --verify

# 2. Day before: Download critical backups off-site
rsync -avz deploy@51.77.150.96:/backups/ ./local-backups/

# 3. During maintenance: Monitor OVH status
# Wait for restoration
```

#### Scenario B: Unexpected Outage

```bash
# 1. Confirm via OVH status page
# Check: https://status.ovh.com/

# 2. If prolonged (>4 hours), consider failover
# Provision new VPS in different region
# Restore from most recent backup

# 3. Update DNS to point to new region
# Accept data loss based on last backup

# 4. When primary restored, decide:
# - Keep new as primary
# - Failback to original
```

---

### Point-in-Time Recovery

**RTO:** 2 hours
**RPO:** Depends on backup frequency (15 min - 1 hour)

#### Procedure

```bash
# 1. Identify deletion timestamp
# Check application logs, audit trails

DELETION_TIME="2026-01-02 14:30:00"

# 2. Find backup immediately before deletion
ls -ltr /backups/chom/incremental/
# Select backup from 2026-01-02 14:15:00

# 3. Stop application
docker compose -f docker-compose.production.yml stop app

# 4. Restore to specific point
./restore-chom.sh --timestamp "2026-01-02 14:15:00" --point-in-time

# 5. Verify restored data present
docker exec chom-mysql mysql -e "SELECT * FROM deleted_table LIMIT 10;"

# 6. Export recovered data
docker exec chom-mysql mysqldump deleted_table > recovered-data.sql

# 7. Restore current backup
./restore-chom.sh --latest

# 8. Import recovered data
docker exec -i chom-mysql mysql < recovered-data.sql

# 9. Restart application
docker compose -f docker-compose.production.yml start app
```

---

## Escalation Paths

### Level 1: On-Call Engineer (0-15 minutes)

**Responsibilities:**
- Initial incident assessment
- Execute documented runbooks
- Attempt automated recovery

**Escalate if:**
- Issue not resolved in 15 minutes
- Runbook procedure fails
- Data loss suspected

**Contact:**
- Slack: #ops-oncall
- Phone: On-call rotation
- PagerDuty: Auto-page

---

### Level 2: Senior DevOps (15-30 minutes)

**Responsibilities:**
- Complex troubleshooting
- Manual intervention decisions
- Approve non-standard procedures

**Escalate if:**
- Issue not resolved in 30 minutes
- Requires infrastructure changes
- Data corruption confirmed

**Contact:**
- Slack: #ops-escalation
- Phone: Senior on-call
- Email: devops-lead@company.com

---

### Level 3: Engineering Manager (30+ minutes)

**Responsibilities:**
- Business impact decisions
- Customer communication
- Resource allocation

**Escalate if:**
- Extended outage (>1 hour)
- Data breach suspected
- Requires external support (OVH)

**Contact:**
- Phone: +33 X XX XX XX XX
- Email: engineering-manager@company.com

---

### Level 4: CTO/Executive (Critical)

**Responsibilities:**
- Executive decisions
- Public communication
- Vendor escalation

**Escalate if:**
- Major data loss
- Security breach confirmed
- Legal implications
- Media attention

**Contact:**
- Phone: +33 X XX XX XX XX (24/7)
- Email: cto@company.com

---

## Testing Schedule

### Monthly Tests (First Monday)

**Backup Verification Test**
- Duration: 30 minutes
- Procedure: Run `./test-backups.sh --monthly`
- Validation: All backups restorable
- Documentation: Update test log

### Quarterly Tests (First Monday of Quarter)

**Database Recovery Test**
- Duration: 2 hours
- Procedure: Full database restoration to test environment
- Validation: Data integrity verified
- Documentation: Update DRP if issues found

**Application Recovery Test**
- Duration: 2 hours
- Procedure: Full application restoration to test environment
- Documentation: Time actual RTO

### Semi-Annual Tests (January & July)

**Full VPS Recovery Test**
- Duration: 4 hours
- Procedure: Provision new test VPS, restore completely
- Validation: All services functional
- Documentation: Update procedures

**Disaster Scenario Simulation**
- Duration: 4 hours
- Procedure: Simulate major incident (table-top or live)
- Participants: Full DevOps team
- Documentation: Update runbooks

### Annual Tests (December)

**Full Disaster Recovery Exercise**
- Duration: 8 hours
- Procedure: End-to-end recovery from simulated data center failure
- Participants: All teams
- Validation: Meet all RTO/RPO targets
- Documentation: Comprehensive DRP review

---

## Test Log Template

```markdown
### Disaster Recovery Test - [DATE]

**Test Type:** [Monthly/Quarterly/Annual]
**Scenario:** [What was tested]
**Duration:** [Actual time taken]
**Success:** [Yes/No]

**Procedure Followed:**
- Step 1: [Completed/Failed]
- Step 2: [Completed/Failed]
- ...

**Issues Encountered:**
1. [Issue description]
2. [Issue description]

**RTO/RPO Achievement:**
- Target RTO: [X minutes]
- Actual RTO: [Y minutes]
- Target RPO: [X minutes]
- Actual RPO: [Y minutes]

**Action Items:**
- [ ] Update procedure documentation
- [ ] Fix automation script
- [ ] Schedule additional training

**Tested By:** [Name]
**Approved By:** [Name]
```

---

## Contact Information

### Internal Contacts

| Role | Name | Slack | Email | Phone |
|------|------|-------|-------|-------|
| On-Call Engineer | Rotation | #ops-oncall | oncall@company.com | PagerDuty |
| DevOps Lead | [Name] | @devops-lead | devops-lead@company.com | +33 X XX XX XX XX |
| Engineering Manager | [Name] | @eng-manager | eng-manager@company.com | +33 X XX XX XX XX |
| CTO | [Name] | @cto | cto@company.com | +33 X XX XX XX XX |

### External Contacts

| Provider | Purpose | Contact | SLA |
|----------|---------|---------|-----|
| OVH Support | Infrastructure | https://www.ovh.com/manager/ | 1 hour response |
| OVH Emergency | Critical outage | +33 9 72 10 10 07 | 24/7 |
| DNS Provider | DNS changes | support@dns-provider.com | 2 hours |
| SSL Provider | Certificate issues | support@ssl-provider.com | 4 hours |

---

## Document Control

### Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-02 | DevOps Team | Initial DRP creation |

### Review Schedule

- **Quarterly Review:** First week of Jan, Apr, Jul, Oct
- **Post-Incident Review:** Within 48 hours of any incident
- **Annual Audit:** December

### Approval

| Role | Name | Signature | Date |
|------|------|-----------|------|
| DevOps Lead | _________ | _________ | __/__/____ |
| Engineering Manager | _________ | _________ | __/__/____ |
| CTO | _________ | _________ | __/__/____ |

---

## Appendices

### Appendix A: Backup Locations

- **Primary:** `/backups/` on each VPS
- **Secondary:** Cross-VPS (landsraad <-> mentat)
- **Tertiary:** OVH Object Storage (planned)
- **Archive:** Monthly archives retained for 12 months

### Appendix B: Critical File Locations

**CHOM (landsraad):**
- Application: `/opt/chom`
- Database: Docker volume `mysql_data`
- Backups: `/backups/chom/`
- Logs: `/opt/chom/storage/logs`
- SSL: `/opt/chom/docker/production/ssl/`

**Observability (mentat):**
- Stack: `/opt/observability-stack`
- Prometheus: Docker volume `prometheus-data`
- Loki: Docker volume `loki-data`
- Grafana: Docker volume `grafana-data`
- Backups: `/backups/observability/`

### Appendix C: Quick Reference Commands

```bash
# Backup
./backup-chom.sh --full
./backup-observability.sh --full

# Restore
./restore-chom.sh --latest
./restore-observability.sh --latest

# Health Check
./health-check.sh --mode full

# Test Backups
./test-backups.sh --verify-all

# View Backup Status
./backup-chom.sh --status
```

---

**END OF DISASTER RECOVERY PLAN**
