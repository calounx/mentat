# CHOM Load Testing Execution Guide

**Version:** 1.0.0
**Last Updated:** 2026-01-02
**Audience:** DevOps Engineers, Performance Engineers, QA Team

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Installation](#installation)
4. [Quick Start](#quick-start)
5. [Test Scenarios](#test-scenarios)
6. [Execution Commands](#execution-commands)
7. [Results Analysis](#results-analysis)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)

---

## Overview

This guide provides step-by-step instructions for executing load tests on the CHOM application using k6. The load testing framework validates that CHOM can handle production traffic levels with acceptable performance.

### What You'll Learn

- How to install and configure k6
- How to run different load testing scenarios
- How to analyze and interpret test results
- How to identify and troubleshoot performance issues

### Performance Goals

- **Response Time:** p95 < 500ms, p99 < 1000ms
- **Throughput:** > 100 requests/second
- **Error Rate:** < 0.1%
- **Concurrent Users:** 100+

---

## Prerequisites

### System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **CPU** | 2 cores | 4+ cores |
| **RAM** | 4 GB | 8+ GB |
| **Disk** | 10 GB free | 20+ GB free |
| **Network** | 10 Mbps | 100+ Mbps |

### Software Requirements

- **k6** v0.45.0 or later
- **Node.js** 18+ (for helper scripts)
- **Git** (for version control)
- **curl** (for API verification)
- **jq** (for JSON processing)

### Environment Access

- CHOM application running and accessible
- Database server healthy and optimized
- Redis cache server running
- Monitoring tools configured (Prometheus, Grafana)

---

## Installation

### 1. Install k6

#### macOS
```bash
brew install k6
```

#### Linux (Debian/Ubuntu)
```bash
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6
```

#### Linux (Fedora/CentOS)
```bash
sudo dnf install https://dl.k6.io/rpm/repo.rpm
sudo dnf install k6
```

#### Windows
```powershell
choco install k6
```

#### Docker
```bash
docker pull grafana/k6:latest
```

### 2. Verify Installation

```bash
k6 version
```

Expected output: `k6 v0.45.0 or later`

### 3. Install Helper Tools

```bash
# Install jq for JSON processing
sudo apt-get install jq  # Ubuntu/Debian
brew install jq          # macOS

# Verify jq installation
jq --version
```

---

## Quick Start

### 1. Navigate to Load Tests Directory

```bash
cd /home/calounx/repositories/mentat/chom/tests/load
```

### 2. Verify Application Health

```bash
# Check if CHOM is running
curl -s http://localhost:8000/api/v1/health | jq .

# Expected response:
# {
#   "status": "healthy",
#   "timestamp": "2026-01-02T12:00:00Z"
# }
```

### 3. Run Your First Load Test

```bash
# Run authentication flow test (quick validation)
k6 run scripts/auth-flow.js

# Expected output:
# ✓ Register: status is 201
# ✓ Login: status is 200
# ...
# http_req_duration..........: avg=250ms min=100ms max=500ms p(95)=400ms p(99)=450ms
```

### 4. Run Complete Test Suite

```bash
# Use the helper script to run all tests
./run-load-tests.sh --scenario all
```

---

## Test Scenarios

### Available Test Scripts

| Script | Purpose | Duration | Users | When to Use |
|--------|---------|----------|-------|-------------|
| **auth-flow.js** | Authentication testing | 12 min | 10→100 | Validate auth performance |
| **site-management.js** | Site CRUD operations | 15 min | 10→100 | Test site operations |
| **backup-operations.js** | Backup lifecycle | 13 min | 10→50 | Validate backup performance |

### Available Test Scenarios

| Scenario | Purpose | Duration | Pattern | When to Use |
|----------|---------|----------|---------|-------------|
| **ramp-up-test.js** | Capacity validation | 15 min | 10→50→100 | Before releases |
| **sustained-load-test.js** | Steady-state performance | 10 min | 100 constant | Daily validation |
| **spike-test.js** | Resilience testing | 5 min | 100→200→100 | Traffic spike prep |
| **soak-test.js** | Memory leak detection | 60 min | 50 constant | Weekly/monthly |
| **stress-test.js** | Breaking point discovery | 17 min | 0→500 | Capacity planning |

---

## Execution Commands

### Basic Execution

#### Run Single Test
```bash
k6 run scripts/auth-flow.js
```

#### Run with Custom Duration
```bash
k6 run --duration 5m scripts/auth-flow.js
```

#### Run with Custom VUs
```bash
k6 run --vus 50 --duration 10m scripts/site-management.js
```

### Advanced Execution

#### Run with Environment Variables
```bash
BASE_URL=http://staging.chom.local:8000 k6 run scripts/auth-flow.js
```

#### Run with Custom Thresholds
```bash
k6 run --threshold 'http_req_duration{percentile:95}<500' scripts/auth-flow.js
```

#### Run with Multiple Scenarios
```bash
k6 run scenarios/ramp-up-test.js scenarios/sustained-load-test.js
```

### Output Options

#### Save Results to JSON
```bash
k6 run --out json=results/auth-results.json scripts/auth-flow.js
```

#### Save Results to CSV
```bash
k6 run --out csv=results/auth-results.csv scripts/auth-flow.js
```

#### Send Results to InfluxDB
```bash
k6 run --out influxdb=http://localhost:8086/k6 scripts/auth-flow.js
```

#### Multiple Output Formats
```bash
k6 run \
  --out json=results/results.json \
  --out influxdb=http://localhost:8086/k6 \
  scripts/auth-flow.js
```

### Docker Execution

#### Run Test in Docker
```bash
docker run --rm -i \
  -v $(pwd):/scripts \
  grafana/k6:latest \
  run /scripts/scripts/auth-flow.js
```

#### Run with Environment Variables
```bash
docker run --rm -i \
  -e BASE_URL=http://host.docker.internal:8000 \
  -v $(pwd):/scripts \
  grafana/k6:latest \
  run /scripts/scripts/auth-flow.js
```

---

## Scenario-Specific Commands

### 1. Ramp-Up Test
**Purpose:** Validate smooth scaling from 10 to 100 users

```bash
# Standard execution
k6 run scenarios/ramp-up-test.js

# With monitoring
k6 run \
  --out influxdb=http://localhost:8086/k6 \
  scenarios/ramp-up-test.js
```

**Expected Results:**
- p95 < 500ms throughout ramp
- Error rate < 0.1%
- No resource saturation

### 2. Sustained Load Test
**Purpose:** Verify steady-state performance with 100 users

```bash
# Standard execution
k6 run scenarios/sustained-load-test.js

# Extended duration (30 minutes)
k6 run --duration 30m scenarios/sustained-load-test.js
```

**Expected Results:**
- Stable response times
- No memory leaks
- Consistent throughput

### 3. Spike Test
**Purpose:** Test resilience under sudden traffic spike

```bash
# Standard execution
k6 run scenarios/spike-test.js

# Monitor recovery
k6 run \
  --out json=results/spike-test-recovery.json \
  scenarios/spike-test.js
```

**Expected Results:**
- System remains functional
- Graceful degradation
- Quick recovery

### 4. Soak Test
**Purpose:** Detect memory leaks over 1 hour

```bash
# Standard execution (1 hour)
k6 run scenarios/soak-test.js

# Extended soak (4 hours)
k6 run --duration 4h scenarios/soak-test.js
```

**Expected Results:**
- No performance degradation
- Stable resource utilization
- No connection leaks

### 5. Stress Test
**Purpose:** Find breaking point

```bash
# Standard execution
k6 run scenarios/stress-test.js

# Find exact capacity limit
k6 run \
  --out json=results/stress-test-limits.json \
  scenarios/stress-test.js
```

**Expected Results:**
- Identify breaking point
- Document failure modes
- Graceful degradation

---

## Results Analysis

### Reading Test Output

#### Understanding k6 Output

```
     ✓ checks.........................: 99.95% ✓ 9995      ✗ 5
     data_received...................: 15 MB  500 kB/s
     data_sent.......................: 5 MB   167 kB/s
     http_req_blocked...............: avg=1.2ms    min=0.5ms   med=1ms     max=15ms    p(90)=2ms     p(95)=3ms
     http_req_connecting............: avg=0.8ms    min=0.3ms   med=0.7ms   max=10ms    p(90)=1.5ms   p(95)=2ms
   ✓ http_req_duration..............: avg=250ms    min=50ms    med=200ms   max=1500ms  p(90)=400ms   p(95)=450ms
     http_req_failed................: 0.05%  ✓ 5         ✗ 9995
   ✓ http_req_receiving.............: avg=0.5ms    min=0.1ms   med=0.4ms   max=5ms     p(90)=1ms     p(95)=1.5ms
     http_req_sending...............: avg=0.3ms    min=0.1ms   med=0.2ms   max=3ms     p(90)=0.5ms   p(95)=0.8ms
     http_req_tls_handshaking.......: avg=0ms      min=0ms     med=0ms     max=0ms     p(90)=0ms     p(95)=0ms
     http_req_waiting...............: avg=249ms    min=49ms    med=199ms   max=1499ms  p(90)=399ms   p(95)=449ms
   ✓ http_reqs......................: 10000  333.33/s
     iteration_duration.............: avg=3s       min=1s      med=2.5s    max=8s      p(90)=4s      p(95)=5s
     iterations.....................: 1000   33.33/iter
     vus............................: 100    min=10      max=100
     vus_max........................: 100    min=100     max=100
```

#### Key Metrics Explained

| Metric | Description | Good Value |
|--------|-------------|------------|
| **http_req_duration (p95)** | 95% of requests faster than this | < 500ms |
| **http_req_duration (p99)** | 99% of requests faster than this | < 1000ms |
| **http_req_failed** | Percentage of failed requests | < 0.1% |
| **http_reqs** | Total requests and rate | > 100/s |
| **checks** | Percentage of passed assertions | > 99.9% |

### Analyzing JSON Results

```bash
# Extract key metrics from JSON results
cat results/results.json | jq '
  .metrics | {
    avg_duration: .http_req_duration.values.avg,
    p95_duration: .http_req_duration.values["p(95)"],
    p99_duration: .http_req_duration.values["p(99)"],
    error_rate: .http_req_failed.values.rate,
    throughput: .http_reqs.values.rate
  }
'
```

### Performance Comparison

```bash
# Compare two test runs
./scripts/compare-results.sh results/baseline.json results/current.json
```

---

## Monitoring During Tests

### Real-Time Monitoring

#### Watch k6 Output
```bash
k6 run --summary-trend-stats="avg,min,med,max,p(95),p(99)" scenarios/ramp-up-test.js
```

#### Monitor System Resources
```bash
# In separate terminal
watch -n 1 'ps aux | grep php | grep -v grep'
watch -n 1 'free -m'
watch -n 1 'netstat -an | grep :8000 | wc -l'
```

#### Monitor Database
```bash
# MySQL connections
watch -n 1 'mysql -e "SHOW STATUS LIKE \"Threads_connected\""'

# PostgreSQL connections
watch -n 1 'psql -c "SELECT count(*) FROM pg_stat_activity"'
```

#### Monitor Application Logs
```bash
tail -f /home/calounx/repositories/mentat/chom/storage/logs/laravel.log
```

### Prometheus Metrics

If Prometheus is configured, monitor:

```bash
# Application metrics
curl http://localhost:9090/api/v1/query?query=chom_http_request_duration_seconds

# System metrics
curl http://localhost:9090/api/v1/query?query=node_cpu_seconds_total
```

---

## Troubleshooting

### Common Issues

#### Issue: Connection Refused
```
Error: connection refused
```

**Solution:**
```bash
# Verify CHOM is running
curl http://localhost:8000/api/v1/health

# Check port availability
netstat -tuln | grep 8000

# Restart CHOM if needed
cd /home/calounx/repositories/mentat/chom
php artisan serve
```

#### Issue: High Error Rate
```
http_req_failed: 5.2% ✓ 520 ✗ 9480
```

**Solution:**
```bash
# Check application logs
tail -100 /home/calounx/repositories/mentat/chom/storage/logs/laravel.log

# Check database connections
mysql -e "SHOW PROCESSLIST"

# Review error distribution
cat results/results.json | jq '.metrics.http_req_failed'
```

#### Issue: Slow Response Times
```
http_req_duration: avg=2500ms p(95)=5000ms
```

**Solution:**
```bash
# Check database slow queries
mysql -e "SHOW FULL PROCESSLIST"

# Monitor CPU usage
top -p $(pgrep php)

# Check cache status
redis-cli INFO stats

# Review application profiling
# Enable Laravel Telescope or Debugbar
```

#### Issue: Rate Limiting Errors
```
http_req_failed: 429 Too Many Requests
```

**Solution:**
```bash
# Adjust rate limits in .env
CHOM_API_RATE_LIMIT=120

# Or use lower VU count
k6 run --vus 25 scripts/auth-flow.js
```

#### Issue: Memory Exhaustion
```
Error: insufficient memory
```

**Solution:**
```bash
# Increase PHP memory limit
echo "memory_limit = 512M" >> /etc/php/8.2/cli/php.ini

# Restart PHP-FPM
sudo systemctl restart php8.2-fpm

# Monitor memory during test
watch -n 1 free -m
```

---

## Best Practices

### Before Running Tests

1. **Prepare Environment**
   ```bash
   # Optimize database
   php artisan optimize
   php artisan cache:clear
   php artisan config:cache

   # Warm up cache
   curl http://localhost:8000/api/v1/sites
   ```

2. **Verify Baseline**
   ```bash
   # Run health check
   k6 run --vus 1 --duration 30s scripts/auth-flow.js
   ```

3. **Set Up Monitoring**
   ```bash
   # Start monitoring in separate terminals
   tail -f storage/logs/laravel.log
   htop
   watch 'redis-cli INFO stats'
   ```

### During Tests

1. **Monitor Key Metrics**
   - Response times (p95, p99)
   - Error rates
   - Resource utilization
   - Database connections

2. **Watch for Anomalies**
   - Sudden error spikes
   - Memory leaks
   - Connection pool exhaustion
   - Disk I/O saturation

3. **Document Observations**
   - Record when issues occur
   - Note load levels at failure points
   - Capture error messages

### After Tests

1. **Analyze Results**
   ```bash
   # Generate summary report
   ./scripts/generate-report.sh results/
   ```

2. **Compare with Baselines**
   ```bash
   # Compare with previous test
   ./scripts/compare-results.sh results/baseline.json results/current.json
   ```

3. **Document Findings**
   - Update PERFORMANCE-OPTIMIZATION-REPORT.md
   - Record bottlenecks identified
   - List recommendations

### Testing Schedule

| Test Type | Frequency | Purpose |
|-----------|-----------|---------|
| **Smoke Test** | Every deploy | Quick validation |
| **Sustained Load** | Daily | Regression detection |
| **Ramp-Up** | Weekly | Capacity validation |
| **Spike** | Weekly | Resilience testing |
| **Soak** | Monthly | Memory leak detection |
| **Stress** | Monthly | Capacity planning |

---

## Helper Scripts

### Available Scripts

| Script | Purpose |
|--------|---------|
| **run-load-tests.sh** | Execute test suites |
| **compare-results.sh** | Compare test results |
| **generate-report.sh** | Create HTML reports |
| **monitor-test.sh** | Real-time monitoring |

### Usage Examples

```bash
# Run specific scenario
./run-load-tests.sh --scenario ramp-up

# Run all tests
./run-load-tests.sh --scenario all

# Run with custom config
./run-load-tests.sh --config production.env --scenario sustained

# Generate comparison report
./compare-results.sh results/baseline.json results/current.json > comparison-report.md
```

---

## Next Steps

After completing load testing:

1. Review [PERFORMANCE-BASELINES.md](./PERFORMANCE-BASELINES.md) for targets
2. Read [PERFORMANCE-OPTIMIZATION-REPORT.md](./PERFORMANCE-OPTIMIZATION-REPORT.md) for recommendations
3. Implement optimizations based on findings
4. Re-run tests to validate improvements
5. Document baseline metrics for future comparisons

---

## Support & Resources

### Documentation
- k6 Documentation: https://k6.io/docs/
- CHOM API Documentation: `/home/calounx/repositories/mentat/chom/docs/API-README.md`

### Useful Commands Reference

```bash
# Quick health check
curl http://localhost:8000/api/v1/health | jq .

# Check Laravel queue
php artisan queue:work --once

# Clear all caches
php artisan optimize:clear

# View routes
php artisan route:list

# Check database connection
php artisan tinker --execute="DB::connection()->getPdo()"
```

---

**Last Updated:** 2026-01-02
**Maintainer:** DevOps Team
**Version:** 1.0.0
