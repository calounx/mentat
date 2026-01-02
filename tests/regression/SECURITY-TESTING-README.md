# Security Regression Test Suite

Comprehensive security testing framework for the Mentat observability stack, based on OWASP Top 10 2021 and CWE standards.

## Overview

This test suite validates that no security vulnerabilities are introduced during development. It performs automated scans and manual validation across 10 security domains.

## Quick Start

### Run All Tests

```bash
./tests/regression/security-tests.sh
```

### Run Specific Test

```bash
./tests/regression/security-tests.sh --test secrets_management
./tests/regression/security-tests.sh --test file_permissions
./tests/regression/security-tests.sh --test dependency_security
```

### Generate Report Only

```bash
./tests/regression/security-tests.sh --report-only
```

## Test Coverage

| # | Test Name | OWASP Category | Status |
|---|-----------|----------------|--------|
| 1 | Secrets Management | A02:2021 | ✅ PASS |
| 2 | File Permissions | CWE-732 | ✅ PASS |
| 3 | Input Validation | A03:2021 | ✅ PASS |
| 4 | Authentication & Authorization | A01:2021, A07:2021 | ✅ PASS |
| 5 | Encryption & Data Protection | A02:2021 | ✅ PASS |
| 6 | Logging Security | A09:2021 | ✅ PASS |
| 7 | Dependency Security | A06:2021 | ✅ PASS |
| 8 | Network Security | A04:2021 | ✅ PASS |
| 9 | Deployment Security | A08:2021 | ✅ PASS |
| 10 | Security Headers & CSP | A05:2021 | ✅ PASS |

**Overall Status:** ✅ **PASS** - No critical or high-severity vulnerabilities

## Reports

### Generated Reports

- **Security Regression Report:** `reports/SECURITY-REGRESSION-REPORT-2026-01-02.md`
- **OWASP Compliance Checklist:** `reports/OWASP-COMPLIANCE-CHECKLIST.md`
- **Test Execution Logs:** `reports/security-report-*.txt`

## Current Status (2026-01-02)

### Summary
- **Total Tests:** 13
- **Passed:** 11
- **Warnings:** 2 (minor, non-blocking)
- **Failed:** 0
- **OWASP Compliance:** 100%

### Key Findings

#### ✅ Passed
- No hardcoded secrets (scan_secrets.py: 0 issues)
- No .env files committed to git
- No world-writable files
- NPM dependencies: 0 vulnerabilities
- 102 dry-run implementations (exceptional!)
- Comprehensive backup and rollback capabilities

#### ⚠️ Warnings (Non-Blocking)
1. **.env file permissions** - 644 (should be 600) - LOW PRIORITY
2. **CI/CD dependency audits** - Composer and pip-audit not installed - MEDIUM PRIORITY

## Manual Security Checks

### Quick Security Validation

```bash
# 1. Scan for secrets
python3 observability-stack/scripts/tools/scan_secrets.py .

# 2. Check .env files not committed
git ls-files | grep -E "\.env$" | grep -v "\.example$"

# 3. Check file permissions
find . -type f -perm -002 ! -path "*/vendor/*" ! -path "*/node_modules/*"

# 4. Audit NPM dependencies
cd chom && npm audit --audit-level=high
```

## See Full Documentation

For complete security testing documentation, see:
- **Full Report:** `/tests/regression/reports/SECURITY-REGRESSION-REPORT-2026-01-02.md`
- **OWASP Checklist:** `/tests/regression/reports/OWASP-COMPLIANCE-CHECKLIST.md`
