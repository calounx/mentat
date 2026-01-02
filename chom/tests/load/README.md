# CHOM Load Testing Framework

Comprehensive k6-based load testing framework for validating CHOM application performance and production readiness.

## Overview

This framework provides a complete load testing solution including:
- **Test Scripts** for authentication, site management, and backup operations
- **Test Scenarios** for different load patterns (ramp-up, sustained, spike, soak, stress)
- **Performance Baselines** and SLA targets
- **Execution Scripts** for automated testing
- **Analysis Tools** for results interpretation

## Quick Start

### 1. Install k6

```bash
# macOS
brew install k6

# Linux (Debian/Ubuntu)
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6

# Windows
choco install k6
```

### 2. Verify CHOM is Running

```bash
curl http://localhost:8000/api/v1/health
```

### 3. Run Your First Test

```bash
# Quick authentication test
k6 run scripts/auth-flow.js

# Or use the helper script
./run-load-tests.sh --scenario auth
```

## Directory Structure

```
tests/load/
├── scripts/                    # Individual test scripts
│   ├── auth-flow.js           # Authentication flow testing
│   ├── site-management.js     # Site CRUD operations
│   └── backup-operations.js   # Backup lifecycle testing
│
├── scenarios/                  # Test scenarios
│   ├── ramp-up-test.js        # Capacity validation (10→100 users)
│   ├── sustained-load-test.js # Steady-state test (100 users)
│   ├── spike-test.js          # Resilience test (100→200 spike)
│   ├── soak-test.js           # Memory leak detection (60 min)
│   └── stress-test.js         # Breaking point discovery (0→500)
│
├── utils/                      # Shared utilities
│   └── helpers.js             # Common test functions
│
├── data/                       # Test data
│   └── (generated at runtime)
│
├── results/                    # Test results
│   └── (output files)
│
├── k6.config.js               # Global configuration
├── run-load-tests.sh          # Test execution script
│
├── LOAD-TESTING-GUIDE.md      # Comprehensive execution guide
├── PERFORMANCE-BASELINES.md   # SLA targets and thresholds
└── PERFORMANCE-OPTIMIZATION-REPORT.md  # Optimization recommendations
```

## Available Tests

### Test Scripts

| Script | Purpose | Duration | Users |
|--------|---------|----------|-------|
| **auth-flow.js** | Authentication testing | 12 min | 10→100 |
| **site-management.js** | Site CRUD operations | 15 min | 10→100 |
| **backup-operations.js** | Backup lifecycle | 13 min | 10→50 |

### Test Scenarios

| Scenario | Purpose | Duration | Pattern |
|----------|---------|----------|---------|
| **ramp-up-test.js** | Capacity validation | 15 min | 10→50→100 |
| **sustained-load-test.js** | Steady-state performance | 10 min | 100 constant |
| **spike-test.js** | Resilience testing | 5 min | 100→200→100 |
| **soak-test.js** | Memory leak detection | 60 min | 50 constant |
| **stress-test.js** | Breaking point discovery | 17 min | 0→500 |

## Usage Examples

### Basic Execution

```bash
# Run authentication flow test
k6 run scripts/auth-flow.js

# Run site management test
k6 run scripts/site-management.js

# Run backup operations test
k6 run scripts/backup-operations.js
```

### Scenario Execution

```bash
# Ramp-up test (capacity validation)
k6 run scenarios/ramp-up-test.js

# Sustained load test (steady-state)
k6 run scenarios/sustained-load-test.js

# Spike test (resilience)
k6 run scenarios/spike-test.js

# Soak test (memory leaks)
k6 run scenarios/soak-test.js

# Stress test (breaking point)
k6 run scenarios/stress-test.js
```

### Using Helper Script

```bash
# Run specific scenario
./run-load-tests.sh --scenario auth
./run-load-tests.sh --scenario ramp-up

# Run all tests
./run-load-tests.sh --scenario all

# Custom configuration
./run-load-tests.sh \
  --scenario sustained \
  --base-url http://staging:8000 \
  --vus 50 \
  --duration 5m
```

### Advanced Options

```bash
# Save results to JSON
k6 run --out json=results/auth-results.json scripts/auth-flow.js

# Run against different environment
BASE_URL=http://staging:8000 k6 run scripts/auth-flow.js

# Override duration and VUs
k6 run --vus 50 --duration 10m scripts/site-management.js

# Send results to InfluxDB
k6 run --out influxdb=http://localhost:8086/k6 scenarios/ramp-up-test.js
```

## Performance Targets

| Metric | Target | Critical |
|--------|--------|----------|
| **Response Time (p95)** | < 500ms | < 800ms |
| **Response Time (p99)** | < 1000ms | < 1500ms |
| **Error Rate** | < 0.1% | < 1% |
| **Throughput** | > 100 req/s | > 80 req/s |
| **Concurrent Users** | 100+ | 50+ |

## Test Results Analysis

### Reading k6 Output

Key metrics to monitor:
- **http_req_duration (p95/p99)**: Response time percentiles
- **http_req_failed**: Error rate
- **http_reqs**: Request rate (throughput)
- **checks**: Assertion pass rate

### Success Criteria

A test passes when:
- ✓ p95 response time < 500ms
- ✓ p99 response time < 1000ms
- ✓ Error rate < 0.1%
- ✓ Throughput > 100 req/s
- ✓ Check pass rate > 99.9%

## Documentation

| Document | Description |
|----------|-------------|
| **[LOAD-TESTING-GUIDE.md](./LOAD-TESTING-GUIDE.md)** | Comprehensive execution guide |
| **[PERFORMANCE-BASELINES.md](./PERFORMANCE-BASELINES.md)** | SLA targets and thresholds |
| **[PERFORMANCE-OPTIMIZATION-REPORT.md](./PERFORMANCE-OPTIMIZATION-REPORT.md)** | Optimization recommendations |

## Troubleshooting

### Common Issues

**Connection Refused**
```bash
# Verify CHOM is running
curl http://localhost:8000/api/v1/health

# Start CHOM if needed
cd /home/calounx/repositories/mentat/chom
php artisan serve
```

**High Error Rate**
```bash
# Check application logs
tail -f /home/calounx/repositories/mentat/chom/storage/logs/laravel.log

# Check database connections
mysql -e "SHOW PROCESSLIST"
```

**Slow Response Times**
```bash
# Monitor system resources
htop

# Check cache status
redis-cli INFO stats

# Review slow queries
mysql -e "SHOW FULL PROCESSLIST"
```

## Best Practices

### Before Testing
1. Ensure CHOM is running in production mode
2. Database is optimized with indexes
3. Cache is configured and warmed
4. Monitoring tools are ready

### During Testing
1. Monitor system resources
2. Watch application logs
3. Track error rates
4. Note any anomalies

### After Testing
1. Analyze results against baselines
2. Compare with previous tests
3. Document findings
4. Implement optimizations

## Testing Schedule

| Test Type | Frequency | Purpose |
|-----------|-----------|---------|
| **Smoke Test** | Every deploy | Quick validation |
| **Load Test** | Daily | Regression detection |
| **Stress Test** | Weekly | Capacity planning |
| **Soak Test** | Monthly | Memory leak detection |

## Contributing

When adding new tests:
1. Follow the existing test structure
2. Include proper documentation
3. Set appropriate thresholds
4. Add to this README

## Support

For questions or issues:
- Review [LOAD-TESTING-GUIDE.md](./LOAD-TESTING-GUIDE.md)
- Check [PERFORMANCE-BASELINES.md](./PERFORMANCE-BASELINES.md)
- Consult the k6 documentation: https://k6.io/docs/

## License

MIT License - Part of the CHOM project

---

**Version:** 1.0.0
**Last Updated:** 2026-01-02
**Maintained By:** DevOps Team
