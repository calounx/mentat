# Incident Runbook: High CPU/Memory Usage

**Severity:** SEV2 (High) - Can escalate to SEV1
**Component:** Application/Infrastructure
**Impact:** Performance degradation, potential outage
**Expected Resolution Time:** 10-30 minutes

---

## Detection

### Automated Alerts
- Prometheus alert: `HighCPUUsage` (> 80% for 5 minutes)
- Prometheus alert: `HighMemoryUsage` (> 90% for 5 minutes)
- Application slow response times
- Queue backlog building up

### Manual Detection
- Users reporting slow page loads
- SSH/terminal lag on server
- High load average in monitoring dashboards

---

## Triage (First 2 Minutes)

### Quick Assessment
```bash
# 1. Check overall system resources
ssh deploy@landsraad.arewel.com << 'EOF'
echo "=== CPU & Memory ==="
top -bn1 | head -20

echo "=== Load Average ==="
uptime

echo "=== Memory Details ==="
free -h

echo "=== Top Processes by CPU ==="
ps aux --sort=-%cpu | head -10

echo "=== Top Processes by Memory ==="
ps aux --sort=-%mem | head -10
EOF

# 2. Check Docker container resources
ssh deploy@landsraad.arewel.com "docker stats --no-stream"
```

### Determine Resource Type
- [ ] High CPU usage
- [ ] High Memory usage
- [ ] Both CPU and Memory high
- [ ] Memory leak suspected
- [ ] CPU runaway process

---

## Resolution Procedures

### Scenario 1: PHP-FPM High CPU/Memory

**Symptoms:** `php-fpm` processes consuming excessive resources

```bash
# 1. Identify problematic PHP processes
ssh deploy@landsraad.arewel.com << 'EOF'
ps aux | grep php-fpm | grep -v grep
docker exec chom-app php artisan queue:work --help 2>&1 | head -1
EOF

# 2. Check for long-running requests
ssh deploy@landsraad.arewel.com "docker logs chom-nginx --tail 100 | grep -E 'request_time:[5-9]|request_time:[0-9]{2}'"

# 3. QUICK FIX: Restart PHP-FPM container
ssh deploy@landsraad.arewel.com << 'EOF'
docker compose -f docker-compose.production.yml restart app
EOF

# 4. Monitor improvement
watch -n 5 'ssh deploy@landsraad.arewel.com "docker stats --no-stream chom-app"'

# 5. If issue persists, check for infinite loops in code
ssh deploy@landsraad.arewel.com "docker logs chom-app --tail 500 | grep -i error"

# 6. Check Laravel query log for slow queries
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-app tail -100 /var/www/html/storage/logs/laravel.log | grep -i "select\|update\|insert"
EOF
```

**Expected Resolution Time:** 5-10 minutes

---

### Scenario 2: Queue Worker Memory Leak

**Symptoms:** Queue worker memory grows continuously

```bash
# 1. Check queue worker memory
ssh deploy@landsraad.arewel.com << 'EOF'
docker stats --no-stream chom-queue | awk '{print $3, $7}'
EOF

# 2. Restart queue workers (safe - jobs are persisted in Redis)
ssh deploy@landsraad.arewel.com << 'EOF'
docker compose -f docker-compose.production.yml restart queue
EOF

# 3. Monitor memory usage after restart
watch -n 10 'ssh deploy@landsraad.arewel.com "docker stats --no-stream chom-queue"'

# 4. If memory grows quickly, implement worker restart policy
ssh deploy@landsraad.arewel.com << 'EOF'
# Edit docker-compose.production.yml to add:
# queue:
#   command: php artisan queue:work --max-time=3600 --max-jobs=1000
docker compose -f docker-compose.production.yml up -d queue
EOF
```

**Expected Resolution Time:** 5-10 minutes

---

### Scenario 3: Database Query Performance

**Symptoms:** High CPU due to slow database queries

```bash
# 1. Check slow query log
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-mysql tail -50 /var/log/mysql/slow-query.log
EOF

# 2. Check current queries
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "SHOW PROCESSLIST;"
EOF

# 3. Kill long-running queries (> 60 seconds)
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "
SELECT CONCAT('KILL ', id, ';')
FROM information_schema.processlist
WHERE time > 60
AND user != 'system user';"
EOF

# 4. Check for missing indexes
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "
SELECT * FROM sys.statements_with_runtimes_in_95th_percentile;
"
EOF

# 5. If specific query identified, add to queue for optimization
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-app php artisan tinker --execute="
  logger()->warning('Slow query identified: [QUERY_TEXT]');
"
EOF
```

**Expected Resolution Time:** 10-20 minutes

---

### Scenario 4: Redis Memory Exhaustion

**Symptoms:** Redis using excessive memory, evicting keys

```bash
# 1. Check Redis memory usage
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-redis redis-cli INFO memory
EOF

# 2. Check key count and sizes
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-redis redis-cli DBSIZE
docker exec chom-redis redis-cli --bigkeys
EOF

# 3. Clear specific problematic keys
ssh deploy@landsraad.arewel.com << 'EOF'
# Clear cache (sessions and queues preserved)
docker exec chom-redis redis-cli -n 1 FLUSHDB
EOF

# 4. If critical, clear all except queues
ssh deploy@landsraad.arewel.com << 'EOF'
# ⚠️  WARNING: This will log out all users
docker exec chom-redis redis-cli -n 0 FLUSHDB  # Laravel cache
docker exec chom-redis redis-cli -n 3 FLUSHDB  # Sessions
# Do NOT flush DB 2 (queues) unless necessary
EOF

# 5. Restart application to clear in-memory caches
ssh deploy@landsraad.arewel.com << 'EOF'
docker compose -f docker-compose.production.yml restart app
EOF
```

**Expected Resolution Time:** 5-15 minutes

---

### Scenario 5: Nginx Worker Saturation

**Symptoms:** All Nginx workers busy, queuing requests

```bash
# 1. Check Nginx status
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-nginx nginx -T | grep worker
docker stats --no-stream chom-nginx
EOF

# 2. Check active connections
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-nginx sh -c "ss -s"
EOF

# 3. Restart Nginx (brief < 1 second interruption)
ssh deploy@landsraad.arewel.com << 'EOF'
docker compose -f docker-compose.production.yml restart nginx
EOF

# 4. If under DDoS, implement rate limiting
ssh deploy@landsraad.arewel.com << 'EOF'
# Add to nginx config:
# limit_req_zone $binary_remote_addr zone=one:10m rate=10r/s;
# limit_req zone=one burst=20 nodelay;
docker compose -f docker-compose.production.yml reload nginx
EOF
```

**Expected Resolution Time:** 5-10 minutes

---

## Emergency Procedures

### CRITICAL: System Unresponsive

If system is so overloaded you can't even SSH:

```bash
# 1. Access via OVH console/KVM
# 2. Emergency kill processes
killall -9 php-fpm
killall -9 queue:work

# 3. Restart Docker
systemctl restart docker

# 4. Bring up only critical services
cd /opt/chom
docker compose -f docker-compose.production.yml up -d mysql redis nginx app
# Leave queue workers down temporarily

# 5. Once stable, restart queue
docker compose -f docker-compose.production.yml up -d queue
```

### Memory Leak Suspected

```bash
# 1. Enable maintenance mode
ssh deploy@landsraad.arewel.com "docker exec chom-app php artisan down"

# 2. Capture memory dump for analysis
ssh deploy@landsraad.arewel.com << 'EOF'
docker stats --no-stream > /tmp/docker-stats-$(date +%Y%m%d-%H%M%S).txt
docker exec chom-app ps aux > /tmp/process-list-$(date +%Y%m%d-%H%M%S).txt
EOF

# 3. Restart all containers
ssh deploy@landsraad.arewel.com << 'EOF'
docker compose -f docker-compose.production.yml restart
EOF

# 4. Disable maintenance mode
ssh deploy@landsraad.arewel.com "docker exec chom-app php artisan up"

# 5. Monitor closely for 30 minutes
watch -n 60 'ssh deploy@landsraad.arewel.com "docker stats --no-stream"'
```

---

## Verification Steps

```bash
# 1. Check CPU usage returned to normal
ssh deploy@landsraad.arewel.com "top -bn1 | head -20"
# Expected: CPU < 50%, load average < 2.0

# 2. Check memory usage
ssh deploy@landsraad.arewel.com "free -h"
# Expected: Memory used < 80%

# 3. Check Docker container resources
ssh deploy@landsraad.arewel.com "docker stats --no-stream"
# Expected: All containers < 80% memory, < 50% CPU

# 4. Test application response time
for i in {1..10}; do
  curl -o /dev/null -s -w "Response time: %{time_total}s\n" https://landsraad.arewel.com
done
# Expected: < 1 second per request

# 5. Check queue processing
ssh deploy@landsraad.arewel.com "docker exec chom-redis redis-cli LLEN queues:default"
# Expected: Queue depth decreasing

# 6. Monitor Prometheus metrics
curl -s http://51.254.139.78:9090/api/v1/query?query=node_load1 | jq '.data.result[0].value[1]'
# Expected: < 2.0
```

---

## Post-Incident Actions

### Immediate
1. Document peak resource usage observed
2. Identify trigger (specific endpoint, background job, etc.)
3. Check if issue is recurring pattern

### Short-term (24 hours)
1. Review application logs for optimization opportunities
2. Analyze slow queries and add indexes
3. Implement code-level fixes if bottleneck identified
4. Update monitoring thresholds if needed

### Long-term (1 week)
1. Load testing to identify breaking points
2. Implement horizontal scaling if needed
3. Optimize resource-intensive operations
4. Schedule capacity planning review

---

## Prevention Checklist

- [ ] Resource monitoring alerts configured (80% threshold)
- [ ] Auto-scaling policies defined
- [ ] Queue worker restart policy (max-time, max-jobs)
- [ ] Database query monitoring active
- [ ] Slow query log enabled
- [ ] Application profiling tools installed
- [ ] Load testing performed quarterly
- [ ] Capacity planning reviewed monthly

---

**Document Version:** 1.0
**Last Updated:** 2026-01-02
**Last Tested:** [DATE]
**Next Review:** 2026-02-02
