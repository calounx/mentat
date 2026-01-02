# CHOM Production Deployment Checklist

**Version:** 1.0.0
**Environment:** Production
**Target:** mentat.arewel.com (51.254.139.78) + landsraad.arewel.com (51.77.150.96)

---

## Quick Reference

**Purpose:** This checklist provides a quick reference for production deployments. For detailed procedures, see PRODUCTION_DEPLOYMENT_RUNBOOK.md.

**Estimated Time:** 3 hours total
**Downtime:** 5-10 minutes during CHOM application cutover

---

## Pre-Deployment Phase (30 minutes)

### Infrastructure Verification

- [ ] VPS mentat.arewel.com accessible via SSH
- [ ] VPS landsraad.arewel.com accessible via SSH
- [ ] Both servers have Debian 13 installed
- [ ] Minimum resources available:
  - [ ] mentat: 2GB RAM, 40GB disk, 2 CPU
  - [ ] landsraad: 4GB RAM, 40GB disk, 2 CPU
- [ ] Internet connectivity verified on both servers
- [ ] Network connectivity between servers verified

### DNS Verification

- [ ] mentat.arewel.com → 51.254.139.78
- [ ] landsraad.arewel.com → 51.77.150.96
- [ ] DNS propagation complete
- [ ] Tested from multiple locations

### SSH Configuration

- [ ] SSH keys generated
- [ ] SSH keys deployed to both servers
- [ ] Passwordless SSH working
- [ ] SSH config file updated
- [ ] Sudo access verified

### Configuration Files

- [ ] .env.production created
- [ ] All required values filled in .env.production:
  - [ ] APP_KEY generated
  - [ ] DB_PASSWORD generated
  - [ ] REDIS_PASSWORD generated
  - [ ] PROMETHEUS_AUTH_PASSWORD generated
  - [ ] Brevo SMTP credentials added
  - [ ] Stripe keys added (if applicable)
- [ ] inventory.yaml configured with correct IPs
- [ ] Deployment scripts downloaded

### External Services

- [ ] Brevo SMTP account configured
- [ ] Brevo sender domain verified
- [ ] Test email sent and received
- [ ] SSL email address configured (admin@arewel.com)

### Team Readiness

- [ ] Deployment team assembled
- [ ] Roles and responsibilities assigned
- [ ] Communication channels established (#production-deploys, #incidents)
- [ ] Deployment window scheduled
- [ ] Stakeholders notified
- [ ] Runbook reviewed by all team members

### Backup Preparation

- [ ] VPS snapshots created (if available)
- [ ] Current state documented
- [ ] Rollback plan reviewed

---

## Deployment Phase 1: Observability Stack (45 minutes)

### Pre-Flight Checks

- [ ] Run: `./deploy-enhanced.sh --validate observability`
- [ ] All pre-flight checks passed

### Automated Deployment

- [ ] Run: `./deploy-enhanced.sh observability`
- [ ] Deployment completed without errors
- [ ] Review deployment logs

### Manual Verification (if automated deployment fails)

- [ ] Prometheus installed and running
- [ ] Loki installed and running
- [ ] Grafana installed and running
- [ ] Alertmanager installed and running
- [ ] Node Exporter installed and running
- [ ] Nginx configured and running
- [ ] SSL certificate obtained and valid
- [ ] Firewall rules configured

### Service Health Checks

- [ ] Prometheus health: `curl http://51.254.139.78:9090/-/healthy`
- [ ] Loki health: `curl http://51.254.139.78:3100/ready`
- [ ] Grafana health: `curl http://51.254.139.78:3000/api/health`
- [ ] Alertmanager health: `curl http://51.254.139.78:9093/-/healthy`
- [ ] Node Exporter health: `curl http://51.254.139.78:9100/metrics`
- [ ] HTTPS access: `curl -I https://mentat.arewel.com`

### Observability Stack Configuration

- [ ] Prometheus scraping configuration reviewed
- [ ] Loki retention configured (30 days)
- [ ] Grafana admin password changed
- [ ] Grafana data sources added:
  - [ ] Prometheus data source
  - [ ] Loki data source
- [ ] Initial dashboards imported

---

## Deployment Phase 2: CHOM Application (60 minutes)

### Pre-Flight Checks

- [ ] Run: `./deploy-enhanced.sh --validate vpsmanager`
- [ ] All pre-flight checks passed
- [ ] Observability stack verified accessible from landsraad

### Infrastructure Setup

- [ ] System packages updated
- [ ] Required packages installed:
  - [ ] Nginx
  - [ ] MySQL
  - [ ] Redis
  - [ ] PHP 8.4 + extensions
  - [ ] Composer
  - [ ] Promtail
  - [ ] Node Exporter

### Database Configuration

- [ ] MySQL installed and secured
- [ ] CHOM database created
- [ ] CHOM user created with proper permissions
- [ ] MySQL configuration tuned for production
- [ ] MySQL service running and enabled

### Redis Configuration

- [ ] Redis installed
- [ ] Redis password configured
- [ ] Redis persistence configured
- [ ] Redis service running and enabled

### PHP-FPM Configuration

- [ ] PHP-FPM pool configured
- [ ] PHP settings optimized for production
- [ ] PHP-FPM service running and enabled

### Application Installation

- [ ] Application directory created (/var/www/chom)
- [ ] Repository cloned
- [ ] File permissions set correctly
- [ ] Composer dependencies installed
- [ ] .env.production copied to .env
- [ ] APP_KEY generated

### Database Migration

- [ ] Migrations reviewed: `php artisan migrate:status`
- [ ] Migrations executed: `php artisan migrate --force`
- [ ] Migration status verified

### Application Optimization

- [ ] Caches cleared
- [ ] Production caches created:
  - [ ] Config cache
  - [ ] Route cache
  - [ ] View cache
  - [ ] Event cache
- [ ] Assets compiled (npm run build)
- [ ] Storage link created

### Queue Workers

- [ ] Queue worker services created:
  - [ ] chom-queue-worker (main)
  - [ ] chom-queue-default
  - [ ] chom-queue-emails
  - [ ] chom-queue-notifications
  - [ ] chom-queue-reports
- [ ] All queue workers started and enabled
- [ ] Queue workers verified running

### Cron Jobs

- [ ] Laravel scheduler cron job created
- [ ] Cron job permissions set
- [ ] Scheduler tested manually

### Nginx Configuration

- [ ] Nginx server block created
- [ ] Nginx configuration tested
- [ ] SSL certificate obtained
- [ ] HTTPS redirect configured
- [ ] Security headers configured
- [ ] Metrics endpoint protected with basic auth

### Log Shipping (Promtail)

- [ ] Promtail configured to ship to Loki
- [ ] Log sources configured:
  - [ ] Application logs
  - [ ] Nginx access logs
  - [ ] Nginx error logs
  - [ ] MySQL slow query logs
  - [ ] PHP-FPM error logs
  - [ ] Syslog
- [ ] Promtail service running and enabled

### Monitoring (Node Exporter)

- [ ] Node Exporter installed
- [ ] Node Exporter service running and enabled
- [ ] Metrics accessible

### Firewall Configuration

- [ ] UFW firewall configured
- [ ] Firewall rules verified:
  - [ ] SSH allowed (22)
  - [ ] HTTP allowed (80)
  - [ ] HTTPS allowed (443)
  - [ ] Internal monitoring ports restricted
- [ ] Firewall enabled

---

## Post-Deployment Validation (30 minutes)

### Service Health Checks - Observability

- [ ] All observability services running:
  - [ ] Prometheus
  - [ ] Loki
  - [ ] Grafana
  - [ ] Alertmanager
  - [ ] Node Exporter
  - [ ] Nginx
- [ ] All health endpoints responding
- [ ] HTTPS accessible

### Service Health Checks - CHOM

- [ ] All CHOM services running:
  - [ ] Nginx
  - [ ] PHP-FPM
  - [ ] MySQL
  - [ ] Redis
  - [ ] Queue workers (all 5)
  - [ ] Promtail
  - [ ] Node Exporter
- [ ] Health endpoints responding:
  - [ ] /health/ready
  - [ ] /health/live
  - [ ] /health/basic
- [ ] Database connectivity verified
- [ ] Redis connectivity verified

### Application Smoke Tests

- [ ] Homepage loads: `curl -I https://landsraad.arewel.com`
- [ ] Login page accessible
- [ ] API health endpoint responding
- [ ] Metrics endpoint accessible (with auth)
- [ ] Static assets loading
- [ ] No 500 errors in logs

### End-to-End Workflow Test

- [ ] User registration works
- [ ] Email delivery works
- [ ] User login works
- [ ] Dashboard accessible
- [ ] Core functionality tested:
  - [ ] Create organization
  - [ ] Create site
  - [ ] Background job processing
- [ ] Queue jobs processing correctly

### Performance Verification

- [ ] Homepage response time < 1 second
- [ ] Load test passed (100 requests, no failures)
- [ ] No performance warnings in logs
- [ ] Resource usage within limits:
  - [ ] CPU < 50%
  - [ ] Memory < 70%
  - [ ] Disk usage < 80%

### Security Validation

- [ ] SSL certificate valid
- [ ] SSL configuration strong (A+ rating)
- [ ] Security headers present:
  - [ ] Strict-Transport-Security
  - [ ] X-Frame-Options
  - [ ] X-Content-Type-Options
  - [ ] X-XSS-Protection
  - [ ] Referrer-Policy
- [ ] Firewall rules active
- [ ] MySQL not accessible from internet
- [ ] Redis not accessible from internet
- [ ] Fail2ban active

### Monitoring Validation

- [ ] Prometheus scraping CHOM metrics
  - [ ] Target status: UP
  - [ ] Metrics visible in Prometheus
- [ ] Loki receiving logs
  - [ ] Application logs visible
  - [ ] Nginx logs visible
  - [ ] System logs visible
- [ ] Grafana accessible
  - [ ] Admin login works
  - [ ] Dashboards visible
  - [ ] Data sources working
- [ ] Alertmanager configured
  - [ ] Alert rules loaded
  - [ ] Test alert sent successfully

### Backup Verification

- [ ] Backup directories exist
- [ ] Database backup tested
- [ ] Automated backup cron jobs configured
- [ ] Backup retention policy set

---

## Post-Deployment Tasks

### Configuration Updates

- [ ] Update Prometheus scrape config with actual credentials
- [ ] Update Grafana API key in .env (if needed)
- [ ] Configure alert notification channels
- [ ] Set up monitoring dashboards
- [ ] Import pre-built dashboards

### Documentation

- [ ] Deployment documented in change log
- [ ] Credentials securely stored in password manager
- [ ] Access information shared with team
- [ ] Monitoring alerts documented
- [ ] Runbook updated with actual values

### Team Handoff

- [ ] Access credentials shared (securely)
- [ ] Monitoring dashboards shared
- [ ] Alert channels configured
- [ ] On-call rotation updated
- [ ] Support team briefed

### Security Hardening

- [ ] Root SSH login disabled
- [ ] Fail2ban configured and tested
- [ ] Automatic security updates enabled
- [ ] Audit logging enabled
- [ ] Rate limiting configured

### Final Verification

- [ ] All critical paths tested
- [ ] No errors in any logs
- [ ] Monitoring working end-to-end
- [ ] Backups tested and working
- [ ] Team satisfied with deployment

---

## Sign-Off

### Deployment Team Sign-Off

- [ ] **Infrastructure Engineer:** _______________ Date: _______
  - Verified infrastructure setup
  - Verified network configuration
  - Verified security hardening

- [ ] **Application Engineer:** _______________ Date: _______
  - Verified application deployment
  - Verified database migrations
  - Verified queue workers

- [ ] **Database Administrator:** _______________ Date: _______
  - Verified database setup
  - Verified database performance
  - Verified backup configuration

- [ ] **Security Engineer:** _______________ Date: _______
  - Verified SSL configuration
  - Verified firewall rules
  - Verified security hardening

- [ ] **Monitoring Engineer:** _______________ Date: _______
  - Verified observability stack
  - Verified metrics collection
  - Verified log aggregation
  - Verified alerting

- [ ] **Operations Manager:** _______________ Date: _______
  - Overall deployment approved
  - Team satisfied with results
  - Ready for production traffic

### Deployment Status

**Deployment Result:** [ ] SUCCESS [ ] PARTIAL SUCCESS [ ] FAILED

**Deployment Start Time:** _____________

**Deployment End Time:** _____________

**Total Deployment Duration:** _____________

**Actual Downtime:** _____________

**Issues Encountered:**

1. _______________________________________________________
2. _______________________________________________________
3. _______________________________________________________

**Lessons Learned:**

1. _______________________________________________________
2. _______________________________________________________
3. _______________________________________________________

**Follow-Up Actions Required:**

1. _______________________________________________________
2. _______________________________________________________
3. _______________________________________________________

---

## Post-Deployment Monitoring (First 24 Hours)

### Hour 1

- [ ] No critical errors in logs
- [ ] Resource usage normal
- [ ] Response times acceptable
- [ ] No user-reported issues

### Hour 4

- [ ] No critical errors in logs
- [ ] Resource usage stable
- [ ] Metrics collecting correctly
- [ ] Logs aggregating correctly

### Hour 8

- [ ] No critical errors in logs
- [ ] Queue workers processing jobs
- [ ] Database performance good
- [ ] No memory leaks detected

### Hour 24

- [ ] Full day of logs in Loki
- [ ] Full day of metrics in Prometheus
- [ ] No unexpected issues
- [ ] Backups completed successfully
- [ ] Ready to mark deployment as stable

---

## Emergency Contacts

**On-Call Engineer:** _______________ Phone: _____________

**Backup Engineer:** _______________ Phone: _____________

**Engineering Manager:** _______________ Phone: _____________

**Escalation:** _______________ Phone: _____________

**Communication Channels:**
- Slack: #production-deploys
- Slack: #incidents
- Email: ops@arewel.com

---

## Quick Reference Commands

```bash
# Service Status
ssh deploy@mentat.arewel.com "sudo systemctl status prometheus grafana-server loki"
ssh deploy@landsraad.arewel.com "sudo systemctl status nginx php8.4-fpm mysql redis-server"

# Health Checks
curl https://mentat.arewel.com
curl https://landsraad.arewel.com/health/ready

# Logs
ssh deploy@landsraad.arewel.com "sudo tail -f /var/www/chom/storage/logs/laravel.log"
ssh deploy@landsraad.arewel.com "sudo journalctl -u chom-queue-worker -f"

# Restart Services (if needed)
ssh deploy@landsraad.arewel.com "sudo systemctl restart chom-queue-worker"
ssh deploy@landsraad.arewel.com "sudo systemctl restart php8.4-fpm"

# Enable Maintenance Mode (emergency)
ssh deploy@landsraad.arewel.com "cd /var/www/chom && sudo -u www-data php artisan down"
ssh deploy@landsraad.arewel.com "cd /var/www/chom && sudo -u www-data php artisan up"
```

---

**END OF DEPLOYMENT CHECKLIST**

**Print this checklist and check off items as you complete them during deployment.**
