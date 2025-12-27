# Missing Tests - Action Plan
**Priority:** HIGH
**Created:** 2025-12-27
**Status:** PENDING IMPLEMENTATION

---

## Critical Tests Missing (Must Implement)

### 1. Secret Management Tests (CRITICAL)
**File:** `tests/unit/test_secrets.bats`
**Library:** `scripts/lib/secrets.sh`
**Priority:** ⚡ CRITICAL
**Estimated Effort:** 4-6 hours
**Risk if not tested:** Credential exposure, security breach

**Required Test Cases:**
```bash
@test "secrets: encrypt_secret encrypts plaintext correctly"
@test "secrets: decrypt_secret retrieves original value"
@test "secrets: systemd credential integration works"
@test "secrets: migration from plaintext to encrypted"
@test "secrets: handles invalid credentials gracefully"
@test "secrets: file permissions are restrictive (600)"
@test "secrets: prevents path traversal in secret names"
@test "secrets: handles empty/null values"
@test "secrets: validates secret name format"
@test "secrets: cleanup removes all traces"
@test "secrets: concurrent access handling"
@test "secrets: backup includes encrypted secrets"
```

**Implementation Template:**
```bash
#!/usr/bin/env bats

setup() {
    STACK_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    source "$STACK_ROOT/scripts/lib/secrets.sh"
    TEST_TMP="$BATS_TEST_TMPDIR/secrets_tests_$$"
    mkdir -p "$TEST_TMP"
    export CREDENTIALS_DIR="$TEST_TMP/credentials"
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "encrypt_secret creates encrypted credential" {
    local secret_name="test_password"
    local secret_value="super_secret_123"

    encrypt_secret "$secret_name" "$secret_value"

    # Verify credential file exists
    [[ -f "$CREDENTIALS_DIR/$secret_name" ]]

    # Verify not plaintext
    ! grep -q "$secret_value" "$CREDENTIALS_DIR/$secret_name"

    # Verify permissions
    [[ "$(stat -c %a "$CREDENTIALS_DIR/$secret_name")" == "600" ]]
}

@test "decrypt_secret retrieves original value" {
    local secret_name="test_password"
    local secret_value="super_secret_123"

    encrypt_secret "$secret_name" "$secret_value"
    result=$(decrypt_secret "$secret_name")

    [[ "$result" == "$secret_value" ]]
}

# Add remaining tests...
```

---

### 2. Transaction & Rollback Tests (HIGH)
**File:** `tests/unit/test_transaction.bats`
**Library:** `scripts/lib/transaction.sh`
**Priority:** ⚡ HIGH
**Estimated Effort:** 3-4 hours
**Risk if not tested:** System left in partial state, difficult recovery

**Required Test Cases:**
```bash
@test "transaction: init_transaction creates state tracking"
@test "transaction: track_file_created records file paths"
@test "transaction: track_service_added records service names"
@test "transaction: track_user_created records usernames"
@test "transaction: rollback removes files in reverse order"
@test "transaction: rollback stops and removes services"
@test "transaction: rollback removes created users"
@test "transaction: rollback handles missing rollback file"
@test "transaction: cleanup removes rollback tracking"
@test "transaction: rollback handles partial failures gracefully"
@test "transaction: nested transactions not supported (error)"
@test "transaction: concurrent transactions use unique state files"
@test "transaction: rollback skips already-deleted items"
```

---

### 3. Download Verification Tests (HIGH)
**File:** `tests/unit/test_download_utils.bats`
**Library:** `scripts/lib/download-utils.sh`
**Priority:** ⚡ HIGH
**Estimated Effort:** 2-3 hours
**Risk if not tested:** MITM attacks, corrupted downloads, security vulnerabilities

**Required Test Cases:**
```bash
@test "download: SHA256 verification succeeds for valid file"
@test "download: SHA256 verification fails for corrupted file"
@test "download: SHA256 verification fails for mismatched checksum"
@test "download: retry logic attempts 3 times on failure"
@test "download: retry with exponential backoff"
@test "download: timeout after configured duration"
@test "download: HTTPS-only enforcement (blocks HTTP)"
@test "download: localhost HTTP allowed for testing"
@test "download: handles network timeout gracefully"
@test "download: handles DNS resolution failure"
@test "download: verifies against checksums.sha256 file"
@test "download: fails if checksum not in database"
@test "download: progress indicator doesn't break download"
@test "download: cleanup removes partial downloads on failure"
```

---

### 4. File Locking Tests (HIGH)
**File:** `tests/unit/test_lock_utils.bats`
**Library:** `scripts/lib/lock-utils.sh`
**Priority:** ⚡ HIGH
**Estimated Effort:** 2-3 hours
**Risk if not tested:** Race conditions, data corruption, concurrent access issues

**Required Test Cases:**
```bash
@test "lock: acquire_lock creates lock file"
@test "lock: acquire_lock blocks if lock exists"
@test "lock: acquire_lock respects timeout"
@test "lock: release_lock removes lock file"
@test "lock: release_lock handles missing lock file"
@test "lock: stale lock cleanup after process death"
@test "lock: concurrent processes cannot acquire same lock"
@test "lock: lock contains PID of holder"
@test "lock: deadlock detection and prevention"
@test "lock: lock directory creation if missing"
@test "lock: handles permissions errors gracefully"
@test "lock: automatic cleanup on script exit"
```

---

### 5. Firewall Management Tests (MEDIUM-HIGH)
**File:** `tests/unit/test_firewall.bats`
**Library:** `scripts/lib/firewall.sh`
**Priority:** 🔥 MEDIUM-HIGH
**Estimated Effort:** 2-3 hours
**Risk if not tested:** Port exposure, lockout from system, security misconfiguration

**Required Test Cases:**
```bash
@test "firewall: detect_firewall identifies ufw"
@test "firewall: detect_firewall identifies firewalld"
@test "firewall: detect_firewall returns none if neither present"
@test "firewall: open_port adds ufw allow rule"
@test "firewall: open_port adds firewalld port"
@test "firewall: close_port removes rule"
@test "firewall: open_port is idempotent"
@test "firewall: port validation (1-65535)"
@test "firewall: handles firewall not installed gracefully"
@test "firewall: sudo requirement check"
@test "firewall: rule already exists handling"
@test "firewall: multiple port opening"
```

---

## Important Tests Missing (Should Implement)

### 6. Retry Logic Tests (MEDIUM)
**File:** `tests/unit/test_retry.bats`
**Library:** `scripts/lib/retry.sh`
**Estimated Effort:** 1-2 hours

**Test Cases:**
- Retry with exponential backoff
- Max retry limit enforcement
- Success after N retries
- Failure after max retries
- Custom retry count
- Custom backoff multiplier
- Timeout integration

---

### 7. Service Management Tests (MEDIUM)
**File:** `tests/unit/test_service.bats`
**Library:** `scripts/lib/service.sh`
**Estimated Effort:** 2-3 hours

**Test Cases:**
- Service start/stop/restart
- Status checking (active/inactive/failed)
- systemd detection
- Service existence validation
- Enable/disable at boot
- Service wait with timeout
- Failed service handling

---

### 8. Backup & Restore Tests (MEDIUM)
**File:** `tests/unit/test_backup.bats`
**Library:** `scripts/lib/backup.sh`
**Estimated Effort:** 2-3 hours

**Test Cases:**
- Configuration backup creation
- Backup timestamp naming
- Backup directory creation
- Restore from backup
- Backup validation
- Incremental backup
- Rotation/cleanup of old backups
- Compression handling

---

### 9. Registry Tests (MEDIUM)
**File:** `tests/unit/test_registry.bats`
**Library:** `scripts/lib/registry.sh`
**Estimated Effort:** 1-2 hours

**Test Cases:**
- Module registration
- Module deregistration
- List registered modules
- Registry file creation
- Concurrent registry updates
- Invalid module handling

---

### 10. Config Management Tests (LOW-MEDIUM)
**File:** `tests/unit/test_config.bats`
**Library:** `scripts/lib/config.sh`
**Estimated Effort:** 1-2 hours

**Test Cases:**
- Load configuration
- Validate configuration structure
- Default value handling
- Configuration merging
- Override precedence

---

## Integration Tests Missing

### 11. Multi-Host Configuration (MEDIUM)
**File:** `tests/integration/test_multi_host.bats`
**Estimated Effort:** 3-4 hours

**Test Cases:**
- Add 5+ hosts simultaneously
- Remove host and verify cleanup
- Update host configuration
- Configuration regeneration for all hosts
- Port conflict detection across hosts
- Label propagation

---

### 12. Module Upgrade/Downgrade (MEDIUM)
**File:** `tests/integration/test_module_lifecycle.bats`
**Estimated Effort:** 2-3 hours

**Test Cases:**
- Install module version 1.0
- Upgrade to version 2.0
- Downgrade to version 1.0
- Service continuity during upgrade
- Configuration preservation
- Rollback on failed upgrade

---

### 13. Rollback Verification (HIGH)
**File:** `tests/integration/test_rollback.bats`
**Estimated Effort:** 3-4 hours

**Test Cases:**
- Full installation rollback
- Verify files removed
- Verify services removed
- Verify users removed
- Verify firewall rules removed
- System state identical to pre-install

---

## Performance Tests Missing

### 14. Large-Scale YAML Parsing (LOW)
**File:** `tests/performance/test_yaml_performance.bats`
**Estimated Effort:** 1-2 hours

**Test Cases:**
- Parse 1000-line YAML file
- Parse deeply nested YAML (10+ levels)
- Parse YAML with 100+ modules
- Benchmark parsing speed

---

### 15. Concurrent Operations (MEDIUM)
**File:** `tests/performance/test_concurrent.bats`
**Estimated Effort:** 2-3 hours

**Test Cases:**
- Multiple modules installing concurrently
- Concurrent configuration generation
- File locking under load
- Race condition detection

---

## Alternative Test Execution

### Create BATS-Free Verification Script

**File:** `tests/manual-verification.sh`
**Priority:** MEDIUM
**Estimated Effort:** 2-3 hours

```bash
#!/bin/bash
#===============================================================================
# Manual Verification Script
# Basic testing without BATS dependency
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$STACK_ROOT/scripts/lib/common.sh"
source "$STACK_ROOT/scripts/lib/module-loader.sh"

PASSED=0
FAILED=0

# Test function
run_test() {
    local description="$1"
    local command="$2"

    printf "%-60s" "$description"

    if eval "$command" &>/dev/null; then
        echo "✓ PASS"
        ((PASSED++))
    else
        echo "✗ FAIL"
        ((FAILED++))
    fi
}

echo "Manual Verification Script"
echo "=========================="
echo ""

# YAML Parsing Tests
echo "YAML Parsing:"
run_test "  Extract simple YAML value" \
    "[[ \$(yaml_get 'tests/fixtures/sample_module.yaml' 'name') == 'node_exporter' ]]"

run_test "  Extract nested YAML value" \
    "[[ \$(yaml_get_nested 'tests/fixtures/sample_module.yaml' 'exporter' 'port') == '9100' ]]"

# Validation Tests
echo ""
echo "Input Validation:"
run_test "  Valid IP address" \
    "is_valid_ip '192.168.1.1'"

run_test "  Invalid IP address (high octet)" \
    "! is_valid_ip '256.1.1.1'"

run_test "  Valid hostname" \
    "is_valid_hostname 'web-server-01.example.com'"

run_test "  Invalid hostname (starts with hyphen)" \
    "! is_valid_hostname '-invalid'"

# Version Comparison Tests
echo ""
echo "Version Comparison:"
run_test "  Equal versions" \
    "[[ \$(version_compare '1.2.3' '1.2.3') -eq 0 ]]"

run_test "  Greater version" \
    "[[ \$(version_compare '2.0.0' '1.9.9') -gt 0 ]]"

# Path Utilities
echo ""
echo "Path Utilities:"
run_test "  Get stack root" \
    "[[ -d \$(get_stack_root) ]]"

run_test "  Get modules directory" \
    "[[ -d \$(get_modules_dir) ]]"

# Security Tests
echo ""
echo "Security Validation:"
run_test "  Block command injection (semicolon)" \
    "! validate_and_execute_detection_command 'systemctl status; rm -rf /'"

run_test "  Block command substitution" \
    "! validate_and_execute_detection_command 'systemctl \$(whoami)'"

run_test "  Allow safe command" \
    "validate_and_execute_detection_command 'test -f /etc/hosts' || true"

# Summary
echo ""
echo "=========================="
echo "Summary:"
echo "  Passed: $PASSED"
echo "  Failed: $FAILED"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo "✓ All manual tests passed!"
    exit 0
else
    echo "✗ $FAILED test(s) failed"
    exit 1
fi
```

---

## Implementation Priority

### Week 1 (Critical)
1. ⚡ `test_secrets.bats` (CRITICAL - 4-6 hours)
2. ⚡ `test_transaction.bats` (HIGH - 3-4 hours)
3. ⚡ `test_download_utils.bats` (HIGH - 2-3 hours)

**Total Week 1:** ~9-13 hours

### Week 2 (High Priority)
4. 🔥 `test_lock_utils.bats` (HIGH - 2-3 hours)
5. 🔥 `test_firewall.bats` (MEDIUM-HIGH - 2-3 hours)
6. 🔥 `test_rollback.bats` (integration) (HIGH - 3-4 hours)

**Total Week 2:** ~7-10 hours

### Week 3 (Important)
7. `test_retry.bats` (MEDIUM - 1-2 hours)
8. `test_service.bats` (MEDIUM - 2-3 hours)
9. `test_backup.bats` (MEDIUM - 2-3 hours)
10. `manual-verification.sh` (MEDIUM - 2-3 hours)

**Total Week 3:** ~7-11 hours

### Week 4 (Nice to Have)
11. `test_registry.bats` (MEDIUM - 1-2 hours)
12. `test_config.bats` (LOW-MEDIUM - 1-2 hours)
13. `test_multi_host.bats` (integration) (MEDIUM - 3-4 hours)
14. `test_module_lifecycle.bats` (integration) (MEDIUM - 2-3 hours)

**Total Week 4:** ~7-11 hours

---

## Estimated Total Effort

**Critical Tests (Must Do):** 9-13 hours
**High Priority Tests:** 7-10 hours
**Important Tests:** 7-11 hours
**Nice to Have Tests:** 7-11 hours

**Total Estimated Effort:** 30-45 hours (~1 week of dedicated work)

---

## Success Criteria

✅ **Phase 1 Complete** (After Week 1):
- Secret management fully tested
- Transaction/rollback fully tested
- Download verification fully tested
- **Risk reduced by 70%**

✅ **Phase 2 Complete** (After Week 2):
- File locking fully tested
- Firewall management fully tested
- Rollback integration tested
- **Risk reduced by 85%**

✅ **Phase 3 Complete** (After Week 3):
- All core utilities tested
- BATS-free alternative available
- **Risk reduced by 95%**

✅ **Phase 4 Complete** (After Week 4):
- Integration tests comprehensive
- Performance baseline established
- **100% critical coverage achieved**

---

## Maintenance Plan

### After Implementation

1. **Update Documentation:**
   - Update TEST_COVERAGE_VERIFICATION_REPORT.md
   - Update coverage claims in README.md
   - Update TESTING_COMPLETE.md with new statistics

2. **CI/CD Integration:**
   - Add new test files to `.github/workflows/test.yml`
   - Verify all tests run in CI
   - Set up coverage tracking

3. **Regular Review:**
   - Review test coverage monthly
   - Add tests for new features immediately
   - Maintain 80%+ coverage target

---

## Questions & Clarifications

**Q: Should we consolidate duplicate test files?**
A: Yes, after new tests are added, analyze test-*.bats vs organized structure and merge/remove duplicates.

**Q: Do we need BATS alternatives?**
A: Yes, `manual-verification.sh` provides basic validation without BATS dependency for environments where BATS cannot be installed.

**Q: What about performance tests?**
A: Lower priority. Add after critical functionality is tested. Use for benchmarking and regression detection.

**Q: Should secrets tests use real systemd?**
A: Start with mocking systemd-creds. Add real systemd tests as integration tests (require root).

---

**Action Plan Status:** READY FOR IMPLEMENTATION
**Next Step:** Begin Week 1 critical tests (secrets, transactions, downloads)
