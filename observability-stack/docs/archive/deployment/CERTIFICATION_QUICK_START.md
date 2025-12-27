# Post-Upgrade Certification Quick Start Guide

**Purpose:** Execute comprehensive post-upgrade validation and generate certification report
**Duration:** 10-15 minutes
**Requirements:** Root access, all services should be running

---

## Quick Execution (Recommended)

### 1. Run Comprehensive Certification

```bash
cd /opt/observability-stack
sudo ./tests/post-upgrade-certification.sh | tee certification-$(date +%Y%m%d-%H%M%S).log
```

**What this does:**
- Verifies all component versions match targets
- Checks all service health status
- Validates metrics endpoints
- Confirms Prometheus targets are up
- Detects metrics gaps
- Tests Grafana connectivity
- Validates alert system
- Verifies backups exist
- Checks performance metrics
- Analyzes error logs

**Expected output:**
```
╔════════════════════════════════════════════════════════════════════╗
║                                                                    ║
║         POST-UPGRADE CERTIFICATION VALIDATION                      ║
║         Observability Stack v3.0.0                                 ║
║                                                                    ║
╚════════════════════════════════════════════════════════════════════╝

Certification Date: 2025-12-27 14:30:00 UTC
Certification ID: CERT-20251227-143000
Validation Mode: COMPREHENSIVE

[... detailed validation output ...]

╔════════════════════════════════════════════════════════════════════╗
║                                                                    ║
║  CERTIFICATION STATUS: FULLY CERTIFIED                             ║
║                                                                    ║
║  Success Rate: 95.5%                                               ║
║                                                                    ║
╚════════════════════════════════════════════════════════════════════╝

✓ Post-upgrade validation PASSED
```

---

## Step-by-Step Validation

If you prefer to run validation in phases:

### Step 1: Phase 1 (Exporter) Validation

```bash
sudo ./tests/phase1-post-validation.sh
```

**Validates:**
- node_exporter, nginx_exporter, mysqld_exporter, phpfpm_exporter, fail2ban_exporter
- Expected versions: 1.9.1, 1.5.1, 0.18.0, 2.3.0, 0.5.0

**Pass criteria:** All exporters at target versions, all services active

---

### Step 2: Phase 2 (Prometheus) Validation

```bash
sudo ./tests/phase2-post-validation.sh
```

**Validates:**
- prometheus, alertmanager
- Expected versions: 2.48.1, 0.26.0
- Prometheus targets, queries, storage

**Pass criteria:** Prometheus operational, all targets up

---

### Step 3: Phase 3 (Loki) Validation

```bash
sudo ./tests/phase3-post-validation.sh
```

**Validates:**
- loki, promtail
- Expected versions: 2.9.3, 2.9.3
- Log ingestion, queries

**Pass criteria:** Loki operational, logs flowing

---

### Step 4: Comprehensive Health Check

```bash
sudo ./tests/health-check-comprehensive.sh
```

**Validates:**
- All services
- All endpoints
- Grafana connectivity
- Performance metrics
- Error logs

**Pass criteria:** Overall status: HEALTHY

---

## Quick Health Check

For a rapid status check without detailed analysis:

```bash
sudo ./scripts/health-check.sh
```

**Output:**
```
[PASS] prometheus: active
[PASS] loki: active
[PASS] grafana-server: active
...
Overall: HEALTHY
```

---

## Individual Component Checks

### Check Specific Component Version

```bash
# Node Exporter
node_exporter --version

# Prometheus
prometheus --version

# Loki
loki --version

# Grafana
grafana-server -v
```

### Check Specific Service Status

```bash
systemctl status prometheus
systemctl status loki
systemctl status grafana-server
```

### Check Specific Metrics Endpoint

```bash
curl http://localhost:9100/metrics  # node_exporter
curl http://localhost:9090/-/ready  # prometheus
curl http://localhost:3100/ready    # loki
```

---

## Validation Results Interpretation

### Fully Certified (✅)

**Status:** FULLY CERTIFIED
**Criteria:**
- 0 failed checks
- 0 warnings (or minor warnings only)
- Success rate ≥ 95%

**Action:** System is ready for production use. Document results.

---

### Certified with Warnings (⚠️)

**Status:** CERTIFIED WITH MINOR WARNINGS
**Criteria:**
- 0 failed checks
- < 5 warnings
- Success rate ≥ 90%

**Action:**
- Review warnings
- Address non-critical issues
- System can be used in production
- Monitor warning items

---

### Conditionally Certified (⚠️)

**Status:** CONDITIONALLY CERTIFIED
**Criteria:**
- ≤ 2 failed checks
- < 10 warnings
- Success rate ≥ 80%

**Action:**
- Review failed checks
- Determine if failures are acceptable
- Create remediation plan
- May use in production with caution

---

### Not Certified (❌)

**Status:** NOT CERTIFIED
**Criteria:**
- > 2 failed checks
- Success rate < 80%

**Action:**
- Do NOT use in production
- Review all failures
- Execute rollback if necessary
- Resolve issues before retrying

---

## Common Issues and Resolutions

### Issue: Version Mismatch

**Symptom:**
```
[FAIL] prometheus: 2.45.0 (expected 2.48.1)
```

**Resolution:**
1. Check if upgrade actually ran:
   ```bash
   prometheus --version
   ```
2. If version is old, re-run upgrade:
   ```bash
   sudo ./scripts/upgrade-orchestrator.sh --component prometheus --force
   ```
3. Verify again

---

### Issue: Service Not Active

**Symptom:**
```
[FAIL] loki: inactive
```

**Resolution:**
1. Check service status:
   ```bash
   systemctl status loki
   ```
2. Check logs:
   ```bash
   journalctl -u loki -n 50
   ```
3. Start service:
   ```bash
   systemctl start loki
   ```
4. If fails to start, check configuration:
   ```bash
   loki --config.file=/etc/loki/loki.yaml --verify-config
   ```

---

### Issue: Metrics Endpoint Not Responding

**Symptom:**
```
[FAIL] node_exporter (port 9100): HTTP 000
```

**Resolution:**
1. Check if service is running:
   ```bash
   systemctl status node_exporter
   ```
2. Check if port is listening:
   ```bash
   ss -tlnp | grep 9100
   ```
3. Test locally:
   ```bash
   curl http://localhost:9100/metrics
   ```
4. Check firewall:
   ```bash
   ufw status | grep 9100
   ```

---

### Issue: Prometheus Targets Down

**Symptom:**
```
[FAIL] Targets: 5 up, 3 down
```

**Resolution:**
1. Identify down targets:
   ```bash
   curl -s http://localhost:9090/api/v1/targets | \
     jq -r '.data.activeTargets[] | select(.health=="down") | "\(.labels.job): \(.lastError)"'
   ```
2. Check target connectivity:
   ```bash
   curl http://[target-host]:9100/metrics
   ```
3. Verify firewall allows Prometheus IP
4. Check target service status on remote host

---

### Issue: Metrics Gaps

**Symptom:**
```
[WARN] node_exporter: 85 samples (70.8% coverage, ~450s gap)
```

**Resolution:**
1. Check if recent (during upgrade window):
   - If gap occurred during upgrade: ACCEPTABLE
   - If gap is ongoing: INVESTIGATE

2. Verify current scraping:
   ```bash
   curl -s http://localhost:9090/api/v1/query?query=up{job="node_exporter"}
   ```

3. Check Prometheus scrape config:
   ```bash
   grep -A 10 "job_name: node_exporter" /etc/prometheus/prometheus.yml
   ```

---

### Issue: Grafana Data Source Error

**Symptom:**
```
[FAIL] Prometheus data source: error
```

**Resolution:**
1. Check Grafana logs:
   ```bash
   journalctl -u grafana-server -n 50
   ```
2. Test data source directly:
   ```bash
   curl http://localhost:9090/api/v1/query?query=up
   ```
3. Reconfigure data source in Grafana UI:
   - Settings → Data Sources → Prometheus
   - URL: http://localhost:9090
   - Save & Test

---

## Certification Data Output

### JSON Certification Data

The certification script creates a JSON file with detailed results:

```bash
# Find latest certification data
ls -lt /tmp/upgrade-cert-data-*.json | head -1

# View certification data
cat /tmp/upgrade-cert-data-20251227-143000.json | jq '.'
```

**JSON Structure:**
```json
{
  "certification_date": "2025-12-27T14:30:00+00:00",
  "certification_type": "post_upgrade_validation",
  "overall_status": "excellent",
  "success_rate": 95.5,
  "total_checks": 66,
  "passed": 63,
  "failed": 0,
  "warnings": 3,
  "components": {
    "prometheus": {
      "version": "2.48.1",
      "status": "pass"
    },
    ...
  },
  "health_checks": {...},
  "issues": [],
  "recommendations": []
}
```

---

## Completing the Certification Report

After running validation, fill in the certification report:

1. **Open the certification report template:**
   ```bash
   vim /opt/observability-stack/UPGRADE_CERTIFICATION_REPORT.md
   ```

2. **Fill in sections marked `[TO BE RECORDED]`:**
   - Upgrade timeline (start/end times, duration)
   - Validation results (from certification script output)
   - Issues encountered and resolutions
   - Performance observations
   - Alert activity

3. **Attach validation outputs:**
   - Copy certification script output to Appendix A
   - Include JSON certification data
   - Add screenshots if relevant

4. **Sign off:**
   - Technical validation signature
   - Management approval

---

## Reporting Results

### Generate Summary Report

```bash
# Create summary
cat > upgrade-summary-$(date +%Y%m%d).txt <<EOF
Observability Stack v3.0.0 - Upgrade Certification Summary
Date: $(date)

OVERALL STATUS: [PASTE FROM CERTIFICATION OUTPUT]
Success Rate: [PASTE FROM CERTIFICATION OUTPUT]

Total Checks: [COUNT]
Passed: [COUNT]
Failed: [COUNT]
Warnings: [COUNT]

Critical Issues: [LIST OR "NONE"]
Recommendations: [LIST OR "NONE"]

Certified By: [YOUR NAME]
Certification Date: $(date)
EOF
```

### Email Notification

```bash
# Send results to stakeholders
mail -s "Observability Stack Upgrade Certification - $(date +%Y-%m-%d)" \
     stakeholders@example.com < upgrade-summary-$(date +%Y%m%d).txt
```

---

## Next Steps After Certification

### If CERTIFIED ✅

1. **Document completion:**
   - Update UPGRADE_CERTIFICATION_REPORT.md
   - Save certification outputs
   - Archive logs

2. **Monitor for 24 hours:**
   - Watch dashboards for anomalies
   - Review alert activity
   - Check error logs

3. **Cleanup:**
   - Remove old backups (keep last 5)
   - Archive upgrade logs
   - Update documentation

4. **Team notification:**
   - Notify stakeholders of successful upgrade
   - Share certification report
   - Schedule post-mortem if needed

### If NOT CERTIFIED ❌

1. **Immediate actions:**
   - Review all failed checks
   - Determine severity of issues
   - Decide: Fix forward or rollback

2. **Rollback decision:**
   ```bash
   # If rollback needed
   sudo ./scripts/rollback-deployment.sh
   ```

3. **Root cause analysis:**
   - Review upgrade logs
   - Identify what went wrong
   - Document lessons learned

4. **Remediation plan:**
   - Create action items to fix issues
   - Schedule retry with fixes
   - Update procedures

---

## Quick Reference: Key Commands

```bash
# Full certification
sudo ./tests/post-upgrade-certification.sh | tee cert-$(date +%Y%m%d).log

# Phase validations
sudo ./tests/phase1-post-validation.sh
sudo ./tests/phase2-post-validation.sh
sudo ./tests/phase3-post-validation.sh

# Health check
sudo ./tests/health-check-comprehensive.sh

# Version checks
for cmd in node_exporter prometheus loki grafana-server; do
  echo -n "$cmd: "; $cmd --version 2>&1 | head -1
done

# Service status
systemctl status prometheus loki grafana-server alertmanager

# Metrics endpoints
curl http://localhost:9090/-/ready    # Prometheus
curl http://localhost:3100/ready      # Loki
curl http://localhost:3000/api/health # Grafana

# Prometheus targets
curl -s http://localhost:9090/api/v1/targets | \
  jq -r '.data.activeTargets[] | "\(.labels.job): \(.health)"'

# Rollback (if needed)
sudo ./scripts/rollback-deployment.sh
```

---

## Support and Troubleshooting

### Documentation References

- **Certification Report:** `UPGRADE_CERTIFICATION_REPORT.md`
- **Deployment Readiness:** `DEPLOYMENT_READINESS_FINAL.md`
- **Phase 1 Plan:** `docs/PHASE_1_EXECUTION_PLAN.md`
- **Rollback Procedures:** `scripts/rollback-deployment.sh --help`

### Troubleshooting Scripts

- **Validate config:** `./scripts/validate-config.sh`
- **Health check:** `./scripts/health-check.sh`
- **Validate integrity:** `./scripts/phase3-validate-integrity.sh`

### Getting Help

1. **Check logs:**
   ```bash
   journalctl -u [service-name] -n 100
   ```

2. **Review state file:**
   ```bash
   cat /var/lib/observability-upgrades/state.json | jq '.'
   ```

3. **Contact:**
   - Documentation: See `/opt/observability-stack/README.md`
   - GitHub Issues: [Repository URL]
   - Internal team: [Team contact]

---

**Document Version:** 1.0
**Last Updated:** 2025-12-27
**Maintained By:** Deployment Engineering Team
