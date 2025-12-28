# Repository Cleanup Plan

> Generated from comprehensive file and documentation analysis - December 2025

## Executive Summary

**Files to Remove:** 6 files (~150KB)
**Documentation Issues:** 8 critical, 12 medium priority
**Overall Impact:** Reduced confusion, improved clarity, better user experience

---

## Phase 1: File Cleanup (IMMEDIATE)

### Files to Delete

1. **observability-stack/scripts/lib/module-loader.sh.bak**
   - Type: Backup file
   - Size: 24KB
   - Reason: Tracked in git by mistake, current version is functional
   - Risk: None - git history preserves old version
   - **ACTION: DELETE**

2. **observability-stack/tests/full-test-results.txt**
   - Type: Test artifact
   - Size: 59KB
   - Reason: Test output that shouldn't be committed
   - Risk: None - test results are regenerable
   - **ACTION: DELETE**

3. **observability-stack/config/global.yaml.example**
   - Type: Redundant configuration
   - Size: ~4KB
   - Reason: Identical to global.yaml.template (which uses secure syntax)
   - Risk: None - template is the canonical version
   - **ACTION: DELETE**

### Files to Archive

4. **observability-stack/scripts/setup-monitored-host-legacy.sh**
   - Type: Legacy script
   - Size: 43KB
   - Reason: Replaced by modular system
   - Risk: Low - functionality exists in new system
   - **ACTION: Move to scripts/archive/legacy/**

5. **observability-stack/scripts/phase3-rollback-loki.sh**
   - Type: One-time migration script
   - Size: 13KB
   - Reason: Phase 3 upgrade complete
   - Risk: Low - keep for 6 months then archive
   - **ACTION: Move to scripts/archive/migrations/**

6. **observability-stack/scripts/phase3-validate-integrity.sh**
   - Type: One-time migration script
   - Size: 14KB
   - Reason: Phase 3 upgrade complete
   - Risk: Low - keep for 6 months then archive
   - **ACTION: Move to scripts/archive/migrations/**

### Empty Directories to Document

7. **observability-stack/deploy/templates/**
   - **ACTION: Add README.md** explaining purpose

8. **observability-stack/modules/_available/**
   - **ACTION: Add README.md** for community modules

9. **observability-stack/modules/_custom/**
   - **ACTION: Add README.md** for user modules

10. **observability-stack/tempo/**
    - **ACTION: Remove** (consolidate into modules/_core/tempo/)

---

## Phase 2: Critical Documentation Fixes (HIGH PRIORITY)

### 1. Create Missing CHOM README.md ⚠️ CRITICAL

**File:** `chom/README.md`
**Issue:** Main project has no overview documentation
**Impact:** Users cannot understand CHOM without reading code
**Priority:** **CRITICAL**

**Content Needed:**
- Project overview and purpose
- Features list
- Architecture diagram
- Quick start guide
- Installation instructions
- Link to full documentation

### 2. Fix Version Inconsistencies ⚠️ HIGH

**Files Affected:**
- `/README.md` - Says v4.0.0
- `/observability-stack/SECURITY.md` - Says v3.0.x
- `/SECURITY.md` - Says v4.x.x (correct)

**Action:** Synchronize to v4.0.0 across all docs

### 3. Consolidate Security Documentation ⚠️ HIGH

**Current State:** 3 security files with 40% redundancy
- `/SECURITY.md`
- `/observability-stack/SECURITY.md`
- Overlap in reporting procedures, checklists

**Proposed Structure:**
```
SECURITY.md (root) - Master security policy
├── Reporting procedures (unified)
├── Supported versions (both projects)
└── Links to component-specific guides

observability-stack/docs/security/
├── infrastructure-security.md (obs-specific)
└── secrets-management.md (already exists)

chom/docs/security/
└── application-security.md (CHOM-specific)
```

### 4. Reduce CONTRIBUTING.md Redundancy

**Current State:** 60% overlap between root and observability-stack
**Action:**
- Root CONTRIBUTING.md: General guidelines (commit format, PR process, etc.)
- Component CONTRIBUTING.md: Only component-specific content
- Add clear cross-references

### 5. Add Prerequisites Section to Root README

**Missing:**
- OS requirements (Debian 13 / Ubuntu 22.04+)
- Technical knowledge level
- Estimated time
- Access requirements (root/sudo)

**Action:** Add "Before You Begin" section after intro

### 6. Create Glossary

**File:** `docs/GLOSSARY.md`
**Content:**
- SLO/SLI definitions
- OTLP, TSDB, WAL explanations
- VPS, SSH, systemd concepts
- All technical jargon used in docs

### 7. Improve QUICK_START.md

**Issues:**
- Assumes knowledge of VPS concepts
- Missing validation steps
- No "what's next" guidance

**Actions:**
- Explain each prompt users will see
- Add validation commands (curl tests)
- Add "First 5 Things to Do" section

### 8. Fix Deployment Wizard Discoverability

**File:** `deployment-wizard.sh`
**Issue:** Not mentioned in main README
**Action:** Add prominent link in root README

---

## Phase 3: Medium Priority Improvements

### 9. Create Troubleshooting Index

**File:** `docs/troubleshooting/README.md`
**Content:**
- Searchable index of common issues
- Links to solutions across all docs
- FAQ section

### 10. Add Architecture Diagrams

**Files Needing Diagrams:**
- Root README (system architecture)
- observability-stack/README.md (data flow)
- chom/README.md (application architecture)

**Format:** Mermaid diagrams (renders on GitHub)

### 11. Improve IMPLEMENTATION_GUIDE.md

**Issues:**
- Incomplete dashboard examples (says "for brevity")
- Missing testing sections
- No error handling

**Actions:**
- Provide complete dashboard templates
- Add module testing guide
- Add troubleshooting for each module

### 12. Add Estimated Times

**Add to:**
- Deployment instructions (30-45 minutes)
- Test suite execution (5-10 minutes)
- Upgrade procedures (15-30 minutes per phase)

---

## Phase 4: Nice-to-Have Enhancements

### 13. Create Quick Reference Cards

**Files:**
- `docs/quick-reference/deployment.md`
- `docs/quick-reference/security.md`
- `docs/quick-reference/testing.md`

**Format:** 1-page cheat sheets for common operations

### 14. Add Screenshots/Recordings

**Locations:**
- Grafana dashboard import
- Alert configuration
- CHOM UI overview

### 15. Improve Code Examples

**Action:**
- Ensure all examples are complete and tested
- Add expected output for all commands
- Include error examples

### 16. Create ADRs (Architecture Decision Records)

**File:** `docs/adr/`
**Content:**
- Why Loki over Elasticsearch
- Why no Docker/K8s requirement
- Module system design decisions

---

## Execution Checklist

### Immediate Actions (This Session)

- [ ] Delete module-loader.sh.bak
- [ ] Delete full-test-results.txt
- [ ] Delete global.yaml.example
- [ ] Create chom/README.md
- [ ] Fix version inconsistencies
- [ ] Add prerequisites to root README
- [ ] Add deployment-wizard.sh to root README
- [ ] Create empty directory READMEs

### High Priority (Next Session)

- [ ] Consolidate security documentation
- [ ] Reduce CONTRIBUTING.md redundancy
- [ ] Create glossary
- [ ] Improve QUICK_START.md
- [ ] Archive legacy scripts

### Medium Priority (Future)

- [ ] Create troubleshooting index
- [ ] Add architecture diagrams
- [ ] Improve IMPLEMENTATION_GUIDE.md
- [ ] Add estimated times

---

## Risk Assessment

**Low Risk:**
- File deletions (backed up in git)
- Documentation improvements
- Adding missing docs

**Medium Risk:**
- Moving/archiving scripts (users may reference them)
- Restructuring security docs (may break bookmarks)

**Mitigation:**
- Keep redirects for moved docs
- Add deprecation notices before removing
- Announce changes in CHANGELOG

---

## Success Metrics

**Before:**
- Documentation score: 8.1/10
- Files: Backup files, test artifacts tracked
- User confusion: Version inconsistencies, redundant docs

**After:**
- Documentation score: 9.0+/10
- Files: Clean, no unnecessary artifacts
- User experience: Clear, consistent, beginner-friendly

---

## Timeline

**Session 1 (Now):** Critical fixes (2 hours)
- File cleanup
- Create CHOM README
- Fix versions
- Add prerequisites

**Session 2 (Next week):** Documentation consolidation (4 hours)
- Security doc consolidation
- CONTRIBUTING cleanup
- Glossary creation

**Session 3 (Future):** Enhancements (6+ hours)
- Troubleshooting index
- Architecture diagrams
- Quick reference cards

---

## Questions for User

1. Should we keep migration scripts (phase3-*, migrate-*) or archive them now?
2. Preferred format for architecture diagrams (Mermaid, PlantUML, images)?
3. Should CHOM README be comprehensive or minimal with links?
4. Target audience for glossary (absolute beginners or intermediate users)?

---

**Status:** Ready for execution
**Generated:** December 28, 2025
**Last Updated:** December 28, 2025
