# Loki Multi-Tenancy - Production Deployment

## Overview

Loki multi-tenancy is enabled on the production observability stack to provide log isolation between different organizations and environments.

## Quick Reference

### Configuration Files

- **Loki Config**: `/etc/observability/loki/loki-config.yml`
- **Tenant Limits**: `/etc/observability/loki/tenant-limits.yaml`
- **Promtail Config**: `/etc/observability/promtail/promtail-config.yml`

### Key Setting

```yaml
auth_enabled: true
```

## Required Header

All Loki API requests must include:

```bash
X-Scope-OrgID: <tenant-id>
```

## Promtail Configuration

Promtail automatically adds the tenant ID to all log pushes:

```yaml
clients:
  - url: http://localhost:3100/loki/api/v1/push
    tenant_id: "mentat-system"
```

### Setting Tenant ID for Different Environments

Edit `/etc/observability/promtail/promtail-config.yml`:

- Production: `tenant_id: "prod"`
- Staging: `tenant_id: "staging"`
- Customer A: `tenant_id: "customer-a"`

After changing, restart Promtail:
```bash
sudo systemctl restart promtail
```

## Querying Logs

### Via curl

```bash
# Query logs
curl -H "X-Scope-OrgID: mentat-system" \
  "http://localhost:3100/loki/api/v1/query_range?query={job=\"nginx\"}"

# Get labels
curl -H "X-Scope-OrgID: mentat-system" \
  "http://localhost:3100/loki/api/v1/labels"
```

### Via Grafana

Configure datasource in `/etc/grafana/provisioning/datasources/`:

```yaml
datasources:
  - name: Loki
    type: loki
    url: http://localhost:3100
    jsonData:
      httpHeaderName1: 'X-Scope-OrgID'
    secureJsonData:
      httpHeaderValue1: 'mentat-system'
```

## Per-Tenant Limits

Edit `/etc/observability/loki/tenant-limits.yaml`:

```yaml
overrides:
  "*":
    max_streams_per_user: 10000
    max_query_length: 721h

  # Custom limits for high-volume tenant
  customer-a:
    max_streams_per_user: 20000
    ingestion_rate_mb: 20
```

After modifying, reload Loki:
```bash
sudo systemctl reload loki
```

## Testing Tenant Isolation

```bash
# Push log for tenant A
curl -X POST http://localhost:3100/loki/api/v1/push \
  -H "Content-Type: application/json" \
  -H "X-Scope-OrgID: tenant-a" \
  --data '{"streams":[{"stream":{"job":"test"},"values":[["'$(date +%s)'000000000","Log A"]]}]}'

# Push log for tenant B
curl -X POST http://localhost:3100/loki/api/v1/push \
  -H "Content-Type: application/json" \
  -H "X-Scope-OrgID: tenant-b" \
  --data '{"streams":[{"stream":{"job":"test"},"values":[["'$(date +%s)'000000000","Log B"]]}]}'

# Query tenant A (should only see "Log A")
curl -s "http://localhost:3100/loki/api/v1/query_range?query={job=\"test\"}" \
  -H "X-Scope-OrgID: tenant-a" | jq

# Query tenant B (should only see "Log B")
curl -s "http://localhost:3100/loki/api/v1/query_range?query={job=\"test\"}" \
  -H "X-Scope-OrgID: tenant-b" | jq
```

## Troubleshooting

### Error: "no org id"

Missing `X-Scope-OrgID` header. Add it to all requests.

### Promtail Not Sending Logs

Check Promtail configuration has `tenant_id` set:
```bash
sudo grep -A 5 "clients:" /etc/observability/promtail/promtail-config.yml
```

Check Promtail logs:
```bash
sudo journalctl -u promtail -f
```

### Grafana Shows No Data

Verify datasource has `X-Scope-OrgID` header configured. Check in Grafana UI:
- Configuration > Data Sources > Loki
- Custom HTTP Headers section

### Check Loki Health

```bash
# Health check (no tenant needed)
curl http://localhost:3100/ready

# Check Loki logs
sudo journalctl -u loki -f

# Verify tenant limits are loaded
sudo grep "per_tenant_override_config" /etc/observability/loki/loki-config.yml
```

## Deployment

The tenant limits file is automatically deployed by:
```bash
sudo ./deploy/scripts/deploy-observability.sh
```

## Security Notes

1. Loki is not exposed publicly - only accessible via nginx reverse proxy with authentication
2. Tenant IDs are configuration data, not secrets
3. True authentication requires nginx/application-level auth
4. Multi-tenancy provides data isolation, not access control

## References

- Full documentation: `/home/calounx/repositories/mentat/observability-stack/loki/MULTI_TENANCY.md`
- Loki config: `/etc/observability/loki/loki-config.yml`
- Deployment script: `/home/calounx/repositories/mentat/deploy/scripts/deploy-observability.sh`
