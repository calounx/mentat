# CHOM Load Testing - Quick Start Guide

## 1-Minute Setup

```bash
# Install k6
brew install k6  # macOS
# OR
sudo apt-get install k6  # Linux

# Navigate to tests
cd /home/calounx/repositories/mentat/chom/tests/load

# Verify CHOM is running
curl http://localhost:8000/api/v1/health

# Run your first test
./run-load-tests.sh --scenario auth
```

## Common Commands

```bash
# Quick validation tests
./run-load-tests.sh --scenario auth        # 12 min - Auth testing
./run-load-tests.sh --scenario sites       # 15 min - Site management
./run-load-tests.sh --scenario backups     # 13 min - Backup operations

# Load scenarios
./run-load-tests.sh --scenario ramp-up     # 15 min - Capacity test
./run-load-tests.sh --scenario sustained   # 10 min - Steady-state
./run-load-tests.sh --scenario spike       #  5 min - Resilience
./run-load-tests.sh --scenario soak        # 60 min - Memory leaks
./run-load-tests.sh --scenario stress      # 17 min - Breaking point

# Run all tests
./run-load-tests.sh --scenario all
```

## Performance Targets

| Metric | Target |
|--------|--------|
| Response Time (p95) | < 500ms |
| Response Time (p99) | < 1000ms |
| Error Rate | < 0.1% |
| Throughput | > 100 req/s |
| Concurrent Users | 100+ |

## Success Indicators

Look for these in test output:
```
✓ http_req_duration..........: avg=250ms p(95)=400ms p(99)=800ms
✓ http_req_failed............: 0.05%
✓ http_reqs..................: 150/s
✓ checks.....................: 99.95%
```

## Quick Troubleshooting

**Connection Refused?**
```bash
curl http://localhost:8000/api/v1/health
php artisan serve  # If needed
```

**High Error Rate?**
```bash
tail -f storage/logs/laravel.log
```

**Slow Response?**
```bash
htop                        # Check CPU/memory
redis-cli INFO stats        # Check cache
mysql -e "SHOW PROCESSLIST" # Check database
```

## Files Overview

```
scripts/          - Individual test scripts
scenarios/        - Load test scenarios
results/          - Test output files
*.md             - Documentation
run-load-tests.sh - Main execution script
```

## Next Steps

1. Run baseline test: `./run-load-tests.sh --scenario sustained`
2. Review results in `results/` directory
3. Compare with targets in `PERFORMANCE-BASELINES.md`
4. Read `LOAD-TESTING-GUIDE.md` for detailed info

## Need Help?

- Full Guide: `LOAD-TESTING-GUIDE.md`
- Baselines: `PERFORMANCE-BASELINES.md`
- Optimizations: `PERFORMANCE-OPTIMIZATION-REPORT.md`
- k6 Docs: https://k6.io/docs/
