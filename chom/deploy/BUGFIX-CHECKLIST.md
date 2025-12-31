# Deployment Scripts Bug Fix Checklist

## Critical Security Fixes (DO FIRST)

### 1. Command Injection in remote_exec ⚠️ CRITICAL
- [ ] File: `deploy-enhanced.sh` line 934-947
- [ ] Add proper input validation for all parameters
- [ ] Quote variables properly or use SSH with `--`
- [ ] Sanitize `obs_ip` before using in line 1917
- [ ] Test: Try injecting `; rm -rf /` in config

### 2. eval Command Injection ⚠️ CRITICAL
- [ ] File: `deploy-enhanced.sh` line 1001, 1019
- [ ] Replace `eval "$command_to_retry"` with direct function calls
- [ ] Replace `eval "$auto_fix_function"` with function pointers
- [ ] Refactor retry_with_healing to accept function references
- [ ] Test: Ensure no code execution from strings

### 3. Unsafe Temp File Handling ⚠️ CRITICAL
- [ ] File: `deploy-enhanced.sh` line 462-510
- [ ] Fix trap to use single quotes: `trap 'rm -f "$tmp_file"' RETURN`
- [ ] Replace `${STATE_FILE}.tmp.$$` with `mktemp`
- [ ] Set chmod 600 BEFORE writing data
- [ ] Test: Check permissions during file creation

### 4. Credentials in World-Readable /tmp ⚠️ CRITICAL
- [ ] File: `setup-vpsmanager-vps.sh` line 228-244
- [ ] Replace `/tmp/.my.cnf` with mktemp in /root
- [ ] Set chmod 600 BEFORE writing
- [ ] Use secure deletion (shred)
- [ ] Test: Monitor /tmp during script execution

### 5. Dashboard Rate Limit File Vulnerability ⚠️ CRITICAL
- [ ] File: `setup-vpsmanager-vps.sh` line 402-436
- [ ] Replace temp file approach with session-based storage
- [ ] Remove predictable filenames
- [ ] Add file ownership validation if keeping files
- [ ] Test: Pre-create symlinks and verify protection

## Major Security Fixes

### 6. Password Hashing Exposure
- [ ] File: `setup-vpsmanager-vps.sh` line 389
- [ ] Use environment variable instead of command line arg
- [ ] Prevent password in process list
- [ ] Test: Check `ps aux` during execution

### 7. Input Validation on Config
- [ ] File: `deploy-enhanced.sh` line 720-722
- [ ] Add validation for IP addresses
- [ ] Add validation for ports
- [ ] Add validation for usernames
- [ ] Reject special characters that could break commands
- [ ] Test: Try config with `; rm -rf /` in fields

### 8. TOCTOU Race in Lock File
- [ ] File: `deploy-enhanced.sh` line 226-244
- [ ] Use atomic file creation with `set -C`
- [ ] Add retry logic for lock acquisition
- [ ] Test: Run two instances simultaneously

### 9. Missing Quotes in Variable Expansion
- [ ] File: `deploy-enhanced.sh` line 1034
- [ ] Fix: `for ((i=$delay; i>0; i--)); do`
- [ ] Audit all variable uses in arithmetic contexts

### 10. Weak Signal Handling
- [ ] File: `deploy-enhanced.sh` line 179-195
- [ ] Track remote SSH PIDs
- [ ] Kill remote processes on interrupt
- [ ] Add cleanup for remote temp files
- [ ] Test: Ctrl+C during remote execution

### 11. Service Stop Verification
- [ ] File: `setup-observability-vps.sh` line 35-68
- [ ] File: `setup-vpsmanager-vps.sh` line 40-73
- [ ] Check if lsof is installed before using
- [ ] Add fallback if lsof unavailable
- [ ] Check binary exists before lsof
- [ ] Test: Run on system without lsof

### 12. Loki Authentication Misconfiguration
- [ ] File: `setup-observability-vps.sh` line 256
- [ ] Either set `auth_enabled: false`
- [ ] OR add proper multi-tenant config
- [ ] Test: Verify Loki accepts connections

## Correctness Fixes

### 13. State File Race Condition
- [ ] File: `deploy-enhanced.sh` line 456-511
- [ ] Add file locking (flock)
- [ ] Handle concurrent state updates
- [ ] Test: Update state from multiple processes

### 14. Exponential Backoff Overflow
- [ ] File: `deploy-enhanced.sh` line 970-986
- [ ] Cap exponent to prevent overflow (max 2^5)
- [ ] Add bounds checking
- [ ] Test: Verify with high retry counts

### 15. Temp Scripts Not Cleaned Up
- [ ] File: `deploy-enhanced.sh` line 1876, 1917
- [ ] Add `; rm -f /tmp/setup-*.sh` after execution
- [ ] Or use trap on remote side
- [ ] Test: Check /tmp on VPS after deployment

### 16. SSH Key Copy Not Verified
- [ ] File: `deploy-enhanced.sh` line 815-839
- [ ] Test key auth after ssh-copy-id
- [ ] Verify key actually works before continuing
- [ ] Test: Run with read-only authorized_keys

### 17. Hardcoded Timeouts
- [ ] File: `deploy-enhanced.sh` line 890
- [ ] Make SSH_CONNECT_TIMEOUT configurable
- [ ] Increase default to 30s
- [ ] Document in help

### 18. No Binary Verification
- [ ] File: `setup-observability-vps.sh` line 123-134
- [ ] Download checksums
- [ ] Verify sha256sum before installing
- [ ] Add option to skip for air-gapped systems
- [ ] Test: Verify with corrupted download

### 19. IPv6 Not Supported
- [ ] File: `deploy-enhanced.sh` line 664-674
- [ ] Add IPv6 regex validation
- [ ] Or document IPv4-only limitation clearly
- [ ] Test: Try with IPv6 address

## Code Quality Improvements

### 20. Remove Unused Variables
- [ ] Line 71: Remove or use `TOTAL_STEPS`
- [ ] Line 72: Remove or implement `CURRENT_STEP`
- [ ] Line 73: Remove or populate `STEP_DESCRIPTIONS`
- [ ] Line 76: Remove or use `ERROR_CONTEXT`

### 21. Fix SC2155 Warnings
- [ ] Separate declare and assign for all `local var=$(cmd)`
- [ ] Check return values properly
- [ ] Files: Multiple locations (see shellcheck output)

### 22. Add Error Context
- [ ] Populate ERROR_CONTEXT array with useful debug info
- [ ] Show context on errors
- [ ] Include: last command, current operation, remote host

## Additional Recommendations

### 23. Add Validation Mode
- [ ] New function: `validate_config_security()`
- [ ] Check for injection attempts in config
- [ ] Warn on suspicious values
- [ ] Run before any deployment

### 24. Add Rollback Capability
- [ ] Save pre-deployment state
- [ ] Create rollback script
- [ ] Allow reverting failed deployments

### 25. Improve Logging
- [ ] Add timestamp to all log messages
- [ ] Log to file and stdout
- [ ] Include hostname in remote logs
- [ ] Rotate log files

### 26. Add Health Checks
- [ ] Verify services after deployment
- [ ] Test actual functionality (HTTP requests)
- [ ] Validate monitoring is working
- [ ] Check resource usage

## Testing Checklist

### Security Testing
- [ ] Run with malicious YAML config (injection attempts)
- [ ] Check file permissions during execution
- [ ] Verify credentials never in /tmp
- [ ] Monitor process list for secrets
- [ ] Test concurrent deployments
- [ ] Send signals during execution
- [ ] Run shellcheck and fix all warnings
- [ ] Run as non-root user where possible

### Functional Testing
- [ ] Fresh Debian 13 deployment
- [ ] Resume after failure
- [ ] Deploy observability only
- [ ] Deploy vpsmanager only
- [ ] Deploy with --auto-approve
- [ ] Deploy with --plan
- [ ] Deploy with --validate-only
- [ ] Test on slow network
- [ ] Test with firewall enabled
- [ ] Test with existing services

### Edge Cases
- [ ] Config file missing
- [ ] Config file invalid YAML
- [ ] VPS unreachable
- [ ] SSH key already exists
- [ ] Services already installed
- [ ] Disk full on VPS
- [ ] Out of memory on VPS
- [ ] Network failure mid-deployment
- [ ] Multiple simultaneous deploys

## Priority Order

1. **Week 1: Critical Security** (Issues 1-5)
   - Command injection fixes
   - Temp file security
   - Credential handling

2. **Week 2: Major Security** (Issues 6-12)
   - Input validation
   - Race conditions
   - Service verification

3. **Week 3: Correctness** (Issues 13-19)
   - State management
   - Error handling
   - Feature completeness

4. **Week 4: Quality & Testing** (Issues 20-26)
   - Code cleanup
   - Testing
   - Documentation

## Sign-off Checklist

Before marking complete:
- [ ] All critical issues resolved
- [ ] All major issues resolved or documented
- [ ] Security review passed
- [ ] Functional tests passed
- [ ] Edge case tests passed
- [ ] Code review completed
- [ ] Documentation updated
- [ ] CHANGELOG updated

## Notes

- Use version control for all changes
- Test each fix independently
- Document any breaking changes
- Consider backward compatibility
- Update deployment guide with new requirements
