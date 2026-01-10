# CHOM Onboarding Workflow - Requirements Confirmed

**Date**: 2026-01-10
**Status**: ✅ 17/17 Questions Answered - Complete and Ready for Implementation

---

## ✅ Confirmed Requirements

### Category 1: Signup Form ✅ COMPLETE

**Q1: Should we collect username?**
- **Answer**: YES
- **Impact**: Add `username` field to users table (unique, required)

**Q2: Split name into first_name/last_name?**
- **Answer**: YES
- **Impact**: Migrate `name` field to `first_name` + `last_name`, update all references

**Q3: What is a "fictive organization"?**
- **Answer**: Default unique organization created in background
- **Details**:
  - Invisible to users (internal use only)
  - Auto-generated when user signs up without real organization
  - Each fictive org is unique per user
- **Impact**: Add `is_fictive` boolean flag, auto-generation logic

**Q4: Can users join existing organizations during signup?**
- **Answer**: NO - Only via organization invitation
- **Impact**: No "join existing org" UI needed in signup flow

---

### Category 2: Approval Workflow ✅ COMPLETE

**Q5: Approve at user level, org level, or both?**
- **Answer**: BOTH
- **Impact**:
  - Add `approval_status` to users table
  - Add `is_approved` to organizations table
  - Admin must approve both user AND organization

**Q6: What happens to users before approval?**
- **Answer**: LOCKED (cannot login)
- **Impact**: Block authentication for unapproved users, show "pending approval" message

**Q7: Require email verification before admin review?**
- **Answer**: YES
- **Impact**: Enforce email verification, block approval until verified

**Q8: What additional info should admins see?**
- **Answer**: ALL INPUT FIELDS
- **Impact**: Admin panel shows username, first_name, last_name, email, organization details

**Q9: Should there be approval notes/rejection reasons?**
- **Answer**: YES, and rejected email kept for "spam" process
- **Impact**:
  - Add `approval_notes` and `rejection_reason` fields
  - Store rejected user emails in spam tracking system
  - Admin can add notes during approval/rejection

---

### Category 4: Notifications ✅ COMPLETE

**Q13: What notifications to admins?**
- **Answer**: EMAIL (to be defined)
- **Impact**: Send email to admin team when new user registers

**Q14: What notifications to users?**
- **Answer**: WHEN APPROVED/REJECTED
- **Impact**:
  - Email when user+org approved
  - Email with reason when rejected

---

### Category 5: User Experience ✅ COMPLETE

**Q15: Multi-step onboarding wizard?**
- **Answer**: WHEN NEEDED
- **Impact**: Implement wizard if signup form becomes too complex

**Q16: Can users edit pending applications?**
- **Answer**: NO
- **Impact**: No edit functionality for pending users

**Q17: What happens on rejection?**
- **Answer**: NOTIFICATION SENT TO USER AND EMAIL KEPT FOR SPAM PROCESS
- **Impact**:
  - Send rejection email with reason
  - Store email in spam prevention database
  - Prevent re-registration with same email

---

## ✅ Category 3: Plan Selection - COMPLETE

**Q10: When exactly should plan selection happen?**
- **Answer**: AFTER admin approval, user forced to select plan before dashboard access
- **Impact**:
  - User receives approval email with login link
  - On first login after approval, redirect to /plan-selection page
  - User CANNOT access dashboard or create sites until plan selected
  - Add `requires_plan_selection` flag to tenants (defaults true until plan chosen)

**Q11: Who selects the plan (user vs. admin)?**
- **Answer**: USER selects (self-service)
- **Impact**:
  - Build plan selection UI showing tier comparison (Starter, Pro, Enterprise)
  - User clicks "Select Plan" button for chosen tier
  - Plan immediately assigned to tenant
  - Admin can view plan selection history in audit log

**Q12: Can users upgrade/downgrade plans later?**
- **Answer**: YES, with admin approval required
- **Impact**:
  - Add "Request Plan Change" feature in user dashboard
  - User selects new plan → creates plan_change_request record
  - Admin receives notification → approves/rejects request
  - New table: `plan_change_requests` (status: pending/approved/rejected)
  - Email notifications on approval/rejection

---

## 📋 Implementation Summary (Based on Confirmed Answers)

### Database Schema Changes

```sql
-- Users table
ALTER TABLE users
  ADD COLUMN username VARCHAR(50) UNIQUE NOT NULL,
  ADD COLUMN first_name VARCHAR(100) NOT NULL,
  ADD COLUMN last_name VARCHAR(100) NOT NULL,
  DROP COLUMN name,
  ADD COLUMN approval_status ENUM('pending', 'approved', 'rejected') DEFAULT 'pending',
  ADD COLUMN approved_at TIMESTAMP NULL,
  ADD COLUMN approved_by UUID NULL,
  ADD COLUMN rejection_reason TEXT NULL,
  ADD COLUMN rejected_at TIMESTAMP NULL,
  ADD COLUMN rejected_by UUID NULL;

-- Organizations table
ALTER TABLE organizations
  ADD COLUMN is_fictive BOOLEAN DEFAULT FALSE,
  ADD COLUMN is_approved BOOLEAN DEFAULT FALSE,
  ADD COLUMN approved_at TIMESTAMP NULL,
  ADD COLUMN approved_by UUID NULL,
  ADD COLUMN rejection_reason TEXT NULL,
  ADD COLUMN approval_notes TEXT NULL;

-- Tenants table
ALTER TABLE tenants
  ADD COLUMN plan_selected_at TIMESTAMP NULL,
  ADD COLUMN requires_plan_selection BOOLEAN DEFAULT TRUE,
  MODIFY tier ENUM('starter', 'pro', 'enterprise') NULL;  -- NULL until user selects

-- Spam tracking table (NEW)
CREATE TABLE rejected_emails (
  id UUID PRIMARY KEY,
  email VARCHAR(255) NOT NULL,
  rejection_reason TEXT,
  rejected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  rejected_by UUID,
  attempts INT DEFAULT 1,
  INDEX idx_email (email)
);

-- Plan change requests table (NEW)
CREATE TABLE plan_change_requests (
  id UUID PRIMARY KEY,
  tenant_id UUID NOT NULL,
  user_id UUID NOT NULL,
  current_tier ENUM('starter', 'pro', 'enterprise') NOT NULL,
  requested_tier ENUM('starter', 'pro', 'enterprise') NOT NULL,
  reason TEXT NULL,
  status ENUM('pending', 'approved', 'rejected') DEFAULT 'pending',
  requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  reviewed_at TIMESTAMP NULL,
  reviewed_by UUID NULL,
  reviewer_notes TEXT NULL,
  FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_tenant_status (tenant_id, status)
);
```

### New Onboarding Flow (Complete)

```
┌─────────────────────────────────────────────────────────────────┐
│ STEP 1: USER SIGNUP                                             │
├─────────────────────────────────────────────────────────────────┤
│ Form Fields:                                                    │
│   • username (NEW - unique, required)                           │
│   • first_name (NEW - required)                                 │
│   • last_name (NEW - required)                                  │
│   • email (required, unique)                                    │
│   • password + confirmation                                     │
│   • organization_name (optional)                                │
│   • [ ] "I don't have an organization" checkbox                │
│                                                                 │
│ What Happens:                                                   │
│   ✓ User created (approval_status: 'pending')                  │
│   ✓ Organization created:                                       │
│       - If org_name provided: real org (is_fictive=false)      │
│       - If checkbox: fictive org (is_fictive=true, invisible)  │
│   ✓ Organization status: is_approved=false                     │
│   ✓ Tenant created (is_approved=false)                         │
│   ✓ Email verification sent (REQUIRED)                         │
│   ✓ Admin notification sent                                     │
│   ✗ User CANNOT login yet                                       │
│   ✗ NO plan assigned yet (TBD)                                  │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 2: EMAIL VERIFICATION (REQUIRED)                           │
├─────────────────────────────────────────────────────────────────┤
│ User Receives:                                                  │
│   ✉️  "Verify Your Email" message                              │
│   • Click verification link                                     │
│                                                                 │
│ After Verification:                                             │
│   ✓ email_verified_at set                                      │
│   • Status: Awaiting admin approval                            │
│   • User still CANNOT login                                     │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 3: ADMIN APPROVAL (User + Organization)                    │
├─────────────────────────────────────────────────────────────────┤
│ Admin Receives:                                                 │
│   ✉️  Email notification "New user pending approval"           │
│                                                                 │
│ Admin Reviews (via /admin/pending-approvals):                  │
│   • username, first_name, last_name, email                     │
│   • email_verified_at (must be verified)                       │
│   • organization_name, is_fictive flag                         │
│   • signup timestamp                                            │
│                                                                 │
│ Admin Actions:                                                  │
│   APPROVE BOTH:                                                 │
│     ✓ user.approval_status = 'approved'                        │
│     ✓ organization.is_approved = true                          │
│     ✓ tenant.is_approved = true                                │
│     ✓ Set approved_at, approved_by                             │
│     ✓ Can add approval_notes                                   │
│     ✓ Send approval email to user                              │
│                                                                 │
│   REJECT:                                                       │
│     ✓ user.approval_status = 'rejected'                        │
│     ✓ organization.is_approved = false                         │
│     ✓ Set rejection_reason (required)                          │
│     ✓ Store email in rejected_emails table (spam tracking)     │
│     ✓ Send rejection email with reason                         │
│     ✓ Block future signups with same email                     │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 4: PLAN SELECTION (Forced After Approval)                 │
├─────────────────────────────────────────────────────────────────┤
│ User Logs In:                                                   │
│   • Redirected to /plan-selection (FORCED)                     │
│   • Cannot access dashboard without selecting plan             │
│                                                                 │
│ User Sees:                                                      │
│   • Plan comparison cards (Starter, Pro, Enterprise)           │
│   • Features, limits, pricing for each tier                    │
│   • "Select Plan" button for each tier                         │
│                                                                 │
│ User Chooses Plan:                                              │
│   ✓ tenant.tier = selected_tier                                │
│   ✓ tenant.plan_selected_at = now()                           │
│   ✓ tenant.requires_plan_selection = false                    │
│   ✓ Redirect to /dashboard (full access granted)              │
│                                                                 │
│ Plan Changes:                                                   │
│   • User can request plan change later                         │
│   • Admin must approve change requests                         │
│   • Email notifications on approval/rejection                  │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 5: USER CAN CREATE SITES                                   │
├─────────────────────────────────────────────────────────────────┤
│ Checks Performed:                                               │
│   ✓ user.approval_status == 'approved'                         │
│   ✓ user.email_verified_at != null                             │
│   ✓ organization.is_approved == true                           │
│   ✓ tenant.is_approved == true                                 │
│   ✓ tenant.tier != null (plan assigned - TBD how)              │
│   ✓ tenant.status == 'active'                                  │
│   ✓ user.canManageSites() (role check)                         │
│   ✓ sites_count < tier_limit.max_sites                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Workflow Comparison

| Step | Current | Confirmed New | TBD |
|------|---------|---------------|-----|
| **Signup fields** | name, email, password, org_name | username, first_name, last_name, email, password, org_name (optional) | ✅ |
| **Fictive org** | Not supported | Auto-created if user has no org | ✅ |
| **Email verification** | Optional | REQUIRED before approval | ✅ |
| **User can login before approval** | YES (limited access) | NO (locked) | ✅ |
| **Approval scope** | Tenant only | User + Organization + Tenant | ✅ |
| **Admin notification** | None | Email on new signup | ✅ |
| **Rejection handling** | Not supported | Email to user, store in spam DB | ✅ |
| **Plan assignment** | Auto 'starter' | User selects after approval | ✅ |
| **Plan selection timing** | At signup (auto) | After approval, forced before dashboard | ✅ |
| **Plan changes** | Not supported | User requests, admin approves | ✅ |

---

## 📊 Implementation Phases

### Phase 1: Database & Models ✅ READY TO IMPLEMENT
- Database migrations (users, organizations, tenants, rejected_emails)
- Update User model (username, first_name, last_name, approval_status)
- Update Organization model (is_fictive, is_approved)
- Spam tracking model (RejectedEmail)

### Phase 2: Signup Flow ✅ READY TO IMPLEMENT
- Update registration form (new fields)
- Fictive organization creation logic
- Email verification enforcement
- Prevent login for unapproved users

### Phase 3: Admin Approval ✅ READY TO IMPLEMENT
- Admin panel for pending approvals
- Dual approval (user + organization)
- Approval notes and rejection reasons
- Admin email notifications

### Phase 4: User Notifications ✅ READY TO IMPLEMENT
- Approval email template
- Rejection email template (with reason)
- Spam tracking integration

### Phase 5: Plan Selection ✅ READY TO IMPLEMENT
- Plan selection page UI (/plan-selection)
- Middleware to enforce plan selection after approval
- Redirect logic on login (if requires_plan_selection=true)
- Plan selection API endpoint
- Plan change request feature
- Admin panel for plan change approvals

### Phase 6: Site Creation Gates ✅ READY TO IMPLEMENT
- Update SitePolicy (check user + org + tenant approval + plan selected)
- Update Tenant model (requires_plan_selection checks)
- Update error messages for unapproved/no-plan states

---

## 🎯 Next Steps - Ready to Implement

### All Requirements Confirmed ✅

All 17 questions have been answered. Implementation can proceed.

### Implementation Order:

1. **Create detailed implementation plan** with file-by-file changes
   - Database migrations (users, organizations, tenants, rejected_emails, plan_change_requests)
   - Model updates (User, Organization, Tenant, RejectedEmail, PlanChangeRequest)
   - Controller updates (AuthController, Admin panels)
   - Policy updates (SitePolicy, UserPolicy, etc.)

2. **Write database migrations** with rollback support
   - Migration: add username, first_name, last_name to users
   - Migration: add approval fields to users and organizations
   - Migration: add plan selection fields to tenants
   - Migration: create rejected_emails table
   - Migration: create plan_change_requests table
   - Data migration: split existing name → first_name/last_name

3. **Update models and business logic**
   - User model: approval workflow methods
   - Organization model: fictive org handling
   - Tenant model: plan selection enforcement
   - New models: RejectedEmail, PlanChangeRequest

4. **Build frontend components**
   - Updated registration form (username, first_name, last_name, org options)
   - Admin approval dashboard (dual approval UI)
   - Plan selection page (tier comparison cards)
   - Plan change request UI

5. **Implement notification system**
   - Admin notification on new signup
   - User approval/rejection emails
   - Plan change request notifications

6. **Write comprehensive test suite**
   - Unit tests for all models
   - Feature tests for signup flow
   - Admin approval workflow tests
   - Plan selection tests

7. **Deploy to staging for testing**
   - Test complete flow end-to-end
   - Verify email delivery
   - Test edge cases (duplicate emails, spam tracking, etc.)

---

## ⏱️ Estimated Implementation Time

**With Plan Selection Answers:**
- Phase 1-4 (confirmed requirements): 40-50 hours
- Phase 5 (plan selection): 10-15 hours (depends on answers)
- Phase 6 (finalization): 5-10 hours
- **Total: 55-75 hours**

**Risk Factors:**
- Data migration for existing users (name → first_name/last_name)
- Spam tracking integration complexity
- Email delivery configuration
- Dual approval UI/UX complexity

---

**Status**: ✅ ALL REQUIREMENTS CONFIRMED - Ready to proceed with full implementation (Phases 1-6).
