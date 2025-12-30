# CHOM API Quick Start

Get up and running with the CHOM API in 5 minutes. This guide will walk you through authentication and your first API calls.

## Table of Contents

- [Prerequisites](#prerequisites)
- [1. Authentication](#1-authentication)
- [2. Your First API Call](#2-your-first-api-call)
- [3. Common Operations](#3-common-operations)
- [4. Error Handling Basics](#4-error-handling-basics)
- [Next Steps](#next-steps)

## Prerequisites

- A CHOM account (or create one via the API)
- A terminal with `curl` installed
- Base URL: `https://api.chom.example.com/api/v1` (or your instance URL)

> **Note:** Replace `https://api.chom.example.com/api/v1` with your actual CHOM instance URL throughout this guide.

---

## 1. Authentication

CHOM uses Bearer token authentication. You'll need to register or login to get your API token.

### Option A: Register a New Account

Create a new user account and organization in one step:

```bash
curl -X POST https://api.chom.example.com/api/v1/auth/register \
  -H "Content-Type: application/json" \
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
      "id": "750e8400-e29b-41d4-a716-446655440000",
      "name": "John Doe",
      "email": "john@example.com",
      "role": "owner"
    },
    "organization": {
      "id": "850e8400-e29b-41d4-a716-446655440000",
      "name": "ACME Corporation",
      "slug": "acme-corporation-a1b2c3"
    },
    "token": "1|abcdefghijklmnopqrstuvwxyz1234567890"
  }
}
```

### Option B: Login to Existing Account

If you already have an account:

```bash
curl -X POST https://api.chom.example.com/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "john@example.com",
    "password": "SecurePassword123!"
  }'
```

**Response:**
```json
{
  "success": true,
  "data": {
    "user": {
      "id": "750e8400-e29b-41d4-a716-446655440000",
      "name": "John Doe",
      "email": "john@example.com",
      "role": "owner"
    },
    "token": "1|abcdefghijklmnopqrstuvwxyz1234567890"
  }
}
```

### Save Your Token

> **Important:** Save the token from the response. You'll use it for all subsequent API calls.

```bash
# Export the token as an environment variable for convenience
export CHOM_TOKEN="1|abcdefghijklmnopqrstuvwxyz1234567890"
```

---

## 2. Your First API Call

Let's verify your authentication by retrieving your user details:

```bash
curl -X GET https://api.chom.example.com/api/v1/auth/me \
  -H "Authorization: Bearer $CHOM_TOKEN" \
  -H "Content-Type: application/json"
```

**Response:**
```json
{
  "success": true,
  "data": {
    "user": {
      "id": "750e8400-e29b-41d4-a716-446655440000",
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

> **Success!** If you received a response like above, you're authenticated and ready to use the API.

---

## 3. Common Operations

Now let's perform the most common operations: creating, reading, updating, and deleting sites.

### Create a WordPress Site

```bash
curl -X POST https://api.chom.example.com/api/v1/sites \
  -H "Authorization: Bearer $CHOM_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "domain": "mysite.com",
    "site_type": "wordpress",
    "php_version": "8.2",
    "ssl_enabled": true
  }'
```

**Response:**
```json
{
  "success": true,
  "message": "Site is being created.",
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "domain": "mysite.com",
    "url": "https://mysite.com",
    "site_type": "wordpress",
    "php_version": "8.2",
    "ssl_enabled": true,
    "status": "creating",
    "created_at": "2024-01-15T10:30:00Z"
  }
}
```

> **Note:** Site creation is asynchronous. The status will be `creating` initially and will change to `active` once complete.

### List All Sites

```bash
curl -X GET https://api.chom.example.com/api/v1/sites \
  -H "Authorization: Bearer $CHOM_TOKEN"
```

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "domain": "mysite.com",
      "url": "https://mysite.com",
      "site_type": "wordpress",
      "status": "active",
      "created_at": "2024-01-15T10:30:00Z"
    }
  ],
  "meta": {
    "pagination": {
      "current_page": 1,
      "per_page": 20,
      "total": 1,
      "total_pages": 1
    }
  }
}
```

### Get Site Details

```bash
curl -X GET https://api.chom.example.com/api/v1/sites/550e8400-e29b-41d4-a716-446655440000 \
  -H "Authorization: Bearer $CHOM_TOKEN"
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "domain": "mysite.com",
    "url": "https://mysite.com",
    "site_type": "wordpress",
    "php_version": "8.2",
    "ssl_enabled": true,
    "status": "active",
    "storage_used_mb": 245,
    "db_name": "wp_mysite_com",
    "document_root": "/var/www/mysite.com",
    "recent_backups": [
      {
        "id": "650e8400-e29b-41d4-a716-446655440000",
        "type": "full",
        "size": "1.2 GB",
        "created_at": "2024-01-14T10:30:00Z"
      }
    ]
  }
}
```

### Update Site Settings

```bash
curl -X PATCH https://api.chom.example.com/api/v1/sites/550e8400-e29b-41d4-a716-446655440000 \
  -H "Authorization: Bearer $CHOM_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "php_version": "8.4"
  }'
```

### Delete a Site

```bash
curl -X DELETE https://api.chom.example.com/api/v1/sites/550e8400-e29b-41d4-a716-446655440000 \
  -H "Authorization: Bearer $CHOM_TOKEN"
```

**Response:**
```json
{
  "success": true,
  "message": "Site deleted successfully."
}
```

> **Warning:** Site deletion is permanent and cannot be undone. All associated data including backups will be deleted.

### Create a Backup

```bash
curl -X POST https://api.chom.example.com/api/v1/sites/550e8400-e29b-41d4-a716-446655440000/backups \
  -H "Authorization: Bearer $CHOM_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "backup_type": "full",
    "retention_days": 30
  }'
```

**Response:**
```json
{
  "success": true,
  "message": "Backup has been queued for processing.",
  "data": {
    "id": "650e8400-e29b-41d4-a716-446655440000",
    "site_id": "550e8400-e29b-41d4-a716-446655440000",
    "backup_type": "full",
    "is_ready": false,
    "created_at": "2024-01-15T10:30:00Z"
  }
}
```

---

## 4. Error Handling Basics

All errors follow a consistent format. Here's what a typical error looks like:

### Validation Error Example

```bash
# Missing required field
curl -X POST https://api.chom.example.com/api/v1/sites \
  -H "Authorization: Bearer $CHOM_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "site_type": "wordpress"
  }'
```

**Error Response:**
```json
{
  "success": false,
  "message": "The given data was invalid.",
  "errors": {
    "domain": [
      "The domain field is required."
    ]
  }
}
```

### Authentication Error Example

```bash
# Invalid or missing token
curl -X GET https://api.chom.example.com/api/v1/sites \
  -H "Authorization: Bearer invalid-token"
```

**Error Response:**
```json
{
  "success": false,
  "error": {
    "code": "UNAUTHENTICATED",
    "message": "Authentication token is invalid or expired."
  }
}
```

### Common HTTP Status Codes

| Status Code | Meaning | Common Causes |
|-------------|---------|---------------|
| `200` | Success | Request completed successfully |
| `201` | Created | Resource created successfully |
| `400` | Bad Request | Invalid request format or parameters |
| `401` | Unauthorized | Missing or invalid authentication token |
| `403` | Forbidden | Insufficient permissions |
| `404` | Not Found | Resource doesn't exist |
| `422` | Validation Error | Request validation failed |
| `429` | Too Many Requests | Rate limit exceeded |
| `500` | Server Error | Internal server error |

> **Tip:** Always check the `success` field in the response. If it's `false`, check the `error` or `errors` field for details.

---

## Next Steps

Now that you've mastered the basics, explore more:

- **[API Cheat Sheet](./CHEAT-SHEET.md)** - Quick reference for all endpoints
- **[Real-world Examples](./EXAMPLES.md)** - Code samples in multiple languages
- **[Error Handling Guide](./ERRORS.md)** - Comprehensive error reference
- **[OpenAPI Specification](../../openapi.yaml)** - Complete API documentation

### Rate Limits

Be aware of rate limits to avoid throttling:

| Endpoint Type | Limit | Window |
|---------------|-------|--------|
| Authentication | 5 requests | 1 minute |
| Standard API | 60 requests | 1 minute |
| Sensitive Operations | 10 requests | 1 minute |

> **Tip:** The API returns `X-RateLimit-Limit` and `X-RateLimit-Remaining` headers with each response.

### Best Practices

1. **Store tokens securely** - Never commit tokens to version control
2. **Handle errors gracefully** - Always check the `success` field
3. **Use pagination** - For large datasets, use `page` and `per_page` parameters
4. **Implement retry logic** - For transient errors (500, 503)
5. **Monitor rate limits** - Watch the rate limit headers

### Getting Help

- **Documentation:** Check the [API README](../API-README.md)
- **Support:** Contact support@chom.example.com
- **API Status:** Check https://status.chom.example.com

---

**Ready to build something awesome?** Start creating sites, managing backups, and automating your WordPress hosting with the CHOM API!
