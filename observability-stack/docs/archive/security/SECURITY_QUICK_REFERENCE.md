# Security Quick Reference - Observability Stack

**For Developers**: Quick guide to the security patterns implemented in this codebase.

---

## Golden Rules

1. **NEVER** interpolate user input into jq expressions
2. **ALWAYS** validate component names before using in paths
3. **ALWAYS** use `umask 077` before creating temp files
4. **ALWAYS** use `timeout` when executing external binaries
5. **ALWAYS** use `flock` for atomic file operations

---

## Common Patterns

### ✓ Safe jq Usage

```bash
# DO THIS (Safe)
jq --arg name "$component" '.components[$name] = ...' file.json

# NOT THIS (Vulnerable)
jq ".components.\"$component\" = ..." file.json
```

### ✓ Safe Component Name Validation

```bash
# DO THIS (Safe)
if [[ ! "$component" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    log_error "Invalid component name: $component"
    return 1
fi

# NOT THIS (Insufficient)
if [[ -z "$component" ]]; then
    return 1
fi
```

### ✓ Safe Temp File Creation

```bash
# DO THIS (Safe)
local old_umask=$(umask)
umask 077
temp_file=$(mktemp "/var/tmp/app.XXXXXX")
umask "$old_umask"
chmod 600 "$temp_file"

# NOT THIS (Vulnerable)
temp_file=$(mktemp "/var/tmp/app.XXXXXX")
```

### ✓ Safe Binary Execution

```bash
# DO THIS (Safe)
if [[ "$binary_path" =~ \.\. ]]; then
    log_error "Path traversal attempt"
    return 1
fi

perms=$(stat -c '%a' "$binary_path")
if [[ "$perms" =~ [2367]$ ]]; then
    log_error "Binary is world-writable"
    return 1
fi

version=$(timeout 5 "$binary_path" --version)

# NOT THIS (Vulnerable)
version=$("$binary_path" --version)
```

### ✓ Safe File Locking

```bash
# DO THIS (Safe - prevents TOCTOU)
if (
    exec 200>"$lockfile"
    flock -x -n 200 && perform_action
) 2>/dev/null; then
    log_success "Action completed"
fi

# NOT THIS (Vulnerable - TOCTOU)
if [[ ! -f "$lockfile" ]]; then
    perform_action
    touch "$lockfile"
fi
```

---

## Input Validation Cheat Sheet

### Component Names
```bash
# Pattern: alphanumeric, underscore, hyphen only
[[ "$component" =~ ^[a-zA-Z0-9_-]+$ ]]

# Examples:
node_exporter        ✓ Valid
nginx-exporter       ✓ Valid
prometheus2          ✓ Valid
test;rm -rf /        ✗ Blocked
../../etc/passwd     ✗ Blocked
```

### File Paths
```bash
# Check for path traversal
[[ "$path" =~ \.\. ]] && return 1
[[ "$path" =~ / ]] && return 1 # For component names

# Examples:
/usr/local/bin/app   ✓ Valid
../../../etc/passwd  ✗ Blocked (contains ..)
/var/www/../etc      ✗ Blocked (contains ..)
```

### Version Strings
```bash
# Use validate_version() from versions.sh
if ! validate_version "$version"; then
    log_error "Invalid version format"
    return 1
fi

# Examples:
1.2.3                ✓ Valid
1.2.3-beta.1         ✓ Valid
v2.0.0               ✗ Blocked (prefix not allowed in some contexts)
1.2.3; rm -rf /      ✗ Blocked
```

### File Permissions
```bash
# Check if world-writable
perms=$(stat -c '%a' "$file")
[[ "$perms" =~ [2367]$ ]] && return 1

# Examples:
600  ✓ Valid (rw-------)
644  ✓ Valid (rw-r--r--)
666  ✗ Blocked (rw-rw-rw-)
777  ✗ Blocked (rwxrwxrwx)
```

---

## jq Parameter Passing Reference

### String Variables
```bash
# Single variable
jq --arg name "$value" '.field = $name' file.json

# Multiple variables
jq --arg name1 "$val1" \
   --arg name2 "$val2" \
   '.field1 = $name1 | .field2 = $name2' file.json
```

### Numeric Variables
```bash
# Use --argjson for numbers
jq --argjson count "$num" '.count = $count' file.json

# NOT --arg (would be string)
jq --arg count "$num" '.count = $count' file.json  # Wrong!
```

### Boolean Variables
```bash
# Use --argjson for booleans
jq --argjson enabled "$bool_var" '.enabled = $enabled' file.json
```

### Arrays (advanced)
```bash
# Use --argjson with JSON string
jq --argjson items "$(echo '["a","b","c"]')" '.items = $items' file.json
```

---

## Error Handling Patterns

### Check All Critical Operations
```bash
# Pattern 1: Check and return
if ! validate_input "$input"; then
    log_error "Validation failed"
    return 1
fi

# Pattern 2: Check in condition
if [[ -f "$file" ]] && validate_file "$file"; then
    process_file "$file"
fi

# Pattern 3: Fail early
[[ -z "$required_var" ]] && { log_error "Missing variable"; return 1; }
```

### Lock Acquisition Error Handling
```bash
if ! state_lock; then
    log_error "Failed to acquire lock"
    # Clean up any partial work
    rm -f "$temp_file" 2>/dev/null
    return 1
fi

# Ensure unlock on exit
trap 'state_unlock 2>/dev/null' EXIT
```

---

## Security Code Review Checklist

When reviewing code, check for:

- [ ] No direct string interpolation into jq expressions
- [ ] All user input validated with regex patterns
- [ ] Component names validated before use in paths
- [ ] Temp files created with umask 077
- [ ] External binaries executed with timeout
- [ ] Binary permissions checked before execution
- [ ] Path traversal checks on all file paths
- [ ] Lock acquisition uses flock for atomicity
- [ ] All error cases properly handled
- [ ] Security-relevant events logged

---

## Common Vulnerabilities to Avoid

### 1. jq Injection
```bash
# VULNERABLE
jq ".name = \"$user_input\"" data.json

# SAFE
jq --arg name "$user_input" '.name = $name' data.json
```

### 2. Path Traversal
```bash
# VULNERABLE
cp "$file" "/backup/$user_component/"

# SAFE
[[ "$user_component" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
cp "$file" "/backup/$user_component/"
```

### 3. TOCTOU Race
```bash
# VULNERABLE
if [[ -f "$file" ]]; then
    rm "$file"  # File could change between check and remove
fi

# SAFE
flock -x "$file.lock" rm "$file"
```

### 4. Insecure Temp Files
```bash
# VULNERABLE
temp=$(mktemp)  # Created with system umask

# SAFE
old_umask=$(umask)
umask 077
temp=$(mktemp)
umask "$old_umask"
```

### 5. Unvalidated External Command
```bash
# VULNERABLE
version=$("$binary" --version)

# SAFE
[[ "$binary" =~ \.\. ]] && return 1
perms=$(stat -c '%a' "$binary")
[[ "$perms" =~ [2367]$ ]] && return 1
version=$(timeout 5 "$binary" --version)
validate_version "$version" || return 1
```

---

## Testing Your Code

### Test Input Validation
```bash
# Test with malicious input
component='test"; rm -rf /'
your_function "$component"
# Should fail with: "Invalid component name"

# Test with path traversal
component='../../etc/passwd'
your_function "$component"
# Should fail with: "Invalid component name"
```

### Test Concurrent Access
```bash
# Run multiple instances
for i in {1..10}; do
    your_script &
done
wait

# Check logs - should see lock contention, no corruption
```

### Test File Permissions
```bash
# Check temp file permissions
stat -c '%a' /var/tmp/app.*
# Should all be: 600
```

---

## Quick Security Audit

Run these commands to verify security:

```bash
# Check for unsafe jq usage
grep -rn 'jq ".*\$' scripts/
# Should find: 0 results

# Check for unvalidated component usage
grep -rn '\$component' scripts/ | grep -v 'validate\|=~'
# Review any results

# Check for unsafe temp file creation
grep -rn 'mktemp' scripts/ | grep -v 'umask 077'
# Review any results

# Check for binary execution without timeout
grep -rn '\$.*--version' scripts/ | grep -v 'timeout'
# Review any results
```

---

## Getting Help

- **Full Documentation**: `SECURITY_FIXES_APPLIED.md`
- **Audit Report**: `SECURITY_AUDIT_UPGRADE_SYSTEM.md`
- **Questions**: security@observability-stack.example.com

---

**Remember**: Security is not a feature, it's a requirement. When in doubt, validate and log!

---

Last Updated: 2025-12-27
