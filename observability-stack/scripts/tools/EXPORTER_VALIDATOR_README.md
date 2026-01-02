# Prometheus Exporter Validation Tool

**Production-ready metrics validation for Prometheus exporters**

## What is This?

A comprehensive Python tool that validates Prometheus exporter metrics for:
- Format compliance (Prometheus text format)
- Naming conventions (Prometheus best practices)
- Performance issues (high cardinality)
- Health problems (staleness, connectivity)
- Prometheus integration (scraping status)

## Quick Start (60 seconds)

```bash
# 1. Navigate to tools directory
cd observability-stack/scripts/tools

# 2. Install dependencies
pip install -r requirements.txt

# 3. Run validation
./validate-exporters.py --endpoint http://localhost:9100/metrics

# 4. Check exit code
echo $?  # 0=success, 1=warnings, 2=critical
```

## Why Use This Tool?

### Problems It Solves

1. **Catch Issues Early**: Detect metric problems before they reach production
2. **Prevent Outages**: Identify high-cardinality metrics that can crash Prometheus
3. **Enforce Standards**: Ensure metrics follow Prometheus naming conventions
4. **Save Time**: Automated validation instead of manual checks
5. **CI/CD Integration**: Block deployments with bad metrics
6. **Monitor Health**: Detect stuck or stale exporters

### Real-World Examples

**Problem**: Deployed exporter with unbounded label (user_id), crashed Prometheus
```bash
# Before deployment, this would have caught it:
./validate-exporters.py --endpoint http://staging:9100/metrics
# ✗ High cardinality detected: 50000 unique label sets [http_requests_total]
```

**Problem**: Counter metric named incorrectly, breaks Grafana dashboards
```bash
# Validation catches naming issues:
./validate-exporters.py --endpoint http://localhost:9100/metrics
# ⚠ Counter metric should end with '_total' [requests_count]
```

**Problem**: Exporter stopped updating metrics, went unnoticed for hours
```bash
# Staleness detection finds this:
./validate-exporters.py --endpoint http://localhost:9104/metrics
# ⚠ Metric appears stale (age: 7200s) [mysql_connections]
```

## Documentation

- **Quick Start**: [QUICK_START_VALIDATION.md](QUICK_START_VALIDATION.md) - Get started in 5 minutes
- **Full Documentation**: [EXPORTER_VALIDATION.md](EXPORTER_VALIDATION.md) - Complete reference
- **Examples**: [examples/README.md](examples/README.md) - Integration patterns
- **Summary**: [VALIDATOR_SUMMARY.md](VALIDATOR_SUMMARY.md) - Implementation details

## Common Use Cases

### 1. Development Testing

Validate exporter during development:
```bash
./validate-exporters.py --endpoint http://localhost:8080/metrics --verbose
```

### 2. Pre-Deployment Checks

Validate before deploying to production:
```bash
./examples/ci-cd-validation.sh
# Blocks deployment if critical issues found
```

### 3. Production Monitoring

Run hourly validation on production exporters:
```bash
# Add to crontab
0 * * * * /opt/observability/scripts/tools/examples/validate-all-exporters.sh
```

### 4. Troubleshooting

Debug problematic exporter:
```bash
./validate-exporters.py \
  --endpoint http://problematic-exporter:9100/metrics \
  --verbose \
  --max-cardinality 100  # Lower threshold to find issues
```

### 5. CI/CD Pipeline

Automated validation in CI/CD:
```yaml
# .gitlab-ci.yml
validate-exporters:
  stage: test
  script:
    - ./scripts/tools/validate-exporters.py --endpoint http://test:9100/metrics --exit-on-warning
```

## What Gets Validated

### Critical Checks (Will Fail Deployment)
- ✗ Exporter unreachable or returning errors
- ✗ Metrics fail to parse (invalid format)
- ✗ High cardinality (>1000 unique label combinations)
- ✗ Duplicate metric names
- ✗ Prometheus target down

### Warning Checks (Should Fix Soon)
- ⚠ Naming convention violations
- ⚠ Counter missing `_total` suffix
- ⚠ Approaching high cardinality (>700)
- ⚠ Slow scrapes (>10 seconds)
- ⚠ Stale metrics (>5 minutes)

### Info Checks (Nice to Have)
- ℹ Missing type declarations
- ℹ Missing unit suffixes

## Example Output

### Healthy Exporter
```
================================================================================
Prometheus Exporter Validation Report
================================================================================

Endpoint: http://localhost:9100/metrics
Timestamp: 2026-01-02 10:30:45
Duration: 125.45ms
Metrics: 842
Samples: 842

✓ All checks passed!

Summary:
  Total endpoints: 1
  Passed: 1
  Warnings: 0
  Failed: 0
```

### Problematic Exporter
```
Endpoint: http://localhost:9104/metrics
Duration: 156.23ms
Metrics: 45
Samples: 1523

Issues Found:
  ● Critical: 1
  ● Warnings: 2

CARDINALITY:
  ✗ High cardinality detected: 1500 unique label sets [mysql_query_duration]
    cardinality: 1500
    threshold: 1000

    FIX: Remove unbounded labels (query_id, user_id, etc.)
         Use aggregation or recording rules instead

NAMING:
  ⚠ Counter metric should end with '_total' [mysql_connections]
    FIX: Rename metric to 'mysql_connections_total'

  ⚠ Invalid metric name format: mysql-queries [mysql-queries]
    FIX: Replace hyphens with underscores: 'mysql_queries'
```

## Advanced Features

### 1. Port Scanning
Automatically discover exporters:
```bash
./validate-exporters.py --scan-host mentat.arewel.com
# Finds: node_exporter, mysqld_exporter, etc.
```

### 2. Prometheus Integration
Verify Prometheus is scraping successfully:
```bash
./validate-exporters.py \
  --endpoint http://localhost:9100/metrics \
  --prometheus http://prometheus:9090 \
  --job node_exporter
```

### 3. Bulk Validation
Validate multiple endpoints from file:
```bash
cat > endpoints.txt <<EOF
http://host1:9100/metrics
http://host2:9100/metrics
http://db:9104/metrics
EOF

./validate-exporters.py --endpoints-file endpoints.txt
```

### 4. JSON Output
Machine-readable output for automation:
```bash
./validate-exporters.py --endpoint http://localhost:9100/metrics --json | jq
{
  "validation_time": "2026-01-02T10:30:45",
  "results": [{
    "endpoint": "http://localhost:9100/metrics",
    "total_metrics": 842,
    "issues": [],
    "exit_code": 0
  }],
  "summary": {
    "total_endpoints": 1,
    "passed": 1,
    "warnings": 0,
    "failed": 0
  }
}
```

### 5. Custom Thresholds
Adjust validation strictness:
```bash
./validate-exporters.py \
  --endpoint http://localhost:9100/metrics \
  --max-cardinality 500 \        # Stricter cardinality limit
  --staleness-threshold 60 \     # 1 minute instead of 5
  --timeout 5                    # Faster timeout
```

## Integration Examples

### Systemd Timer (Periodic Validation)
```bash
# Runs validation every hour
sudo systemctl enable --now exporter-validation.timer
# See examples/ for complete setup
```

### Jenkins Pipeline
```groovy
stage('Validate Exporters') {
    steps {
        sh './scripts/tools/examples/ci-cd-validation.sh'
    }
    post {
        always {
            archiveArtifacts 'validation-artifacts/**/*'
        }
    }
}
```

### GitLab CI
```yaml
validate-exporters:
  stage: test
  script:
    - cd observability-stack/scripts/tools
    - ./validate-exporters.py --scan-host localhost --exit-on-warning
```

### Kubernetes CronJob
```yaml
schedule: "0 * * * *"  # Hourly
command: ["./validate-exporters.py", "--scan-host", "localhost"]
```

### Docker Container
```bash
docker run exporter-validator \
  --endpoint http://host.docker.internal:9100/metrics
```

## Troubleshooting

### Common Issues

**"Connection refused"**
```bash
# Check exporter is running
systemctl status node_exporter

# Verify port
ss -tlnp | grep 9100

# Test connectivity
curl http://localhost:9100/metrics
```

**"High cardinality detected"**
```bash
# Identify problematic labels
./validate-exporters.py --endpoint URL --verbose

# Common causes:
# - User IDs, request IDs, timestamps as labels
# - Unbounded label values
# - Too many label combinations

# Solutions:
# 1. Remove unbounded labels
# 2. Use recording rules for aggregation
# 3. Drop high-cardinality metrics
# 4. Adjust threshold if legitimate
```

**"Metric appears stale"**
```bash
# Check exporter logs
journalctl -u node_exporter -f

# Verify data source connectivity
# Restart exporter if needed
systemctl restart node_exporter
```

**"Prometheus target down"**
```bash
# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq

# Verify network connectivity
curl http://localhost:9100/metrics

# Review Prometheus config
cat /etc/prometheus/prometheus.yml
```

## Files and Structure

```
observability-stack/scripts/tools/
├── validate-exporters.py              # Main tool (1,050 lines)
├── requirements.txt                   # Dependencies
├── EXPORTER_VALIDATION.md             # Full documentation
├── QUICK_START_VALIDATION.md          # Quick start guide
├── VALIDATOR_SUMMARY.md               # Implementation summary
└── examples/
    ├── README.md                      # Examples documentation
    ├── validate-all-exporters.sh      # Comprehensive validation
    ├── ci-cd-validation.sh            # CI/CD integration
    ├── test-validator.py              # Unit tests
    └── endpoints-example.txt          # Sample endpoints file
```

## Requirements

- Python 3.8+
- requests library: `pip install requests`

## Installation

```bash
# Install dependencies
pip install -r observability-stack/scripts/tools/requirements.txt

# Make executable (if needed)
chmod +x observability-stack/scripts/tools/validate-exporters.py

# Verify installation
./observability-stack/scripts/tools/validate-exporters.py --help
```

## Testing

```bash
# Run unit tests
python3 examples/test-validator.py

# Test with real exporter
./validate-exporters.py --endpoint http://localhost:9100/metrics
```

## Best Practices

1. **Run in CI/CD**: Validate before every deployment
2. **Schedule Regular Checks**: Hourly or daily in production
3. **Monitor Validation**: Create alerts for validation failures
4. **Use Strict Mode**: In CI/CD to catch all issues
5. **Customize Thresholds**: Based on your environment
6. **Review Warnings**: Don't ignore non-critical issues
7. **Document Exceptions**: If you increase thresholds, document why

## Exit Codes

| Code | Meaning | Action |
|------|---------|--------|
| 0 | Success | All checks passed, safe to deploy |
| 1 | Warning | Non-critical issues, review before deploying |
| 2 | Critical | Serious issues, do NOT deploy |

## Support and Help

1. **Tool Help**: `./validate-exporters.py --help`
2. **Quick Start**: Read `QUICK_START_VALIDATION.md`
3. **Full Docs**: Read `EXPORTER_VALIDATION.md`
4. **Examples**: Check `examples/` directory
5. **Tests**: Run `python3 examples/test-validator.py`
6. **Verbose Mode**: Use `--verbose` for debugging

## Contributing

When adding features:
1. Follow existing code style (PEP 8)
2. Add type hints
3. Include docstrings
4. Update documentation
5. Add unit tests
6. Test with real exporters

## License

Part of the Mentat observability stack.

## See Also

- [Prometheus Metric Best Practices](https://prometheus.io/docs/practices/naming/)
- [Prometheus Text Format](https://prometheus.io/docs/instrumenting/exposition_formats/)
- [Exporter Development Guide](https://prometheus.io/docs/instrumenting/writing_exporters/)

## Summary

This tool provides:
- ✓ Comprehensive metrics validation
- ✓ Prometheus integration checks
- ✓ Multiple output formats
- ✓ CI/CD pipeline integration
- ✓ Extensive documentation
- ✓ Complete test coverage
- ✓ Production-ready reliability

**Start validating your exporters today!**

```bash
cd observability-stack/scripts/tools
pip install -r requirements.txt
./validate-exporters.py --endpoint http://localhost:9100/metrics
```
