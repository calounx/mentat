# CHOM API Cheat Sheet

Quick reference for all CHOM API endpoints, parameters, and responses. Bookmark this page for fast lookups.

## Table of Contents

- [Base URL & Authentication](#base-url--authentication)
- [Rate Limits](#rate-limits)
- [Authentication Endpoints](#authentication-endpoints)
- [Sites Management](#sites-management)
- [Backups Management](#backups-management)
- [Team Management](#team-management)
- [Organization Management](#organization-management)
- [Health Check](#health-check)
- [Pagination](#pagination)
- [Common Response Formats](#common-response-formats)

---

## Base URL & Authentication

**Base URL:** `https://api.chom.example.com/api/v1`

**Authentication:** Include Bearer token in all authenticated requests:
```bash
Authorization: Bearer YOUR_TOKEN_HERE
```

**Content Type:** All requests and responses use JSON:
```bash
Content-Type: application/json
```

---

## Rate Limits

| Endpoint Type | Limit | Window |
|---------------|-------|--------|
| Authentication (`/auth/*`) | 5 requests | 1 minute |
| Standard API | 60 requests | 1 minute |
| Sensitive Operations (delete, backup, restore) | 10 requests | 1 minute |

**Headers Returned:**
- `X-RateLimit-Limit` - Total requests allowed
- `X-RateLimit-Remaining` - Remaining requests
- `X-RateLimit-Reset` - Time when limit resets (Unix timestamp)

---

## Authentication Endpoints

### Register New User

| Field | Value |
|-------|-------|
| **Method** | `POST` |
| **Path** | `/auth/register` |
| **Auth Required** | No |

**Required Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | string | User's full name (max 255 chars) |
| `email` | string | Valid email address |
| `password` | string | Password (min 8 chars) |
| `password_confirmation` | string | Must match password |
| `organization_name` | string | Organization name (max 255 chars) |

**Example:**
```bash
POST /auth/register
{
  "name": "John Doe",
  "email": "john@example.com",
  "password": "SecurePass123!",
  "password_confirmation": "SecurePass123!",
  "organization_name": "ACME Corp"
}
```

**Response:** `201 Created` - Returns user, organization, tenant, and token

---

### Login

| Field | Value |
|-------|-------|
| **Method** | `POST` |
| **Path** | `/auth/login` |
| **Auth Required** | No |

**Required Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `email` | string | User email |
| `password` | string | User password |

**Example:**
```bash
POST /auth/login
{
  "email": "john@example.com",
  "password": "SecurePass123!"
}
```

**Response:** `200 OK` - Returns user, organization, and token

---

### Get Current User

| Field | Value |
|-------|-------|
| **Method** | `GET` |
| **Path** | `/auth/me` |
| **Auth Required** | Yes |

**Example:**
```bash
GET /auth/me
```

**Response:** `200 OK` - Returns user, organization, and tenant details

---

### Refresh Token

| Field | Value |
|-------|-------|
| **Method** | `POST` |
| **Path** | `/auth/refresh` |
| **Auth Required** | Yes |

**Example:**
```bash
POST /auth/refresh
```

**Response:** `200 OK` - Returns new token

---

### Logout

| Field | Value |
|-------|-------|
| **Method** | `POST` |
| **Path** | `/auth/logout` |
| **Auth Required** | Yes |

**Example:**
```bash
POST /auth/logout
```

**Response:** `200 OK` - Token is revoked

---

## Sites Management

### List Sites

| Field | Value |
|-------|-------|
| **Method** | `GET` |
| **Path** | `/sites` |
| **Auth Required** | Yes |

**Optional Parameters:**
| Parameter | Type | Options | Description |
|-----------|------|---------|-------------|
| `status` | string | `creating`, `active`, `disabled`, `failed`, `deleting` | Filter by status |
| `type` | string | `wordpress`, `html`, `laravel` | Filter by type |
| `search` | string | - | Search by domain name |
| `page` | integer | Default: 1 | Page number |
| `per_page` | integer | Default: 20, Max: 100 | Items per page |

**Example:**
```bash
GET /sites?status=active&per_page=50
```

**Response:** `200 OK` - Returns array of sites with pagination

---

### Create Site

| Field | Value |
|-------|-------|
| **Method** | `POST` |
| **Path** | `/sites` |
| **Auth Required** | Yes |

**Required Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `domain` | string | Valid domain name (max 253 chars) |

**Optional Parameters:**
| Parameter | Type | Options | Default |
|-----------|------|---------|---------|
| `site_type` | string | `wordpress`, `html`, `laravel` | `wordpress` |
| `php_version` | string | `8.2`, `8.4` | `8.2` |
| `ssl_enabled` | boolean | `true`, `false` | `true` |

**Example:**
```bash
POST /sites
{
  "domain": "mysite.com",
  "site_type": "wordpress",
  "php_version": "8.2",
  "ssl_enabled": true
}
```

**Response:** `201 Created` - Returns site details (status: `creating`)

---

### Get Site Details

| Field | Value |
|-------|-------|
| **Method** | `GET` |
| **Path** | `/sites/{id}` |
| **Auth Required** | Yes |

**Path Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | UUID | Site ID |

**Example:**
```bash
GET /sites/550e8400-e29b-41d4-a716-446655440000
```

**Response:** `200 OK` - Returns detailed site information

---

### Update Site

| Field | Value |
|-------|-------|
| **Method** | `PATCH` |
| **Path** | `/sites/{id}` |
| **Auth Required** | Yes |

**Optional Parameters:**
| Parameter | Type | Options |
|-----------|------|---------|
| `php_version` | string | `8.2`, `8.4` |
| `settings` | object | Custom settings object |

**Example:**
```bash
PATCH /sites/550e8400-e29b-41d4-a716-446655440000
{
  "php_version": "8.4"
}
```

**Response:** `200 OK` - Returns updated site

---

### Delete Site

| Field | Value |
|-------|-------|
| **Method** | `DELETE` |
| **Path** | `/sites/{id}` |
| **Auth Required** | Yes |
| **Rate Limited** | Yes (10/min) |

**Example:**
```bash
DELETE /sites/550e8400-e29b-41d4-a716-446655440000
```

**Response:** `200 OK` - Site deleted (permanent action)

---

### Enable Site

| Field | Value |
|-------|-------|
| **Method** | `POST` |
| **Path** | `/sites/{id}/enable` |
| **Auth Required** | Yes |

**Example:**
```bash
POST /sites/550e8400-e29b-41d4-a716-446655440000/enable
```

**Response:** `200 OK` - Site enabled

---

### Disable Site

| Field | Value |
|-------|-------|
| **Method** | `POST` |
| **Path** | `/sites/{id}/disable` |
| **Auth Required** | Yes |

**Example:**
```bash
POST /sites/550e8400-e29b-41d4-a716-446655440000/disable
```

**Response:** `200 OK` - Site disabled

---

### Issue SSL Certificate

| Field | Value |
|-------|-------|
| **Method** | `POST` |
| **Path** | `/sites/{id}/ssl` |
| **Auth Required** | Yes |

**Example:**
```bash
POST /sites/550e8400-e29b-41d4-a716-446655440000/ssl
```

**Response:** `200 OK` - SSL issuance initiated

---

### Get Site Metrics

| Field | Value |
|-------|-------|
| **Method** | `GET` |
| **Path** | `/sites/{id}/metrics` |
| **Auth Required** | Yes |

**Example:**
```bash
GET /sites/550e8400-e29b-41d4-a716-446655440000/metrics
```

**Response:** `200 OK` - Returns performance metrics

---

## Backups Management

### List All Backups

| Field | Value |
|-------|-------|
| **Method** | `GET` |
| **Path** | `/backups` |
| **Auth Required** | Yes |

**Optional Parameters:**
| Parameter | Type | Options | Description |
|-----------|------|---------|-------------|
| `site_id` | UUID | - | Filter by site |
| `type` | string | `full`, `database`, `files` | Filter by type |
| `page` | integer | Default: 1 | Page number |
| `per_page` | integer | Default: 20, Max: 100 | Items per page |

**Example:**
```bash
GET /backups?site_id=550e8400-e29b-41d4-a716-446655440000&type=full
```

**Response:** `200 OK` - Returns array of backups

---

### Create Backup

| Field | Value |
|-------|-------|
| **Method** | `POST` |
| **Path** | `/backups` |
| **Auth Required** | Yes |
| **Rate Limited** | Yes (10/min) |

**Required Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `site_id` | UUID | Site to backup |

**Optional Parameters:**
| Parameter | Type | Options | Default |
|-----------|------|---------|---------|
| `backup_type` | string | `full`, `database`, `files` | `full` |
| `retention_days` | integer | 1-365 | `30` |

**Example:**
```bash
POST /backups
{
  "site_id": "550e8400-e29b-41d4-a716-446655440000",
  "backup_type": "full",
  "retention_days": 30
}
```

**Response:** `201 Created` - Backup queued

---

### Get Backup Details

| Field | Value |
|-------|-------|
| **Method** | `GET` |
| **Path** | `/backups/{id}` |
| **Auth Required** | Yes |

**Example:**
```bash
GET /backups/650e8400-e29b-41d4-a716-446655440000
```

**Response:** `200 OK` - Returns backup details

---

### Delete Backup

| Field | Value |
|-------|-------|
| **Method** | `DELETE` |
| **Path** | `/backups/{id}` |
| **Auth Required** | Yes |
| **Rate Limited** | Yes (10/min) |

**Example:**
```bash
DELETE /backups/650e8400-e29b-41d4-a716-446655440000
```

**Response:** `200 OK` - Backup deleted

---

### Download Backup

| Field | Value |
|-------|-------|
| **Method** | `GET` |
| **Path** | `/backups/{id}/download` |
| **Auth Required** | Yes |

**Example:**
```bash
GET /backups/650e8400-e29b-41d4-a716-446655440000/download
```

**Response:** `200 OK` - Returns temporary download URL (valid 15 minutes)

---

### Restore from Backup

| Field | Value |
|-------|-------|
| **Method** | `POST` |
| **Path** | `/backups/{id}/restore` |
| **Auth Required** | Yes |
| **Rate Limited** | Yes (10/min) |

**Example:**
```bash
POST /backups/650e8400-e29b-41d4-a716-446655440000/restore
```

**Response:** `200 OK` - Restore initiated

---

### List Site Backups

| Field | Value |
|-------|-------|
| **Method** | `GET` |
| **Path** | `/sites/{siteId}/backups` |
| **Auth Required** | Yes |

**Optional Parameters:**
| Parameter | Type | Default |
|-----------|------|---------|
| `page` | integer | 1 |
| `per_page` | integer | 20 |

**Example:**
```bash
GET /sites/550e8400-e29b-41d4-a716-446655440000/backups
```

**Response:** `200 OK` - Returns site backups

---

### Create Site Backup

| Field | Value |
|-------|-------|
| **Method** | `POST` |
| **Path** | `/sites/{siteId}/backups` |
| **Auth Required** | Yes |
| **Rate Limited** | Yes (10/min) |

**Optional Parameters:**
| Parameter | Type | Options | Default |
|-----------|------|---------|---------|
| `backup_type` | string | `full`, `database`, `files` | `full` |
| `retention_days` | integer | 1-365 | `30` |

**Example:**
```bash
POST /sites/550e8400-e29b-41d4-a716-446655440000/backups
{
  "backup_type": "full",
  "retention_days": 30
}
```

**Response:** `201 Created` - Backup queued

---

## Team Management

### List Team Members

| Field | Value |
|-------|-------|
| **Method** | `GET` |
| **Path** | `/team/members` |
| **Auth Required** | Yes |

**Optional Parameters:**
| Parameter | Type | Default |
|-----------|------|---------|
| `page` | integer | 1 |
| `per_page` | integer | 20 |

**Example:**
```bash
GET /team/members?page=1&per_page=20
```

**Response:** `200 OK` - Returns team members

---

### Get Team Member

| Field | Value |
|-------|-------|
| **Method** | `GET` |
| **Path** | `/team/members/{id}` |
| **Auth Required** | Yes |

**Example:**
```bash
GET /team/members/750e8400-e29b-41d4-a716-446655440000
```

**Response:** `200 OK` - Returns member details

---

### Update Team Member Role

| Field | Value |
|-------|-------|
| **Method** | `PATCH` |
| **Path** | `/team/members/{id}` |
| **Auth Required** | Yes (Admin/Owner) |

**Required Parameters:**
| Parameter | Type | Options |
|-----------|------|---------|
| `role` | string | `admin`, `member`, `viewer` |

**Example:**
```bash
PATCH /team/members/750e8400-e29b-41d4-a716-446655440000
{
  "role": "admin"
}
```

**Response:** `200 OK` - Role updated

---

### Remove Team Member

| Field | Value |
|-------|-------|
| **Method** | `DELETE` |
| **Path** | `/team/members/{id}` |
| **Auth Required** | Yes (Admin/Owner) |

**Example:**
```bash
DELETE /team/members/750e8400-e29b-41d4-a716-446655440000
```

**Response:** `200 OK` - Member removed

---

### List Invitations

| Field | Value |
|-------|-------|
| **Method** | `GET` |
| **Path** | `/team/invitations` |
| **Auth Required** | Yes |

**Example:**
```bash
GET /team/invitations
```

**Response:** `200 OK` - Returns pending invitations

---

### Invite Team Member

| Field | Value |
|-------|-------|
| **Method** | `POST` |
| **Path** | `/team/invitations` |
| **Auth Required** | Yes (Admin/Owner) |

**Required Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `email` | string | Invitee email |
| `role` | string | `admin`, `member`, or `viewer` |

**Optional Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | string | Invitee name |

**Example:**
```bash
POST /team/invitations
{
  "email": "newuser@example.com",
  "role": "member",
  "name": "Jane Doe"
}
```

**Response:** `201 Created` - Invitation sent

---

### Cancel Invitation

| Field | Value |
|-------|-------|
| **Method** | `DELETE` |
| **Path** | `/team/invitations/{id}` |
| **Auth Required** | Yes (Admin/Owner) |

**Example:**
```bash
DELETE /team/invitations/invitation-uuid-here
```

**Response:** `200 OK` - Invitation cancelled

---

### Transfer Ownership

| Field | Value |
|-------|-------|
| **Method** | `POST` |
| **Path** | `/team/transfer-ownership` |
| **Auth Required** | Yes (Owner only) |

**Required Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `user_id` | UUID | New owner's user ID |
| `password` | string | Current password for confirmation |

**Example:**
```bash
POST /team/transfer-ownership
{
  "user_id": "750e8400-e29b-41d4-a716-446655440000",
  "password": "CurrentPassword123!"
}
```

**Response:** `200 OK` - Ownership transferred

---

## Organization Management

### Get Organization

| Field | Value |
|-------|-------|
| **Method** | `GET` |
| **Path** | `/organization` |
| **Auth Required** | Yes |

**Example:**
```bash
GET /organization
```

**Response:** `200 OK` - Returns organization details

---

### Update Organization

| Field | Value |
|-------|-------|
| **Method** | `PATCH` |
| **Path** | `/organization` |
| **Auth Required** | Yes (Owner only) |

**Optional Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | string | Organization name (max 255 chars) |
| `billing_email` | string | Billing email address |

**Example:**
```bash
PATCH /organization
{
  "name": "ACME Corporation Ltd",
  "billing_email": "billing@acme.com"
}
```

**Response:** `200 OK` - Organization updated

---

## Health Check

### API Health Status

| Field | Value |
|-------|-------|
| **Method** | `GET` |
| **Path** | `/health` |
| **Auth Required** | No |

**Example:**
```bash
GET /health
```

**Response:** `200 OK`
```json
{
  "status": "ok",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

---

## Pagination

All list endpoints support pagination with these parameters:

| Parameter | Type | Default | Max | Description |
|-----------|------|---------|-----|-------------|
| `page` | integer | 1 | - | Page number |
| `per_page` | integer | 20 | 100 | Items per page |

**Pagination Metadata in Response:**
```json
{
  "meta": {
    "pagination": {
      "current_page": 1,
      "per_page": 20,
      "total": 42,
      "total_pages": 3
    }
  }
}
```

---

## Common Response Formats

### Success Response
```json
{
  "success": true,
  "data": { /* resource data */ },
  "message": "Optional success message"
}
```

### Error Response
```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable error message",
    "details": {}
  }
}
```

### Validation Error Response
```json
{
  "success": false,
  "message": "The given data was invalid.",
  "errors": {
    "field_name": [
      "Error message 1",
      "Error message 2"
    ]
  }
}
```

---

## Status Codes Reference

| Code | Status | Meaning |
|------|--------|---------|
| 200 | OK | Request successful |
| 201 | Created | Resource created successfully |
| 400 | Bad Request | Invalid request format |
| 401 | Unauthorized | Authentication required or failed |
| 403 | Forbidden | Insufficient permissions |
| 404 | Not Found | Resource not found |
| 422 | Unprocessable Entity | Validation failed |
| 429 | Too Many Requests | Rate limit exceeded |
| 500 | Internal Server Error | Server error occurred |

---

## Quick Tips

> **Tip:** Save your token as an environment variable:
> ```bash
> export CHOM_TOKEN="your-token-here"
> ```

> **Tip:** Use `jq` to prettify JSON responses:
> ```bash
> curl ... | jq .
> ```

> **Tip:** Check rate limit headers in responses:
> ```bash
> curl -I https://api.chom.example.com/api/v1/sites
> ```

> **Warning:** Site deletion and backup restore operations are irreversible. Always double-check before executing.

---

**Need more details?** Check out:
- [Quick Start Guide](./QUICK-START.md) - Get started in 5 minutes
- [Examples](./EXAMPLES.md) - Real-world code samples
- [Error Guide](./ERRORS.md) - Comprehensive error reference
- [OpenAPI Spec](../../openapi.yaml) - Complete API specification
