# Dependency Validation - Quick Reference

## What Is This?

All deployment scripts now validate their dependencies BEFORE executing. This prevents mysterious failures caused by missing files or incorrect working directories.

## What Gets Validated?

Every script checks:

1. Script is being run from the correct location
2. Required utility files exist (`logging.sh`, `colors.sh`, etc.)
3. Required directories exist (`utils/`, `scripts/`, `security/`)
4. Files are readable

## What Happens If Validation Fails?

You'll see a clear error message like this:

```
ERROR: Missing required dependencies for deploy-application.sh

Script location: /wrong/path/deploy/scripts
Deploy root: /wrong/path/deploy
Utils directory: /wrong/path/deploy/utils

Missing dependencies:
  - /wrong/path/deploy/utils/logging.sh
  - /wrong/path/deploy/utils/colors.sh

Run from repository root: sudo ./deploy/scripts/deploy-application.sh
```

## How To Fix Validation Errors

### Quick Fix (Most Common)

```bash
# 1. Navigate to the repository root
cd /home/calounx/repositories/mentat

# 2. Run the script with the correct path
sudo ./deploy/deploy-chom.sh
```

### If Files Are Actually Missing

```bash
# Check repository status
git status

# Pull latest changes
git pull

# Verify utility files exist
ls -la deploy/utils/
```

### If You Get Permission Errors

```bash
# Make utility files readable
chmod +r deploy/utils/*.sh

# Make scripts executable
chmod +x deploy/**/*.sh
```

## Running Scripts Correctly

### Main Deployment Scripts

```bash
# From repository root
cd /home/calounx/repositories/mentat

# Run main deployment
sudo ./deploy/deploy-chom.sh --repo-url=<url>

# Run automated deployment
sudo ./deploy/deploy-chom-automated.sh
```

### Deployment Subscripts

```bash
# Always from repository root
cd /home/calounx/repositories/mentat

# Examples
sudo ./deploy/scripts/prepare-mentat.sh
sudo ./deploy/scripts/prepare-landsraad.sh
sudo ./deploy/scripts/deploy-application.sh --branch main
```

### Security Scripts

```bash
# Always from repository root
cd /home/calounx/repositories/mentat

# Examples
sudo ./deploy/security/master-security-setup.sh
sudo ./deploy/security/harden-application.sh
```

## Common Mistakes

### WRONG: Running from the wrong directory

```bash
cd /home/calounx/repositories/mentat/deploy
./deploy-chom.sh  # ✗ WRONG - will fail validation
```

### RIGHT: Running from repository root

```bash
cd /home/calounx/repositories/mentat
./deploy/deploy-chom.sh  # ✓ CORRECT
```

### WRONG: Using absolute paths incorrectly

```bash
sudo /home/calounx/repositories/mentat/deploy/scripts/prepare-mentat.sh  # ✗ Might work but not recommended
```

### RIGHT: Relative path from repository root

```bash
cd /home/calounx/repositories/mentat
sudo ./deploy/scripts/prepare-mentat.sh  # ✓ CORRECT
```

## Testing Validation

Test that validation is working:

```bash
cd /home/calounx/repositories/mentat
./deploy/test-dependency-validation.sh
```

## For Developers

### Adding Validation to New Scripts

Copy this template at the top of your script (after `set -euo pipefail`):

```bash
# Dependency validation - MUST run before sourcing any files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Validate dependencies before doing anything else
validate_deployment_dependencies() {
    local script_dir="$1"
    local deploy_root="$2"
    local script_name="$(basename "$0")"
    local errors=()

    if [[ ! -d "$deploy_root" ]]; then
        errors+=("Deploy root directory not found: $deploy_root")
    fi

    local utils_dir="${deploy_root}/utils"
    if [[ ! -d "$utils_dir" ]]; then
        errors+=("Utils directory not found: $utils_dir")
    else
        # Add required files here
        local required_utils=(
            "${utils_dir}/logging.sh"
            "${utils_dir}/colors.sh"
            "${utils_dir}/dependency-validation.sh"
        )

        for util_file in "${required_utils[@]}"; do
            if [[ ! -f "$util_file" ]]; then
                errors+=("Required utility file not found: $util_file")
            elif [[ ! -r "$util_file" ]]; then
                errors+=("Required utility file not readable: $util_file")
            fi
        done
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "" >&2
        echo "ERROR: Missing required dependencies for ${script_name}" >&2
        echo "" >&2
        echo "Script location: ${script_dir}" >&2
        echo "Deploy root: ${deploy_root}" >&2
        echo "" >&2
        echo "Missing dependencies:" >&2
        for error in "${errors[@]}"; do
            echo "  - ${error}" >&2
        done
        echo "" >&2
        echo "Run from repository root: sudo ./deploy/scripts/${script_name}" >&2
        exit 1
    fi
}

validate_deployment_dependencies "$SCRIPT_DIR" "$DEPLOY_ROOT"

# Now safe to source utility files
source "${SCRIPT_DIR}/../utils/logging.sh"
```

### Adjust for Script Location

- **Main scripts** (in `deploy/`): `DEPLOY_ROOT="$SCRIPT_DIR"`
- **Subscripts** (in `deploy/scripts/`): `DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"`
- **Security scripts** (in `deploy/security/`): `DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"`

## Bypassing Validation (NOT RECOMMENDED)

If you absolutely must bypass validation for debugging:

```bash
# Comment out the validation call
# validate_deployment_dependencies "$SCRIPT_DIR" "$DEPLOY_ROOT"
```

**WARNING**: Only do this temporarily for debugging. Never commit commented-out validation!

## Quick Checklist

Before running any deployment script:

- [ ] Am I in `/home/calounx/repositories/mentat`?
- [ ] Am I using a relative path like `./deploy/script.sh`?
- [ ] Have I run `git pull` to get latest changes?
- [ ] Do I have sudo/root access if required?

## Getting Help

If validation fails and you can't figure out why:

1. Check the error message carefully - it tells you exactly what's missing
2. Verify you're in the repository root: `pwd`
3. List utility files: `ls -la deploy/utils/`
4. Check git status: `git status`
5. Run the test suite: `./deploy/test-dependency-validation.sh`

## What Changed?

**Before**: Scripts would fail with cryptic bash errors if files were missing
```
./deploy/scripts/prepare-mentat.sh: line 14: ../utils/logging.sh: No such file or directory
```

**After**: Scripts provide clear, actionable error messages
```
ERROR: Missing required dependencies for prepare-mentat.sh

Script location: /wrong/path/scripts
Deploy root: /wrong/path
Utils directory: /wrong/path/utils

Missing dependencies:
  - /wrong/path/utils/logging.sh

Run from repository root: sudo ./deploy/scripts/prepare-mentat.sh
```

## Files Modified

- 2 main deployment scripts
- 14 deployment subscripts
- 20 security scripts
- 4 new utility files
- 2 new documentation files

Total: 42 files updated/created

---

**Remember**: Always run from `/home/calounx/repositories/mentat` using relative paths!
