# Audit Fixes Tracking

**Related to:** Observability Stack Audit - 2025-12-25

## Critical Priority Fixes

### Error Handling - File Operations
- [ ] Fix `setup-observability.sh` line 835 (alert rules copy)
- [ ] Fix `setup-observability.sh` line 1010 (nginx reload)
- [ ] Fix `setup-observability.sh` lines 1656-1657 (dashboard copy)
- [ ] Fix `config-generator.sh` line 159 (alerts copy)
- [ ] Fix `config-generator.sh` line 194 (dashboard copy)

### Network Operations - Download Retry
- [ ] Add `safe_download()` function to `common.sh`
- [ ] Fix `setup-observability.sh` line 767 (prometheus download)
- [ ] Fix `setup-observability.sh` line 908 (node_exporter download)
- [ ] Fix `setup-observability.sh` line 983 (nginx_exporter download)
- [ ] Fix `setup-observability.sh` line 1080 (phpfpm_exporter download)
- [ ] Fix `setup-observability.sh` line 1184 (promtail download)
- [ ] Fix `setup-observability.sh` line 1328 (alertmanager download)
- [ ] Fix `setup-observability.sh` line 1490 (loki download)

### Race Conditions
- [ ] Use `safe_stop_service()` consistently in all scripts
- [ ] Fix service stop timing in `setup-observability.sh` (6 locations)

### Detection & Validation
- [ ] Add timeout to detection commands in `module-loader.sh` line 205
- [ ] Add `is_valid_ip()` function to `common.sh`
- [ ] Add IP validation in `setup-observability.sh` line 803

### State Management
- [ ] Fix module enable/disable idempotency in `module-manager.sh` lines 131-140
- [ ] Add failure tracking to `setup-monitored-host.sh` lines 209-247
- [ ] Cap confidence scores in `module-loader.sh` lines 234-250

## Medium Priority Fixes

### Service Verification
- [ ] Improve `verify_metrics()` in `node_exporter/install.sh`
- [ ] Improve `verify_metrics()` in `nginx_exporter/install.sh`
- [ ] Improve `verify_metrics()` in `mysqld_exporter/install.sh`
- [ ] Improve `verify_metrics()` in `phpfpm_exporter/install.sh`
- [ ] Improve `verify_metrics()` in `fail2ban_exporter/install.sh`
- [ ] Improve `start_service()` in `promtail/install.sh`

### SSL and Configuration
- [ ] Improve SSL error handling in `setup-observability.sh` line 1759
- [ ] Add config regeneration trigger to `module-manager.sh` enable/disable

## Testing Checklist

### Automated Tests
- [ ] Test download failure recovery
- [ ] Test file copy error handling
- [ ] Test module enable/disable idempotency
- [ ] Test partial installation failure
- [ ] Test detection timeout
- [ ] Test IP validation
- [ ] Test confidence score edge cases
- [ ] Test service startup verification

### Integration Tests
- [ ] Fresh install on clean Debian 13
- [ ] Upgrade from previous version
- [ ] Force reinstall with --force flag
- [ ] Uninstall with --purge flag
- [ ] Multiple hosts configuration
- [ ] Network failure scenarios

### Manual Testing
- [ ] Config diff display works correctly
- [ ] Backup creation and restoration
- [ ] Module auto-detection accuracy
- [ ] Grafana dashboard provisioning
- [ ] Alert rules deployment
- [ ] Service monitoring endpoints

## Documentation Updates

- [ ] Update README.md with new error handling behavior
- [ ] Document safe_download() and is_valid_ip() functions
- [ ] Add troubleshooting section for common failures
- [ ] Update upgrade guide with backup/restore procedures

## Estimated Completion

- Implementation: 2-3 days
- Testing: 1-2 days
- Documentation: 0.5 days
- **Total: 3.5 - 5.5 days**

## Dependencies

None - all fixes are self-contained

## Breaking Changes

None - all changes are backwards compatible

## Success Criteria

- [ ] All critical priority fixes implemented
- [ ] All tests passing
- [ ] No regression in existing functionality
- [ ] Documentation updated
- [ ] Code review completed
