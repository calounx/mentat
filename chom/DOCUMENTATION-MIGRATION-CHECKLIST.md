# CHOM Documentation Migration - Implementation Checklist

**Timeline:** 10 days
**Goal:** Migrate from 94 files to 45 well-organized files

---

## Quick Reference

| Phase | Days | Files Before | Files After | Status |
|-------|------|--------------|-------------|--------|
| Preparation | Day 1 | 94 | 94 | [ ] |
| Security | Day 2 | 94 | 84 | [ ] |
| Deployment | Day 3 | 84 | 77 | [ ] |
| Performance/Database | Day 4 | 77 | 69 | [ ] |
| API/Components | Day 5 | 69 | 62 | [ ] |
| Getting Started | Day 6 | 62 | 67 | [ ] |
| Navigation | Day 7 | 67 | 70 | [ ] |
| Archive | Day 8 | 70 | 45 | [ ] |
| Validation | Day 9 | 45 | 45 | [ ] |
| Finalize | Day 10 | 45 | 45 | [ ] |

---

## Day 1: Preparation

### Setup

- [ ] Create backup of all current documentation
  ```bash
  cd /home/calounx/repositories/mentat/chom
  tar -czf docs-backup-$(date +%Y%m%d).tar.gz *.md docs/ deploy/ tests/
  ```

- [ ] Create feature branch
  ```bash
  git checkout -b docs/architecture-v2
  git push -u origin docs/architecture-v2
  ```

- [ ] Create new directory structure
  ```bash
  mkdir -p docs/{getting-started,guides,api,development,deployment,security,performance,database,components,diagrams,reference,archive}
  mkdir -p docs/archive/{security,deployment,performance,implementation-reports,design-docs}
  mkdir -p deploy/docs
  ```

- [ ] Create tracking spreadsheet
  - Copy template from this checklist
  - Track file movements
  - Note any issues

### Deliverables

- [ ] Backup created: `docs-backup-YYYYMMDD.tar.gz`
- [ ] Branch created: `docs/architecture-v2`
- [ ] Directory structure ready
- [ ] Tracking spreadsheet initialized

**Commit:** "docs: initialize architecture v2 directory structure"

---

## Day 2: Security Documentation

**Goal:** Consolidate 10 security files into 6 organized files

### Step 1: Create docs/security/guide.md

- [ ] Start with `/SECURITY-IMPLEMENTATION.md` as base
  ```bash
  cp SECURITY-IMPLEMENTATION.md docs/security/guide.md
  ```

- [ ] Merge unique content from:
  - [ ] `/docs/SECURITY-IMPLEMENTATION.md`
  - [ ] `/docs/security/application-security.md`
  - [ ] Relevant sections from `/docs/2FA-CONFIGURATION-GUIDE.md`

- [ ] Add table of contents
- [ ] Update all internal links
- [ ] Test all code examples

**Expected:** ~1,800 lines comprehensive guide

### Step 2: Create docs/security/quick-reference.md

- [ ] Compare both versions:
  ```bash
  diff SECURITY-QUICK-REFERENCE.md docs/SECURITY-QUICK-REFERENCE.md
  ```

- [ ] Merge best content from:
  - [ ] `/SECURITY-QUICK-REFERENCE.md` (644 lines)
  - [ ] `/docs/SECURITY-QUICK-REFERENCE.md` (537 lines)

- [ ] Remove duplicates
- [ ] Keep practical examples
- [ ] Update code samples

**Expected:** ~600 lines unified reference

### Step 3: Create docs/security/authentication.md

- [ ] Extract 2FA content from:
  - [ ] `/2FA-CONFIGURATION-UPDATE.md`
  - [ ] `/docs/2FA-CONFIGURATION-GUIDE.md`
  - [ ] Sections from guide.md

- [ ] Organize by topic:
  - [ ] 2FA setup
  - [ ] Token management
  - [ ] Session security

**Expected:** ~400 lines

### Step 4: Create docs/security/authorization.md

- [ ] Extract RBAC content from security guides
- [ ] Document:
  - [ ] Role definitions
  - [ ] Permission system
  - [ ] Policy configuration

**Expected:** ~300 lines

### Step 5: Move audit checklist

- [ ] Move file:
  ```bash
  mv docs/SECURITY-AUDIT-CHECKLIST.md docs/security/audit-checklist.md
  ```

- [ ] Update links
- [ ] Verify content

### Step 6: Create docs/security/README.md

- [ ] Create navigation hub for security docs
- [ ] Link to all security files
- [ ] Add quick reference table
- [ ] Include related documentation links

### Step 7: Archive old files

- [ ] Archive summaries:
  ```bash
  mv SECURITY-AUDIT-REPORT.md docs/archive/security/
  mv 2FA-CONFIGURATION-UPDATE.md docs/archive/security/
  mv docs/SECURITY-IMPLEMENTATION-SUMMARY.md docs/archive/security/
  mv deploy/2FA-CONFIG-SUMMARY.md docs/archive/security/
  ```

### Step 8: Delete old files

- [ ] Verify merges are complete
- [ ] Delete old files:
  ```bash
  rm SECURITY-IMPLEMENTATION.md
  rm SECURITY-QUICK-REFERENCE.md
  rm docs/SECURITY-IMPLEMENTATION.md
  rm docs/SECURITY-QUICK-REFERENCE.md
  rm docs/2FA-CONFIGURATION-GUIDE.md
  rm docs/security/application-security.md
  rm docs/security/SECURITY-QUICK-REFERENCE.md
  ```

### Validation

- [ ] All security content preserved
- [ ] No broken links in security docs
- [ ] All code examples work
- [ ] README.md provides clear navigation

**Commit:** "docs: consolidate security documentation (10 → 6 files)"

**Files Before:** 94
**Files After:** 84 (-10)

---

## Day 3: Deployment Documentation

**Goal:** Consolidate 12 deployment files into 5 + organized subdirectory

### Step 1: Update deploy/README.md

- [ ] Use `deploy/DEPLOYMENT-GUIDE.md` as base
- [ ] Merge content from:
  - [ ] Current `deploy/README.md`
  - [ ] `deploy/README-ENHANCED.md` (if exists)

- [ ] Structure:
  - [ ] Overview
  - [ ] Quick start (link to docs/deployment/quick-start.md)
  - [ ] Prerequisites
  - [ ] Deployment steps
  - [ ] Verification
  - [ ] Troubleshooting (link to troubleshooting.md)

**Expected:** ~1,500 lines

### Step 2: Create docs/deployment/quick-start.md

- [ ] Compare both quick starts:
  ```bash
  diff deploy/QUICKSTART.md deploy/QUICK-START.md
  ```

- [ ] Use `deploy/QUICKSTART.md` as base (more detailed)
- [ ] Add unique content from `deploy/QUICK-START.md`
- [ ] Create single comprehensive quick start

**Expected:** ~350 lines

### Step 3: Create deploy/docs/troubleshooting.md

- [ ] Merge content from:
  - [ ] `deploy/BUGFIX-CHECKLIST.md`
  - [ ] `deploy/CRITICAL-FINDINGS.md`
  - [ ] `deploy/QUICK-FIX-GUIDE.md`

- [ ] Organize by category:
  - [ ] SSH/Authentication issues
  - [ ] Permission issues
  - [ ] Service startup issues
  - [ ] Network/firewall issues

**Expected:** ~600 lines

### Step 4: Move deployment docs

- [ ] Move to deploy/docs/:
  ```bash
  mv deploy/SUDO-USER-SETUP.md deploy/docs/sudo-user-setup.md
  mv deploy/SECURITY-REVIEW.md deploy/docs/security-review.md
  ```

- [ ] Keep `deploy/UPDATE-GUIDE.md` (move to docs/deployment/)
  ```bash
  mv deploy/UPDATE-GUIDE.md docs/deployment/updates.md
  ```

### Step 5: Create docs/deployment/ directory

- [ ] Create `docs/deployment/README.md`
- [ ] Create `docs/deployment/production-guide.md` (extract from deploy/README.md)
- [ ] Create `docs/deployment/configuration.md` (extract config sections)
- [ ] Create `docs/deployment/security-hardening.md` (security-specific deployment)
- [ ] Create `docs/deployment/monitoring.md` (observability stack setup)

### Step 6: Archive design docs

- [ ] Archive to docs/archive/deployment/:
  ```bash
  mv deploy/INTERACTIVE-WORKFLOW.md docs/archive/deployment/
  mv deploy/MINIMAL-INTERACTION-DESIGN.md docs/archive/deployment/
  mv deploy/IMPROVEMENTS-SUMMARY.md docs/archive/deployment/
  mv deploy/CLI-UX-IMPROVEMENTS.md docs/archive/deployment/
  mv deploy/CHANGELOG-3STEP.md docs/archive/deployment/
  ```

### Step 7: Delete old files

- [ ] Verify merges complete
- [ ] Delete:
  ```bash
  rm deploy/DEPLOYMENT-GUIDE.md
  rm deploy/QUICKSTART.md
  rm deploy/QUICK-START.md
  rm deploy/BUGFIX-CHECKLIST.md
  rm deploy/CRITICAL-FINDINGS.md
  rm deploy/QUICK-FIX-GUIDE.md
  ```

### Validation

- [ ] All deployment content preserved
- [ ] Clear separation: scripts in deploy/, docs in docs/deployment/
- [ ] No broken links
- [ ] Single quick-start guide (no confusion)

**Commit:** "docs: consolidate deployment documentation (12 → 5 files)"

**Files Before:** 84
**Files After:** 77 (-7)

---

## Day 4: Performance & Database Documentation

**Goal:** Consolidate performance (6 → 3) and database (3 → 4) docs

### Performance Documentation

#### Step 1: Create docs/performance/guide.md

- [ ] Merge content from:
  - [ ] `docs/PERFORMANCE-ANALYSIS.md` (1,545 lines)
  - [ ] `docs/PERFORMANCE-IMPLEMENTATION-GUIDE.md` (1,444 lines)
  - [ ] `docs/PERFORMANCE-BASELINES.md` (575 lines)
  - [ ] `docs/performance/PERFORMANCE-OPTIMIZATIONS.md` (412 lines)

- [ ] Structure:
  - [ ] Overview & Analysis
  - [ ] Implementation Guide
  - [ ] Baselines & Metrics
  - [ ] Optimizations Applied
  - [ ] Troubleshooting

**Expected:** ~3,200 lines

#### Step 2: Organize remaining performance docs

- [ ] Move files:
  ```bash
  mv docs/PERFORMANCE-TESTING-GUIDE.md docs/performance/testing.md
  mv docs/PERFORMANCE-QUICK-REFERENCE.md docs/performance/quick-reference.md
  ```

#### Step 3: Create docs/performance/README.md

- [ ] Performance documentation index
- [ ] Links to guide, testing, quick-reference
- [ ] Related documentation

#### Step 4: Archive performance summaries

- [ ] Archive:
  ```bash
  mv docs/PERFORMANCE-EXECUTIVE-SUMMARY.md docs/archive/performance/
  ```

#### Step 5: Delete old performance files

- [ ] Verify merges complete
- [ ] Delete:
  ```bash
  rm docs/PERFORMANCE-ANALYSIS.md
  rm docs/PERFORMANCE-IMPLEMENTATION-GUIDE.md
  rm docs/PERFORMANCE-BASELINES.md
  rm docs/performance/PERFORMANCE-OPTIMIZATIONS.md
  ```

### Database Documentation

#### Step 1: Create docs/database/README.md

- [ ] Database documentation index
- [ ] Overview of database topics

#### Step 2: Create docs/database/schema.md

- [ ] NEW: Document database schema
- [ ] Include ER diagrams
- [ ] Table relationships
- [ ] Key indexes

**Expected:** ~400 lines

#### Step 3: Create docs/database/optimization.md

- [ ] Merge from:
  - [ ] `docs/database/DATABASE_OPTIMIZATION_SUMMARY.md`
  - [ ] `docs/database/DATABASE_OPTIMIZATION_QUICK_REFERENCE.md`

**Expected:** ~700 lines

#### Step 4: Keep Redis setup

- [ ] Move file:
  ```bash
  mv docs/database/REDIS-SETUP.md docs/database/redis-setup.md
  ```

#### Step 5: Delete old database files

- [ ] Verify merges complete
- [ ] Delete:
  ```bash
  rm docs/database/DATABASE_OPTIMIZATION_SUMMARY.md
  rm docs/database/DATABASE_OPTIMIZATION_QUICK_REFERENCE.md
  ```

### Validation

- [ ] All performance content preserved
- [ ] All database content preserved
- [ ] Clear organization
- [ ] No broken links

**Commit:** "docs: consolidate performance and database documentation"

**Files Before:** 77
**Files After:** 69 (-8)

---

## Day 5: API & Components Documentation

**Goal:** Organize API (7 → 5) and components (4 → 2) docs

### API Documentation

#### Step 1: Organize API docs

- [ ] Move to docs/api/:
  ```bash
  mv docs/API-README.md docs/api/README.md
  mv docs/API-QUICKSTART.md docs/api/quick-start.md
  mv docs/API-VERSIONING.md docs/api/versioning.md
  mv docs/API-CHANGELOG.md docs/api/changelog.md
  mv docs/L5-SWAGGER-SETUP.md docs/api/swagger-setup.md
  ```

#### Step 2: Create docs/api/reference.md

- [ ] Complete API reference
- [ ] All endpoints documented
- [ ] Request/response examples

#### Step 3: Create docs/api/authentication.md

- [ ] Extract auth content from README
- [ ] Document token authentication
- [ ] API key management

#### Step 4: Archive API summaries

- [ ] Archive:
  ```bash
  mv docs/api/API-DOCUMENTATION-SUMMARY.md docs/archive/api/
  mv docs/api/API-FILES-INDEX.md docs/archive/api/
  ```

### Components Documentation

#### Step 1: Create docs/components/library.md

- [ ] Move and rename:
  ```bash
  mv COMPONENT-LIBRARY.md docs/components/library.md
  ```

- [ ] Add intro from COMPONENT-README.md if useful

#### Step 2: Move quick reference

- [ ] Move:
  ```bash
  mv COMPONENT-QUICK-REFERENCE.md docs/components/quick-reference.md
  ```

#### Step 3: Create docs/components/README.md

- [ ] Components index
- [ ] Links to library and quick-reference

#### Step 4: Archive component summaries

- [ ] Archive:
  ```bash
  mv COMPONENT-SUMMARY.md docs/archive/components/
  ```

#### Step 5: Delete old component files

- [ ] Delete:
  ```bash
  rm COMPONENT-README.md
  ```

### Validation

- [ ] API docs well-organized
- [ ] Component docs consolidated
- [ ] No broken links
- [ ] Collections (Postman/Insomnia) still accessible

**Commit:** "docs: organize API and component documentation"

**Files Before:** 69
**Files After:** 62 (-7)

---

## Day 6: Getting Started Documentation

**Goal:** Create new getting-started/ directory (5 new files)

### Step 1: Create docs/getting-started/README.md

- [ ] Getting started index
- [ ] Clear paths for different audiences:
  - [ ] New users
  - [ ] Developers
  - [ ] Operators

**Expected:** ~300 lines

### Step 2: Create docs/getting-started/installation.md

- [ ] Extract from:
  - [ ] Root README.md (quick start section)
  - [ ] ONBOARDING.md (setup section)
  - [ ] DEVELOPMENT.md (environment setup)

- [ ] Content:
  - [ ] Prerequisites
  - [ ] Installation steps
  - [ ] Environment configuration
  - [ ] Verification

**Expected:** ~400 lines

### Step 3: Create docs/getting-started/configuration.md

- [ ] Extract from:
  - [ ] DEVELOPMENT.md
  - [ ] Various configuration guides

- [ ] Content:
  - [ ] Environment variables
  - [ ] Database setup
  - [ ] Cache configuration
  - [ ] Development settings

**Expected:** ~350 lines

### Step 4: Create docs/getting-started/first-site.md

- [ ] NEW comprehensive tutorial
- [ ] Content:
  - [ ] Create WordPress site
  - [ ] Configure domain
  - [ ] Issue SSL certificate
  - [ ] Deploy site
  - [ ] View monitoring
  - [ ] Create backup

**Expected:** ~500 lines

### Step 5: Create docs/getting-started/next-steps.md

- [ ] NEW role-based next steps
- [ ] Content:
  - [ ] For developers → development/
  - [ ] For operators → deployment/
  - [ ] For users → guides/user-guide.md
  - [ ] By topic (API, security, etc.)

**Expected:** ~250 lines

### Validation

- [ ] Clear onboarding path created
- [ ] Progressive tutorial (installation → configuration → first site)
- [ ] Role-based next steps
- [ ] All content original or properly extracted

**Commit:** "docs: create getting-started documentation"

**Files Before:** 62
**Files After:** 67 (+5)

---

## Day 7: Guides & Navigation

**Goal:** Create guides/ directory and navigation hubs

### Step 1: Create docs/guides/user-guide.md

- [ ] Extract user-focused content from:
  - [ ] Current README.md
  - [ ] Scattered user documentation

- [ ] Content:
  - [ ] Dashboard overview
  - [ ] Site management
  - [ ] Backup management
  - [ ] User management
  - [ ] Billing
  - [ ] FAQ

**Expected:** ~800 lines

### Step 2: Create docs/guides/developer-guide.md

- [ ] Extract/consolidate from:
  - [ ] DEVELOPMENT.md
  - [ ] ONBOARDING.md (developer sections)
  - [ ] Various dev guides

- [ ] Content:
  - [ ] Development environment
  - [ ] Code structure
  - [ ] Development workflow
  - [ ] Testing
  - [ ] Code quality
  - [ ] Contributing

**Expected:** ~1,000 lines

### Step 3: Create docs/guides/operator-guide.md

- [ ] NEW comprehensive operator guide
- [ ] Content:
  - [ ] Production deployment
  - [ ] Configuration management
  - [ ] Monitoring & observability
  - [ ] Backup & recovery
  - [ ] Updates & maintenance
  - [ ] Troubleshooting
  - [ ] Security

**Expected:** ~1,200 lines

### Step 4: Create docs/guides/troubleshooting.md

- [ ] Consolidate troubleshooting from:
  - [ ] Various guides
  - [ ] deployment/troubleshooting.md (link or merge)

- [ ] Organize by category:
  - [ ] Installation issues
  - [ ] Runtime errors
  - [ ] Performance problems
  - [ ] Security issues
  - [ ] Deployment problems

**Expected:** ~600 lines

### Step 5: Create docs/guides/README.md

- [ ] Guides index
- [ ] Links to all guides
- [ ] Guide by audience
- [ ] Guide by task

### Step 6: Create main documentation hub

- [ ] Create docs/README.md (use template from proposal)
- [ ] Content:
  - [ ] Quick start paths
  - [ ] Documentation by audience
  - [ ] Documentation by topic
  - [ ] Common tasks
  - [ ] Documentation structure

**Expected:** ~800 lines

### Step 7: Update root README.md

- [ ] Update documentation section
- [ ] Add clear links to:
  - [ ] QUICK-START.md
  - [ ] docs/README.md
  - [ ] docs/getting-started/
  - [ ] docs/guides/

- [ ] Add quick reference table
- [ ] Update architecture section

### Step 8: Create QUICK-START.md

- [ ] Create root QUICK-START.md (use template from proposal)
- [ ] Content:
  - [ ] 5-minute setup
  - [ ] Quick commands
  - [ ] What's next
  - [ ] Troubleshooting

**Expected:** ~200 lines

### Validation

- [ ] Clear navigation from any point
- [ ] docs/README.md serves as hub
- [ ] All guides comprehensive
- [ ] No broken links

**Commit:** "docs: create guides and navigation hubs"

**Files Before:** 67
**Files After:** 70 (+3)

---

## Day 8: Archive & Cleanup

**Goal:** Archive historical documents and clean up root

### Step 1: Create archive structure

- [ ] Ensure directories exist:
  ```bash
  mkdir -p docs/archive/{security,deployment,performance,testing,implementation-reports,design-docs}
  ```

### Step 2: Archive implementation reports

- [ ] Move to docs/archive/implementation-reports/:
  ```bash
  mv CLEANUP-SUMMARY.md docs/archive/implementation-reports/
  mv CLEANUP-REPORT.md docs/archive/implementation-reports/
  mv COMPREHENSIVE-VALIDATION-REPORT.md docs/archive/implementation-reports/
  mv docs/IMPLEMENTATION-SUMMARY.md docs/archive/implementation-reports/
  mv docs/FINAL-VALIDATION-SUMMARY.md docs/archive/implementation-reports/
  mv docs/DX-TOOLKIT-SUMMARY.md docs/archive/implementation-reports/
  ```

### Step 3: Archive documentation meta-docs

- [ ] Move to docs/archive/:
  ```bash
  mv DOCUMENTATION-SUMMARY.md docs/archive/
  mv DOCUMENTATION-AUDIT-REPORT.md docs/archive/
  mv DOCUMENTATION-CONSOLIDATION-PLAN.md docs/archive/
  mv DOCUMENTATION-AUDIT-QUICK-REFERENCE.md docs/archive/
  ```

### Step 4: Archive NEXT-STEPS.md

- [ ] Move to archive:
  ```bash
  mv NEXT-STEPS.md docs/archive/
  ```

### Step 5: Move development docs

- [ ] Create docs/development/ if not exists
- [ ] Move/consolidate:
  ```bash
  mv ONBOARDING.md docs/archive/  # Content extracted to getting-started/
  mv DEVELOPMENT.md docs/development/setup.md
  mv TESTING.md docs/development/testing.md
  ```

### Step 6: Create docs/archive/README.md

- [ ] Document archive structure
- [ ] List archived documents by category
- [ ] Explain why documents were archived

### Step 7: Verify root directory

- [ ] Root should contain only:
  - [ ] README.md
  - [ ] QUICK-START.md
  - [ ] CONTRIBUTING.md
  - [ ] CHANGELOG.md
  - [ ] CODE-STYLE.md
  - [ ] LICENSE.md
  - [ ] SECURITY.md
  - [ ] (Optional) COMPONENT-FILES.txt

### Step 8: Clean up docs/ directory

- [ ] Remove any remaining scattered files
- [ ] Ensure all files are in proper subdirectories
- [ ] No loose files in docs/ root except README.md

### Validation

- [ ] Root directory clean (8 files)
- [ ] All implementation details in docs/
- [ ] Archive well-organized
- [ ] No important content lost

**Commit:** "docs: archive historical documents and clean up root"

**Files Before:** 70
**Files After:** 45 (-25 archived)

---

## Day 9: Link Validation & Testing

**Goal:** Fix all broken links and validate navigation

### Step 1: Create link validation script

- [ ] Create script:
  ```bash
  cat > /tmp/validate-links.sh << 'EOF'
  #!/bin/bash
  cd /home/calounx/repositories/mentat/chom

  echo "Checking for broken markdown links..."
  broken_links=0

  find . -name "*.md" -not -path "./vendor/*" -not -path "./node_modules/*" | while read file; do
    grep -o '\[.*\](.*\.md[^)]*)' "$file" | while read link; do
      target=$(echo "$link" | sed 's/.*(\([^)]*\))/\1/' | sed 's/#.*//')
      dir=$(dirname "$file")

      if [[ "$target" == /* ]]; then
        # Absolute path
        full_path="$target"
      else
        # Relative path
        full_path="$dir/$target"
      fi

      # Normalize path
      full_path=$(realpath -m "$full_path" 2>/dev/null || echo "$full_path")

      if [[ ! -f "$full_path" ]]; then
        echo "BROKEN: $file -> $target"
        ((broken_links++))
      fi
    done
  done

  echo ""
  echo "Total broken links: $broken_links"
  EOF
  chmod +x /tmp/validate-links.sh
  ```

- [ ] Run script:
  ```bash
  /tmp/validate-links.sh > /tmp/broken-links.txt
  cat /tmp/broken-links.txt
  ```

### Step 2: Fix broken links

- [ ] Review /tmp/broken-links.txt
- [ ] Fix each broken link:
  - [ ] Update path if file moved
  - [ ] Remove link if target archived
  - [ ] Replace with new link if consolidated

### Step 3: Validate code examples

- [ ] Test code examples in:
  - [ ] docs/security/quick-reference.md
  - [ ] docs/deployment/quick-start.md
  - [ ] docs/api/quick-start.md
  - [ ] docs/performance/quick-reference.md
  - [ ] QUICK-START.md

- [ ] Verify:
  - [ ] Bash commands are valid
  - [ ] PHP code is syntactically correct
  - [ ] Paths are correct

### Step 4: Test navigation paths

- [ ] Test audience paths:
  - [ ] New user path (README → getting-started → first-site)
  - [ ] Developer path (README → QUICK-START → development)
  - [ ] Operator path (README → deployment)

- [ ] Verify all README.md files:
  - [ ] docs/README.md
  - [ ] docs/getting-started/README.md
  - [ ] docs/guides/README.md
  - [ ] docs/api/README.md
  - [ ] docs/security/README.md
  - [ ] docs/deployment/README.md
  - [ ] docs/performance/README.md
  - [ ] docs/database/README.md
  - [ ] docs/components/README.md
  - [ ] docs/development/README.md

### Step 5: Verify file count

- [ ] Count markdown files:
  ```bash
  find . -name "*.md" -not -path "./vendor/*" -not -path "./node_modules/*" -not -path "./docs/archive/*" | wc -l
  ```
- [ ] Should be ~45 files

### Step 6: Check for duplicates

- [ ] Check for duplicate filenames:
  ```bash
  find . -name "*.md" -not -path "./vendor/*" -not -path "./node_modules/*" -not -path "./docs/archive/*" -exec basename {} \; | sort | uniq -d
  ```
- [ ] Should only show README.md (which is expected)

### Step 7: Verify content completeness

- [ ] Check major topics covered:
  - [ ] Security ✓
  - [ ] Deployment ✓
  - [ ] Performance ✓
  - [ ] API ✓
  - [ ] Database ✓
  - [ ] Components ✓
  - [ ] Getting Started ✓
  - [ ] Development ✓

### Validation

- [ ] Zero broken links
- [ ] All code examples work
- [ ] All navigation paths functional
- [ ] File count ~45
- [ ] No unexpected duplicates

**Commit:** "docs: fix broken links and validate navigation"

---

## Day 10: Finalization

**Goal:** Final polish and preparation for merge

### Step 1: Create migration guide

- [ ] Create docs/MIGRATION-GUIDE.md
- [ ] Content:
  - [ ] What changed
  - [ ] File mapping table (old → new)
  - [ ] Topic-based lookup
  - [ ] Search tips

**Expected:** ~400 lines

### Step 2: Standardize formatting

- [ ] Verify consistent formatting:
  - [ ] Heading levels (# → ## → ### → ####)
  - [ ] Code block language tags
  - [ ] Table formatting
  - [ ] File naming (lowercase-with-hyphens)

- [ ] Add table of contents to long docs (>500 lines):
  - [ ] docs/security/guide.md
  - [ ] docs/performance/guide.md
  - [ ] docs/guides/developer-guide.md
  - [ ] docs/guides/operator-guide.md

### Step 3: Add breadcrumbs

- [ ] Add breadcrumb navigation to all docs:
  ```markdown
  [Home](../../README.md) > [Documentation](../README.md) > [Topic](README.md) > Page
  ```

### Step 4: Add related links

- [ ] Ensure all docs have "Related Documentation" section
- [ ] Add "Next Steps" where appropriate

### Step 5: Final review checklist

**Structure:**
- [ ] 45 active documentation files
- [ ] ~33 archived files
- [ ] Directory structure matches proposal
- [ ] Archive is organized with README

**Content:**
- [ ] No duplicate content
- [ ] All important info preserved
- [ ] Code examples work
- [ ] Links are valid
- [ ] Navigation is clear

**Quality:**
- [ ] Formatting is consistent
- [ ] TOCs are accurate
- [ ] Headers are hierarchical
- [ ] No orphaned files
- [ ] Breadcrumbs present

**Git:**
- [ ] All changes committed
- [ ] Commit messages clear
- [ ] No large binary files
- [ ] .gitignore updated if needed

### Step 6: Generate metrics report

- [ ] Create final metrics:
  ```bash
  echo "=== Documentation Migration Metrics ===" > /tmp/migration-metrics.txt
  echo "" >> /tmp/migration-metrics.txt
  echo "Files before: 94" >> /tmp/migration-metrics.txt
  echo "Files after: $(find . -name "*.md" -not -path "./vendor/*" -not -path "./node_modules/*" -not -path "./docs/archive/*" | wc -l)" >> /tmp/migration-metrics.txt
  echo "Files archived: $(find docs/archive -name "*.md" | wc -l)" >> /tmp/migration-metrics.txt
  echo "" >> /tmp/migration-metrics.txt
  echo "Root files: $(find . -maxdepth 1 -name "*.md" | wc -l)" >> /tmp/migration-metrics.txt
  echo "Broken links: 0" >> /tmp/migration-metrics.txt
  ```

### Step 7: Create pull request

- [ ] Push branch:
  ```bash
  git push origin docs/architecture-v2
  ```

- [ ] Create PR with:
  - [ ] Title: "Documentation Architecture v2"
  - [ ] Description summarizing changes
  - [ ] Link to proposal
  - [ ] Metrics summary
  - [ ] Migration guide link

### Step 8: Request team review

- [ ] Tag reviewers
- [ ] Post in team chat
- [ ] Walk through changes if needed

### Validation

- [ ] All checklist items complete
- [ ] Metrics look good
- [ ] PR created
- [ ] Team notified

**Commit:** "docs: finalize architecture v2 migration"

---

## Post-Migration Tasks

### Week 1

- [ ] Monitor for broken link reports
- [ ] Address feedback from team
- [ ] Update external references (if any)
- [ ] Create announcement post

### Month 1

- [ ] Add any missing documentation
- [ ] Improve code examples based on feedback
- [ ] Add more diagrams where helpful
- [ ] Consider video tutorials

### Quarter 1

- [ ] Set up automated link checking (CI)
- [ ] Implement documentation versioning
- [ ] Add search functionality
- [ ] Gather metrics on usage

---

## Success Metrics

### Must Achieve

- [ ] File count: 94 → 45 (52% reduction) ✓
- [ ] Broken links: 0 ✓
- [ ] Content duplication: <10% ✓
- [ ] Clear entry points: 3+ ✓
- [ ] All topics covered ✓

### Should Achieve

- [ ] Time to find info: <2 minutes ✓
- [ ] Time to productivity: <15 minutes ✓
- [ ] Migration guide created ✓
- [ ] Code examples tested ✓
- [ ] Team approval ✓

### Nice to Have

- [ ] Improved diagrams
- [ ] Better code examples
- [ ] Video walkthroughs
- [ ] Automated link checking
- [ ] Documentation CI/CD

---

## Rollback Plan

If migration needs to be rolled back:

1. **Restore from backup:**
   ```bash
   git checkout master
   git branch -D docs/architecture-v2
   tar -xzf docs-backup-YYYYMMDD.tar.gz
   ```

2. **Verify restoration:**
   - Check file count
   - Test critical links
   - Verify content

3. **Communicate rollback:**
   - Notify team
   - Document reason
   - Plan retry

---

## Support & Questions

**Project Lead:** TBD
**Documentation Owner:** TBD
**Questions:** Post in #documentation channel

**Issues:** Create GitHub issue with label `docs-migration`

---

**Last Updated:** 2025-12-30
**Version:** 1.0
**Status:** Ready for execution
