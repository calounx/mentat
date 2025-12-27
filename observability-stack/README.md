# Observability Stack

Production-ready observability platform for Debian/Ubuntu servers. Complete metrics, logs, and traces collection without Docker.

## Stack Components

| Component | Purpose | Port |
|-----------|---------|------|
| **Prometheus** | Metrics collection & alerting | 9090 |
| **Loki** | Log aggregation | 3100 |
| **Tempo** | Distributed tracing | 4317/4318 |
| **Grafana** | Visualization & dashboards | 3000 |
| **Alertmanager** | Alert routing | 9093 |
| **Alloy** | OpenTelemetry collector | 12345 |

## Quick Start

```bash
# Clone and configure
git clone <repo> && cd observability-stack
cp config/global.yaml.example config/global.yaml
nano config/global.yaml

# Install on observability server
sudo ./scripts/setup-observability.sh

# Add monitored hosts
sudo ./scripts/setup-monitored-host.sh <OBSERVABILITY_IP>
```

## Available Modules

```
modules/_core/
├── prometheus/        # Metrics server (v3.x)
├── loki/              # Log aggregation (v3.x)
├── tempo/             # Distributed tracing
├── alloy/             # OpenTelemetry collector
├── promtail/          # Log shipper
├── node_exporter/     # System metrics
├── nginx_exporter/    # Nginx metrics
├── mysqld_exporter/   # MySQL/MariaDB metrics
├── phpfpm_exporter/   # PHP-FPM metrics
└── fail2ban_exporter/ # Fail2ban metrics
```

## Pre-built Alert Rules

Ready-to-use alert rules in `prometheus/alerts/`:

| File | Coverage |
|------|----------|
| `node-alerts.yaml` | CPU, memory, disk, network, hardware |
| `prometheus-alerts.yaml` | Self-monitoring, TSDB, scraping |
| `loki-alerts.yaml` | Ingestion, storage, promtail |
| `nginx-alerts.yaml` | Availability, connections, SSL |
| `mysql-alerts.yaml` | Connections, replication, slow queries |
| `application-alerts.yaml` | HTTP, PHP-FPM, containers, fail2ban |
| `tempo-alerts.yaml` | Traces, spans, storage |
| `alloy-alerts.yaml` | Pipelines, components, resources |

## Dashboard Library

Pre-built dashboards in `grafana/dashboards/library/`:

- **Node Exporter Full** - Comprehensive system metrics
- **Nginx Overview** - Web server monitoring
- **MySQL Overview** - Database with replication status
- **Loki Overview** - Log aggregation metrics
- **Prometheus Self-Monitoring** - Prometheus health
- **Tempo Overview** - Distributed tracing
- **Alloy Overview** - Telemetry collector pipelines

## SLO/SLI Framework

Service Level Objectives with multi-window burn rate alerting:

```
slo/slo-config.yaml              # SLO definitions
prometheus/rules/sli-*.yaml      # Recording rules
prometheus/rules/slo-*.yaml      # Alerting rules
grafana/dashboards/slo-*.json    # Error budget dashboards
```

## Module Management

```bash
# List modules
./scripts/module-manager.sh list

# Install module
./scripts/module-manager.sh install node_exporter

# Check status
./scripts/module-manager.sh status

# Auto-detect services
./scripts/auto-detect.sh
```

## Upgrade System

```bash
# Check versions
./scripts/upgrade-orchestrator.sh --status

# Upgrade all (dry-run first)
./scripts/upgrade-orchestrator.sh --all --dry-run
./scripts/upgrade-orchestrator.sh --all

# Upgrade by phase
./scripts/upgrade-orchestrator.sh --phase exporters
./scripts/upgrade-orchestrator.sh --phase prometheus
./scripts/upgrade-orchestrator.sh --phase loki

# Rollback
./scripts/upgrade-orchestrator.sh --rollback
```

## Directory Structure

```
observability-stack/
├── config/
│   ├── global.yaml           # Global settings
│   ├── versions.yaml         # Component versions
│   └── hosts/                # Per-host configs
├── modules/_core/            # Installable modules
├── prometheus/
│   ├── alerts/               # Alert rules library
│   └── rules/                # Recording rules
├── grafana/
│   └── dashboards/
│       ├── library/          # Pre-built dashboards
│       └── slo-overview.json
├── slo/                      # SLO definitions
├── scripts/
│   ├── lib/                  # Shared libraries
│   └── tools/                # Validation tools
└── tests/                    # Test suites
```

## Documentation

- [QUICK_START.md](QUICK_START.md) - Installation guide
- [SECURITY.md](SECURITY.md) - Security practices
- [CONTRIBUTING.md](CONTRIBUTING.md) - Contribution guidelines
- [docs/upgrade/](docs/upgrade/) - Upgrade documentation
- [docs/SECRETS.md](docs/SECRETS.md) - Secrets management

## Standalone Deployment

Build a self-contained deployment package:

```bash
./build.sh
# Creates dist/observability-stack-<version>.tar.gz
```

## Health Check

```bash
./scripts/health-check.sh
```

## License

MIT
