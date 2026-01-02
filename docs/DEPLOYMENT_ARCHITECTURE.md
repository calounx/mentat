# CHOM Production Deployment Architecture

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Infrastructure Components](#infrastructure-components)
3. [Deployment Strategies](#deployment-strategies)
4. [CI/CD Pipeline](#cicd-pipeline)
5. [Monitoring & Observability](#monitoring--observability)
6. [Backup & Disaster Recovery](#backup--disaster-recovery)
7. [Security](#security)
8. [Runbooks & Procedures](#runbooks--procedures)

---

## Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Internet / Users                            │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                   DNS (arewel.com)                               │
│  - landsraad.arewel.com → 51.77.150.96 (Application)           │
│  - mentat.arewel.com → 51.254.139.78 (Observability)           │
└────────────┬──────────────────────────┬─────────────────────────┘
             │                          │
    ┌────────▼─────────┐       ┌────────▼──────────┐
    │  Application VPS │       │ Observability VPS │
    │ landsraad        │       │ mentat            │
    │ 51.77.150.96     │       │ 51.254.139.78     │
    └──────────────────┘       └───────────────────┘
```

### Deployment Architecture (Blue-Green)

```
┌─────────────────────────────────────────────────────────────────┐
│                      Load Balancer / Nginx                       │
└────────────────┬───────────────────────┬────────────────────────┘
                 │                       │
         ┌───────▼────────┐     ┌───────▼────────┐
         │  BLUE (Current)│     │ GREEN (New)    │
         │                │     │                │
         │  Release: v1.0 │     │  Release: v1.1 │
         │  Status: Live  │     │  Status: Staged│
         └────────────────┘     └────────────────┘
                 │                       │
         ┌───────▼────────────────────────▼────────┐
         │        Shared Resources                 │
         │  - Database (MySQL)                     │
         │  - Cache (Redis)                        │
         │  - Storage (Persistent Volumes)         │
         │  - Queue (Redis)                        │
         └─────────────────────────────────────────┘
```

### Canary Deployment Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                   Nginx (Weighted Routing)                       │
└─┬───────────────────────────────────────────────────────────────┘
  │
  ├─ 90% traffic ──► Stable Version (v1.0)
  │                  - PHP-FPM Pool: stable
  │                  - Proven release
  │
  └─ 10% traffic ──► Canary Version (v1.1)
                     - PHP-FPM Pool: canary
                     - New release under test
                     - Monitored for errors

     Gradual shift: 10% → 25% → 50% → 75% → 100%
     Each stage: 5 minutes monitoring
```

---

## Infrastructure Components

### Production VPS Servers

#### Application Server (landsraad.arewel.com)
- **IP:** 51.77.150.96
- **Location:** OVH RBX (Roubaix, France)
- **Specs:** VPS Value 1-2-40
  - CPU: 1 vCore
  - RAM: 2 GB
  - Disk: 40 GB SSD
- **OS:** Debian 13 (Trixie)

**Services:**
- Nginx 1.24+ (Web Server)
- PHP 8.2-FPM (Application Runtime)
- MySQL 8.0 / MariaDB 10.11 (Database)
- Redis 7+ (Cache & Queue)
- Supervisor (Process Manager)
- Node Exporter (Metrics)
- Nginx Exporter (Metrics)
- MySQL Exporter (Metrics)
- PHP-FPM Exporter (Metrics)
- Grafana Alloy (Logs/Traces)

**Directory Structure:**
```
/var/www/
├── chom/                    # Current symlink → chom_current
├── chom_current/            # Symlink to current release
├── releases/                # Release history
│   ├── 20260102_120000/    # Blue (current)
│   ├── 20260102_140000/    # Green (new)
│   └── 20260101_100000/    # Previous (rollback)
├── shared/                  # Shared resources
│   └── storage/            # Persistent storage
└── backups/                # Local backups

/var/backups/chom/
├── database/               # Database backups
├── files/                  # File backups
├── config/                 # Configuration backups
└── reports/                # Backup reports

/var/log/chom/
├── deployment_*.log        # Deployment logs
├── backup_*.log           # Backup logs
└── rollback_*.log         # Rollback logs
```

#### Observability Server (mentat.arewel.com)
- **IP:** 51.254.139.78
- **Location:** OVH RBX (Roubaix, France)
- **Specs:** VPS Value 1-2-40
- **OS:** Debian 13 (Trixie)

**Services:**
- Prometheus (Metrics Collection & Storage)
- Grafana (Visualization & Dashboards)
- Loki (Log Aggregation)
- Tempo (Distributed Tracing)
- Alertmanager (Alert Management)
- Node Exporter (System Metrics)
- Grafana Alloy (Metrics/Logs/Traces Collection)

**Data Retention:**
- Prometheus: 30 days local
- Loki Logs: 30 days local
- Tempo Traces: 7 days local
- Grafana Dashboards: Persistent

### Network Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                      Public Internet                          │
└────┬─────────────────────────────────────────┬───────────────┘
     │                                         │
     │ HTTPS (443)                            │ HTTPS (3000)
     │ HTTP (80 → 443)                        │
     │                                         │
┌────▼──────────────────────┐    ┌───────────▼──────────────┐
│  Application Server       │    │  Observability Server    │
│  landsraad.arewel.com     │◄───┤  mentat.arewel.com       │
│                           │    │                          │
│  Ports:                   │    │  Ports:                  │
│  - 80/443 (Web)          │    │  - 3000 (Grafana)        │
│  - 9100 (Node Exporter)  │───►│  - 9090 (Prometheus)     │
│  - 9113 (Nginx Exporter) │───►│  - 3100 (Loki)           │
│  - 9104 (MySQL Exporter) │───►│  - 3200 (Tempo)          │
│  - 9253 (PHP-FPM Exp)    │───►│  - 9093 (Alertmanager)   │
│  - 12345 (Alloy)         │───►│  - 12345 (Alloy)         │
└───────────────────────────┘    └──────────────────────────┘
```

### Backup Storage

**Primary Backup Locations:**
1. **Local (On-Server)**
   - Path: `/var/backups/chom/`
   - Retention: 7 days
   - Types: Database, Files, Config

2. **Offsite (S3-Compatible)**
   - Service: OVH Object Storage / AWS S3
   - Bucket: `chom-backups`
   - Region: EU-WEST-1 (or OVH GRA)
   - Retention: 90 days
   - Lifecycle: Transition to Glacier after 30 days

**Backup Schedule:**
```
Database:  Every 6 hours + pre-deployment
Files:     Daily at 02:00 UTC
Config:    After changes + daily at 03:00 UTC
```

---

## Deployment Strategies

### 1. Blue-Green Deployment (Default)

**Characteristics:**
- Zero downtime
- Instant rollback capability
- Full environment duplication
- Atomic switch

**Process:**
1. Deploy to GREEN environment
2. Run migrations on GREEN
3. Health check GREEN
4. Atomic symlink switch (BLUE → GREEN)
5. Reload services
6. Verify deployment
7. Keep BLUE for rollback

**Advantages:**
- Instant rollback (just switch symlink back)
- No user impact during deployment
- Full testing before traffic switch

**Disadvantages:**
- Requires double storage space
- Database migrations must be backward compatible

**Best For:**
- Production deployments
- Major version updates
- High-risk changes

**Script:** `/var/www/chom/scripts/deploy-blue-green.sh`

### 2. Canary Deployment

**Characteristics:**
- Gradual traffic shift
- Real user testing
- Risk mitigation
- Automated rollback on errors

**Process:**
1. Deploy canary version
2. Route 10% traffic to canary
3. Monitor for 5 minutes
4. If healthy, increase to 25%
5. Continue: 50% → 75% → 100%
6. Rollback if error rate > 5% or p95 latency > 2s

**Traffic Distribution:**
```
Stage 1:  10% canary,  90% stable   (5 min monitoring)
Stage 2:  25% canary,  75% stable   (5 min monitoring)
Stage 3:  50% canary,  50% stable   (5 min monitoring)
Stage 4:  75% canary,  25% stable   (5 min monitoring)
Stage 5: 100% canary,   0% stable   (finalized)
```

**Best For:**
- Feature releases
- Performance testing
- Gradual rollouts

**Script:** `/var/www/chom/scripts/deploy-canary.sh`

### 3. Rolling Deployment

**Characteristics:**
- Sequential update
- Minimal resource usage
- Suitable for single server

**Process:**
1. Enable maintenance mode
2. Pull latest code
3. Install dependencies
4. Run migrations
5. Clear caches
6. Reload services
7. Disable maintenance mode

**Best For:**
- Minor updates
- Hotfixes
- Development/Staging

**Script:** `/var/www/chom/scripts/deploy-production.sh`

---

## CI/CD Pipeline

### Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Developer Workflow                           │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
              ┌──────────────┐
              │ Git Push to  │
              │   main/tags  │
              └──────┬───────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│              GitHub Actions Pipeline                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Stage 1: BUILD & TEST                                          │
│  ├─ Setup PHP 8.2 + Node 20                                     │
│  ├─ Install dependencies (Composer + NPM)                       │
│  ├─ Run PHPUnit tests (parallel)                                │
│  ├─ Run PHPStan static analysis                                 │
│  ├─ Build frontend assets (Vite)                                │
│  └─ Create deployment artifact (.tar.gz)                        │
│                                                                  │
│  Stage 2: SECURITY SCAN                                         │
│  ├─ Trivy vulnerability scanner                                 │
│  ├─ Composer audit                                              │
│  ├─ NPM audit                                                   │
│  ├─ TruffleHog secrets detection                               │
│  └─ CodeQL SAST analysis                                        │
│                                                                  │
│  Stage 3: DEPLOYMENT (Blue-Green)                               │
│  ├─ Download artifact                                           │
│  ├─ SSH to production server                                    │
│  ├─ Extract to GREEN environment                                │
│  ├─ Run database migrations                                     │
│  ├─ Health check GREEN                                          │
│  ├─ Atomic switch BLUE → GREEN                                  │
│  ├─ Reload PHP-FPM + Nginx                                      │
│  ├─ Post-deployment health checks                               │
│  └─ Rollback on failure                                         │
│                                                                  │
│  Stage 4: SMOKE TESTS                                           │
│  ├─ Test homepage                                               │
│  ├─ Test health endpoints                                       │
│  ├─ Test API endpoints                                          │
│  ├─ Verify database connectivity                                │
│  └─ Check queue workers                                         │
│                                                                  │
│  Stage 5: OBSERVABILITY UPDATE                                  │
│  ├─ Add deployment annotation to Grafana                        │
│  ├─ Update Prometheus labels                                    │
│  └─ Send Slack notification                                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Pipeline Configuration

**File:** `.github/workflows/deploy-production.yml`

**Triggers:**
- Push to `main` branch
- Git tags matching `v*.*.*`
- Manual workflow dispatch

**Environments:**
- **Production:** Requires manual approval
- **Protected branches:** main
- **Required checks:** All tests must pass

**Secrets Required:**
```
PRODUCTION_SSH_KEY          # SSH private key for server access
PRODUCTION_HOST             # landsraad.arewel.com
PRODUCTION_USER             # ops
SSH_KNOWN_HOSTS             # Server fingerprints
SLACK_WEBHOOK_URL           # Slack notifications
GRAFANA_URL                 # https://mentat.arewel.com:3000
GRAFANA_API_KEY             # Grafana API token
PROMETHEUS_URL              # http://mentat.arewel.com:9090
```

### Deployment Flow

```
┌──────────────┐
│  Git Push    │
└──────┬───────┘
       │
       ▼
┌──────────────┐     Pass      ┌─────────────┐
│ Build & Test ├──────────────►│  Security   │
└──────┬───────┘                └──────┬──────┘
       │ Fail                          │ Pass
       ▼                               ▼
┌──────────────┐              ┌─────────────────┐
│   Notify     │              │ Deploy (Blue-   │
│   Team       │              │  Green)         │
└──────────────┘              └────────┬────────┘
                                       │
                              ┌────────▼────────┐
                              │  Health Checks  │
                              └────────┬────────┘
                                       │
                       ┌───────────────┴──────────────┐
                       │ Pass                         │ Fail
                       ▼                              ▼
              ┌─────────────────┐           ┌─────────────────┐
              │  Smoke Tests    │           │   Rollback      │
              └────────┬────────┘           └─────────────────┘
                       │ Pass
                       ▼
              ┌─────────────────┐
              │   Success!      │
              │   Notify Team   │
              └─────────────────┘
```

---

## Monitoring & Observability

### Metrics Collection

**Architecture:**
```
┌─────────────────────────────────────────────────────────────────┐
│                    Application Server                            │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │Node Exporter │  │Nginx Exporter│  │MySQL Exporter│         │
│  │  :9100       │  │  :9113       │  │  :9104       │         │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘         │
│         │                 │                  │                  │
│         └─────────────────┴──────────────────┤                  │
│                                              │                  │
│  ┌──────────────┐                           │                  │
│  │PHP-FPM Exp   │                           │                  │
│  │  :9253       │                           │                  │
│  └──────┬───────┘                           │                  │
│         │                                    │                  │
│         └────────────────────────────────────┤                  │
│                                              │                  │
│  ┌───────────────────────────────────────────▼─────┐           │
│  │          Grafana Alloy                          │           │
│  │  Collects & forwards metrics, logs, traces     │           │
│  └───────────────────────────┬─────────────────────┘           │
└────────────────────────────────│────────────────────────────────┘
                                 │
                                 │ Push to
                                 │
┌────────────────────────────────▼────────────────────────────────┐
│                 Observability Server                             │
│                                                                  │
│  ┌─────────────┐  ┌──────────┐  ┌───────┐  ┌──────────────┐   │
│  │ Prometheus  │  │   Loki   │  │ Tempo │  │ Alertmanager │   │
│  │   :9090     │  │  :3100   │  │ :3200 │  │    :9093     │   │
│  └──────┬──────┘  └─────┬────┘  └───┬───┘  └──────┬───────┘   │
│         │               │            │             │            │
│         └───────────────┴────────────┴─────────────┤            │
│                                                     │            │
│                                    ┌────────────────▼───────┐   │
│                                    │     Grafana            │   │
│                                    │  Dashboards & Alerts   │   │
│                                    │       :3000            │   │
│                                    └────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Key Metrics

**Application Metrics:**
- HTTP request rate (req/s)
- HTTP error rate (4xx, 5xx)
- Response time (p50, p95, p99)
- Active users
- Queue depth
- Cache hit rate

**Infrastructure Metrics:**
- CPU usage (%)
- Memory usage (%)
- Disk usage (%)
- Disk I/O (IOPS)
- Network throughput (MB/s)
- Process count

**Database Metrics:**
- Query rate (queries/s)
- Slow queries
- Connection pool usage
- Table locks
- Replication lag (if applicable)

**PHP-FPM Metrics:**
- Active processes
- Idle processes
- Queue length
- Max children reached

**Nginx Metrics:**
- Requests per second
- Active connections
- Waiting/Reading/Writing connections
- Response codes

### Dashboards

**Grafana Dashboards:**
1. **Application Overview**
   - Request rate, error rate, response time
   - Active users, sessions
   - Top endpoints by traffic

2. **Infrastructure Health**
   - CPU, memory, disk usage
   - Network I/O
   - System load

3. **Database Performance**
   - Query rate, slow queries
   - Connection pool
   - Table sizes

4. **Deployment Tracking**
   - Deployment timeline with annotations
   - Error rate before/after deployment
   - Response time trends

5. **Business Metrics**
   - User registrations
   - API usage
   - Feature adoption

### Alerting Rules

**Critical Alerts (PagerDuty):**
- Application down (HTTP 5xx > 50%)
- Database connection failure
- Disk usage > 95%
- Memory usage > 95%
- SSL certificate expiring in < 7 days

**Warning Alerts (Slack):**
- High error rate (HTTP 5xx > 5%)
- Slow response time (p95 > 2s)
- Disk usage > 85%
- Memory usage > 85%
- Queue depth > 1000

**Configuration:**
```yaml
# Prometheus Alert Rules
groups:
  - name: application
    interval: 30s
    rules:
      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate detected"
          description: "Error rate is {{ $value }}%"

      - alert: ApplicationDown
        expr: up{job="chom-app"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Application is down"
          description: "CHOM application is not responding"
```

---

## Backup & Disaster Recovery

### Backup Strategy

See detailed runbook: `/docs/DISASTER_RECOVERY_RUNBOOK.md`

**Automated Backups:**
```
Database:   Every 6 hours + pre-deployment
Files:      Daily at 02:00 UTC
Config:     After changes + daily
```

**Backup Script:** `/var/www/chom/scripts/backup-automated.sh`

**Cron Configuration:**
```bash
# Database backups every 6 hours
0 */6 * * * /var/www/chom/scripts/backup-automated.sh --type=database

# Full backup daily at 02:00 UTC
0 2 * * * /var/www/chom/scripts/backup-automated.sh --type=all

# Config backup after changes (manual trigger)
```

### Recovery Objectives

| Component | RTO | RPO |
|-----------|-----|-----|
| Database | 1 hour | 15 minutes |
| Application | 2 hours | 1 hour |
| Files | 2 hours | 24 hours |
| Observability | 4 hours | 24 hours |

---

## Security

### Security Layers

**1. Network Security**
- Firewall (UFW) configured
- Only required ports open: 80, 443, 9090, 3000
- SSH key-based authentication only
- Fail2ban for brute force protection

**2. Application Security**
- HTTPS enforced (Let's Encrypt)
- Security headers (HSTS, CSP, X-Frame-Options)
- Rate limiting on API endpoints
- CSRF protection
- XSS protection
- SQL injection prevention (Eloquent ORM)

**3. Data Security**
- Database backups encrypted at rest
- Environment files encrypted in backup
- Secrets stored in environment variables
- No secrets in version control

**4. CI/CD Security**
- Secrets stored in GitHub Secrets
- SSH key rotation every 90 days
- Automated vulnerability scanning
- Dependency audit in pipeline

**5. Access Control**
- Least privilege principle
- Separate deployment user (ops)
- Sudo access only when required
- SSH key rotation policy

### Security Scanning

**Automated Scans:**
- Composer audit (PHP dependencies)
- NPM audit (JavaScript dependencies)
- Trivy (Container/filesystem scan)
- CodeQL (Static analysis)
- TruffleHog (Secret detection)

**Schedule:**
- On every commit/PR
- Daily scheduled scan
- Weekly dependency update check

---

## Runbooks & Procedures

### Standard Operating Procedures

1. **Normal Deployment**
   - Trigger: Git push to main or tag
   - Script: CI/CD pipeline
   - Duration: 10-15 minutes
   - Rollback: Automatic on failure

2. **Hotfix Deployment**
   - Create hotfix branch
   - Test in staging
   - Deploy via pipeline
   - Tag release

3. **Rollback Procedure**
   - Script: `/var/www/chom/scripts/rollback.sh`
   - Duration: 5-10 minutes
   - Steps:
     ```bash
     ssh ops@landsraad.arewel.com
     cd /var/www/chom
     sudo -u www-data ./scripts/rollback.sh --steps=1
     ```

4. **Database Backup & Restore**
   - Backup: `/var/www/chom/scripts/backup-automated.sh --type=database`
   - Restore: See DR Runbook

5. **SSL Certificate Renewal**
   ```bash
   ssh ops@landsraad.arewel.com
   sudo certbot renew --force-renewal
   sudo systemctl reload nginx
   ```

6. **Scale Queue Workers**
   ```bash
   ssh ops@landsraad.arewel.com
   sudo vi /etc/supervisor/conf.d/chom-worker.conf
   # Update numprocs=10
   sudo supervisorctl reread
   sudo supervisorctl update
   ```

### Troubleshooting Guide

**Application Not Responding:**
1. Check service status: `systemctl status nginx php8.2-fpm`
2. Check logs: `tail -100 /var/www/chom/storage/logs/laravel.log`
3. Check disk space: `df -h`
4. Check processes: `ps aux | grep php`
5. Restart services: `systemctl restart php8.2-fpm nginx`

**Database Connection Issues:**
1. Check MySQL status: `systemctl status mysql`
2. Check connections: `mysql -e "SHOW PROCESSLIST;"`
3. Check error log: `tail -100 /var/log/mysql/error.log`
4. Restart MySQL: `systemctl restart mysql`

**High CPU Usage:**
1. Check top processes: `top -bn1 | head -20`
2. Check slow queries: `mysql -e "SHOW FULL PROCESSLIST;"`
3. Check queue depth: `php artisan queue:monitor`
4. Scale workers if needed

**Deployment Failed:**
1. Check deployment log: `tail -500 /var/log/chom/deployment_*.log`
2. Check health: `curl -f https://landsraad.arewel.com/health`
3. Rollback: `./scripts/rollback.sh --steps=1`
4. Investigate failure, fix, redeploy

---

## Maintenance Windows

**Scheduled Maintenance:**
- **Time:** First Sunday of month, 02:00-04:00 UTC
- **Activities:**
  - System updates
  - Database optimization
  - Log rotation
  - Backup verification
  - DR drill

**Emergency Maintenance:**
- Announced via status page
- Slack notification
- Customer notification if > 30 min

---

## Change Management

**Change Categories:**

**Category 1: Low Risk**
- Minor bug fixes
- UI tweaks
- Documentation updates
- Approval: Tech Lead
- Process: Standard CI/CD

**Category 2: Medium Risk**
- New features
- Database schema changes
- Configuration updates
- Approval: Tech Lead + DevOps
- Process: Staging → Production with monitoring

**Category 3: High Risk**
- Major version upgrades
- Infrastructure changes
- Security updates
- Approval: CTO + Team Review
- Process: Full DR drill + Canary deployment

---

## Contact Information

**On-Call Rotation:**
- Primary: [Name] - [Phone]
- Secondary: [Name] - [Phone]
- Escalation: CTO - [Phone]

**External Support:**
- OVH Support: support@ovh.com
- GitHub Support: support@github.com

**Status Page:** https://status.arewel.com (if applicable)

---

**Document Version:** 1.0
**Last Updated:** 2026-01-02
**Next Review:** 2026-04-02
**Owner:** DevOps Team
