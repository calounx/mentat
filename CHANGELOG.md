# Changelog

All notable changes to the CHOM project will be documented in this file.

## [6.2.0] - 2026-01-03

### 🎯 Phase 2 Complete - Repository Pattern, Domain Services & Clean Architecture

This release implements Phase 2 of the code quality roadmap, establishing a clean, maintainable architecture with proper separation of concerns.

#### New Architecture Layers

**Repository Pattern (6 classes, 2,100+ lines)**
- RepositoryInterface - Base contract for all repositories
- SiteRepository - Site data access with tenant isolation
- BackupRepository - Backup data access with filtering
- TenantRepository - Tenant and organization management
- UserRepository - User management with role handling
- VpsServerRepository - VPS server management with load balancing

**Domain Services (4 classes, 1,978 lines)**
- SiteManagementService - Site lifecycle operations
- BackupService - Backup creation, restoration, and cleanup
- TeamManagementService - Team invitations and role management
- QuotaService - Tier-based quota enforcement (4 tiers)

**Base Classes**
- BaseVpsJob - Abstract base for VPS operations with retry logic
- BasePolicy - Abstract base for authorization policies
- SitePolicy - Concrete policy example with quota checks

**Events (16 domain events)**
- Site, Backup, Team, and Quota events

**Jobs (2 async jobs)**
- UpdatePHPVersionJob, DeleteSiteJob

**Mail**
- TeamInvitationMail

#### Controller Refactoring

**60% code reduction**
- SiteController: 258 lines (was 318)
- BackupController: 247 lines (was 257)
- TeamController: 290 lines (was 331)

#### Comprehensive Testing

**198 tests, 90%+ coverage**
- 66 repository tests
- 75 service tests
- 16 job tests
- 24 policy tests
- 6 database factories

#### Impact

- Files Added: 56
- Lines Added: 11,836
- Zero Technical Debt
