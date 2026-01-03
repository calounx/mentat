# COMPREHENSIVE SHELL SCRIPT VALIDATION REPORT

**Generated:** Sat Jan  3 18:11:28 UTC 2026

## Summary

- **Total Scripts:** 87
- **Passed:** 14
- **Warnings:** 70
- **Errors:** 3
- **No Execute Permission:** 6

## Scripts with ERRORS (3)

### chom/deploy/observability-native/uninstall-all.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/observability-native/uninstall-all.sh:15:1: warning: MAGENTA appears unused. Verify use (or export if used externally). [SC2034]
/home/calounx/repositories/mentat/chom/deploy/observability-native/uninstall-all.sh:69:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/observability-native/uninstall-all.sh:73:30: note: Note that A && B || C is not if-then-else. C may run when A is true. [SC2015]
/home/calounx/repositories/mentat/chom/deploy/observability-native/uninstall-all.sh:74:27: note: Note that A && B || C is not if-then-else. C may run when A is true. [SC2015]
/home/calounx/repositories/mentat/chom/deploy/observability-native/uninstall-all.sh:75:24: note: Note that A && B || C is not if-then-else. C may run when A is true. [SC2015]
/home/calounx/repositories/mentat/chom/deploy/observability-native/uninstall-all.sh:76:28: note: Note that A && B || C is not if-then-else. C may run when A is true. [SC2015]
/home/calounx/repositories/mentat/chom/deploy/observability-native/uninstall-all.sh:77:32: note: Note that A && B || C is not if-then-else. C may run when A is true. [SC2015]
/home/calounx/repositories/mentat/chom/deploy/observability-native/uninstall-all.sh:296:5: warning: Use -print0/-0 or -exec + to allow for non-alphanumeric filenames. [SC2038]
/home/calounx/repositories/mentat/chom/deploy/observability-native/uninstall-all.sh:323:14: error: -d doesn't work with globs. Use a for loop. [SC2144]
/home/calounx/repositories/mentat/chom/deploy/observability-native/uninstall-all.sh:324:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/observability-native/uninstall-all.sh:324:28: note: Use find instead of ls to better handle non-alphanumeric filenames. [SC2012]
```

### chom/deploy/troubleshooting/emergency-diagnostics.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:85:63: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:163:47: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:199:5: error: 'local' is only valid in functions. [SC2168]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:199:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:201:56: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:218:41: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:270:40: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:289:40: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:292:40: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:295:40: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:331:5: error: 'local' is only valid in functions. [SC2168]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:331:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:338:9: error: 'local' is only valid in functions. [SC2168]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:338:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:338:81: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:345:5: error: 'local' is only valid in functions. [SC2168]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:345:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:348:5: error: 'local' is only valid in functions. [SC2168]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:348:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:354:5: error: 'local' is only valid in functions. [SC2168]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:354:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:354:66: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:357:5: error: 'local' is only valid in functions. [SC2168]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:357:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:363:5: note: Use find instead of ls to better handle non-alphanumeric filenames. [SC2012]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:379:5: error: 'local' is only valid in functions. [SC2168]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh:379:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/security/generate-secure-secrets.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** MISSING
- **Bash Syntax:** ERROR

**Bash Syntax Errors:**
```
/home/calounx/repositories/mentat/deploy/security/generate-secure-secrets.sh: line 355: syntax error near unexpected token `)'
/home/calounx/repositories/mentat/deploy/security/generate-secure-secrets.sh: line 355: `    log_success "Encryption key generated (${#encryption_key} characters, 256-bit)")'

```

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/security/generate-secure-secrets.sh:343:1: note: The mentioned syntax error was in this function. [SC1009]
/home/calounx/repositories/mentat/deploy/security/generate-secure-secrets.sh:343:27: error: Couldn't parse this brace group. Fix to allow more checks. [SC1073]
/home/calounx/repositories/mentat/deploy/security/generate-secure-secrets.sh:355:84: error: Expected a '}'. If you have one, try a ; or \n in front of it. [SC1056]
/home/calounx/repositories/mentat/deploy/security/generate-secure-secrets.sh:355:84: error: Missing '}'. Fix any mentioned problems and try again. [SC1072]
```

## Scripts with WARNINGS (70)

### chom/deploy/database/audit-database-users.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/database/audit-database-users.sh:26:1: warning: MYSQL_CMD appears unused. Verify use (or export if used externally). [SC2034]
/home/calounx/repositories/mentat/chom/deploy/database/audit-database-users.sh:39:5: note: read without -r will mangle backslashes. [SC2162]
/home/calounx/repositories/mentat/chom/deploy/database/audit-database-users.sh:45:15: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/audit-database-users.sh:45:29: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/audit-database-users.sh:45:43: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/audit-database-users.sh:45:61: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/audit-database-users.sh:68:1: note: Consider using { cmd1; cmd2; } >> file instead of individual redirects. [SC2129]
/home/calounx/repositories/mentat/chom/deploy/database/audit-database-users.sh:73:10: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/audit-database-users.sh:73:24: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/audit-database-users.sh:73:38: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/audit-database-users.sh:73:56: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/audit-database-users.sh:104:23: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/audit-database-users.sh:104:37: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/audit-database-users.sh:104:51: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/audit-database-users.sh:104:69: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/audit-database-users.sh:108:14: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/audit-database-users.sh:108:28: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/audit-database-users.sh:108:42: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/audit-database-users.sh:108:60: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/audit-database-users.sh:115:26: note: Double quote to prevent globbing and word splitting. [SC2086]

... and 91 more issues
```

### chom/deploy/database/mariadb-health-check.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/database/mariadb-health-check.sh:28:1: warning: BUFFER_POOL_THRESHOLD appears unused. Verify use (or export if used externally). [SC2034]
/home/calounx/repositories/mentat/chom/deploy/database/mariadb-health-check.sh:46:5: note: read without -r will mangle backslashes. [SC2162]
/home/calounx/repositories/mentat/chom/deploy/database/mariadb-health-check.sh:52:15: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/mariadb-health-check.sh:52:29: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/mariadb-health-check.sh:52:43: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/mariadb-health-check.sh:52:56: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/mariadb-health-check.sh:79:14: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/mariadb-health-check.sh:79:28: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/mariadb-health-check.sh:79:42: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/mariadb-health-check.sh:79:55: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/mariadb-health-check.sh:240:13: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/mariadb-health-check.sh:240:27: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/mariadb-health-check.sh:240:41: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/mariadb-health-check.sh:240:54: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/mariadb-health-check.sh:244:18: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/mariadb-health-check.sh:244:32: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/mariadb-health-check.sh:244:46: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/mariadb-health-check.sh:244:59: note: Double quote to prevent globbing and word splitting. [SC2086]
```

### chom/deploy/database/point-in-time-recovery.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/database/point-in-time-recovery.sh:51:1: note: read without -r will mangle backslashes. [SC2162]
/home/calounx/repositories/mentat/chom/deploy/database/point-in-time-recovery.sh:56:5: note: read without -r will mangle backslashes. [SC2162]
/home/calounx/repositories/mentat/chom/deploy/database/point-in-time-recovery.sh:62:5: note: read without -r will mangle backslashes. [SC2162]
/home/calounx/repositories/mentat/chom/deploy/database/point-in-time-recovery.sh:74:74: note: read without -r will mangle backslashes. [SC2162]
/home/calounx/repositories/mentat/chom/deploy/database/point-in-time-recovery.sh:108:9: note: read without -r will mangle backslashes. [SC2162]
/home/calounx/repositories/mentat/chom/deploy/database/point-in-time-recovery.sh:136:1: note: read without -r will mangle backslashes. [SC2162]
/home/calounx/repositories/mentat/chom/deploy/database/point-in-time-recovery.sh:142:10: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/point-in-time-recovery.sh:142:24: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/point-in-time-recovery.sh:142:38: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/point-in-time-recovery.sh:142:51: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/point-in-time-recovery.sh:148:10: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/point-in-time-recovery.sh:148:24: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/point-in-time-recovery.sh:148:38: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/point-in-time-recovery.sh:148:51: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/point-in-time-recovery.sh:154:10: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/point-in-time-recovery.sh:154:24: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/point-in-time-recovery.sh:154:38: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/point-in-time-recovery.sh:154:51: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/database/point-in-time-recovery.sh:171:5: note: read without -r will mangle backslashes. [SC2162]
/home/calounx/repositories/mentat/chom/deploy/database/point-in-time-recovery.sh:174:5: note: read without -r will mangle backslashes. [SC2162]

... and 14 more issues
```

### chom/deploy/monitoring/deployment-history.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-history.sh:44:51: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-history.sh:52:1: note: ssh may swallow stdin, preventing this loop from working properly. [SC2095]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-history.sh:84:53: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-history.sh:87:53: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-history.sh:90:59: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-history.sh:97:8: warning: Use ssh -n to prevent ssh from swallowing stdin. [SC2095]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-history.sh:97:48: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-history.sh:98:12: warning: Use ssh -n to prevent ssh from swallowing stdin. [SC2095]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-history.sh:98:62: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-history.sh:100:14: warning: Use ssh -n to prevent ssh from swallowing stdin. [SC2095]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-history.sh:100:63: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-history.sh:105:74: note: Note that, unescaped, this expands on the client side. [SC2029]
```

### chom/deploy/monitoring/deployment-status.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-status.sh:72:67: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-status.sh:75:62: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-status.sh:85:71: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-status.sh:95:53: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-status.sh:105:64: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-status.sh:112:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-status.sh:113:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-status.sh:114:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-status.sh:130:55: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-status.sh:139:54: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-status.sh:150:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-status.sh:151:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-status.sh:167:48: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-status.sh:198:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-status.sh:204:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-status.sh:205:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-status.sh:206:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-status.sh:214:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-status.sh:215:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/deployment-status.sh:216:11: warning: Declare and assign separately to avoid masking return values. [SC2155]

... and 27 more issues
```

### chom/deploy/monitoring/resource-monitor.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/monitoring/resource-monitor.sh:48:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/resource-monitor.sh:66:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/resource-monitor.sh:67:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/resource-monitor.sh:74:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/resource-monitor.sh:75:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/resource-monitor.sh:76:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/resource-monitor.sh:92:19: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/resource-monitor.sh:93:19: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/resource-monitor.sh:94:19: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/resource-monitor.sh:95:19: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/resource-monitor.sh:105:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/resource-monitor.sh:106:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/resource-monitor.sh:107:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/resource-monitor.sh:108:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/resource-monitor.sh:120:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/resource-monitor.sh:128:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/resource-monitor.sh:129:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/resource-monitor.sh:130:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/resource-monitor.sh:131:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/resource-monitor.sh:134:11: warning: Declare and assign separately to avoid masking return values. [SC2155]

... and 43 more issues
```

### chom/deploy/monitoring/service-status.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/monitoring/service-status.sh:43:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/service-status.sh:43:77: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/monitoring/service-status.sh:55:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/service-status.sh:55:70: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/monitoring/service-status.sh:74:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/service-status.sh:75:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/service-status.sh:76:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/service-status.sh:77:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/service-status.sh:83:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/service-status.sh:84:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/service-status.sh:85:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/service-status.sh:86:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/service-status.sh:87:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/service-status.sh:88:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/service-status.sh:95:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/service-status.sh:96:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/service-status.sh:97:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/service-status.sh:102:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/service-status.sh:103:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/monitoring/service-status.sh:110:11: warning: Declare and assign separately to avoid masking return values. [SC2155]

... and 23 more issues
```

### chom/deploy/observability-native/install-alertmanager.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/observability-native/install-alertmanager.sh:80:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### chom/deploy/observability-native/install-all.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/observability-native/install-all.sh:25:1: warning: APP_SERVER appears unused. Verify use (or export if used externally). [SC2034]
/home/calounx/repositories/mentat/chom/deploy/observability-native/install-all.sh:97:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/observability-native/install-all.sh:97:32: note: Useless cat. Consider 'cmd < file | ..' or 'cmd file | ..' instead. [SC2002]
/home/calounx/repositories/mentat/chom/deploy/observability-native/install-all.sh:109:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/observability-native/install-all.sh:118:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/observability-native/install-all.sh:119:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/observability-native/install-all.sh:127:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### chom/deploy/observability-native/install-loki.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/observability-native/install-loki.sh:91:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### chom/deploy/observability-native/install-node-exporter.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/observability-native/install-node-exporter.sh:58:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### chom/deploy/observability-native/install-prometheus.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/observability-native/install-prometheus.sh:81:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### chom/deploy/observability-native/install-promtail.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/observability-native/install-promtail.sh:90:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### chom/deploy/observability-native/manage-services.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/observability-native/manage-services.sh:100:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/observability-native/manage-services.sh:101:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/observability-native/manage-services.sh:367:19: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### chom/deploy/troubleshooting/analyze-logs.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/analyze-logs.sh:63:50: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/analyze-logs.sh:69:11: warning: cutoff_time appears unused. Verify use (or export if used externally). [SC2034]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/analyze-logs.sh:75:89: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/analyze-logs.sh:88:57: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/analyze-logs.sh:96:53: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/analyze-logs.sh:104:64: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/analyze-logs.sh:106:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/analyze-logs.sh:107:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/analyze-logs.sh:118:55: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/analyze-logs.sh:127:66: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/analyze-logs.sh:130:67: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/analyze-logs.sh:133:66: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/analyze-logs.sh:148:57: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/analyze-logs.sh:149:19: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/analyze-logs.sh:160:55: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/analyze-logs.sh:169:66: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/analyze-logs.sh:172:66: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/analyze-logs.sh:175:66: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/analyze-logs.sh:178:66: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/analyze-logs.sh:190:57: note: Note that, unescaped, this expands on the client side. [SC2029]

... and 15 more issues
```

### chom/deploy/troubleshooting/test-connections.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/test-connections.sh:48:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/test-connections.sh:50:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/test-connections.sh:64:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/test-connections.sh:64:70: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/test-connections.sh:65:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/test-connections.sh:65:70: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/test-connections.sh:66:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/test-connections.sh:66:74: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/test-connections.sh:67:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/test-connections.sh:67:74: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/test-connections.sh:68:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/test-connections.sh:68:74: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/test-connections.sh:78:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/test-connections.sh:79:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/test-connections.sh:79:64: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/test-connections.sh:80:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/test-connections.sh:87:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/test-connections.sh:88:53: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/test-connections.sh:89:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/troubleshooting/test-connections.sh:103:11: warning: Declare and assign separately to avoid masking return values. [SC2155]

... and 39 more issues
```

### chom/deploy/validation/migration-check.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/validation/migration-check.sh:75:59: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/migration-check.sh:84:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/migration-check.sh:85:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/migration-check.sh:116:50: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/migration-check.sh:138:55: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/migration-check.sh:152:62: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/migration-check.sh:169:51: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/migration-check.sh:210:54: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/migration-check.sh:250:55: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/migration-check.sh:275:60: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/migration-check.sh:278:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/migration-check.sh:281:9: note: ssh may swallow stdin, preventing this loop from working properly. [SC2095]
/home/calounx/repositories/mentat/chom/deploy/validation/migration-check.sh:282:16: warning: Use ssh -n to prevent ssh from swallowing stdin. [SC2095]
/home/calounx/repositories/mentat/chom/deploy/validation/migration-check.sh:282:82: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/migration-check.sh:308:57: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/migration-check.sh:329:60: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/migration-check.sh:347:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/migration-check.sh:362:50: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/migration-check.sh:380:55: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/migration-check.sh:416:48: note: Note that, unescaped, this expands on the client side. [SC2029]

... and 3 more issues
```

### chom/deploy/validation/observability-check.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/validation/observability-check.sh:80:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/observability-check.sh:90:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/observability-check.sh:94:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/observability-check.sh:97:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/observability-check.sh:98:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/observability-check.sh:109:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/observability-check.sh:118:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/observability-check.sh:129:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/observability-check.sh:139:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/observability-check.sh:143:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/observability-check.sh:152:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/observability-check.sh:155:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/observability-check.sh:167:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/observability-check.sh:177:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/observability-check.sh:182:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/observability-check.sh:190:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/observability-check.sh:204:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/observability-check.sh:214:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/observability-check.sh:217:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/observability-check.sh:218:15: warning: Declare and assign separately to avoid masking return values. [SC2155]

... and 15 more issues
```

### chom/deploy/validation/performance-check.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/validation/performance-check.sh:90:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/performance-check.sh:108:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/performance-check.sh:108:70: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/performance-check.sh:122:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/performance-check.sh:124:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/performance-check.sh:149:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/performance-check.sh:159:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/performance-check.sh:159:70: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/performance-check.sh:173:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/performance-check.sh:175:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/performance-check.sh:200:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/performance-check.sh:216:5: warning: i appears unused. Verify use (or export if used externally). [SC2034]
/home/calounx/repositories/mentat/chom/deploy/validation/performance-check.sh:217:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/performance-check.sh:218:44: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/performance-check.sh:224:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/performance-check.sh:249:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/performance-check.sh:259:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/performance-check.sh:260:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/performance-check.sh:261:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/performance-check.sh:262:11: warning: Declare and assign separately to avoid masking return values. [SC2155]

... and 21 more issues
```

### chom/deploy/validation/post-deployment-check.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/validation/post-deployment-check.sh:22:1: warning: PROJECT_ROOT appears unused. Verify use (or export if used externally). [SC2034]
/home/calounx/repositories/mentat/chom/deploy/validation/post-deployment-check.sh:96:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/chom/deploy/validation/post-deployment-check.sh:97:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/chom/deploy/validation/post-deployment-check.sh:98:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/chom/deploy/validation/post-deployment-check.sh:98:23: note: Want to escape a single quote? echo 'This is how it'\''s done'. [SC1003]
/home/calounx/repositories/mentat/chom/deploy/validation/post-deployment-check.sh:99:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/chom/deploy/validation/post-deployment-check.sh:99:11: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/chom/deploy/validation/post-deployment-check.sh:99:17: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/validation/post-deployment-check.sh:100:9: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/chom/deploy/validation/post-deployment-check.sh:101:9: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/chom/deploy/validation/post-deployment-check.sh:102:9: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/chom/deploy/validation/post-deployment-check.sh:103:9: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/chom/deploy/validation/post-deployment-check.sh:103:15: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/validation/post-deployment-check.sh:104:9: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/chom/deploy/validation/post-deployment-check.sh:106:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/chom/deploy/validation/post-deployment-check.sh:143:64: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/post-deployment-check.sh:153:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/post-deployment-check.sh:154:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/post-deployment-check.sh:155:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/post-deployment-check.sh:168:15: warning: Declare and assign separately to avoid masking return values. [SC2155]

... and 39 more issues
```

### chom/deploy/validation/pre-deployment-check.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/validation/pre-deployment-check.sh:215:59: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/pre-deployment-check.sh:275:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/pre-deployment-check.sh:276:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/pre-deployment-check.sh:298:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/pre-deployment-check.sh:317:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/pre-deployment-check.sh:318:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/pre-deployment-check.sh:319:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/pre-deployment-check.sh:355:50: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/pre-deployment-check.sh:364:54: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/pre-deployment-check.sh:367:53: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/chom/deploy/validation/pre-deployment-check.sh:398:55: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/pre-deployment-check.sh:400:55: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/pre-deployment-check.sh:450:36: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/pre-deployment-check.sh:455:60: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/pre-deployment-check.sh:458:19: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/pre-deployment-check.sh:459:19: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/pre-deployment-check.sh:460:19: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/pre-deployment-check.sh:473:40: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/pre-deployment-check.sh:490:31: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/pre-deployment-check.sh:492:46: note: Note that, unescaped, this expands on the client side. [SC2029]

... and 7 more issues
```

### chom/deploy/validation/rollback-test.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/validation/rollback-test.sh:77:48: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/rollback-test.sh:82:63: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/rollback-test.sh:91:52: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/rollback-test.sh:108:48: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/rollback-test.sh:113:70: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/rollback-test.sh:116:19: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/rollback-test.sh:120:56: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/rollback-test.sh:138:63: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/rollback-test.sh:153:52: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/rollback-test.sh:162:55: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/rollback-test.sh:179:48: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/rollback-test.sh:184:62: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/rollback-test.sh:192:52: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/rollback-test.sh:193:23: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/rollback-test.sh:194:23: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/rollback-test.sh:194:76: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/rollback-test.sh:200:67: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/rollback-test.sh:204:74: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/rollback-test.sh:205:23: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/rollback-test.sh:229:48: note: Note that, unescaped, this expands on the client side. [SC2029]

... and 15 more issues
```

### chom/deploy/validation/security-check.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/validation/security-check.sh:73:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/security-check.sh:73:70: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/security-check.sh:80:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/security-check.sh:93:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/security-check.sh:94:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/security-check.sh:100:19: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/security-check.sh:101:19: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/security-check.sh:102:19: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/security-check.sh:121:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/security-check.sh:121:70: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/security-check.sh:127:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/security-check.sh:131:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/security-check.sh:154:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/security-check.sh:182:48: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/security-check.sh:187:19: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/security-check.sh:187:68: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/security-check.sh:198:48: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/security-check.sh:209:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/security-check.sh:209:68: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/security-check.sh:218:11: warning: Declare and assign separately to avoid masking return values. [SC2155]

... and 33 more issues
```

### chom/deploy/validation/smoke-tests.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/chom/deploy/validation/smoke-tests.sh:55:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/smoke-tests.sh:55:70: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/smoke-tests.sh:62:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/smoke-tests.sh:63:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/smoke-tests.sh:64:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/smoke-tests.sh:75:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/smoke-tests.sh:75:70: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/smoke-tests.sh:82:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/smoke-tests.sh:83:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/smoke-tests.sh:84:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/smoke-tests.sh:95:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/smoke-tests.sh:95:70: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/smoke-tests.sh:102:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/smoke-tests.sh:103:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/smoke-tests.sh:104:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/smoke-tests.sh:115:11: warning: result appears unused. Verify use (or export if used externally). [SC2034]
/home/calounx/repositories/mentat/chom/deploy/validation/smoke-tests.sh:115:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/smoke-tests.sh:115:55: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/chom/deploy/validation/smoke-tests.sh:117:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/chom/deploy/validation/smoke-tests.sh:118:11: warning: Declare and assign separately to avoid masking return values. [SC2155]

... and 48 more issues
```

### deploy/deploy-chom-automated.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** MISSING
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/deploy-chom-automated.sh:30:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/deploy-chom-automated.sh:104:8: note: Not following: ./utils/logging.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/deploy-chom-automated.sh:105:8: note: Not following: ./utils/notifications.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/deploy-chom-automated.sh:106:8: note: Not following: ./utils/dependency-validation.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/deploy-chom-automated.sh:234:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/deploy-chom-automated.sh:240:13: note: read without -r will mangle backslashes. [SC2162]
/home/calounx/repositories/mentat/deploy/deploy-chom-automated.sh:288:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/deploy-chom-automated.sh:292:41: note: $/${} is unnecessary on arithmetic variables. [SC2004]
/home/calounx/repositories/mentat/deploy/deploy-chom-automated.sh:368:9: note: read without -r will mangle backslashes. [SC2162]
/home/calounx/repositories/mentat/deploy/deploy-chom-automated.sh:404:98: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/deploy/deploy-chom-automated.sh:441:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/deploy-chom-automated.sh:441:40: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/deploy-chom-automated.sh:444:33: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/deploy/deploy-chom-automated.sh:478:20: warning: ShellCheck can't follow non-constant source. Use a directive to specify location. [SC1090]
/home/calounx/repositories/mentat/deploy/deploy-chom-automated.sh:498:20: warning: ShellCheck can't follow non-constant source. Use a directive to specify location. [SC1090]
/home/calounx/repositories/mentat/deploy/deploy-chom-automated.sh:766:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/deploy-chom-automated.sh:767:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/deploy-chom-automated.sh:767:42: warning: Expanding an array without an index only gives the first element. [SC2128]
/home/calounx/repositories/mentat/deploy/deploy-chom-automated.sh:768:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/deploy-chom-automated.sh:769:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]

... and 2 more issues
```

### deploy/deploy-chom.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/deploy-chom.sh:16:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/deploy-chom.sh:90:8: note: Not following: ./utils/logging.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/deploy-chom.sh:91:8: note: Not following: ./utils/notifications.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/deploy-chom.sh:92:8: note: Not following: ./utils/dependency-validation.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/deploy-chom.sh:199:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/deploy-chom.sh:200:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/deploy-chom.sh:202:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/deploy-chom.sh:204:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/deploy-chom.sh:221:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/deploy-chom.sh:255:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/deploy-chom.sh:268:85: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/deploy/deploy-chom.sh:286:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/deploy-chom.sh:328:48: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/deploy/deploy-chom.sh:355:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/deploy-chom.sh:379:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/deploy-chom.sh:388:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/deploy.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/deploy.sh:91:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/deploy.sh:92:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/deploy.sh:93:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/deploy.sh:94:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/deploy.sh:120:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/deploy.sh:121:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/deploy.sh:122:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/deploy.sh:123:11: warning: hostname appears unused. Verify use (or export if used externally). [SC2034]
/home/calounx/repositories/mentat/deploy/deploy.sh:123:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/deploy.sh:124:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/deploy.sh:151:9: warning: dry_run appears unused. Verify use (or export if used externally). [SC2034]
```

### deploy/scripts/backup-before-deploy.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/scripts/backup-before-deploy.sh:14:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/backup-before-deploy.sh:60:8: note: Not following: ./../utils/logging.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/scripts/backup-before-deploy.sh:111:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/backup-before-deploy.sh:112:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/backup-before-deploy.sh:113:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/backup-before-deploy.sh:114:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/backup-before-deploy.sh:115:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/backup-before-deploy.sh:137:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/backup-before-deploy.sh:142:9: note: Consider using { cmd1; cmd2; } >> file instead of individual redirects. [SC2129]
/home/calounx/repositories/mentat/deploy/scripts/backup-before-deploy.sh:177:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/backup-before-deploy.sh:220:20: warning: Quote this to prevent word splitting. [SC2046]
/home/calounx/repositories/mentat/deploy/scripts/backup-before-deploy.sh:220:30: warning: Quote this to prevent word splitting. [SC2046]
/home/calounx/repositories/mentat/deploy/scripts/backup-before-deploy.sh:222:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/backup-before-deploy.sh:276:17: note: Quote expansions in this for loop glob to prevent wordsplitting, e.g. "$dir"/*.txt . [SC2231]
/home/calounx/repositories/mentat/deploy/scripts/backup-before-deploy.sh:276:33: note: Quote expansions in this for loop glob to prevent wordsplitting, e.g. "$dir"/*.txt . [SC2231]
/home/calounx/repositories/mentat/deploy/scripts/backup-before-deploy.sh:278:19: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/backup-before-deploy.sh:291:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/backup-before-deploy.sh:291:26: note: Use find instead of ls to better handle non-alphanumeric filenames. [SC2012]
/home/calounx/repositories/mentat/deploy/scripts/backup-before-deploy.sh:291:32: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/backup-before-deploy.sh:304:11: warning: Declare and assign separately to avoid masking return values. [SC2155]

... and 4 more issues
```

### deploy/scripts/deploy-application.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/scripts/deploy-application.sh:16:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/deploy-application.sh:62:8: note: Not following: ./../utils/logging.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/scripts/deploy-application.sh:63:8: note: Not following: ./../utils/notifications.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/scripts/deploy-application.sh:64:8: note: Not following: ./../utils/dependency-validation.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/scripts/deploy-application.sh:123:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/scripts/deploy-application.sh:124:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/scripts/deploy-application.sh:126:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/scripts/deploy-application.sh:126:94: warning: Expanding an array without an index only gives the first element. [SC2128]
/home/calounx/repositories/mentat/deploy/scripts/deploy-application.sh:129:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/scripts/deploy-application.sh:131:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/scripts/deploy-application.sh:131:8: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/scripts/deploy-application.sh:132:9: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/scripts/deploy-application.sh:134:9: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/scripts/deploy-application.sh:137:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/scripts/deploy-application.sh:145:10: note: Useless echo? Instead of 'echo $(cmd)', just use 'cmd'. [SC2005]
/home/calounx/repositories/mentat/deploy/scripts/deploy-application.sh:171:19: note: See if you can use ${variable//search/replace} instead. [SC2001]
/home/calounx/repositories/mentat/deploy/scripts/deploy-application.sh:179:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/deploy-application.sh:180:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/deploy-application.sh:341:19: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/deploy-application.sh:381:30: note: Double quote to prevent globbing and word splitting. [SC2086]

... and 6 more issues
```

### deploy/scripts/deploy-observability.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/scripts/deploy-observability.sh:16:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/deploy-observability.sh:61:8: note: Not following: ./../utils/logging.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/scripts/deploy-observability.sh:62:8: note: Not following: ./../utils/dependency-validation.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/scripts/deploy-observability.sh:148:30: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/deploy-observability.sh:156:30: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/deploy-observability.sh:329:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/scripts/generate-deployment-secrets.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/scripts/generate-deployment-secrets.sh:17:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/generate-deployment-secrets.sh:62:8: note: Not following: ./../utils/logging.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/scripts/generate-deployment-secrets.sh:63:8: note: Not following: ./../utils/dependency-validation.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/scripts/generate-deployment-secrets.sh:99:53: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/generate-deployment-secrets.sh:114:9: note: read without -r will mangle backslashes. [SC2162]
/home/calounx/repositories/mentat/deploy/scripts/generate-deployment-secrets.sh:127:9: note: read without -r will mangle backslashes. [SC2162]
/home/calounx/repositories/mentat/deploy/scripts/generate-deployment-secrets.sh:142:9: note: read without -r will mangle backslashes. [SC2162]
/home/calounx/repositories/mentat/deploy/scripts/generate-deployment-secrets.sh:156:16: warning: ShellCheck can't follow non-constant source. Use a directive to specify location. [SC1090]
/home/calounx/repositories/mentat/deploy/scripts/generate-deployment-secrets.sh:169:9: warning: existing_file appears unused. Verify use (or export if used externally). [SC2034]
/home/calounx/repositories/mentat/deploy/scripts/generate-deployment-secrets.sh:172:16: warning: ShellCheck can't follow non-constant source. Use a directive to specify location. [SC1090]
/home/calounx/repositories/mentat/deploy/scripts/generate-deployment-secrets.sh:302:13: note: read without -r will mangle backslashes. [SC2162]
/home/calounx/repositories/mentat/deploy/scripts/generate-deployment-secrets.sh:352:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/scripts/health-check.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/scripts/health-check.sh:15:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/health-check.sh:61:8: note: Not following: ./../utils/logging.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/scripts/health-check.sh:138:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/health-check.sh:160:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/health-check.sh:161:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/health-check.sh:162:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/health-check.sh:163:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/health-check.sh:164:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/health-check.sh:197:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/health-check.sh:215:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/health-check.sh:216:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/health-check.sh:268:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/health-check.sh:328:19: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/health-check.sh:355:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/health-check.sh:385:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/health-check.sh:386:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/health-check.sh:387:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/scripts/preflight-check.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/scripts/preflight-check.sh:15:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/preflight-check.sh:61:8: note: Not following: ./../utils/logging.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/scripts/preflight-check.sh:161:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/preflight-check.sh:162:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/preflight-check.sh:177:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/preflight-check.sh:189:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/preflight-check.sh:201:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/preflight-check.sh:212:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/preflight-check.sh:222:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/preflight-check.sh:324:11: warning: ip appears unused. Verify use (or export if used externally). [SC2034]
/home/calounx/repositories/mentat/deploy/scripts/preflight-check.sh:586:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/scripts/prepare-landsraad.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/scripts/prepare-landsraad.sh:21:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/prepare-landsraad.sh:66:8: note: Not following: ./../utils/logging.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/scripts/prepare-landsraad.sh:67:8: note: Not following: ./../utils/dependency-validation.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/scripts/prepare-landsraad.sh:110:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/prepare-landsraad.sh:135:12: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/prepare-landsraad.sh:136:12: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/prepare-landsraad.sh:137:12: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/prepare-landsraad.sh:138:12: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/prepare-landsraad.sh:139:12: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/prepare-landsraad.sh:140:12: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/prepare-landsraad.sh:141:12: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/prepare-landsraad.sh:142:12: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/prepare-landsraad.sh:143:12: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/prepare-landsraad.sh:144:12: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/prepare-landsraad.sh:145:12: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/prepare-landsraad.sh:146:12: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/prepare-landsraad.sh:147:12: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/prepare-landsraad.sh:148:12: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/prepare-landsraad.sh:149:12: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/prepare-landsraad.sh:150:12: note: Double quote to prevent globbing and word splitting. [SC2086]

... and 16 more issues
```

### deploy/scripts/prepare-mentat.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/scripts/prepare-mentat.sh:21:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/prepare-mentat.sh:86:8: note: Not following: ./../utils/logging.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/scripts/prepare-mentat.sh:87:8: note: Not following: ./../utils/dependency-validation.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/scripts/prepare-mentat.sh:143:25: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/prepare-mentat.sh:144:19: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/prepare-mentat.sh:144:34: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/prepare-mentat.sh:144:55: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/prepare-mentat.sh:145:26: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/prepare-mentat.sh:192:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/prepare-mentat.sh:284:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/scripts/rollback.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/scripts/rollback.sh:14:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/rollback.sh:61:8: note: Not following: ./../utils/logging.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/scripts/rollback.sh:62:8: note: Not following: ./../utils/notifications.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/scripts/rollback.sh:113:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/rollback.sh:116:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/rollback.sh:138:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/rollback.sh:140:5: note: Use find instead of ls to better handle non-alphanumeric filenames. [SC2012]
/home/calounx/repositories/mentat/deploy/scripts/rollback.sh:140:36: note: read without -r will mangle backslashes. [SC2162]
/home/calounx/repositories/mentat/deploy/scripts/rollback.sh:166:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/rollback.sh:185:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/rollback.sh:201:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/rollback.sh:202:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/rollback.sh:203:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/rollback.sh:204:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/rollback.sh:205:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/rollback.sh:209:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/rollback.sh:279:30: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/rollback.sh:317:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/rollback.sh:324:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/rollback.sh:336:9: note: read without -r will mangle backslashes. [SC2162]

... and 1 more issues
```

### deploy/scripts/setup-ssh-automation.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-automation.sh:16:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-automation.sh:61:8: note: Not following: ./../utils/logging.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-automation.sh:62:8: note: Not following: ./../utils/dependency-validation.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-automation.sh:119:47: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-automation.sh:124:44: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-automation.sh:132:65: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-automation.sh:134:61: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-automation.sh:144:40: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-automation.sh:154:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-automation.sh:154:59: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-automation.sh:157:46: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-automation.sh:165:49: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-automation.sh:168:40: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-automation.sh:169:51: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-automation.sh:181:80: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-automation.sh:210:47: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-automation.sh:215:46: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-automation.sh:228:73: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-automation.sh:233:47: note: Note that, unescaped, this expands on the client side. [SC2029]
```

### deploy/scripts/setup-ssh-keys.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-keys.sh:8:8: note: Not following: ./../utils/logging.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-keys.sh:58:11: note: Check exit code directly with e.g. 'if mycmd;', not indirectly with $?. [SC2181]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-keys.sh:75:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-keys.sh:77:86: note: Note that, unescaped, this expands on the client side. [SC2029]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-keys.sh:79:15: note: Check exit code directly with e.g. 'if mycmd;', not indirectly with $?. [SC2181]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-keys.sh:117:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssh-keys.sh:159:11: note: Check exit code directly with e.g. 'if mycmd;', not indirectly with $?. [SC2181]
```

### deploy/scripts/setup-ssl.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/scripts/setup-ssl.sh:8:8: note: Not following: ./../utils/logging.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssl.sh:130:11: note: Check exit code directly with e.g. 'if mycmd;', not indirectly with $?. [SC2181]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssl.sh:163:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssl.sh:164:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/setup-ssl.sh:165:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/scripts/setup-stilgar-user-standalone.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/scripts/setup-stilgar-user-standalone.sh:75:5: warning: USER_EXISTS appears unused. Verify use (or export if used externally). [SC2034]
/home/calounx/repositories/mentat/deploy/scripts/setup-stilgar-user-standalone.sh:166:26: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/setup-stilgar-user-standalone.sh:167:26: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/setup-stilgar-user-standalone.sh:168:30: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/scripts/setup-stilgar-user-standalone.sh:170:36: note: Double quote to prevent globbing and word splitting. [SC2086]
```

### deploy/scripts/setup-stilgar-user.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/scripts/setup-stilgar-user.sh:20:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/scripts/setup-stilgar-user.sh:65:8: note: Not following: ./../utils/logging.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/scripts/setup-stilgar-user.sh:66:8: note: Not following: ./../utils/dependency-validation.sh was not specified as input (see shellcheck -x). [SC1091]
```

### deploy/scripts/setup-vpsmanager-vps.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/scripts/setup-vpsmanager-vps.sh:18:1: warning: REDIS_VERSION appears unused. Verify use (or export if used externally). [SC2034]
```

### deploy/security/compliance-check.sh

- **Executable:** No
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/security/compliance-check.sh:20:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/compliance-check.sh:134:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/compliance-check.sh:147:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/compliance-check.sh:208:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/compliance-check.sh:208:54: note: Consider using 'grep -c' instead of 'grep|wc -l'. [SC2126]
/home/calounx/repositories/mentat/deploy/security/compliance-check.sh:276:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/compliance-check.sh:293:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/compliance-check.sh:321:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/compliance-check.sh:321:54: note: Consider using 'grep -c' instead of 'grep|wc -l'. [SC2126]
/home/calounx/repositories/mentat/deploy/security/compliance-check.sh:423:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/compliance-check.sh:440:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/security/configure-access-control.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/security/configure-access-control.sh:19:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/configure-access-control.sh:99:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/configure-access-control.sh:211:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/security/configure-firewall.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/security/configure-firewall.sh:20:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/configure-firewall.sh:111:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/configure-firewall.sh:348:11: warning: Variable was used as an array but is now assigned a string. [SC2178]
/home/calounx/repositories/mentat/deploy/security/configure-firewall.sh:455:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/security/create-deployment-user.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/security/create-deployment-user.sh:28:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/create-deployment-user.sh:77:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/create-deployment-user.sh:83:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/create-deployment-user.sh:89:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/create-deployment-user.sh:95:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/create-deployment-user.sh:197:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/create-deployment-user.sh:198:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/create-deployment-user.sh:212:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/create-deployment-user.sh:219:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/create-deployment-user.sh:252:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/create-deployment-user.sh:482:11: warning: Variable was used as an array but is now assigned a string. [SC2178]
/home/calounx/repositories/mentat/deploy/security/create-deployment-user.sh:491:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/create-deployment-user.sh:498:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/create-deployment-user.sh:505:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/create-deployment-user.sh:513:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/create-deployment-user.sh:522:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/create-deployment-user.sh:602:28: warning: user_exists appears unused. Verify use (or export if used externally). [SC2034]
```

### deploy/security/encrypt-backups.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/security/encrypt-backups.sh:19:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/encrypt-backups.sh:110:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/encrypt-backups.sh:186:11: note: Check exit code directly with e.g. 'if mycmd;', not indirectly with $?. [SC2181]
/home/calounx/repositories/mentat/deploy/security/encrypt-backups.sh:209:11: note: Check exit code directly with e.g. 'if mycmd;', not indirectly with $?. [SC2181]
/home/calounx/repositories/mentat/deploy/security/encrypt-backups.sh:227:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/encrypt-backups.sh:394:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/encrypt-backups.sh:394:79: note: Double quote to prevent globbing and word splitting. [SC2086]
/home/calounx/repositories/mentat/deploy/security/encrypt-backups.sh:407:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/encrypt-backups.sh:413:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/encrypt-backups.sh:422:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/encrypt-backups.sh:529:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/security/generate-ssh-keys-secure.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/security/generate-ssh-keys-secure.sh:29:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/generate-ssh-keys-secure.sh:83:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/generate-ssh-keys-secure.sh:89:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/generate-ssh-keys-secure.sh:95:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/generate-ssh-keys-secure.sh:101:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/generate-ssh-keys-secure.sh:149:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/generate-ssh-keys-secure.sh:154:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/generate-ssh-keys-secure.sh:182:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/generate-ssh-keys-secure.sh:300:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/generate-ssh-keys-secure.sh:314:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/generate-ssh-keys-secure.sh:340:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/generate-ssh-keys-secure.sh:513:11: warning: Variable was used as an array but is now assigned a string. [SC2178]
/home/calounx/repositories/mentat/deploy/security/generate-ssh-keys-secure.sh:529:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/generate-ssh-keys-secure.sh:538:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/generate-ssh-keys-secure.sh:547:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/security/harden-application.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/security/harden-application.sh:19:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/harden-application.sh:148:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/harden-application.sh:474:11: warning: Variable was used as an array but is now assigned a string. [SC2178]
/home/calounx/repositories/mentat/deploy/security/harden-application.sh:478:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/harden-application.sh:497:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/security/harden-database.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/security/harden-database.sh:19:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/harden-database.sh:59:1: warning: PG_DATA_DIR appears unused. Verify use (or export if used externally). [SC2034]
```

### deploy/security/incident-response.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/security/incident-response.sh:19:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/incident-response.sh:103:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/incident-response.sh:129:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/incident-response.sh:272:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/incident-response.sh:282:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/incident-response.sh:312:5: warning: Don't use ls | grep. Use a glob or a for loop with a condition to allow non-alphanumeric filenames. [SC2010]
/home/calounx/repositories/mentat/deploy/security/incident-response.sh:395:10: note: Use find instead of ls to better handle non-alphanumeric filenames. [SC2012]
/home/calounx/repositories/mentat/deploy/security/incident-response.sh:437:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/incident-response.sh:462:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/incident-response.sh:468:5: note: read without -r will mangle backslashes. [SC2162]
/home/calounx/repositories/mentat/deploy/security/incident-response.sh:469:5: note: read without -r will mangle backslashes. [SC2162]
/home/calounx/repositories/mentat/deploy/security/incident-response.sh:470:5: note: read without -r will mangle backslashes. [SC2162]
/home/calounx/repositories/mentat/deploy/security/incident-response.sh:471:5: note: read without -r will mangle backslashes. [SC2162]
/home/calounx/repositories/mentat/deploy/security/incident-response.sh:493:9: note: read without -r will mangle backslashes. [SC2162]
/home/calounx/repositories/mentat/deploy/security/incident-response.sh:501:21: note: read without -r will mangle backslashes. [SC2162]
/home/calounx/repositories/mentat/deploy/security/incident-response.sh:531:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/incident-response.sh:605:19: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/incident-response.sh:610:19: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/incident-response.sh:610:35: note: Use find instead of ls to better handle non-alphanumeric filenames. [SC2012]
```

### deploy/security/manage-secrets.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/security/manage-secrets.sh:19:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/manage-secrets.sh:130:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/manage-secrets.sh:196:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/manage-secrets.sh:208:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/manage-secrets.sh:220:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/manage-secrets.sh:232:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/manage-secrets.sh:244:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/manage-secrets.sh:256:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/manage-secrets.sh:269:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/manage-secrets.sh:273:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/manage-secrets.sh:277:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/manage-secrets.sh:288:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/manage-secrets.sh:348:19: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/manage-secrets.sh:369:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/manage-secrets.sh:370:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/manage-secrets.sh:371:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/manage-secrets.sh:372:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/manage-secrets.sh:411:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/manage-secrets.sh:433:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/security/master-security-setup.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/security/master-security-setup.sh:20:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/master-security-setup.sh:167:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/master-security-setup.sh:193:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/security/rotate-secrets.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** MISSING
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/security/rotate-secrets.sh:36:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/rotate-secrets.sh:106:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/rotate-secrets.sh:112:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/rotate-secrets.sh:118:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/rotate-secrets.sh:124:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/rotate-secrets.sh:241:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/rotate-secrets.sh:273:12: warning: ShellCheck can't follow non-constant source. Use a directive to specify location. [SC1090]
/home/calounx/repositories/mentat/deploy/security/rotate-secrets.sh:278:5: warning: OLD_APP_KEY appears unused. Verify use (or export if used externally). [SC2034]
/home/calounx/repositories/mentat/deploy/security/rotate-secrets.sh:341:11: note: Check exit code directly with e.g. 'if mycmd;', not indirectly with $?. [SC2181]
/home/calounx/repositories/mentat/deploy/security/rotate-secrets.sh:351:11: note: Check exit code directly with e.g. 'if mycmd;', not indirectly with $?. [SC2181]
/home/calounx/repositories/mentat/deploy/security/rotate-secrets.sh:384:15: note: Check exit code directly with e.g. 'if mycmd;', not indirectly with $?. [SC2181]
/home/calounx/repositories/mentat/deploy/security/rotate-secrets.sh:394:15: note: Check exit code directly with e.g. 'if mycmd;', not indirectly with $?. [SC2181]
/home/calounx/repositories/mentat/deploy/security/rotate-secrets.sh:539:11: warning: Variable was used as an array but is now assigned a string. [SC2178]
/home/calounx/repositories/mentat/deploy/security/rotate-secrets.sh:544:15: note: Check exit code directly with e.g. 'if mycmd;', not indirectly with $?. [SC2181]
/home/calounx/repositories/mentat/deploy/security/rotate-secrets.sh:555:15: note: Check exit code directly with e.g. 'if mycmd;', not indirectly with $?. [SC2181]
/home/calounx/repositories/mentat/deploy/security/rotate-secrets.sh:600:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/rotate-secrets.sh:662:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/security/security-audit.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/security/security-audit.sh:19:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/security-audit.sh:182:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/security-audit.sh:218:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/security-audit.sh:218:39: note: Consider using 'grep -c' instead of 'grep|wc -l'. [SC2126]
/home/calounx/repositories/mentat/deploy/security/security-audit.sh:230:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/security-audit.sh:239:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/security-audit.sh:248:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/security-audit.sh:258:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/security-audit.sh:268:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/security-audit.sh:280:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/security-audit.sh:280:144: note: Consider using 'grep -c' instead of 'grep|wc -l'. [SC2126]
/home/calounx/repositories/mentat/deploy/security/security-audit.sh:288:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/security-audit.sh:288:123: note: Consider using 'grep -c' instead of 'grep|wc -l'. [SC2126]
/home/calounx/repositories/mentat/deploy/security/security-audit.sh:294:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/security-audit.sh:327:19: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/security-audit.sh:335:19: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/security-audit.sh:392:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/security-audit.sh:401:23: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/security-audit.sh:405:27: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/security-audit.sh:406:27: warning: Declare and assign separately to avoid masking return values. [SC2155]

... and 16 more issues
```

### deploy/security/setup-fail2ban.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/security/setup-fail2ban.sh:19:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/setup-fail2ban.sh:557:45: note: $/${} is unnecessary on arithmetic variables. [SC2004]
/home/calounx/repositories/mentat/deploy/security/setup-fail2ban.sh:558:47: note: $/${} is unnecessary on arithmetic variables. [SC2004]
```

### deploy/security/setup-intrusion-detection.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/security/setup-intrusion-detection.sh:19:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/security/setup-security-monitoring.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/security/setup-security-monitoring.sh:20:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/security/setup-ssh-keys.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/security/setup-ssh-keys.sh:20:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/setup-ssh-keys.sh:55:1: warning: SSH_KEY_BITS appears unused. Verify use (or export if used externally). [SC2034]
/home/calounx/repositories/mentat/deploy/security/setup-ssh-keys.sh:160:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/setup-ssh-keys.sh:310:5: note: read without -r will mangle backslashes. [SC2162]
```

### deploy/security/setup-ssl.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/security/setup-ssl.sh:20:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/setup-ssl.sh:57:1: warning: CERTBOT_DIR appears unused. Verify use (or export if used externally). [SC2034]
/home/calounx/repositories/mentat/deploy/security/setup-ssl.sh:96:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/setup-ssl.sh:243:11: note: Check exit code directly with e.g. 'if mycmd;', not indirectly with $?. [SC2181]
/home/calounx/repositories/mentat/deploy/security/setup-ssl.sh:425:11: note: Check exit code directly with e.g. 'if mycmd;', not indirectly with $?. [SC2181]
/home/calounx/repositories/mentat/deploy/security/setup-ssl.sh:443:42: note: Note that A && B || C is not if-then-else. C may run when A is true. [SC2015]
/home/calounx/repositories/mentat/deploy/security/setup-ssl.sh:563:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/security/vulnerability-scan.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/security/vulnerability-scan.sh:19:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/vulnerability-scan.sh:156:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/vulnerability-scan.sh:159:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/vulnerability-scan.sh:160:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/vulnerability-scan.sh:178:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/vulnerability-scan.sh:178:63: note: Consider using 'grep -c' instead of 'grep|wc -l'. [SC2126]
/home/calounx/repositories/mentat/deploy/security/vulnerability-scan.sh:205:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/vulnerability-scan.sh:208:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/vulnerability-scan.sh:226:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/vulnerability-scan.sh:226:48: note: Consider using 'grep -c' instead of 'grep|wc -l'. [SC2126]
/home/calounx/repositories/mentat/deploy/security/vulnerability-scan.sh:239:19: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/vulnerability-scan.sh:256:23: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/vulnerability-scan.sh:260:23: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/vulnerability-scan.sh:261:23: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/vulnerability-scan.sh:262:23: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/vulnerability-scan.sh:263:38: note: $/${} is unnecessary on arithmetic variables. [SC2004]
/home/calounx/repositories/mentat/deploy/security/vulnerability-scan.sh:263:54: note: $/${} is unnecessary on arithmetic variables. [SC2004]
/home/calounx/repositories/mentat/deploy/security/vulnerability-scan.sh:272:23: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/vulnerability-scan.sh:329:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/security/vulnerability-scan.sh:333:15: warning: Declare and assign separately to avoid masking return values. [SC2155]

... and 5 more issues
```

### deploy/test-dependency-validation.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/test-dependency-validation.sh:40:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/test-dependency-validation.sh:54:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/test-dependency-validation.sh:57:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/test-dependency-validation.sh:58:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/test-dependency-validation.sh:83:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/test-dependency-validation.sh:97:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/test-dependency-validation.sh:126:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/tests/test-edge-cases-advanced.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/tests/test-edge-cases-advanced.sh:10:1: warning: DEPLOY_ROOT appears unused. Verify use (or export if used externally). [SC2034]
/home/calounx/repositories/mentat/deploy/tests/test-edge-cases-advanced.sh:17:1: warning: YELLOW appears unused. Verify use (or export if used externally). [SC2034]
/home/calounx/repositories/mentat/deploy/tests/test-edge-cases-advanced.sh:29:14: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-edge-cases-advanced.sh:29:39: note: Note that A && B || C is not if-then-else. C may run when A is true. [SC2015]
/home/calounx/repositories/mentat/deploy/tests/test-edge-cases-advanced.sh:29:42: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-edge-cases-advanced.sh:29:77: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-edge-cases-advanced.sh:65:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-edge-cases-advanced.sh:66:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-edge-cases-advanced.sh:69:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-edge-cases-advanced.sh:70:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-edge-cases-advanced.sh:70:29: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-edge-cases-advanced.sh:71:9: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-edge-cases-advanced.sh:72:9: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-edge-cases-advanced.sh:76:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-edge-cases-advanced.sh:76:42: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-edge-cases-advanced.sh:77:9: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-edge-cases-advanced.sh:78:9: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-edge-cases-advanced.sh:79:9: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-edge-cases-advanced.sh:83:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-edge-cases-advanced.sh:84:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]

... and 261 more issues
```

### deploy/tests/test-idempotence.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/tests/test-idempotence.sh:9:8: note: Not following: ./../utils/logging.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/tests/test-idempotence.sh:34:13: warning: TEST_MODE appears unused. Verify use (or export if used externally). [SC2034]
/home/calounx/repositories/mentat/deploy/tests/test-idempotence.sh:83:19: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/tests/test-idempotence.sh:89:30: warning: sudo doesn't affect redirects. Use ..| sudo tee file [SC2024]
/home/calounx/repositories/mentat/deploy/tests/test-idempotence.sh:92:24: warning: sudo doesn't affect redirects. Use ..| sudo tee file [SC2024]
/home/calounx/repositories/mentat/deploy/tests/test-idempotence.sh:93:19: warning: sudo doesn't affect redirects. Use ..| sudo tee file [SC2024]
/home/calounx/repositories/mentat/deploy/tests/test-idempotence.sh:99:21: warning: sudo doesn't affect redirects. Use ..| sudo tee file [SC2024]
/home/calounx/repositories/mentat/deploy/tests/test-idempotence.sh:118:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/tests/test-idempotence.sh:158:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/tests/test-idempotence.sh:168:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/tests/test-idempotence.sh:232:17: warning: all_iterations_passed appears unused. Verify use (or export if used externally). [SC2034]
/home/calounx/repositories/mentat/deploy/tests/test-idempotence.sh:279:20: warning: Prefer mapfile or read -a to split command output (or quote to avoid splitting). [SC2207]
/home/calounx/repositories/mentat/deploy/tests/test-idempotence.sh:345:9: note: read without -r will mangle backslashes. [SC2162]
```

### deploy/tests/test-idempotency.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** OK
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/tests/test-idempotency.sh:45:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-idempotency.sh:46:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-idempotency.sh:168:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-idempotency.sh:169:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-idempotency.sh:171:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-idempotency.sh:174:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-idempotency.sh:175:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-idempotency.sh:175:10: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-idempotency.sh:176:9: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-idempotency.sh:177:9: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-idempotency.sh:181:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-idempotency.sh:181:10: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-idempotency.sh:182:9: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-idempotency.sh:183:9: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-idempotency.sh:187:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-idempotency.sh:187:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/tests/test-idempotency.sh:187:18: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-idempotency.sh:188:5: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]
/home/calounx/repositories/mentat/deploy/tests/test-idempotency.sh:188:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/tests/test-idempotency.sh:188:18: note: Command appears to be unreachable. Check usage (or ignore if invoked indirectly). [SC2317]

... and 307 more issues
```

### deploy/utils/colors.sh

- **Executable:** No
- **Shebang:** OK
- **Set Flags:** MISSING
- **Bash Syntax:** OK

### deploy/utils/dependency-validation.sh

- **Executable:** No
- **Shebang:** OK
- **Set Flags:** MISSING
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/utils/dependency-validation.sh:81:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/utils/dependency-validation.sh:96:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/utils/dependency-validation.sh:324:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/utils/idempotence.sh

- **Executable:** Yes
- **Shebang:** OK
- **Set Flags:** MISSING
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/utils/idempotence.sh:200:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/utils/idempotence.sh:201:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/utils/idempotence.sh:218:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/utils/idempotence.sh:330:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/utils/logging.sh

- **Executable:** No
- **Shebang:** OK
- **Set Flags:** MISSING
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/utils/logging.sh:9:8: note: Not following: ./colors.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/utils/logging.sh:35:5: note: Consider using { cmd1; cmd2; } >> file instead of individual redirects. [SC2129]
/home/calounx/repositories/mentat/deploy/utils/logging.sh:48:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/utils/logging.sh:139:12: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/utils/logging.sh:145:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/utils/logging.sh:158:15: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

### deploy/utils/notifications.sh

- **Executable:** No
- **Shebang:** OK
- **Set Flags:** MISSING
- **Bash Syntax:** OK

**Shellcheck Issues:**
```
/home/calounx/repositories/mentat/deploy/utils/notifications.sh:10:8: note: Not following: ./logging.sh was not specified as input (see shellcheck -x). [SC1091]
/home/calounx/repositories/mentat/deploy/utils/notifications.sh:45:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/utils/notifications.sh:46:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/utils/notifications.sh:47:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/utils/notifications.sh:49:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/utils/notifications.sh:113:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/utils/notifications.sh:114:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/utils/notifications.sh:115:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
/home/calounx/repositories/mentat/deploy/utils/notifications.sh:117:11: warning: Declare and assign separately to avoid masking return values. [SC2155]
```

## Scripts that PASSED (14)

- chom/deploy/database/backup-and-verify.sh
- chom/deploy/database/database-security-hardening.sh
- chom/deploy/database/setup-mariadb-ssl.sh
- chom/deploy/database/setup-replication.sh
- chom/deploy/observability-native/install-grafana.sh
- chom/deploy/verify-installation.sh
- deploy/scripts/bootstrap-ssh-access.sh
- deploy/scripts/setup-firewall.sh
- deploy/scripts/setup-observability-vps.sh
- deploy/scripts/validate-dependencies.sh
- deploy/scripts/verify-debian13-compatibility.sh
- deploy/scripts/verify-native-deployment.sh
- deploy/utils/add-validation-header.sh
- deploy/utils/batch-add-validation.sh

## Scripts without Execute Permission (6)

- deploy/security/compliance-check.sh
- deploy/utils/add-validation-header.sh
- deploy/utils/colors.sh
- deploy/utils/dependency-validation.sh
- deploy/utils/logging.sh
- deploy/utils/notifications.sh

**Fix command:**
```bash
chmod +x /home/calounx/repositories/mentat/deploy/security/compliance-check.sh
chmod +x /home/calounx/repositories/mentat/deploy/utils/add-validation-header.sh
chmod +x /home/calounx/repositories/mentat/deploy/utils/colors.sh
chmod +x /home/calounx/repositories/mentat/deploy/utils/dependency-validation.sh
chmod +x /home/calounx/repositories/mentat/deploy/utils/logging.sh
chmod +x /home/calounx/repositories/mentat/deploy/utils/notifications.sh
```

