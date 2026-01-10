# CHOM Test Scripts

This directory contains utility scripts for testing and development of the CHOM platform.

## Available Scripts

### create-test-users.sh

Creates test users, organizations, and tenants for development and testing.

**Usage**:
```bash
./scripts/create-test-users.sh
```

**What it creates**:

1. **Super Admin**
   - Email: `admin@chom.test`
   - Password: `password`
   - Role: Super Admin

2. **Starter Organization**
   - Owner: `starter@chom.test` / `password`
   - Organization: Starter Organization
   - Tenant: Starter Tenant

3. **Pro Organization**
   - Owner: `pro@chom.test` / `password`
   - Organization: Pro Organization
   - Tenant: Pro Tenant

4. **Enterprise Organization**
   - Owner: `enterprise@chom.test` / `password`
   - Organization: Enterprise Organization
   - Tenant: Enterprise Tenant

5. **Team Members** (in Starter Organization)
   - Admin: `admin-member@chom.test` / `password`
   - Member: `member@chom.test` / `password`
   - Viewer: `viewer@chom.test` / `password`

**Requirements**:
- Laravel must be installed and configured
- Database must be migrated
- Cannot run in production environment

**Notes**:
- All users are auto-approved and email-verified
- Safe to run multiple times (uses `firstOrCreate`)
- Only for development/testing environments

---

## Adding New Scripts

When adding new scripts to this directory:

1. Make them executable: `chmod +x scripts/your-script.sh`
2. Add a shebang: `#!/bin/bash`
3. Add error handling: `set -e`
4. Add usage documentation
5. Add to this README
6. Test in development environment first

---

## Script Guidelines

All scripts in this directory should follow these guidelines:

### Structure

```bash
#!/bin/bash

# Script description
# Usage information

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Pre-flight checks
# Main logic
# Cleanup
```

### Safety

- Check environment before running
- Prevent running in production
- Validate inputs
- Provide dry-run mode when appropriate
- Add confirmation prompts for destructive actions

### Documentation

- Add comments explaining complex logic
- Include usage examples
- Document required environment variables
- List prerequisites

---

## Related Documentation

- [TEST_ENVIRONMENT.md](../TEST_ENVIRONMENT.md) - Complete test environment setup
- [Vagrantfile](../Vagrantfile) - VM configuration
- [.github/workflows/ci.yml](../.github/workflows/ci.yml) - CI/CD pipeline

---

**Last Updated**: 2025-01-10
