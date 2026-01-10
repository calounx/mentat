# CHOM Onboarding Workflow - Visual Comparison

**Date**: 2026-01-10
**Purpose**: Side-by-side comparison of current vs. desired onboarding flow

---

## Current Implementation Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ STEP 1: USER SIGNUP (registration = signup)                     │
├─────────────────────────────────────────────────────────────────┤
│ Form Fields:                                                    │
│   • name (full name - single field)                            │
│   • email                                                       │
│   • password + confirmation                                     │
│   • organization_name                                           │
│                                                                 │
│ What Happens Immediately:                                       │
│   ✓ Organization created (status: 'active')                    │
│   ✓ Default tenant created (status: 'active', is_approved: false) │
│   ✓ Tier assigned: 'starter' (HARDCODED)                      │
│   ✓ User created (role: 'owner')                              │
│   ✓ User AUTO-LOGGED IN                                        │
│   ✓ Redirect to /dashboard                                     │
│   ✗ NO email verification required                             │
│   ✗ NO admin notification sent                                 │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 2: USER DASHBOARD (while pending approval)                 │
├─────────────────────────────────────────────────────────────────┤
│ User Can:                                                       │
│   ✓ Access /dashboard (limited view)                           │
│   ✓ View profile, settings                                     │
│   ✓ View team members                                          │
│   ✗ CANNOT create sites (tenant.is_approved = false blocks)   │
│                                                                 │
│ User Sees:                                                      │
│   ⚠️  "Account pending approval" message when trying sites     │
│   ⚠️  No notification about approval needed                    │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 3: ADMIN APPROVAL (manual, no notifications)               │
├─────────────────────────────────────────────────────────────────┤
│ Admin Access:                                                   │
│   • Navigate to /admin/tenants                                 │
│   • Filter by "Pending Approval"                               │
│   • Manually review tenant                                     │
│   • Click "Approve Tenant" button                              │
│                                                                 │
│ What Happens on Approval:                                       │
│   ✓ tenant.is_approved = true                                 │
│   ✓ tenant.approved_at = now()                                │
│   ✓ tenant.approved_by = admin_user_id                        │
│   ✗ NO notification sent to user                               │
│                                                                 │
│ Approval Scope:                                                 │
│   • Approves TENANT (not user, not organization separately)    │
│   • Plan already assigned ('starter')                          │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 4: USER CAN CREATE SITES (immediately after approval)      │
├─────────────────────────────────────────────────────────────────┤
│ Checks Performed:                                               │
│   ✓ tenant.is_approved == true                                │
│   ✓ tenant.status == 'active'                                 │
│   ✓ user.canManageSites() (role check)                        │
│   ✓ sites_count < tier_limit.max_sites (quota check)          │
│                                                                 │
│ No Plan Selection Required:                                     │
│   • Plan already set to 'starter' during signup                │
│   • No UI for plan selection shown                             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Desired Workflow (Based on Your Requirements)

```
┌─────────────────────────────────────────────────────────────────┐
│ STEP 1: USER SIGNUP (registration = signup)                     │
├─────────────────────────────────────────────────────────────────┤
│ Form Fields (DESIRED):                                          │
│   • username (?)                                                │
│   • first_name (NEW)                                            │
│   • last_name (NEW)                                             │
│   • email                                                       │
│   • password + confirmation                                     │
│   • organization (choice of):                                   │
│       - Create new organization                                 │
│       - Create "fictive" organization (?)                       │
│       - Join existing organization (?)                          │
│                                                                 │
│ What Should Happen:                                             │
│   ✓ User created (approval_status: 'pending')                  │
│   ✓ Organization created (is_approved: false) OR link to existing │
│   ✓ Tenant created (is_approved: false, NO plan assigned yet)  │
│   ✓ Email verification sent (REQUIRED before anything else?)   │
│   ✓ Admin notification sent                                     │
│   ✗ User NOT auto-logged in (OR logged in but limited access?) │
│   ✗ NO plan assigned yet                                        │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 2: EMAIL VERIFICATION (if required)                        │
├─────────────────────────────────────────────────────────────────┤
│ User Receives:                                                  │
│   • "Verify Your Email" message                                │
│   • Click verification link                                     │
│                                                                 │
│ After Verification:                                             │
│   ✓ email_verified_at set                                      │
│   • Redirect to "Awaiting Approval" page                       │
│                                                                 │
│ QUESTION: Is this step needed?                                  │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 3: ADMIN APPROVAL (WITH notifications)                     │
├─────────────────────────────────────────────────────────────────┤
│ Admin Receives:                                                 │
│   ✉️  Email notification "New user pending approval"           │
│   🔔 Dashboard badge showing pending count                      │
│                                                                 │
│ Admin Reviews:                                                  │
│   • User: username, first_name, last_name, email               │
│   • Organization: name, type (real/fictive)                    │
│   • Signup date                                                 │
│   • Additional info? (reason for signup, company website?)     │
│                                                                 │
│ Admin Actions:                                                  │
│   • APPROVE → User notified, proceeds to plan selection        │
│   • REJECT → User notified with reason, account locked         │
│                                                                 │
│ QUESTIONS:                                                      │
│   - Approve user and organization separately, or together?     │
│   - Record approval notes/reasons?                              │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 4: USER NOTIFIED OF APPROVAL                               │
├─────────────────────────────────────────────────────────────────┤
│ User Receives:                                                  │
│   ✉️  "Your account has been approved!" email                  │
│   • Email contains link to login                                │
│   • Email explains next step: Select a plan                    │
│                                                                 │
│ User Logs In:                                                   │
│   • Redirected to /plan-selection (FORCED)                     │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 5: PLAN SELECTION (REQUIRED after approval)                │
├─────────────────────────────────────────────────────────────────┤
│ User Sees:                                                      │
│   • Plan comparison cards (Starter, Pro, Enterprise)           │
│   • Features, limits, pricing for each tier                    │
│   • "Select Plan" button for each tier                         │
│                                                                 │
│ User Chooses Plan:                                              │
│   ✓ tenant.tier = selected_tier                                │
│   ✓ tenant.plan_selected_at = now()                           │
│   ✓ tenant.requires_plan_selection = false                    │
│                                                                 │
│ QUESTIONS:                                                      │
│   - Can user change plan later?                                │
│   - Does plan choice trigger Stripe subscription?              │
│   - Can user "skip" and select later?                          │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 6: USER CAN CREATE SITES (ONLY after approval + plan)      │
├─────────────────────────────────────────────────────────────────┤
│ Checks Performed:                                               │
│   ✓ user.approval_status == 'approved'                        │
│   ✓ organization.is_approved == true (if separate approval)   │
│   ✓ tenant.is_approved == true                                │
│   ✓ tenant.tier != null (plan selected)                       │
│   ✓ tenant.status == 'active'                                 │
│   ✓ user.canManageSites()                                     │
│   ✓ sites_count < tier_limit.max_sites                        │
│                                                                 │
│ Full Dashboard Access:                                          │
│   ✓ Create sites                                               │
│   ✓ Manage backups                                             │
│   ✓ View metrics                                               │
│   ✓ Manage team                                                │
└─────────────────────────────────────────────────────────────────┘
```

---

## Key Differences Summary

| Aspect | Current | Desired | Change Required |
|--------|---------|---------|----------------|
| **Signup form** | name, email, password, org_name | username(?), first_name, last_name, email, password, org options | ⚠️ **Moderate** |
| **Email verification** | Not enforced | Required (?) | ✅ **Easy** |
| **Organization type** | Always new org | New, fictive, or join existing (?) | ⚠️ **Needs clarification** |
| **Auto-login after signup** | Yes | No (?) or limited access | ✅ **Easy** |
| **Plan assignment** | Auto 'starter' on signup | User selects AFTER approval | ⚠️ **Moderate** |
| **Approval scope** | Tenant only | User + Org + Tenant (?) | 🔴 **Complex** |
| **Admin notification** | None | Email + dashboard badge | ⚠️ **Moderate** |
| **User notification** | None | Approval/rejection emails | ✅ **Easy** |
| **Plan selection UI** | None | Required page after approval | ⚠️ **Moderate** |
| **Site creation gate** | Tenant approval only | Approval + plan selection | ✅ **Easy** |

---

## Critical Questions Requiring Answers

### **Category 1: Signup Form (HIGH PRIORITY)**

**Q1**: Should we collect **username**? If yes, is it required or optional?
- Impact: Database field, uniqueness constraint, UI field

**Q2**: Should we split **name** into **first_name** and **last_name**?
- Impact: Database migration, backwards compatibility for existing users

**Q3**: What is a "**fictive organization**"?
- Option A: Placeholder org for solo users (e.g., "Personal Workspace")
- Option B: Test/demo organization
- Option C: Temporary org pending real company approval

**Q4**: Can users **join existing organizations** during signup?
- If yes: How do they find/select existing orgs?
- If no: Only invite-based team joining?

---

### **Category 2: Approval Workflow (HIGH PRIORITY)**

**Q5**: Is approval at **User level**, **Organization level**, or **both**?
- Current: Single tenant approval (combines both)
- Option A: Approve user AND organization separately (2 steps)
- Option B: Approve user+organization together (1 step)

**Q6**: What should happen to users **immediately after signup** (before approval)?
- Option A: Cannot login (account locked)
- Option B: Can login, sees "Pending Approval" dashboard, limited features
- Option C: Can login, full access except site creation

**Q7**: Should we require **email verification** before admin review?
- Recommendation: Yes (prevents spam, validates email)

**Q8**: What **additional info** should admins see when approving?
- Current: Org name, tenant name, created date
- Desired: User details, business justification, company website, reason for signup?

**Q9**: Should there be **approval notes/rejection reasons**?
- Example: Admin approves with "Approved for trial" or rejects with "Duplicate account"

---

### **Category 3: Plan Selection (HIGH PRIORITY)**

**Q10**: WHEN exactly should plan selection happen?
- Option A: During signup (before approval) - admin sees requested plan
- Option B: After admin approval (forced before dashboard access) ← **Your description suggests this**
- Option C: After admin approval (optional, defaults to starter)

**Q11**: WHO selects the plan?
- Option A: User selects plan (self-service)
- Option B: Admin assigns plan during approval
- Option C: User requests, admin approves specific plan

**Q12**: Can users **upgrade/downgrade plans later**?
- If yes: Self-service or admin-only?

---

### **Category 4: Notifications (MEDIUM PRIORITY)**

**Q13**: What notifications should be sent **to admins**?
- [ ] Email when new user signs up
- [ ] Dashboard badge showing pending approval count
- [ ] Daily digest of pending approvals
- [ ] Real-time notification (Pusher/WebSocket)

**Q14**: What notifications should be sent **to users**?
- [ ] Welcome email after signup
- [ ] Email verification link
- [ ] "Account approved" email
- [ ] "Account rejected" email with reason
- [ ] "Plan selection required" reminder

---

### **Category 5: User Experience (LOW PRIORITY)**

**Q15**: Should there be a **multi-step onboarding wizard**?
- Example: Step 1: Basic Info → Step 2: Verify Email → Step 3: Await Approval →
           Step 4: Select Plan → Step 5: Create First Site

**Q16**: Should users be able to **edit their pending application**?
- Example: User signed up, waiting approval, wants to change organization name

**Q17**: What happens if admin **rejects** the application?
- Option A: Account deleted/soft-deleted
- Option B: Account locked, user can reapply
- Option C: Account marked rejected, user can appeal

---

## Implementation Complexity Estimates

| Feature | Complexity | Time Estimate | Dependencies |
|---------|-----------|---------------|--------------|
| Split name to first/last | Low | 4 hours | Database migration |
| Add username field | Low | 3 hours | Database migration |
| Email verification enforcement | Low | 2 hours | Config change |
| Admin email notifications | Medium | 6 hours | Mail setup |
| User email notifications | Low | 4 hours | Mail setup |
| Plan selection UI | Medium | 8 hours | Frontend work |
| Plan selection enforcement | Low | 3 hours | Middleware |
| Fictive organizations | Medium | 6 hours | Needs clarification |
| Separate user/org approval | High | 12 hours | Database changes |
| Approval notes/reasons | Low | 3 hours | Database field |
| Join existing org flow | High | 10 hours | Complex logic |
| Onboarding wizard | High | 12 hours | Frontend work |

**Minimum Implementation** (core requirements only): **30-40 hours**
**Full Implementation** (all features): **70-90 hours**

---

## Recommended Next Steps

### 1. **Answer the 17 Questions Above** ← **CRITICAL**

I cannot proceed with implementation until these are clarified.

### 2. **Review Proposed Database Changes**

```sql
-- Users table
ALTER TABLE users
  ADD COLUMN username VARCHAR(50) UNIQUE NULL,
  ADD COLUMN first_name VARCHAR(100) NOT NULL,
  ADD COLUMN last_name VARCHAR(100) NOT NULL,
  ADD COLUMN approval_status ENUM('pending', 'approved', 'rejected') DEFAULT 'pending',
  ADD COLUMN approved_at TIMESTAMP NULL,
  ADD COLUMN approved_by UUID NULL,
  ADD COLUMN rejection_reason TEXT NULL;

-- Organizations table
ALTER TABLE organizations
  ADD COLUMN is_fictive BOOLEAN DEFAULT FALSE,
  ADD COLUMN is_approved BOOLEAN DEFAULT FALSE,
  ADD COLUMN approved_at TIMESTAMP NULL,
  ADD COLUMN approved_by UUID NULL;

-- Tenants table
ALTER TABLE tenants
  ADD COLUMN plan_selected_at TIMESTAMP NULL,
  MODIFY tier ENUM('starter', 'pro', 'enterprise') NULL;  -- Allow NULL initially
```

### 3. **Approve Implementation Plan**

Once questions answered, I will provide:
- Detailed step-by-step implementation plan
- Database migrations (with rollback)
- Controller/model changes
- View/component updates
- Test suite
- Deployment checklist

---

## My Recommendations (Pending Your Confirmation)

Based on industry best practices and your requirements:

✅ **DO THESE**:
1. Split name → first_name + last_name (better personalization)
2. Require email verification before approval (security)
3. Send admin notifications on new signups (awareness)
4. Send user notifications on approval/rejection (communication)
5. Force plan selection after approval (clear workflow)
6. Add approval notes for audit trail

⚠️ **CONSIDER THESE**:
1. Username field (optional, not login credential)
2. Separate user + organization approval (adds complexity, may not be needed)
3. Onboarding wizard (nice UX, but adds development time)

❌ **SKIP THESE** (unless specifically needed):
1. "Join existing organization" during signup (use invite system instead)
2. Self-service plan upgrades initially (can add later)
3. User editing pending applications (edge case)

---

**Waiting for your answers to proceed with implementation! 🚀**
