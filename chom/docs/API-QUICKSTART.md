# CHOM API Quick Start Guide

Welcome to the CHOM API! This guide will help you get started with the API in minutes.

## Table of Contents
- [Authentication](#authentication)
- [Your First API Call](#your-first-api-call)
- [Creating a WordPress Site](#creating-a-wordpress-site)
- [Managing Backups](#managing-backups)
- [Common Patterns](#common-patterns)
- [Error Handling](#error-handling)
- [Rate Limiting](#rate-limiting)
- [Next Steps](#next-steps)

## Authentication

CHOM uses Laravel Sanctum for API authentication with Bearer tokens.

### 1. Register a New Account

```bash
curl -X POST https://api.chom.example.com/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{
    "name": "John Doe",
    "email": "john@example.com",
    "password": "SecurePassword123!",
    "password_confirmation": "SecurePassword123!",
    "organization_name": "ACME Corporation"
  }'
```

**Response:**
```json
{
  "success": true,
  "data": {
    "user": {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "John Doe",
      "email": "john@example.com",
      "role": "owner"
    },
    "organization": {
      "id": "850e8400-e29b-41d4-a716-446655440000",
      "name": "ACME Corporation",
      "slug": "acme-corporation-a1b2c3"
    },
    "tenant": {
      "id": "950e8400-e29b-41d4-a716-446655440000",
      "name": "Default",
      "tier": "starter"
    },
    "token": "1|abcdefghijklmnopqrstuvwxyz1234567890"
  }
}
```

### 2. Save Your Token

Save the `token` value from the response. You'll need it for all authenticated requests.

### 3. Login (Existing Users)

```bash
curl -X POST https://api.chom.example.com/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{
    "email": "john@example.com",
    "password": "SecurePassword123!"
  }'
```

## Your First API Call

Test your authentication with a simple request:

```bash
curl -X GET https://api.chom.example.com/api/v1/auth/me \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response:**
```json
{
  "success": true,
  "data": {
    "user": {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "John Doe",
      "email": "john@example.com",
      "role": "owner",
      "email_verified_at": "2024-01-15T10:30:00Z"
    },
    "organization": {
      "id": "850e8400-e29b-41d4-a716-446655440000",
      "name": "ACME Corporation",
      "slug": "acme-corporation-a1b2c3"
    },
    "tenant": {
      "id": "950e8400-e29b-41d4-a716-446655440000",
      "name": "Default",
      "tier": "starter",
      "status": "active"
    }
  }
}
```

## Creating a WordPress Site

### Step 1: Create the Site

```bash
curl -X POST https://api.chom.example.com/api/v1/sites \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{
    "domain": "myblog.com",
    "site_type": "wordpress",
    "php_version": "8.2",
    "ssl_enabled": true
  }'
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "660e8400-e29b-41d4-a716-446655440000",
    "domain": "myblog.com",
    "url": "https://myblog.com",
    "site_type": "wordpress",
    "php_version": "8.2",
    "ssl_enabled": true,
    "ssl_expires_at": null,
    "status": "creating",
    "storage_used_mb": 0,
    "created_at": "2024-01-15T10:35:00Z",
    "updated_at": "2024-01-15T10:35:00Z"
  },
  "message": "Site is being created."
}
```

### Step 2: Check Site Status

Site provisioning is asynchronous. Poll the site endpoint to check status:

```bash
curl -X GET https://api.chom.example.com/api/v1/sites/660e8400-e29b-41d4-a716-446655440000 \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Accept: application/json"
```

Status will change from `creating` → `active` when ready (usually 2-5 minutes).

### Step 3: Issue SSL Certificate

Once the site is `active`, issue an SSL certificate:

```bash
curl -X POST https://api.chom.example.com/api/v1/sites/660e8400-e29b-41d4-a716-446655440000/ssl \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Accept: application/json"
```

## Managing Backups

### Create a Backup

```bash
curl -X POST https://api.chom.example.com/api/v1/backups \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{
    "site_id": "660e8400-e29b-41d4-a716-446655440000",
    "backup_type": "full",
    "retention_days": 30
  }'
```

### List Backups

```bash
curl -X GET "https://api.chom.example.com/api/v1/backups?site_id=660e8400-e29b-41d4-a716-446655440000" \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Accept: application/json"
```

### Download a Backup

```bash
curl -X GET https://api.chom.example.com/api/v1/backups/750e8400-e29b-41d4-a716-446655440000/download \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response:**
```json
{
  "success": true,
  "data": {
    "download_url": "https://storage.example.com/backups/temp-url?token=abc123",
    "expires_at": "2024-01-15T11:00:00Z"
  }
}
```

Use the `download_url` to download the backup file (valid for 15 minutes).

### Restore from Backup

```bash
curl -X POST https://api.chom.example.com/api/v1/backups/750e8400-e29b-41d4-a716-446655440000/restore \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Accept: application/json"
```

## Common Patterns

### Pagination

All list endpoints support pagination:

```bash
curl -X GET "https://api.chom.example.com/api/v1/sites?page=2&per_page=20" \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Accept: application/json"
```

**Response includes pagination metadata:**
```json
{
  "success": true,
  "data": [...],
  "meta": {
    "pagination": {
      "current_page": 2,
      "per_page": 20,
      "total": 42,
      "total_pages": 3
    }
  }
}
```

### Filtering

Many endpoints support filtering:

```bash
# Filter sites by status
curl -X GET "https://api.chom.example.com/api/v1/sites?status=active" \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Accept: application/json"

# Search sites by domain
curl -X GET "https://api.chom.example.com/api/v1/sites?search=myblog" \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Accept: application/json"

# Filter backups by type
curl -X GET "https://api.chom.example.com/api/v1/backups?type=database" \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Accept: application/json"
```

### Async Operations

Some operations are asynchronous and return immediately while processing in the background:

- **Site Creation** - Returns `status: "creating"`, poll until `status: "active"`
- **SSL Certificate Issuance** - Returns immediately, certificate issued in background
- **Backups** - Returns immediately, backup processed asynchronously
- **Restore** - Returns immediately, restore happens in background

**Polling Pattern:**
```bash
# Create resource
SITE_ID=$(curl -X POST ... | jq -r '.data.id')

# Poll for completion (with delay)
while true; do
  STATUS=$(curl -X GET "https://api.chom.example.com/api/v1/sites/$SITE_ID" \
    -H "Authorization: Bearer $TOKEN" | jq -r '.data.status')

  if [ "$STATUS" = "active" ]; then
    echo "Site is ready!"
    break
  fi

  echo "Status: $STATUS - waiting..."
  sleep 10
done
```

## Error Handling

All errors follow a consistent format:

```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable error message",
    "details": {
      "additional": "context"
    }
  }
}
```

### Common Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `INVALID_CREDENTIALS` | 401 | Login failed - invalid email/password |
| `SITE_LIMIT_EXCEEDED` | 403 | Cannot create more sites on current plan |
| `SITE_CREATION_FAILED` | 500 | Site provisioning failed |
| `BACKUP_NOT_READY` | 400 | Backup is still processing |
| `BACKUP_EXPIRED` | 400 | Backup retention period has expired |
| `FORBIDDEN` | 403 | Insufficient permissions for this action |
| `CANNOT_MODIFY_OWNER` | 400 | Cannot modify organization owner's role |

### Validation Errors

Validation errors return field-specific messages:

```json
{
  "success": false,
  "message": "The given data was invalid.",
  "errors": {
    "email": ["The email field is required."],
    "password": ["The password must be at least 8 characters."]
  }
}
```

## Rate Limiting

The API implements rate limiting to ensure fair usage:

| Endpoint Type | Limit | Window |
|---------------|-------|--------|
| Authentication (`/auth/*`) | 5 requests | 1 minute |
| Standard API | 60 requests | 1 minute |
| Sensitive operations (delete, backup, restore) | 10 requests | 1 minute |

**Rate limit headers:**
```
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 59
Retry-After: 30
```

When rate limited, you'll receive a `429 Too Many Requests` response:
```json
{
  "message": "Too Many Attempts.",
  "retry_after": 30
}
```

## Next Steps

### 1. Team Management

Invite team members and manage roles:

```bash
# Invite a team member
curl -X POST https://api.chom.example.com/api/v1/team/invitations \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "teammate@example.com",
    "role": "member",
    "name": "Team Member"
  }'

# List team members
curl -X GET https://api.chom.example.com/api/v1/team/members \
  -H "Authorization: Bearer YOUR_TOKEN_HERE"
```

### 2. Site Management

Explore advanced site operations:

```bash
# Disable a site temporarily
curl -X POST https://api.chom.example.com/api/v1/sites/$SITE_ID/disable \
  -H "Authorization: Bearer YOUR_TOKEN_HERE"

# Re-enable the site
curl -X POST https://api.chom.example.com/api/v1/sites/$SITE_ID/enable \
  -H "Authorization: Bearer YOUR_TOKEN_HERE"

# Update PHP version
curl -X PATCH https://api.chom.example.com/api/v1/sites/$SITE_ID \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{"php_version": "8.4"}'

# Get site metrics
curl -X GET https://api.chom.example.com/api/v1/sites/$SITE_ID/metrics \
  -H "Authorization: Bearer YOUR_TOKEN_HERE"
```

### 3. Organization Settings

Manage organization-level settings:

```bash
# Get organization details
curl -X GET https://api.chom.example.com/api/v1/organization \
  -H "Authorization: Bearer YOUR_TOKEN_HERE"

# Update organization (owner only)
curl -X PATCH https://api.chom.example.com/api/v1/organization \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "New Organization Name",
    "billing_email": "billing@example.com"
  }'
```

### 4. Use the Postman Collection

Import the provided Postman collection for easier API testing:

1. Download `postman_collection.json`
2. Import into Postman
3. Set up environment variables:
   - `base_url`: https://api.chom.example.com/api/v1
   - `api_token`: Your authentication token
4. Start making requests!

The collection includes pre-configured requests and automatic token management.

## Resources

- **Full API Reference**: See `openapi.yaml` for complete API specification
- **Postman Collection**: `postman_collection.json`
- **API Changelog**: `docs/API-CHANGELOG.md`
- **Versioning Policy**: `docs/API-VERSIONING.md`
- **Interactive Docs**: https://api.chom.example.com/api/documentation (Swagger UI)

## Support

Need help? Contact us:
- Email: support@chom.example.com
- Documentation: https://docs.chom.example.com
- Status Page: https://status.chom.example.com

## Example: Complete Workflow

Here's a complete example of provisioning a WordPress site with backup:

```bash
#!/bin/bash

# Configuration
BASE_URL="https://api.chom.example.com/api/v1"
TOKEN="your-token-here"

# 1. Create a new site
echo "Creating WordPress site..."
SITE_ID=$(curl -s -X POST "$BASE_URL/sites" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "domain": "myblog.com",
    "site_type": "wordpress",
    "php_version": "8.2",
    "ssl_enabled": true
  }' | jq -r '.data.id')

echo "Site ID: $SITE_ID"

# 2. Wait for site to be active
echo "Waiting for site provisioning..."
while true; do
  STATUS=$(curl -s -X GET "$BASE_URL/sites/$SITE_ID" \
    -H "Authorization: Bearer $TOKEN" | jq -r '.data.status')

  if [ "$STATUS" = "active" ]; then
    echo "Site is active!"
    break
  fi

  echo "Current status: $STATUS"
  sleep 10
done

# 3. Issue SSL certificate
echo "Issuing SSL certificate..."
curl -s -X POST "$BASE_URL/sites/$SITE_ID/ssl" \
  -H "Authorization: Bearer $TOKEN" | jq '.'

# 4. Create a backup
echo "Creating backup..."
BACKUP_ID=$(curl -s -X POST "$BASE_URL/backups" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"site_id\": \"$SITE_ID\",
    \"backup_type\": \"full\",
    \"retention_days\": 30
  }" | jq -r '.data.id')

echo "Backup ID: $BACKUP_ID"
echo "Complete! Site is ready at https://myblog.com"
```

Happy coding! 🚀
