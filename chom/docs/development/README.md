# CHOM Developer Documentation

Welcome to the CHOM developer documentation hub! This directory contains everything you need to be productive as a CHOM developer.

## Quick Navigation

### New to CHOM?

Start here - these guides will get you up and running:

1. **[ONBOARDING.md](ONBOARDING.md)** - Your first 30 minutes with CHOM
   - Environment setup (step-by-step)
   - Understanding the codebase
   - Making your first contribution
   - Development workflow basics
   - Testing your changes

   **Time:** 30 minutes
   **Prerequisites:** Basic Laravel knowledge

---

### Need a Quick Reference?

Bookmark these for daily development:

2. **[CHEAT-SHEETS.md](CHEAT-SHEETS.md)** - Common commands at your fingertips
   - Artisan commands (code generation, management)
   - Database operations (migrations, seeders)
   - Testing commands (running tests, coverage)
   - Git workflow (branching, merging)
   - Debugging tips (logs, tinker, debugbar)
   - Queue & job management
   - API testing (curl examples)
   - Code quality tools

   **Use when:** You know what you want to do, just need the exact command

---

### Something Broken?

Fix it fast with this guide:

3. **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and solutions
   - Environment setup problems
   - Database errors and fixes
   - Testing failures
   - Build & asset errors
   - Performance issues
   - Authentication problems
   - API issues
   - Queue problems
   - Git conflicts

   **Use when:** You hit an error and need a solution NOW

---

### Want to Understand the System?

Learn how CHOM works under the hood:

4. **[ARCHITECTURE-OVERVIEW.md](ARCHITECTURE-OVERVIEW.md)** - System design explained for humans
   - High-level architecture diagrams
   - Core components explained
   - Data flow visualization
   - Multi-tenancy model
   - Request lifecycle
   - Background processing
   - Security architecture
   - Design decisions and trade-offs
   - Scalability strategy

   **Use when:** You want to understand WHY things work the way they do

---

## Documentation Organization

### This Directory (`docs/development/`)

Developer-focused documentation:
- Onboarding new developers
- Daily development tasks
- Troubleshooting common issues
- Understanding architecture

### Parent Directory (`docs/`)

Broader documentation:
- **DEVELOPER-GUIDE.md** - Comprehensive developer reference
- **GETTING-STARTED.md** - General getting started (for all users)
- **USER-GUIDE.md** - End-user documentation
- **OPERATOR-GUIDE.md** - Production operations
- **API-README.md** - API reference
- **SECURITY-*.md** - Security documentation

### Root Directory (`/`)

Project-level files:
- **README.md** - Project overview
- **CONTRIBUTING.md** - Contribution guidelines
- **CODE-STYLE.md** - Coding standards
- **TESTING.md** - Testing practices

---

## Recommended Learning Path

### Day 1: Get Running
1. Read [ONBOARDING.md](ONBOARDING.md) - Environment Setup section
2. Follow step-by-step setup
3. Create test user and login
4. Explore the UI

**Goal:** Have CHOM running locally

---

### Day 2: Understand the Code
1. Read [ONBOARDING.md](ONBOARDING.md) - Understanding the Codebase section
2. Read [ARCHITECTURE-OVERVIEW.md](ARCHITECTURE-OVERVIEW.md) - Big Picture section
3. Explore the codebase structure
4. Run tests: `php artisan test`

**Goal:** Understand how CHOM is organized

---

### Day 3: Make a Change
1. Read [ONBOARDING.md](ONBOARDING.md) - Your First Contribution section
2. Pick a `good-first-issue` from GitHub
3. Make the change
4. Write/update tests
5. Submit PR

**Goal:** Successfully contribute code

---

### Week 2: Deep Dive
1. Read [ARCHITECTURE-OVERVIEW.md](ARCHITECTURE-OVERVIEW.md) fully
2. Study one component deeply (e.g., Site Provisioning)
3. Review `/docs/DEVELOPER-GUIDE.md`
4. Contribute a more complex feature

**Goal:** Become proficient with CHOM architecture

---

## Quick Reference by Task

### I want to...

**Setup my environment**
→ [ONBOARDING.md - Environment Setup](ONBOARDING.md#environment-setup)

**Run the application**
→ [CHEAT-SHEETS.md - Essential Commands](CHEAT-SHEETS.md#essential-commands)

**Create a new model**
→ [CHEAT-SHEETS.md - Artisan Commands](CHEAT-SHEETS.md#artisan-commands)

**Run tests**
→ [CHEAT-SHEETS.md - Testing Commands](CHEAT-SHEETS.md#testing-commands)

**Fix a failing test**
→ [TROUBLESHOOTING.md - Testing Failures](TROUBLESHOOTING.md#testing-failures)

**Debug API issues**
→ [TROUBLESHOOTING.md - API Issues](TROUBLESHOOTING.md#api-issues)

**Understand data flow**
→ [ARCHITECTURE-OVERVIEW.md - Data Flow](ARCHITECTURE-OVERVIEW.md#data-flow)

**Fix database errors**
→ [TROUBLESHOOTING.md - Database Problems](TROUBLESHOOTING.md#database-problems)

**Improve performance**
→ [TROUBLESHOOTING.md - Performance Issues](TROUBLESHOOTING.md#performance-issues)

**Learn Git workflow**
→ [CHEAT-SHEETS.md - Git Workflow](CHEAT-SHEETS.md#git-workflow)

---

## Common Workflows

### Daily Development

```bash
# 1. Start the day
git checkout master
git pull origin master
composer run dev  # Starts all services

# 2. Create feature branch
git checkout -b feature/my-feature

# 3. Make changes...
# Edit files, add features, fix bugs

# 4. Test changes
php artisan test
./vendor/bin/pint  # Format code

# 5. Commit
git add .
git commit -m "Add my feature"

# 6. Push and create PR
git push origin feature/my-feature
```

**Detailed guide:** [CHEAT-SHEETS.md - Git Workflow](CHEAT-SHEETS.md#git-workflow)

---

### Debugging a Problem

```bash
# 1. Clear caches (fixes 90% of issues)
php artisan optimize:clear

# 2. Check logs
php artisan pail  # Real-time
tail -f storage/logs/laravel.log  # Traditional

# 3. Use debugger
# Add dd($variable) in code
# Check browser console (F12)

# 4. Run tests to isolate
php artisan test --filter=MyTest

# 5. Still stuck? Check troubleshooting guide
```

**Detailed guide:** [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

---

### Adding a New Feature

```bash
# 1. Create model with migration
php artisan make:model Backup -mfc

# 2. Edit migration
# database/migrations/*_create_backups_table.php

# 3. Run migration
php artisan migrate

# 4. Create service
php artisan make:class Services/BackupService

# 5. Create tests
php artisan make:test BackupServiceTest --unit

# 6. Implement feature
# Write code, tests, documentation

# 7. Verify
php artisan test
./vendor/bin/pint
```

**Detailed guide:** [ONBOARDING.md - Development Workflow](ONBOARDING.md#development-workflow)

---

## Tools & Resources

### IDE Setup

**VS Code Extensions:**
- Laravel Extension Pack
- PHP Intelephense
- Tailwind CSS IntelliSense
- Alpine.js IntelliSense
- GitLens

**PHPStorm Plugins:**
- Laravel Idea
- PHP Annotations
- Tailwind CSS
- .env files support

---

### Browser Extensions

- **Laravel Debugbar** - Built into CHOM (enable with `DEBUGBAR_ENABLED=true`)
- **Vue DevTools** - For future Vue.js components
- **JSON Formatter** - Pretty print API responses

---

### Command Line Tools

```bash
# Code quality
composer install --dev
./vendor/bin/pint          # Code formatting
./vendor/bin/phpstan       # Static analysis

# API testing
brew install httpie        # Better than curl
brew install jq            # JSON processor

# Database
brew install mysql-client  # MySQL CLI
redis-cli                  # Redis CLI
```

---

## Getting Help

### Self-Service

1. **Search this documentation** - Use Cmd+F / Ctrl+F
2. **Check logs** - `storage/logs/laravel.log`
3. **Search GitHub issues** - Someone likely had this problem
4. **Read Laravel docs** - https://laravel.com/docs

### Ask for Help

1. **GitHub Discussions** - https://github.com/calounx/mentat/discussions
2. **Create an issue** - https://github.com/calounx/mentat/issues
3. **Team Slack** - (for team members)

**When asking for help, include:**
- What you're trying to do
- What you expected to happen
- What actually happened (error messages!)
- What you've already tried
- Your environment (OS, PHP version, etc.)

---

## Contributing to Documentation

Found an error? Want to improve these docs?

```bash
# 1. Edit the markdown file
docs/development/ONBOARDING.md

# 2. Test locally (preview in GitHub or IDE)

# 3. Commit and PR
git add docs/development/ONBOARDING.md
git commit -m "docs: improve onboarding setup steps"
git push origin feature/improve-docs
```

**Documentation standards:**
- Use clear, simple language
- Include code examples
- Add visual aids (diagrams, decision trees)
- Keep it up-to-date
- Link to related docs

---

## Document Metadata

| Document | Audience | Time to Read | Last Updated |
|----------|----------|--------------|--------------|
| ONBOARDING.md | New developers | 30-45 min | 2025-12-30 |
| CHEAT-SHEETS.md | All developers | 5 min (reference) | 2025-12-30 |
| TROUBLESHOOTING.md | Debugging | 10-30 min | 2025-12-30 |
| ARCHITECTURE-OVERVIEW.md | Learning | 45-60 min | 2025-12-30 |

---

## Feedback

Help us improve this documentation!

- **Found an error?** - Create an issue
- **Missing information?** - Create a PR
- **General feedback?** - Comment on GitHub Discussions

**Our goal:** Every developer productive within 30 minutes of cloning the repo.

---

**Happy coding!**
