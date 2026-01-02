# Incident Runbook: Queue Worker Failures

**Severity:** SEV2 (High) - Can escalate to SEV1
**Impact:** Background jobs not processing, email delays
**Expected Resolution Time:** 10-20 minutes

## Detection
- Alert: `QueueBacklogHigh` (> 1000 jobs)
- Alert: `QueueWorkerDown`
- Failed jobs increasing
- User reports: emails not received

## Quick Triage
```bash
# Check queue status
ssh deploy@landsraad.arewel.com << 'EOF'
docker ps | grep queue
docker exec chom-redis redis-cli LLEN queues:default
docker exec chom-redis redis-cli LLEN queues:emails
docker exec chom-mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "SELECT COUNT(*) FROM failed_jobs;"
docker logs chom-queue --tail 50
EOF
```

## Resolution

### Scenario 1: Queue Worker Crashed
```bash
# Restart queue workers
ssh deploy@landsraad.arewel.com << 'EOF'
docker compose -f /opt/chom/docker-compose.production.yml restart queue
EOF

# Verify processing resumed
watch -n 5 'ssh deploy@landsraad.arewel.com "docker exec chom-redis redis-cli LLEN queues:default"'
```

### Scenario 2: Jobs Failing Repeatedly
```bash
# Check failed jobs
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "
  SELECT id, queue, exception, failed_at
  FROM failed_jobs
  ORDER BY failed_at DESC LIMIT 10;
"
EOF

# Clear failed jobs queue (after investigating)
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-app php artisan queue:flush
docker exec chom-app php artisan queue:restart
EOF
```

### Scenario 3: Redis Connection Issues
```bash
# Test Redis connectivity
ssh deploy@landsraad.arewel.com "docker exec chom-redis redis-cli ping"

# If Redis down, restart
ssh deploy@landsraad.arewel.com << 'EOF'
docker compose -f /opt/chom/docker-compose.production.yml restart redis queue
EOF
```

## Verification
```bash
# Queue depth decreasing
ssh deploy@landsraad.arewel.com "docker exec chom-redis redis-cli LLEN queues:default"

# Workers processing
docker logs chom-queue --tail 20 | grep "Processing:"

# No new failures
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "
  SELECT COUNT(*) FROM failed_jobs WHERE failed_at > NOW() - INTERVAL 5 MINUTE;
"
EOF
```

## Prevention
- Worker health monitoring
- Failed job alerts
- Queue depth monitoring
- Auto-restart on failure

---

**Version:** 1.0 | **Updated:** 2026-01-02
