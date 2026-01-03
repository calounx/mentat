# CHOM Alerting Guide

Complete guide to alerts, alert handling, and runbooks for the CHOM production environment.

## Table of Contents

- [Alert Overview](#alert-overview)
- [Alert Severity Levels](#alert-severity-levels)
- [Alert Channels](#alert-channels)
- [Critical Alerts](#critical-alerts)
- [Warning Alerts](#warning-alerts)
- [Runbooks](#runbooks)
- [Alert Configuration](#alert-configuration)

## Alert Overview

The CHOM alerting system monitors critical system metrics and business operations, automatically notifying the team when thresholds are exceeded.

### Alert Philosophy

1. **Alert on symptoms, not causes** - Alert when users are affected
2. **Actionable alerts only** - Every alert should require action
3. **Clear severity levels** - Easy to understand impact and urgency
4. **Detailed context** - Alerts include investigation links and context

### Alert Flow

```
Metric Threshold Exceeded
    ↓
Prometheus AlertRule Triggers
    ↓
AlertManager Receives Alert
    ↓
Alert Grouped & Deduplicated
    ↓
Routed to Appropriate Channel
    ↓
Team Notified (Email/Slack/PagerDuty)
```

## Alert Severity Levels

### Critical (P0)

**Impact**: Service outage or data loss
**Response Time**: Immediate (15 minutes)
**Notification**: Email + Slack + PagerDuty
**Escalation**: Automatic after 15 minutes

### Warning (P2)

**Impact**: Degraded performance or approaching limits
**Response Time**: 1 hour
**Notification**: Email + Slack
**Escalation**: Manual if unresolved after 4 hours

### Info (P3)

**Impact**: Informational only
**Response Time**: Next business day
**Notification**: Slack only
**Escalation**: None

## Alert Channels

### Configuration

Alerts are routed based on severity:

| Severity | Email | Slack | PagerDuty |
|----------|-------|-------|-----------|
| Critical | ✓ | ✓ (#alerts-critical) | ✓ |
| Warning | ✓ | ✓ (#alerts-warning) | ✗ |
| Info | ✗ | ✓ (#alerts-info) | ✗ |

### Setting Up Channels

1. **Email**: Configure in `observability-stack/alertmanager/alertmanager.yml`
2. **Slack**: Set webhook URL in environment variables
3. **PagerDuty**: Add integration key to AlertManager config

## Critical Alerts

### HighErrorRate

**Severity**: Critical
**Threshold**: HTTP error rate >1% for 5 minutes

**Description**: The application is experiencing elevated error rates that are likely impacting users.

**Runbook**:
1. Check System Overview dashboard for error spike pattern
2. Identify affected routes in Grafana
3. Review application logs in Loki:
   ```
   {app="chom"} |= "error" | json
   ```
4. Check recent deployments in last hour
5. Review external service status (database, Redis, VPS provider)

**Common Causes**:
- Recent deployment with bugs
- Database connectivity issues
- External API failures
- High load causing timeouts

**Resolution**:
- Rollback recent deployment if bug identified
- Scale infrastructure if load-related
- Fix external service issues
- Apply hotfix if critical bug found

---

### CriticalErrorRate

**Severity**: Critical
**Threshold**: HTTP error rate >5% for 1 minute

**Description**: CRITICAL: Very high error rate indicating severe service degradation.

**Runbook**:
1. **IMMEDIATE**: Page on-call engineer
2. Check if complete service outage
3. Review AlertManager for cascading alerts
4. Check infrastructure health:
   ```bash
   curl http://localhost:8000/health/detailed
   ```
5. Check database connectivity
6. Review load balancer status

**Common Causes**:
- Database outage
- Application crash/restart loop
- Resource exhaustion (memory/CPU)
- Cascading failure

**Resolution**:
- Rollback immediately if deployment-related
- Restart application if crashed
- Scale infrastructure if resource exhaustion
- Failover database if database issue

---

### VerySlowResponseTime

**Severity**: Critical
**Threshold**: API response time p95 >2s for 5 minutes

**Description**: API response times are critically slow, severely impacting user experience.

**Runbook**:
1. Check "Top Slow Endpoints" in Grafana
2. Review Database Performance dashboard
3. Check for slow queries:
   ```bash
   curl 'http://localhost:9090/api/v1/query?query=topk(10,chom:db:query_duration_p95)'
   ```
4. Review traces in Jaeger for slow requests
5. Check system resources (CPU, memory, disk I/O)

**Common Causes**:
- Unoptimized database queries
- Missing database indexes
- High load
- External API timeouts
- Resource contention

**Resolution**:
- Kill long-running queries
- Add missing indexes
- Scale infrastructure
- Optimize slow code paths
- Add caching

---

### DatabaseUnavailable

**Severity**: Critical
**Threshold**: Database health check failed for 1 minute

**Description**: Database is unavailable, causing complete service failure.

**Runbook**:
1. **IMMEDIATE**: Page on-call and DBA
2. Check database server status
3. Check connection pool exhaustion
4. Review database logs
5. Check for maintenance windows

**Common Causes**:
- Database server down
- Network connectivity issue
- Too many connections
- Disk full on database server

**Resolution**:
- Restart database if crashed
- Increase connection pool size
- Clear disk space
- Failover to replica if available

---

### VpsOperationFailures

**Severity**: Critical
**Threshold**: VPS operation failure rate >5% for 10 minutes

**Description**: High rate of VPS operation failures affecting site provisioning and management.

**Runbook**:
1. Check Business Metrics dashboard
2. Review VPS provider API status
3. Check VPS provider credentials
4. Review VPS operation logs
5. Check quota limits

**Common Causes**:
- VPS provider API issues
- Authentication failures
- Quota/resource limits
- Network issues

**Resolution**:
- Contact VPS provider support
- Refresh API credentials
- Increase quota limits
- Retry failed operations

---

### SiteProvisioningFailures

**Severity**: Critical
**Threshold**: Site provisioning failure rate >10% for 15 minutes

**Description**: High rate of site provisioning failures impacting new customer onboarding.

**Runbook**:
1. Check Business Metrics dashboard
2. Review provisioning job logs
3. Check VPS connectivity
4. Review failed job traces in Jaeger
5. Check queue worker status

**Common Causes**:
- VPS provider issues
- Insufficient resources
- Configuration errors
- Network connectivity

**Resolution**:
- Fix VPS connectivity issues
- Scale VPS resources
- Fix configuration errors
- Retry failed provisioning jobs

## Warning Alerts

### SlowResponseTime

**Severity**: Warning
**Threshold**: API response time p95 >500ms for 5 minutes

**Description**: API response times are elevated and approaching critical levels.

**Runbook**:
1. Monitor trend - is it getting worse?
2. Check Database Performance dashboard
3. Review slow queries
4. Check cache hit rate
5. Review system load

**Resolution**:
- Optimize slow queries
- Add caching where appropriate
- Scale infrastructure if load increasing
- Schedule optimization work

---

### SlowDatabaseQueries

**Severity**: Warning
**Threshold**: Database query p95 >100ms for 5 minutes

**Description**: Database queries are running slower than optimal.

**Runbook**:
1. Review Database Performance dashboard
2. Identify slow query types (SELECT, INSERT, UPDATE)
3. Check for missing indexes
4. Review query execution plans
5. Check database load

**Resolution**:
- Add missing indexes
- Optimize complex queries
- Review query patterns for N+1 issues
- Schedule query optimization

---

### HighJobFailureRate

**Severity**: Warning
**Threshold**: Queue job failure rate >5% for 10 minutes

**Description**: Elevated queue job failure rate.

**Runbook**:
1. Check Business Metrics dashboard
2. Identify failing job types
3. Review job error logs
4. Check job dependencies (database, APIs)
5. Review job retry configuration

**Resolution**:
- Fix bugs in failing jobs
- Increase job timeout if needed
- Fix dependency issues
- Adjust retry configuration

---

### LowCacheHitRate

**Severity**: Warning
**Threshold**: Cache hit rate <50% for 15 minutes

**Description**: Cache is not being utilized effectively.

**Runbook**:
1. Review cache configuration
2. Check cache TTL settings
3. Identify frequently missed keys
4. Review cache eviction policy
5. Check Redis memory usage

**Resolution**:
- Adjust cache TTL values
- Increase cache size if memory allows
- Review and optimize cache strategy
- Pre-warm cache for common queries

---

### HighMemoryUsage

**Severity**: Warning
**Threshold**: Memory usage >85% for 5 minutes

**Description**: Application memory usage is high and may lead to OOM issues.

**Runbook**:
1. Check memory usage trend
2. Review active processes
3. Check for memory leaks
4. Review recent code changes
5. Check object cache size

**Resolution**:
- Restart application if memory leak
- Scale infrastructure (more memory)
- Fix memory leaks in code
- Optimize memory usage

---

### LowDiskSpace

**Severity**: Warning
**Threshold**: Disk space <10% for 5 minutes

**Description**: Disk space is running low and may impact operations.

**Runbook**:
1. Check disk usage by directory
2. Review log rotation
3. Check for large files
4. Review backup storage
5. Check tmp directory

**Resolution**:
- Clean up old logs
- Archive old backups
- Remove temporary files
- Add more disk space

## Runbooks

### Generic Alert Response Checklist

For any alert:

- [ ] Acknowledge alert in AlertManager
- [ ] Check alert severity and impact
- [ ] Review relevant dashboard in Grafana
- [ ] Check application logs in Loki
- [ ] Review traces in Jaeger if applicable
- [ ] Document findings in incident ticket
- [ ] Implement fix or mitigation
- [ ] Verify alert resolved
- [ ] Update runbook if new learnings

### Investigation Commands

```bash
# Check application health
curl http://localhost:8000/health/detailed

# View current metrics
curl http://localhost:8000/metrics | grep error

# Query Prometheus
curl 'http://localhost:9090/api/v1/query?query=chom:http:error_rate'

# View recent logs
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={app="chom"} |= "error"' \
  --data-urlencode 'limit=100'

# Check active alerts
curl http://localhost:9093/api/v1/alerts

# Check database connections
mysql -e "SHOW PROCESSLIST;"

# Check queue status
php artisan queue:monitor

# Restart services
docker-compose -f observability-stack/docker-compose.yml restart
```

## Alert Configuration

### Modifying Alerts

Edit alert rules in:
```
observability-stack/prometheus/alerting-rules.yml
```

### Alert Rule Format

```yaml
- alert: AlertName
  expr: metric_expression > threshold
  for: 5m
  labels:
    severity: critical
    component: application
  annotations:
    summary: "Brief alert description"
    description: "Detailed alert description with {{ $value }}"
    runbook_url: "https://docs.chom.app/runbooks/alert-name"
```

### Testing Alerts

1. **Trigger test alert manually**:
   ```bash
   # Send test alert to AlertManager
   curl -X POST http://localhost:9093/api/v1/alerts -d '[{
     "labels": {"alertname": "TestAlert", "severity": "warning"},
     "annotations": {"summary": "Test alert"}
   }]'
   ```

2. **Verify alert routing**:
   - Check email delivery
   - Verify Slack notification
   - Confirm PagerDuty escalation (for critical)

3. **Test alert resolution**:
   - Wait for condition to clear
   - Verify resolution notification sent

### Alert Tuning

If experiencing alert fatigue:

1. **Review false positives**
   - Adjust thresholds based on baseline
   - Increase evaluation period
   - Add additional conditions

2. **Group related alerts**
   - Use inhibition rules
   - Group by service/component
   - Reduce notification frequency

3. **Adjust severity**
   - Downgrade non-actionable alerts
   - Combine multiple conditions
   - Remove redundant alerts

## On-Call Responsibilities

### Primary On-Call

- Respond to critical alerts within 15 minutes
- Acknowledge all alerts
- Escalate if unable to resolve within 1 hour
- Document all incidents
- Update runbooks based on learnings

### Secondary On-Call

- Monitor #alerts-critical channel
- Assist primary if requested
- Take over if primary non-responsive after 30 minutes
- Review incident reports

### Post-Incident

- Complete incident report within 24 hours
- Update relevant runbooks
- Create follow-up tasks for preventive measures
- Share learnings with team

## References

- [OBSERVABILITY.md](OBSERVABILITY.md) - Observability stack documentation
- [MONITORING_GUIDE.md](MONITORING_GUIDE.md) - Daily monitoring operations
- Prometheus Alerts: http://localhost:9090/alerts
- AlertManager: http://localhost:9093
- Grafana Dashboards: http://localhost:3000
