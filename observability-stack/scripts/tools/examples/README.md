# Exporter Validation Examples

This directory contains example scripts and test cases for the exporter validation tool.

## Files

### validate-all-exporters.sh
Comprehensive validation script that:
- Scans for local exporters
- Validates specific critical endpoints
- Checks Prometheus target health
- Generates detailed reports
- Sends alerts on failures
- Cleans up old results

**Usage:**
```bash
# Basic usage
./validate-all-exporters.sh

# With custom Prometheus URL
PROMETHEUS_URL=http://mentat.arewel.com:9090 ./validate-all-exporters.sh

# With alerting
ALERT_EMAIL=admin@example.com ./validate-all-exporters.sh

# Custom results directory
RESULTS_DIR=/var/log/validation ./validate-all-exporters.sh
```

**Environment Variables:**
- `PROMETHEUS_URL` - Prometheus server URL (default: http://localhost:9090)
- `RESULTS_DIR` - Directory for validation results (default: /tmp/exporter-validation)
- `ALERT_WEBHOOK_URL` - Webhook for critical alerts
- `ALERT_EMAIL` - Email address for alerts

### ci-cd-validation.sh
CI/CD pipeline integration script with:
- Strict mode for blocking deployments
- Artifact generation
- Automated testing
- Markdown reports
- Exit code handling

**Usage:**
```bash
# Standard CI/CD validation
./ci-cd-validation.sh

# Strict mode (warnings = failures)
STRICT_MODE=true ./ci-cd-validation.sh

# Custom configuration
PROMETHEUS_URL=http://prom:9090 \
MAX_CARDINALITY=500 \
STALENESS_THRESHOLD=60 \
./ci-cd-validation.sh
```

**Environment Variables:**
- `STRICT_MODE` - Fail on warnings (default: true)
- `PROMETHEUS_URL` - Prometheus URL
- `MAX_CARDINALITY` - Maximum label cardinality
- `STALENESS_THRESHOLD` - Max metric age in seconds
- `TIMEOUT` - HTTP timeout in seconds
- `ARTIFACTS_DIR` - Directory for CI artifacts

### test-validator.py
Unit and integration tests for the validator:
- Parser tests
- Validation logic tests
- Mock HTTP server
- Integration tests

**Usage:**
```bash
# Run all tests
python3 test-validator.py

# Run with verbose output
python3 test-validator.py -v

# Run specific test class
python3 -m unittest test-validator.TestPrometheusMetricParser
```

## Integration Examples

### Jenkins Pipeline

```groovy
pipeline {
    agent any

    stages {
        stage('Validate Exporters') {
            steps {
                script {
                    sh '''
                        cd observability-stack/scripts/tools/examples
                        ./ci-cd-validation.sh
                    '''
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'validation-artifacts/**/*'
                    publishHTML([
                        reportDir: 'validation-artifacts',
                        reportFiles: 'validation-report.md',
                        reportName: 'Exporter Validation Report'
                    ])
                }
            }
        }
    }
}
```

### GitLab CI

```yaml
validate-exporters:
  stage: test
  script:
    - cd observability-stack/scripts/tools/examples
    - ./ci-cd-validation.sh
  artifacts:
    paths:
      - validation-artifacts/
    reports:
      junit: validation-artifacts/test-results.xml
    when: always
  only:
    - main
    - develop
```

### GitHub Actions

```yaml
name: Validate Exporters

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  validate:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'

      - name: Install dependencies
        run: |
          pip install -r observability-stack/scripts/tools/requirements.txt

      - name: Run validation
        run: |
          cd observability-stack/scripts/tools/examples
          ./ci-cd-validation.sh

      - name: Upload artifacts
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: validation-results
          path: validation-artifacts/
```

### Docker Container

```dockerfile
FROM python:3.10-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY validate-exporters.py .
COPY examples/ examples/

ENTRYPOINT ["python3", "validate-exporters.py"]
```

**Build and run:**
```bash
docker build -t exporter-validator .
docker run exporter-validator --endpoint http://host.docker.internal:9100/metrics
```

### Kubernetes CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: exporter-validation
  namespace: monitoring
spec:
  schedule: "0 * * * *"  # Every hour
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: validator
            image: exporter-validator:latest
            args:
              - --scan-host
              - node-exporter.monitoring.svc.cluster.local
              - --prometheus
              - http://prometheus.monitoring.svc.cluster.local:9090
              - --json
          restartPolicy: OnFailure
```

### Ansible Automation

```yaml
---
- name: Scheduled Exporter Validation
  hosts: monitoring_servers
  become: yes

  tasks:
    - name: Install validation dependencies
      pip:
        requirements: /opt/observability/scripts/tools/requirements.txt

    - name: Run validation
      command: >
        /opt/observability/scripts/tools/examples/validate-all-exporters.sh
      environment:
        PROMETHEUS_URL: "http://{{ prometheus_host }}:9090"
        RESULTS_DIR: "/var/log/exporter-validation"
      register: validation_result
      ignore_errors: yes

    - name: Send notification on failure
      mail:
        subject: "Exporter Validation Failed on {{ inventory_hostname }}"
        body: "{{ validation_result.stdout }}"
        to: admin@example.com
      when: validation_result.rc != 0
```

## Systemd Timer Example

**Service file:** `/etc/systemd/system/exporter-validation.service`
```ini
[Unit]
Description=Validate Prometheus Exporters
After=network.target prometheus.service

[Service]
Type=oneshot
User=prometheus
WorkingDirectory=/opt/observability/scripts/tools/examples
ExecStart=/opt/observability/scripts/tools/examples/validate-all-exporters.sh
Environment="PROMETHEUS_URL=http://localhost:9090"
Environment="RESULTS_DIR=/var/log/exporter-validation"
StandardOutput=journal
StandardError=journal
```

**Timer file:** `/etc/systemd/system/exporter-validation.timer`
```ini
[Unit]
Description=Run Exporter Validation Hourly
Requires=exporter-validation.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target
```

**Enable:**
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now exporter-validation.timer
sudo systemctl status exporter-validation.timer
```

## Monitoring Validation Results

### Export Metrics

Create a simple exporter for validation results:

```python
#!/usr/bin/env python3
from prometheus_client import Gauge, start_http_server
import subprocess
import json
import time

# Metrics
validation_exit_code = Gauge('exporter_validation_exit_code',
                             'Last validation exit code',
                             ['endpoint'])
validation_duration = Gauge('exporter_validation_duration_ms',
                           'Validation duration in milliseconds',
                           ['endpoint'])
validation_issues = Gauge('exporter_validation_issues_total',
                         'Number of validation issues',
                         ['endpoint', 'severity'])

def run_validation():
    result = subprocess.run(
        ['./validate-all-exporters.sh'],
        capture_output=True,
        text=True
    )

    # Parse JSON results and update metrics
    # ... implementation ...

if __name__ == '__main__':
    start_http_server(9999)
    while True:
        run_validation()
        time.sleep(3600)  # Every hour
```

### Grafana Dashboard

Create dashboard to visualize validation results:

```json
{
  "dashboard": {
    "title": "Exporter Validation",
    "panels": [
      {
        "title": "Validation Status",
        "targets": [
          {
            "expr": "exporter_validation_exit_code"
          }
        ]
      },
      {
        "title": "Validation Duration",
        "targets": [
          {
            "expr": "exporter_validation_duration_ms"
          }
        ]
      },
      {
        "title": "Issues by Severity",
        "targets": [
          {
            "expr": "sum(exporter_validation_issues_total) by (severity)"
          }
        ]
      }
    ]
  }
}
```

## Testing

Run the test suite before deploying:

```bash
# Run unit tests
python3 test-validator.py

# Test with mock exporter
python3 -m http.server 8000 &
echo "test_metric 42" > index.html
../validate-exporters.py --endpoint http://localhost:8000/ --verbose
```

## Troubleshooting

### Common Issues

**Issue:** Scripts fail with "command not found"
```bash
# Solution: Make scripts executable
chmod +x *.sh
```

**Issue:** Python import errors
```bash
# Solution: Install dependencies
pip install -r ../requirements.txt
```

**Issue:** Permission denied writing results
```bash
# Solution: Create results directory with proper permissions
sudo mkdir -p /var/log/exporter-validation
sudo chown $USER:$USER /var/log/exporter-validation
```

## Contributing

When adding new example scripts:
1. Follow existing naming conventions
2. Include comprehensive comments
3. Support environment variable configuration
4. Provide usage examples in this README
5. Test in CI/CD environment before committing
