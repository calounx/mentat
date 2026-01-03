# CHOM Monitoring Guide

Operations guide for monitoring the CHOM production environment.

## Table of Contents

- [Daily Operations](#daily-operations)
- [Metrics to Monitor](#metrics-to-monitor)
- [Dashboard Navigation](#dashboard-navigation)
- [Common Scenarios](#common-scenarios)
- [Performance Tuning](#performance-tuning)
- [Incident Response](#incident-response)

## Daily Operations

### Morning Checks

1. **Check System Overview Dashboard**
   - Navigate to Grafana → CHOM → System Overview
   - Review request rate trends (last 24h)
   - Check error rate (should be <1%)
   - Verify response times (p95 <500ms)

2. **Review Active Alerts**
   - Check AlertManager: http://localhost:9093
   - Acknowledge any informational alerts
   - Investigate any warnings

3. **Check Health Status**
   ```bash
   curl http://localhost:8000/health/detailed
   ```

4. **Review Queue Status**
   - Navigate to Business Metrics dashboard
   - Check queue job success rate (should be >95%)
   - Verify queue backlog is manageable (<1000 jobs)

### Weekly Reviews

1. **Capacity Planning**
   - Review tenant resource usage trends
   - Check storage growth rates
   - Monitor database size growth
   - Plan for scaling needs

2. **Performance Analysis**
   - Identify slow endpoints
   - Review database query performance
   - Analyze peak load periods
   - Optimize problem areas

3. **Cost Analysis**
   - Review infrastructure resource utilization
   - Identify unused or underutilized resources
   - Optimize for cost efficiency

## Metrics to Monitor

### Application Health

| Metric | Threshold | Action |
|--------|-----------|--------|
| Error Rate | >1% | Investigate immediately |
| Response Time (p95) | >500ms | Review slow endpoints |
| Response Time (p95) | >2s | Critical - immediate action |
| Active Requests | Sudden spike | Check for traffic anomalies |

### Database Performance

| Metric | Threshold | Action |
|--------|-----------|--------|
| Query Duration (p95) | >100ms | Review slow queries |
| Slow Query Rate | Increasing | Optimize problem queries |
| Connection Pool | >80% | Scale database or optimize connections |

### Queue Performance

| Metric | Threshold | Action |
|--------|-----------|--------|
| Job Success Rate | <95% | Investigate failing jobs |
| Queue Backlog | >1000 | Scale workers or investigate |
| Job Duration (p95) | >60s | Optimize slow jobs |

### Infrastructure

| Metric | Threshold | Action |
|--------|-----------|--------|
| Memory Usage | >85% | Investigate memory leaks |
| CPU Usage | >80% | Scale up or optimize code |
| Disk Space | <10% | Clean up or add storage |
| Disk Space | <5% | Critical - immediate action |

### Business Metrics

| Metric | Threshold | Action |
|--------|-----------|--------|
| Site Provisioning Success | <90% | Check VPS connectivity |
| VPS Operation Failures | >5% | Investigate provider issues |
| Backup Failures | >10% | Check backup infrastructure |

## Dashboard Navigation

### System Overview Dashboard

**Purpose**: High-level system health monitoring

**Key Panels**:
- Request Rate: Total requests per second
- Error Rate: Percentage of failed requests
- Request Duration (p95): 95th percentile response time
- Active Requests: Current concurrent requests
- Memory Usage: Application memory consumption
- Cache Hit Rate: Cache efficiency

**When to Use**: Daily monitoring, incident response

### Database Performance Dashboard

**Purpose**: Database query and connection monitoring

**Key Panels**:
- Query Rate: Queries per second by type
- Query Duration: Query execution times
- Slow Query Rate: Queries exceeding threshold
- Connection Pool: Database connection usage

**When to Use**: Performance tuning, slow query investigation

### Business Metrics Dashboard

**Purpose**: Business operation monitoring

**Key Panels**:
- Site Provisioning Rate: Sites provisioned per hour
- VPS Operations: VPS operation success/failure
- Queue Job Processing: Job throughput and success
- Tenant Resource Usage: Per-tenant consumption

**When to Use**: Business reporting, capacity planning

## Common Scenarios

### Scenario 1: High Error Rate Alert

**Symptoms**: Error rate >1% alert firing

**Investigation Steps**:
1. Check System Overview dashboard for error spike
2. Click through to see which routes are affected
3. Review logs in Loki filtered by error level
4. Check traces in Jaeger for failing requests
5. Review recent deployments

**Resolution**:
- If code issue: Rollback deployment
- If dependency issue: Check external service status
- If load issue: Scale infrastructure

### Scenario 2: Slow Response Times

**Symptoms**: Response time p95 >500ms

**Investigation Steps**:
1. Navigate to "Top Slow Endpoints" panel
2. Identify slowest routes
3. Check Database Performance dashboard
4. Review query durations for slow routes
5. Check traces for bottlenecks

**Resolution**:
- Optimize slow database queries
- Add caching where appropriate
- Review N+1 query problems
- Scale infrastructure if needed

### Scenario 3: Queue Backlog

**Symptoms**: Queue size >1000 jobs

**Investigation Steps**:
1. Check Queue Job Processing Rate
2. Review Job Success Rate
3. Check for failing jobs
4. Review worker capacity

**Resolution**:
- Scale queue workers
- Fix failing jobs
- Optimize slow jobs
- Adjust job priorities

### Scenario 4: Database Connection Pool Exhaustion

**Symptoms**: Connection pool >80% utilized

**Investigation Steps**:
1. Check Database Performance dashboard
2. Review query duration distribution
3. Check for long-running queries
4. Review connection timeout settings

**Resolution**:
- Kill long-running queries
- Optimize slow queries
- Increase connection pool size
- Add connection pooling middleware

### Scenario 5: High Memory Usage

**Symptoms**: Memory usage >85%

**Investigation Steps**:
1. Check memory usage trend
2. Review active operations
3. Check for memory leaks
4. Review recent code changes

**Resolution**:
- Restart application if memory leak
- Optimize memory-intensive operations
- Increase available memory
- Review and fix memory leaks

## Performance Tuning

### Database Optimization

1. **Identify Slow Queries**
   ```bash
   # Check Prometheus for slow queries
   curl 'http://localhost:9090/api/v1/query?query=topk(10,chom:db:slow_query_rate)'
   ```

2. **Review Query Patterns**
   - Check for N+1 queries
   - Add eager loading where needed
   - Add missing indexes
   - Review query complexity

3. **Connection Pool Tuning**
   ```php
   // config/database.php
   'connections' => [
       'mysql' => [
           'pool' => [
               'min' => 5,
               'max' => 20,
           ],
       ],
   ],
   ```

### Cache Optimization

1. **Monitor Hit Rate**
   - Target: >70% cache hit rate
   - Review cache TTL settings
   - Identify cacheable operations

2. **Cache Strategy**
   ```php
   // Aggressive caching for static data
   Cache::remember('static-data', 3600, fn() => $data);

   // Short TTL for dynamic data
   Cache::remember('dynamic-data', 60, fn() => $data);
   ```

### Queue Optimization

1. **Job Chunking**
   ```php
   // Split large jobs into smaller chunks
   dispatch(new ProcessChunk($items->chunk(100)));
   ```

2. **Job Priority**
   ```php
   // Use priority queues
   dispatch(new CriticalJob)->onQueue('high');
   dispatch(new BackgroundJob)->onQueue('low');
   ```

3. **Worker Scaling**
   ```bash
   # Scale workers based on queue depth
   php artisan queue:work --tries=3 --timeout=60
   ```

## Incident Response

### Severity Levels

**P0 - Critical**
- Complete service outage
- Data loss risk
- Security breach

**P1 - High**
- Partial service degradation
- High error rates (>5%)
- Database issues

**P2 - Medium**
- Performance degradation
- Non-critical feature failure
- Warning alerts

**P3 - Low**
- Informational alerts
- Minor issues
- Scheduled maintenance

### Incident Response Steps

1. **Acknowledge Alert**
   - Acknowledge in AlertManager
   - Create incident ticket
   - Notify team

2. **Assess Impact**
   - Check affected services
   - Estimate user impact
   - Review recent changes

3. **Mitigate**
   - Implement immediate fixes
   - Rollback if needed
   - Scale resources if needed

4. **Investigate**
   - Check logs in Loki
   - Review traces in Jaeger
   - Analyze metrics in Grafana

5. **Resolve**
   - Implement permanent fix
   - Verify resolution
   - Update documentation

6. **Post-Incident**
   - Write incident report
   - Update runbooks
   - Implement preventive measures

### Emergency Contacts

```
On-Call Rotation: [Configure PagerDuty/OpsGenie]
Escalation Path:
  L1: On-Call Engineer
  L2: Senior Engineer
  L3: Engineering Manager
  L4: CTO
```

### Useful Commands

```bash
# Check application health
curl http://localhost:8000/health/detailed

# View metrics
curl http://localhost:8000/metrics

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets

# View active alerts
curl http://localhost:9093/api/v1/alerts

# Restart services
docker-compose -f observability-stack/docker-compose.yml restart

# View logs
docker-compose -f observability-stack/docker-compose.yml logs -f [service]

# Scale queue workers
php artisan queue:work --workers=5
```

## Best Practices

1. **Monitor Trends, Not Just Values**
   - Look for unexpected changes
   - Compare to historical baselines
   - Identify patterns

2. **Set Up Proper Alerts**
   - Alert on SLIs, not just symptoms
   - Avoid alert fatigue
   - Test alert routing

3. **Document Everything**
   - Update runbooks after incidents
   - Document normal behavior
   - Share knowledge with team

4. **Regular Reviews**
   - Weekly performance reviews
   - Monthly capacity planning
   - Quarterly system audits

5. **Automate Where Possible**
   - Auto-scaling rules
   - Automated remediation
   - Self-healing systems

6. **Test in Non-Production**
   - Load testing
   - Chaos engineering
   - Disaster recovery drills

## References

- [OBSERVABILITY.md](OBSERVABILITY.md) - Complete observability documentation
- [ALERTING.md](ALERTING.md) - Alert runbooks and configurations
- Grafana: http://localhost:3000
- Prometheus: http://localhost:9090
- Jaeger: http://localhost:16686
- AlertManager: http://localhost:9093
