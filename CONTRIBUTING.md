# Contributing to Mentat Monorepo

Thank you for considering contributing to the Mentat monorepo! This repository contains two major projects:
- **Observability Stack** - Infrastructure monitoring tools
- **CHOM** - Cloud Hosting & Observability Manager (Laravel SaaS)

This document provides guidelines for contributing to both projects.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Repository Structure](#repository-structure)
- [How to Contribute](#how-to-contribute)
- [Development Workflow](#development-workflow)
- [Testing](#testing)
- [Code Style](#code-style)
- [Commit Guidelines](#commit-guidelines)
- [Pull Request Process](#pull-request-process)

---

## Code of Conduct

This project adheres to a code of conduct. By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainers.

---

## Getting Started

### Prerequisites

**For Observability Stack:**
- Debian 13 or Ubuntu 22.04+ (for testing)
- Bash 4.0+
- BATS (Bash Automated Testing System)
- ShellCheck

**For CHOM:**
- PHP 8.2+
- Composer
- Node.js 18+ and npm
- SQLite, MySQL, or PostgreSQL

**General:**
- Git
- Make (for running tests)

### Setting Up Development Environment

```bash
# Clone the repository
git clone https://github.com/calounx/mentat.git
cd mentat

# Install all dependencies
make install-deps

# Run all tests to verify setup
make test-all
```

**For Observability Stack development:**
```bash
cd observability-stack

# Install BATS and ShellCheck
make install-deps

# Run tests
make test-quick
```

**For CHOM development:**
```bash
cd chom

# Install PHP dependencies
composer install

# Install JavaScript dependencies
npm install

# Setup environment
cp .env.example .env
php artisan key:generate

# Run database migrations
php artisan migrate

# Run tests
php artisan test

# Start development server
php artisan serve

# Watch frontend assets (in another terminal)
npm run dev
```

---

## Repository Structure

```
mentat/
├── observability-stack/   # Observability infrastructure (Bash, YAML)
│   ├── prometheus/        # Metrics collection
│   ├── loki/             # Log aggregation
│   ├── grafana/          # Visualization
│   ├── scripts/          # Installation/management scripts
│   ├── tests/            # BATS test suites
│   └── Makefile          # Component-specific tests
├── chom/                 # Laravel SaaS application (PHP, JS)
│   ├── app/              # Application logic
│   ├── resources/        # Frontend assets
│   ├── tests/            # PHPUnit tests
│   └── ...
├── Makefile              # Root-level test orchestration
└── README.md             # Main documentation
```

---

## How to Contribute

### Types of Contributions

We welcome various types of contributions:

1. **Bug Fixes** - Fix issues in existing code
2. **New Features** - Add new functionality
3. **Documentation** - Improve or add documentation
4. **Tests** - Add or improve test coverage
5. **Performance** - Optimize existing code
6. **Security** - Report or fix security issues

### Choosing What to Work On

- Check the [Issues](https://github.com/calounx/mentat/issues) page for open tasks
- Look for issues labeled `good first issue` or `help wanted`
- Comment on an issue to claim it before starting work
- For major changes, open an issue first to discuss the approach

---

## Development Workflow

### 1. Fork and Clone

```bash
# Fork the repository on GitHub
# Clone your fork
git clone https://github.com/YOUR_USERNAME/mentat.git
cd mentat

# Add upstream remote
git remote add upstream https://github.com/calounx/mentat.git
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

**For Observability Stack (Bash/Shell):**
- Follow existing script structure and patterns
- Add appropriate error handling and logging
- Update relevant documentation
- Write BATS tests for new functionality

**For CHOM (Laravel/PHP):**
- Follow PSR-12 coding standards
- Use Laravel best practices
- Write PHPUnit tests for new functionality
- Update API documentation if needed

### 4. Test Your Changes

```bash
# Test everything
make test-all

# Or test specific components
make test-obs      # Observability stack only
make test-chom     # CHOM only

# Run linters
make lint
```

### 5. Commit Your Changes

Follow the [commit guidelines](#commit-guidelines) below.

### 6. Push and Create Pull Request

```bash
# Push to your fork
git push origin feature/my-new-feature

# Create a pull request on GitHub
```

---

## Testing

### Running Tests

**All Tests:**
```bash
make test-all
```

**Component-Specific:**
```bash
# Observability stack (BATS + ShellCheck)
cd observability-stack
make test-quick          # Quick tests (unit + shellcheck)
make test-all           # All tests (unit + integration + security)
make test-unit          # Unit tests only
make test-integration   # Integration tests only
make test-security      # Security tests only

# CHOM (PHPUnit)
cd chom
php artisan test              # All tests
php artisan test --coverage   # With coverage
php artisan test --filter=UserTest  # Specific test
```

### Writing Tests

**For Observability Stack:**
- Use BATS framework for shell script tests
- Place tests in `observability-stack/tests/`
- Follow existing test patterns
- Test both success and failure cases

**For CHOM:**
- Use PHPUnit for unit tests
- Use Laravel's testing helpers
- Place tests in `chom/tests/Feature/` or `chom/tests/Unit/`
- Test API endpoints, services, and models

---

## Code Style

### Observability Stack (Bash)

- Use 4-space indentation (no tabs)
- Follow [ShellCheck](https://www.shellcheck.net/) recommendations
- Use `#!/usr/bin/env bash` shebang
- Add function documentation comments
- Use meaningful variable names (UPPERCASE for constants)
- Add error handling with proper exit codes

**Example:**
```bash
#!/usr/bin/env bash
set -euo pipefail

# Function: setup_prometheus
# Description: Install and configure Prometheus
# Arguments:
#   $1 - Version number
# Returns:
#   0 on success, 1 on failure
setup_prometheus() {
    local version="${1:-3.8.1}"

    echo "Installing Prometheus ${version}..."
    # Implementation here
}
```

### CHOM (PHP/Laravel)

- Follow PSR-12 coding standards
- Use Laravel's coding conventions
- Run Laravel Pint for formatting: `./vendor/bin/pint`
- Use type hints for function parameters and return types
- Write descriptive PHPDoc comments

**Example:**
```php
<?php

namespace App\Services;

use App\Models\Site;

class SiteManager
{
    /**
     * Create a new site with the given configuration.
     *
     * @param  array<string, mixed>  $config
     * @return Site
     */
    public function createSite(array $config): Site
    {
        // Implementation here
    }
}
```

### CHOM (JavaScript)

- Use ES6+ syntax
- Follow Alpine.js conventions
- Use 2-space indentation
- Use meaningful variable names

---

## Commit Guidelines

### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation changes
- `style` - Code style changes (formatting)
- `refactor` - Code refactoring
- `test` - Adding or updating tests
- `chore` - Maintenance tasks

**Scopes:**
- `obs` - Observability stack
- `chom` - CHOM application
- `ci` - CI/CD changes
- `deps` - Dependency updates

**Examples:**
```
feat(obs): add fail2ban exporter module

Add new exporter for monitoring fail2ban status and bans.
Includes configuration, systemd service, and dashboard.

feat(chom): add backup restoration API endpoint

Implement POST /api/v1/backups/{id}/restore endpoint with
validation and authorization checks.

fix(obs): correct prometheus retention configuration

The retention setting was not being applied correctly due to
incorrect systemd service parameter.

Fixes #123
```

---

## Pull Request Process

### Before Submitting

1. **Run all tests**: `make test-all`
2. **Run linters**: `make lint`
3. **Update documentation** if needed
4. **Add tests** for new functionality
5. **Rebase on latest master** to avoid merge conflicts

### PR Template

When creating a pull request, include:

**Description:**
- What does this PR do?
- Why is this change needed?

**Related Issues:**
- Fixes #123
- Related to #456

**Testing:**
- How was this tested?
- What test cases were added?

**Screenshots (if applicable):**
- For UI changes, include before/after screenshots

**Checklist:**
- [ ] Tests pass (`make test-all`)
- [ ] Linters pass (`make lint`)
- [ ] Documentation updated
- [ ] Commit messages follow guidelines
- [ ] Ready for review

### Review Process

1. At least one maintainer review is required
2. All CI checks must pass
3. Address review feedback
4. Maintainer will merge when approved

---

## Reporting Bugs

### Before Reporting

1. Check existing issues to avoid duplicates
2. Verify the bug exists on the latest version
3. Collect relevant information (OS, versions, logs)

### Bug Report Template

```markdown
**Description:**
A clear description of the bug.

**To Reproduce:**
Steps to reproduce the behavior:
1. Go to '...'
2. Run command '...'
3. See error

**Expected Behavior:**
What you expected to happen.

**Actual Behavior:**
What actually happened.

**Environment:**
- OS: [e.g., Debian 13]
- Component: [observability-stack or chom]
- Version: [e.g., v4.0.0]

**Logs/Screenshots:**
Relevant logs or screenshots.
```

---

## Suggesting Enhancements

### Enhancement Request Template

```markdown
**Feature Description:**
A clear description of the feature.

**Use Case:**
Why is this feature needed? Who would benefit?

**Proposed Solution:**
How should this be implemented?

**Alternatives Considered:**
Other approaches you've thought about.

**Additional Context:**
Any other relevant information.
```

---

## Questions?

If you have questions, feel free to:
- Open a [Discussion](https://github.com/calounx/mentat/discussions)
- Comment on an existing issue
- Reach out to maintainers

---

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

Thank you for contributing to Mentat!
