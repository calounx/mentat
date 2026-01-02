# Team Management API Implementation

## Overview

Complete implementation of the Team Management API Controller for CHOM application with comprehensive invitation system, role-based access control, and security features.

**Location:** `/app/Http/Controllers/Api/V1/TeamController.php`

**Status:** ✅ Fully Implemented

---

## Architecture Components

### 1. Database Schema

#### TeamInvitation Model
- **Migration:** `database/migrations/2026_01_02_000001_create_team_invitations_table.php`
- **Model:** `app/Models/TeamInvitation.php`

**Schema:**
```sql
team_invitations:
  - id (uuid, primary)
  - organization_id (uuid, foreign key -> organizations)
  - invited_by (uuid, foreign key -> users)
  - email (string)
  - token (string, unique)
  - role (enum: admin, member, viewer)
  - expires_at (timestamp)
  - accepted_at (timestamp, nullable)
  - created_at, updated_at

Indexes:
  - organization_id + email (composite)
  - token (unique)
  - expires_at
```

**Features:**
- Auto-generates unique 64-char token on creation
- Default 7-day expiration
- Scopes: `pending()`, `expired()`
- Helper methods: `isExpired()`, `isValid()`, `markAsAccepted()`

### 2. Request Validation Classes

#### InviteMemberRequest
**Location:** `app/Http/Requests/V1/Team/InviteMemberRequest.php`

**Rules:**
- Email: required, valid email, unique in organization
- Role: required, must be in allowed roles (based on inviter's role)
- Name: optional, string

**Authorization:**
- Only admins and owners can invite
- Owners can invite as: admin, member, viewer
- Admins can only invite as: member, viewer

#### UpdateMemberRequest
**Location:** `app/Http/Requests/V1/Team/UpdateMemberRequest.php`

**Rules:**
- Role: required, must be in allowed roles

**Authorization:**
- Only admins and owners can update roles
- Owners can set: admin, member, viewer
- Admins can only set: member, viewer

### 3. API Resources

#### TeamMemberResource
**Location:** `app/Http/Resources/V1/TeamMemberResource.php`

**Response Structure:**
```json
{
  "id": "uuid",
  "name": "string",
  "email": "string",
  "role": "owner|admin|member|viewer",
  "email_verified": boolean,
  "email_verified_at": "ISO8601",
  "two_factor_enabled": boolean,
  "created_at": "ISO8601",
  "updated_at": "ISO8601",
  "permissions": {
    "can_manage_sites": boolean,
    "can_manage_team": boolean,
    "is_owner": boolean,
    "is_admin": boolean,
    "is_viewer": boolean
  }
}
```

#### TeamMemberCollection
**Location:** `app/Http/Resources/V1/TeamMemberCollection.php`

**Response Structure:**
```json
{
  "success": true,
  "data": [...TeamMemberResource],
  "meta": {
    "pagination": {
      "total": int,
      "count": int,
      "per_page": int,
      "current_page": int,
      "total_pages": int,
      "has_more_pages": boolean
    },
    "summary": {
      "total_members": int,
      "roles": {
        "owners": int,
        "admins": int,
        "members": int,
        "viewers": int
      }
    }
  }
}
```

#### TeamInvitationResource
**Location:** `app/Http/Resources/V1/TeamInvitationResource.php`

**Response Structure:**
```json
{
  "id": "uuid",
  "email": "string",
  "role": "admin|member|viewer",
  "token": "string (only on creation)",
  "expires_at": "ISO8601",
  "accepted_at": "ISO8601|null",
  "created_at": "ISO8601",
  "invited_by": {
    "id": "uuid",
    "name": "string",
    "email": "string"
  },
  "status": {
    "is_pending": boolean,
    "is_expired": boolean,
    "is_accepted": boolean
  },
  "expires_in_human": "string"
}
```

---

## API Endpoints

### Team Member Management

#### 1. List Team Members
```
GET /api/v1/team
```

**Query Parameters:**
- `per_page` (optional, default: 20)

**Authorization:** Any authenticated user in organization

**Response:** 200 OK
```json
{
  "success": true,
  "data": [...TeamMemberResource],
  "meta": {...pagination}
}
```

**Behavior:**
- Returns all members of authenticated user's organization
- Sorted by role hierarchy (owner → admin → member → viewer), then by name
- Paginated results

---

#### 2. Get Team Member Details
```
GET /api/v1/team/{member}
```

**Authorization:** Any authenticated user in organization

**Response:** 200 OK
```json
{
  "success": true,
  "data": {...TeamMemberResource}
}
```

**Errors:**
- 404: Member not found in organization

---

#### 3. Update Team Member Role
```
PATCH /api/v1/team/{member}
```

**Authorization:** Admin or Owner only

**Request Body:**
```json
{
  "role": "admin|member|viewer"
}
```

**Response:** 200 OK
```json
{
  "success": true,
  "data": {...TeamMemberResource},
  "message": "Team member role updated successfully."
}
```

**Business Rules:**
- Cannot modify yourself
- Cannot modify owner's role (use transfer-ownership instead)
- Admins cannot modify other admins (only owner can)
- Owners can set: admin, member, viewer
- Admins can only set: member, viewer

**Errors:**
- 400: Cannot modify owner/self
- 403: Insufficient permissions
- 404: Member not found

---

#### 4. Remove Team Member
```
DELETE /api/v1/team/{member}
```

**Authorization:** Admin or Owner only

**Rate Limit:** Sensitive operations (10/min)

**Response:** 204 No Content

**Business Rules:**
- Cannot remove yourself
- Cannot remove the owner
- Admins cannot remove other admins (only owner can)
- Revokes all API tokens
- Sets organization_id to null and role to viewer

**Errors:**
- 400: Cannot remove owner/self
- 403: Insufficient permissions
- 404: Member not found
- 500: Removal failed

---

### Team Invitation Management

#### 5. Invite Team Member
```
POST /api/v1/team/invite
```

**Authorization:** Admin or Owner only

**Request Body:**
```json
{
  "email": "user@example.com",
  "role": "admin|member|viewer",
  "name": "Optional Name"
}
```

**Response:** 201 Created
```json
{
  "success": true,
  "data": {...TeamInvitationResource},
  "message": "Invitation sent successfully."
}
```

**Business Rules:**
- Email must not be existing member
- Email must not have pending invitation
- Owners can invite as: admin, member, viewer
- Admins can only invite as: member, viewer
- Token valid for 7 days
- Email sending is logged (implement email service separately)

**Errors:**
- 400: Already member or pending invitation
- 403: Insufficient permissions
- 500: Invitation failed

---

#### 6. Accept Invitation
```
POST /api/v1/team/accept/{token}
```

**Authorization:** Optional (authenticated user recommended)

**Response:** 200 OK
```json
{
  "success": true,
  "message": "Invitation accepted successfully...",
  "data": {
    "organization": {
      "id": "uuid",
      "name": "string"
    },
    "role": "string"
  }
}
```

**Business Rules:**
- Token must be valid and not expired
- User email must match invitation email
- User cannot already be in an organization
- Marks invitation as accepted
- Updates user's organization_id and role

**Errors:**
- 400: Expired, already accepted, email mismatch, already in org
- 404: Invalid token
- 500: Acceptance failed

---

#### 7. List Pending Invitations
```
GET /api/v1/team/pending
```

**Authorization:** Admin or Owner only

**Query Parameters:**
- `per_page` (optional, default: 20)

**Response:** 200 OK
```json
{
  "success": true,
  "data": [...TeamInvitationResource],
  "meta": {...pagination}
}
```

**Behavior:**
- Returns only pending (not accepted, not expired) invitations
- Ordered by creation date (newest first)

**Errors:**
- 403: Insufficient permissions

---

#### 8. Cancel Invitation
```
DELETE /api/v1/team/invitations/{invitation}
```

**Authorization:** Admin or Owner only

**Response:** 204 No Content

**Business Rules:**
- Invitation must belong to organization
- Invitation must be pending (not accepted, not expired)

**Errors:**
- 400: Invitation not pending
- 403: Insufficient permissions
- 404: Invitation not found
- 500: Cancellation failed

---

### Organization Management

#### 9. Transfer Ownership
```
POST /api/v1/team/transfer-ownership
```

**Authorization:** Owner only

**Rate Limit:** Sensitive operations (10/min)

**Request Body:**
```json
{
  "user_id": "uuid",
  "password": "current_password"
}
```

**Response:** 200 OK
```json
{
  "success": true,
  "message": "Ownership transferred successfully.",
  "data": {
    "new_owner": {...TeamMemberResource},
    "previous_owner": {...TeamMemberResource}
  }
}
```

**Business Rules:**
- Requires password confirmation
- New owner must be member of organization
- Cannot transfer to yourself
- Previous owner becomes admin
- Transaction-safe operation

**Errors:**
- 400: Invalid user, self-transfer
- 401: Invalid password
- 403: Not owner
- 500: Transfer failed

---

## Security Features

### 1. Authorization
- Role-based access control (RBAC)
- Method-level authorization checks
- Request class authorization
- Password confirmation for sensitive operations

### 2. Rate Limiting
- Standard API: 100-1000 req/min (tier-based)
- Sensitive operations: 10 req/min
  - Member removal
  - Ownership transfer

### 3. Validation
- Email uniqueness (per organization)
- Role permission validation
- Token expiration (7 days)
- Business rule enforcement

### 4. Audit Logging
- All operations logged with context
- Includes: actor, target, changes, timestamp
- Error logging with stack traces

### 5. Data Security
- Tokens auto-generated (64 chars)
- API tokens revoked on member removal
- Transaction-safe operations
- Foreign key constraints

---

## Role Permissions Matrix

| Action | Owner | Admin | Member | Viewer |
|--------|-------|-------|--------|--------|
| View team members | ✅ | ✅ | ✅ | ✅ |
| View member details | ✅ | ✅ | ✅ | ✅ |
| Invite as admin | ✅ | ❌ | ❌ | ❌ |
| Invite as member/viewer | ✅ | ✅ | ❌ | ❌ |
| Update to admin | ✅ | ❌ | ❌ | ❌ |
| Update to member/viewer | ✅ | ✅ | ❌ | ❌ |
| Remove admin | ✅ | ❌ | ❌ | ❌ |
| Remove member/viewer | ✅ | ✅ | ❌ | ❌ |
| View pending invitations | ✅ | ✅ | ❌ | ❌ |
| Cancel invitations | ✅ | ✅ | ❌ | ❌ |
| Transfer ownership | ✅ | ❌ | ❌ | ❌ |

---

## Error Response Format

All errors follow consistent format:

```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable error message"
  }
}
```

**Common Error Codes:**
- `FORBIDDEN` - Insufficient permissions
- `NOT_FOUND` - Resource not found
- `INVALID_TOKEN` - Invalid invitation token
- `INVITATION_EXPIRED` - Invitation has expired
- `ALREADY_MEMBER` - Email already in organization
- `CANNOT_MODIFY_OWNER` - Cannot modify owner's role
- `CANNOT_REMOVE_SELF` - Cannot remove yourself
- `INSUFFICIENT_PERMISSIONS` - Not authorized for action
- `EMAIL_MISMATCH` - User email doesn't match invitation
- `ALREADY_IN_ORGANIZATION` - User already in another org

---

## Testing Guide

### Manual Testing

1. **Setup:**
```bash
cd /home/calounx/repositories/mentat/chom
php artisan migrate
```

2. **Create Test Users:**
```bash
# Register as owner
curl -X POST http://localhost/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Owner User",
    "email": "owner@test.com",
    "password": "password123",
    "password_confirmation": "password123",
    "organization_name": "Test Org"
  }'

# Save the token from response
export TOKEN="your-token-here"
```

3. **Test Endpoints:**

```bash
# List team members
curl http://localhost/api/v1/team \
  -H "Authorization: Bearer $TOKEN"

# Invite member
curl -X POST http://localhost/api/v1/team/invite \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "member@test.com",
    "role": "member"
  }'

# List pending invitations
curl http://localhost/api/v1/team/pending \
  -H "Authorization: Bearer $TOKEN"

# Update member role (get member ID from list)
curl -X PATCH http://localhost/api/v1/team/{member-id} \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"role": "admin"}'

# Remove member
curl -X DELETE http://localhost/api/v1/team/{member-id} \
  -H "Authorization: Bearer $TOKEN"
```

---

## Email Integration (TODO)

The invitation system logs email details but doesn't send emails yet. To implement:

1. **Configure Mail Driver:**
```env
MAIL_MAILER=smtp
MAIL_HOST=smtp.mailtrap.io
MAIL_PORT=2525
MAIL_USERNAME=your-username
MAIL_PASSWORD=your-password
```

2. **Create Notification:**
```php
php artisan make:notification TeamInvitationNotification
```

3. **Update TeamController@invite:**
```php
use App\Notifications\TeamInvitationNotification;

// After creating invitation
Notification::route('mail', $validated['email'])
    ->notify(new TeamInvitationNotification($invitation));
```

4. **Notification Template:**
```php
public function toMail($notifiable)
{
    return (new MailMessage)
        ->subject('You have been invited to join ' . $this->invitation->organization->name)
        ->line('Click the link below to accept the invitation:')
        ->action('Accept Invitation', url("/accept-invitation/{$this->invitation->token}"))
        ->line('This invitation will expire in 7 days.');
}
```

---

## Migration Guide

To run the migration:

```bash
cd /home/calounx/repositories/mentat/chom
php artisan migrate
```

To rollback:
```bash
php artisan migrate:rollback --step=1
```

---

## Files Created/Modified

### Created Files:
1. `database/migrations/2026_01_02_000001_create_team_invitations_table.php`
2. `app/Models/TeamInvitation.php`
3. `app/Http/Requests/V1/Team/InviteMemberRequest.php`
4. `app/Http/Requests/V1/Team/UpdateMemberRequest.php`
5. `app/Http/Resources/V1/TeamMemberResource.php`
6. `app/Http/Resources/V1/TeamMemberCollection.php`
7. `app/Http/Resources/V1/TeamInvitationResource.php`
8. `app/Http/Resources/V1/TeamInvitationCollection.php`

### Modified Files:
1. `app/Http/Controllers/Api/V1/TeamController.php` - Complete rewrite with invitation system
2. `routes/api.php` - Updated team routes
3. `app/Models/Organization.php` - Added teamInvitations relationships

---

## Production Checklist

- [x] Database migration created
- [x] Model with relationships
- [x] Request validation classes
- [x] API Resource classes
- [x] Controller implementation
- [x] Routes registered
- [x] Authorization checks
- [x] Rate limiting configured
- [x] Audit logging
- [x] Error handling
- [ ] Email notifications (TODO)
- [ ] Unit tests (TODO)
- [ ] Integration tests (TODO)
- [ ] API documentation (Swagger/OpenAPI) (TODO)

---

## Support

For issues or questions:
1. Check error logs: `storage/logs/laravel.log`
2. Review audit logs for team operations
3. Verify database constraints and relationships
4. Test with different user roles

---

**Implementation Date:** 2026-01-02  
**Status:** Production Ready (except email notifications)  
**Version:** 1.0
