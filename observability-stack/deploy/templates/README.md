# Deployment Templates Directory

This directory contains templates for deploying the observability stack in various configurations.

## Purpose

Templates provide:
- Pre-configured deployment scenarios
- Role-based installation profiles
- Infrastructure-as-code examples
- Quick-start configurations

## Available Templates

Currently, this directory is empty. Templates are being developed for:

### Planned Templates

1. **single-vps.yaml** - All-in-one observability VPS
   - Prometheus, Loki, Tempo, Grafana on one server
   - Suitable for: Small deployments, development

2. **distributed.yaml** - Distributed multi-VPS setup
   - Separate VPS for each component
   - Suitable for: Production, high-availability

3. **vpsmanager.yaml** - VPSManager role configuration
   - Laravel application with full monitoring
   - Suitable for: Hosting platforms, CHOM integration

4. **monitored-host.yaml** - Exporters-only configuration
   - Just exporters, no storage/visualization
   - Suitable for: Adding servers to existing monitoring

## Using Templates

When templates are available:

```bash
# Deploy using a template
./deploy/install.sh --template single-vps

# Or with bootstrap
curl -sSL https://raw.githubusercontent.com/calounx/mentat/master/observability-stack/deploy/bootstrap.sh | \
  sudo bash -s -- --template single-vps
```

## Creating Custom Templates

Template structure (when implemented):

```yaml
---
template:
  name: "single-vps"
  description: "All-in-one observability VPS"

modules:
  - prometheus
  - loki
  - tempo
  - grafana
  - alertmanager
  - node_exporter

configuration:
  prometheus:
    retention: 30d
  loki:
    retention: 15d
  grafana:
    admin_password: "${SECRET:grafana_admin_password}"

firewall:
  ports:
    - 3000  # Grafana
    - 9090  # Prometheus
    - 3100  # Loki
```

## Current Status

**Templates Available**: 0 (Directory is currently empty)

**Deployment is currently managed by**:
- [bootstrap.sh](../bootstrap.sh) - Interactive role-based installer
- [install.sh](../install.sh) - Role-based deployment script

## See Also

- [Deployment Guide](../README.md)
- [Bootstrap Installer](../bootstrap.sh)
- [Role-Based Installation](../install.sh)
