# Advanced Grafana Dashboards - Index

## Directory Structure

```
advanced/
├── Dashboards (JSON)
│   ├── sre-golden-signals.json          [34KB] SRE Golden Signals monitoring
│   ├── devops-deployment.json           [31KB] DORA metrics & deployment tracking
│   └── infrastructure-health.json       [42KB] Infrastructure health & monitoring
│
├── Documentation
│   ├── README.md                        [12KB] Quick start & overview
│   ├── IMPORT_GUIDE.md                  [29KB] Detailed setup instructions
│   ├── SUMMARY.md                       [8.5KB] Executive summary
│   └── INDEX.md                         [This file] Directory index
│
└── Tools & Scripts
    ├── example-metrics.py               [17KB] Python metrics instrumentation
    └── validate-dashboards.sh           [6.2KB] Dashboard validation script
```

**Total:** 8 files, ~180KB

---

## Quick Navigation

### For First-Time Users
1. Start here: [README.md](README.md)
2. Then read: [IMPORT_GUIDE.md](IMPORT_GUIDE.md)
3. Reference: [example-metrics.py](example-metrics.py)

### For Grafana Admins
1. Review: [IMPORT_GUIDE.md](IMPORT_GUIDE.md)
2. Validate: Run `./validate-dashboards.sh`
3. Import: Use JSON files

### For Developers
1. Reference: [example-metrics.py](example-metrics.py)
2. Implement metrics in your application
3. Verify with Prometheus

### For Management
1. Overview: [SUMMARY.md](SUMMARY.md)
2. Business value & KPIs
3. ROI justification

---

## Dashboard Details

### 1. SRE Golden Signals (`sre-golden-signals.json`)

**Purpose:** Real-time service reliability monitoring

**Metrics Covered:**
- Latency (p50, p90, p95, p99)
- Traffic (RPS, bandwidth)
- Errors (rates, budget)
- Saturation (CPU, memory, disk, connections)

**Panels:** 17 visualization panels
**Rows:** 5 organized sections
**Variables:** 1 (instance filter)
**Time Range:** Last 6 hours

**Best For:**
- On-call engineers
- Incident response
- Real-time monitoring
- SLO tracking

---

### 2. DevOps Deployment (`devops-deployment.json`)

**Purpose:** DORA metrics and deployment tracking

**Metrics Covered:**
- Deployment frequency
- Lead time for changes
- Change failure rate
- Mean time to recovery (MTTR)
- Pipeline success rates
- Git activity

**Panels:** 15 visualization panels
**Rows:** 3 organized sections
**Variables:** 2 (environment, pipeline)
**Time Range:** Last 7 days

**Best For:**
- Engineering managers
- DevOps teams
- Release management
- Performance optimization

---

### 3. Infrastructure Health (`infrastructure-health.json`)

**Purpose:** Comprehensive infrastructure monitoring

**Metrics Covered:**
- Service health & uptime
- Disk I/O (throughput, IOPS, latency)
- SSL certificate expiry
- Backup success/failure
- Log error rates
- System entropy

**Panels:** 17 visualization panels
**Rows:** 6 organized sections
**Variables:** 2 (instance, service)
**Time Range:** Last 6 hours

**Best For:**
- Infrastructure teams
- Security teams
- Capacity planning
- Compliance monitoring

---

## File Descriptions

### Dashboard Files (JSON)

#### sre-golden-signals.json
Complete Grafana dashboard implementing Google's SRE Golden Signals methodology. Includes error budget tracking, SLO monitoring, and multi-window burn rate alerts.

**Key Features:**
- Real-time availability gauge
- Latency percentile tracking
- Error budget visualization
- Resource saturation metrics
- Deployment annotations

#### devops-deployment.json
DORA (DevOps Research and Assessment) metrics dashboard for measuring engineering effectiveness and deployment velocity.

**Key Features:**
- Deployment frequency trends
- Lead time measurement
- Change failure rate tracking
- MTTR by severity
- Pipeline health monitoring
- Git commit activity

#### infrastructure-health.json
Comprehensive infrastructure and operational health monitoring with focus on preventing issues before they impact users.

**Key Features:**
- Service dependency mapping
- Disk performance metrics
- SSL certificate management
- Backup verification
- Log analysis
- Security monitoring (entropy)

---

### Documentation Files

#### README.md
Primary documentation file with quick start guide, feature overview, and best practices. Start here if you're new to these dashboards.

**Contents:**
- Quick start instructions
- Dashboard overviews
- Feature descriptions
- Technical requirements
- Troubleshooting tips
- Best practices

#### IMPORT_GUIDE.md
Comprehensive setup and configuration guide with detailed instructions for importing dashboards and setting up the complete monitoring stack.

**Contents:**
- Prerequisites
- Metrics requirements (with code examples)
- Import methods (UI, provisioning, Docker)
- Alert rule configurations
- Alertmanager setup
- Troubleshooting guide

#### SUMMARY.md
Executive summary document highlighting business value, key features, and deliverables. Useful for stakeholder communication.

**Contents:**
- What was created
- Key features
- Business value
- Success metrics
- Roadmap
- Resource links

#### INDEX.md (This File)
Directory index and navigation guide for quick reference.

---

### Tools & Scripts

#### example-metrics.py
Complete Python implementation showing how to instrument your application with all required metrics. Includes examples for Flask, FastAPI, and standalone usage.

**Contents:**
- Metric definitions (Counter, Histogram, Gauge)
- HTTP request tracking
- Deployment metrics
- Backup tracking
- SSL certificate monitoring
- Flask/FastAPI middleware examples
- Context managers and decorators

**Usage:**
```bash
# Install dependencies
pip install prometheus-client

# Run example server
python example-metrics.py

# View metrics
curl http://localhost:9090/metrics
```

#### validate-dashboards.sh
Bash script to validate dashboard JSON files for common issues before importing to Grafana.

**Features:**
- JSON syntax validation
- Required field checking
- Panel counting
- Query validation
- File size checking
- Colorized output

**Usage:**
```bash
# Make executable
chmod +x validate-dashboards.sh

# Run validation
./validate-dashboards.sh
```

---

## Metrics Implementation Checklist

Use this checklist to ensure your application exposes all required metrics:

### HTTP Metrics (Required)
- [ ] `http_requests_total` - Request counter with labels
- [ ] `http_request_duration_seconds` - Request duration histogram
- [ ] `http_request_size_bytes` - Request size histogram
- [ ] `http_response_size_bytes` - Response size histogram

### Deployment Metrics (Required for DevOps Dashboard)
- [ ] `chom_deployment_total` - Deployment counter
- [ ] `chom_deployment_duration_seconds` - Deployment duration
- [ ] `chom_deployment_lead_time_minutes` - Lead time tracking
- [ ] `chom_deployment_info` - Current deployment info

### SLO/Error Budget (Required for SRE Dashboard)
- [ ] `chom_error_budget_consumed_total` - Error budget consumption

### Incident Metrics (Optional but Recommended)
- [ ] `chom_incident_mttr_minutes` - Mean time to recovery

### Pipeline Metrics (Required for DevOps Dashboard)
- [ ] `chom_pipeline_runs_total` - Pipeline execution counter
- [ ] `chom_pipeline_duration_seconds` - Pipeline duration

### Git Metrics (Optional)
- [ ] `chom_git_commits_total` - Commit counter

### Infrastructure Metrics (Required for Infrastructure Dashboard)
- [ ] `chom_service_latency_seconds` - Inter-service latency
- [ ] `ssl_certificate_expiry_seconds` - Certificate expiry
- [ ] `ssl_certificate_valid` - Certificate validity
- [ ] `chom_backup_total` - Backup counter
- [ ] `chom_backup_duration_seconds` - Backup duration
- [ ] `chom_backup_last_timestamp_seconds` - Last backup time
- [ ] `chom_backup_size_bytes` - Backup size
- [ ] `chom_log_entries_total` - Log entry counter

### System Metrics (Via Node Exporter)
- [x] CPU, Memory, Disk metrics (automatic)
- [x] Network metrics (automatic)
- [x] Entropy metrics (automatic)

---

## Import Workflow

### Step 1: Prerequisites
```bash
# Verify Prometheus is running
curl http://localhost:9090/-/healthy

# Verify Node Exporter is running
curl http://localhost:9100/metrics | head

# Verify Grafana is accessible
curl http://localhost:3000/api/health
```

### Step 2: Validate Dashboards
```bash
cd /path/to/advanced/
./validate-dashboards.sh
```

### Step 3: Import to Grafana
**Option A - UI Import:**
1. Login to Grafana
2. Click + > Import
3. Upload JSON file
4. Select Prometheus data source
5. Click Import

**Option B - Provisioning:**
```bash
# Copy dashboards
cp *.json /var/lib/grafana/dashboards/chom-advanced/

# Create provisioning config
cat > /etc/grafana/provisioning/dashboards/chom-advanced.yml << 'YAML'
apiVersion: 1
providers:
  - name: 'CHOM Advanced'
    folder: 'CHOM - Advanced'
    type: file
    options:
      path: /var/lib/grafana/dashboards/chom-advanced
YAML

# Restart Grafana
systemctl restart grafana-server
```

### Step 4: Configure Alerts
```bash
# Add alert rules to Prometheus
cp alert-rules.yml /etc/prometheus/alerts/chom-advanced.yml

# Update prometheus.yml
echo "  - 'alerts/chom-advanced.yml'" >> /etc/prometheus/prometheus.yml

# Reload Prometheus
curl -X POST http://localhost:9090/-/reload
```

### Step 5: Verify
1. Open each dashboard in Grafana
2. Check that panels show data
3. Test template variables
4. Verify time ranges
5. Check alert rules in Prometheus

---

## Common Tasks

### Adding a Custom Panel
1. Open dashboard in Grafana
2. Click "Add panel"
3. Select visualization type
4. Write Prometheus query
5. Configure thresholds and legend
6. Save dashboard

### Modifying Thresholds
1. Click panel title > Edit
2. Navigate to "Field" tab
3. Find "Thresholds" section
4. Adjust values
5. Save dashboard

### Adding Template Variable
1. Dashboard Settings > Variables
2. Click "Add variable"
3. Select "Query" type
4. Write Prometheus query
5. Configure display options
6. Save

### Exporting Dashboard
1. Dashboard Settings > JSON Model
2. Copy JSON
3. Save to file
4. Or click "Save dashboard"

---

## Troubleshooting Quick Reference

| Problem | Solution |
|---------|----------|
| No data displayed | Check Prometheus targets, verify metrics exist |
| Slow loading | Use recording rules, reduce time range |
| Missing metrics | Implement in application using example-metrics.py |
| Query errors | Verify metric names, check label selectors |
| Variables not working | Refresh variable cache, check query syntax |

See [IMPORT_GUIDE.md](IMPORT_GUIDE.md) for detailed troubleshooting.

---

## Support Resources

### Internal Documentation
- [Main Import Guide](../IMPORT_GUIDE.md)
- [Observability Integration](../../docs/observability-integration/)
- [Deployment Runbooks](../../runbooks/)

### External Resources
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Google SRE Book](https://sre.google/books/)
- [DORA Metrics Guide](https://cloud.google.com/blog/products/devops-sre/using-the-four-keys-to-measure-your-devops-performance)

### Community
- Grafana Community Forums
- Prometheus Mailing List
- Stack Overflow (tags: grafana, prometheus)

---

## Changelog

### Version 1.0.0 (2026-01-02)
- Initial release
- 3 advanced dashboards created
- Complete documentation suite
- Example Python instrumentation
- Validation script
- Alert rule examples

---

## License

MIT License - See project LICENSE file

---

## Contributors

Created by: CHOM SRE Team
Maintained by: Platform Engineering

For issues or contributions, please contact the SRE team.

---

**Last Updated:** 2026-01-02
**Version:** 1.0.0
**Location:** `/home/calounx/repositories/mentat/deploy/grafana-dashboards/advanced/`
