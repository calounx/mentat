# CHOM Model Testing Suite

Comprehensive test suite for CHOM database models, relationships, and data integrity.

## Quick Start

```bash
# Run all model tests
php artisan test tests/Unit/Models/

# Run specific test file
php artisan test tests/Unit/Models/UserModelTest.php

# Run with coverage
php artisan test tests/Unit/Models/ --coverage

# Run specific test method
php artisan test --filter=it_encrypts_ssh_keys
```

## Test Files

### Unit Tests (7 files, 132 tests)

| File | Tests | Focus |
|------|-------|-------|
| `UserModelTest.php` | 24 | User attributes, auth, 2FA, roles |
| `OrganizationModelTest.php` | 12 | Organizations, billing, subscriptions |
| `TenantModelTest.php` | 13 | Multi-tenancy, tier limits, caching |
| `SiteModelTest.php` | 16 | Sites, SSL, soft deletes, scopes |
| `VpsServerModelTest.php` | 14 | Infrastructure, encryption, health |
| `ModelRelationshipsTest.php` | 18 | All relationships, eager loading |
| `DataIntegrityTest.php` | 26 | Constraints, transactions, integrity |

### Documentation (3 files)

| File | Purpose |
|------|---------|
| `MODEL_TEST_REPORT.md` | Comprehensive test results and findings |
| `DATABASE_SCHEMA.md` | Complete schema documentation with ER diagrams |
| `README.md` | This file - quick reference |

## Test Results

**Latest Run:** 2026-01-02

- **Total Tests:** 132
- **Passed:** 110 (83.3%)
- **Failed:** 22 (16.7%)
- **Assertions:** 263+
- **Duration:** ~6-7 seconds

## Coverage by Model

| Model | Coverage | Status |
|-------|----------|--------|
| User | ✓ Complete | All tests passing |
| Organization | ✓ Comprehensive | Minor factory issues |
| Tenant | ✓ Comprehensive | Tier limit conflicts |
| Site | ✓ Comprehensive | Soft delete tests |
| VpsServer | ✓ Comprehensive | Enum constraint issues |
| SiteBackup | ○ Partial | Covered in relationships |
| VpsAllocation | ○ Partial | Covered in relationships |
| Subscription | ○ Partial | Covered in relationships |
| Invoice | ○ Partial | Covered in relationships |
| Operation | ○ Partial | Covered in relationships |
| UsageRecord | ○ Partial | Covered in relationships |
| AuditLog | ○ Partial | Covered in relationships |
| TierLimit | ○ Partial | Covered in relationships |

## What's Tested

### 1. Model Attributes
- Fillable attributes validation
- Hidden fields security
- Type casting (boolean, datetime, JSON, encrypted)
- Default values
- Mass assignment protection

### 2. Relationships
- BelongsTo (inverse 1-to-1)
- HasMany (1-to-many)
- HasOne (1-to-1)
- HasManyThrough (indirect relationships)
- Bidirectional integrity
- Eager loading optimization

### 3. Data Integrity
- Unique constraints
- Foreign key constraints
- Cascade behavior
- Soft deletes
- Transactions
- UUID generation

### 4. Business Logic
- Role checking (User)
- Tier limits (Tenant)
- SSL validation (Site)
- Resource allocation (VPS)
- Caching mechanisms

### 5. Security Features
- Password hashing
- 2FA encryption
- SSH key encryption
- Hidden field protection
- Audit log hash chain

### 6. Performance
- N+1 query prevention
- Cached aggregates
- Query scopes
- Index usage

## Key Findings

### ✓ Working Correctly

1. **Encryption:**
   - 2FA secrets encrypted at rest (AES-256-CBC)
   - SSH keys encrypted at rest
   - Auto-decryption on retrieval

2. **Relationships:**
   - Bidirectional relationships verified
   - Eager loading prevents N+1 queries
   - HasManyThrough working correctly

3. **Security:**
   - Hidden fields excluded from JSON
   - Password auto-hashing
   - Tenant isolation via global scopes

4. **Caching:**
   - Tenant statistics cached (5-min TTL)
   - Tier limits cached (1-hour TTL)
   - Auto-invalidation working

### ⚠ Issues Found

1. **Factory Constraints:**
   - TierLimit factory creates duplicate tiers
   - VPS factory uses invalid enum values
   - Fix: Use factory states for enum values

2. **Foreign Key Behavior:**
   - Tests expect RESTRICT, schema may use CASCADE
   - Recommendation: Review migration constraints

3. **Missing Unit Tests:**
   - Invoice model needs dedicated tests
   - Subscription model needs dedicated tests
   - AuditLog hash chain needs verification tests

## Test Categories

### Attributes & Casting (✓ PASS)
```php
✓ Fillable attributes
✓ Hidden attributes
✓ Type casting (datetime, boolean, JSON)
✓ Encrypted fields
✓ Password hashing
```

### Relationships (83% PASS)
```php
✓ Organization → Users
✓ Tenant → Sites
✓ Site → Backups
✓ VPS → Sites
✓ Tenant → VPS (through allocations)
✓ Eager loading optimization
⚠ Some factory setup issues
```

### Data Integrity (73% PASS)
```php
✓ Unique constraints
✓ Foreign key constraints
✓ Soft deletes
✓ Transactions
⚠ Cascade behavior verification
```

### Business Logic (✓ PASS)
```php
✓ User role checking
✓ Tenant tier limits
✓ Site SSL validation
✓ VPS resource calculations
✓ Cached statistics
```

## Models Overview

### User
- **Purpose:** Authentication and authorization
- **Key Features:** 2FA, role-based access, password confirmation
- **Security:** Encrypted 2FA secrets, hidden passwords
- **Tests:** 24 comprehensive tests

### Organization
- **Purpose:** Billing and organizational root
- **Key Features:** Stripe integration, default tenant
- **Relationships:** Users, tenants, subscriptions, invoices
- **Tests:** 12 tests covering all relationships

### Tenant
- **Purpose:** Multi-tenant application isolation
- **Key Features:** Tier limits, cached statistics, global scopes
- **Relationships:** Sites, VPS allocations, operations
- **Tests:** 13 tests including caching

### Site
- **Purpose:** Hosted applications
- **Key Features:** Soft deletes, SSL tracking, tenant isolation
- **Security:** Hidden database credentials
- **Tests:** 16 tests including soft delete behavior

### VpsServer
- **Purpose:** Infrastructure servers
- **Key Features:** Encrypted SSH keys, health monitoring
- **Security:** Keys encrypted at rest, hidden from JSON
- **Tests:** 14 tests including encryption

## Database Schema

**Total Models:** 13
**Total Tables:** 15 (including Laravel tables)
**Total Indexes:** 40+
**Encrypted Fields:** 4
**Global Scopes:** 4

See `DATABASE_SCHEMA.md` for complete schema documentation.

## Next Steps

### High Priority
1. Fix factory enum constraints
2. Add Invoice unit tests
3. Add Subscription unit tests
4. Verify foreign key cascade behavior

### Medium Priority
1. Add AuditLog hash chain tests
2. Implement performance benchmarks
3. Add query EXPLAIN analysis
4. Create integration test suite

### Low Priority
1. Increase test coverage to 95%
2. Add mutation testing
3. Create database migration tests
4. Add schema drift detection

## Documentation

- **Test Report:** `MODEL_TEST_REPORT.md` - Detailed test results and analysis
- **Schema Docs:** `DATABASE_SCHEMA.md` - Complete database schema with ER diagrams
- **This File:** `README.md` - Quick reference guide

## Contributing

When adding new tests:

1. Follow existing naming conventions: `it_does_something`
2. Use descriptive test names
3. Test one thing per test method
4. Include both positive and negative cases
5. Document complex test scenarios

## Support

For questions or issues:
1. Review the test report
2. Check the schema documentation
3. Examine existing test examples
4. Run tests with `--verbose` flag

---

**Generated:** 2026-01-02
**Framework:** Laravel 11 + PHPUnit 11
**Test Suite Version:** 1.0
