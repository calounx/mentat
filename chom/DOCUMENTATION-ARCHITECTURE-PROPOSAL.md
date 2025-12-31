# CHOM Documentation Architecture Proposal

**Version:** 2.0
**Date:** 2025-12-30
**Status:** Ready for Implementation

---

## Executive Summary

This proposal outlines an optimal documentation architecture for CHOM that transforms 94 scattered files into a well-organized, audience-focused documentation system. The new structure reduces duplication from 30-40% to <10%, improves discoverability, and implements progressive disclosure principles.

### Key Metrics

| Metric | Current | Target | Improvement |
|--------|---------|--------|-------------|
| Total Files | 94 | 45 | 52% reduction |
| Duplication | 30-40% | <10% | 70% reduction |
| Root Files | 17 | 8 | 53% reduction |
| Broken Links | 15+ | 0 | 100% fixed |
| Avg. Time to Find Info | 5-10 min | <2 min | 60% faster |

---

## Table of Contents

1. [Core Principles](#core-principles)
2. [Proposed Directory Structure](#proposed-directory-structure)
3. [Documentation Categories](#documentation-categories)
4. [Naming Conventions](#naming-conventions)
5. [Navigation Strategy](#navigation-strategy)
6. [Migration Plan](#migration-plan)
7. [Before/After Examples](#beforeafter-examples)
8. [Implementation Roadmap](#implementation-roadmap)

---

## Core Principles

### 1. Audience-First Organization

**Three Primary Audiences:**

```
Users (Site Operators)
├── Getting Started
├── User Guide
└── FAQ

Developers
├── Quick Start
├── Development Guide
├── API Reference
└── Architecture Docs

Operators (DevOps/SRE)
├── Deployment
├── Configuration
├── Monitoring
└── Troubleshooting
```

### 2. Progressive Disclosure

**Information Hierarchy:**

```
Level 1: Quick Start (5 minutes)
  ↓
Level 2: Guides (20-30 minutes)
  ↓
Level 3: Reference (as needed)
  ↓
Level 4: Deep Dive (architecture, patterns)
```

### 3. Single Source of Truth

**Rule:** One canonical document per topic
- No duplicate SECURITY-IMPLEMENTATION.md files
- No multiple QUICK-START vs QUICKSTART variants
- Cross-reference instead of duplicate

### 4. Clear Navigation

**Navigation Elements:**
- **README.md in every directory** - Navigation hub
- **Index pages** - Topic-based indexes
- **Breadcrumbs** - Context awareness
- **Related links** - Semantic connections

---

## Proposed Directory Structure

### Final Structure

```
chom/
├── README.md                          # Project overview, quick links
├── QUICK-START.md                     # 5-minute getting started
├── CONTRIBUTING.md                    # How to contribute
├── CHANGELOG.md                       # Version history
├── CODE-STYLE.md                      # Code standards
├── LICENSE.md                         # License
├── SECURITY.md                        # Security policy
│
├── docs/                              # All documentation
│   ├── README.md                      # Documentation hub (main index)
│   │
│   ├── getting-started/               # For new users/developers
│   │   ├── README.md                  # Getting started index
│   │   ├── installation.md            # Install CHOM locally
│   │   ├── configuration.md           # Configure environment
│   │   ├── first-site.md              # Create your first site
│   │   └── next-steps.md              # What to learn next
│   │
│   ├── guides/                        # Task-oriented guides
│   │   ├── README.md                  # Guides index
│   │   ├── user-guide.md              # For site operators
│   │   ├── developer-guide.md         # For developers
│   │   ├── operator-guide.md          # For DevOps/SRE
│   │   └── troubleshooting.md         # Common problems & solutions
│   │
│   ├── api/                           # API documentation
│   │   ├── README.md                  # API overview
│   │   ├── quick-start.md             # API quick start
│   │   ├── reference.md               # Complete API reference
│   │   ├── authentication.md          # Auth & tokens
│   │   ├── versioning.md              # API versioning
│   │   ├── changelog.md               # API changes
│   │   ├── postman_collection.json    # Postman collection
│   │   └── insomnia_workspace.json    # Insomnia workspace
│   │
│   ├── development/                   # Development topics
│   │   ├── README.md                  # Development index
│   │   ├── setup.md                   # Dev environment setup
│   │   ├── architecture.md            # System architecture
│   │   ├── patterns.md                # Design patterns
│   │   ├── service-layer.md           # Service layer guide
│   │   ├── testing.md                 # Testing guide
│   │   ├── code-quality.md            # Quality standards
│   │   └── workflows.md               # Git workflows
│   │
│   ├── deployment/                    # Deployment & operations
│   │   ├── README.md                  # Deployment index
│   │   ├── quick-start.md             # Quick deploy (30 min)
│   │   ├── production-guide.md        # Production deployment
│   │   ├── configuration.md           # Environment config
│   │   ├── security-hardening.md      # Security setup
│   │   ├── monitoring.md              # Observability stack
│   │   ├── backup-restore.md          # Backup strategies
│   │   ├── troubleshooting.md         # Deployment issues
│   │   └── updates.md                 # Update procedures
│   │
│   ├── security/                      # Security documentation
│   │   ├── README.md                  # Security index
│   │   ├── guide.md                   # Complete security guide
│   │   ├── quick-reference.md         # Security checklist
│   │   ├── authentication.md          # Auth & 2FA setup
│   │   ├── authorization.md           # Roles & permissions
│   │   ├── audit-checklist.md         # Security audit
│   │   └── incident-response.md       # Security incidents
│   │
│   ├── performance/                   # Performance optimization
│   │   ├── README.md                  # Performance index
│   │   ├── guide.md                   # Complete perf guide
│   │   ├── database.md                # Database optimization
│   │   ├── caching.md                 # Redis caching
│   │   ├── testing.md                 # Performance testing
│   │   └── quick-reference.md         # Quick tips
│   │
│   ├── database/                      # Database documentation
│   │   ├── README.md                  # Database index
│   │   ├── schema.md                  # Schema documentation
│   │   ├── migrations.md              # Migration guide
│   │   ├── optimization.md            # DB optimization
│   │   └── redis-setup.md             # Redis setup
│   │
│   ├── components/                    # UI components
│   │   ├── README.md                  # Components index
│   │   ├── library.md                 # Component catalog
│   │   └── quick-reference.md         # Component lookup
│   │
│   ├── diagrams/                      # Architecture diagrams
│   │   ├── README.md                  # Diagrams index
│   │   ├── system-architecture.md     # System overview
│   │   ├── security-architecture.md   # Security design
│   │   ├── request-flow.md            # Request lifecycle
│   │   ├── deployment-architecture.md # Deployment topology
│   │   └── database-schema.md         # ER diagrams
│   │
│   ├── reference/                     # Reference documentation
│   │   ├── README.md                  # Reference index
│   │   ├── configuration.md           # All config options
│   │   ├── cli-commands.md            # Artisan commands
│   │   ├── environment-variables.md   # All env vars
│   │   └── error-codes.md             # Error reference
│   │
│   └── archive/                       # Historical documents
│       ├── README.md                  # Archive index
│       ├── implementation-reports/    # Feature implementation
│       ├── design-docs/               # Design decisions
│       ├── audit-reports/             # Past audits
│       └── migration-guides/          # Past migrations
│
├── deploy/                            # Deployment scripts & docs
│   ├── README.md                      # Deploy guide (canonical)
│   ├── deploy-enhanced.sh             # Main deploy script
│   ├── configs/                       # Config templates
│   ├── scripts/                       # Helper scripts
│   └── docs/                          # Deploy-specific docs
│       ├── sudo-user-setup.md         # User setup
│       ├── security-review.md         # Security checklist
│       └── troubleshooting.md         # Deploy troubleshooting
│
└── tests/                             # Test documentation
    ├── README.md                      # Testing overview
    ├── quick-reference.md             # Quick test commands
    ├── test-suite.md                  # Test suite docs
    ├── security-testing.md            # Security tests
    └── execution-guide.md             # How to run tests
```

---

## Documentation Categories

### By Audience

#### 1. End Users (Site Operators)

**Goal:** Manage sites without technical knowledge

**Documents:**
- `docs/guides/user-guide.md` - Complete user manual
- `docs/getting-started/first-site.md` - Tutorial
- `docs/guides/troubleshooting.md` - Self-service help

**Navigation Path:**
```
README.md → docs/guides/user-guide.md → Specific tasks
```

#### 2. Developers

**Goal:** Build features, fix bugs, contribute

**Documents:**
- `QUICK-START.md` - Get running in 5 minutes
- `docs/development/setup.md` - Dev environment
- `docs/development/architecture.md` - System design
- `docs/development/testing.md` - Test guide
- `docs/api/reference.md` - API reference

**Navigation Path:**
```
README.md → QUICK-START.md → docs/development/ → Specific topics
```

#### 3. Operators (DevOps/SRE)

**Goal:** Deploy, monitor, maintain production

**Documents:**
- `docs/deployment/quick-start.md` - Deploy in 30 min
- `docs/deployment/production-guide.md` - Full deploy
- `docs/deployment/monitoring.md` - Observability
- `docs/deployment/troubleshooting.md` - Fix issues
- `docs/security/guide.md` - Security hardening

**Navigation Path:**
```
README.md → docs/deployment/ → Production deployment → Monitoring
```

### By Task

#### Quick Tasks (<10 minutes)

| Task | Document | Location |
|------|----------|----------|
| Run CHOM locally | QUICK-START.md | Root |
| Create first site | docs/getting-started/first-site.md | Getting Started |
| Run tests | tests/quick-reference.md | Tests |
| Deploy to production | docs/deployment/quick-start.md | Deployment |
| Enable 2FA | docs/security/authentication.md | Security |
| Check API docs | docs/api/quick-start.md | API |

#### Deep Dives (30+ minutes)

| Topic | Document | Audience |
|-------|----------|----------|
| System Architecture | docs/development/architecture.md | Developers |
| Security Implementation | docs/security/guide.md | All |
| Performance Optimization | docs/performance/guide.md | Developers/Ops |
| Service Layer Patterns | docs/development/service-layer.md | Developers |
| Production Deployment | docs/deployment/production-guide.md | Operators |

### By Lifecycle Stage

```
Learn           → docs/getting-started/
Build           → docs/development/
Deploy          → docs/deployment/
Monitor         → docs/deployment/monitoring.md
Troubleshoot    → docs/guides/troubleshooting.md
Optimize        → docs/performance/
Secure          → docs/security/
Reference       → docs/reference/
```

---

## Naming Conventions

### File Naming

**Rules:**
1. Use lowercase with hyphens: `user-guide.md`, not `User_Guide.md`
2. Be descriptive: `production-guide.md`, not `prod.md`
3. Use standard suffixes:
   - `-guide.md` - Comprehensive guides
   - `-reference.md` - Quick lookup
   - `quick-start.md` - Quick start guides
   - `README.md` - Directory indexes

**Standard Names:**

```
✓ GOOD                          ✗ BAD
quick-start.md                  QUICKSTART.md / QUICK-START.md
user-guide.md                   userguide.md / USER_GUIDE.md
authentication.md               auth.md / 2fa-config.md
production-guide.md             prod-deploy.md / DEPLOYMENT-GUIDE.md
troubleshooting.md              bugs.md / QUICK-FIX-GUIDE.md
```

### Directory Naming

**Rules:**
1. Use lowercase, plural nouns: `guides/`, `diagrams/`
2. Group by topic, not document type
3. Maximum 2 levels deep (except archive)

**Examples:**

```
✓ GOOD                          ✗ BAD
docs/guides/                    docs/GUIDES/
docs/security/                  docs/sec/
docs/getting-started/           docs/tutorials/
```

### Document Titles

**Rules:**
1. Match filename: `user-guide.md` → `# User Guide`
2. Be concise: `# API Quick Start`, not `# Quick Start Guide for API`
3. No redundancy: `# Guide`, not `# User Guide Guide`

### Section Headings

**Hierarchy:**

```markdown
# Document Title (H1) - One per document
## Major Section (H2)
### Subsection (H3)
#### Detail (H4) - Rare, avoid if possible
```

**Style:**

```
✓ GOOD                          ✗ BAD
## Installation Steps           ## How to Install CHOM
## Configuration Options        ## Configuring Your Environment
## Troubleshooting              ## Common Issues and Solutions
```

---

## Navigation Strategy

### 1. Hub-and-Spoke Model

**Central Hub:** `docs/README.md`

```markdown
# CHOM Documentation

## I'm New Here
→ [Quick Start](../QUICK-START.md) (5 minutes)
→ [Getting Started Guide](getting-started/README.md) (30 minutes)
→ [First Site Tutorial](getting-started/first-site.md)

## By Role
→ [User Guide](guides/user-guide.md) - For site operators
→ [Developer Guide](guides/developer-guide.md) - For developers
→ [Operator Guide](guides/operator-guide.md) - For DevOps

## By Topic
→ [API Documentation](api/README.md)
→ [Security](security/README.md)
→ [Performance](performance/README.md)
→ [Deployment](deployment/README.md)

## Reference
→ [Architecture Diagrams](diagrams/README.md)
→ [Configuration Reference](reference/configuration.md)
→ [CLI Commands](reference/cli-commands.md)
```

### 2. Directory Indexes

**Every directory has README.md:**

Example: `docs/security/README.md`

```markdown
# Security Documentation

## Quick Start
- [Security Checklist](quick-reference.md) - Essential security steps

## Guides
- [Complete Security Guide](guide.md) - Comprehensive security
- [Authentication Setup](authentication.md) - 2FA configuration
- [Authorization](authorization.md) - Roles & permissions

## Reference
- [Security Audit Checklist](audit-checklist.md)
- [Incident Response](incident-response.md)

## Related Documentation
- [Deployment Security](../deployment/security-hardening.md)
- [API Authentication](../api/authentication.md)
```

### 3. Breadcrumb Navigation

**At top of every document:**

```markdown
[Home](../../README.md) > [Documentation](../README.md) > [Security](README.md) > Guide

# Security Guide
```

### 4. Related Links

**At bottom of every document:**

```markdown
---

## Related Documentation

- [API Authentication](../api/authentication.md)
- [Deployment Security](../deployment/security-hardening.md)
- [User Management](../guides/user-guide.md#user-management)

## Next Steps

- [Configure 2FA](authentication.md)
- [Run Security Audit](audit-checklist.md)
- [Review Incident Response](incident-response.md)
```

### 5. Quick Reference Cards

**In each major section:**

```markdown
## Quick Reference

| Task | Command/Link |
|------|--------------|
| Enable 2FA | See [Authentication](authentication.md#2fa) |
| Run security scan | `composer security-check` |
| Review audit logs | [Dashboard](https://chom.io/audit) |
| Report security issue | security@chom.io |
```

---

## What Stays in Root vs docs/

### Root Directory (8 files)

**Purpose:** Essential project information

```
chom/
├── README.md              # Project overview, badges, quick links
├── QUICK-START.md         # 5-minute getting started
├── CONTRIBUTING.md        # Contribution guidelines
├── CHANGELOG.md           # Version history
├── CODE-STYLE.md          # Code standards
├── LICENSE.md             # License
├── SECURITY.md            # Security policy & reporting
└── .github/               # GitHub-specific files
    └── PULL_REQUEST_TEMPLATE.md
```

**Why in root:**
- First impression for GitHub visitors
- Required by GitHub (LICENSE, SECURITY.md)
- Common conventions (CONTRIBUTING.md, CHANGELOG.md)
- Quick access for developers

### docs/ Directory (All other docs)

**Purpose:** Comprehensive documentation

**Why in docs/:**
- Keeps root clean and focused
- Allows better organization
- Standard practice for large projects
- Easier to version documentation

### deploy/ Directory (Deployment-specific)

**Purpose:** Deployment scripts AND docs

```
deploy/
├── README.md                  # Main deployment guide
├── deploy-enhanced.sh         # Deployment script
├── configs/                   # Configuration templates
├── scripts/                   # Helper scripts
└── docs/                      # Deploy-specific docs
```

**Why separate:**
- Deployment is self-contained workflow
- Scripts + docs together
- Can be distributed separately
- Clear separation of concerns

### tests/ Directory (Test-specific)

**Purpose:** Test suite AND test docs

```
tests/
├── README.md                  # Testing overview
├── quick-reference.md         # Quick commands
├── Feature/                   # Feature tests
├── Unit/                      # Unit tests
└── ...
```

**Why separate:**
- Co-located with test code
- Developers expect docs with tests
- Test documentation is code documentation

---

## Migration Plan

### Phase 1: Preparation (Day 1)

**Actions:**
1. Create backup branch
2. Create new directory structure
3. Set up archive directory
4. Create tracking spreadsheet

**Commands:**
```bash
git checkout -b docs/architecture-v2
mkdir -p docs/{getting-started,guides,api,development,deployment,security,performance,database,components,diagrams,reference,archive}
```

### Phase 2: Consolidate by Topic (Days 2-6)

#### Day 2: Security (10 files → 6 files)

**Consolidate:**
- Merge `/SECURITY-IMPLEMENTATION.md` + `/docs/SECURITY-IMPLEMENTATION.md` → `docs/security/guide.md`
- Merge 2 versions of QUICK-REFERENCE → `docs/security/quick-reference.md`
- Create `docs/security/authentication.md` (extract 2FA content)
- Create `docs/security/authorization.md` (extract RBAC content)

**Archive:**
- `2FA-CONFIG-SUMMARY.md`
- `SECURITY-AUDIT-REPORT.md`

#### Day 3: Deployment (12 files → 5 files)

**Consolidate:**
- Merge deploy docs → `deploy/README.md`
- Merge QUICKSTART + QUICK-START → `docs/deployment/quick-start.md`
- Create `docs/deployment/troubleshooting.md`

**Move:**
- `deploy/SUDO-USER-SETUP.md` → `deploy/docs/sudo-user-setup.md`
- `deploy/SECURITY-REVIEW.md` → `deploy/docs/security-review.md`

#### Day 4: Performance & Database (9 files → 6 files)

**Consolidate:**
- Merge performance docs → `docs/performance/guide.md`
- Merge database docs → `docs/database/optimization.md`

#### Day 5: Development & API (12 files → 8 files)

**Reorganize:**
- Move architecture docs to `docs/development/`
- Organize API docs in `docs/api/`
- Create `docs/development/setup.md`

#### Day 6: Getting Started & Guides (Create new)

**Create:**
- `docs/getting-started/installation.md`
- `docs/getting-started/configuration.md`
- `docs/getting-started/first-site.md`
- `docs/guides/user-guide.md`
- `docs/guides/developer-guide.md`
- `docs/guides/operator-guide.md`

**Extract from:**
- Current README.md
- ONBOARDING.md
- DEVELOPMENT.md

### Phase 3: Navigation (Day 7)

**Create:**
- `docs/README.md` - Main documentation hub
- README.md in every directory
- Update root README.md with new links

### Phase 4: Validation (Day 8)

**Tasks:**
- Fix all broken links
- Validate all code examples
- Test all navigation paths
- Review for duplicates

### Phase 5: Finalize (Day 9)

**Tasks:**
- Create migration guide
- Update all cross-references
- Final review and approval
- Merge to main

---

## Before/After Examples

### Example 1: Security Documentation

#### BEFORE (10 files, lots of duplication)

```
/SECURITY-IMPLEMENTATION.md (1,098 lines)
/docs/SECURITY-IMPLEMENTATION.md (different content!)
/docs/security/application-security.md (750 lines)
/SECURITY-QUICK-REFERENCE.md (644 lines)
/docs/SECURITY-QUICK-REFERENCE.md (537 lines, DIFFERENT!)
/docs/2FA-CONFIGURATION-GUIDE.md (595 lines)
/docs/security/2FA-CONFIGURATION-UPDATE.md
/2FA-CONFIGURATION-UPDATE.md (duplicate!)
/docs/SECURITY-AUDIT-CHECKLIST.md
/deploy/2FA-CONFIG-SUMMARY.md
```

**Problems:**
- Duplicate filenames (which one is current?)
- Content scattered across 10 files
- 30-40% duplication
- Hard to find information
- No clear navigation

#### AFTER (6 files, organized, no duplication)

```
docs/security/
├── README.md                 # Security documentation index
├── guide.md                  # Comprehensive security guide (merged)
├── quick-reference.md        # Security checklist (merged)
├── authentication.md         # Auth & 2FA setup
├── authorization.md          # RBAC & policies
└── audit-checklist.md        # Security audit procedures
```

**Improvements:**
- Single source of truth
- Clear hierarchy
- No duplication
- Easy navigation
- Logical organization

### Example 2: Deployment Documentation

#### BEFORE (12 files, confusing)

```
deploy/
├── README.md
├── DEPLOYMENT-GUIDE.md (1,220 lines)
├── QUICKSTART.md (326 lines)
├── QUICK-START.md (173 lines, DIFFERENT!)
├── BUGFIX-CHECKLIST.md
├── CRITICAL-FINDINGS.md
├── QUICK-FIX-GUIDE.md
├── SUDO-USER-SETUP.md
├── UPDATE-GUIDE.md
├── SECURITY-REVIEW.md
├── INTERACTIVE-WORKFLOW.md
└── MINIMAL-INTERACTION-DESIGN.md
```

**Problems:**
- Two "quick start" files (which one?)
- Troubleshooting split across 3 files
- Design docs mixed with user docs
- No clear entry point

#### AFTER (5 files + organized subdirectory)

```
deploy/
├── README.md                    # Main deployment guide (canonical)
├── deploy-enhanced.sh           # Deployment script
├── configs/                     # Configuration templates
├── scripts/                     # Helper scripts
└── docs/                        # Deploy-specific docs
    ├── sudo-user-setup.md       # User setup procedures
    ├── security-review.md       # Security checklist
    └── troubleshooting.md       # Common deployment issues

docs/deployment/
├── README.md                    # Deployment documentation index
├── quick-start.md               # 30-minute quick deploy
├── production-guide.md          # Complete production setup
├── configuration.md             # Environment configuration
├── security-hardening.md        # Security setup
├── monitoring.md                # Observability stack
└── updates.md                   # Update procedures
```

**Improvements:**
- Single quick-start guide
- Clear separation: scripts in deploy/, docs in docs/
- Consolidated troubleshooting
- Progressive disclosure (quick-start → production-guide)

### Example 3: Root Directory Cleanup

#### BEFORE (17 files, cluttered)

```
chom/
├── README.md
├── ONBOARDING.md
├── DEVELOPMENT.md
├── TESTING.md
├── CONTRIBUTING.md
├── CODE-STYLE.md
├── CHANGELOG.md
├── SECURITY-IMPLEMENTATION.md
├── 2FA-CONFIGURATION-UPDATE.md
├── DOCUMENTATION-SUMMARY.md
├── DOCUMENTATION-AUDIT-REPORT.md
├── DOCUMENTATION-CONSOLIDATION-PLAN.md
├── DOCUMENTATION-AUDIT-QUICK-REFERENCE.md
├── CLEANUP-REPORT.md
├── CLEANUP-SUMMARY.md
├── COMPREHENSIVE-VALIDATION-REPORT.md
└── NEXT-STEPS.md
```

**Problems:**
- Too many files (overwhelming)
- Implementation details in root
- Audit reports in root
- No clear priority

#### AFTER (8 files, focused)

```
chom/
├── README.md                    # Project overview + quick links
├── QUICK-START.md               # 5-minute getting started (NEW)
├── CONTRIBUTING.md              # Contribution guidelines
├── CHANGELOG.md                 # Version history
├── CODE-STYLE.md                # Code standards
├── LICENSE.md                   # License
├── SECURITY.md                  # Security policy
└── docs/                        # All other documentation
    ├── README.md                # Documentation hub (NEW)
    ├── getting-started/         # New user path (NEW)
    ├── guides/                  # Task guides (NEW)
    └── ...
```

**Improvements:**
- Clean, professional root
- Essential files only
- Clear entry points
- Implementation details moved to docs/

### Example 4: Developer Onboarding Path

#### BEFORE (fragmented path)

```
1. Read README.md
2. Search for "getting started"... find nothing
3. Try ONBOARDING.md
4. Try DEVELOPMENT.md
5. Look for API docs... where are they?
6. Give up, ask team
```

**Time:** 15-30 minutes of confusion

#### AFTER (clear path)

```
1. Read README.md → See "Quick Start (5 minutes)"
2. Click QUICK-START.md → Running locally in 5 minutes
3. Click "Next Steps" → docs/getting-started/
4. Follow getting-started/first-site.md → First site created
5. Need API? Click docs/api/quick-start.md → Integrated
```

**Time:** <10 minutes, productive immediately

---

## Implementation Roadmap

### Week 1: Core Restructuring

**Day 1-2: Security & Deployment**
- Consolidate security docs (10 → 6 files)
- Consolidate deployment docs (12 → 5 files)
- Fix duplicate file issues

**Day 3-4: Performance, Database, API**
- Consolidate performance docs (6 → 3 files)
- Consolidate database docs (3 → 2 files)
- Organize API docs (7 → 5 files)

**Day 5: Development & Components**
- Organize development docs
- Consolidate component docs (4 → 2 files)
- Create development/ structure

### Week 2: Navigation & Polish

**Day 6-7: Create Getting Started & Guides**
- Create docs/getting-started/ directory
- Create docs/guides/ directory
- Extract content from scattered sources

**Day 8: Navigation & Indexes**
- Create docs/README.md (main hub)
- Create README.md for all directories
- Update root README.md
- Create QUICK-START.md

**Day 9-10: Validation & Migration**
- Fix all broken links
- Test all navigation paths
- Create migration guide
- Final review

### Metrics & Success Criteria

**Must Have:**
- [ ] 94 files → 45 files (52% reduction)
- [ ] 0 duplicate filenames
- [ ] 0 broken links
- [ ] <10% content duplication
- [ ] README.md in every directory

**Should Have:**
- [ ] Clear navigation from any point
- [ ] <2 minutes to find any information
- [ ] Migration guide for existing bookmarks
- [ ] All code examples tested
- [ ] Consistent formatting

**Nice to Have:**
- [ ] Automated link checking (CI)
- [ ] Documentation version control
- [ ] Search functionality
- [ ] Interactive examples

---

## Appendix A: Complete File Mapping

### Security Files

| Current Location | New Location | Action |
|-----------------|--------------|--------|
| `/SECURITY-IMPLEMENTATION.md` | `docs/security/guide.md` | Merge |
| `/docs/SECURITY-IMPLEMENTATION.md` | `docs/security/guide.md` | Merge |
| `/docs/security/application-security.md` | `docs/security/guide.md` | Merge |
| `/SECURITY-QUICK-REFERENCE.md` | `docs/security/quick-reference.md` | Merge |
| `/docs/SECURITY-QUICK-REFERENCE.md` | `docs/security/quick-reference.md` | Merge |
| `/docs/2FA-CONFIGURATION-GUIDE.md` | `docs/security/authentication.md` | Extract |
| `/2FA-CONFIGURATION-UPDATE.md` | `docs/archive/security/` | Archive |
| `/docs/SECURITY-AUDIT-CHECKLIST.md` | `docs/security/audit-checklist.md` | Move |
| `/deploy/2FA-CONFIG-SUMMARY.md` | `docs/archive/security/` | Archive |

### Deployment Files

| Current Location | New Location | Action |
|-----------------|--------------|--------|
| `deploy/README.md` | `deploy/README.md` | Update |
| `deploy/DEPLOYMENT-GUIDE.md` | `deploy/README.md` | Merge |
| `deploy/QUICKSTART.md` | `docs/deployment/quick-start.md` | Merge |
| `deploy/QUICK-START.md` | `docs/deployment/quick-start.md` | Merge |
| `deploy/BUGFIX-CHECKLIST.md` | `deploy/docs/troubleshooting.md` | Merge |
| `deploy/CRITICAL-FINDINGS.md` | `deploy/docs/troubleshooting.md` | Merge |
| `deploy/QUICK-FIX-GUIDE.md` | `deploy/docs/troubleshooting.md` | Merge |
| `deploy/SUDO-USER-SETUP.md` | `deploy/docs/sudo-user-setup.md` | Move |
| `deploy/UPDATE-GUIDE.md` | `docs/deployment/updates.md` | Move |
| `deploy/SECURITY-REVIEW.md` | `deploy/docs/security-review.md` | Move |

### Performance Files

| Current Location | New Location | Action |
|-----------------|--------------|--------|
| `docs/PERFORMANCE-ANALYSIS.md` | `docs/performance/guide.md` | Merge |
| `docs/PERFORMANCE-IMPLEMENTATION-GUIDE.md` | `docs/performance/guide.md` | Merge |
| `docs/PERFORMANCE-BASELINES.md` | `docs/performance/guide.md` | Merge |
| `docs/PERFORMANCE-TESTING-GUIDE.md` | `docs/performance/testing.md` | Move |
| `docs/PERFORMANCE-QUICK-REFERENCE.md` | `docs/performance/quick-reference.md` | Move |
| `docs/PERFORMANCE-EXECUTIVE-SUMMARY.md` | `docs/archive/performance/` | Archive |

### Root Cleanup

| Current Location | New Location | Action |
|-----------------|--------------|--------|
| `ONBOARDING.md` | `docs/getting-started/README.md` | Extract |
| `DEVELOPMENT.md` | `docs/development/setup.md` | Move |
| `TESTING.md` | `docs/development/testing.md` | Move |
| `DOCUMENTATION-*.md` (5 files) | `docs/archive/` | Archive |
| `CLEANUP-*.md` (2 files) | `docs/archive/` | Archive |
| `COMPREHENSIVE-VALIDATION-REPORT.md` | `docs/archive/` | Archive |
| `NEXT-STEPS.md` | `docs/archive/` | Archive |

---

## Appendix B: Template for docs/README.md

```markdown
# CHOM Documentation

Welcome to the CHOM documentation! This guide will help you find exactly what you need.

---

## Quick Start Paths

### I'm Brand New
Never used CHOM before? Start here:

1. **[Quick Start](../QUICK-START.md)** (5 minutes)
   Get CHOM running locally with minimal setup

2. **[Installation Guide](getting-started/installation.md)** (15 minutes)
   Complete installation and configuration

3. **[First Site Tutorial](getting-started/first-site.md)** (20 minutes)
   Create and deploy your first WordPress site

4. **[Next Steps](getting-started/next-steps.md)**
   What to learn next based on your role

### I'm a Developer
Building features or contributing code:

1. **[Developer Guide](guides/developer-guide.md)** - Complete development guide
2. **[Architecture](development/architecture.md)** - System architecture
3. **[API Reference](api/reference.md)** - Complete API documentation
4. **[Testing Guide](development/testing.md)** - Running and writing tests

### I'm an Operator
Deploying or maintaining CHOM in production:

1. **[Deployment Quick Start](deployment/quick-start.md)** - Deploy in 30 minutes
2. **[Production Guide](deployment/production-guide.md)** - Complete production setup
3. **[Monitoring](deployment/monitoring.md)** - Set up observability
4. **[Troubleshooting](guides/troubleshooting.md)** - Fix common issues

### I'm a User
Operating sites through the CHOM dashboard:

1. **[User Guide](guides/user-guide.md)** - Complete user manual
2. **[First Site](getting-started/first-site.md)** - Create your first site
3. **[Troubleshooting](guides/troubleshooting.md)** - Common problems

---

## Documentation by Topic

### Core Topics

| Topic | Quick Start | Complete Guide | Reference |
|-------|-------------|----------------|-----------|
| **API** | [Quick Start](api/quick-start.md) | [API Guide](api/README.md) | [Reference](api/reference.md) |
| **Security** | [Checklist](security/quick-reference.md) | [Security Guide](security/guide.md) | [Audit](security/audit-checklist.md) |
| **Performance** | [Quick Tips](performance/quick-reference.md) | [Perf Guide](performance/guide.md) | [Testing](performance/testing.md) |
| **Deployment** | [Quick Deploy](deployment/quick-start.md) | [Production Guide](deployment/production-guide.md) | [Config](deployment/configuration.md) |

### Specialized Topics

- **[Database](database/README.md)** - Schema, migrations, optimization
- **[Components](components/README.md)** - UI component library
- **[Architecture](diagrams/README.md)** - System diagrams and design
- **[Reference](reference/README.md)** - Configuration, CLI, error codes

---

## Common Tasks

### Setup & Installation
- [Install CHOM locally](getting-started/installation.md)
- [Configure environment](getting-started/configuration.md)
- [Set up development environment](development/setup.md)
- [Deploy to production](deployment/production-guide.md)

### Daily Operations
- [Create a new site](getting-started/first-site.md)
- [Manage backups](guides/user-guide.md#backups)
- [Monitor performance](deployment/monitoring.md)
- [Update CHOM](deployment/updates.md)

### Development
- [Run tests](development/testing.md)
- [Use the API](api/quick-start.md)
- [Understand architecture](development/architecture.md)
- [Follow code style](../CODE-STYLE.md)

### Security
- [Enable 2FA](security/authentication.md)
- [Configure RBAC](security/authorization.md)
- [Run security audit](security/audit-checklist.md)
- [Harden production](deployment/security-hardening.md)

### Troubleshooting
- [Common issues](guides/troubleshooting.md)
- [Deployment problems](deployment/troubleshooting.md)
- [Performance issues](performance/guide.md#troubleshooting)
- [Security incidents](security/incident-response.md)

---

## Documentation Structure

```
docs/
├── getting-started/     # New user onboarding
├── guides/              # Task-oriented guides
├── api/                 # API documentation
├── development/         # Development topics
├── deployment/          # Deployment & operations
├── security/            # Security documentation
├── performance/         # Performance optimization
├── database/            # Database documentation
├── components/          # UI components
├── diagrams/            # Architecture diagrams
└── reference/           # Reference documentation
```

---

## Contributing to Documentation

Found an error? Want to improve the docs?

1. Read [Contributing Guidelines](../CONTRIBUTING.md)
2. Follow [Documentation Standards](../CODE-STYLE.md#documentation)
3. Submit a pull request

---

## Need Help?

- **GitHub Issues**: [Report bugs or request features](https://github.com/calounx/mentat/issues)
- **Discussions**: [Ask questions](https://github.com/calounx/mentat/discussions)
- **Email**: support@chom.io
- **Security**: security@chom.io (for security issues only)

---

**Last Updated:** 2025-12-30
**Documentation Version:** 2.0
```

---

## Appendix C: Template for QUICK-START.md

```markdown
# CHOM Quick Start (5 Minutes)

Get CHOM running locally in 5 minutes or less.

---

## Prerequisites

Verify you have these installed:

```bash
php -v        # Need PHP 8.2+
composer -V   # Need Composer 2.x
node -v       # Need Node.js 18+
git --version # Need Git
```

Don't have them? See [Installation Guide](docs/getting-started/installation.md).

---

## Quick Setup

### 1. Clone & Install (2 minutes)

```bash
# Clone repository
git clone https://github.com/calounx/mentat.git
cd mentat/chom

# Install dependencies
composer install && npm install
```

### 2. Configure (1 minute)

```bash
# Create environment file
cp .env.example .env

# Generate application key
php artisan key:generate

# Create SQLite database
touch database/database.sqlite
```

### 3. Setup Database (1 minute)

```bash
# Run migrations
php artisan migrate

# (Optional) Seed sample data
php artisan db:seed --class=TestUserSeeder
```

### 4. Start Development Server (1 minute)

```bash
# Build frontend assets
npm run build

# Start Laravel server
php artisan serve
```

**Done!** Open http://localhost:8000

---

## What's Next?

### Create Your First Site (10 minutes)
Follow the [First Site Tutorial](docs/getting-started/first-site.md) to:
- Create a WordPress site
- Configure SSL
- Set up monitoring

### Learn More
- **[Full Installation Guide](docs/getting-started/installation.md)** - Detailed setup
- **[Developer Guide](docs/guides/developer-guide.md)** - Development workflow
- **[API Quick Start](docs/api/quick-start.md)** - API integration

### Join the Community
- Star the repo on [GitHub](https://github.com/calounx/mentat)
- Read [Contributing Guidelines](CONTRIBUTING.md)
- Join [Discussions](https://github.com/calounx/mentat/discussions)

---

## Troubleshooting

### Common Issues

**"composer: command not found"**
```bash
# Install Composer
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer
```

**"Class 'PDO' not found"**
```bash
# Enable PHP PDO extension
# Ubuntu/Debian:
sudo apt-get install php-sqlite3
# macOS:
brew install php
```

**Port 8000 already in use**
```bash
# Use different port
php artisan serve --port=8080
```

### Get Help
- [Troubleshooting Guide](docs/guides/troubleshooting.md)
- [GitHub Discussions](https://github.com/calounx/mentat/discussions)
- [Email Support](mailto:support@chom.io)

---

**Estimated Time:** 5 minutes
**Difficulty:** Beginner
**Next:** [Create Your First Site](docs/getting-started/first-site.md)
```

---

## Conclusion

This documentation architecture proposal provides:

1. **Clear Organization** - Audience-first, topic-based structure
2. **Progressive Disclosure** - Quick start → Guides → Reference → Deep dive
3. **Single Source of Truth** - No duplicate content
4. **Excellent Navigation** - Hub-and-spoke model with breadcrumbs
5. **52% File Reduction** - 94 files → 45 files
6. **Professional Structure** - Industry best practices

### Implementation Timeline

- **Week 1:** Core restructuring (Days 1-5)
- **Week 2:** Navigation and validation (Days 6-10)
- **Total:** 10 days

### Expected Outcomes

- Developers productive in <10 minutes (vs 30+ currently)
- Information findable in <2 minutes (vs 5-10 currently)
- Zero broken links (vs 15+ currently)
- Professional, maintainable documentation structure

---

**Status:** Ready for approval and implementation
**Owner:** Documentation Team
**Timeline:** 2 weeks
**Next Step:** Approve plan and begin Phase 1
