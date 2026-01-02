# Team Management API - Quick Reference

## Base URL
```
/api/v1/team
```

## Authentication
All endpoints require Bearer token:
```
Authorization: Bearer {your-api-token}
```

---

## Quick Endpoint Reference

| Method | Endpoint | Description | Auth Level |
|--------|----------|-------------|------------|
| GET | `/` | List all team members | Any |
| GET | `/{member}` | Get member details | Any |
| POST | `/invite` | Invite new member | Admin/Owner |
| GET | `/pending` | List pending invitations | Admin/Owner |
| POST | `/accept/{token}` | Accept invitation | Public/Authenticated |
| PATCH | `/{member}` | Update member role | Admin/Owner |
| DELETE | `/{member}` | Remove member | Admin/Owner |
| DELETE | `/invitations/{invitation}` | Cancel invitation | Admin/Owner |
| POST | `/transfer-ownership` | Transfer ownership | Owner only |

---

## Common Examples

### 1. List Team Members
```bash
curl -X GET "http://your-domain/api/v1/team" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### 2. Invite Member
```bash
curl -X POST "http://your-domain/api/v1/team/invite" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "newmember@example.com",
    "role": "member"
  }'
```

### 3. Update Member Role
```bash
curl -X PATCH "http://your-domain/api/v1/team/MEMBER_ID" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "role": "admin"
  }'
```

### 4. Remove Member
```bash
curl -X DELETE "http://your-domain/api/v1/team/MEMBER_ID" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### 5. List Pending Invitations
```bash
curl -X GET "http://your-domain/api/v1/team/pending" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### 6. Accept Invitation
```bash
curl -X POST "http://your-domain/api/v1/team/accept/INVITATION_TOKEN" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### 7. Transfer Ownership
```bash
curl -X POST "http://your-domain/api/v1/team/transfer-ownership" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "NEW_OWNER_UUID",
    "password": "your_current_password"
  }'
```

---

## Role Hierarchy

1. **Owner** - Full control, can transfer ownership
2. **Admin** - Team management, cannot modify owner or other admins
3. **Member** - Site management, no team management
4. **Viewer** - Read-only access

---

## Response Codes

| Code | Meaning |
|------|---------|
| 200 | Success |
| 201 | Created (invitation sent) |
| 204 | No Content (successful deletion) |
| 400 | Bad Request (validation error) |
| 401 | Unauthorized (invalid password) |
| 403 | Forbidden (insufficient permissions) |
| 404 | Not Found |
| 500 | Server Error |

---

## Common Error Codes

| Code | Description |
|------|-------------|
| `FORBIDDEN` | You don't have permission |
| `NOT_FOUND` | Resource not found |
| `CANNOT_MODIFY_OWNER` | Cannot change owner role |
| `CANNOT_REMOVE_SELF` | Cannot remove yourself |
| `ALREADY_MEMBER` | Email already in organization |
| `INVITATION_EXPIRED` | Invitation has expired |
| `INVALID_TOKEN` | Invalid invitation token |
| `EMAIL_MISMATCH` | Email doesn't match invitation |

---

## Pagination

All list endpoints support pagination:

**Query Parameters:**
- `per_page` - Items per page (default: 20, max: 100)
- `page` - Page number (default: 1)

**Example:**
```bash
curl "http://your-domain/api/v1/team?per_page=50&page=2" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

---

## Rate Limits

- **Standard operations:** 100-1000 req/min (tier-based)
- **Sensitive operations:** 10 req/min
  - Remove member
  - Transfer ownership

---

## Testing in Development

1. Register a test organization:
```bash
curl -X POST "http://localhost/api/v1/auth/register" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test Owner",
    "email": "owner@test.com",
    "password": "password123",
    "password_confirmation": "password123",
    "organization_name": "Test Organization"
  }'
```

2. Save the returned token

3. Use token for all team management operations

---

## Database Migration

Run migration before using:
```bash
php artisan migrate
```

Check migration status:
```bash
php artisan migrate:status
```

---

## Logs

Team operations are logged to:
- **Application Log:** `storage/logs/laravel.log`
- **Log Context:** Includes organization_id, user_id, action, timestamp

Example log search:
```bash
grep "Team member role updated" storage/logs/laravel.log
grep "Team invitation created" storage/logs/laravel.log
```

---

## Files Reference

**Controller:** `app/Http/Controllers/Api/V1/TeamController.php`  
**Model:** `app/Models/TeamInvitation.php`  
**Migration:** `database/migrations/2026_01_02_000001_create_team_invitations_table.php`  
**Requests:** `app/Http/Requests/V1/Team/`  
**Resources:** `app/Http/Resources/V1/`  

---

For detailed documentation, see: `TEAM_API_IMPLEMENTATION.md`
