# CHOM API Documentation

Complete API documentation for the CHOM multi-tenant WordPress hosting platform.

## Overview

The CHOM API is a RESTful API that allows you to programmatically manage WordPress sites, backups, teams, and organizations. It uses Laravel Sanctum for authentication and follows OpenAPI 3.1 standards.

## Quick Links

- **Quick Start Guide**: [API-QUICKSTART.md](./API-QUICKSTART.md)
- **OpenAPI Specification**: [../openapi.yaml](../openapi.yaml)
- **Postman Collection**: [../postman_collection.json](../postman_collection.json)
- **Changelog**: [API-CHANGELOG.md](./API-CHANGELOG.md)
- **Versioning Policy**: [API-VERSIONING.md](./API-VERSIONING.md)
- **L5-Swagger Setup**: [L5-SWAGGER-SETUP.md](./L5-SWAGGER-SETUP.md)
- **Interactive Docs**: http://localhost:8000/api/documentation (Swagger UI)

## Features

### Core Capabilities

- **Multi-Tenant Architecture** - Isolated data per organization
- **Site Management** - Create, configure, and manage WordPress sites
- **Automated Backups** - Schedule and manage site backups
- **Team Collaboration** - Role-based access control
- **SSL Management** - Automatic Let's Encrypt certificates
- **Real-Time Metrics** - Performance monitoring and analytics

### API Features

- **RESTful Design** - Standard HTTP methods and status codes
- **JSON Responses** - Consistent response format
- **Bearer Authentication** - Secure token-based auth
- **Rate Limiting** - Three-tier rate limiting system
- **Pagination** - Efficient data retrieval
- **Filtering** - Query parameters for list endpoints
- **Async Operations** - Background processing for heavy tasks
- **Error Handling** - Standardized error responses

## Getting Started

### 1. Authentication

Register for an account or login to get an API token:

```bash
# Register
curl -X POST http://localhost:8000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "name": "John Doe",
    "email": "john@example.com",
    "password": "SecurePassword123!",
    "password_confirmation": "SecurePassword123!",
    "organization_name": "ACME Corp"
  }'

# Login
curl -X POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "john@example.com",
    "password": "SecurePassword123!"
  }'
```

Save the returned `token` for authenticated requests.

### 2. Make Your First Request

```bash
curl -X GET http://localhost:8000/api/v1/auth/me \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Accept: application/json"
```

### 3. Create a Site

```bash
curl -X POST http://localhost:8000/api/v1/sites \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "domain": "myblog.com",
    "site_type": "wordpress",
    "php_version": "8.2",
    "ssl_enabled": true
  }'
```

## Documentation Files

### For Developers

| File | Description |
|------|-------------|
| [API-QUICKSTART.md](./API-QUICKSTART.md) | Step-by-step getting started guide |
| [openapi.yaml](../openapi.yaml) | Complete OpenAPI 3.1 specification |
| [postman_collection.json](../postman_collection.json) | Importable Postman collection |
| [API-CHANGELOG.md](./API-CHANGELOG.md) | Version history and breaking changes |
| [API-VERSIONING.md](./API-VERSIONING.md) | Versioning strategy and deprecation policy |

### For Integration

| File | Description |
|------|-------------|
| [L5-SWAGGER-SETUP.md](./L5-SWAGGER-SETUP.md) | L5-Swagger integration guide |
| Interactive UI | http://localhost:8000/api/documentation |

## API Endpoints

### Authentication

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/auth/register` | Register new user and organization |
| POST | `/auth/login` | Login and receive token |
| POST | `/auth/logout` | Logout and revoke token |
| GET | `/auth/me` | Get current user details |
| POST | `/auth/refresh` | Refresh API token |

### Sites

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/sites` | List all sites |
| POST | `/sites` | Create new site |
| GET | `/sites/{id}` | Get site details |
| PATCH | `/sites/{id}` | Update site settings |
| DELETE | `/sites/{id}` | Delete site |
| POST | `/sites/{id}/enable` | Enable site |
| POST | `/sites/{id}/disable` | Disable site |
| POST | `/sites/{id}/ssl` | Issue SSL certificate |
| GET | `/sites/{id}/metrics` | Get site metrics |

### Backups

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/backups` | List all backups |
| POST | `/backups` | Create new backup |
| GET | `/backups/{id}` | Get backup details |
| DELETE | `/backups/{id}` | Delete backup |
| GET | `/backups/{id}/download` | Get download URL |
| POST | `/backups/{id}/restore` | Restore from backup |
| GET | `/sites/{id}/backups` | List site backups |
| POST | `/sites/{id}/backups` | Create site backup |

### Team

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/team/members` | List team members |
| GET | `/team/members/{id}` | Get member details |
| PATCH | `/team/members/{id}` | Update member role |
| DELETE | `/team/members/{id}` | Remove member |
| POST | `/team/invitations` | Invite team member |
| GET | `/team/invitations` | List invitations |
| DELETE | `/team/invitations/{id}` | Cancel invitation |
| POST | `/team/transfer-ownership` | Transfer ownership |

### Organization

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/organization` | Get organization details |
| PATCH | `/organization` | Update organization |

### System

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check (no auth) |

## Response Format

### Success Response

```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "domain": "example.com",
    ...
  },
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
    "details": {
      "additional": "context"
    }
  }
}
```

### Paginated Response

```json
{
  "success": true,
  "data": [...],
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

## Authentication

All authenticated endpoints require a Bearer token in the Authorization header:

```http
Authorization: Bearer YOUR_TOKEN_HERE
Accept: application/json
```

### Token Management

- **Obtain**: Register or login to receive a token
- **Use**: Include in `Authorization` header for all requests
- **Refresh**: Use `/auth/refresh` to get a new token
- **Revoke**: Use `/auth/logout` to invalidate current token

## Rate Limiting

| Tier | Endpoints | Limit | Window |
|------|-----------|-------|--------|
| Authentication | `/auth/register`, `/auth/login` | 5 requests | 1 minute |
| Standard API | Most endpoints | 60 requests | 1 minute |
| Sensitive | Delete, backup, restore | 10 requests | 1 minute |

Rate limit headers in responses:
```http
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 59
Retry-After: 30
```

## Pagination

List endpoints support pagination with query parameters:

```bash
GET /api/v1/sites?page=2&per_page=20
```

Parameters:
- `page` - Page number (default: 1)
- `per_page` - Items per page (default: 20, max: 100)

## Filtering

Many endpoints support filtering:

```bash
# Filter sites by status
GET /api/v1/sites?status=active

# Search by domain
GET /api/v1/sites?search=myblog

# Filter backups by type
GET /api/v1/backups?type=database
```

## Error Handling

### Common HTTP Status Codes

| Code | Meaning | Description |
|------|---------|-------------|
| 200 | OK | Request successful |
| 201 | Created | Resource created successfully |
| 400 | Bad Request | Invalid request data |
| 401 | Unauthorized | Missing or invalid authentication |
| 403 | Forbidden | Insufficient permissions |
| 404 | Not Found | Resource not found |
| 422 | Unprocessable Entity | Validation failed |
| 429 | Too Many Requests | Rate limit exceeded |
| 500 | Server Error | Internal server error |

### Error Codes

See [API-CHANGELOG.md](./API-CHANGELOG.md#error-code-reference) for complete error code reference.

## Async Operations

Some operations are processed asynchronously:

- **Site Creation** - Returns `status: "creating"`, poll until `"active"`
- **SSL Issuance** - Returns immediately, certificate issued in background
- **Backups** - Returns immediately, processed asynchronously
- **Restores** - Returns immediately, restore happens in background

Poll the resource endpoint to check status:

```bash
# Check site status
GET /api/v1/sites/{id}

# Look for status field
{
  "data": {
    "status": "active"  // Was "creating"
  }
}
```

## Testing

### Postman Collection

1. Import `postman_collection.json`
2. Set environment variables:
   - `base_url`: http://localhost:8000/api/v1
   - `api_token`: Your auth token
3. Run requests from the collection

### Swagger UI

Visit http://localhost:8000/api/documentation to:
- Browse all endpoints
- Test API calls directly
- View request/response schemas
- Try authentication

### cURL Examples

See [API-QUICKSTART.md](./API-QUICKSTART.md) for complete cURL examples.

## SDKs (Planned)

Auto-generated client libraries:

- **PHP** - Composer package
- **JavaScript/TypeScript** - npm package
- **Python** - pip package

Generate from OpenAPI spec using [OpenAPI Generator](https://openapi-generator.tech/).

## Versioning

CHOM uses URL-based versioning:

```
https://api.chom.example.com/api/v1/sites
                                  ^^
                                  version
```

- **Current Version**: v1.0.0
- **Support Duration**: Minimum 36 months per major version
- **Deprecation Notice**: Minimum 6 months advance warning

See [API-VERSIONING.md](./API-VERSIONING.md) for complete versioning policy.

## Security

### Best Practices

1. **Store tokens securely** - Never commit to version control
2. **Use HTTPS** - Always use HTTPS in production
3. **Rotate tokens regularly** - Use `/auth/refresh` periodically
4. **Implement rate limit backoff** - Handle 429 responses gracefully
5. **Validate SSL certificates** - Don't disable certificate validation
6. **Use environment variables** - Store credentials in env vars

### Reporting Security Issues

Email: security@chom.example.com
PGP Key: https://chom.example.com/pgp-key

## Support

### Documentation

- Quick Start: [API-QUICKSTART.md](./API-QUICKSTART.md)
- Changelog: [API-CHANGELOG.md](./API-CHANGELOG.md)
- Versioning: [API-VERSIONING.md](./API-VERSIONING.md)

### Contact

- **General Support**: support@chom.example.com
- **Bug Reports**: bugs@chom.example.com
- **Feature Requests**: feedback@chom.example.com
- **Security Issues**: security@chom.example.com

### Status Page

Monitor API status: https://status.chom.example.com

## Examples

### Complete Workflow

```bash
#!/bin/bash

BASE_URL="http://localhost:8000/api/v1"

# 1. Register
TOKEN=$(curl -s -X POST "$BASE_URL/auth/register" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "John Doe",
    "email": "john@example.com",
    "password": "SecurePassword123!",
    "password_confirmation": "SecurePassword123!",
    "organization_name": "ACME Corp"
  }' | jq -r '.data.token')

echo "Token: $TOKEN"

# 2. Create site
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

# 3. Wait for site to be active
while true; do
  STATUS=$(curl -s -X GET "$BASE_URL/sites/$SITE_ID" \
    -H "Authorization: Bearer $TOKEN" | jq -r '.data.status')

  if [ "$STATUS" = "active" ]; then
    echo "Site is active!"
    break
  fi

  echo "Status: $STATUS"
  sleep 10
done

# 4. Create backup
BACKUP_ID=$(curl -s -X POST "$BASE_URL/backups" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"site_id\": \"$SITE_ID\",
    \"backup_type\": \"full\",
    \"retention_days\": 30
  }" | jq -r '.data.id')

echo "Backup ID: $BACKUP_ID"
echo "Done!"
```

## License

The CHOM API is open-source software licensed under the [MIT license](https://opensource.org/licenses/MIT).

---

**API Version**: v1.0.0
**Last Updated**: 2024-01-15
**Documentation Version**: 1.0
