# VPS Management API - Quick Reference Card

**Version:** 1.0.0 | **Date:** 2026-01-02

---

## Endpoints at a Glance

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/api/v1/vps` | User | List all VPS servers |
| POST | `/api/v1/vps` | Admin | Create new VPS server |
| GET | `/api/v1/vps/{id}` | User | Get VPS details |
| PUT/PATCH | `/api/v1/vps/{id}` | Admin | Update VPS server |
| DELETE | `/api/v1/vps/{id}` | Owner | Delete VPS server |
| GET | `/api/v1/vps/{id}/stats` | User | Get resource statistics |

---

## Quick Create VPS

```bash
POST /api/v1/vps
Content-Type: application/json
Authorization: Bearer {token}

{
  "hostname": "vps-01.example.com",
  "ip_address": "192.0.2.10",
  "provider": "digitalocean",
  "region": "nyc3",
  "spec_cpu": 4,
  "spec_memory_mb": 8192,
  "spec_disk_gb": 160,
  "allocation_type": "shared",
  "ssh_private_key": "-----BEGIN RSA PRIVATE KEY-----\n...",
  "ssh_public_key": "ssh-rsa AAAAB3NzaC1..."
}
```

---

## Provider Options

- `digitalocean`
- `linode`
- `vultr`
- `aws`
- `hetzner`
- `ovh`
- `custom`

---

## Status Values

- `provisioning` - Initial state, VPS being set up
- `active` - VPS operational and accepting sites
- `maintenance` - Temporary unavailable for maintenance
- `inactive` - VPS disabled or decommissioned

---

## Health Status Values

- `healthy` - All systems operational
- `degraded` - Performance issues detected
- `unhealthy` - Critical issues, requires attention
- `unknown` - Health check pending

---

## Allocation Types

- `shared` - Multi-tenant VPS (default)
- `dedicated` - Single tenant VPS

---

## Filter Examples

```bash
# Filter by provider
GET /api/v1/vps?provider=digitalocean

# Filter by status
GET /api/v1/vps?status=active

# Sort by hostname
GET /api/v1/vps?sort=hostname&order=asc

# Pagination
GET /api/v1/vps?page=2&per_page=20

# Combined filters
GET /api/v1/vps?provider=digitalocean&status=active&sort=created_at&order=desc
```

---

## Authorization Matrix

| Action | Guest | Member | Admin | Owner |
|--------|-------|--------|-------|-------|
| View List | ❌ | ✅ | ✅ | ✅ |
| View Details | ❌ | ✅ | ✅ | ✅ |
| Create VPS | ❌ | ❌ | ✅ | ✅ |
| Update VPS | ❌ | ❌ | ✅ | ✅ |
| Delete VPS | ❌ | ❌ | ❌ | ✅ |
| View Stats | ❌ | ✅ | ✅ | ✅ |

---

## Response Structure

### Success Response
```json
{
  "success": true,
  "data": { ... },
  "message": "Optional success message"
}
```

### Error Response
```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable message",
    "details": { ... }
  }
}
```

---

## Common Validation Rules

| Field | Type | Rules |
|-------|------|-------|
| hostname | string | Required, unique, max:253, RFC 1123 |
| ip_address | string | Required, IP (v4/v6), unique |
| provider | string | Required, whitelist |
| spec_cpu | integer | Min:1, Max:128 |
| spec_memory_mb | integer | Min:512, Max:1048576 |
| spec_disk_gb | integer | Min:10, Max:10240 |
| allocation_type | string | shared or dedicated |

---

## Security Notes

### SSH Keys
- **Encrypted at rest** using AES-256-CBC
- **Never exposed** in API responses
- Use `ssh_configured: true/false` to check status

### IP Address
- **Cannot be changed** after creation
- Validated for IPv4 and IPv6 formats
- Must be unique across all VPS servers

### Tenant Isolation
- **Shared VPS:** Accessible to all tenants
- **Dedicated VPS:** Only accessible to allocated tenant

---

## Error Codes

| Code | Status | Meaning |
|------|--------|---------|
| VPS_CREATION_FAILED | 500 | Server error during creation |
| VPS_UPDATE_FAILED | 500 | Server error during update |
| VPS_DELETION_FAILED | 500 | Server error during deletion |
| VPS_HAS_ACTIVE_SITES | 409 | Cannot delete VPS with sites |
| IP_CHANGE_NOT_ALLOWED | 422 | IP changes not permitted |

---

## Files Reference

```
app/
├── Http/
│   ├── Controllers/Api/V1/
│   │   └── VpsController.php          # Main controller
│   ├── Requests/V1/Vps/
│   │   ├── CreateVpsRequest.php       # Create validation
│   │   └── UpdateVpsRequest.php       # Update validation
│   └── Resources/V1/
│       ├── VpsResource.php            # Single VPS response
│       └── VpsCollection.php          # Collection response
├── Models/
│   ├── VpsServer.php                  # VPS model
│   └── VpsAllocation.php              # Tenant allocation
└── Policies/
    └── VpsPolicy.php                  # Authorization rules
```

---

## Testing Quick Commands

```bash
# Run VPS tests
php artisan test --filter=VpsController

# Check VPS routes
php artisan route:list --name=vps

# Verify VPS policy
php artisan policy:check VpsServer create

# Generate VPS factory data
php artisan tinker
>>> VpsServer::factory()->count(5)->create();
```

---

## Need Help?

- **Full Documentation:** `VPS_API_IMPLEMENTATION_SUMMARY.md`
- **Model Documentation:** `app/Models/VpsServer.php`
- **OpenAPI Spec:** `openapi.yaml`
- **Support:** Contact DevOps team

---

**Last Updated:** 2026-01-02
**Implementation Status:** PRODUCTION-READY ✓
