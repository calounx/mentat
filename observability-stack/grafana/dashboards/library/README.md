# Dashboard Library

Pre-built Grafana dashboards for common monitoring scenarios.

## Available Dashboards

| Dashboard | UID | Description |
|-----------|-----|-------------|
| Node Exporter Full | `node-exporter-full-lib` | Comprehensive system metrics (CPU, memory, disk, network) |
| Nginx Overview | `nginx-overview-lib` | Nginx web server monitoring |
| MySQL Overview | `mysql-overview-lib` | MySQL/MariaDB database monitoring with replication |
| Loki Overview | `loki-overview-lib` | Loki log aggregation and Promtail status |
| Prometheus Self-Monitoring | `prometheus-self-lib` | Prometheus health and performance |
| Tempo Overview | `tempo-overview-lib` | Distributed tracing metrics |
| Grafana Alloy Overview | `alloy-overview-lib` | OpenTelemetry collector with metrics, logs, traces pipelines |

## Usage

### Import via Grafana UI

1. Navigate to Dashboards → Import
2. Upload JSON file or paste content
3. Select data source
4. Click Import

### Provisioning

Add to your Grafana provisioning configuration:

```yaml
apiVersion: 1
providers:
  - name: 'library'
    folder: 'Library'
    type: file
    options:
      path: /path/to/dashboards/library
```

## Variables

Most dashboards use these template variables:

- `$instance` - Filter by instance/host
- `$DS_PROMETHEUS` - Prometheus data source UID

## Tags

Each dashboard is tagged for easy filtering:
- `library` - All library dashboards
- `node`, `nginx`, `mysql`, `loki`, `prometheus`, `tempo`, `alloy` - Component-specific
