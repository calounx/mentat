# Test Coverage Improvement Roadmap

**Goal**: Increase coverage from 44% to 70-80% for production readiness
**Timeline**: 3-4 weeks
**Current Status**: 463 tests, critical paths covered, library gaps exist

---

## Week 1: Critical Security & Data Safety

### Day 1-3: Secrets Management Testing (CRITICAL)
**File to create**: `tests/unit/test_secrets.bats`
**Library under test**: `scripts/lib/secrets.sh` (9 functions)
**Priority**: CRITICAL (security)

**Tests to add** (20-30 tests):
```bash
# Secret Generation
@test "generate_secret creates random secret"
@test "generate_secret validates length parameter"
@test "generate_secret produces different secrets each time"

# Secret Encryption
@test "encrypt_secret encrypts with systemd credentials"
@test "encrypt_secret fails with invalid key"
@test "encrypt_secret produces non-readable ciphertext"
@test "encrypt_secret handles special characters"

# Secret Decryption
@test "decrypt_secret retrieves original value"
@test "decrypt_secret fails with wrong key"
@test "decrypt_secret handles corrupted data gracefully"

# Secret Storage
@test "store_secret creates file with correct permissions (0600)"
@test "store_secret validates directory permissions"
@test "store_secret refuses to overwrite without force flag"

# Secret Retrieval
@test "get_secret returns stored secret"
@test "get_secret fails for non-existent secret"
@test "get_secret validates secret format"

# Secret Rotation
@test "rotate_secret creates new value"
@test "rotate_secret keeps old backup"
@test "rotate_secret updates all references"

# Secret Validation
@test "validate_secret checks format"
@test "validate_secret checks permissions"
@test "validate_secret detects plaintext secrets"

# Integration
@test "secret lifecycle: generate -> store -> retrieve -> rotate"
@test "secrets are not world-readable"
@test "secrets directory has correct ownership"
@test "no secrets leak in error messages"

# Edge Cases
@test "handles empty secret gracefully"
@test "handles very long secrets (10KB+)"
@test "handles special characters in secret names"
@test "concurrent secret access doesn't corrupt data"
```

**Acceptance Criteria**:
- [ ] All 9 functions in secrets.sh tested
- [ ] File permission security verified
- [ ] systemd credentials integration tested
- [ ] No secret leakage in any test output
- [ ] All tests pass in CI/CD

---

### Day 4-6: Backup/Recovery Testing (CRITICAL)
**File to create**: `tests/unit/test_backup.bats`
**Library under test**: `scripts/lib/backup.sh` (8 functions)
**Priority**: CRITICAL (data safety)

**Tests to add** (15-20 tests):
```bash
# Backup Creation
@test "create_backup creates backup archive"
@test "create_backup includes all necessary files"
@test "create_backup creates compressed archive"
@test "create_backup validates source paths"
@test "create_backup sets correct permissions"

# Backup Validation
@test "validate_backup checks archive integrity"
@test "validate_backup verifies checksum"
@test "validate_backup detects corrupted archives"
@test "validate_backup checks file completeness"

# Backup Restoration
@test "restore_backup extracts to correct location"
@test "restore_backup validates before restoring"
@test "restore_backup preserves permissions"
@test "restore_backup fails on checksum mismatch"

# Backup Management
@test "list_backups shows available backups"
@test "cleanup_old_backups respects retention policy"
@test "get_backup_size reports accurate size"

# Integration
@test "full backup lifecycle: create -> validate -> restore"
@test "incremental backup works correctly"
@test "backup rotation maintains retention period"

# Error Handling
@test "backup fails gracefully on disk full"
@test "backup handles permission denied"
@test "restore detects missing backup files"
```

**Acceptance Criteria**:
- [ ] All 8 functions in backup.sh tested
- [ ] Backup integrity verified
- [ ] Restore process validated
- [ ] Retention policies tested
- [ ] All tests pass in CI/CD

---

### Day 7: Transaction Testing Setup (CRITICAL)
**File to create**: `tests/unit/test_transaction.bats`
**Library under test**: `scripts/lib/transaction.sh` (22 functions)
**Priority**: CRITICAL (atomicity)

**Initial tests to add** (10-15 tests):
```bash
# Transaction Basics
@test "begin_transaction initializes state"
@test "commit_transaction persists changes"
@test "rollback_transaction reverts changes"
@test "transaction fails if already active"

# Nested Transactions
@test "nested transactions work correctly"
@test "nested rollback only affects inner transaction"
@test "outer transaction rollback reverts all changes"

# Transaction State
@test "transaction state is properly tracked"
@test "transaction cleanup on success"
@test "transaction cleanup on failure"

# Atomicity
@test "partial operations rollback completely"
@test "transaction isolation from concurrent operations"

# Error Handling
@test "transaction handles command failures"
@test "transaction prevents zombie transactions"
@test "transaction detects stale locks"
```

**Note**: This is a complex library - continue testing in Week 2

**Acceptance Criteria (Week 1)**:
- [ ] Basic transaction operations tested
- [ ] Rollback mechanism verified
- [ ] State tracking validated

---

## Week 2: Complete Critical Coverage

### Day 8-9: Complete Transaction Testing
**Continue**: `tests/unit/test_transaction.bats`
**Additional tests** (15-20 tests):
```bash
# Advanced Atomicity
@test "transaction with multiple file operations"
@test "transaction with config changes"
@test "transaction with service restarts"
@test "transaction checkpoint creation"
@test "transaction recovery from checkpoint"

# Transaction Hooks
@test "pre-commit hooks execute"
@test "post-commit hooks execute"
@test "rollback hooks execute on failure"

# Multi-Resource Transactions
@test "transaction across multiple modules"
@test "transaction with external dependencies"

# Performance
@test "transaction overhead is acceptable"
@test "large transactions complete successfully"

# Edge Cases
@test "transaction during system shutdown"
@test "transaction during out-of-space condition"
@test "transaction with concurrent file access"
@test "transaction recovery after crash"
```

**Acceptance Criteria**:
- [ ] All 22 functions in transaction.sh tested
- [ ] Atomicity guarantees verified
- [ ] Crash recovery tested
- [ ] Performance acceptable

---

### Day 10-13: End-to-End Testing (HIGH)
**Directory to create**: `tests/e2e/`
**Priority**: HIGH (integration verification)

**Files to create**:
1. `tests/e2e/test_full_deployment.bats` (5-7 tests)
2. `tests/e2e/test_monitored_host_setup.bats` (4-6 tests)
3. `tests/e2e/test_upgrade_workflow.bats` (3-5 tests)
4. `tests/e2e/test_rollback_workflow.bats` (3-5 tests)

**E2E Test Scenarios** (15-20 total):

**Full Deployment**:
```bash
@test "E2E: Fresh observability server installation"
  # 1. Run preflight checks
  # 2. Initialize secrets
  # 3. Run setup-observability.sh
  # 4. Verify all services running
  # 5. Verify Prometheus/Grafana accessible
  # 6. Verify initial config generated

@test "E2E: Add first monitored host"
  # 1. Run setup-monitored-host.sh on client
  # 2. Run add-monitored-host.sh on server
  # 3. Verify host appears in Prometheus targets
  # 4. Verify metrics are collected
  # 5. Verify dashboards show data

@test "E2E: Add multiple monitored hosts"
  # Test with 5-10 hosts

@test "E2E: Auto-detect and configure modules"
  # Test auto-detection workflow

@test "E2E: Manual module selection"
  # Test manual configuration
```

**Monitored Host Setup**:
```bash
@test "E2E: Setup node with node_exporter"
@test "E2E: Setup web server with nginx_exporter"
@test "E2E: Setup database server with mysqld_exporter"
@test "E2E: Setup all exporters on single host"
@test "E2E: Remove host from monitoring"
```

**Upgrade Workflow**:
```bash
@test "E2E: Upgrade single module"
@test "E2E: Upgrade all modules"
@test "E2E: Upgrade with state preservation"
@test "E2E: Upgrade idempotency (run twice)"
```

**Rollback Workflow**:
```bash
@test "E2E: Rollback after failed upgrade"
@test "E2E: Rollback to specific version"
@test "E2E: Rollback with state recovery"
```

**Acceptance Criteria**:
- [ ] Complete deployment tested end-to-end
- [ ] Multi-host scenarios working
- [ ] Upgrade/rollback workflows verified
- [ ] Tests can run in CI/CD (docker/VM)

---

### Day 14: Enhanced Rollback Testing
**File to enhance**: Add to existing rollback tests
**New file**: `tests/integration/test_rollback_scenarios.bats`
**Priority**: HIGH (disaster recovery)

**Additional tests** (10-15 tests):
```bash
# Complete Rollback Scenarios
@test "rollback after partial module installation"
@test "rollback after failed config update"
@test "rollback after service failure"
@test "rollback preserves user data"

# Multi-stage Rollback
@test "rollback multiple upgrades in sequence"
@test "rollback to last known good state"
@test "rollback with state corruption"

# Rollback Validation
@test "verify rollback completeness"
@test "verify services after rollback"
@test "verify configuration after rollback"

# Edge Cases
@test "rollback during concurrent operations"
@test "rollback with missing backup"
@test "rollback with partial backup"
@test "rollback after disk failure"
```

**Acceptance Criteria**:
- [ ] All rollback scenarios tested
- [ ] State recovery verified
- [ ] Data preservation confirmed

---

## Week 3: Complete Library Coverage

### Day 15-16: Service Management Testing
**File to create**: `tests/unit/test_service.bats`
**Library under test**: `scripts/lib/service.sh` (8 functions)
**Priority**: HIGH

**Tests to add** (15-20 tests):
```bash
# Service Control
@test "start_service starts systemd service"
@test "stop_service stops systemd service"
@test "restart_service restarts service"
@test "reload_service reloads configuration"

# Service Status
@test "is_service_running detects running service"
@test "is_service_enabled detects enabled service"
@test "get_service_status returns correct status"

# Service Management
@test "enable_service enables on boot"
@test "disable_service disables on boot"

# Error Handling
@test "start fails for non-existent service"
@test "stop handles already stopped service"
@test "service operations timeout appropriately"

# Integration
@test "full service lifecycle: enable -> start -> verify -> stop"
@test "service restart preserves configuration"
@test "service reload doesn't interrupt operations"
```

---

### Day 17: Firewall Testing
**File to create**: `tests/unit/test_firewall.bats`
**Library under test**: `scripts/lib/firewall.sh` (6 functions)
**Priority**: HIGH

**Tests to add** (10-15 tests):
```bash
# Port Management
@test "open_port allows traffic"
@test "close_port blocks traffic"
@test "is_port_open detects open ports"

# Firewall Rules
@test "add_firewall_rule adds rule"
@test "remove_firewall_rule removes rule"
@test "list_firewall_rules shows all rules"

# Integration
@test "firewall allows configured exporter ports"
@test "firewall blocks unconfigured ports"

# Multiple Firewalls
@test "works with ufw"
@test "works with firewalld"
@test "works with iptables"
```

---

### Day 18-19: Retry Logic Testing
**File to create**: `tests/unit/test_retry.bats`
**Library under test**: `scripts/lib/retry.sh` (18 functions)
**Priority**: MEDIUM-HIGH

**Tests to add** (10-15 tests):
```bash
# Basic Retry
@test "retry succeeds on first attempt"
@test "retry retries failing commands"
@test "retry gives up after max attempts"
@test "retry uses exponential backoff"

# Retry Configuration
@test "retry respects max_attempts setting"
@test "retry respects timeout setting"
@test "retry respects backoff strategy"

# Retry Conditions
@test "retry only on specific exit codes"
@test "retry with custom success condition"

# Error Handling
@test "retry logs all attempts"
@test "retry reports final failure correctly"
```

---

### Day 20: Registry & Remaining Libraries
**Files to create**:
- `tests/unit/test_registry.bats` (8-10 tests)
- `tests/unit/test_config.bats` (5-8 tests)
- `tests/unit/test_download_utils.bats` (5-8 tests)
- `tests/unit/test_install_helpers.bats` (5-8 tests)

**Priority**: MEDIUM (comprehensive coverage)

**Tests per library** (5-10 each):
```bash
# Registry
- Module registration
- Module lookup
- Module updates
- Registry cleanup

# Config
- Config loading
- Config validation
- Config merging
- Config defaults

# Download Utils
- Download with retry
- Checksum verification
- Partial download resume

# Install Helpers
- Binary installation
- Permission setting
- Symlink creation
```

---

## Week 4: Performance & Polish

### Day 21-23: Performance Testing
**Directory to create**: `tests/performance/`
**Priority**: MEDIUM

**Files to create**:
1. `tests/performance/test_benchmarks.bats` (8-10 tests)
2. `tests/performance/test_scalability.bats` (5-7 tests)

**Performance tests** (15-20 total):
```bash
# Benchmarks
@test "module installation completes in < 30s"
@test "config generation for 50 hosts < 5s"
@test "module detection < 1s per module"
@test "state operations < 100ms"

# Scalability
@test "handles 100 hosts"
@test "handles 1000 scrape targets"
@test "concurrent operations don't deadlock"

# Resource Usage
@test "memory usage < 100MB"
@test "no memory leaks over time"
@test "disk I/O within limits"
```

---

### Day 24-25: Load/Stress Testing
**Directory to create**: `tests/load/`
**Priority**: MEDIUM

**Files to create**:
1. `tests/load/test_concurrent_operations.bats` (5-7 tests)
2. `tests/load/test_sustained_load.bats` (3-5 tests)

**Load tests** (8-12 total):
```bash
# Concurrent Operations
@test "10 parallel host additions"
@test "concurrent module installations"
@test "parallel config generations"

# Sustained Load
@test "continuous operations for 10 minutes"
@test "no degradation over time"
@test "recover from resource exhaustion"
```

---

### Day 26-28: Coverage Analysis & Refinement

**Day 26**: Coverage Measurement
- Run coverage tools
- Identify remaining gaps
- Measure improvement

**Day 27**: Gap Filling
- Add tests for missed functions
- Add edge case tests
- Add integration tests

**Day 28**: Documentation & CI/CD
- Update test documentation
- Optimize CI/CD pipelines
- Create coverage badges
- Final verification

---

## Progress Tracking

### Week 1 Deliverables
- [ ] test_secrets.bats (20-30 tests)
- [ ] test_backup.bats (15-20 tests)
- [ ] test_transaction.bats (initial 10-15 tests)

**Expected coverage after Week 1**: ~50%

### Week 2 Deliverables
- [ ] Complete test_transaction.bats (total 25-30 tests)
- [ ] E2E test suite (15-20 tests)
- [ ] Enhanced rollback tests (10-15 tests)

**Expected coverage after Week 2**: ~60%

### Week 3 Deliverables
- [ ] test_service.bats (15-20 tests)
- [ ] test_firewall.bats (10-15 tests)
- [ ] test_retry.bats (10-15 tests)
- [ ] test_registry.bats (8-10 tests)
- [ ] Other library tests (20-25 tests)

**Expected coverage after Week 3**: ~70%

### Week 4 Deliverables
- [ ] Performance tests (15-20 tests)
- [ ] Load tests (8-12 tests)
- [ ] Coverage analysis
- [ ] Documentation updates

**Expected coverage after Week 4**: ~75-80%

---

## Success Metrics

### Coverage Targets
- **Week 1**: 50% (from 44%)
- **Week 2**: 60%
- **Week 3**: 70% ← Minimum for production
- **Week 4**: 75-80% ← Recommended for production

### Test Count Targets
- **Current**: 463 tests
- **Week 1**: ~530 tests (+67)
- **Week 2**: ~625 tests (+95)
- **Week 3**: ~720 tests (+95)
- **Week 4**: ~760 tests (+40)

### Quality Targets
- **Determinism**: Maintain 95%+
- **Cleanup**: Maintain 100%
- **Independence**: Maintain 98%+
- **CI/CD**: All tests pass

---

## Resource Allocation

### Team Size Recommendations
- **1 developer**: 6-8 weeks
- **2 developers**: 3-4 weeks (recommended)
- **3 developers**: 2-3 weeks

### Skills Required
- Bash scripting
- BATS testing framework
- System administration
- Security testing
- Performance testing

### Tools Needed
- BATS (installed)
- Shellcheck (installed)
- Docker/VM for E2E tests
- Performance profiling tools
- Coverage analysis tools

---

## Risk Mitigation

### Potential Blockers
1. **Complex transaction testing** - allocate extra time
2. **E2E test environment** - set up early
3. **Performance test infrastructure** - can defer if needed
4. **Team availability** - plan for interruptions

### Contingency Plans
- If running behind: Focus on Week 1-3 (critical coverage)
- If E2E is hard: Expand integration tests instead
- If performance testing delayed: Defer to post-launch
- If coverage goal not met: 65% is acceptable with monitoring

---

## Next Steps

### Immediately
1. Review this roadmap with team
2. Assign developers to Week 1 tasks
3. Set up test environment for E2E tests
4. Create initial test file templates

### This Week
1. Complete secrets.sh testing
2. Complete backup.sh testing
3. Begin transaction.sh testing
4. Daily standups to track progress

### Ongoing
1. Run tests in CI/CD daily
2. Track coverage metrics
3. Adjust timeline as needed
4. Document test patterns

---

**Questions?** Refer to `TEST_COVERAGE_FINAL.md` for detailed analysis.

**Ready to start?** Begin with `tests/unit/test_secrets.bats` - it's the highest priority!
