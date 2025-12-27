# Contributing to Observability Stack

Thank you for considering contributing to the Observability Stack! This document provides guidelines and instructions for contributing.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [How to Contribute](#how-to-contribute)
- [Development Workflow](#development-workflow)
- [Testing](#testing)
- [Code Style](#code-style)
- [Commit Guidelines](#commit-guidelines)
- [Pull Request Process](#pull-request-process)
- [Reporting Bugs](#reporting-bugs)
- [Suggesting Enhancements](#suggesting-enhancements)

---

## Code of Conduct

This project adheres to a code of conduct. By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainers.

---

## Getting Started

### Prerequisites

- Debian 13 or Ubuntu 22.04+ (for testing)
- Bash 4.0+
- Git
- BATS (Bash Automated Testing System)
- ShellCheck

### Setting Up Development Environment

```bash
# Clone the repository
git clone <repository-url>
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

## How to Contribute

### Types of Contributions

We welcome various types of contributions:

1. **Bug Fixes**: Fix issues in existing code
2. **New Features**: Add new modules, exporters, or functionality
3. **Documentation**: Improve or add documentation
4. **Tests**: Add or improve test coverage
5. **Performance**: Optimize existing code
6. **Security**: Report or fix security issues

---

## Development Workflow

### 1. Fork and Clone

```bash
# Fork the repository on GitHub
# Clone your fork
git clone https://github.com/YOUR_USERNAME/observability-stack.git
cd observability-stack

# Add upstream remote
git remote add upstream https://github.com/ORIGINAL_OWNER/observability-stack.git
```

### 2. Create a Branch

```bash
# Update main branch
git checkout master
git pull upstream master

# Create feature branch
git checkout -b feature/my-new-feature

# Or for bug fixes
git checkout -b fix/bug-description
```

### 3. Make Changes

- Write clean, maintainable code
- Follow existing code style
- Add tests for new functionality
- Update documentation as needed

### 4. Test Your Changes

```bash
# Run all tests
make test-all

# Run specific test suites
make test-unit
make test-integration
make test-security

# Run shellcheck
make test-shellcheck

# Validate YAML
make validate-yaml

# Check bash syntax
make syntax-check
```

---

## Testing

### Writing Tests

We use BATS for testing. Place tests in the `tests/` directory:

```bash
# Unit tests
tests/test-*.bats

# Integration tests
tests/integration/test-*.bats

# Security tests
tests/security/test-*.bats
```

### Test Example

```bash
#!/usr/bin/env bats

@test "function returns expected value" {
    source scripts/lib/common.sh
    result=$(my_function "input")
    [ "$result" = "expected" ]
}
```

### Running Tests

```bash
# All tests
bats tests/**/*.bats

# Specific file
bats tests/test-common.bats

# With test runner
./tests/run-tests.sh all
```

---

## Code Style

### Bash Scripts

Follow these guidelines:

1. **Use ShellCheck**: All scripts must pass ShellCheck
2. **Set strict mode**: `set -euo pipefail`
3. **Use functions**: Break code into reusable functions
4. **Comment complex logic**: Explain non-obvious code
5. **Error handling**: Always handle errors gracefully

### Example

```bash
#!/bin/bash
#===============================================================================
# Script Description
# Brief explanation of what the script does
#===============================================================================

set -euo pipefail

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Functions
function my_function() {
    local input="$1"

    if [[ -z "$input" ]]; then
        log_error "Input required"
        return 1
    fi

    # Implementation
}

# Main execution
main() {
    my_function "$@"
}

main "$@"
```

### Shell Style Guide

- Use `[[` instead of `[` for conditionals
- Quote variables: `"$variable"`
- Use `readonly` for constants
- Use `local` for function variables
- Prefer `$()` over backticks
- Use long-form flags: `--verbose` not `-v` in code

---

## Commit Guidelines

### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `test`: Adding or updating tests
- `refactor`: Code refactoring
- `perf`: Performance improvements
- `chore`: Maintenance tasks
- `security`: Security fixes

### Examples

```
feat(modules): add redis exporter module

Add new module for monitoring Redis instances with:
- Metrics collection for keys, memory, connections
- Pre-configured Grafana dashboard
- Alert rules for high memory usage

Closes #123
```

```
fix(setup): correct firewall rule generation

Fix issue where multiple firewall rules were created
for the same port when re-running setup script.

Fixes #456
```

### Commit Best Practices

- Keep commits atomic (one logical change per commit)
- Write clear, descriptive commit messages
- Reference issues/PRs when applicable
- Sign commits if possible: `git commit -S`

---

## Pull Request Process

### Before Submitting

1. ✅ All tests passing
2. ✅ ShellCheck passing
3. ✅ Documentation updated
4. ✅ CHANGELOG.md updated (if applicable)
5. ✅ Commits follow guidelines
6. ✅ Branch is up to date with master

### Submitting PR

1. **Push to your fork**
   ```bash
   git push origin feature/my-new-feature
   ```

2. **Create Pull Request on GitHub**
   - Use descriptive title
   - Fill out PR template
   - Link related issues
   - Add screenshots/examples if applicable

3. **PR Template**
   ```markdown
   ## Description
   Brief description of changes

   ## Type of Change
   - [ ] Bug fix
   - [ ] New feature
   - [ ] Documentation update
   - [ ] Security fix

   ## Testing
   - [ ] All tests pass
   - [ ] Added new tests
   - [ ] Manual testing completed

   ## Checklist
   - [ ] Code follows style guidelines
   - [ ] Self-review completed
   - [ ] Documentation updated
   - [ ] No new warnings
   ```

### Review Process

1. **Automated Checks**: CI/CD runs tests
2. **Code Review**: Maintainers review changes
3. **Feedback**: Address review comments
4. **Approval**: At least one maintainer approval required
5. **Merge**: Maintainer merges PR

---

## Reporting Bugs

### Before Reporting

1. Check existing issues
2. Try latest version
3. Verify it's reproducible

### Bug Report Template

```markdown
**Describe the bug**
Clear description of the bug

**To Reproduce**
Steps to reproduce:
1. Run command '...'
2. See error '...'

**Expected behavior**
What should happen

**Actual behavior**
What actually happens

**Environment:**
- OS: [Debian 13]
- Version: [v3.0.0]
- Scripts affected: [setup-observability.sh]

**Logs**
```
Paste relevant logs
```

**Additional context**
Any other relevant information
```

### Security Vulnerabilities

**DO NOT** report security vulnerabilities publicly. See SECURITY.md for responsible disclosure process.

---

## Suggesting Enhancements

### Enhancement Template

```markdown
**Is your feature request related to a problem?**
Description of the problem

**Describe the solution you'd like**
What you want to happen

**Describe alternatives you've considered**
Other solutions considered

**Additional context**
Mockups, examples, use cases
```

---

## Module Development

### Creating a New Module

Modules are self-contained packages for monitoring specific services.

**Module Structure:**
```
modules/_custom/my_exporter/
├── module.yaml           # Manifest
├── install.sh           # Installation script
├── uninstall.sh         # Uninstallation script
├── dashboard.json       # Grafana dashboard
├── alerts.yml          # Prometheus alert rules
└── scrape-config.yml   # Prometheus scrape config
```

**Example module.yaml:**
```yaml
module:
  name: my_exporter
  display_name: My Custom Exporter
  version: "1.0.0"
  description: Monitors my custom service
  category: custom

detection:
  commands:
    - "which my_service"
  systemd_services:
    - my_service
  confidence: 80

exporter:
  binary_name: my_exporter
  port: 9999
  download_url_template: "https://github.com/example/releases/v${VERSION}/my_exporter-${VERSION}.linux-${ARCH}.tar.gz"
  flags:
    - "--web.listen-address=:9999"

prometheus:
  job_name: my_exporter
  scrape_interval: 15s

host_config:
  optional:
    custom_setting:
      type: string
      default: "value"
```

### Testing Your Module

```bash
# Validate module manifest
./scripts/module-manager.sh validate my_exporter

# Test installation
./scripts/module-manager.sh install my_exporter

# Verify status
./scripts/module-manager.sh status

# Test uninstallation
./scripts/module-manager.sh uninstall my_exporter
```

---

## Documentation Guidelines

### Documentation Standards

- Use Markdown format
- Include code examples
- Add troubleshooting sections
- Keep language clear and concise
- Use proper heading hierarchy

### Where to Add Documentation

- **README.md**: Main project documentation
- **QUICK_START.md**: Quick start guide
- **docs/**: Detailed documentation
- **Module README**: Per-module documentation
- **Inline comments**: Complex code explanation

---

## Release Process

### Versioning

We follow [Semantic Versioning](https://semver.org/):

- **MAJOR**: Breaking changes
- **MINOR**: New features (backwards compatible)
- **PATCH**: Bug fixes (backwards compatible)

### Creating a Release

1. Update version in relevant files
2. Update CHANGELOG.md
3. Create release notes
4. Tag the release: `git tag -a v3.0.0 -m "Release v3.0.0"`
5. Push tag: `git push origin v3.0.0`
6. GitHub Actions handles deployment

---

## Getting Help

### Resources

- **Documentation**: See README.md and docs/
- **Issues**: Check existing GitHub issues
- **Discussions**: GitHub Discussions (if enabled)

### Contact

- Open an issue for bugs or features
- Use discussions for questions
- See SECURITY.md for security issues

---

## Recognition

Contributors will be recognized in:

- CHANGELOG.md
- Release notes
- GitHub contributors list

Thank you for contributing to Observability Stack! 🎉

---

**Last Updated:** 2025-12-27
**Maintained By:** Project maintainers
