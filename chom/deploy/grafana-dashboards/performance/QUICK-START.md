# CHOM Performance Dashboards - Quick Start Guide

Get up and running with CHOM performance monitoring in under 10 minutes.

## Prerequisites Checklist

- [ ] Grafana installed and running (http://localhost:3000)
- [ ] Prometheus installed and running (http://localhost:9090)
- [ ] MySQL/PostgreSQL database running
- [ ] CHOM application running

## 5-Minute Setup

### Step 1: Import Dashboards (2 minutes)

```bash
# Navigate to dashboards directory
cd /home/calounx/repositories/mentat/chom/deploy/grafana-dashboards/performance

# Import via Grafana UI
# 1. Open http://localhost:3000
# 2. Login (default: admin/admin)
# 3. Click "+" → "Import"
# 4. Upload each JSON file:
#    - 1-apm-dashboard.json
#    - 2-database-performance-dashboard.json
#    - 3-frontend-performance-dashboard.json
```

### Step 2: Install Required Exporters (3 minutes)

```bash
# Install all exporters via Docker Compose
cat > docker-compose-exporters.yml <<EOF
version: '3.8'

services:
  mysql-exporter:
    image: prom/mysqld-exporter:latest
    ports:
      - "9104:9104"
    environment:
      DATA_SOURCE_NAME: "exporter:password@(mysql:3306)/"
    restart: unless-stopped

  php-fpm-exporter:
    image: hipages/php-fpm_exporter:latest
    ports:
      - "9253:9253"
    command:
      - --phpfpm.scrape-uri
      - tcp://php-fpm:9000/status
    restart: unless-stopped

  node-exporter:
    image: prom/node-exporter:latest
    ports:
      - "9100:9100"
    restart: unless-stopped
EOF

docker-compose -f docker-compose-exporters.yml up -d
```

### Step 3: Configure Prometheus (2 minutes)

```bash
# Add scrape configs to Prometheus
cat >> /etc/prometheus/prometheus.yml <<EOF

  - job_name: 'chom-exporters'
    static_configs:
      - targets:
        - 'localhost:9104'  # MySQL
        - 'localhost:9253'  # PHP-FPM
        - 'localhost:9100'  # Node
EOF

# Reload Prometheus
sudo systemctl reload prometheus
# or
curl -X POST http://localhost:9090/-/reload
```

### Step 4: Verify Setup

```bash
# Check Prometheus targets (all should be "UP")
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Expected output:
# {"job":"chom-exporters","health":"up"}
# {"job":"chom-exporters","health":"up"}
# {"job":"chom-exporters","health":"up"}

# Open Grafana and verify dashboards show data
# http://localhost:3000/dashboards
```

---

## First Use Guide

### 1. APM Dashboard - Find Your Slowest Endpoint

```
1. Open: http://localhost:3000/d/chom-apm-performance
2. Look at "Endpoint Performance Heatmap" panel
3. Red/orange areas = slow endpoints
4. Click on "Slowest Endpoints (Top 10)" table
5. Click on endpoint name to filter dashboard
6. Review specific metrics for that endpoint
```

**Quick Win**: If p95 > 500ms:
```bash
# Check for N+1 queries
php artisan debugbar:cache:clear

# Enable query logging
tail -f storage/logs/laravel.log | grep "SELECT"
```

### 2. Database Dashboard - Identify Slow Queries

```
1. Open: http://localhost:3000/d/chom-database-performance
2. Check "Query Latency Distribution" panel
3. If p95 > 100ms, look at "Slowest Queries by Table"
4. Click table name to filter
5. Review "Index Usage Efficiency" for that table
```

**Quick Win**: If index efficiency < 95%:
```sql
-- Check query execution plan
EXPLAIN SELECT * FROM sites WHERE user_id = 123;

-- If "type: ALL", add index
CREATE INDEX idx_sites_user_id ON sites(user_id);
```

### 3. Frontend Dashboard - Improve Core Web Vitals

```
1. Open: http://localhost:3000/d/chom-frontend-performance
2. Check "Core Web Vitals (p75)" panel
3. Red/yellow values = needs optimization
4. Review "Page Performance Comparison" to find worst pages
5. Click page to filter and see specific issues
```

**Quick Wins**:
- **LCP > 2.5s**: Optimize largest image, add lazy loading
- **FID > 100ms**: Defer non-critical JavaScript
- **CLS > 0.1**: Add width/height to images

---

## Common Performance Issues - Quick Fixes

### Issue 1: High Response Times (p95 > 500ms)

**Diagnosis** (30 seconds):
```bash
# Check APM dashboard → "Slowest Endpoints (Top 10)"
```

**Fix** (5 minutes):
```php
// Add caching to slow endpoint
// Before
public function index()
{
    return Site::with('user')->get();
}

// After
public function index()
{
    return Cache::remember('sites.index', 300, function () {
        return Site::with('user')->get();
    });
}
```

**Verify** (1 minute):
```bash
# Check "Cache Hit/Miss Ratios" panel
# Hit rate should increase to > 90%
```

---

### Issue 2: Low Cache Hit Rate (< 90%)

**Diagnosis** (30 seconds):
```bash
# Check APM dashboard → "Cache Hit/Miss Ratios by Type"
```

**Fix** (3 minutes):
```php
// Increase cache TTL
Cache::remember('key', 3600, fn() => expensiveQuery());  // 1 hour

// Add cache tags for easier invalidation
Cache::tags(['sites', 'user-123'])->remember('sites', 3600, fn() => ...);

// Invalidate specific tags when data changes
Cache::tags(['sites'])->flush();
```

---

### Issue 3: Slow Database Queries (p95 > 100ms)

**Diagnosis** (1 minute):
```bash
# Check Database dashboard → "Slowest Queries by Table"
```

**Fix** (5 minutes):
```sql
-- Check query plan
EXPLAIN SELECT * FROM sites WHERE created_at > '2024-01-01' AND status = 'active';

-- Add composite index
CREATE INDEX idx_sites_created_status ON sites(created_at, status);

-- Verify improvement
EXPLAIN SELECT * FROM sites WHERE created_at > '2024-01-01' AND status = 'active';
-- Should show: type: range, key: idx_sites_created_status
```

---

### Issue 4: Poor LCP (> 2.5s)

**Diagnosis** (30 seconds):
```bash
# Check Frontend dashboard → "Core Web Vitals (p75)"
```

**Fix** (10 minutes):
```html
<!-- 1. Optimize largest image -->
<picture>
  <source srcset="/images/hero.webp" type="image/webp">
  <img src="/images/hero.jpg" alt="Hero" loading="eager" width="1200" height="600">
</picture>

<!-- 2. Preload critical resources -->
<link rel="preload" as="image" href="/images/hero.webp">

<!-- 3. Add CDN -->
<img src="https://cdn.example.com/images/hero.webp" alt="Hero">
```

---

### Issue 5: PHP-FPM Pool Exhaustion (> 80%)

**Diagnosis** (30 seconds):
```bash
# Check APM dashboard → "PHP-FPM Pool Utilization"
```

**Fix** (2 minutes):
```ini
# /etc/php/8.2/fpm/pool.d/chom.conf
pm.max_children = 50        # Increase from default
pm.start_servers = 10
pm.min_spare_servers = 5
pm.max_spare_servers = 15

# Restart PHP-FPM
sudo systemctl restart php8.2-fpm
```

---

## Performance Budget Reference

### Critical Thresholds (Red Alert)

| Metric | Threshold | Action Required |
|--------|-----------|-----------------|
| Response Time (p95) | > 1000ms | Immediate investigation |
| Cache Hit Rate | < 75% | Review cache strategy |
| Database Latency (p95) | > 500ms | Optimize queries/indexes |
| LCP | > 4s | Critical UX issue |
| PHP-FPM Utilization | > 90% | Scale workers |
| Deadlock Rate | > 5/hour | Fix transaction logic |

### Warning Thresholds (Yellow Alert)

| Metric | Threshold | Action Within |
|--------|-----------|---------------|
| Response Time (p95) | 500-1000ms | 24 hours |
| Cache Hit Rate | 75-90% | 1 week |
| Database Latency (p95) | 100-500ms | 48 hours |
| LCP | 2.5-4s | 1 week |
| PHP-FPM Utilization | 80-90% | 1 week |

### Target Performance (Green)

```
✓ Response Time (p95): < 300ms
✓ Cache Hit Rate: > 95%
✓ Database Latency (p95): < 50ms
✓ LCP: < 2.0s
✓ FID: < 50ms
✓ CLS: < 0.05
✓ PHP-FPM Utilization: < 70%
```

---

## Daily Monitoring Routine (5 minutes)

### Morning Check (2 minutes)

```bash
# 1. Check all dashboards for red panels
http://localhost:3000/d/chom-apm-performance
http://localhost:3000/d/chom-database-performance
http://localhost:3000/d/chom-frontend-performance

# 2. Review error logs
tail -100 storage/logs/laravel.log | grep ERROR

# 3. Check queue depth
php artisan queue:monitor
```

### Weekly Review (30 minutes)

```bash
# 1. Run load test
cd /home/calounx/repositories/mentat/chom/tests/load
./run-load-tests.sh weekly

# 2. Review slow query log
mysqldumpslow -s t -t 20 /var/log/mysql/slow.log

# 3. Check for optimization opportunities
# - Cache hit rates by type
# - Slowest endpoints (top 10)
# - Slowest queries (top 10)
# - Pages with poor Core Web Vitals

# 4. Update performance tracking document
```

---

## Emergency Response

### Site is Slow (Response Time Spiking)

```bash
# 1. Quick diagnosis (30 seconds)
curl -w "@curl-format.txt" https://chom.example.com/api/sites
# Shows: time_namelookup, time_connect, time_starttransfer, time_total

# 2. Check current load (30 seconds)
top -b -n 1 | head -20
mysql -e "SHOW PROCESSLIST;"

# 3. Quick fixes (1 minute)
# Clear application cache
php artisan cache:clear

# Restart queue workers
php artisan queue:restart

# Restart PHP-FPM if needed
sudo systemctl restart php8.2-fpm

# 4. Enable maintenance mode if critical
php artisan down --retry=60
```

### Database is Slow (High Query Times)

```bash
# 1. Check for long-running queries
mysql -e "SELECT * FROM information_schema.PROCESSLIST WHERE TIME > 10;"

# 2. Kill problematic queries
mysql -e "KILL <query_id>;"

# 3. Check for deadlocks
mysql -e "SHOW ENGINE INNODB STATUS\G" | grep -A 50 "LATEST DETECTED DEADLOCK"

# 4. Check connection pool
mysql -e "SHOW STATUS LIKE 'Threads%';"
```

### Frontend Performance Degraded

```bash
# 1. Run Lighthouse audit
lighthouse https://chom.example.com --view

# 2. Check CDN status
curl -I https://cdn.example.com

# 3. Clear browser cache directive
# Add to response headers
Cache-Control: no-cache, must-revalidate

# 4. Verify asset compression
curl -H "Accept-Encoding: gzip,deflate" -I https://chom.example.com/js/app.js | grep Content-Encoding
```

---

## Useful Commands Reference

### Grafana
```bash
# Restart Grafana
sudo systemctl restart grafana-server

# View Grafana logs
sudo journalctl -u grafana-server -f

# Backup dashboards
curl -H "Authorization: Bearer YOUR_API_KEY" \
  http://localhost:3000/api/search?type=dash-db | \
  jq -r '.[].uri' | \
  xargs -I {} curl -H "Authorization: Bearer YOUR_API_KEY" \
    http://localhost:3000/api/dashboards/{} > backup.json
```

### Prometheus
```bash
# Check Prometheus targets
curl http://localhost:9090/api/v1/targets

# Query metric
curl "http://localhost:9090/api/v1/query?query=up"

# Reload configuration
curl -X POST http://localhost:9090/-/reload

# Check configuration
promtool check config /etc/prometheus/prometheus.yml
```

### Performance Testing
```bash
# Quick load test
curl -w "@curl-format.txt" -o /dev/null -s https://chom.example.com

# Run k6 load test
k6 run --vus 10 --duration 30s test.js

# Lighthouse audit
lighthouse https://chom.example.com --output html --output-path report.html
```

---

## Next Steps

1. **Read the full guides**:
   - [Performance Troubleshooting Guide](./PERFORMANCE-TROUBLESHOOTING-GUIDE.md)
   - [README](./README.md)

2. **Set up alerts**:
   - Configure Grafana alerts for critical metrics
   - Set up Slack/email notifications

3. **Establish baseline**:
   - Run load tests to establish performance baseline
   - Document current metrics

4. **Schedule reviews**:
   - Add daily monitoring to routine
   - Schedule weekly performance reviews
   - Plan monthly optimization sprints

---

## Support

- **Documentation**: See `README.md` and `PERFORMANCE-TROUBLESHOOTING-GUIDE.md`
- **Issues**: GitHub Issues or DevOps team
- **Emergency**: Contact on-call engineer

---

**Last Updated**: 2026-01-02
**Version**: 1.0.0
