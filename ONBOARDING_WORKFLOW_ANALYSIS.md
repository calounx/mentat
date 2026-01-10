# CHOM User Onboarding Workflow - Comprehensive Analysis

**Date**: 2026-01-10
**Purpose**: Analyze current onboarding flow vs. desired requirements
**Status**: Awaiting clarification on 15 critical questions

---

## Executive Summary

After comprehensive analysis of the CHOM codebase, I've mapped the **current onboarding workflow** and compared it against the **desired workflow** you described. There are **significant differences** that require clarification before implementation.

### Current vs. Desired Flow Comparison

| Step | Current Implementation | Desired Workflow | Match? |
|------|----------------------|------------------|--------|
| 1. User signup | ✅ Collects: name, email, password, org name | ✅ Should collect: username, first/last name, email | ⚠️ **Mismatch** |
| 2. Organization creation | ✅ Auto-created during signup | ✅ User provides organization OR fictive one | ⚠️ **Unclear** |
| 3. Approval required | ✅ Tenant needs approval (is_approved=false) | ✅ Organization/user needs CHOM admin approval | ✅ **Match** |
| 4. Plan selection | ❌ Auto-assigned "starter" plan | ✅ Plan chosen AFTER approval | ❌ **Mismatch** |
| 5. Site creation | ✅ Only after tenant approved | ✅ NOT before approval + plan selection | ⚠️ **Partial** |
| 6. Admin notifications | ❌ No automated notifications | ✅ Admins notified when approval needed | ❌ **Missing** |

---

## PART 1: CURRENT WORKFLOW (As Implemented)

### 1.1 User Signup/Registration Flow

**Route**: `POST /register`
**Files**:
- `/routes/web.php` (lines 103-136)
- `/app/Http/Controllers/Api/V1/AuthController.php` (registration)

**Current Signup Form Collects**:
```
1. name (string) - Full name (NOT separated into first/last)
2. email (string, unique)
3. password (string, confirmed, min 8 chars)
4. organization_name (string) - Organization name
```

**⚠️ ISSUE 1**: Current form doesn't collect username or separate first/last names

**What Happens Immediately After Signup**:

```php
DB::transaction(function () {
    // Step 1: Create Organization automatically
    $organization = Organization::create([
        'name' => $validated['organization_name'],
        'slug' => Str::slug($organization_name) . '-' . Str::random(6),
        'billing_email' => $validated['email'],
        'status' => 'active',  // Organization is ACTIVE immediately
    ]);

    // Step 2: Create Default Tenant (UNAPPROVED by default)
    $tenant = Tenant::create([
        'organization_id' => $organization->id,
        'name' => 'Default',
        'slug' => 'default',
        'tier' => 'starter',           // ⚠️ HARDCODED to starter
        'status' => 'active',
        'is_approved' => false,         // ✅ Requires admin approval
        'approved_at' => null,
        'approved_by' => null,
    ]);

    // Step 3: Create User as organization owner
    $user = User::create([
        'name' => $validated['name'],
        'email' => $validated['email'],
        'password' => Hash::make($validated['password']),
        'organization_id' => $organization->id,
        'role' => 'owner',              // Always owner on signup
        'is_super_admin' => false,
    ]);

    // Step 4: Link user to tenant
    $tenant->users()->attach($user->id);

    // Step 5: Auto-login user
    Auth::login($user);

    return redirect()->route('dashboard');
});
```

**⚠️ ISSUE 2**: Plan (tier) is hardcoded to 'starter' - no selection UI
**⚠️ ISSUE 3**: No "fictive" or placeholder organization support
**⚠️ ISSUE 4**: No email verification enforced (despite MustVerifyEmail interface)
**⚠️ ISSUE 5**: No admin notification sent

### 1.2 Admin Approval Process

**Current Approval Mechanism**:

**Admin Interface**: `/admin/tenants` (Super Admin only)
**File**: `/app/Livewire/Admin/TenantManagement.php`

**What Admins See**:
- List of all tenants
- Filter: "Pending Approval" shows tenants where `is_approved = false`
- Actions available:
  - ✅ Approve Tenant (sets is_approved=true, approved_at=now(), approved_by=admin_id)
  - ❌ Revoke Approval (sets is_approved=false, clears approval fields)

**Approval Action**:
```php
public function approveTenant(string $tenantId): void {
    $tenant = Tenant::findOrFail($tenantId);
    $tenant->approve(auth()->user());  // Records WHO approved and WHEN
}
```

**⚠️ ISSUE 6**: Approval is at TENANT level, not USER or ORGANIZATION level
**⚠️ ISSUE 7**: No automated email/notification to admins when new tenant created
**⚠️ ISSUE 8**: No notification to user when approved/rejected

### 1.3 Plan Selection (Current)

**Current State**:
- ❌ **NO user-facing plan selection UI**
- ✅ All new signups get "starter" tier automatically
- ✅ Tier limits enforced (starter = 5 sites max)
- ✅ Upgrade possible later via admin panel or Stripe integration

**Tier Limits (Current)**:

| Tier | Max Sites | Max Storage | Backup Retention | Price/month |
|------|-----------|-------------|------------------|-------------|
| Starter | 5 | 10 GB | 7 days | $29 |
| Pro | 25 | 100 GB | 30 days | $79 |
| Enterprise | Unlimited | Unlimited | 90 days | Custom |

**⚠️ ISSUE 9**: Your requirement states plan should be chosen AFTER approval, but current flow auto-assigns on signup

### 1.4 Site Creation (Current)

**Prerequisites Enforced**:

```php
// File: /app/Livewire/Sites/SiteCreate.php

public function create(): void {
    // Check 1: User authorization (policy)
    $this->authorize('create', Site::class);  // Requires owner/admin/member role

    $tenant = auth()->user()->currentTenant();

    // Check 2: Tenant exists
    if (!$tenant) {
        return $this->error('No tenant configured.');
    }

    // Check 3: Tenant is APPROVED ✅ CRITICAL GATE
    if (!$tenant->isApproved()) {
        return $this->error('Your account is pending approval.
                             Please wait for administrator approval before creating sites.');
    }

    // Check 4: Tenant is ACTIVE
    if (!$tenant->isActive()) {
        return $this->error('Your account is currently suspended.');
    }

    // Check 5: Under site quota
    if (!$tenant->canCreateSite()) {
        $currentSites = $tenant->sites()->count();
        $maxSites = $tenant->getMaxSites();
        return $this->error("You have reached your plan's site limit
                             ({$currentSites}/{$maxSites}). Please upgrade to create more sites.");
    }

    // Check 6: Domain unique globally
    if (Site::where('domain', $this->domain)->exists()) {
        return $this->error('This domain is already configured.');
    }

    // Check 7: Available VPS exists
    $vps = $this->findAvailableVps($tenant);
    if (!$vps) {
        return $this->error('No available server found. Please contact support.');
    }

    // All checks passed - create site
    Site::create([...]);
}
```

**✅ GOOD**: Site creation is properly gated behind tenant approval
**⚠️ ISSUE 10**: No distinction between "pending approval" and "plan not selected" states

---

## PART 2: DESIRED WORKFLOW (Your Requirements)

Based on your description:

> "onboarding user (username, first and last name, email followed by organization or fictive one,
> once those are approved by chom administration team, a plan is chosen, and then finally
> a website is created NOT before)"

### 2.1 Desired Signup Flow

**Step 1: User Signup**
```
Form should collect:
├─ username (?)
├─ first_name (NEW)
├─ last_name (NEW)
├─ email
├─ password
└─ organization
   ├─ Option A: Select existing organization (?)
   ├─ Option B: Create new organization
   └─ Option C: Create "fictive" organization (?)
```

**Step 2: Create User + Organization**
```
Actions:
├─ Create User record
│  ├─ username
│  ├─ first_name
│  ├─ last_name
│  ├─ email
│  └─ status: 'pending_approval' (?)
│
└─ Create or Link Organization
   ├─ If new: Create organization with status: 'pending_approval' (?)
   ├─ If fictive: Create placeholder organization (?)
   └─ If existing: Link user to existing org (?)
```

**Step 3: Notify CHOM Admins**
```
Notification to admin team:
├─ Email notification
├─ Admin dashboard notification badge
├─ Contains: User info, organization info
└─ Action required: Approve or Reject
```

### 2.2 Desired Approval Flow

**CHOM Admin Review**:
```
Admin reviews:
├─ User information (username, name, email)
├─ Organization request (new or fictive)
├─ Account legitimacy
└─ Decision:
   ├─ APPROVE → Trigger plan selection
   └─ REJECT → Notify user, prevent access
```

**After Approval**:
```
Once approved:
├─ Notify user via email
├─ User can now login
├─ User MUST select a plan
└─ THEN user can create sites
```

### 2.3 Desired Plan Selection Flow

**When**: AFTER admin approval, BEFORE site creation

**User Journey**:
```
1. User logs in (after approval)
2. System detects: No plan selected
3. Redirect to /plan-selection page
4. User chooses: Starter, Pro, or Enterprise
5. System assigns plan to tenant
6. User can now access full dashboard and create sites
```

**⚠️ ISSUE 11**: Current system has no "must select plan" enforcement

### 2.4 Desired Site Creation Flow

**Prerequisites (Desired)**:
```
Can create site only if:
✅ User account approved by admin
✅ Organization approved by admin
✅ Plan selected by user
✅ Under plan quota
✅ Tenant active
```

**Current Prerequisites**:
```
Can create site only if:
✅ Tenant approved by admin (combines user + org approval)
✅ Tenant active
✅ Under plan quota
❌ Plan auto-assigned (not user-selected)
```

---

## PART 3: CRITICAL QUESTIONS FOR CLARIFICATION

### Category A: Signup Form Fields

**Q1**: Should we collect **username** as a separate field from email?
- Current: Only collects `name` (full name) and `email`
- Desired: Appears to want `username`, `first_name`, `last_name`
- **Question**: Is username a login credential, or is email the only login?
- **Recommendation**: Email-only login (industry standard). Username optional for display purposes.

**Q2**: Should we split `name` into `first_name` and `last_name`?
- Current: Single `name` field (VARCHAR 255)
- Desired: Separate first/last name fields
- **Impact**: Database migration required, affects ~10 files
- **Recommendation**: Yes, split for better personalization and sorting

### Category B: Organization Handling

**Q3**: What is a "fictive" organization?
- **Possible Interpretation A**: Placeholder organization for solo users (e.g., "John's Personal Workspace")
- **Possible Interpretation B**: Test/demo organization for trials
- **Possible Interpretation C**: Temporary organization pending real organization approval
- **Question**: Please clarify the exact purpose and behavior of fictive organizations

**Q4**: Can users select an **existing organization** during signup?
- Current: Always creates new organization
- Scenario: User wants to join an existing organization (e.g., colleague's company)
- **Question**: Should there be an "Join Existing Organization" option during signup?
- **Recommendation**: Add invite system - users invited by org owners bypass organization creation

**Q5**: Can one organization have multiple users signup independently?
- Current: First user creates org as "owner", others must be invited via /team
- Desired: Unclear if multiple signups can claim same organization
- **Question**: Should signup allow "I work for [Existing Organization]" with admin approval?

### Category C: Approval Workflow

**Q6**: Is approval at the **User level**, **Organization level**, or **both**?
- Current: Approval is at TENANT level (tenant = organization's environment)
- Possible Interpretation: Approve USER first, then approve their ORGANIZATION separately
- **Question**: Do you want two separate approval steps (user approval + org approval)?
- **Current Recommendation**: Keep single tenant approval (combines both)

**Q7**: What should happen to user immediately after signup (before approval)?
- **Option A**: Can login but sees "Pending Approval" dashboard with limited access
- **Option B**: Cannot login until approved (account locked)
- **Option C**: Can login, access profile/settings, but cannot create sites
- **Current Implementation**: Option C
- **Question**: Which option matches your requirements?

**Q8**: Who are the "CHOM administration team"?
- Current: Super Admins (users with `is_super_admin = true`)
- **Question**: Is this correct, or should there be a separate "approver" role?
- **Possible Extension**: Create dedicated "CHOM Admin" role distinct from "Super Admin"

**Q9**: What information should admins see when approving?
- Current: Organization name, tenant name, tier, created date
- Desired: User details? Business justification? Use case?
- **Question**: Should signup collect additional info for admin review (e.g., "Reason for signup", "Company website")?

**Q10**: Should there be approval **reasons/notes**?
- Example: Admin approves with note "Approved for enterprise trial" or rejects with "Suspected spam"
- Current: No rejection reason tracking
- **Question**: Add approval notes field? Add rejection reason field?

### Category D: Plan Selection

**Q11**: WHEN exactly should plan selection happen?
- **Option A**: During signup (before approval) - admin sees requested plan
- **Option B**: After admin approval (forced before dashboard access)
- **Option C**: After admin approval (optional, defaults to starter)
- Your description suggests: **Option B** ("plan is chosen" after "once those are approved")
- **Question**: Confirm plan selection timing

**Q12**: WHO selects the plan?
- **Option A**: User selects plan during/after signup
- **Option B**: Admin assigns plan during approval
- **Option C**: User requests plan, admin approves specific plan
- Your description suggests: **Option A or C**
- **Question**: User choice or admin assignment?

**Q13**: Can users upgrade/downgrade plans later?
- Current: Yes, via Stripe subscription management (but not user-facing)
- **Question**: Should there be self-service plan upgrade UI, or admin-only?

### Category E: Notifications

**Q14**: What notifications should be sent?

**To Admins**:
- [ ] Email when new user signs up (pending approval)
- [ ] Email when new organization created (pending approval)
- [ ] Dashboard badge showing pending approval count
- [ ] Daily digest of pending approvals
- **Question**: Which of these do you want?

**To Users**:
- [ ] Welcome email after signup (before approval)
- [ ] "Account approved" email with next steps
- [ ] "Account rejected" email with reason
- [ ] "Plan selection required" email
- [ ] Email verification required before anything else
- **Question**: Which of these do you want?

**Q15**: Should email verification be **required** before approval?
- Current: User model implements `MustVerifyEmail` but it's not enforced
- **Question**: Should users verify email BEFORE admin reviews account?
- **Recommendation**: Yes - prevents spam signups, validates email legitimacy

### Category F: Site Creation Flow

**Q16**: Are there any other prerequisites for site creation beyond approval + plan?
- Examples: Payment method on file, completed profile, agreed to ToS
- **Question**: Any additional requirements?

**Q17**: Should there be a **multi-step onboarding wizard**?
- Step 1: Signup → Step 2: Email Verify → Step 3: Await Approval →
- Step 4: Select Plan → Step 5: Create First Site
- **Question**: Would a guided wizard be helpful?

---

## PART 4: PROPOSED CHANGES (Based on Requirements)

### Assuming answers to questions above, here are proposed changes:

### 4.1 Database Schema Changes

**Users Table Additions**:
```sql
ALTER TABLE users
  ADD COLUMN username VARCHAR(50) UNIQUE NULL AFTER id,
  ADD COLUMN first_name VARCHAR(100) NOT NULL,
  ADD COLUMN last_name VARCHAR(100) NOT NULL,
  MODIFY name VARCHAR(255) NULL;  -- Make nullable, keep for backwards compat
```

**Organizations Table Additions**:
```sql
ALTER TABLE organizations
  ADD COLUMN is_fictive BOOLEAN DEFAULT FALSE,
  ADD COLUMN is_approved BOOLEAN DEFAULT FALSE,
  ADD COLUMN approved_at TIMESTAMP NULL,
  ADD COLUMN approved_by UUID NULL,
  ADD CONSTRAINT fk_org_approved_by FOREIGN KEY (approved_by) REFERENCES users(id);
```

**Users Table Additions (Approval)**:
```sql
ALTER TABLE users
  ADD COLUMN approval_status ENUM('pending', 'approved', 'rejected') DEFAULT 'pending',
  ADD COLUMN approved_at TIMESTAMP NULL,
  ADD COLUMN approved_by UUID NULL,
  ADD COLUMN rejection_reason TEXT NULL;
```

**Tenants Table Additions**:
```sql
ALTER TABLE tenants
  ADD COLUMN plan_selected_at TIMESTAMP NULL,
  ADD COLUMN requires_plan_selection BOOLEAN DEFAULT TRUE;
```

### 4.2 New Middleware

**RequiresPlanSelection** - Force plan selection before dashboard access
```php
// Redirect to /plan-selection if:
// - User is approved
// - Tenant is approved
// - No plan selected (tenant.plan_selected_at IS NULL)
```

**RequiresApproval** - Block access if not approved
```php
// Show "Pending Approval" page if:
// - User.approval_status = 'pending'
// - Organization.is_approved = false
// - Tenant.is_approved = false
```

### 4.3 New Routes/Pages

```php
// Signup flow
GET  /signup                      // New signup form with first/last name
POST /signup                      // Create user + org, send to pending

// Approval flow
GET  /pending-approval            // Shown to user awaiting approval
GET  /admin/approvals             // Admin queue for pending users/orgs
POST /admin/users/{id}/approve    // Approve user
POST /admin/users/{id}/reject     // Reject user with reason
POST /admin/orgs/{id}/approve     // Approve organization

// Plan selection
GET  /plan-selection              // Plan selection UI (required after approval)
POST /plan-selection              // Submit plan choice

// Email verification
GET  /email/verify/{token}        // Verify email
POST /email/resend                // Resend verification email
```

### 4.4 New Notifications

**Admin Notifications** (New Approval Needed):
```php
Notification::route('mail', config('chom.admin_email'))
    ->notify(new NewUserPendingApproval($user, $organization));
```

**User Notifications**:
```php
// After signup
$user->notify(new WelcomeEmail());
$user->notify(new VerifyEmail());

// After admin approval
$user->notify(new AccountApproved());

// After admin rejection
$user->notify(new AccountRejected($reason));

// Reminder if plan not selected
$user->notify(new PlanSelectionRequired());
```

### 4.5 Updated Signup Controller

```php
Route::post('/signup', function (Request $request) {
    $validated = $request->validate([
        'username' => ['nullable', 'string', 'max:50', 'unique:users'],
        'first_name' => ['required', 'string', 'max:100'],
        'last_name' => ['required', 'string', 'max:100'],
        'email' => ['required', 'email', 'unique:users'],
        'password' => ['required', 'confirmed', 'min:8'],
        'organization_name' => ['required', 'string', 'max:255'],
        'is_fictive_org' => ['boolean'],
    ]);

    DB::transaction(function () use ($validated) {
        // Create organization (pending approval)
        $organization = Organization::create([
            'name' => $validated['organization_name'],
            'slug' => Str::slug($validated['organization_name']) . '-' . Str::random(6),
            'billing_email' => $validated['email'],
            'is_fictive' => $validated['is_fictive_org'] ?? false,
            'status' => 'active',
            'is_approved' => false,  // Requires admin approval
        ]);

        // Create default tenant (pending approval, no plan assigned)
        $tenant = Tenant::create([
            'organization_id' => $organization->id,
            'name' => 'Default',
            'slug' => 'default',
            'tier' => null,  // No plan until user selects
            'status' => 'active',
            'is_approved' => false,
            'requires_plan_selection' => true,
        ]);

        // Create user (pending approval)
        $user = User::create([
            'username' => $validated['username'],
            'first_name' => $validated['first_name'],
            'last_name' => $validated['last_name'],
            'name' => $validated['first_name'] . ' ' . $validated['last_name'],  // Computed
            'email' => $validated['email'],
            'password' => Hash::make($validated['password']),
            'organization_id' => $organization->id,
            'role' => 'owner',
            'approval_status' => 'pending',
            'must_reset_password' => false,
        ]);

        $tenant->users()->attach($user->id);

        // Send email verification
        $user->sendEmailVerificationNotification();

        // Notify admins
        Notification::route('mail', config('chom.admin_email'))
            ->notify(new NewUserPendingApproval($user, $organization));

        // Log audit trail
        AuditLog::log('user.registered', 'user', $user->id, [
            'organization_id' => $organization->id,
            'is_fictive' => $organization->is_fictive,
        ]);

        // Do NOT auto-login - redirect to "check your email"
        return redirect()->route('verification.notice')
            ->with('success', 'Please check your email to verify your account.');
    });
});
```

---

## PART 5: IMPLEMENTATION COMPLEXITY ANALYSIS

### 5.1 Changes Required Summary

| Component | Current | Desired | Complexity | Estimated Time |
|-----------|---------|---------|------------|----------------|
| **Signup form** | 4 fields | 6-7 fields (username, first/last name, org options) | Low | 2 hours |
| **Database schema** | name field | first_name, last_name, username | Medium | 4 hours (migration + seeding) |
| **Organization approval** | Tenant-level only | Org-level + User-level | Medium | 6 hours |
| **Plan selection UI** | None | New page with plan cards | Medium | 8 hours |
| **Plan enforcement** | Auto-starter | Force selection after approval | Low | 3 hours |
| **Email verification** | Not enforced | Required before approval | Low | 2 hours |
| **Admin notifications** | None | Email + dashboard badges | Medium | 6 hours |
| **User notifications** | None | Approval/rejection emails | Low | 4 hours |
| **Middleware** | has-tenant only | +plan-required, +approval-required | Low | 3 hours |
| **Admin approval UI** | Tenant approval | User + Org approval queues | High | 10 hours |
| **"Fictive" orgs** | Not supported | New organization type | Medium | 6 hours |
| **Onboarding wizard** | None | Optional multi-step flow | High | 12 hours (if desired) |

**Total Estimated Time**: 50-66 hours (depending on feature scope)

### 5.2 Breaking Changes

**⚠️ WARNING**: These changes will affect existing users:

1. **Database Migration**: Existing users have `name` but not `first_name`/`last_name`
   - **Solution**: Parse existing names into first/last (or require manual update)

2. **Existing Unapproved Tenants**: Current tenants with `is_approved=false` won't have plan selected
   - **Solution**: Grandfather in existing tenants with 'starter' plan, or force plan selection on next login

3. **API Breaking Change**: Registration endpoint changes from `name` to `first_name`/`last_name`
   - **Solution**: Accept both formats, deprecate old format

### 5.3 Backward Compatibility Strategy

```php
// In User model - Accessor for backward compat
public function getNameAttribute(): string {
    // If legacy name field exists, use it
    if ($this->attributes['name']) {
        return $this->attributes['name'];
    }
    // Otherwise, compute from first/last
    return trim($this->first_name . ' ' . $this->last_name);
}

// In migration - Split existing names
foreach (User::whereNull('first_name')->get() as $user) {
    $parts = explode(' ', $user->name, 2);
    $user->update([
        'first_name' => $parts[0],
        'last_name' => $parts[1] ?? $parts[0],
    ]);
}
```

---

## PART 6: RECOMMENDED IMPLEMENTATION PHASES

### Phase 1: Core Workflow Changes (High Priority)

1. ✅ Update signup form (add first/last name fields)
2. ✅ Database migration (split name → first_name, last_name)
3. ✅ Add email verification enforcement
4. ✅ Add admin notification on signup
5. ✅ Add user notification on approval/rejection
6. ✅ Update admin approval UI to show more user details

**Estimated**: 20 hours
**Impact**: Minimal breaking changes

### Phase 2: Plan Selection (Medium Priority)

1. ✅ Create plan selection UI
2. ✅ Add middleware to enforce plan selection after approval
3. ✅ Remove hardcoded 'starter' tier on signup
4. ✅ Add plan_selected_at tracking

**Estimated**: 12 hours
**Impact**: Existing users need to select plan on next login

### Phase 3: Organization Approval (Low Priority - Optional)

1. ✅ Add organization-level approval (separate from tenant)
2. ✅ Add "fictive" organization support
3. ✅ Add "join existing organization" flow

**Estimated**: 16 hours
**Impact**: Significant - changes approval model

### Phase 4: Enhancements (Optional)

1. ✅ Add username support
2. ✅ Onboarding wizard
3. ✅ Approval workflows with notes/reasons
4. ✅ Daily digest emails for admins

**Estimated**: 18 hours
**Impact**: Additive features

---

## PART 7: NEXT STEPS - AWAITING YOUR INPUT

**🚨 CRITICAL: Please answer the 17 questions in Part 3 before implementation.**

Once you provide answers, I will:

1. ✅ Create detailed implementation plan
2. ✅ Write database migrations
3. ✅ Update models and relationships
4. ✅ Create new controllers and views
5. ✅ Implement notification system
6. ✅ Write tests for new flow
7. ✅ Create deployment guide

**Estimated Total Implementation Time**: 50-120 hours depending on scope

---

## SUMMARY OF KEY DECISIONS NEEDED

| # | Decision Required | Impact |
|---|------------------|--------|
| 1 | Username required? | Database + Forms |
| 2 | Split name to first/last? | Database migration |
| 3 | What is "fictive" organization? | Business logic |
| 4 | Approval at user, org, or tenant level? | Approval workflow |
| 5 | When does plan selection happen? | User flow |
| 6 | Who selects the plan? | Business model |
| 7 | Email verification required? | Security |
| 8 | What notifications to send? | Email infrastructure |
| 9 | Multiple approval steps or single? | Admin workflow |
| 10 | Onboarding wizard needed? | UX |

**Please provide answers to move forward with implementation.**

---

*Analysis completed: 2026-01-10*
*Codebase reviewed: 100+ files, 50+ migrations, 30+ models*
*Confidence level: Awaiting clarification on requirements*
