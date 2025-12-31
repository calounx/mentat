# Contributing to CHOM

Thank you for considering contributing to CHOM (CPanel Hosting Operations Manager)! This document provides guidelines for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Coding Standards](#coding-standards)
- [Testing](#testing)
- [Pull Request Process](#pull-request-process)
- [Reporting Bugs](#reporting-bugs)
- [Feature Requests](#feature-requests)

## Code of Conduct

- Be respectful and inclusive
- Provide constructive feedback
- Focus on what is best for the project
- Show empathy towards other community members

## Getting Started

### Prerequisites

- PHP 8.2 or higher
- Composer
- Node.js 18+ and NPM
- Docker (optional, for local services)
- Git

### Setup Development Environment

```bash
# Clone the repository
git clone <repository-url>
cd chom

# Run the automated setup script
./scripts/setup-dev.sh

# Or manually:
composer install
npm install
cp .env.example .env
php artisan key:generate
php artisan migrate
php artisan db:seed
```

## Development Workflow

### 1. Fork and Clone

```bash
git clone https://github.com/yourusername/chom.git
cd chom
git remote add upstream <original-repository-url>
```

### 2. Create a Branch

```bash
# Create a feature branch
git checkout -b feature/my-new-feature

# Or a bugfix branch
git checkout -b fix/issue-123
```

Branch naming conventions:
- `feature/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation updates
- `refactor/` - Code refactoring
- `test/` - Test improvements
- `chore/` - Maintenance tasks

### 3. Make Changes

- Write clear, self-documenting code
- Follow the coding standards (see below)
- Add tests for new features
- Update documentation as needed
- Keep commits atomic and focused

### 4. Commit Changes

```bash
# Stage changes
git add .

# Commit with descriptive message
git commit -m "Add feature: Site backup scheduling"
```

Commit message format:
```
<type>: <subject>

<body>

<footer>
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Formatting, missing semicolons, etc
- `refactor`: Code refactoring
- `test`: Adding tests
- `chore`: Maintenance

Example:
```
feat: Add automated site backup scheduling

Implement a new scheduling system that allows users to configure
automatic backups for their sites with customizable intervals.

Closes #123
```

### 5. Push and Create Pull Request

```bash
# Push to your fork
git push origin feature/my-new-feature

# Create pull request on GitHub
```

## Coding Standards

### PHP

We follow PSR-12 coding standards with some additional rules:

```bash
# Run PHP CS Fixer
composer run format

# Or manually
vendor/bin/pint
```

Key guidelines:
- Use type hints for all method parameters and return types
- Document all public methods with PHPDoc blocks
- Keep methods small and focused (single responsibility)
- Use meaningful variable and method names
- Avoid magic numbers - use constants
- Maximum line length: 120 characters

Example:
```php
<?php

namespace App\Services;

use App\Models\Site;
use App\Contracts\BackupServiceInterface;

class SiteBackupService implements BackupServiceInterface
{
    /**
     * Create a new backup for the given site.
     *
     * @param  Site  $site
     * @param  string  $type
     * @return Backup
     * @throws BackupException
     */
    public function createBackup(Site $site, string $type = 'full'): Backup
    {
        // Implementation
    }
}
```

### JavaScript

- Use ES6+ features
- Prefer `const` over `let`, avoid `var`
- Use arrow functions where appropriate
- Format with Prettier

### Blade Templates

- Keep logic minimal
- Extract complex logic to view composers or components
- Use Livewire components for interactive features

## Testing

### Running Tests

```bash
# Run all tests
composer test

# Or
php artisan test

# Run specific test file
php artisan test --filter=SiteTest

# Run with coverage
php artisan test --coverage
```

### Writing Tests

- Write tests for all new features
- Write tests for bug fixes
- Aim for at least 80% code coverage
- Use feature tests for end-to-end scenarios
- Use unit tests for isolated logic

Example:
```php
<?php

namespace Tests\Feature;

use App\Models\User;
use Tests\TestCase;

class SiteCreationTest extends TestCase
{
    public function test_user_can_create_site(): void
    {
        $user = User::factory()->create(['role' => 'owner']);

        $response = $this->actingAs($user)
            ->post('/api/v1/sites', [
                'domain' => 'example.test',
                'type' => 'wordpress',
            ]);

        $response->assertStatus(201);
        $this->assertDatabaseHas('sites', [
            'domain' => 'example.test',
        ]);
    }
}
```

## Pull Request Process

### Before Submitting

- [ ] Code follows style guidelines
- [ ] All tests pass
- [ ] New tests added for new features
- [ ] Documentation updated
- [ ] Changelog updated (if applicable)
- [ ] No merge conflicts with main branch

### PR Description Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
How has this been tested?

## Screenshots (if applicable)
Add screenshots for UI changes

## Checklist
- [ ] Tests pass
- [ ] Code follows style guide
- [ ] Documentation updated
```

### Review Process

1. Automated checks must pass (CI/CD)
2. At least one maintainer review required
3. All review comments addressed
4. Up to date with main branch
5. Squash and merge preferred

## Reporting Bugs

### Before Reporting

- Check existing issues to avoid duplicates
- Try to reproduce on the latest version
- Gather relevant information

### Bug Report Template

```markdown
## Bug Description
Clear description of the bug

## Steps to Reproduce
1. Go to '...'
2. Click on '...'
3. See error

## Expected Behavior
What should happen?

## Actual Behavior
What actually happens?

## Environment
- OS: [e.g., Ubuntu 22.04]
- PHP Version: [e.g., 8.2.10]
- Laravel Version: [e.g., 11.0]
- Browser: [if applicable]

## Screenshots
Add screenshots if applicable

## Additional Context
Any other relevant information
```

## Feature Requests

### Feature Request Template

```markdown
## Feature Description
Clear description of the proposed feature

## Problem it Solves
What problem does this feature solve?

## Proposed Solution
How should this feature work?

## Alternatives Considered
What other approaches did you consider?

## Additional Context
Any other relevant information
```

## Security Issues

If you discover a security vulnerability, please email security@example.com instead of creating a public issue.

## Questions?

- Check the [documentation](./DEVELOPMENT.md)
- Ask in GitHub Discussions
- Join our community chat (if available)

## License

By contributing, you agree that your contributions will be licensed under the project's license.

## Recognition

Contributors will be recognized in:
- CHANGELOG.md for significant contributions
- GitHub contributors list
- Project documentation (if desired)

---

Thank you for contributing to CHOM!
