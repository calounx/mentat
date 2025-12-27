# Library Architecture

This document describes the library structure and design decisions to maintain consistency and prevent code duplication.

## Directory Structure

```
observability-stack/
├── scripts/lib/           # Primary library - canonical implementations
│   ├── common.sh          # Core utilities (logging, paths, validation basics)
│   ├── validation.sh      # Input validation functions
│   ├── yaml-parser.sh     # YAML parsing with intelligent fallbacks
│   ├── errors.sh          # Error handling with stack traces
│   ├── versions.sh        # Version resolution and comparison
│   ├── secrets.sh         # Secret management
│   ├── config.sh          # Configuration loading
│   ├── module-loader.sh   # Module discovery and loading
│   ├── module-validator.sh # Security validation for modules
│   └── ...                # Other specialized modules
│
└── deploy/lib/            # Deployment-specific library
    ├── shared.sh          # Bridge to scripts/lib (sources shared utilities)
    ├── common.sh          # Deploy-specific functions + fallbacks
    └── config.sh          # Deploy configuration helpers
```

## Design Principles

### 1. Single Source of Truth

The `scripts/lib/` directory contains the **canonical implementations** of all shared utilities:

- **DO**: Add new shared functions to `scripts/lib/`
- **DON'T**: Duplicate functions in `deploy/lib/`
- **EXCEPTION**: Deploy-specific functions (firewall, systemd) belong in `deploy/lib/`

### 2. Shared Library Bridge

The `deploy/lib/shared.sh` acts as a bridge:

```bash
# In deploy/lib/common.sh
source "$DEPLOY_LIB_DIR/shared.sh"  # Sources scripts/lib utilities
```

This approach:
- Provides fallbacks when scripts/lib is unavailable (standalone deployment)
- Maintains compatibility with both interactive and automated installations
- Allows deploy scripts to work independently if needed

### 3. Fallback Pattern

All shared utilities in `deploy/lib/` use the fallback pattern:

```bash
# Only define if not already provided by shared.sh
if ! declare -f function_name >/dev/null 2>&1; then
    function_name() {
        # Fallback implementation
    }
fi
```

### 4. Guard Against Multiple Sourcing

All library files use sourcing guards:

```bash
[[ -n "${LIBRARY_NAME_LOADED:-}" ]] && return 0
LIBRARY_NAME_LOADED=1
```

## Function Categories

### scripts/lib/ - Canonical Functions

| Module | Responsibility |
|--------|----------------|
| `common.sh` | Logging, paths, atomic writes, basic validation |
| `validation.sh` | Input validation (IP, port, hostname, email) |
| `yaml-parser.sh` | YAML parsing with yq/python/awk fallbacks |
| `errors.sh` | Error codes, stack traces, error recovery |
| `versions.sh` | Version comparison, resolution strategies |
| `secrets.sh` | Secret loading from files/env/encrypted |
| `module-loader.sh` | Module discovery, manifest parsing |
| `module-validator.sh` | Security analysis for modules |

### deploy/lib/ - Deploy-Specific Functions

| Function | Purpose |
|----------|---------|
| `print_banner()` | Display ASCII banner |
| `setup_firewall_*()` | UFW firewall configuration |
| `create_systemd_service()` | Systemd unit file generation |
| `enable_and_start()` | Service enablement with waiting |
| `download_file()` | Secure download with checksum |
| `download_and_verify_github()` | GitHub release downloads |
| `is_placeholder()` | Detect placeholder values |
| `validate_config_no_placeholders()` | Config validation |
| `preflight_check()` | Pre-deployment validation |
| `get_component_version()` | Version resolution |
| `ensure_system_user()` | Idempotent user creation |
| `ensure_directory()` | Idempotent directory creation |
| `binary_installed()` | Check binary version |

## Adding New Functions

### Shared Utility (used by both scripts/ and deploy/)

1. Add to appropriate `scripts/lib/*.sh` file
2. The function will be available to deploy/ via `shared.sh`
3. Optionally add fallback in `deploy/lib/common.sh` for standalone use

### Deploy-Specific Function

1. Add directly to `deploy/lib/common.sh`
2. No fallback needed (only used during deployment)

## Testing

- Unit tests: `tests/unit/test-*.bats`
- Deploy tests: `tests/unit/test-deploy-lib.bats`
- All tests use BATS framework
- Test fixtures use hyphen-naming: `sample-config.yaml`

## Maintenance Notes

### Preventing Duplication

Before adding a new function:
1. Check if it exists in `scripts/lib/`
2. If yes, use via `shared.sh`
3. If no, determine if it's shared or deploy-specific
4. Add to appropriate location

### Updating Shared Functions

When updating a function in `scripts/lib/`:
1. Update the canonical implementation
2. Check if `deploy/lib/common.sh` has a fallback
3. Update fallback to match (for standalone compatibility)

### common.sh Size

The `scripts/lib/common.sh` is intentionally comprehensive. It provides:
- Logging infrastructure with file rotation
- Path utilities and atomic writes
- Basic validation functions
- Template rendering
- Cleanup trap management

Future decomposition opportunities:
- Extract logging → `logging.sh` (if standalone logging needed)
- Extract templates → `templates.sh` (if template complexity grows)
