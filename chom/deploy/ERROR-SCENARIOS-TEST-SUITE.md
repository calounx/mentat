# CHOM Deployment Error Scenarios - Test Suite

**Purpose:** Systematic testing of failure scenarios to validate error handling
**Run Time:** ~2 hours for full suite
**Environment:** Requires 2 test VPS instances

---

## Test Environment Setup

```bash
# Test VPS requirements:
# - VPS 1: Observability (1 vCPU, 1GB RAM, 10GB disk) - INTENTIONALLY MINIMAL
# - VPS 2: VPSManager (1 vCPU, 1GB RAM, 10GB disk) - INTENTIONALLY MINIMAL

# Test control machine:
export TEST_OBS_IP="TEST_IP_1"
export TEST_VPS_IP="TEST_IP_2"
export TEST_USER="deploy"
```

---

## Category 1: SSH Connection Failures

### Test 1.1: SSH Timeout (Network Drop Mid-Deployment)

**Scenario:** Network connection drops after SSH established

**Setup:**
```bash
# On control machine, start deployment
./deploy-enhanced.sh all &
DEPLOY_PID=$!

# Wait for SSH connection
sleep 10

# Block SSH traffic with iptables
sudo iptables -A OUTPUT -p tcp --dport 22 -d $TEST_OBS_IP -j DROP

# Wait and observe
tail -f logs/deployment-*.log
```

**Expected Behavior (CURRENT - BAD):**
- Deployment hangs indefinitely
- Lock file never released
- No error message
- Requires manual SIGKILL

**Expected Behavior (AFTER FIX):**
- Timeout after 30 seconds
- Error: "SSH connection timeout to observability VPS"
- Lock file released
- Exit code: 2 (SSH_ERROR)

**Verification:**
```bash
# After test completes
ps aux | grep deploy-enhanced.sh  # Should be empty
cat .deploy-state/deploy.lock     # Should not exist or have old PID
echo $?                            # Should be 2
```

**Cleanup:**
```bash
sudo iptables -D OUTPUT -p tcp --dport 22 -d $TEST_OBS_IP -j DROP
kill -9 $DEPLOY_PID 2>/dev/null
rm -f .deploy-state/deploy.lock
```

---

### Test 1.2: Wrong SSH Key

**Scenario:** SSH key not authorized on remote VPS

**Setup:**
```bash
# Remove SSH key from remote
ssh $TEST_USER@$TEST_OBS_IP "sed -i '/chom-deploy/d' ~/.ssh/authorized_keys"

# Try deployment
./deploy-enhanced.sh all
```

**Expected Behavior (CURRENT - BAD):**
- Generic "Cannot connect" error
- No specific guidance

**Expected Behavior (AFTER FIX):**
- Specific error: "SSH key not authorized"
- Actionable fix: "Run: ssh-copy-id -i ./keys/chom_deploy_key.pub deploy@IP"
- Exit code: 2 (SSH_ERROR)

**Verification:**
```bash
# Check error message
grep "SSH key not authorized" logs/deployment-*.log
```

**Cleanup:**
```bash
ssh-copy-id -i ./keys/chom_deploy_key.pub $TEST_USER@$TEST_OBS_IP
```

---

### Test 1.3: SSH Port Blocked by Firewall

**Scenario:** VPS firewall blocks SSH port

**Setup:**
```bash
# On remote VPS, block incoming SSH
ssh $TEST_USER@$TEST_OBS_IP "sudo ufw deny 22/tcp && sudo ufw reload"

# Try deployment
./deploy-enhanced.sh all
```

**Expected Behavior:**
- Error: "Connection timeout to observability VPS"
- Suggestion: "Check firewall rules on remote VPS"
- Exit code: 2

**Cleanup:**
```bash
# Need console access to remote VPS to re-enable SSH
# Or use VPS provider's console
sudo ufw allow 22/tcp
sudo ufw reload
```

---

## Category 2: Partial Deployment Failures

### Test 2.1: Network Drop During Binary Download

**Scenario:** Network interruption during Prometheus download

**Setup:**
```bash
# Start deployment
./deploy-enhanced.sh all &
DEPLOY_PID=$!

# Wait for downloads to start (watch for wget processes)
sleep 15
until pgrep wget >/dev/null; do sleep 1; done

# Drop network connection
sudo iptables -A OUTPUT -p tcp --dport 443 -j DROP

# Wait 30 seconds
sleep 30

# Restore network
sudo iptables -D OUTPUT -p tcp --dport 443 -j DROP
```

**Expected Behavior (CURRENT - BAD):**
- wget continues (--continue flag)
- Partial file left in /tmp
- Re-run may use corrupted partial file

**Expected Behavior (AFTER FIX):**
- Download fails with timeout
- Partial file cleaned up
- Re-run starts fresh download
- Checksum validation catches corruption

**Verification:**
```bash
# Check for partial files
ls -la /tmp/*.partial  # Should not exist

# Check if retry succeeds
wait $DEPLOY_PID
echo $?  # Should be 0 (success after retry)
```

**Cleanup:**
```bash
sudo rm -f /tmp/prometheus-*.tar.gz
sudo rm -f /tmp/*.partial
```

---

### Test 2.2: Disk Full During Installation

**Scenario:** /tmp runs out of space during extraction

**Setup:**
```bash
# Fill /tmp to 90% capacity
SPACE_AVAILABLE=$(df -BM /tmp | tail -1 | awk '{print $4}' | sed 's/M//')
FILL_SIZE=$((SPACE_AVAILABLE - 500))  # Leave 500MB
dd if=/dev/zero of=/tmp/fill-disk bs=1M count=$FILL_SIZE

# Try deployment
./deploy-enhanced.sh all
```

**Expected Behavior (CURRENT - BAD):**
- Script starts download
- Extraction fails with "No space left"
- Partial files left
- Services in broken state

**Expected Behavior (AFTER FIX):**
- Pre-flight check detects insufficient space
- Error: "Insufficient space in /tmp: 400MB available, 1200MB required"
- Attempts cleanup
- If cleanup insufficient, exits before download
- Exit code: 4 (DISK_FULL)

**Verification:**
```bash
# Check error logged
grep "Insufficient.*space" logs/deployment-*.log

# Check no partial files
ls /tmp/prometheus-* 2>/dev/null  # Should not exist
```

**Cleanup:**
```bash
rm -f /tmp/fill-disk
```

---

### Test 2.3: Service Fails to Start (Port Conflict)

**Scenario:** Port 9090 already in use when Prometheus starts

**Setup:**
```bash
# On remote VPS, start dummy service on port 9090
ssh $TEST_USER@$TEST_OBS_IP "python3 -m http.server 9090 &"

# Try deployment
./deploy-enhanced.sh all
```

**Expected Behavior (CURRENT - PARTIAL):**
- Port cleanup attempts to kill process
- May succeed or fail depending on process

**Expected Behavior (AFTER FIX):**
- Port conflict detected in pre-flight check
- Shows what process is using port
- Asks for confirmation to kill (if interactive)
- Kills process and retries
- Verifies port freed before starting service

**Verification:**
```bash
# Check Prometheus started successfully
ssh $TEST_USER@$TEST_OBS_IP "systemctl is-active prometheus"
```

**Cleanup:**
```bash
ssh $TEST_USER@$TEST_OBS_IP "killall python3"
```

---

## Category 3: Configuration Errors

### Test 3.1: Invalid IP Address in inventory.yaml

**Scenario:** Malformed IP address

**Setup:**
```bash
# Backup inventory
cp configs/inventory.yaml configs/inventory.yaml.backup

# Insert invalid IP
yq eval '.observability.ip = "999.999.999.999"' -i configs/inventory.yaml

# Try deployment
./deploy-enhanced.sh all
```

**Expected Behavior:**
- Validation error: "Invalid IP octet in observability IP: 999 (must be 0-255)"
- Exit code: 1 (CONFIG_ERROR)
- No deployment attempted

**Verification:**
```bash
grep "Invalid IP octet" logs/deployment-*.log
```

**Cleanup:**
```bash
mv configs/inventory.yaml.backup configs/inventory.yaml
```

---

### Test 3.2: .local Domain for SSL

**Scenario:** Using .local TLD (Let's Encrypt cannot issue cert)

**Setup:**
```bash
cp configs/inventory.yaml configs/inventory.yaml.backup
yq eval '.observability.config.grafana_domain = "grafana.local"' -i configs/inventory.yaml

./deploy-enhanced.sh all
```

**Expected Behavior (CURRENT - BAD):**
- Deployment proceeds
- SSL fails with cryptic certbot error
- Service accessible via HTTP only

**Expected Behavior (AFTER FIX):**
- Pre-flight validation catches .local domain
- Error: "Domain grafana.local uses .local TLD"
- Error: "Let's Encrypt cannot issue certificates for .local domains"
- Suggestion: "Use a public domain or subdomain"
- Exit code: 1 (CONFIG_ERROR)

**Cleanup:**
```bash
mv configs/inventory.yaml.backup configs/inventory.yaml
```

---

### Test 3.3: Command Injection via inventory.yaml

**Scenario:** Malicious command in configuration (SECURITY TEST)

**Setup:**
```bash
cp configs/inventory.yaml configs/inventory.yaml.backup

# Inject malicious command
yq eval '.observability.ip = "1.2.3.4; touch /tmp/HACKED"' -i configs/inventory.yaml

./deploy-enhanced.sh all
```

**Expected Behavior (CURRENT - CRITICAL VULNERABILITY):**
- Command executes
- /tmp/HACKED file created
- SECURITY BREACH!

**Expected Behavior (AFTER FIX):**
- Input validation rejects IP with semicolon
- Error: "Invalid IP address format: 1.2.3.4; touch /tmp/HACKED"
- No command execution
- Exit code: 1 (CONFIG_ERROR)

**Verification:**
```bash
# Critical: This file should NOT exist
ls /tmp/HACKED  # Should fail with "No such file"
```

**Cleanup:**
```bash
rm -f /tmp/HACKED
mv configs/inventory.yaml.backup configs/inventory.yaml
```

---

## Category 4: Resource Exhaustion

### Test 4.1: Out of Memory During Parallel Extraction

**Scenario:** Low-memory VPS (1GB) with parallel extractions

**Setup:**
```bash
# Use minimal 1GB RAM VPS for this test
# Start deployment and monitor memory

./deploy-enhanced.sh all &
DEPLOY_PID=$!

# Monitor memory usage
watch -n 1 'ssh $TEST_USER@$TEST_OBS_IP "free -m"'
```

**Expected Behavior (CURRENT - BAD):**
- All 4 extractions start in parallel
- Memory exhaustion
- OOM killer activates
- Random process killed
- Deployment fails

**Expected Behavior (AFTER FIX):**
- Script detects low memory (1GB)
- Limits parallel extractions to 2 (not 4)
- Memory stays below 80%
- All extractions complete successfully

**Verification:**
```bash
# Check extraction succeeded
ssh $TEST_USER@$TEST_OBS_IP "ls /opt/observability/bin/"
# Should show: prometheus, loki, alertmanager, node_exporter
```

---

### Test 4.2: Disk Space Runs Out During Deployment

**Scenario:** Disk fills up mid-deployment

**Setup:**
```bash
# Start deployment
./deploy-enhanced.sh all &
DEPLOY_PID=$!

# Wait for downloads to complete
sleep 60

# Fill disk on remote VPS
ssh $TEST_USER@$TEST_OBS_IP "dd if=/dev/zero of=/tmp/fill bs=1M count=5000 &"

# Wait for deployment to fail
wait $DEPLOY_PID
```

**Expected Behavior (CURRENT - BAD):**
- Operations fail with "No space left on device"
- Partial files left
- Services half-installed

**Expected Behavior (AFTER FIX):**
- Periodic disk space checks
- Detects space exhaustion
- Error: "Disk space critical: 50MB remaining"
- Attempts cleanup
- If cleanup insufficient, rolls back changes
- Exit code: 4 (DISK_FULL)

**Cleanup:**
```bash
ssh $TEST_USER@$TEST_OBS_IP "rm -f /tmp/fill"
```

---

## Category 5: Concurrent Deployments

### Test 5.1: Two Deployments Started Simultaneously

**Scenario:** Race condition in lock file creation

**Setup:**
```bash
# Start two deployments at exactly the same time
./deploy-enhanced.sh all &
PID1=$!

./deploy-enhanced.sh all &
PID2=$!

# Wait for both
wait $PID1; CODE1=$?
wait $PID2; CODE2=$?

echo "Deployment 1: exit code $CODE1"
echo "Deployment 2: exit code $CODE2"
```

**Expected Behavior (CURRENT - BAD):**
- Both deployments start
- Race condition in lock file
- Both think they have lock
- Concurrent SSH connections
- State file corrupted
- Unpredictable failures

**Expected Behavior (AFTER FIX):**
- First deployment acquires lock
- Second deployment fails immediately
- Error: "Another deployment is running (PID: XXXX)"
- Exit code: 8 (LOCK_ERROR)
- First deployment completes successfully

**Verification:**
```bash
# Exactly one should succeed, one should fail
[[ ($CODE1 -eq 0 && $CODE2 -eq 8) || ($CODE1 -eq 8 && $CODE2 -eq 0) ]]
echo $?  # Should be 0 (true)
```

---

## Category 6: Hardware Detection

### Test 6.1: Missing Hardware Detection Tools

**Scenario:** Minimal OS without nproc/free commands

**Setup:**
```bash
# On remote VPS, temporarily rename commands
ssh $TEST_USER@$TEST_OBS_IP "sudo mv /usr/bin/nproc /usr/bin/nproc.backup"
ssh $TEST_USER@$TEST_OBS_IP "sudo mv /usr/bin/free /usr/bin/free.backup"

# Try deployment
./deploy-enhanced.sh all
```

**Expected Behavior (CURRENT - BAD):**
- CPU/RAM detection fails
- Empty values or errors
- Validation may pass with wrong values

**Expected Behavior (AFTER FIX):**
- Fallback to /proc/cpuinfo for CPU count
- Fallback to /proc/meminfo for RAM
- Fallback to df -k for disk
- Warning: "Using fallback method for CPU detection"
- Deployment continues with correct values

**Verification:**
```bash
# Check detected values in log
grep "CPU:" logs/deployment-*.log
grep "RAM:" logs/deployment-*.log
```

**Cleanup:**
```bash
ssh $TEST_USER@$TEST_OBS_IP "sudo mv /usr/bin/nproc.backup /usr/bin/nproc"
ssh $TEST_USER@$TEST_OBS_IP "sudo mv /usr/bin/free.backup /usr/bin/free"
```

---

## Test Results Template

Use this template to record test results:

```markdown
## Test Results - [Date]

| Test ID | Scenario | Status | Notes |
|---------|----------|--------|-------|
| 1.1 | SSH Timeout | FAIL | Hangs indefinitely |
| 1.2 | Wrong SSH Key | PARTIAL | Error but not actionable |
| 1.3 | Firewall Block | PASS | Detected correctly |
| 2.1 | Network Drop Download | FAIL | Corrupt partial file |
| 2.2 | Disk Full | FAIL | No pre-check |
| 2.3 | Port Conflict | PARTIAL | Cleanup works but no confirmation |
| 3.1 | Invalid IP | PASS | Validation works |
| 3.2 | .local Domain | FAIL | Not caught in validation |
| 3.3 | Command Injection | CRITICAL | Command executed! |
| 4.1 | OOM | FAIL | No memory management |
| 4.2 | Disk Exhaustion | FAIL | No monitoring |
| 5.1 | Concurrent Deploy | FAIL | Race condition |
| 6.1 | Missing Tools | FAIL | No fallback |

**Summary:**
- CRITICAL: 1 (command injection)
- FAIL: 7
- PARTIAL: 2
- PASS: 2
```

---

## Automated Test Runner

```bash
#!/bin/bash
# run-error-tests.sh - Automated test suite

set -euo pipefail

# Test configuration
TEST_LOG="test-results-$(date +%Y%m%d-%H%M%S).log"
TESTS_PASSED=0
TESTS_FAILED=0

# Logging
log_test() {
    echo "[TEST] $1" | tee -a "$TEST_LOG"
}

log_pass() {
    echo "[PASS] $1" | tee -a "$TEST_LOG"
    ((TESTS_PASSED++))
}

log_fail() {
    echo "[FAIL] $1" | tee -a "$TEST_LOG"
    ((TESTS_FAILED++))
}

# Run test
run_test() {
    local test_name="$1"
    local test_func="$2"

    log_test "Starting: $test_name"

    if $test_func; then
        log_pass "$test_name"
    else
        log_fail "$test_name"
    fi
}

# Test functions
test_ssh_timeout() {
    # Implement test 1.1
    true  # Placeholder
}

test_invalid_ip() {
    # Implement test 3.1
    cp configs/inventory.yaml configs/inventory.yaml.backup
    yq eval '.observability.ip = "999.999.999.999"' -i configs/inventory.yaml

    if ./deploy-enhanced.sh --validate 2>&1 | grep -q "Invalid IP octet"; then
        mv configs/inventory.yaml.backup configs/inventory.yaml
        return 0
    else
        mv configs/inventory.yaml.backup configs/inventory.yaml
        return 1
    fi
}

# Run all tests
run_test "Invalid IP Validation" test_invalid_ip
# Add more tests...

# Summary
echo ""
echo "======================================"
echo "Test Results Summary"
echo "======================================"
echo "PASSED: $TESTS_PASSED"
echo "FAILED: $TESTS_FAILED"
echo "Total:  $((TESTS_PASSED + TESTS_FAILED))"
echo "======================================"
echo "Full log: $TEST_LOG"
```

---

## Priority Test Order

Run tests in this order (highest priority first):

1. **Test 3.3** - Command Injection (CRITICAL SECURITY)
2. **Test 5.1** - Concurrent Deployment (DATA CORRUPTION)
3. **Test 1.1** - SSH Timeout (SYSTEM HANG)
4. **Test 2.1** - Network Drop Download (CORRUPT BINARIES)
5. **Test 2.2** - Disk Full (PARTIAL INSTALL)
6. **Test 4.1** - OOM (SERVICE FAILURE)
7. **Test 3.2** - .local Domain (CONFIG ERROR)
8. **Test 6.1** - Missing Tools (COMPATIBILITY)

Remaining tests are important but lower priority.

---

## Continuous Testing

Set up automated testing:

```bash
# crontab -e
# Run tests every night
0 2 * * * cd /home/calounx/repositories/mentat/chom/deploy && ./run-error-tests.sh
```

Or GitHub Actions:

```yaml
name: Deployment Error Tests
on:
  push:
    branches: [master]
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM

jobs:
  test-errors:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run error scenarios
        run: ./run-error-tests.sh
```

---

## End of Test Suite

Remember to restore test VPS to clean state after each test run:

```bash
# Full cleanup script
ssh $TEST_USER@$TEST_OBS_IP "sudo systemctl stop prometheus loki grafana alertmanager nginx"
ssh $TEST_USER@$TEST_OBS_IP "sudo rm -rf /opt/observability /etc/observability /var/lib/observability"
ssh $TEST_USER@$TEST_OBS_IP "sudo apt-get remove --purge -y grafana"
ssh $TEST_USER@$TEST_OBS_IP "sudo rm -rf /tmp/prometheus-* /tmp/loki-*"

# Same for VPSManager VPS
ssh $TEST_USER@$TEST_VPS_IP "sudo systemctl stop nginx php8.2-fpm mariadb redis"
ssh $TEST_USER@$TEST_VPS_IP "sudo apt-get remove --purge -y nginx php8.2-fpm mariadb-server redis"
ssh $TEST_USER@$TEST_VPS_IP "sudo rm -rf /opt/vpsmanager /var/www/*"
```
