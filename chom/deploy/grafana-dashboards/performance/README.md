# CHOM Performance Optimization Grafana Dashboards

## Overview

This directory contains three comprehensive Grafana dashboards specifically designed for CHOM performance monitoring and optimization:

1. **APM (Application Performance Monitoring) Dashboard** - Application-level performance metrics
2. **Database Performance Dashboard** - Database query optimization and health monitoring
3. **Frontend Performance Dashboard** - Core Web Vitals and Real User Monitoring (RUM)

These dashboards are engineered to help identify performance bottlenecks, track optimization progress, and maintain performance budgets across the CHOM application stack.

## Dashboard Files

```
performance/
├── 1-apm-dashboard.json                          # Application Performance Monitoring
├── 2-database-performance-dashboard.json         # Database Performance
├── 3-frontend-performance-dashboard.json         # Frontend & Core Web Vitals
├── PERFORMANCE-TROUBLESHOOTING-GUIDE.md         # Comprehensive troubleshooting guide
└── README.md                                     # This file
```

## Installation

### 1. Import Dashboards into Grafana

**Via Grafana UI**:
```bash
# 1. Login to Grafana (default: http://localhost:3000)
# 2. Navigate to: Dashboards → Import
# 3. Upload JSON file or paste JSON content
# 4. Select Prometheus data source
# 5. Click "Import"
```

**Via Grafana API**:
```bash
# Import all performance dashboards
for dashboard in 1-apm-dashboard.json 2-database-performance-dashboard.json 3-frontend-performance-dashboard.json; do
  curl -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer YOUR_API_KEY" \
    -d @"$dashboard" \
    http://localhost:3000/api/dashboards/db
done
```

**Via Provisioning** (recommended for automation):
```bash
# 1. Copy dashboards to Grafana provisioning directory
sudo mkdir -p /etc/grafana/provisioning/dashboards/performance
sudo cp *.json /etc/grafana/provisioning/dashboards/performance/

# 2. Create provisioning config
cat <<EOF | sudo tee /etc/grafana/provisioning/dashboards/performance.yaml
apiVersion: 1

providers:
  - name: 'CHOM Performance'
    orgId: 1
    folder: 'CHOM Performance'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards/performance
EOF

# 3. Restart Grafana
sudo systemctl restart grafana-server
```

### 2. Configure Prometheus Data Source

Ensure Prometheus is configured with the correct scrape targets:

```yaml
# /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # CHOM Application Metrics
  - job_name: 'chom-app'
    static_configs:
      - targets: ['localhost:9090']
    metrics_path: /metrics

  # PHP-FPM Metrics (via php-fpm-exporter)
  - job_name: 'php-fpm'
    static_configs:
      - targets: ['localhost:9253']

  # MySQL Metrics (via mysqld_exporter)
  - job_name: 'mysql'
    static_configs:
      - targets: ['localhost:9104']

  # Node Exporter (System Metrics)
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']

  # Frontend RUM Metrics (via custom endpoint)
  - job_name: 'frontend-rum'
    static_configs:
      - targets: ['localhost:8080']
    metrics_path: /rum/metrics
```

### 3. Required Exporters

Install and configure these exporters for full dashboard functionality:

**PHP-FPM Exporter**:
```bash
# Install via Docker
docker run -d \
  --name php-fpm-exporter \
  -p 9253:9253 \
  hipages/php-fpm_exporter:latest \
  --phpfpm.scrape-uri tcp://php-fpm:9000/status

# Or install binary
wget https://github.com/hipages/php-fpm_exporter/releases/download/v2.2.0/php-fpm_exporter_2.2.0_linux_amd64.tar.gz
tar xvfz php-fpm_exporter_2.2.0_linux_amd64.tar.gz
sudo mv php-fpm_exporter /usr/local/bin/
```

**MySQL Exporter**:
```bash
# Install via Docker
docker run -d \
  --name mysqld-exporter \
  -p 9104:9104 \
  -e DATA_SOURCE_NAME="exporter:password@(localhost:3306)/" \
  prom/mysqld-exporter:latest

# Create MySQL user for exporter
mysql -u root -p <<EOF
CREATE USER 'exporter'@'localhost' IDENTIFIED BY 'password' WITH MAX_USER_CONNECTIONS 3;
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';
FLUSH PRIVILEGES;
EOF
```

**Node Exporter**:
```bash
# Install via package manager
sudo apt-get install prometheus-node-exporter

# Or via Docker
docker run -d \
  --name node-exporter \
  -p 9100:9100 \
  prom/node-exporter:latest
```

## Dashboard Details

### 1. APM (Application Performance Monitoring) Dashboard

**Purpose**: Monitor application-level performance, identify slow endpoints, and optimize caching strategies.

**Key Panels**:
- **Endpoint Performance Heatmap**: Visual representation of endpoint latency distribution
- **Slow Query Detection**: Trending of database queries exceeding thresholds
- **Cache Hit/Miss Ratios**: Performance by cache type (Redis, OPcache, Query, Application, View)
- **Queue Job Processing Times**: Background job performance by type
- **Memory Usage Per Request**: Detect memory leaks and inefficient code
- **PHP-FPM Pool Utilization**: Monitor worker pool saturation
- **OPcache Statistics**: PHP bytecode cache efficiency
- **Session Handling Performance**: Session creation, destruction, and write times

**Performance Budgets**:
```
✓ P95 Response Time: < 500ms (Warning: 500-1000ms, Critical: >1000ms)
✓ Cache Hit Rate: > 90% (Warning: 75-90%, Critical: <75%)
✓ Queue Processing: < 5s per job (Warning: 5-10s, Critical: >10s)
✓ PHP-FPM Pool: < 80% utilization (Warning: 80-90%, Critical: >90%)
✓ OPcache Hit Rate: > 95% (Warning: 90-95%, Critical: <90%)
✓ Memory per Request: < 50MB (Warning: 50-100MB, Critical: >100MB)
```

**Use Cases**:
- Identify and optimize slow API endpoints
- Tune cache configuration and TTL strategies
- Optimize background job processing
- Right-size PHP-FPM worker pools
- Detect memory leaks

**Variables**:
- `$endpoint`: Filter by API endpoint path
- `$cache_type`: Filter by cache type (Redis, OPcache, etc.)

---

### 2. Database Performance Dashboard

**Purpose**: Optimize database queries, prevent deadlocks, and ensure efficient index usage.

**Key Panels**:
- **Query Latency Distribution**: Percentile-based latency tracking (p50, p95, p99, p99.9)
- **Deadlock Detection**: Real-time deadlock monitoring with frequency analysis
- **Table Lock Wait Times**: Identify lock contention issues
- **Replication Lag**: Master-replica synchronization monitoring
- **Connection Pool Exhaustion**: Track connection usage and prevent exhaustion
- **Query Cache Effectiveness**: Cache hit rate and memory utilization
- **Index Usage Efficiency**: Full table scans vs. index usage ratio
- **Buffer Pool Hit Rate**: InnoDB buffer pool effectiveness
- **Slowest Queries by Table**: Top 10 optimization targets

**Performance Budgets**:
```
✓ Query Latency (p95): < 100ms (Warning: 100-500ms, Critical: >500ms)
✓ Deadlock Rate: < 1 per hour (Warning: 1-5/hr, Critical: >5/hr)
✓ Connection Pool: < 75% utilization (Warning: 75-90%, Critical: >90%)
✓ Buffer Pool Hit: > 99% (Warning: 95-99%, Critical: <95%)
✓ Index Efficiency: > 95% (Warning: 90-95%, Critical: <90%)
✓ Replication Lag: < 1s (Warning: 1-5s, Critical: >5s)
```

**Use Cases**:
- Identify and optimize slow database queries
- Resolve deadlock issues and transaction conflicts
- Optimize index strategy and prevent full table scans
- Tune InnoDB buffer pool size
- Monitor replication health

**Variables**:
- `$query_type`: Filter by query type (SELECT, INSERT, UPDATE, DELETE)
- `$table`: Filter by database table name

---

### 3. Frontend Performance & Core Web Vitals Dashboard

**Purpose**: Monitor user-perceived performance through Real User Monitoring (RUM) and optimize Core Web Vitals.

**Key Panels**:
- **Core Web Vitals (p75)**: LCP, FID, CLS monitoring per Google standards
- **Page Load Time Breakdown**: TTFB, FCP, LCP timeline
- **JavaScript Execution Time**: Script performance by type
- **API Call Latency from Frontend**: User-perceived API performance
- **Asset Load Times**: CSS, JavaScript, images, fonts performance
- **Browser Rendering Metrics**: DOM processing, layout, paint times
- **Core Web Vitals Distribution**: Percentage breakdown (Good/Needs Improvement/Poor)
- **Real User Monitoring Metrics**: Page views, unique users, session duration, bounce rate
- **Geographic Performance Breakdown**: Performance by country/region
- **Page Performance Comparison**: Identify slowest pages

**Performance Budgets (Core Web Vitals)**:
```
✓ LCP (Largest Contentful Paint): < 2.5s (Needs Improvement: 2.5-4s, Poor: >4s)
✓ FID (First Input Delay): < 100ms (Needs Improvement: 100-300ms, Poor: >300ms)
✓ CLS (Cumulative Layout Shift): < 0.1 (Needs Improvement: 0.1-0.25, Poor: >0.25)
✓ TTFB (Time to First Byte): < 600ms (Needs Improvement: 600-1500ms, Poor: >1500ms)
✓ FCP (First Contentful Paint): < 1.8s (Needs Improvement: 1.8-3s, Poor: >3s)
✓ API Latency: < 500ms (Warning: 500-1000ms, Critical: >1000ms)
```

**Use Cases**:
- Achieve Google Core Web Vitals "Good" ratings
- Optimize page load performance for users
- Reduce JavaScript execution time
- Improve API response times from user perspective
- Identify geographic performance issues

**Variables**:
- `$page`: Filter by page URL
- `$api_endpoint`: Filter by API endpoint
- `$country`: Filter by user country

---

## Performance Monitoring Workflow

### 1. Establish Baseline

```bash
# Run load test to establish baseline
cd /home/calounx/repositories/mentat/chom/tests/load
./run-load-tests.sh baseline

# Document baseline metrics
cat > baseline-$(date +%Y%m%d).txt <<EOF
Date: $(date)
Environment: Production

APM Metrics:
- P95 Response Time: 245ms
- Cache Hit Rate: 92%
- Queue Processing: 2.1s avg

Database Metrics:
- P95 Query Latency: 65ms
- Buffer Pool Hit: 99.2%
- Index Efficiency: 96%

Frontend Metrics:
- LCP (p75): 2.1s
- FID (p75): 75ms
- CLS (p75): 0.08
EOF
```

### 2. Monitor and Alert

Configure Grafana alerts for critical metrics:

```yaml
# Example alert configuration
apiVersion: 1
groups:
  - name: CHOM Performance Alerts
    interval: 1m
    rules:
      - alert: HighResponseTime
        expr: histogram_quantile(0.95, sum(rate(chom_http_request_duration_ms_bucket[5m])) by (le)) > 1000
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High response time detected"
          description: "P95 response time is {{ $value }}ms (threshold: 1000ms)"

      - alert: LowCacheHitRate
        expr: 100 * (rate(chom_cache_hits_total[5m]) / (rate(chom_cache_hits_total[5m]) + rate(chom_cache_misses_total[5m]))) < 75
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Low cache hit rate"
          description: "Cache hit rate is {{ $value }}% (threshold: 75%)"

      - alert: DatabaseDeadlocks
        expr: increase(mysql_global_status_innodb_deadlocks[1h]) > 5
        labels:
          severity: critical
        annotations:
          summary: "High deadlock rate detected"
          description: "{{ $value }} deadlocks in the last hour"

      - alert: PoorLCP
        expr: histogram_quantile(0.75, sum(rate(chom_frontend_lcp_ms_bucket[5m])) by (le)) > 4000
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "Poor LCP performance"
          description: "LCP p75 is {{ $value }}ms (threshold: 4000ms)"
```

### 3. Optimize and Validate

```bash
# 1. Identify bottleneck using dashboards
# Example: High response time on /api/sites endpoint

# 2. Apply optimization
# See PERFORMANCE-TROUBLESHOOTING-GUIDE.md for specific solutions

# 3. Run before/after comparison
./run-load-tests.sh comparison \
  --baseline baseline-20260102.json \
  --scenario api-sites

# 4. Validate improvement in Grafana
# Check metrics over last 24 hours vs. baseline
```

### 4. Continuous Monitoring

```bash
# Schedule regular performance tests
# /etc/cron.d/chom-performance-tests

# Daily performance baseline check (3 AM)
0 3 * * * chom cd /path/to/chom/tests/load && ./run-load-tests.sh daily

# Weekly comprehensive test (Sunday 2 AM)
0 2 * * 0 chom cd /path/to/chom/tests/load && ./run-load-tests.sh weekly

# Monthly regression check (1st of month, 1 AM)
0 1 1 * * chom cd /path/to/chom/tests/load && ./run-load-tests.sh regression
```

---

## Metric Collection Implementation

### Application Metrics (Laravel/PHP)

Add Prometheus metrics collection to your Laravel application:

```php
// app/Http/Middleware/PrometheusMetrics.php
namespace App\Http\Middleware;

use Closure;
use Illuminate\Support\Facades\Redis;

class PrometheusMetrics
{
    public function handle($request, Closure $next)
    {
        $start = microtime(true);
        $memoryStart = memory_get_usage(true);

        $response = $next($request);

        $duration = (microtime(true) - $start) * 1000; // milliseconds
        $memory = memory_get_usage(true) - $memoryStart;

        // Record metrics
        $this->recordMetrics([
            'path' => $request->path(),
            'method' => $request->method(),
            'status' => $response->status(),
            'duration' => $duration,
            'memory' => $memory,
        ]);

        return $response;
    }

    private function recordMetrics(array $metrics)
    {
        $labels = sprintf(
            'path="%s",method="%s",status="%d"',
            $metrics['path'],
            $metrics['method'],
            $metrics['status']
        );

        // Increment request counter
        Redis::hincrby('chom_http_requests_total', $labels, 1);

        // Record duration histogram
        $this->recordHistogram(
            'chom_http_request_duration_ms',
            $metrics['duration'],
            $labels
        );

        // Record memory histogram
        $this->recordHistogram(
            'chom_http_request_memory_bytes',
            $metrics['memory'],
            $labels
        );

        // Record errors
        if ($metrics['status'] >= 400) {
            $errorType = $metrics['status'] >= 500 ? '5xx' : '4xx';
            Redis::hincrby('chom_http_errors_total', "$labels,type=\"$errorType\"", 1);
        }
    }

    private function recordHistogram(string $metric, float $value, string $labels)
    {
        $buckets = [10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000];

        foreach ($buckets as $bucket) {
            if ($value <= $bucket) {
                Redis::hincrby("{$metric}_bucket", "$labels,le=\"$bucket\"", 1);
            }
        }

        Redis::hincrby("{$metric}_bucket", "$labels,le=\"+Inf\"", 1);
        Redis::hincrbyfloat("{$metric}_sum", $labels, $value);
        Redis::hincrby("{$metric}_count", $labels, 1);
    }
}
```

### Frontend RUM Metrics Collection

```javascript
// resources/js/performance-monitoring.js

class PerformanceMonitor {
  constructor() {
    this.metrics = [];
    this.init();
  }

  init() {
    // Core Web Vitals
    this.measureLCP();
    this.measureFID();
    this.measureCLS();

    // Additional metrics
    this.measureTTFB();
    this.measureFCP();
    this.measureJavaScriptExecution();

    // Send metrics periodically
    setInterval(() => this.sendMetrics(), 30000); // Every 30 seconds
  }

  measureLCP() {
    new PerformanceObserver((list) => {
      const entries = list.getEntries();
      const lastEntry = entries[entries.length - 1];

      this.metrics.push({
        name: 'lcp',
        value: lastEntry.startTime,
        element: lastEntry.element?.tagName,
      });
    }).observe({ entryTypes: ['largest-contentful-paint'] });
  }

  measureFID() {
    new PerformanceObserver((list) => {
      const firstInput = list.getEntries()[0];

      this.metrics.push({
        name: 'fid',
        value: firstInput.processingStart - firstInput.startTime,
        eventType: firstInput.name,
      });
    }).observe({ entryTypes: ['first-input'] });
  }

  measureCLS() {
    let clsScore = 0;

    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        if (!entry.hadRecentInput) {
          clsScore += entry.value;
        }
      }

      this.metrics.push({
        name: 'cls',
        value: clsScore,
      });
    }).observe({ entryTypes: ['layout-shift'] });
  }

  measureTTFB() {
    const navigationEntry = performance.getEntriesByType('navigation')[0];

    this.metrics.push({
      name: 'ttfb',
      value: navigationEntry.responseStart - navigationEntry.requestStart,
    });
  }

  measureFCP() {
    new PerformanceObserver((list) => {
      const entries = list.getEntries();
      const fcpEntry = entries.find(entry => entry.name === 'first-contentful-paint');

      if (fcpEntry) {
        this.metrics.push({
          name: 'fcp',
          value: fcpEntry.startTime,
        });
      }
    }).observe({ entryTypes: ['paint'] });
  }

  measureJavaScriptExecution() {
    const scripts = performance.getEntriesByType('resource')
      .filter(entry => entry.initiatorType === 'script');

    const totalDuration = scripts.reduce((sum, script) => sum + script.duration, 0);

    this.metrics.push({
      name: 'js_execution',
      value: totalDuration,
      scriptCount: scripts.length,
    });
  }

  async sendMetrics() {
    if (this.metrics.length === 0) return;

    const payload = {
      page: window.location.pathname,
      metrics: this.metrics,
      userAgent: navigator.userAgent,
      country: await this.getCountry(),
      timestamp: Date.now(),
    };

    try {
      await fetch('/api/rum/metrics', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });

      this.metrics = []; // Clear sent metrics
    } catch (error) {
      console.error('Failed to send RUM metrics:', error);
    }
  }

  async getCountry() {
    try {
      const response = await fetch('https://ipapi.co/json/');
      const data = await response.json();
      return data.country_code;
    } catch {
      return 'UNKNOWN';
    }
  }
}

// Initialize on page load
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', () => new PerformanceMonitor());
} else {
  new PerformanceMonitor();
}
```

---

## Troubleshooting

### Dashboards Not Loading

**Issue**: Dashboards show "No data" or fail to load

**Solutions**:
```bash
# 1. Verify Prometheus is scraping metrics
curl http://localhost:9090/api/v1/targets

# 2. Check if metrics exist
curl http://localhost:9090/api/v1/query?query=chom_http_requests_total

# 3. Verify data source configuration in Grafana
curl -H "Authorization: Bearer YOUR_API_KEY" \
  http://localhost:3000/api/datasources

# 4. Check Grafana logs
sudo journalctl -u grafana-server -f

# 5. Verify Prometheus configuration
promtool check config /etc/prometheus/prometheus.yml
```

### Missing Metrics

**Issue**: Specific panels show "No data"

**Check metric availability**:
```bash
# List all available metrics
curl -s http://localhost:9090/api/v1/label/__name__/values | jq .

# Check specific metric
curl "http://localhost:9090/api/v1/query?query=chom_cache_hits_total"
```

**Ensure exporters are running**:
```bash
# Check PHP-FPM exporter
curl http://localhost:9253/metrics | grep phpfpm

# Check MySQL exporter
curl http://localhost:9104/metrics | grep mysql

# Check node exporter
curl http://localhost:9100/metrics | grep node
```

### Performance Alerts Not Firing

**Issue**: Alerts configured but not triggering

**Debug alert rules**:
```bash
# Check alert rule status
curl http://localhost:9090/api/v1/rules

# Test alert expression
curl "http://localhost:9090/api/v1/query?query=histogram_quantile(0.95,%20sum(rate(chom_http_request_duration_ms_bucket[5m]))%20by%20(le))%20>%201000"

# Check Grafana alert status
curl -H "Authorization: Bearer YOUR_API_KEY" \
  http://localhost:3000/api/alerts
```

---

## Best Practices

### 1. Regular Review Cadence

```markdown
## Daily
- [ ] Review APM dashboard for anomalies
- [ ] Check error rates and response times
- [ ] Verify queue processing is healthy

## Weekly
- [ ] Review database slow query log
- [ ] Check cache hit rates and optimize TTL
- [ ] Review Core Web Vitals trends
- [ ] Run load tests against baseline

## Monthly
- [ ] Comprehensive performance audit
- [ ] Update performance budgets
- [ ] Review and optimize indexes
- [ ] Capacity planning review
```

### 2. Performance Budget Management

Create and enforce performance budgets:

```javascript
// lighthouse-budget.json
[
  {
    "path": "/*",
    "resourceSizes": [
      { "resourceType": "script", "budget": 200 },
      { "resourceType": "stylesheet", "budget": 50 },
      { "resourceType": "image", "budget": 500 },
      { "resourceType": "total", "budget": 1000 }
    ],
    "resourceCounts": [
      { "resourceType": "third-party", "budget": 10 }
    ]
  }
]

// Run in CI/CD
// lighthouse https://chom.example.com --budget-path=lighthouse-budget.json
```

### 3. Documentation and Knowledge Sharing

- Document all optimizations in `/docs/performance-optimizations/`
- Share performance wins in team meetings
- Create runbooks for common performance issues
- Maintain changelog of performance-related changes

---

## Support and Contribution

### Getting Help

1. Check the [Performance Troubleshooting Guide](./PERFORMANCE-TROUBLESHOOTING-GUIDE.md)
2. Review existing GitHub issues
3. Contact DevOps team: devops@chom.example.com

### Contributing Improvements

```bash
# Fork repository and create feature branch
git checkout -b feature/dashboard-improvement

# Make changes to dashboards
# Test thoroughly in development environment

# Submit pull request with:
# - Description of changes
# - Before/after screenshots
# - Performance impact analysis
```

---

## Additional Resources

- [CHOM Performance Troubleshooting Guide](./PERFORMANCE-TROUBLESHOOTING-GUIDE.md)
- [CHOM Load Testing Guide](../../tests/load/LOAD-TESTING-GUIDE.md)
- [Grafana Documentation](https://grafana.com/docs/)
- [Prometheus Best Practices](https://prometheus.io/docs/practices/)
- [Core Web Vitals](https://web.dev/vitals/)

---

**Last Updated**: 2026-01-02
**Version**: 1.0.0
**Maintained by**: CHOM DevOps Team
