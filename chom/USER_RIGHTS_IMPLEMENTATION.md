# User Rights Implementation Guide

**Last Updated: January 2, 2026**

This document provides technical implementation details for GDPR user rights (Articles 15-22) in the CHOM platform.

## Overview

CHOM implements comprehensive user rights functionality to ensure GDPR compliance with 100% coverage of mandatory data subject rights.

## 1. Right of Access (GDPR Article 15)

### 1.1 What Users Can Access
Users can request and receive:
- All personal data we hold about them
- Purposes of processing
- Categories of data processed
- Recipients or categories of recipients
- Retention periods
- Source of data (if not collected from user)
- Existence of automated decision-making

### 1.2 Implementation

#### Via Account Settings (Self-Service)
```
Account Settings > Privacy & Data > View My Data
```

**Display Format:**
- **User Profile**: Name, email, role, organization
- **Account Activity**: Login history, operations performed, API calls
- **Billing Information**: Invoices, payment history, subscription details
- **Sites & Resources**: All sites, VPS allocations, backups
- **Audit Trail**: Complete audit log of user actions
- **Preferences**: UI settings, notification preferences

**Response Time**: Immediate display

#### Via Email Request
**Email**: privacy@[YOUR-DOMAIN].com
**Subject**: "Right of Access Request"

**Required Information**:
- Full name
- Email address associated with account
- Account ID or organization name (for verification)

**Response Time**: Within 30 days (GDPR Article 12(3))

**Response Format**:
- PDF report summarizing data
- JSON export attachment with complete data
- Includes metadata: processing purposes, retention periods, recipients

### 1.3 Technical Implementation

**Database Queries**:
```php
// Pseudo-code example
$user = User::with([
    'organization',
    'operations',
    'auditLogs',
    'sites',
    'backups'
])->find($userId);

$accessReport = [
    'personal_data' => $user->toArray(),
    'processing_purposes' => ['service_delivery', 'billing', 'security'],
    'retention_periods' => [
        'account_data' => 'Active account + 30 days',
        'billing_records' => '7 years',
        'audit_logs' => '1 year'
    ],
    'recipients' => ['Stripe (payment)', 'Email provider'],
    'rights' => ['access', 'rectification', 'erasure', 'portability', 'objection']
];
```

**Access Controls**:
- User can only access own data
- Organization owners can access organization-level data
- Admins cannot access other users' personal data without permission

## 2. Right to Rectification (GDPR Article 16)

### 2.1 What Users Can Rectify
Users can correct:
- Name
- Email address (requires verification)
- Organization details
- Billing information
- Site configurations
- Preferences and settings

### 2.2 Implementation

#### Via Account Settings (Self-Service)
```
Account Settings > Profile > Edit
Account Settings > Organization > Edit
```

**Editable Fields**:
- User name
- Email (with email verification step)
- Organization name
- Billing email
- Contact information

**Restrictions**:
- Cannot change: User ID (UUID), creation date, audit logs
- Email change requires verification link sent to both old and new addresses

**Response Time**: Immediate update

#### Via Email Request
**Email**: privacy@[YOUR-DOMAIN].com
**Subject**: "Right to Rectification Request"

**Required Information**:
- Account identification
- Field(s) to be corrected
- Corrected information
- Reason for correction (optional)

**Response Time**: Within 30 days (GDPR Article 12(3))

### 2.3 Technical Implementation

**Update Process**:
```php
// Email change with verification
$user->email_pending = $newEmail;
$user->save();

// Send verification to new email
Mail::to($newEmail)->send(new VerifyEmailChange($token));

// Upon verification
$user->email = $user->email_pending;
$user->email_pending = null;
$user->email_verified_at = now();
$user->save();

// Log in audit trail
AuditLog::create([
    'user_id' => $user->id,
    'action' => 'email_changed',
    'old_value' => $oldEmail,
    'new_value' => $newEmail,
    'ip_address' => request()->ip()
]);
```

**Notification**:
- Email sent to old address notifying of change
- Security alert if change not initiated by user

## 3. Right to Erasure / "Right to be Forgotten" (GDPR Article 17)

### 3.1 What Gets Deleted
When user exercises right to erasure:
- ✅ User account and profile
- ✅ Sites and configurations
- ✅ VPS allocations
- ✅ Backups (after retention period)
- ✅ Usage data and metrics
- ✅ Audit logs (after retention period)
- ✅ Support tickets (after retention period)
- ❌ Billing records (7-year legal obligation)
- ❌ Anonymous aggregate statistics

### 3.2 Implementation

#### Via Account Settings (Self-Service)
```
Account Settings > Privacy & Data > Delete My Account
```

**Deletion Process**:
1. **Warning Dialog**: Explains consequences, 30-day recovery period
2. **Confirmation**: User types "DELETE" to confirm
3. **Verification**: Email confirmation link sent
4. **Grace Period**: 30 days to recover account
5. **Permanent Deletion**: After 30 days, irreversible deletion

**Response Time**:
- Immediate soft delete (account inaccessible)
- Permanent deletion after 30 days

#### Via Email Request
**Email**: privacy@[YOUR-DOMAIN].com
**Subject**: "Right to Erasure Request"

**Required Information**:
- Account identification
- Reason for deletion (optional)
- Preference: Immediate deletion or 30-day grace period

**Response Time**: Within 30 days (GDPR Article 12(3))

### 3.3 Deletion Process

**Phase 1: Soft Delete (Day 0)**
```php
// Mark account for deletion
$user->deleted_at = now();
$user->deletion_scheduled_at = now()->addDays(30);
$user->save();

// Disable access immediately
$user->tokens()->delete(); // Revoke API tokens
$user->sessions()->delete(); // Clear sessions

// Notify organization owner if not the user themselves
if (!$user->isOwner()) {
    Mail::to($organization->owner)->send(new UserAccountDeleted($user));
}
```

**Phase 2: Data Anonymization (Day 30)**
```php
// Overwrite personal data
$user->name = 'Deleted User ' . $user->id;
$user->email = 'deleted.' . $user->id . '@deleted.local';
$user->password = null;
$user->two_factor_secret = null;

// Delete related resources
$user->sites()->each(function($site) {
    $site->backups()->delete();
    $site->delete();
});

$user->operations()->delete();
$user->usageRecords()->delete();

// Anonymize audit logs (retain for compliance but remove PII)
$user->auditLogs()->update([
    'user_id' => null,
    'user_email_hash' => hash('sha256', $user->email),
    'anonymized_at' => now()
]);

$user->forceDelete(); // Permanent deletion
```

**Exceptions (Not Deleted)**:
```php
// Retain billing records for 7 years (legal obligation)
Invoice::where('organization_id', $organization->id)
    ->update(['retention_reason' => 'legal_obligation_tax']);

// Aggregate statistics (anonymized)
UsageStatistics::aggregateAndAnonymize($user->id);
```

### 3.4 Recovery During Grace Period

**Recovery Process**:
```
Email: privacy@[YOUR-DOMAIN].com
Subject: "Account Recovery Request"
```

**Verification Required**:
- Original email address
- Account details
- Security questions (if configured)

**Response Time**: Within 24 hours

**Technical Process**:
```php
// Restore soft-deleted account
$user->deleted_at = null;
$user->deletion_scheduled_at = null;
$user->restore();

// Log recovery
AuditLog::create([
    'user_id' => $user->id,
    'action' => 'account_recovered',
    'ip_address' => request()->ip()
]);
```

## 4. Right to Restriction of Processing (GDPR Article 18)

### 4.1 When Restriction Applies
Users can request restriction when:
- Accuracy of personal data is contested (during verification)
- Processing is unlawful but user opposes erasure
- We no longer need data but user needs it for legal claims
- User has objected to processing (pending verification of grounds)

### 4.2 Implementation

**Email Request**:
**Email**: privacy@[YOUR-DOMAIN].com
**Subject**: "Right to Restriction Request"

**Required Information**:
- Account identification
- Reason for restriction (must match one of the grounds above)
- Scope of restriction (all processing or specific purposes)

**Response Time**: Within 30 days

### 4.3 Technical Implementation

**Restriction Flags**:
```php
// Add to users table migration
$table->boolean('processing_restricted')->default(false);
$table->text('restriction_reason')->nullable();
$table->timestamp('restriction_applied_at')->nullable();

// Apply restriction
$user->processing_restricted = true;
$user->restriction_reason = 'accuracy_contested';
$user->restriction_applied_at = now();
$user->save();
```

**Processing Limitations**:
```php
// Check before processing
if ($user->processing_restricted) {
    // Only allow storage, not active processing
    // Block: emails, analytics, marketing, automated actions
    // Allow: storage, data access requests, legal obligations

    if ($purpose !== 'storage' && $purpose !== 'legal_obligation') {
        throw new ProcessingRestrictedException(
            'Processing restricted per GDPR Article 18'
        );
    }
}
```

**Permitted During Restriction**:
- ✅ Data storage (not deleted)
- ✅ Processing with user's explicit consent
- ✅ Processing for legal claims
- ✅ Processing to protect rights of others
- ✅ Processing for important public interest

**Restricted During Restriction**:
- ❌ Marketing emails
- ❌ Analytics and profiling
- ❌ Automated site provisioning
- ❌ Data sharing with sub-processors (except storage)

**Lifting Restriction**:
- User notification before lifting restriction
- User may request lifting at any time

## 5. Right to Data Portability (GDPR Article 20)

### 5.1 What Data Is Portable
Users can export:
- All personal data provided to us
- All derived data (configurations, settings)
- Data processed with consent or for contract performance
- **Format**: Structured, commonly used, machine-readable (JSON)

### 5.2 Implementation

#### Via Account Settings (Self-Service)
```
Account Settings > Privacy & Data > Export My Data
```

**Export Options**:
- **Full Export**: All data (recommended)
- **Partial Export**: Select data categories
- **Format**: JSON (structured, machine-readable)

**Response Time**:
- Standard data: Immediate download
- Large datasets (>1GB): Email link within 48 hours

#### Via Email Request
**Email**: privacy@[YOUR-DOMAIN].com
**Subject**: "Right to Data Portability Request"

**Response Time**: Within 30 days

### 5.3 Export Data Structure

**JSON Export Schema**:
```json
{
  "export_metadata": {
    "export_date": "2026-01-02T12:00:00Z",
    "user_id": "uuid",
    "format_version": "1.0",
    "gdpr_article": "Article 20 - Right to Data Portability"
  },
  "personal_data": {
    "user_profile": {
      "name": "John Doe",
      "email": "john@example.com",
      "created_at": "2025-06-01T10:30:00Z",
      "role": "owner",
      "two_factor_enabled": true
    },
    "organization": {
      "name": "Example Corp",
      "slug": "example-corp",
      "billing_email": "billing@example.com",
      "created_at": "2025-06-01T10:30:00Z"
    },
    "sites": [
      {
        "id": "uuid",
        "domain": "example.com",
        "site_type": "wordpress",
        "php_version": "8.2",
        "ssl_enabled": true,
        "created_at": "2025-06-15T14:20:00Z",
        "settings": {}
      }
    ],
    "subscriptions": [
      {
        "tier": "pro",
        "status": "active",
        "created_at": "2025-06-01T10:35:00Z"
      }
    ],
    "operations": [
      {
        "type": "site_created",
        "status": "completed",
        "created_at": "2025-06-15T14:20:00Z"
      }
    ],
    "audit_logs": [
      {
        "action": "login",
        "ip_address": "192.0.2.1",
        "user_agent": "Mozilla/5.0...",
        "created_at": "2026-01-02T09:00:00Z"
      }
    ],
    "usage_records": [
      {
        "metric": "sites_count",
        "value": 3,
        "recorded_at": "2026-01-01T00:00:00Z"
      }
    ]
  },
  "preferences": {
    "ui_theme": "dark",
    "notifications_enabled": true,
    "language": "en"
  },
  "billing_history": [
    {
      "invoice_id": "inv_123",
      "amount": 79.00,
      "currency": "USD",
      "status": "paid",
      "date": "2025-12-01T00:00:00Z"
    }
  ]
}
```

### 5.4 Technical Implementation

**Export Generation**:
```php
class DataPortabilityExport
{
    public function generate(User $user): string
    {
        $data = [
            'export_metadata' => [
                'export_date' => now()->toIso8601String(),
                'user_id' => $user->id,
                'format_version' => '1.0',
                'gdpr_article' => 'Article 20 - Right to Data Portability'
            ],
            'personal_data' => [
                'user_profile' => $user->only(['name', 'email', 'created_at', 'role']),
                'organization' => $user->organization,
                'sites' => $user->organization->tenants()
                    ->with('sites')->get(),
                'subscriptions' => $user->organization->subscription,
                'operations' => $user->operations,
                'audit_logs' => $user->auditLogs,
                'usage_records' => $user->organization->usageRecords
            ],
            'preferences' => $user->preferences ?? [],
            'billing_history' => $user->organization->invoices
        ];

        return json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    }
}

// Controller
public function exportData(Request $request)
{
    $user = $request->user();
    $exporter = new DataPortabilityExport();
    $json = $exporter->generate($user);

    // Log export
    AuditLog::create([
        'user_id' => $user->id,
        'action' => 'data_export',
        'ip_address' => $request->ip()
    ]);

    return response()->streamDownload(function() use ($json) {
        echo $json;
    }, 'chom-data-export-' . now()->format('Y-m-d') . '.json');
}
```

### 5.5 Direct Transfer to Another Controller

**GDPR Article 20(2)**: Right to have data transmitted directly to another controller.

**Request Method**:
**Email**: privacy@[YOUR-DOMAIN].com
**Subject**: "Direct Data Transfer Request"

**Required Information**:
- Recipient controller details
- Recipient's technical contact
- Transfer protocol (API, SFTP, email)

**Technical Feasibility**:
- We will make reasonable efforts to accommodate
- Must be technically feasible
- May require recipient to provide API endpoint or transfer mechanism

## 6. Right to Object (GDPR Article 21)

### 6.1 Grounds for Objection
Users can object to processing based on:
- **Article 21(1)**: Legitimate interests
- **Article 21(2)**: Direct marketing (absolute right)
- **Article 21(3)**: Automated decision-making and profiling

### 6.2 Implementation

#### Object to Marketing (Self-Service)
```
Account Settings > Notifications > Marketing Preferences
Email footer: "Unsubscribe from marketing emails"
```

**Effect**: Immediate cessation of marketing communications

**Response Time**: Immediate

#### Object to Other Processing (Email)
**Email**: privacy@[YOUR-DOMAIN].com
**Subject**: "Right to Object Request"

**Required Information**:
- Account identification
- Processing activity to object to
- Grounds for objection (based on particular situation)

**Response Time**: Within 30 days

### 6.3 Technical Implementation

**Marketing Opt-Out**:
```php
// User table
$table->boolean('marketing_opt_out')->default(false);
$table->timestamp('marketing_opt_out_at')->nullable();

// Before sending marketing email
if ($user->marketing_opt_out) {
    return; // Do not send
}

// Marketing opt-out action
$user->marketing_opt_out = true;
$user->marketing_opt_out_at = now();
$user->save();

// Log
AuditLog::create([
    'user_id' => $user->id,
    'action' => 'marketing_opt_out'
]);
```

**Objection to Legitimate Interest Processing**:
```php
// Evaluate objection
if ($user->hasObjection('analytics')) {
    // Cease processing unless we demonstrate compelling grounds
    // Compelling grounds: safety, security, fraud prevention

    if ($purpose === 'security' || $purpose === 'fraud_prevention') {
        // Continue processing (compelling grounds override)
        $this->process($data, $purpose);
    } else {
        // Stop processing
        return;
    }
}
```

## 7. Right Not to Be Subject to Automated Decision-Making (GDPR Article 22)

### 7.1 Automated Processing in CHOM

**Current Automated Decisions**:
1. **Usage Limit Enforcement**: Automatic blocking when tier limits exceeded
2. **Fraud Detection**: Automatic flagging of suspicious activity

**No Profiling**: We do not create user profiles for marketing or other purposes.

### 7.2 User Rights
Users have the right to:
- Request human review of automated decisions
- Express their point of view
- Contest the decision

### 7.3 Implementation

**Request Method**:
**Email**: privacy@[YOUR-DOMAIN].com
**Subject**: "Automated Decision Review Request"

**Required Information**:
- Account identification
- Automated decision to review (e.g., account suspension)
- Your perspective

**Response Time**: Within 7 days (expedited for account access issues)

### 7.4 Technical Safeguards

**Human Review Process**:
```php
// Flag for human review
if ($user->requests_human_review) {
    // Suspend automated action
    $automatedDecision->status = 'pending_human_review';
    $automatedDecision->save();

    // Notify support team
    Notification::send($supportTeam, new HumanReviewRequired($user, $automatedDecision));

    // Allow user to provide context
    return view('automated-decision-appeal', [
        'decision' => $automatedDecision,
        'appeal_form' => true
    ]);
}
```

**Automated Decision Logging**:
```php
AuditLog::create([
    'user_id' => $user->id,
    'action' => 'automated_decision',
    'decision_type' => 'usage_limit_enforcement',
    'decision_outcome' => 'access_restricted',
    'algorithm_version' => '1.0',
    'human_review_available' => true
]);
```

## 8. Summary of Implementation Status

| Right | Article | Self-Service | Email Request | Response Time | Status |
|-------|---------|--------------|---------------|---------------|--------|
| Access | 15 | ✅ Yes | ✅ Yes | Immediate / 30 days | ✅ Implemented |
| Rectification | 16 | ✅ Yes | ✅ Yes | Immediate / 30 days | ✅ Implemented |
| Erasure | 17 | ✅ Yes | ✅ Yes | 30 days | ✅ Implemented |
| Restriction | 18 | ❌ No | ✅ Yes | 30 days | ✅ Implemented |
| Portability | 20 | ✅ Yes | ✅ Yes | Immediate / 30 days | ✅ Implemented |
| Object | 21 | ✅ Yes (marketing) | ✅ Yes (other) | Immediate / 30 days | ✅ Implemented |
| Automated Decisions | 22 | ❌ No | ✅ Yes | 7 days | ✅ Implemented |

**100% GDPR User Rights Coverage Achieved**

## 9. Verification and Security

### 9.1 Identity Verification
Before processing rights requests via email:
1. **Email Match**: Request from registered email address
2. **Account Details**: Provide account ID or organization name
3. **Additional Verification**: Security questions or support ticket verification
4. **Suspicious Requests**: May require additional proof of identity

### 9.2 Fraudulent Requests
If we suspect fraudulent request:
- Request additional verification
- Notify account owner at registered email
- Delay processing until verification complete

### 9.3 Third-Party Requests
Requests on behalf of data subjects (e.g., legal representatives):
- Require proof of authorization
- Copy of power of attorney or legal documentation
- Direct confirmation from data subject

## 10. Logging and Accountability

All rights requests are logged:
```php
RightsRequest::create([
    'user_id' => $user->id,
    'right' => 'erasure', // Article 17
    'request_date' => now(),
    'request_method' => 'email', // or 'self_service'
    'processed_at' => now()->addDays(3),
    'outcome' => 'completed',
    'notes' => 'Account deleted per user request'
]);
```

**Audit Trail Retention**: 3 years for compliance verification

---

**Last Updated**: January 2, 2026
**Review Frequency**: Annually or upon GDPR updates
**Contact**: privacy@[YOUR-DOMAIN].com
