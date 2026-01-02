# Quick Start: Exporter Validation

Get started with exporter validation in 5 minutes.

## Installation

```bash
# Navigate to tools directory
cd observability-stack/scripts/tools

# Install dependencies
pip install -r requirements.txt

# Verify installation
./validate-exporters.py --help
```

## Basic Usage

### 1. Validate Single Exporter

```bash
./validate-exporters.py --endpoint http://localhost:9100/metrics
```

**Expected Output:**
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
```

### 2. Scan for Exporters on Host

```bash
./validate-exporters.py --scan-host localhost
```

Automatically discovers exporters on common ports (9100, 9104, etc.).

### 3. Validate with Prometheus Integration

```bash
./validate-exporters.py \
  --endpoint http://localhost:9100/metrics \
  --prometheus http://localhost:9090
```

Checks both the exporter endpoint AND Prometheus scraping status.

### 4. CI/CD Integration

```bash
./validate-exporters.py \
  --endpoint http://localhost:9100/metrics \
  --exit-on-warning \
  --json > validation-results.json

# Check exit code
echo $?
# 0 = success, 1 = warnings, 2 = critical errors
```

## Common Commands

### Validate All Exporters

```bash
# Use the comprehensive script
./examples/validate-all-exporters.sh
```

### Validate from Endpoints File

```bash
# Create endpoints file
cat > my-endpoints.txt <<EOF
http://host1:9100/metrics
http://host2:9100/metrics
http://db-server:9104/metrics
EOF

# Validate all
./validate-exporters.py --endpoints-file my-endpoints.txt
```

### Custom Thresholds

```bash
./validate-exporters.py \
  --endpoint http://localhost:9100/metrics \
  --max-cardinality 500 \
  --staleness-threshold 60 \
  --timeout 5
```

### JSON Output for Automation

```bash
./validate-exporters.py \
  --endpoint http://localhost:9100/metrics \
  --json | jq '.summary'
```

**Output:**
```json
{
  "total_endpoints": 1,
  "passed": 1,
  "warnings": 0,
  "failed": 0
}
```

### Verbose Debugging

```bash
./validate-exporters.py \
  --endpoint http://localhost:9100/metrics \
  --verbose
```

## Understanding Results

### Exit Codes

| Code | Meaning | Description |
|------|---------|-------------|
| 0 | Success | All checks passed |
| 1 | Warning | Non-critical issues found |
| 2 | Critical | Serious issues detected |

### Issue Severity Levels

**CRITICAL** (Red ✗)
- Endpoint unreachable
- HTTP errors (500, 404)
- High cardinality (>1000)
- Target down in Prometheus
- Duplicate metric names

**WARNING** (Yellow ⚠)
- Naming convention violations
- Counter missing `_total` suffix
- Approaching high cardinality (>700)
- Slow scrapes (>10s)
- Stale metrics (>5 min)

**INFO** (Blue ℹ)
- Missing metric type declarations
- Missing unit suffixes (non-critical)

## What Gets Validated

1. **HTTP Health**
   - Endpoint responds with 200 OK
   - Response time within timeout
   - Correct Content-Type header

2. **Metrics Format**
   - Valid Prometheus text format
   - Parseable metric lines
   - TYPE and HELP directives present

3. **Naming Conventions**
   - Metric names: `[a-zA-Z_:][a-zA-Z0-9_:]*`
   - Label names: `[a-zA-Z_][a-zA-Z0-9_]*`
   - Counters end with `_total`
   - No reserved prefixes (`__`)

4. **Cardinality**
   - Maximum unique label combinations
   - Default threshold: 1000
   - Warning at 70% threshold

5. **Staleness**
   - Metric age from timestamp
   - Default threshold: 5 minutes
   - Indicates stuck exporters

6. **Prometheus Integration** (optional)
   - Target scrape status
   - Scrape success rate
   - Service discovery status

## Examples by Use Case

### Development

Quick validation during development:
```bash
./validate-exporters.py --endpoint http://localhost:9100/metrics --verbose
```

### Testing

Validate before merging:
```bash
./examples/ci-cd-validation.sh
```

### Production

Scheduled validation:
```bash
# Add to crontab
0 * * * * /opt/observability/scripts/tools/examples/validate-all-exporters.sh
```

### Debugging

Find issues with specific exporter:
```bash
./validate-exporters.py \
  --endpoint http://localhost:9104/metrics \
  --verbose \
  --max-cardinality 100  # Lower threshold to detect issues
```

## Troubleshooting

### Connection Refused

**Problem:**
```
✗ Connection failed: [Errno 111] Connection refused
```

**Solution:**
```bash
# Check if exporter is running
systemctl status node_exporter

# Check port is open
ss -tlnp | grep 9100

# Test with curl
curl http://localhost:9100/metrics
```

### High Cardinality Detected

**Problem:**
```
✗ High cardinality detected: 1500 unique label sets [http_requests_total]
```

**Solution:**
1. Review metric labels - remove unbounded values (IDs, timestamps)
2. Use aggregation or recording rules
3. Drop the metric if not needed
4. Adjust threshold if legitimate: `--max-cardinality 2000`

### Naming Violations

**Problem:**
```
⚠ Counter metric should end with '_total' [requests_count]
```

**Solution:**
Update exporter code to rename metric:
```python
# Before
requests_count = Counter('requests_count', 'Request count')

# After
requests_total = Counter('requests_total', 'Request count')
```

### Prometheus Target Down

**Problem:**
```
✗ Target down: node_exporter/localhost:9100
```

**Solution:**
```bash
# Check Prometheus configuration
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health != "up")'

# Verify network connectivity
curl http://localhost:9100/metrics

# Check Prometheus logs
journalctl -u prometheus -f
```

## Next Steps

1. **Read Full Documentation**: See [EXPORTER_VALIDATION.md](EXPORTER_VALIDATION.md)
2. **Explore Examples**: Check [examples/](examples/) directory
3. **Set Up Automation**: Integrate with CI/CD pipeline
4. **Monitor Validation**: Create dashboards and alerts
5. **Customize Thresholds**: Adjust for your environment

## Quick Reference

### Most Common Commands

```bash
# Basic validation
./validate-exporters.py --endpoint URL

# Scan host
./validate-exporters.py --scan-host HOST

# With Prometheus
./validate-exporters.py --endpoint URL --prometheus PROM_URL

# JSON output
./validate-exporters.py --endpoint URL --json

# CI/CD mode
./validate-exporters.py --endpoint URL --exit-on-warning --json
```

### Environment Variables for Examples

```bash
# For validate-all-exporters.sh
export PROMETHEUS_URL=http://prometheus:9090
export RESULTS_DIR=/var/log/validation
export ALERT_EMAIL=admin@example.com

# For ci-cd-validation.sh
export STRICT_MODE=true
export MAX_CARDINALITY=500
export STALENESS_THRESHOLD=60
```

## Support

- **Tool Help**: `./validate-exporters.py --help`
- **Documentation**: [EXPORTER_VALIDATION.md](EXPORTER_VALIDATION.md)
- **Examples**: [examples/README.md](examples/README.md)
- **Test Suite**: `python3 examples/test-validator.py`
