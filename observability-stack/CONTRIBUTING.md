# Contributing to Observability Stack

Thank you for considering contributing to the Observability Stack!

> **For general contribution guidelines** (Git workflow, commit format, PR process, code of conduct), see the [root CONTRIBUTING.md](../CONTRIBUTING.md).

This document covers **observability-stack specific** development practices:

## Table of Contents

- [Quick Reference](#quick-reference)
- [Development Environment Setup](#development-environment-setup)
- [Shell Script Standards](#shell-script-standards)
- [Testing with BATS](#testing-with-bats)
- [Module Development](#module-development)
- [Component-Specific Guidelines](#component-specific-guidelines)
- [Release Process](#release-process)

---

## Quick Reference

**Testing:**
```bash
make test-all           # All tests (unit + integration + security)
make test-quick         # Quick tests (unit + shellcheck)
make test-unit          # Unit tests only
make test-integration   # Integration tests only
make test-security      # Security tests only
make test-shellcheck    # ShellCheck linting
make validate-yaml      # YAML validation
make syntax-check       # Bash syntax check
```

**Common Tasks:**
- General guidelines: See [root CONTRIBUTING.md](../CONTRIBUTING.md)
- Creating modules: See [Module Development](#module-development)
- Shell scripting: See [Shell Script Standards](#shell-script-standards)
- Writing tests: See [Testing with BATS](#testing-with-bats)

---

## Development Environment Setup

### Prerequisites

- Debian 13 or Ubuntu 22.04+ (for testing)
- Bash 4.0+
- Git
- BATS (Bash Automated Testing System)
- ShellCheck

### Setup

```bash
# From repository root
cd observability-stack

# Install testing dependencies
sudo apt-get update
sudo apt-get install -y bats shellcheck

# Or use Makefile
make install-deps

# Run tests to verify setup
make test-all
```

---

## Shell Script Standards

### Mandatory Requirements

All shell scripts in this project **must**:

1. **Pass ShellCheck** with no warnings
2. **Use strict mode**: `set -euo pipefail`
3. **Include proper shebang**: `#!/usr/bin/env bash` (preferred) or `#!/bin/bash`
4. **Handle errors gracefully** with appropriate exit codes
5. **Use functions** to organize code into reusable blocks

### Script Template

```bash
#!/usr/bin/env bash
#===============================================================================
# Script: script-name.sh
# Description: Brief explanation of what the script does
# Usage: ./script-name.sh [options]
#===============================================================================

set -euo pipefail

# Constants (use UPPERCASE)
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="/etc/myapp/config.yml"

# Functions
# Function: setup_component
# Description: Install and configure a component
# Arguments:
#   $1 - Version number
# Returns:
#   0 on success, 1 on failure
setup_component() {
    local version="${1:-3.8.1}"

    if [[ -z "$version" ]]; then
        log_error "Version required"
        return 1
    fi

    echo "Installing component ${version}..."
    # Implementation here

    return 0
}

# Main execution
main() {
    setup_component "$@"
}

# Only run main if script is executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

### Style Guidelines

**Variables:**
- Use `UPPERCASE` for constants/globals: `readonly MAX_RETRIES=3`
- Use `lowercase` for local variables: `local retry_count=0`
- Always quote variables: `"$variable"` not `$variable`
- Use `local` for function variables
- Use `readonly` for constants

**Conditionals:**
- Use `[[ ]]` instead of `[ ]`: `if [[ "$var" == "value" ]]; then`
- Quote string comparisons
- Use `-z` for empty checks: `[[ -z "$var" ]]`

**Commands:**
- Prefer `$()` over backticks: `result=$(command)` not `` result=`command` ``
- Use long-form flags in scripts: `--verbose` not `-v` (for readability)
- Check command existence: `command -v tool >/dev/null 2>&1`

**Functions:**
- Document complex functions with comments
- Use `return` for status codes (0 = success, 1+ = failure)
- Validate input parameters
- Use meaningful function names: `install_prometheus` not `do_stuff`

**Error Handling:**
```bash
# Check command success
if ! systemctl start myservice; then
    log_error "Failed to start service"
    return 1
fi

# Validate file existence
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Config file not found: $CONFIG_FILE"
    exit 1
fi

# Validate required commands
for cmd in curl jq systemctl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Required command not found: $cmd"
        exit 1
    fi
done
```

### Common Patterns

**Logging:**
```bash
log_info() {
    echo "[INFO] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_warn() {
    echo "[WARN] $*" >&2
}
```

**Cleanup on Exit:**
```bash
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT
```

**User Confirmation:**
```bash
confirm() {
    local prompt="$1"
    read -r -p "$prompt [y/N] " response
    [[ "$response" =~ ^[Yy]$ ]]
}

if confirm "Proceed with installation?"; then
    install_component
fi
```

---

## Testing with BATS

### Test Organization

Tests are organized in `tests/` directory:

```
tests/
├── test-common.bats           # Common library tests
├── test-module-manager.bats   # Module management tests
├── integration/               # Integration tests
│   ├── test-full-setup.bats
│   └── test-module-install.bats
└── security/                  # Security tests
    ├── test-permissions.bats
    └── test-hardening.bats
```

### Writing BATS Tests

**Basic Test Structure:**
```bash
#!/usr/bin/env bats

# Setup function runs before each test
setup() {
    # Load libraries
    load '../scripts/lib/common.sh'

    # Create temp directory
    TEST_TEMP_DIR="$(mktemp -d)"
}

# Teardown function runs after each test
teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

@test "function returns expected value" {
    # Arrange
    local input="test_input"

    # Act
    run my_function "$input"

    # Assert
    [ "$status" -eq 0 ]
    [ "$output" = "expected_output" ]
}

@test "function handles missing input" {
    # Act
    run my_function ""

    # Assert
    [ "$status" -eq 1 ]
    [[ "$output" =~ "error" ]]
}
```

**Testing Best Practices:**

1. **Use descriptive test names:**
   ```bash
   @test "setup_prometheus installs correct version" { }
   @test "setup_prometheus fails with invalid version" { }
   ```

2. **Test both success and failure cases:**
   ```bash
   @test "validate_config succeeds with valid config" { }
   @test "validate_config fails with invalid config" { }
   ```

3. **Use `run` for command execution:**
   ```bash
   run my_command arg1 arg2
   [ "$status" -eq 0 ]
   [[ "$output" =~ "expected pattern" ]]
   ```

4. **Check status codes:**
   ```bash
   [ "$status" -eq 0 ]    # Success
   [ "$status" -eq 1 ]    # Failure
   ```

5. **Use regex matching for flexible assertions:**
   ```bash
   [[ "$output" =~ "Installation complete" ]]
   [[ "$output" =~ ^ERROR: ]]
   ```

6. **Mock external commands when needed:**
   ```bash
   # Create a mock in setup()
   setup() {
       PATH="$TEST_TEMP_DIR/bin:$PATH"
       mkdir -p "$TEST_TEMP_DIR/bin"

       cat > "$TEST_TEMP_DIR/bin/systemctl" <<'EOF'
   #!/bin/bash
   echo "mock systemctl called with: $*"
   exit 0
   EOF
       chmod +x "$TEST_TEMP_DIR/bin/systemctl"
   }
   ```

### Running Tests

```bash
# All tests
make test-all

# Specific test file
bats tests/test-common.bats

# Specific test by pattern
bats tests/test-*.bats

# With verbose output
bats --tap tests/test-common.bats

# Using test runner script
./tests/run-tests.sh all
./tests/run-tests.sh unit
./tests/run-tests.sh integration
```

---

## Module Development

### Creating a New Module

Modules are self-contained packages for monitoring specific services. Each module follows a standard structure.

**Module Directory Structure:**
```
modules/_custom/my_exporter/
├── module.yaml           # Module manifest (required)
├── install.sh           # Installation script (required)
├── uninstall.sh         # Uninstallation script (required)
├── dashboard.json       # Grafana dashboard (optional)
├── alerts.yml          # Prometheus alert rules (optional)
├── scrape-config.yml   # Prometheus scrape config (optional)
└── README.md           # Module documentation (recommended)
```

### Module Manifest (module.yaml)

**Complete Example:**
```yaml
module:
  name: my_exporter
  display_name: My Custom Exporter
  version: "1.0.0"
  description: Monitors my custom service metrics
  category: custom
  author: Your Name
  homepage: https://github.com/example/my_exporter

# Service detection (how to detect if service is installed)
detection:
  commands:
    - "which my_service"
    - "test -f /etc/my_service/config.yml"
  systemd_services:
    - my_service
  confidence: 80  # 0-100, how confident this detection is

# Exporter configuration
exporter:
  binary_name: my_exporter
  port: 9999
  download_url_template: "https://github.com/example/releases/v${VERSION}/my_exporter-${VERSION}.linux-${ARCH}.tar.gz"
  version: "1.0.0"
  checksum_url: "https://github.com/example/releases/v${VERSION}/checksums.txt"

  # Command-line flags for the exporter
  flags:
    - "--web.listen-address=:9999"
    - "--config.file=/etc/my_exporter/config.yml"

  # Service configuration
  service:
    user: my_exporter
    working_directory: /var/lib/my_exporter

# Prometheus scrape configuration
prometheus:
  job_name: my_exporter
  scrape_interval: 15s
  scrape_timeout: 10s
  metrics_path: /metrics

# Optional configuration for hosts
host_config:
  required:
    service_url:
      type: string
      description: "URL of the service to monitor"
  optional:
    custom_setting:
      type: string
      default: "default_value"
      description: "Custom setting description"

# Dependencies on other modules
dependencies:
  - prometheus
```

### Installation Script (install.sh)

**Template:**
```bash
#!/usr/bin/env bash
#===============================================================================
# Module: my_exporter
# Installation script
#===============================================================================

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../scripts/lib/common.sh
source "${SCRIPT_DIR}/../../../scripts/lib/common.sh"

# Module variables
MODULE_NAME="my_exporter"
EXPORTER_PORT=9999
EXPORTER_USER="my_exporter"

install_my_exporter() {
    log_info "Installing ${MODULE_NAME}..."

    # Create user
    create_service_user "$EXPORTER_USER"

    # Download and install exporter
    download_exporter "$MODULE_NAME" "$EXPORTER_PORT"

    # Create configuration
    create_config

    # Install systemd service
    install_systemd_service

    # Configure firewall
    configure_firewall "$EXPORTER_PORT"

    log_info "${MODULE_NAME} installed successfully"
}

create_config() {
    log_info "Creating configuration..."

    cat > "/etc/${MODULE_NAME}/config.yml" <<EOF
# Configuration for ${MODULE_NAME}
service_url: ${SERVICE_URL}
EOF

    chown "${EXPORTER_USER}:${EXPORTER_USER}" "/etc/${MODULE_NAME}/config.yml"
}

install_systemd_service() {
    log_info "Installing systemd service..."

    cat > "/etc/systemd/system/${MODULE_NAME}.service" <<EOF
[Unit]
Description=My Custom Exporter
After=network.target

[Service]
Type=simple
User=${EXPORTER_USER}
ExecStart=/usr/local/bin/${MODULE_NAME} \\
    --web.listen-address=:${EXPORTER_PORT} \\
    --config.file=/etc/${MODULE_NAME}/config.yml
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "${MODULE_NAME}.service"
    systemctl start "${MODULE_NAME}.service"
}

# Main execution
install_my_exporter
```

### Uninstallation Script (uninstall.sh)

**Template:**
```bash
#!/usr/bin/env bash
#===============================================================================
# Module: my_exporter
# Uninstallation script
#===============================================================================

set -euo pipefail

MODULE_NAME="my_exporter"
EXPORTER_PORT=9999

uninstall_my_exporter() {
    echo "Uninstalling ${MODULE_NAME}..."

    # Stop and disable service
    if systemctl is-active --quiet "${MODULE_NAME}"; then
        systemctl stop "${MODULE_NAME}.service"
    fi
    systemctl disable "${MODULE_NAME}.service" 2>/dev/null || true

    # Remove systemd service
    rm -f "/etc/systemd/system/${MODULE_NAME}.service"
    systemctl daemon-reload

    # Remove binary
    rm -f "/usr/local/bin/${MODULE_NAME}"

    # Remove configuration
    rm -rf "/etc/${MODULE_NAME}"

    # Remove firewall rule
    ufw delete allow "${EXPORTER_PORT}/tcp" 2>/dev/null || true

    # Optionally remove user (be careful!)
    # userdel -r "${MODULE_NAME}" 2>/dev/null || true

    echo "${MODULE_NAME} uninstalled successfully"
}

# Main execution
uninstall_my_exporter
```

### Testing Your Module

```bash
# Validate module manifest
./scripts/module-manager.sh validate my_exporter

# Test installation
./scripts/module-manager.sh install my_exporter

# Verify service is running
systemctl status my_exporter

# Check metrics endpoint
curl http://localhost:9999/metrics

# Check module status
./scripts/module-manager.sh status

# Test uninstallation
./scripts/module-manager.sh uninstall my_exporter

# Verify cleanup
systemctl status my_exporter  # Should fail
test -f /usr/local/bin/my_exporter && echo "Binary still exists!" || echo "Cleanup OK"
```

### Module Development Checklist

- [ ] `module.yaml` is valid and complete
- [ ] `install.sh` follows shell script standards
- [ ] `uninstall.sh` properly cleans up all resources
- [ ] Service detection logic is accurate
- [ ] Exporter runs under dedicated user (not root)
- [ ] Firewall rules are configured
- [ ] Systemd service uses appropriate restart policies
- [ ] Dashboard.json includes relevant visualizations
- [ ] Alert rules cover critical conditions
- [ ] README.md documents module usage
- [ ] Module passes `validate` check
- [ ] Installation tested on clean system
- [ ] Uninstallation tested and verified cleanup

---

## Component-Specific Guidelines

### Prometheus Configuration

**When adding scrape configs:**
- Use descriptive job names
- Set appropriate scrape intervals (default: 15s)
- Add relabeling rules for better organization
- Test configuration: `promtool check config prometheus.yml`

**Example:**
```yaml
scrape_configs:
  - job_name: 'my_exporter'
    scrape_interval: 15s
    static_configs:
      - targets: ['localhost:9999']
        labels:
          instance: 'main'
          environment: 'production'
```

### Grafana Dashboards

**Dashboard best practices:**
- Use template variables for flexibility
- Include helpful descriptions in panels
- Group related metrics together
- Use appropriate visualization types
- Set sensible refresh intervals
- Export as JSON with proper formatting

**Testing dashboards:**
```bash
# Validate JSON syntax
jq empty dashboard.json

# Check for required fields
jq '.title, .uid, .version' dashboard.json
```

### Loki Configuration

**When adding log sources:**
- Use descriptive job labels
- Include relevant metadata
- Test regex patterns for parsing
- Consider log volume and retention

### Alert Rules

**Alert best practices:**
- Use clear, actionable alert names
- Include helpful annotations
- Set appropriate thresholds
- Test alert expressions: `promtool check rules alerts.yml`

**Example:**
```yaml
groups:
  - name: my_exporter_alerts
    interval: 30s
    rules:
      - alert: MyServiceDown
        expr: up{job="my_exporter"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "My Service is down"
          description: "My Service has been down for more than 1 minute."
```

---

## Release Process

### Versioning

We follow [Semantic Versioning](https://semver.org/):

- **MAJOR** (X.0.0): Breaking changes (incompatible API changes)
- **MINOR** (x.X.0): New features (backwards compatible)
- **PATCH** (x.x.X): Bug fixes (backwards compatible)

### Creating a Release

1. **Update version numbers:**
   ```bash
   # Update module versions in module.yaml files
   # Update version in README.md
   # Update CHANGELOG.md
   ```

2. **Run full test suite:**
   ```bash
   make test-all
   make validate-yaml
   make syntax-check
   ```

3. **Update CHANGELOG.md:**
   ```markdown
   ## [4.1.0] - 2025-01-15

   ### Added
   - New Redis exporter module
   - Support for custom alert rules

   ### Changed
   - Improved module detection logic

   ### Fixed
   - Fixed firewall rule duplication issue (#123)
   ```

4. **Create git tag:**
   ```bash
   git tag -a v4.1.0 -m "Release v4.1.0"
   git push origin v4.1.0
   ```

5. **Create GitHub release:**
   - Go to GitHub Releases
   - Draft new release
   - Select the tag
   - Add release notes from CHANGELOG
   - Publish release

---

## Additional Resources

**Project Documentation:**
- [Root CONTRIBUTING.md](../CONTRIBUTING.md) - General contribution guidelines
- [README.md](README.md) - Project overview and quick start
- [QUICK_START.md](QUICK_START.md) - Detailed installation guide
- [SECURITY.md](../SECURITY.md) - Security policy and reporting

**External Resources:**
- [ShellCheck Wiki](https://www.shellcheck.net/wiki/)
- [BATS Documentation](https://bats-core.readthedocs.io/)
- [Prometheus Best Practices](https://prometheus.io/docs/practices/)
- [Grafana Dashboard Best Practices](https://grafana.com/docs/grafana/latest/best-practices/)

---

## Getting Help

- **Questions about general workflow?** See [root CONTRIBUTING.md](../CONTRIBUTING.md)
- **Module development questions?** Open a [Discussion](https://github.com/calounx/mentat/discussions)
- **Found a bug?** Open an [Issue](https://github.com/calounx/mentat/issues)
- **Security concerns?** See [SECURITY.md](../SECURITY.md)

---

Thank you for contributing to the Observability Stack!

**Last Updated:** 2025-12-28
