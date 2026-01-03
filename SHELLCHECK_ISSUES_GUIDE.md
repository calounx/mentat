# SHELLCHECK ISSUES REFERENCE GUIDE

**Analysis Date:** 2026-01-03
**Total Issues Found:** 1,964 across 87 scripts

This guide explains the most common shellcheck issues found in the codebase and how to fix them.

---

## TOP 20 MOST COMMON ISSUES

### 1. SC2155 (703 occurrences) - Declare and assign separately

**Issue:** Declaring a local variable and assigning a command substitution in one line masks the return value.

**Example:**
```bash
# PROBLEMATIC - masks return value
local result=$(some_command)

# CORRECT - preserves return value
local result
result=$(some_command)
```

**Why it matters:** If `some_command` fails, you won't know because the return value is from `local`, which always succeeds.

**Quick Fix Pattern:**
```bash
# Before:
local var=$(command)

# After:
local var
var=$(command)
```

---

### 2. SC2317 (593 occurrences) - Command appears to be unreachable

**Issue:** Shellcheck thinks a function or command is never called.

**Common Causes:**
- Function defined but not called in the script
- Function called indirectly (via variable or external script)
- Function meant to be sourced by other scripts

**Example:**
```bash
# Function defined but shellcheck doesn't see it being called
cleanup() {
    rm -f /tmp/tempfile
}
# If this is meant to be sourced, this is OK
```

**Fix Options:**
1. If function is used, ignore: `# shellcheck disable=SC2317`
2. If function is dead code, remove it
3. If function is sourced externally, add comment explaining

---

### 3. SC2086 (235 occurrences) - Double quote to prevent globbing

**Issue:** Unquoted variables can cause word splitting and glob expansion.

**Example:**
```bash
# PROBLEMATIC
rm $file
echo $message

# CORRECT
rm "$file"
echo "$message"
```

**Why it matters:** If `file` contains spaces, `rm $file` will try to delete multiple files.

**Special Cases:**
```bash
# Sometimes intentional for word splitting
options="-v -x"
command $options  # Want word splitting here

# But better to use array:
options=(-v -x)
command "${options[@]}"
```

---

### 4. SC2029 (233 occurrences) - SSH variable expansion on wrong side

**Issue:** Variables expand on the client side instead of the remote server.

**Example:**
```bash
# PROBLEMATIC - $VAR expands locally
ssh user@host "echo $VAR"

# CORRECT - \$VAR expands remotely
ssh user@host "echo \$VAR"

# ALSO CORRECT - use single quotes
ssh user@host 'echo $VAR'
```

**When you want local expansion:**
```bash
# Explicitly expand locally
local_value="test"
ssh user@host "echo $local_value"  # OK, intentional
```

---

### 5. SC1091 (33 occurrences) - Not following sourced file

**Issue:** Shellcheck can't analyze sourced files.

**Example:**
```bash
source ./utils/logging.sh
# SC1091: Not following: ./utils/logging.sh was not specified as input
```

**Fix:**
```bash
# Option 1: Tell shellcheck where to find it
# shellcheck source=./utils/logging.sh
source ./utils/logging.sh

# Option 2: Disable if not important
# shellcheck disable=SC1091
source ./utils/logging.sh
```

---

### 6. SC2162 (31 occurrences) - Read without -r

**Issue:** `read` without `-r` interprets backslashes.

**Example:**
```bash
# PROBLEMATIC
read line

# CORRECT
read -r line
```

**Why it matters:** Without `-r`, input like `C:\temp\file` becomes `C:tempfile`.

---

### 7. SC2034 (27 occurrences) - Variable appears unused

**Issue:** Variable is assigned but never referenced.

**Example:**
```bash
# PROBLEMATIC
result=$(command)
# result is never used

# CORRECT
result=$(command)
echo "$result"

# OR if intentionally unused:
_ result=$(command)  # Prefix with underscore
```

---

### 8. SC2181 (18 occurrences) - Check exit code directly

**Issue:** Checking `$?` instead of using the command directly in `if`.

**Example:**
```bash
# LESS READABLE
some_command
if [[ $? -eq 0 ]]; then
    echo "success"
fi

# MORE READABLE
if some_command; then
    echo "success"
fi
```

---

### 9. SC2012 (17 occurrences) - Use find instead of ls

**Issue:** Parsing `ls` output is fragile and breaks with special filenames.

**Example:**
```bash
# PROBLEMATIC
files=$(ls -t /path/*.txt | head -1)

# CORRECT
files=$(find /path -name "*.txt" -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)

# OR use shell globs
shopt -s nullglob
files=(/path/*.txt)
latest="${files[0]}"
```

---

### 10. SC2129 (15 occurrences) - Multiple redirects, use block

**Issue:** Multiple commands redirecting to same file can be grouped.

**Example:**
```bash
# LESS EFFICIENT
echo "line1" >> file.txt
echo "line2" >> file.txt
echo "line3" >> file.txt

# MORE EFFICIENT
{
    echo "line1"
    echo "line2"
    echo "line3"
} >> file.txt
```

---

### 11. SC2126 (10 occurrences) - Counting with grep

**Issue:** Using `grep | wc -l` when `grep -c` exists.

**Example:**
```bash
# LESS EFFICIENT
count=$(grep "pattern" file | wc -l)

# MORE EFFICIENT
count=$(grep -c "pattern" file)
```

---

### 12. SC2168 (8 occurrences) - 'local' only valid in functions

**Issue:** Using `local` keyword outside a function.

**Example:**
```bash
# WRONG - outside function
local var="value"

# CORRECT - inside function
my_function() {
    local var="value"
}

# CORRECT - outside function
var="value"
```

**This is a CRITICAL ERROR found in emergency-diagnostics.sh**

---

### 13. SC2015 (7 occurrences) - A && B || C is not if-then-else

**Issue:** The pattern `A && B || C` doesn't work like if-then-else.

**Example:**
```bash
# PROBLEMATIC - if B fails, C runs even though A succeeded
[[ -f file ]] && rm file || echo "File not found"

# CORRECT
if [[ -f file ]]; then
    rm file
else
    echo "File not found"
fi
```

---

### 14. SC2004 (7 occurrences) - $ not needed in arithmetic

**Issue:** Using `$` in `$(( ))` is redundant.

**Example:**
```bash
# REDUNDANT
result=$(($var + 1))

# CLEANER
result=$((var + 1))
```

---

### 15. SC2095 (6 occurrences) - SSH without BatchMode

**Issue:** SSH may hang waiting for password/interaction.

**Example:**
```bash
# PROBLEMATIC in automation
ssh user@host command

# BETTER for automation
ssh -o BatchMode=yes user@host command
```

---

## SEVERITY BREAKDOWN

| Severity | Count | Percentage |
|----------|-------|------------|
| **WARNING** | 70 scripts | 80.5% |
| **PASS** | 14 scripts | 16.1% |
| **ERROR** | 3 scripts | 3.4% |

---

## SCRIPTS THAT NEED IMMEDIATE ATTENTION

### Critical (Syntax Errors - Won't Run)
1. `deploy/security/generate-secure-secrets.sh` - Syntax error (extra parenthesis)

### High (Logic Errors - May Fail)
2. `chom/deploy/troubleshooting/emergency-diagnostics.sh` - local outside functions
3. `chom/deploy/observability-native/uninstall-all.sh` - glob in -d test

---

## RECOMMENDED FIXES BY PRIORITY

### Priority 1: Fix Now (Blocks Deployments)
- [ ] Fix syntax error in `generate-secure-secrets.sh`
- [ ] Fix `local` outside functions in `emergency-diagnostics.sh`
- [ ] Fix glob pattern in `uninstall-all.sh`

### Priority 2: Fix This Week (Prevents Issues)
- [ ] Add `set -euo pipefail` to all scripts (ensures errors are caught)
- [ ] Fix SC2155 in critical deployment scripts (masks errors)
- [ ] Add executable permissions where needed

### Priority 3: Fix This Sprint (Improves Reliability)
- [ ] Fix SC2086 (quote all variables) in security-sensitive scripts
- [ ] Fix SC2029 (SSH variable expansion) to prevent remote execution issues
- [ ] Fix SC2012 (replace ls with find) to handle special filenames

### Priority 4: Technical Debt (Cleanup)
- [ ] Remove unused variables (SC2034)
- [ ] Simplify logic (SC2181, SC2015)
- [ ] Optimize redirects (SC2129)
- [ ] Remove unreachable code or add comments (SC2317)

---

## AUTOMATED FIX SCRIPT

A script has been created to automatically fix the critical errors:

```bash
/home/calounx/repositories/mentat/fix-critical-script-errors.sh
```

This script:
1. Creates backups of all modified files
2. Fixes syntax errors
3. Removes invalid `local` declarations
4. Fixes glob patterns
5. Adds executable permissions where needed
6. Verifies all fixes with shellcheck

---

## BEST PRACTICES FOR FUTURE SCRIPTS

### 1. Always Start With
```bash
#!/usr/bin/env bash
set -euo pipefail

# set -e: Exit on error
# set -u: Exit on undefined variable
# set -o pipefail: Exit on pipe failure
```

### 2. Quote All Variables
```bash
# Always quote
echo "$var"
rm "$file"
cd "$directory"

# Exception: when word splitting is intentional (use arrays instead)
```

### 3. Declare and Assign Separately
```bash
# In functions
local result
result=$(command)

# Check return value
if ! result=$(command); then
    echo "Command failed"
    return 1
fi
```

### 4. Use ShellCheck
```bash
# Before committing
shellcheck script.sh

# In CI/CD
find . -name "*.sh" -exec shellcheck {} +
```

### 5. Test Scripts
```bash
# Syntax check
bash -n script.sh

# Run with set -x for debugging
bash -x script.sh
```

---

## PRE-COMMIT HOOK TEMPLATE

Create `.git/hooks/pre-commit`:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Running shellcheck on changed shell scripts..."

files=$(git diff --cached --name-only --diff-filter=ACM | grep '\.sh$' || true)

if [[ -z "$files" ]]; then
    exit 0
fi

failed=0
for file in $files; do
    echo "Checking: $file"
    if ! shellcheck "$file"; then
        failed=1
    fi
done

if [[ $failed -eq 1 ]]; then
    echo ""
    echo "❌ Shellcheck found issues. Please fix before committing."
    echo "   Or use 'git commit --no-verify' to skip (not recommended)"
    exit 1
fi

echo "✅ All shell scripts passed shellcheck"
exit 0
```

---

## USEFUL SHELLCHECK OPTIONS

```bash
# Exclude specific warnings
shellcheck -e SC2034,SC2317 script.sh

# Set severity level
shellcheck -S warning script.sh  # Only show warnings and errors

# Different output formats
shellcheck -f json script.sh     # JSON output
shellcheck -f gcc script.sh      # GCC-style (file:line:col)
shellcheck -f checkstyle script.sh # For CI tools

# Follow sourced files
shellcheck -x script.sh
```

---

## ADDITIONAL RESOURCES

- **Shellcheck Wiki**: https://www.shellcheck.net/wiki/
- **Google Shell Style Guide**: https://google.github.io/styleguide/shellguide.html
- **Bash Best Practices**: https://bertvv.github.io/cheat-sheets/Bash.html

---

## SUMMARY

- **Total Issues**: 1,964
- **Most Common**: SC2155 (declare/assign separately) - 703 occurrences
- **Critical Errors**: 3 scripts
- **Scripts Needing Work**: 73 out of 87 (83.9%)

**Recommendation**: Run the automated fix script, then systematically address warnings by priority.
