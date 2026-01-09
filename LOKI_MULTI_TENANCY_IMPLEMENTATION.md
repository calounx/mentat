# Loki Multi-Tenancy Implementation - Summary

**Date**: 2026-01-09
**Status**: Complete
**Purpose**: Enable multi-tenancy in Loki for observability isolation between organizations

## Overview

Loki multi-tenancy has been successfully implemented across both Docker-based and native deployments. This ensures that logs from Organization A cannot be viewed by Organization B, providing complete data isolation.

## Changes Made

### 1. Loki Configuration Files

#### Docker Deployment (`observability-stack/loki/loki-config.yml`)
- **Changed**: `auth_enabled: false` → `auth_enabled: true`
- **Added**: Multi-tenancy configuration in `limits_config`:
  ```yaml
  limits_config:
    enforce_metric_name: false
    reject_old_samples: true
    reject_old_samples_max_age: 168h
    split_queries_by_interval: 15m
    max_streams_per_user: 10000
    max_query_length: 721h
    per_tenant_override_config: /etc/loki/tenant-limits.yaml
  ```

#### Native Deployment (`deploy/config/mentat/loki-config.yml`)
- **Changed**: `auth_enabled: false` → `auth_enabled: true`
- **Added**: Same multi-tenancy configuration as Docker deployment
- **Path**: `/etc/observability/loki/tenant-limits.yaml` (production path)

#### Native Install Script (`chom/deploy/observability-native/install-loki.sh`)
- **Changed**: Default `auth_enabled` to `true`
- **Added**: `create_tenant_limits()` function to create tenant limits file
- **Added**: Call to `create_tenant_limits` in main installation flow
- **Updated**: Status output to show multi-tenancy is enabled

### 2. Tenant Limits Files (NEW)

Created two tenant limits files:

#### Docker: `observability-stack/loki/tenant-limits.yaml`
```yaml
overrides:
  "*":
    max_streams_per_user: 10000
    max_query_length: 721h
    max_entries_limit_per_query: 10000
    max_chunks_per_query: 2000000
    ingestion_rate_mb: 16
    ingestion_burst_size_mb: 32
```

#### Native: `deploy/config/mentat/tenant-limits.yaml`
- Same structure as Docker version
- Deployed to `/etc/observability/loki/tenant-limits.yaml` in production

### 3. Docker Compose Configuration

#### Updated: `observability-stack/docker-compose.yml`
- **Added volume mount** for tenant limits file:
  ```yaml
  volumes:
    - ./loki/loki-config.yml:/etc/loki/local-config.yaml
    - ./loki/tenant-limits.yaml:/etc/loki/tenant-limits.yaml  # NEW
    - loki-data:/loki
  ```

### 4. Promtail Configuration

#### Docker: `observability-stack/promtail/promtail-config.yml`
- **Added tenant_id** to clients section:
  ```yaml
  clients:
    - url: http://loki:3100/loki/api/v1/push
      tenant_id: "default-tenant"
  ```

#### Native: `deploy/config/mentat/promtail-config.yml`
- **Added tenant_id** to clients section:
  ```yaml
  clients:
    - url: http://localhost:3100/loki/api/v1/push
      tenant_id: "mentat-system"
  ```

### 5. Grafana Datasource Configuration

#### Docker: `observability-stack/grafana/provisioning/datasources/datasources.yml`
- **Added X-Scope-OrgID header** to Loki datasource:
  ```yaml
  jsonData:
    maxLines: 1000
    httpHeaderName1: 'X-Scope-OrgID'
  secureJsonData:
    httpHeaderValue1: 'default-tenant'
  ```

#### Native: `deploy/config/mentat/grafana-datasources.yml`
- **Added X-Scope-OrgID header** to Loki datasource:
  ```yaml
  jsonData:
    maxLines: 1000
    httpHeaderName1: 'X-Scope-OrgID'
  secureJsonData:
    httpHeaderValue1: 'mentat-system'
  ```

### 6. Deployment Scripts

#### Updated: `deploy/scripts/deploy-observability.sh`
- **Added deployment** of tenant limits file:
  ```bash
  if [[ -f "${SRC_CONFIG_DIR}/tenant-limits.yaml" ]]; then
      sudo cp "${SRC_CONFIG_DIR}/tenant-limits.yaml" "${CONFIG_DIR}/loki/"
      sudo chown observability:observability "${CONFIG_DIR}/loki/tenant-limits.yaml"
      log_success "Loki tenant limits configuration deployed"
  fi
  ```

### 7. Documentation (NEW)

#### Created: `observability-stack/loki/MULTI_TENANCY.md`
Comprehensive guide covering:
- How multi-tenancy works
- Configuration details
- Sending logs to Loki (via Promtail, API, application code)
- Querying logs (via Grafana, LogCLI, API)
- Per-tenant limits configuration
- Testing multi-tenancy
- Troubleshooting
- Best practices
- Migration guide
- Security considerations

#### Created: `deploy/config/mentat/LOKI_MULTI_TENANCY.md`
Production-focused guide covering:
- Quick reference for config file locations
- Promtail configuration for different environments
- Querying examples
- Per-tenant limits management
- Testing tenant isolation
- Troubleshooting common issues
- Deployment procedures

## Key Behavioral Changes

### Before (auth_enabled: false)
- All logs stored together without isolation
- No headers required for API requests
- Any user could query any logs
- No per-tenant resource controls

### After (auth_enabled: true)
- Logs stored per tenant with complete isolation
- **All requests require `X-Scope-OrgID: <tenant-id>` header**
- Users can only query logs for their specified tenant
- Per-tenant resource limits enforced
- Requests without header return `401 Unauthorized`

## Tenant IDs in Use

### Docker Deployment
- `default-tenant` - Default system logs

### Native Deployment
- `mentat-system` - Mentat observability stack logs

### Example Custom Tenants
- `org-a` - Organization A
- `org-b` - Organization B
- `prod` - Production environment
- `staging` - Staging environment
- `customer-123` - Specific customer

## Testing Multi-Tenancy

### Quick Test Script

```bash
# Test tenant isolation
cd /home/calounx/repositories/mentat/observability-stack

# Start stack
docker-compose up -d

# Wait for Loki to be ready
sleep 10

# Push log for tenant A
curl -X POST http://localhost:3100/loki/api/v1/push \
  -H "Content-Type: application/json" \
  -H "X-Scope-OrgID: org-a" \
  --data '{"streams":[{"stream":{"job":"test"},"values":[["'$(date +%s)'000000000","Log from org-a"]]}]}'

# Push log for tenant B
curl -X POST http://localhost:3100/loki/api/v1/push \
  -H "Content-Type: application/json" \
  -H "X-Scope-OrgID: org-b" \
  --data '{"streams":[{"stream":{"job":"test"},"values":[["'$(date +%s)'000000000","Log from org-b"]]}]}'

# Query tenant A (should only see org-a logs)
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  -H "X-Scope-OrgID: org-a" \
  --data-urlencode 'query={job="test"}' | jq

# Query tenant B (should only see org-b logs)
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  -H "X-Scope-OrgID: org-b" \
  --data-urlencode 'query={job="test"}' | jq

# Request without header (should fail with 401)
curl -v http://localhost:3100/loki/api/v1/labels
```

## Deployment Instructions

### Docker Deployment

```bash
cd /home/calounx/repositories/mentat/observability-stack

# Restart Loki to apply changes
docker-compose restart loki

# Restart Promtail to apply tenant_id
docker-compose restart promtail

# Restart Grafana to apply datasource changes
docker-compose restart grafana
```

### Native Deployment

```bash
cd /home/calounx/repositories/mentat

# Deploy observability stack (includes Loki config and tenant limits)
sudo ./deploy/scripts/deploy-observability.sh

# Or manually restart services
sudo systemctl restart loki
sudo systemctl restart promtail
sudo systemctl restart grafana-server
```

### Fresh Native Installation

```bash
# Install Loki with multi-tenancy enabled by default
sudo /home/calounx/repositories/mentat/chom/deploy/observability-native/install-loki.sh
```

## Verification Checklist

- [ ] Loki starts successfully with `auth_enabled: true`
- [ ] Tenant limits file is accessible at configured path
- [ ] Promtail sends logs with tenant header
- [ ] Grafana can query logs (datasource has X-Scope-OrgID header)
- [ ] API requests without header return 401
- [ ] Different tenant IDs see different log data
- [ ] Per-tenant limits are enforced

## Troubleshooting

### Issue: "no org id" error
**Solution**: Add `X-Scope-OrgID` header to all Loki API requests

### Issue: Promtail not sending logs
**Solution**: Check `tenant_id` is configured in Promtail clients section

### Issue: Grafana shows no data
**Solution**: Verify Grafana datasource has `X-Scope-OrgID` header configured

### Issue: Loki fails to start
**Solution**:
1. Check tenant limits file exists and is readable
2. Verify path in `per_tenant_override_config` matches actual file location
3. Check Loki logs: `journalctl -u loki -f` or `docker logs chom-loki`

## Configuration File Locations

### Docker Deployment
- Loki config: `/home/calounx/repositories/mentat/observability-stack/loki/loki-config.yml`
- Tenant limits: `/home/calounx/repositories/mentat/observability-stack/loki/tenant-limits.yaml`
- Promtail config: `/home/calounx/repositories/mentat/observability-stack/promtail/promtail-config.yml`
- Grafana datasources: `/home/calounx/repositories/mentat/observability-stack/grafana/provisioning/datasources/datasources.yml`
- Docker compose: `/home/calounx/repositories/mentat/observability-stack/docker-compose.yml`

### Native Deployment
- Loki config: `/home/calounx/repositories/mentat/deploy/config/mentat/loki-config.yml`
  - Deployed to: `/etc/observability/loki/loki-config.yml`
- Tenant limits: `/home/calounx/repositories/mentat/deploy/config/mentat/tenant-limits.yaml`
  - Deployed to: `/etc/observability/loki/tenant-limits.yaml`
- Promtail config: `/home/calounx/repositories/mentat/deploy/config/mentat/promtail-config.yml`
  - Deployed to: `/etc/observability/promtail/promtail-config.yml`
- Grafana datasources: `/home/calounx/repositories/mentat/deploy/config/mentat/grafana-datasources.yml`
  - Deployed to: `/etc/grafana/provisioning/datasources/datasources.yaml`

### Documentation
- Full guide: `/home/calounx/repositories/mentat/observability-stack/loki/MULTI_TENANCY.md`
- Production guide: `/home/calounx/repositories/mentat/deploy/config/mentat/LOKI_MULTI_TENANCY.md`

## Security Considerations

1. **Tenant Isolation**: Complete log isolation between tenants - verified by design
2. **Authentication**: Multi-tenancy provides data isolation, NOT authentication
3. **Network Security**: Loki should not be exposed directly to the internet
4. **Reverse Proxy**: Use nginx with authentication for external access
5. **Tenant ID Management**: Treat tenant IDs as configuration data
6. **Resource Limits**: Set appropriate per-tenant limits to prevent DoS

## Next Steps

1. **Test the implementation** using the test script above
2. **Configure tenant IDs** for your specific organizations/environments
3. **Set per-tenant limits** based on expected usage patterns
4. **Update application logging** to use appropriate tenant IDs
5. **Configure Grafana dashboards** with proper tenant filters
6. **Document tenant ID mapping** for your organization
7. **Set up monitoring** for tenant-level metrics and limits

## References

- [Grafana Loki Multi-Tenancy Docs](https://grafana.com/docs/loki/latest/operations/multi-tenancy/)
- Implementation documentation: `observability-stack/loki/MULTI_TENANCY.md`
- Production guide: `deploy/config/mentat/LOKI_MULTI_TENANCY.md`

## Version Information

- Loki Version (Docker): 2.9.3
- Loki Version (Native): 2.9.4
- Promtail Version (Docker): 2.9.3
- Grafana Version (Docker): 10.2.2
- Schema Version: v11 (Docker), v13 (Native)
