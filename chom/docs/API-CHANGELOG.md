# CHOM API Changelog

All notable changes to the CHOM API will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Table of Contents
- [Unreleased](#unreleased)
- [v1.0.0 - 2024-01-15](#v100---2024-01-15)
- [Migration Guides](#migration-guides)
- [Deprecation Policy](#deprecation-policy)

---

## [Unreleased]

### Planned
- Database management endpoints (`/databases`)
- Observability and monitoring endpoints (`/observability`)
- Billing and invoicing endpoints (`/billing`)
- Webhook configuration endpoints
- Site clone/duplicate functionality
- Automated backup scheduling
- Multi-region site deployment
- Custom domain SSL validation endpoints

---

## [v1.0.0] - 2024-01-15

### Initial Release

The first stable release of the CHOM API includes comprehensive endpoints for WordPress hosting management.

### Added

#### Authentication
- `POST /auth/register` - Register new user with organization
- `POST /auth/login` - Authenticate and receive API token
- `POST /auth/logout` - Revoke current token
- `GET /auth/me` - Get current user details
- `POST /auth/refresh` - Refresh API token

#### Sites Management
- `GET /sites` - List all sites with filtering and pagination
- `POST /sites` - Create new WordPress site
- `GET /sites/{id}` - Get site details with recent backups
- `PATCH /sites/{id}` - Update site settings
- `DELETE /sites/{id}` - Delete site permanently
- `POST /sites/{id}/enable` - Enable disabled site
- `POST /sites/{id}/disable` - Disable site temporarily
- `POST /sites/{id}/ssl` - Issue SSL certificate
- `GET /sites/{id}/metrics` - Get site performance metrics

**Site Features:**
- Support for WordPress, Laravel, and static HTML sites
- PHP version selection (8.2, 8.4)
- Automatic SSL certificate issuance via Let's Encrypt
- Multi-tenant isolation with quota enforcement
- Async site provisioning with status tracking

#### Backup Management
- `GET /backups` - List all backups with filtering
- `POST /backups` - Create new backup
- `GET /backups/{id}` - Get backup details
- `DELETE /backups/{id}` - Delete backup
- `GET /backups/{id}/download` - Get temporary download URL
- `POST /backups/{id}/restore` - Restore site from backup
- `GET /sites/{siteId}/backups` - List backups for specific site
- `POST /sites/{siteId}/backups` - Create backup for specific site

**Backup Features:**
- Three backup types: full, database-only, files-only
- Configurable retention periods (1-365 days)
- Secure temporary download URLs (15-minute expiry)
- Async backup processing
- Automatic expiration handling
- Restore to original site

#### Team Management
- `GET /team/members` - List team members
- `GET /team/members/{id}` - Get team member details
- `PATCH /team/members/{id}` - Update member role
- `DELETE /team/members/{id}` - Remove team member
- `POST /team/invitations` - Invite new team member
- `GET /team/invitations` - List pending invitations
- `DELETE /team/invitations/{id}` - Cancel invitation
- `POST /team/transfer-ownership` - Transfer organization ownership

**Team Features:**
- Four role levels: owner, admin, member, viewer
- Role-based access control (RBAC)
- Invitation system with expiration
- Password confirmation for ownership transfer
- Prevent self-removal and owner modification

#### Organization Management
- `GET /organization` - Get organization details
- `PATCH /organization` - Update organization settings

**Organization Features:**
- Organization-level settings
- Billing email configuration
- Member count tracking
- Subscription tier information

#### System
- `GET /health` - Health check endpoint (no auth required)

### Rate Limiting

Implemented three-tier rate limiting system:

| Tier | Endpoints | Limit | Window |
|------|-----------|-------|--------|
| **Authentication** | `/auth/register`, `/auth/login` | 5 requests | 1 minute |
| **Standard API** | Most endpoints | 60 requests | 1 minute |
| **Sensitive** | Delete, backup, restore operations | 10 requests | 1 minute |

### Response Format

Standardized response format across all endpoints:

**Success Response:**
```json
{
  "success": true,
  "data": { ... },
  "message": "Optional success message"
}
```

**Error Response:**
```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable error message",
    "details": { ... }
  }
}
```

**Pagination Response:**
```json
{
  "success": true,
  "data": [ ... ],
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

### Security

- Laravel Sanctum bearer token authentication
- Multi-tenant data isolation
- Role-based authorization
- Password confirmation for sensitive operations
- Rate limiting to prevent abuse
- Secure token generation and revocation

### Documentation

- Complete OpenAPI 3.1 specification
- Postman collection with automated testing
- Quick start guide
- API versioning documentation
- This changelog

---

## Migration Guides

### From Beta to v1.0.0

**Breaking Changes:**
None - This is the initial stable release.

**Recommendations:**
1. Update base URL to use `/api/v1` prefix
2. Implement proper error handling for all error codes
3. Store and refresh tokens securely
4. Implement rate limit backoff logic
5. Use pagination for list endpoints

---

## Deprecation Policy

### Our Commitment

- **Advance Notice**: Minimum 6 months notice before deprecating any endpoint
- **Versioning**: New major versions for breaking changes
- **Sunset Period**: Minimum 12 months support for deprecated versions
- **Clear Communication**: Deprecation notices in:
  - API response headers (`X-API-Deprecated: true`)
  - This changelog
  - Email notifications to API users
  - Documentation updates

### Deprecation Process

1. **Announcement** (T-6 months)
   - Deprecation announced in changelog
   - Deprecation warnings added to documentation
   - Email sent to all API users

2. **Warning Headers** (T-3 months)
   - Response header `X-API-Deprecated: true` added
   - Response header `X-API-Sunset: YYYY-MM-DD` added
   - Alternative endpoint recommended in header

3. **Sunset** (T-0)
   - Endpoint returns 410 Gone
   - Clear migration instructions provided
   - Support available for migration assistance

### Version Support

| Version | Released | Status | Support Until |
|---------|----------|--------|---------------|
| v1.0.0 | 2024-01-15 | Current | Active |

---

## Error Code Reference

### Authentication Errors (4xx)

| Code | Status | Description |
|------|--------|-------------|
| `INVALID_CREDENTIALS` | 401 | Email or password is incorrect |
| `NO_ORGANIZATION` | 403 | User not associated with an organization |
| `REGISTRATION_FAILED` | 500 | Account creation failed |

### Site Errors

| Code | Status | Description |
|------|--------|-------------|
| `SITE_LIMIT_EXCEEDED` | 403 | Plan site limit reached |
| `SITE_CREATION_FAILED` | 500 | Site provisioning failed |
| `SITE_DELETION_FAILED` | 500 | Site deletion failed |
| `ENABLE_FAILED` | 500 | Site enable operation failed |
| `DISABLE_FAILED` | 500 | Site disable operation failed |
| `SSL_FAILED` | 500 | SSL certificate issuance failed |
| `NO_VPS` | 400 | No VPS server associated with site |

### Backup Errors

| Code | Status | Description |
|------|--------|-------------|
| `BACKUP_CREATION_FAILED` | 500 | Backup creation failed |
| `BACKUP_DELETION_FAILED` | 500 | Backup deletion failed |
| `BACKUP_NOT_READY` | 400 | Backup not yet available |
| `BACKUP_EXPIRED` | 400 | Backup retention period expired |
| `RESTORE_FAILED` | 500 | Backup restore operation failed |

### Team Errors

| Code | Status | Description |
|------|--------|-------------|
| `FORBIDDEN` | 403 | Insufficient permissions |
| `CANNOT_MODIFY_OWNER` | 400 | Cannot modify owner's role |
| `CANNOT_REMOVE_SELF` | 400 | Cannot remove yourself |
| `CANNOT_REMOVE_OWNER` | 400 | Cannot remove organization owner |
| `CANNOT_REMOVE_ADMIN` | 403 | Only owner can remove admins |
| `ALREADY_MEMBER` | 400 | User already in organization |
| `REMOVAL_FAILED` | 500 | Member removal failed |
| `INVALID_PASSWORD` | 401 | Password confirmation failed |
| `TRANSFER_FAILED` | 500 | Ownership transfer failed |

---

## Frequently Asked Questions

### What happens when I delete a site?

Sites are soft-deleted by default and can be recovered within 30 days. After 30 days, they are permanently deleted. Associated backups are retained according to their individual retention periods.

### How long do backup download URLs last?

Temporary download URLs expire after 15 minutes for security. Request a new download URL if needed.

### Can I restore a backup to a different site?

Currently, backups can only be restored to their original site. Cross-site restore functionality is planned for a future release.

### What happens when I reach my rate limit?

You'll receive a `429 Too Many Requests` response with a `Retry-After` header indicating when you can retry. Implement exponential backoff in your client.

### How do I know when async operations complete?

Poll the resource endpoint (e.g., `/sites/{id}`) to check the `status` field. Status changes from `creating` to `active` when complete. Consider implementing webhooks (planned feature) for push notifications.

### What is the difference between owner and admin roles?

- **Owner**: Full control including organization settings, billing, and ownership transfer
- **Admin**: Can manage sites, backups, and members but cannot modify organization settings or transfer ownership
- **Member**: Can view and manage sites/backups but cannot manage team
- **Viewer**: Read-only access to sites and backups

---

## Support & Feedback

We welcome your feedback! Please reach out:

- **Bug Reports**: support@chom.example.com
- **Feature Requests**: feedback@chom.example.com
- **Documentation Issues**: docs@chom.example.com
- **Security Issues**: security@chom.example.com (PGP key available)

---

## Useful Links

- [API Quick Start Guide](./API-QUICKSTART.md)
- [API Versioning Policy](./API-VERSIONING.md)
- [OpenAPI Specification](../openapi.yaml)
- [Postman Collection](../postman_collection.json)
- [Interactive API Docs](https://api.chom.example.com/api/documentation)

---

**Last Updated**: 2024-01-15
**API Version**: v1.0.0
