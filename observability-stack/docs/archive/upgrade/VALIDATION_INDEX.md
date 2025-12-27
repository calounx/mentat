# Post-Upgrade Validation Framework - Index

**Purpose:** Complete index of all validation and certification resources
**Last Updated:** 2025-12-27
**Status:** PRODUCTION READY

---

## Quick Navigation

### For Engineers Performing Validation

👉 **START HERE:** [Certification Quick Start Guide](CERTIFICATION_QUICK_START.md)

**Quick commands:**
```bash
# Full certification (recommended)
sudo ./tests/post-upgrade-certification.sh | tee cert-$(date +%Y%m%d).log

# Quick health check
sudo ./tests/health-check-comprehensive.sh
```

---

### For Management and Stakeholders

👉 **READ THIS:** [Post-Upgrade Validation Summary](POST_UPGRADE_VALIDATION_SUMMARY.md)

**Key points:**
- Complete validation framework overview
- Certification criteria and pass/fail thresholds
- Compliance and audit trail information

---

### For Documentation and Record Keeping

👉 **FILL OUT:** [Upgrade Certification Report](UPGRADE_CERTIFICATION_REPORT.md)

**Purpose:** Official certification document with sign-offs

---

## Document Hierarchy

```
Observability Stack v3.0.0 - Validation Framework
│
├── Executive Level
│   └── POST_UPGRADE_VALIDATION_SUMMARY.md ⭐
│       └── Overview, metrics, compliance, next steps
│
├── Operational Level
│   ├── CERTIFICATION_QUICK_START.md ⭐
│   │   └── Step-by-step execution, troubleshooting
│   │
│   └── VALIDATION_INDEX.md (this file)
│       └── Navigation and reference
│
├── Official Documentation
│   └── UPGRADE_CERTIFICATION_REPORT.md ⭐
│       └── Certification template with sign-offs
│
└── Technical Scripts
    ├── tests/post-upgrade-certification.sh ⭐ (NEW)
    │   └── Comprehensive 60+ check validation
    │
    ├── tests/phase1-post-validation.sh (existing)
    │   └── Exporter validation
    │
    ├── tests/phase2-post-validation.sh (existing)
    │   └── Prometheus validation
    │
    ├── tests/phase3-post-validation.sh (existing)
    │   └── Loki/Promtail validation
    │
    └── tests/health-check-comprehensive.sh (existing)
        └── Full system health check

⭐ = New files created for certification framework
```

---

## Validation Scripts

### Comprehensive Certification (Recommended)

**Script:** `tests/post-upgrade-certification.sh`

**Created:** 2025-12-27 (NEW)

**Purpose:** Complete post-upgrade validation and certification

**Features:**
- 10 validation categories
- 60+ individual checks
- JSON export of results
- Automated scoring and certification status
- Performance benchmarking
- Error log analysis
- Backup verification

**Execution:**
```bash
cd /opt/observability-stack
sudo ./tests/post-upgrade-certification.sh | tee cert-$(date +%Y%m%d).log
```

**Duration:** 5-10 minutes

**Output:**
- Console: Color-coded pass/fail results
- Log file: Complete validation output
- JSON: `/tmp/upgrade-cert-data-*.json`

**Exit codes:**
- 0: PASSED (fully certified)
- 0: PASSED with minor warnings (conditionally certified)
- 1: FAILED (not certified)

---

### Phase-Specific Validation

#### Phase 1: Exporter Validation

**Script:** `tests/phase1-post-validation.sh`

**Purpose:** Validate all 5 exporter upgrades

**Components:**
- node_exporter (1.9.1)
- nginx_exporter (1.5.1)
- mysqld_exporter (0.18.0)
- phpfpm_exporter (2.3.0)
- fail2ban_exporter (0.5.0)

**Checks:**
- Version verification
- Service status
- Metrics endpoints
- Prometheus target health
- Key metrics present
- Data continuity
- Error logs

**Execution:**
```bash
sudo ./tests/phase1-post-validation.sh
```

**Pass criteria:** All exporters at target versions, all services active, all targets up

---

#### Phase 2: Prometheus Validation

**Script:** `tests/phase2-post-validation.sh`

**Purpose:** Validate Prometheus and Alertmanager upgrades

**Components:**
- prometheus (2.48.1)
- alertmanager (0.26.0)

**Checks:**
- Version verification
- Service status
- API endpoints
- Query functionality
- Target scraping
- Storage integrity
- Alert rules loaded
- Performance metrics

**Execution:**
```bash
sudo ./tests/phase2-post-validation.sh
```

**Pass criteria:** Prometheus operational, all targets up, queries executing

---

#### Phase 3: Loki/Promtail Validation

**Script:** `tests/phase3-post-validation.sh`

**Purpose:** Validate Loki and Promtail upgrades

**Components:**
- loki (2.9.3)
- promtail (2.9.3)

**Checks:**
- Version verification
- Service status
- API endpoints
- Log ingestion
- Query functionality
- Promtail shipping logs
- Storage integrity

**Execution:**
```bash
sudo ./tests/phase3-post-validation.sh
```

**Pass criteria:** Loki operational, logs flowing, queries executing

---

### Comprehensive Health Check

**Script:** `tests/health-check-comprehensive.sh`

**Purpose:** Complete system health validation

**Checks:**
- All service status
- All metrics endpoints
- Prometheus targets
- Alert rules
- Query functionality (Prometheus & Loki)
- Grafana connectivity and data sources
- Storage usage
- Performance metrics
- Error log analysis

**Execution:**
```bash
sudo ./tests/health-check-comprehensive.sh
```

**Output:**
```
========================================
  Comprehensive Health Check
========================================

=== Service Status ===
[PASS] prometheus: active
[PASS] loki: active
...

========================================
  Health Check Summary
========================================
Passed:  42
Warnings: 3
Failed:  0
Total:   45

Overall Status: HEALTHY
```

**Exit codes:**
- 0: HEALTHY
- 1: DEGRADED (≤ 2 failures)
- 2: UNHEALTHY (> 2 failures)

---

### Quick Health Check

**Script:** `scripts/health-check.sh`

**Purpose:** Rapid status check

**Checks:**
- Core service status
- Basic endpoint health

**Execution:**
```bash
sudo ./scripts/health-check.sh
```

**Duration:** < 1 minute

---

## Documentation

### Executive Summary

**File:** `POST_UPGRADE_VALIDATION_SUMMARY.md`

**Created:** 2025-12-27 (NEW)

**Contents:**
- Deliverables overview
- Validation framework architecture
- Certification criteria
- Execution workflow
- Troubleshooting guide
- Metrics and KPIs
- Compliance information
- Next steps

**Audience:** Management, stakeholders, audit

**Purpose:** High-level overview of validation framework

---

### Quick Start Guide

**File:** `CERTIFICATION_QUICK_START.md`

**Created:** 2025-12-27 (NEW)

**Contents:**
- Quick execution commands
- Step-by-step procedures
- Results interpretation
- Common issues and resolutions
- Support and troubleshooting
- Quick reference commands

**Audience:** Engineers, DevOps, SRE teams

**Purpose:** Practical execution guide

---

### Certification Report Template

**File:** `UPGRADE_CERTIFICATION_REPORT.md`

**Created:** 2025-12-27 (NEW)

**Contents:**
- Executive summary
- Certification scope
- 10 detailed test cases
- Validation results tables
- Component versions (before/after)
- Upgrade timeline documentation
- Issues and resolutions
- Performance observations
- Backup verification
- Recommendations
- Sign-off section

**Audience:** All stakeholders, official record

**Purpose:** Official certification document

**Completion:** Fill in `[TO BE RECORDED]` sections after validation

---

### This Index

**File:** `VALIDATION_INDEX.md`

**Created:** 2025-12-27 (NEW)

**Purpose:** Navigation and quick reference

---

## Execution Workflows

### Standard Workflow (Recommended)

**Duration:** 30-45 minutes total

```bash
# Step 1: Pre-validation checks (5 min)
systemctl status prometheus loki grafana-server
curl http://localhost:9090/-/ready
curl http://localhost:3100/ready

# Step 2: Execute comprehensive certification (10 min)
cd /opt/observability-stack
sudo ./tests/post-upgrade-certification.sh | tee cert-$(date +%Y%m%d).log

# Step 3: Review results (10 min)
# Check console output for certification status
# Review any failures or warnings
# Examine JSON data: cat /tmp/upgrade-cert-data-*.json | jq '.'

# Step 4: Complete certification report (15 min)
# Edit UPGRADE_CERTIFICATION_REPORT.md
# Fill in [TO BE RECORDED] sections
# Attach outputs
# Get sign-offs
```

---

### Phased Workflow

**Duration:** 25-35 minutes total

```bash
# Phase 1 validation (5 min)
sudo ./tests/phase1-post-validation.sh

# Phase 2 validation (5 min)
sudo ./tests/phase2-post-validation.sh

# Phase 3 validation (5 min)
sudo ./tests/phase3-post-validation.sh

# Comprehensive health check (5 min)
sudo ./tests/health-check-comprehensive.sh

# Final certification (5 min)
sudo ./tests/post-upgrade-certification.sh
```

---

### Quick Check Workflow

**Duration:** 5 minutes

```bash
# Quick health check
sudo ./scripts/health-check.sh

# If all green, optionally run full certification
sudo ./tests/post-upgrade-certification.sh
```

---

## Certification Criteria Summary

### FULLY CERTIFIED ✅

**Requirements:**
- All components at target versions
- All services active
- All endpoints responding HTTP 200
- All Prometheus targets UP
- Metrics gaps < 30 seconds
- Grafana data sources connected
- Alert system operational
- Backups verified
- Query performance acceptable
- No critical errors

**Success Rate:** ≥ 95%
**Failed Checks:** 0
**Warnings:** 0-3

---

### CERTIFIED WITH WARNINGS ⚠️

**Requirements:**
- All critical checks pass
- Minor warnings acceptable
- Performance acceptable
- Issues documented

**Success Rate:** ≥ 90%
**Failed Checks:** 0
**Warnings:** 3-10

---

### CONDITIONALLY CERTIFIED ⚠️

**Requirements:**
- Most checks pass
- Minor failures with workarounds
- Risk assessed and acceptable

**Success Rate:** ≥ 80%
**Failed Checks:** 1-2 (non-critical)
**Action:** Document, create remediation plan

---

### NOT CERTIFIED ❌

**Conditions:**
- > 2 failed checks
- Any critical failure
- Data loss or corruption

**Success Rate:** < 80%
**Action:** Do NOT proceed, rollback, remediate

---

## Troubleshooting Resources

### Quick Troubleshooting

**Version mismatch:**
```bash
# Verify
prometheus --version

# Fix
sudo ./scripts/upgrade-orchestrator.sh --component prometheus --force

# Validate
prometheus --version
```

**Service inactive:**
```bash
# Check
systemctl status loki
journalctl -u loki -n 50

# Fix
systemctl start loki

# Validate
systemctl is-active loki
```

**Targets down:**
```bash
# Identify
curl -s http://localhost:9090/api/v1/targets | \
  jq -r '.data.activeTargets[] | select(.health=="down")'

# Fix
systemctl start [failed-exporter]

# Validate
curl http://localhost:9090/api/v1/targets
```

---

### Detailed Troubleshooting

**Reference:** See `CERTIFICATION_QUICK_START.md` section "Common Issues and Resolutions"

**Topics covered:**
- Version mismatch resolution
- Service startup failures
- Endpoint connectivity issues
- Prometheus target problems
- Metrics gap analysis
- Grafana data source errors
- Alert system issues
- Backup verification failures
- Performance degradation
- Error log analysis

---

## Support and References

### Internal Documentation

- **README:** `/opt/observability-stack/README.md`
- **Deployment Readiness:** `DEPLOYMENT_READINESS_FINAL.md`
- **Phase 1 Plan:** `docs/PHASE_1_EXECUTION_PLAN.md`
- **Rollback Procedures:** `scripts/rollback-deployment.sh --help`

### Validation Scripts

All validation scripts include `--help`:
```bash
./tests/post-upgrade-certification.sh --help
./tests/phase1-post-validation.sh --help
```

### Additional Scripts

- **Config validation:** `./scripts/validate-config.sh`
- **Health check:** `./scripts/health-check.sh`
- **Integrity check:** `./scripts/phase3-validate-integrity.sh`

---

## File Locations

### Main Documentation

| File | Location | Size | Type |
|------|----------|------|------|
| Validation Summary | `POST_UPGRADE_VALIDATION_SUMMARY.md` | 25 KB | Markdown |
| Quick Start Guide | `CERTIFICATION_QUICK_START.md` | 22 KB | Markdown |
| Certification Report | `UPGRADE_CERTIFICATION_REPORT.md` | 35 KB | Markdown |
| Validation Index | `VALIDATION_INDEX.md` | This file | Markdown |

### Validation Scripts

| Script | Location | Size | Type |
|--------|----------|------|------|
| Comprehensive Certification | `tests/post-upgrade-certification.sh` | 15 KB | Bash |
| Phase 1 Validation | `tests/phase1-post-validation.sh` | 8 KB | Bash |
| Phase 2 Validation | `tests/phase2-post-validation.sh` | 8 KB | Bash |
| Phase 3 Validation | `tests/phase3-post-validation.sh` | 8 KB | Bash |
| Health Check | `tests/health-check-comprehensive.sh` | 13 KB | Bash |

### Upgrade Documentation

| Document | Location | Purpose |
|----------|----------|---------|
| Phase 1 Plan | `docs/PHASE_1_EXECUTION_PLAN.md` | Exporter upgrade guide |
| Prometheus Upgrade | `docs/PROMETHEUS_TWO_STAGE_UPGRADE.md` | Prometheus upgrade guide |
| Loki Upgrade | `docs/PHASE_3_LOKI_PROMTAIL_UPGRADE.md` | Loki/Promtail upgrade guide |
| Deployment Readiness | `DEPLOYMENT_READINESS_FINAL.md` | Pre-deployment assessment |

---

## Version Information

### Framework Version

**Version:** 1.0
**Release Date:** 2025-12-27
**Status:** Production Ready

### Validation Script Versions

All scripts support `--version` flag:
```bash
./tests/post-upgrade-certification.sh --version
```

---

## Change Log

### Version 1.0 (2025-12-27)

**Initial Release:**
- Created comprehensive certification framework
- 4 new documentation files
- 1 new validation script (60+ checks)
- Integration with existing validation scripts
- Complete troubleshooting guides
- Certification report template

**Files Created:**
- `POST_UPGRADE_VALIDATION_SUMMARY.md`
- `CERTIFICATION_QUICK_START.md`
- `UPGRADE_CERTIFICATION_REPORT.md`
- `VALIDATION_INDEX.md`
- `tests/post-upgrade-certification.sh`

**Status:** COMPLETE

---

## Quick Reference Card

### Essential Commands

```bash
# Full certification (recommended)
sudo ./tests/post-upgrade-certification.sh | tee cert.log

# Quick health check
sudo ./tests/health-check-comprehensive.sh

# Phase validations
sudo ./tests/phase1-post-validation.sh  # Exporters
sudo ./tests/phase2-post-validation.sh  # Prometheus
sudo ./tests/phase3-post-validation.sh  # Loki

# Component checks
prometheus --version
systemctl status prometheus
curl http://localhost:9090/-/ready

# Results
cat /tmp/upgrade-cert-data-*.json | jq '.'
```

### Essential Files

```bash
# Documentation
cat CERTIFICATION_QUICK_START.md       # Quick start
cat POST_UPGRADE_VALIDATION_SUMMARY.md # Overview
vim UPGRADE_CERTIFICATION_REPORT.md    # Fill out

# Logs
tail -f cert-20251227.log               # Live validation
cat /var/log/syslog | grep prometheus  # System logs
journalctl -u prometheus -f             # Service logs
```

---

## Contact and Support

### Documentation Issues

**File:** This validation framework
**Contact:** Deployment Engineering Team
**Updates:** Version controlled in git repository

### Execution Issues

**Troubleshooting:** See `CERTIFICATION_QUICK_START.md`
**Support:** Internal DevOps team
**Escalation:** Infrastructure management

---

**Document Version:** 1.0
**Last Updated:** 2025-12-27
**Next Review:** After first production use
**Maintained By:** Deployment Engineering Team

---

**END OF INDEX**
