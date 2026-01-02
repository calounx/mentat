# Prometheus Exporter Validation Tool

Comprehensive validation tool for Prometheus exporters that checks metrics format, health, cardinality, and integration with Prometheus.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Validation Checks](#validation-checks)
- [Examples](#examples)
- [Exit Codes](#exit-codes)
- [Integration](#integration)
- [Troubleshooting](#troubleshooting)

## Overview

`validate-exporters.py` is a robust Python tool designed to validate Prometheus exporters at multiple levels:

1. **HTTP Health** - Endpoint availability and response codes
2. **Metrics Format** - Prometheus text format compliance
3. **Naming Conventions** - Metric and label naming best practices
4. **Cardinality** - Detection of high-cardinality metrics
5. **Staleness** - Identification of stale or outdated metrics
6. **Prometheus Integration** - Verification of scraping success

## Features

### Core Validation

- **Format Parsing**: Complete Prometheus text format parser
- **Type Validation**: Counter, Gauge, Histogram, Summary validation
- **Naming Checks**: Prometheus naming convention enforcement
- **Cardinality Detection**: High-cardinality metric identification
- **Staleness Detection**: Metric age and freshness validation
- **Duplicate Detection**: Identification of duplicate metric names

### Prometheus Integration

- **Target Health**: Verify Prometheus is scraping successfully
- **Scrape Duration**: Monitor scrape performance
- **Service Discovery**: Validate target discovery
- **API Integration**: Query Prometheus API for validation

### Output Formats

- **Human-Readable**: Color-coded terminal output with categories
- **JSON**: Structured output for automation and CI/CD
- **Summary**: Brief overview for quick checks

### Advanced Features

- **Bulk Validation**: Validate multiple endpoints
- **Port Scanning**: Auto-discover exporters on a host
- **File Input**: Read endpoints from file
- **Configurable Thresholds**: Customize cardinality and staleness limits
- **Retry Logic**: Built-in HTTP retry mechanism

## Installation

### Prerequisites

- Python 3.8+
- pip package manager

### Install Dependencies

```bash
cd observability-stack/scripts/tools
pip install -r requirements.txt
```

Dependencies:
- `requests>=2.31.0` - HTTP client library

### Verify Installation

```bash
./validate-exporters.py --help
```

## Usage

### Basic Syntax

```bash
./validate-exporters.py [OPTIONS]
```

### Required Arguments

One of the following is required:

- `--endpoint URL` - Validate single exporter endpoint
- `--scan-host HOST` - Scan common ports on host
- `--endpoints-file FILE` - Read endpoints from file

### Optional Arguments

#### Prometheus Integration
- `--prometheus URL` - Prometheus server URL
- `--job NAME` - Filter by Prometheus job name

#### Validation Thresholds
- `--max-cardinality N` - Max label cardinality (default: 1000)
- `--staleness-threshold N` - Max metric age in seconds (default: 300)
- `--timeout N` - HTTP timeout in seconds (default: 10)

#### Output Options
- `--json` - JSON output format
- `--summary-only` - Brief summary only
- `--verbose, -v` - Detailed debug output
- `--quiet, -q` - Suppress non-error output

#### Behavior Options
- `--exit-on-warning` - Exit with code 1 on warnings

## Validation Checks

### 1. HTTP Health Checks

**What it validates:**
- HTTP status code is 200 OK
- Response time within timeout
- Content-Type header is appropriate
- Endpoint is reachable

**Issues detected:**
- Connection failures
- Timeouts
- HTTP errors (4xx, 5xx)
- Incorrect Content-Type

**Severity:** CRITICAL

### 2. Metrics Format Validation

**What it validates:**
- Metrics conform to Prometheus text format
- TYPE and HELP directives present
- Sample lines parse correctly
- Label syntax is valid

**Issues detected:**
- Parse errors
- Invalid syntax
- Malformed labels
- Unknown metric types

**Severity:** WARNING to CRITICAL

### 3. Naming Convention Checks

**What it validates:**
- Metric names match `[a-zA-Z_:][a-zA-Z0-9_:]*`
- Label names match `[a-zA-Z_][a-zA-Z0-9_]*`
- No reserved prefixes (`__`)
- Counters end with `_total`
- Metrics have unit suffixes

**Issues detected:**
- Invalid characters in names
- Missing `_total` suffix for counters
- Reserved label prefixes
- Names starting with underscore

**Severity:** WARNING

### 4. Cardinality Detection

**What it validates:**
- Number of unique label combinations per metric
- Configurable threshold (default: 1000)
- Warning at 70% of threshold

**Issues detected:**
- High cardinality (>1000 label sets)
- Approaching high cardinality (>700 label sets)
- Potential memory/performance issues

**Severity:** WARNING (approaching) or CRITICAL (exceeded)

**Example:**
```
CRITICAL: High cardinality detected: 1500 unique label sets [http_requests_total]
  cardinality: 1500
  threshold: 1000
```

### 5. Staleness Detection

**What it validates:**
- Metric timestamps are recent
- Configurable threshold (default: 5 minutes)
- Metrics are being updated

**Issues detected:**
- Stale metrics (age > threshold)
- Potentially stuck exporters
- Outdated data

**Severity:** WARNING

**Example:**
```
WARNING: Metric appears stale (age: 450s) [process_start_time_seconds]
  age_seconds: 450
  threshold: 300
```

### 6. Type Consistency

**What it validates:**
- Metric types are declared
- Types match naming conventions
- Histogram/Summary have required metrics

**Issues detected:**
- UNTYPED metrics
- Counter without `_total` suffix
- Missing type declarations

**Severity:** INFO to WARNING

### 7. Prometheus Integration

**What it validates:**
- Targets are being scraped
- Scrapes are successful
- Scrape duration is reasonable
- No target down alerts

**Issues detected:**
- Target down
- Scrape failures
- Slow scrapes (>10s)
- Service discovery issues

**Severity:** CRITICAL (target down) or WARNING (slow scrapes)

## Examples

### Example 1: Validate Single Exporter

```bash
./validate-exporters.py --endpoint http://localhost:9100/metrics
```

**Output:**
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

--------------------------------------------------------------------------------

Summary:
  Total endpoints: 1
  Passed: 1
  Warnings: 0
  Failed: 0
```

### Example 2: Validate with Warnings

```bash
./validate-exporters.py --endpoint http://localhost:9104/metrics
```

**Output:**
```
Issues Found:
  ● Warnings: 2

NAMING:
  ⚠ Counter metric should end with '_total' [mysql_connections]
  ⚠ Invalid metric name format: mysql-query-time [mysql-query-time]
```

### Example 3: Prometheus Integration

```bash
./validate-exporters.py \
  --endpoint http://localhost:9100/metrics \
  --prometheus http://mentat.arewel.com:9090 \
  --job node_exporter
```

Validates both the exporter endpoint AND Prometheus scraping status.

### Example 4: Scan Host for Exporters

```bash
./validate-exporters.py --scan-host mentat.arewel.com
```

**Output:**
```
INFO: Found node_exporter at http://mentat.arewel.com:9100/metrics
INFO: Found mysqld_exporter at http://mentat.arewel.com:9104/metrics

Validating 2 endpoints...
```

### Example 5: Validate Multiple Endpoints from File

Create `endpoints.txt`:
```
http://host1:9100/metrics
http://host2:9100/metrics
http://host1:9104/metrics
# Comments are ignored
http://host3:9100/metrics
```

Run validation:
```bash
./validate-exporters.py --endpoints-file endpoints.txt
```

### Example 6: JSON Output for Automation

```bash
./validate-exporters.py \
  --endpoint http://localhost:9100/metrics \
  --json > validation-results.json
```

**JSON Output:**
```json
{
  "validation_time": "2026-01-02T10:30:45.123456",
  "results": [
    {
      "endpoint": "http://localhost:9100/metrics",
      "timestamp": "2026-01-02T10:30:45.123456",
      "duration_ms": 125.45,
      "total_metrics": 842,
      "total_samples": 842,
      "issues": [],
      "exit_code": 0
    }
  ],
  "summary": {
    "total_endpoints": 1,
    "passed": 1,
    "warnings": 0,
    "failed": 0
  }
}
```

### Example 7: CI/CD Integration

```bash
#!/bin/bash
# validate-exporters.sh - CI/CD validation script

set -e

# Validate critical exporters
./validate-exporters.py \
  --endpoint http://localhost:9100/metrics \
  --prometheus http://prometheus:9090 \
  --job node_exporter \
  --exit-on-warning \
  --json > /tmp/validation.json

# Parse results
FAILED=$(jq '.summary.failed' /tmp/validation.json)
WARNINGS=$(jq '.summary.warnings' /tmp/validation.json)

if [ "$FAILED" -gt 0 ]; then
  echo "ERROR: $FAILED endpoint(s) failed validation"
  exit 2
fi

if [ "$WARNINGS" -gt 0 ]; then
  echo "WARNING: $WARNINGS endpoint(s) have warnings"
  exit 1
fi

echo "SUCCESS: All exporters validated"
exit 0
```

### Example 8: Custom Thresholds

```bash
# Stricter validation for production
./validate-exporters.py \
  --endpoint http://prod-exporter:9100/metrics \
  --max-cardinality 500 \
  --staleness-threshold 60 \
  --timeout 5 \
  --exit-on-warning
```

### Example 9: Verbose Debugging

```bash
./validate-exporters.py \
  --endpoint http://localhost:9100/metrics \
  --verbose
```

Shows detailed parsing information and debug logs.

### Example 10: Quick Summary Check

```bash
./validate-exporters.py \
  --scan-host localhost \
  --summary-only
```

**Output:**
```
Summary:
  Total endpoints: 3
  Passed: 2
  Warnings: 1
  Failed: 0
```

## Exit Codes

The tool uses exit codes for easy integration with CI/CD pipelines:

| Code | Meaning | Description |
|------|---------|-------------|
| `0` | Success | All checks passed, no issues |
| `1` | Warning | Non-critical issues detected |
| `2` | Failure | Critical errors detected |

### Exit Code Logic

**Standard Mode:**
- Exit `0`: No issues
- Exit `1`: Warnings only
- Exit `2`: Any critical issues

**Strict Mode (`--exit-on-warning`):**
- Exit `0`: No issues
- Exit `1`: Warnings OR critical issues
- Exit `2`: Reserved for tool errors

### Example Usage in Scripts

```bash
# Standard validation
if ./validate-exporters.py --endpoint http://localhost:9100/metrics; then
  echo "Validation passed"
else
  EXIT_CODE=$?
  if [ $EXIT_CODE -eq 1 ]; then
    echo "Warnings detected"
  else
    echo "Critical failures detected"
    exit 1
  fi
fi
```

## Integration

### Systemd Timer (Periodic Validation)

Create `/etc/systemd/system/exporter-validation.service`:
```ini
[Unit]
Description=Validate Prometheus Exporters
After=network.target

[Service]
Type=oneshot
User=prometheus
ExecStart=/opt/observability/scripts/tools/validate-exporters.py \
  --scan-host localhost \
  --prometheus http://localhost:9090 \
  --json \
  --exit-on-warning
StandardOutput=append:/var/log/exporter-validation.log
StandardError=append:/var/log/exporter-validation.log
```

Create `/etc/systemd/system/exporter-validation.timer`:
```ini
[Unit]
Description=Run Exporter Validation Hourly

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target
```

Enable:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now exporter-validation.timer
```

### Grafana Alerting

Create alert based on validation results:

```yaml
# alerting-rules.yml
groups:
  - name: exporter_validation
    interval: 5m
    rules:
      - alert: ExporterValidationFailed
        expr: exporter_validation_exit_code > 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Exporter validation failed"
          description: "Exporter validation returned exit code {{ $value }}"
```

### Prometheus Exporter for Validation Metrics

You can export validation results as Prometheus metrics:

```python
# validation_exporter.py
from prometheus_client import Gauge, generate_latest
from flask import Flask

app = Flask(__name__)

validation_exit_code = Gauge('exporter_validation_exit_code',
                             'Exit code from last validation',
                             ['endpoint'])
validation_issues = Gauge('exporter_validation_issues',
                         'Number of issues by severity',
                         ['endpoint', 'severity'])

@app.route('/metrics')
def metrics():
    # Run validation and update metrics
    # ...
    return generate_latest()
```

### Ansible Playbook Integration

```yaml
# validate-exporters.yml
---
- name: Validate Prometheus Exporters
  hosts: monitoring_servers
  tasks:
    - name: Run exporter validation
      command: >
        /opt/observability/scripts/tools/validate-exporters.py
        --scan-host {{ inventory_hostname }}
        --prometheus http://prometheus.local:9090
        --json
      register: validation_result
      failed_when: validation_result.rc > 1

    - name: Parse validation results
      set_fact:
        validation_json: "{{ validation_result.stdout | from_json }}"

    - name: Report failures
      debug:
        msg: "{{ validation_json.summary.failed }} endpoint(s) failed"
      when: validation_json.summary.failed > 0
```

## Troubleshooting

### Common Issues

#### Issue: "requests library is required"

**Solution:**
```bash
pip install -r requirements.txt
```

#### Issue: "Connection refused"

**Cause:** Exporter not running or wrong port

**Solution:**
1. Check exporter is running: `systemctl status node_exporter`
2. Verify port: `ss -tlnp | grep 9100`
3. Test connectivity: `curl http://localhost:9100/metrics`

#### Issue: "Request timeout"

**Cause:** Slow exporter or network issues

**Solution:**
1. Increase timeout: `--timeout 30`
2. Check exporter performance
3. Review network latency

#### Issue: "High cardinality detected"

**Cause:** Too many unique label combinations

**Solution:**
1. Review metric labels
2. Remove unbounded labels (IDs, timestamps)
3. Aggregate or drop high-cardinality metrics
4. Adjust threshold if legitimate: `--max-cardinality 2000`

#### Issue: "Metric appears stale"

**Cause:** Exporter not updating metrics

**Solution:**
1. Check exporter logs
2. Verify data source connectivity
3. Restart exporter service
4. Adjust threshold if expected: `--staleness-threshold 600`

#### Issue: "Prometheus API returned error"

**Cause:** Prometheus connectivity or API issues

**Solution:**
1. Verify Prometheus URL: `curl http://prometheus:9090/-/healthy`
2. Check Prometheus is running
3. Review Prometheus logs
4. Verify network connectivity

### Debug Mode

Enable verbose logging for troubleshooting:

```bash
./validate-exporters.py \
  --endpoint http://localhost:9100/metrics \
  --verbose 2>&1 | tee validation-debug.log
```

This shows:
- HTTP request/response details
- Metric parsing steps
- Validation check execution
- Error stack traces

### Testing Validation Logic

Test with a minimal exporter:

```python
# test_exporter.py
from prometheus_client import start_http_server, Counter
import time

# Create test metric
test_counter = Counter('test_requests_total', 'Test counter')

# Start exporter
start_http_server(8000)

# Update metric
while True:
    test_counter.inc()
    time.sleep(1)
```

Run validation:
```bash
python test_exporter.py &
./validate-exporters.py --endpoint http://localhost:8000/metrics
```

### Performance Considerations

**For large deployments:**

1. **Parallel Validation**: Use GNU Parallel for concurrent checks
   ```bash
   cat endpoints.txt | parallel -j 10 \
     "./validate-exporters.py --endpoint {} --json" > results.json
   ```

2. **Reduced Checks**: Skip Prometheus integration for faster validation
   ```bash
   ./validate-exporters.py --endpoint URL  # Endpoint only
   ```

3. **Sampling**: Validate subset of exporters
   ```bash
   # Validate 10% of endpoints
   shuf endpoints.txt | head -n 10 | \
     xargs -I {} ./validate-exporters.py --endpoint {}
   ```

## Best Practices

### Regular Validation

- Run validation after exporter changes
- Include in CI/CD pipelines
- Schedule periodic checks (hourly/daily)
- Monitor validation metrics in Grafana

### Threshold Tuning

- Start with defaults
- Adjust based on your environment
- Document custom thresholds
- Review and update periodically

### Issue Management

- Address CRITICAL issues immediately
- Plan remediation for WARNINGS
- Track INFO items for improvements
- Use JSON output for trend analysis

### Integration Testing

- Validate in staging before production
- Test with realistic data volumes
- Verify Prometheus integration
- Check alert rules trigger correctly

## See Also

- [Prometheus Metric Best Practices](https://prometheus.io/docs/practices/naming/)
- [Exporter Development Guide](https://prometheus.io/docs/instrumenting/writing_exporters/)
- [Prometheus Text Format](https://prometheus.io/docs/instrumenting/exposition_formats/)
- [Observability Stack Documentation](/observability-stack/README.md)

## Support

For issues or questions:
1. Check this documentation
2. Review tool help: `./validate-exporters.py --help`
3. Enable verbose mode for debugging
4. Review Prometheus logs
5. Check exporter-specific documentation
