# CHOM API Error Handling Guide

Comprehensive guide to understanding, handling, and recovering from CHOM API errors.

## Table of Contents

- [Error Response Format](#error-response-format)
- [HTTP Status Codes](#http-status-codes)
- [Authentication Errors](#authentication-errors)
- [Validation Errors](#validation-errors)
- [Resource Errors](#resource-errors)
- [Permission Errors](#permission-errors)
- [Rate Limiting Errors](#rate-limiting-errors)
- [Server Errors](#server-errors)
- [Error Recovery Strategies](#error-recovery-strategies)
- [Best Practices](#best-practices)
- [Support Escalation](#support-escalation)

---

## Error Response Format

All CHOM API errors follow a consistent JSON format:

### Standard Error Response

```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable error message",
    "details": {
      "additional": "contextual information"
    }
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
      "The field_name field is required.",
      "The field_name must be a valid email address."
    ],
    "another_field": [
      "The another_field field must be at least 8 characters."
    ]
  }
}
```

> **Note:** Validation errors (HTTP 422) use a different format with a field-level `errors` object instead of a single `error` object.

---

## HTTP Status Codes

CHOM API uses standard HTTP status codes to indicate success or failure.

| Status Code | Status Name | Meaning | Common Causes |
|-------------|-------------|---------|---------------|
| **200** | OK | Request successful | Successful GET, PATCH, DELETE |
| **201** | Created | Resource created | Successful POST (site, backup, invitation) |
| **400** | Bad Request | Invalid request | Malformed JSON, invalid parameters |
| **401** | Unauthorized | Authentication failed | Missing/invalid/expired token |
| **403** | Forbidden | Permission denied | Insufficient role, plan limits |
| **404** | Not Found | Resource doesn't exist | Invalid ID, deleted resource |
| **422** | Unprocessable Entity | Validation failed | Missing required fields, invalid formats |
| **429** | Too Many Requests | Rate limit exceeded | Too many requests in time window |
| **500** | Internal Server Error | Server error | Unexpected server failure |
| **503** | Service Unavailable | Service temporarily down | Maintenance, overload |

---

## Authentication Errors

### 401 Unauthorized - Missing Token

**Cause:** No authentication token provided in the request.

**Response:**
```json
{
  "success": false,
  "error": {
    "code": "UNAUTHENTICATED",
    "message": "Authentication token is required."
  }
}
```

**Solution:**
```bash
# Include Bearer token in Authorization header
curl -X GET https://api.chom.example.com/api/v1/sites \
  -H "Authorization: Bearer YOUR_TOKEN_HERE"
```

---

### 401 Unauthorized - Invalid Token

**Cause:** Token is invalid, malformed, or has been revoked.

**Response:**
```json
{
  "success": false,
  "error": {
    "code": "UNAUTHENTICATED",
    "message": "Authentication token is invalid or expired."
  }
}
```

**Solutions:**
1. Login again to get a fresh token
2. Use the `/auth/refresh` endpoint to refresh the token

```bash
# Get a new token by logging in
curl -X POST https://api.chom.example.com/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "SecurePass123!"
  }'
```

---

### 401 Unauthorized - Invalid Credentials

**Cause:** Incorrect email or password during login.

**Response:**
```json
{
  "success": false,
  "error": {
    "code": "INVALID_CREDENTIALS",
    "message": "The provided credentials are incorrect."
  }
}
```

**Solutions:**
1. Verify email and password are correct
2. Check for typos or case sensitivity
3. Reset password if forgotten

---

### 403 Forbidden - No Organization

**Cause:** User account exists but is not associated with an organization.

**Response:**
```json
{
  "success": false,
  "error": {
    "code": "NO_ORGANIZATION",
    "message": "User is not associated with an organization."
  }
}
```

**Solution:** Contact support to associate the account with an organization.

---

## Validation Errors

### 422 Unprocessable Entity - Missing Required Fields

**Cause:** Required fields are not provided in the request.

**Example Request:**
```bash
curl -X POST https://api.chom.example.com/api/v1/sites \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "site_type": "wordpress"
  }'
```

**Response:**
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

**Solution:** Include all required fields.

```bash
curl -X POST https://api.chom.example.com/api/v1/sites \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "domain": "example.com",
    "site_type": "wordpress"
  }'
```

---

### 422 Unprocessable Entity - Invalid Format

**Cause:** Field value doesn't match expected format.

**Response:**
```json
{
  "success": false,
  "message": "The given data was invalid.",
  "errors": {
    "email": [
      "The email must be a valid email address."
    ],
    "domain": [
      "The domain format is invalid."
    ],
    "php_version": [
      "The selected php_version is invalid."
    ]
  }
}
```

**Common Format Requirements:**
| Field | Format | Valid Examples |
|-------|--------|----------------|
| `email` | Valid email | `user@example.com` |
| `domain` | Valid domain | `example.com`, `sub.example.com` |
| `php_version` | Enum | `8.2`, `8.4` |
| `site_type` | Enum | `wordpress`, `html`, `laravel` |
| `backup_type` | Enum | `full`, `database`, `files` |
| `role` | Enum | `owner`, `admin`, `member`, `viewer` |

---

### 422 Unprocessable Entity - Field Length

**Cause:** Field value exceeds maximum length or is below minimum.

**Response:**
```json
{
  "success": false,
  "message": "The given data was invalid.",
  "errors": {
    "password": [
      "The password must be at least 8 characters."
    ],
    "name": [
      "The name may not be greater than 255 characters."
    ]
  }
}
```

**Field Length Limits:**
| Field | Minimum | Maximum |
|-------|---------|---------|
| `password` | 8 chars | - |
| `name` | - | 255 chars |
| `email` | - | 255 chars |
| `organization_name` | - | 255 chars |
| `domain` | - | 253 chars |

---

## Resource Errors

### 404 Not Found - Site Not Found

**Cause:** Site ID doesn't exist or has been deleted.

**Response:**
```json
{
  "success": false,
  "error": {
    "code": "SITE_NOT_FOUND",
    "message": "The requested site could not be found."
  }
}
```

**Solutions:**
1. Verify the site ID is correct
2. Check if the site was deleted
3. Ensure you have access to the site (multi-tenancy)

```bash
# List all sites to find correct ID
curl -X GET https://api.chom.example.com/api/v1/sites \
  -H "Authorization: Bearer $TOKEN"
```

---

### 404 Not Found - Backup Not Found

**Cause:** Backup ID doesn't exist or has been deleted.

**Response:**
```json
{
  "success": false,
  "error": {
    "code": "BACKUP_NOT_FOUND",
    "message": "The requested backup could not be found."
  }
}
```

**Solution:** List backups for the site to find available backups.

```bash
curl -X GET https://api.chom.example.com/api/v1/sites/SITE_ID/backups \
  -H "Authorization: Bearer $TOKEN"
```

---

### 404 Not Found - Team Member Not Found

**Cause:** User ID doesn't exist in the organization.

**Response:**
```json
{
  "success": false,
  "error": {
    "code": "USER_NOT_FOUND",
    "message": "The requested user could not be found."
  }
}
```

**Solution:** List team members to find correct user ID.

---

## Permission Errors

### 403 Forbidden - Insufficient Permissions

**Cause:** User role doesn't have permission to perform the action.

**Response:**
```json
{
  "success": false,
  "error": {
    "code": "INSUFFICIENT_PERMISSIONS",
    "message": "You do not have permission to perform this action."
  }
}
```

**Role Permissions:**

| Action | Owner | Admin | Member | Viewer |
|--------|-------|-------|--------|--------|
| View sites | ✓ | ✓ | ✓ | ✓ |
| Create sites | ✓ | ✓ | ✓ | ✗ |
| Delete sites | ✓ | ✓ | ✗ | ✗ |
| Manage team | ✓ | ✓ | ✗ | ✗ |
| Update organization | ✓ | ✗ | ✗ | ✗ |
| Transfer ownership | ✓ | ✗ | ✗ | ✗ |

**Solution:** Contact an admin or owner to:
1. Upgrade your role
2. Perform the action on your behalf

---

### 403 Forbidden - Site Limit Exceeded

**Cause:** Organization has reached the maximum number of sites for their plan.

**Response:**
```json
{
  "success": false,
  "error": {
    "code": "SITE_LIMIT_EXCEEDED",
    "message": "You have reached your plan's site limit.",
    "details": {
      "current_sites": 10,
      "limit": 10
    }
  }
}
```

**Solutions:**
1. Delete unused sites
2. Upgrade to a higher-tier plan
3. Contact support for limit increase

---

### 403 Forbidden - Cannot Remove Last Owner

**Cause:** Attempting to remove or demote the last owner in the organization.

**Response:**
```json
{
  "success": false,
  "error": {
    "code": "CANNOT_REMOVE_LAST_OWNER",
    "message": "Cannot remove the last owner. Transfer ownership first."
  }
}
```

**Solution:** Transfer ownership to another user before removing the current owner.

```bash
curl -X POST https://api.chom.example.com/api/v1/team/transfer-ownership \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "NEW_OWNER_ID",
    "password": "YourCurrentPassword"
  }'
```

---

## Rate Limiting Errors

### 429 Too Many Requests

**Cause:** Exceeded rate limit for the endpoint.

**Response:**
```json
{
  "success": false,
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "Too many requests. Please try again later."
  }
}
```

**Response Headers:**
```
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1705318800
```

**Rate Limits:**
| Endpoint Type | Limit | Window |
|---------------|-------|--------|
| Authentication | 5 requests | 1 minute |
| Standard API | 60 requests | 1 minute |
| Sensitive Operations | 10 requests | 1 minute |

**Solutions:**

1. **Implement exponential backoff:**
```python
import time
import requests

def api_request_with_retry(url, headers, max_retries=3):
    for attempt in range(max_retries):
        response = requests.get(url, headers=headers)

        if response.status_code == 429:
            # Wait exponentially: 1s, 2s, 4s
            wait_time = 2 ** attempt
            print(f"Rate limited. Waiting {wait_time}s...")
            time.sleep(wait_time)
            continue

        return response

    raise Exception("Max retries exceeded")
```

2. **Monitor rate limit headers:**
```python
response = requests.get(url, headers=headers)

remaining = int(response.headers.get('X-RateLimit-Remaining', 0))
limit = int(response.headers.get('X-RateLimit-Limit', 60))

print(f"Rate limit: {remaining}/{limit} remaining")

if remaining < 5:
    print("Warning: Approaching rate limit")
```

3. **Batch operations and use delays:**
```python
import time

for site in sites:
    create_backup(site['id'])
    time.sleep(1)  # 1 second delay between requests
```

---

## Server Errors

### 500 Internal Server Error

**Cause:** Unexpected error on the server side.

**Response:**
```json
{
  "success": false,
  "error": {
    "code": "INTERNAL_SERVER_ERROR",
    "message": "An unexpected error occurred. Please try again later."
  }
}
```

**Solutions:**
1. Retry the request after a short delay
2. If the error persists, contact support with:
   - Timestamp of the error
   - Request details (endpoint, method, parameters)
   - Error response

---

### 503 Service Unavailable

**Cause:** Service is temporarily unavailable (maintenance, overload).

**Response:**
```json
{
  "success": false,
  "error": {
    "code": "SERVICE_UNAVAILABLE",
    "message": "The service is temporarily unavailable. Please try again later."
  }
}
```

**Solutions:**
1. Implement retry logic with exponential backoff
2. Check https://status.chom.example.com for service status
3. Wait for maintenance window to complete

---

### 500 - Site Creation Failed

**Cause:** Site provisioning process failed on the server.

**Response:**
```json
{
  "success": false,
  "error": {
    "code": "SITE_CREATION_FAILED",
    "message": "Failed to create site. Please try again or contact support."
  }
}
```

**Solutions:**
1. Retry site creation
2. Verify domain is not already in use
3. Contact support if issue persists

---

### 500 - Backup Failed

**Cause:** Backup process failed.

**Response:**
```json
{
  "success": false,
  "error": {
    "code": "BACKUP_FAILED",
    "message": "Failed to create backup. Please try again."
  }
}
```

**Solutions:**
1. Verify site is in `active` status
2. Check if there's sufficient storage space
3. Retry backup creation
4. Contact support if issue persists

---

### 400 - Backup Not Ready

**Cause:** Attempting to download or restore a backup that's still processing.

**Response:**
```json
{
  "success": false,
  "error": {
    "code": "BACKUP_NOT_READY",
    "message": "The backup is not ready yet. Please wait for it to complete."
  }
}
```

**Solution:** Poll the backup status until `is_ready` is `true`.

```python
import time

def wait_for_backup(backup_id, timeout=600):
    start_time = time.time()

    while time.time() - start_time < timeout:
        backup = get_backup(backup_id)

        if backup['data']['is_ready']:
            return backup

        time.sleep(10)  # Check every 10 seconds

    raise TimeoutError("Backup timeout")
```

---

## Error Recovery Strategies

### Idempotency

Some operations are idempotent and safe to retry:

**Safe to Retry:**
- GET requests (reading data)
- PUT/PATCH requests (updating with same data)
- DELETE requests (already deleted = 404, which is acceptable)

**Not Safe to Retry Without Checks:**
- POST requests (may create duplicates)

**Example with Idempotency Check:**
```python
def create_site_idempotent(domain):
    # Check if site already exists
    sites = list_sites(search=domain)
    existing = [s for s in sites if s['domain'] == domain]

    if existing:
        print(f"Site {domain} already exists")
        return existing[0]

    # Create site
    return create_site(domain)
```

---

### Retry with Exponential Backoff

Implement retry logic for transient errors (500, 503, 429):

```python
import time
import requests
from requests.exceptions import RequestException

def api_call_with_retry(method, url, max_retries=3, **kwargs):
    """Make API call with exponential backoff retry"""
    retryable_codes = [429, 500, 503]

    for attempt in range(max_retries):
        try:
            response = requests.request(method, url, **kwargs)

            # Success
            if response.status_code < 400:
                return response

            # Retryable error
            if response.status_code in retryable_codes:
                if attempt < max_retries - 1:
                    wait_time = 2 ** attempt  # 1s, 2s, 4s
                    print(f"Retrying in {wait_time}s... (attempt {attempt + 1})")
                    time.sleep(wait_time)
                    continue

            # Non-retryable error
            response.raise_for_status()

        except RequestException as e:
            if attempt < max_retries - 1:
                wait_time = 2 ** attempt
                print(f"Request failed: {e}. Retrying in {wait_time}s...")
                time.sleep(wait_time)
                continue
            raise

    raise Exception(f"Max retries ({max_retries}) exceeded")
```

---

### Graceful Degradation

Handle errors gracefully without crashing your application:

```javascript
async function getSiteMetrics(siteId) {
  try {
    const response = await axios.get(`/sites/${siteId}/metrics`);
    return response.data.data.metrics;
  } catch (error) {
    if (error.response?.status === 404) {
      console.warn(`Site ${siteId} not found`);
      return null;
    } else if (error.response?.status === 500) {
      console.error(`Failed to get metrics for ${siteId}`);
      // Return default/cached metrics
      return { requests_per_minute: 0, response_time_ms: 0 };
    }
    throw error;
  }
}
```

---

### Circuit Breaker Pattern

Prevent cascading failures by stopping requests to failing services:

```python
from datetime import datetime, timedelta

class CircuitBreaker:
    def __init__(self, failure_threshold=5, timeout=60):
        self.failure_threshold = failure_threshold
        self.timeout = timeout
        self.failures = 0
        self.last_failure_time = None
        self.state = 'CLOSED'  # CLOSED, OPEN, HALF_OPEN

    def call(self, func, *args, **kwargs):
        if self.state == 'OPEN':
            if datetime.now() - self.last_failure_time > timedelta(seconds=self.timeout):
                self.state = 'HALF_OPEN'
            else:
                raise Exception('Circuit breaker is OPEN')

        try:
            result = func(*args, **kwargs)
            self.on_success()
            return result
        except Exception as e:
            self.on_failure()
            raise

    def on_success(self):
        self.failures = 0
        self.state = 'CLOSED'

    def on_failure(self):
        self.failures += 1
        self.last_failure_time = datetime.now()

        if self.failures >= self.failure_threshold:
            self.state = 'OPEN'

# Usage
breaker = CircuitBreaker()

try:
    result = breaker.call(api_request, '/sites', token)
except Exception as e:
    print(f"Request failed: {e}")
```

---

## Best Practices

### 1. Always Check the `success` Field

```javascript
const response = await fetch('/api/v1/sites', {
  headers: { 'Authorization': `Bearer ${token}` }
});

const data = await response.json();

if (!data.success) {
  console.error('API Error:', data.error?.message || data.message);
  // Handle error appropriately
  return;
}

// Proceed with data.data
```

### 2. Handle Different Error Types

```python
import requests

try:
    response = requests.post(url, json=payload)
    response.raise_for_status()
    return response.json()

except requests.exceptions.HTTPError as e:
    # Handle HTTP errors (4xx, 5xx)
    if e.response.status_code == 422:
        errors = e.response.json().get('errors', {})
        print("Validation errors:", errors)
    elif e.response.status_code == 401:
        print("Authentication failed - refresh token")
    else:
        print(f"HTTP error: {e}")

except requests.exceptions.ConnectionError:
    # Handle network errors
    print("Connection error - check network")

except requests.exceptions.Timeout:
    # Handle timeout errors
    print("Request timeout - try again")

except requests.exceptions.RequestException as e:
    # Handle other errors
    print(f"Request failed: {e}")
```

### 3. Log Error Details

```python
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

try:
    response = requests.post(url, json=payload)
    response.raise_for_status()
except requests.exceptions.HTTPError as e:
    logger.error(
        "API request failed",
        extra={
            'url': url,
            'status_code': e.response.status_code,
            'response': e.response.text,
            'payload': payload
        }
    )
    raise
```

### 4. Provide User-Friendly Error Messages

```javascript
function getUserFriendlyError(error) {
  const errorCode = error.response?.data?.error?.code;

  const messages = {
    'SITE_LIMIT_EXCEEDED': 'You have reached your site limit. Please upgrade your plan.',
    'INVALID_CREDENTIALS': 'Invalid email or password. Please try again.',
    'RATE_LIMIT_EXCEEDED': 'Too many requests. Please wait a moment and try again.',
    'SITE_NOT_FOUND': 'The requested site could not be found.',
    'INSUFFICIENT_PERMISSIONS': 'You do not have permission to perform this action.'
  };

  return messages[errorCode] || 'An error occurred. Please try again or contact support.';
}

// Usage
try {
  await createSite(domain);
} catch (error) {
  showNotification(getUserFriendlyError(error));
}
```

---

## Support Escalation

When you need to contact support, provide the following information:

### Required Information

1. **Error Details:**
   - HTTP status code
   - Error code (if available)
   - Error message
   - Full error response

2. **Request Details:**
   - Endpoint (e.g., `POST /api/v1/sites`)
   - Request payload (remove sensitive data)
   - Request headers (remove token)
   - Timestamp of the request

3. **Context:**
   - What you were trying to accomplish
   - Steps to reproduce the error
   - Frequency (one-time, intermittent, consistent)

4. **Environment:**
   - Are you using production or staging API?
   - Which client library/language?
   - Network environment (if relevant)

### Contact Channels

| Issue Severity | Response Time | Contact Method |
|----------------|---------------|----------------|
| **Critical** (Service down, data loss) | < 1 hour | Phone: 1-800-CHOM-911 |
| **High** (Major functionality broken) | < 4 hours | Email: urgent@chom.example.com |
| **Medium** (Partial functionality affected) | < 24 hours | Email: support@chom.example.com |
| **Low** (General questions, feature requests) | < 48 hours | Support Portal: https://support.chom.example.com |

### Before Contacting Support

1. Check [API Status](https://status.chom.example.com)
2. Review this error guide
3. Search [Documentation](../API-README.md)
4. Check [Known Issues](https://github.com/chom/known-issues)
5. Verify your API version is up to date

---

## Additional Resources

- **[Quick Start Guide](./QUICK-START.md)** - Get started in 5 minutes
- **[API Cheat Sheet](./CHEAT-SHEET.md)** - Quick reference for all endpoints
- **[Code Examples](./EXAMPLES.md)** - Real-world code samples
- **[OpenAPI Specification](../../openapi.yaml)** - Complete API documentation
- **[API Status Page](https://status.chom.example.com)** - Real-time service status

---

**Remember:** Most errors are recoverable with proper error handling and retry logic. Always implement comprehensive error handling in production applications.
