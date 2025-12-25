# Observability Stack for Debian 13

A complete, production-ready observability stack without Docker. Features a **modular exporter system** that allows different monitored hosts to run different sets of exporters, with centralized dashboard and alert management.

## Components

| Component | Purpose | Port |
|-----------|---------|------|
| **Prometheus** | Metrics collection & storage | 9090 |
| **Loki** | Log aggregation | 3100 |
| **Grafana** | Visualization & dashboards | 3000 |
| **Alertmanager** | Alert routing (Email/Slack) | 9093 |
| **Nginx** | Reverse proxy with SSL | 80/443 |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    OBSERVABILITY VPS                            │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌─────────────┐  │
│  │ Prometheus│  │   Loki    │  │  Grafana  │  │Alertmanager │  │
│  │ (metrics) │  │  (logs)   │  │  (viz)    │  │ (alerts)    │  │
│  └─────▲─────┘  └─────▲─────┘  └───────────┘  └─────────────┘  │
│        │ scrape       │ push                                    │
│  ┌─────┴──────────────┴─────────────────────────────────────┐  │
│  │              MODULE REGISTRY                              │  │
│  │  Dashboards │ Alert Rules │ Scrape Configs │ Install     │  │
│  └───────────────────────────────────────────────────────────┘  │
└────────┬──────────────┬─────────────────────────────────────────┘
         │              │
┌────────┴──────────────┴────────────────────────────────────────┐
│               MONITORED HOSTS (per-host configs)               │
│                                                                 │
│  Host A: node │ nginx │ mysql │ phpfpm                         │
│  Host B: node │ nginx │ fail2ban                               │
│  Host C: node │ promtail                                       │
└─────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
observability-stack/
├── config/
│   ├── global.yaml                    # Global settings (retention, SMTP, Slack)
│   └── hosts/                         # Per-host configuration files
│       ├── webserver-01.yaml          # Host-specific modules & thresholds
│       └── example-host.yaml.template # Template for new hosts
│
├── modules/                           # Module registry
│   ├── _core/                         # Core modules (maintained)
│   │   ├── node_exporter/
│   │   ├── nginx_exporter/
│   │   ├── mysqld_exporter/
│   │   ├── phpfpm_exporter/
│   │   ├── fail2ban_exporter/
│   │   └── promtail/
│   ├── _available/                    # Community modules
│   └── _custom/                       # Custom modules (gitignored)
│
├── scripts/
│   ├── lib/                           # Shared libraries
│   │   ├── common.sh                  # Logging, YAML parsing utilities
│   │   ├── module-loader.sh           # Module discovery & loading
│   │   └── config-generator.sh        # Prometheus/Grafana config generation
│   ├── module-manager.sh              # Module management CLI
│   ├── auto-detect.sh                 # Service auto-detection
│   ├── setup-observability.sh         # Main setup script
│   └── setup-monitored-host.sh        # Module-based host setup
│
├── prometheus/
│   ├── prometheus.yml.template
│   └── rules/                         # Generated from modules
│
├── loki/
│   └── loki-config.yaml
│
├── alertmanager/
│   ├── alertmanager.yml.template
│   └── templates/
│       └── email.tmpl
│
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   └── dashboards/
│   └── dashboards/                    # Generated from modules
│
└── nginx/
    └── observability.conf.template
```

## Module System

Each module is a self-contained package containing:
- `module.yaml` - Manifest with version, port, detection rules, configuration schema
- `install.sh` - Installation script
- `uninstall.sh` - Uninstallation script
- `dashboard.json` - Grafana dashboard
- `alerts.yml` - Prometheus alert rules
- `scrape-config.yml` - Prometheus scrape configuration template

### Module Manager CLI

```bash
# List all available modules
./scripts/module-manager.sh list

# List by category
./scripts/module-manager.sh list core
./scripts/module-manager.sh list available
./scripts/module-manager.sh list custom

# Show module details
./scripts/module-manager.sh show node_exporter

# Validate module manifests
./scripts/module-manager.sh validate
./scripts/module-manager.sh validate node_exporter

# Check module installation status
./scripts/module-manager.sh status

# Install a module on current host
./scripts/module-manager.sh install node_exporter
./scripts/module-manager.sh install node_exporter --force

# Uninstall a module
./scripts/module-manager.sh uninstall node_exporter
./scripts/module-manager.sh uninstall node_exporter --purge

# Enable/disable modules for hosts
./scripts/module-manager.sh enable mysql_exporter webserver-01
./scripts/module-manager.sh disable phpfpm_exporter webserver-01

# Generate Prometheus/Grafana configs from enabled modules
./scripts/module-manager.sh generate-config
./scripts/module-manager.sh generate-config --dry-run
```

### Auto-Detection

Auto-detect which modules should be enabled based on running services:

```bash
# Detect services and show recommendations
./scripts/auto-detect.sh

# Generate host config file from detection
./scripts/auto-detect.sh --generate --output=config/hosts/myhost.yaml

# Force overwrite existing config
./scripts/auto-detect.sh --generate --force --output=config/hosts/myhost.yaml
```

### Available Modules

| Module | Description | Port | Detection |
|--------|-------------|------|-----------|
| node_exporter | System metrics (CPU, memory, disk, network) | 9100 | Always applicable |
| nginx_exporter | Nginx server metrics | 9113 | nginx service detected |
| mysqld_exporter | MySQL/MariaDB database metrics | 9104 | mysql/mariadb service detected |
| phpfpm_exporter | PHP-FPM process pool metrics | 9253 | php-fpm socket detected |
| fail2ban_exporter | Fail2ban jail and ban metrics | 9191 | fail2ban service detected |
| promtail | Log shipping to Loki | - | Always applicable |

## Quick Start

### 1. Configure Global Settings

Edit `config/global.yaml`:

```yaml
network:
  observability_vps_ip: "YOUR_VPS_IP"
  grafana_domain: "mentat.arewel.com"
  letsencrypt_email: "admin@arewel.com"

retention:
  metrics_days: 15
  logs_days: 7

smtp:
  host: "smtp-relay.brevo.com"
  port: 587
  username: "your-brevo-email"
  password: "your-brevo-smtp-key"
  from_address: "alerts@yourdomain.com"
  to_addresses:
    - "admin@yourdomain.com"

slack:
  webhook_url: "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
  channel: "#alerts"
```

### 2. Setup Observability VPS

```bash
# Copy the entire stack to your VPS
scp -r observability-stack root@YOUR_VPS_IP:/opt/

# SSH and run setup
ssh root@YOUR_VPS_IP
cd /opt/observability-stack
./scripts/setup-observability.sh
```

### 3. Add Monitored Hosts

#### Option A: Auto-detect and configure

```bash
# On the monitored host, run auto-detection
./scripts/auto-detect.sh --generate --output=config/hosts/$(hostname).yaml

# Review and adjust the generated config, then install
./scripts/setup-monitored-host.sh OBSERVABILITY_VPS_IP LOKI_URL LOKI_USER LOKI_PASS
```

#### Option B: Manual configuration

Create a host config file `config/hosts/webserver-01.yaml`:

```yaml
host:
  name: "webserver-01"
  ip: "10.0.0.10"
  description: "Production WordPress server"
  environment: "production"

modules:
  node_exporter:
    enabled: true
    config:
      collectors_enabled:
        - systemd
        - filesystem
        - meminfo
    thresholds:
      cpu_usage_warning: 80
      cpu_usage_critical: 95
      memory_usage_warning: 80
      memory_usage_critical: 95
      disk_usage_warning: 80
      disk_usage_critical: 90

  nginx_exporter:
    enabled: true
    config:
      scrape_uri: "http://127.0.0.1:8080/stub_status"

  mysqld_exporter:
    enabled: true
    config:
      credentials:
        username: "exporter"
        password: "CHANGE_ME"

  phpfpm_exporter:
    enabled: true
    config:
      socket: "/run/php/php8.2-fpm.sock"
      pool_name: "www"

  fail2ban_exporter:
    enabled: true

  promtail:
    enabled: true
    config:
      log_paths:
        - "/var/log/nginx/*.log"
        - "/var/log/syslog"
```

Then run setup on the monitored host:

```bash
./scripts/setup-monitored-host.sh OBSERVABILITY_VPS_IP LOKI_URL LOKI_USER LOKI_PASS
```

### 4. Generate Configurations

After adding or modifying host configs, regenerate Prometheus and Grafana configurations:

```bash
# On observability VPS
./scripts/module-manager.sh generate-config

# Reload services
systemctl reload prometheus
systemctl restart grafana-server
```

## Pre-configured Dashboards

Each module includes a dashboard. When modules are enabled for any host, their dashboards are automatically provisioned.

| Dashboard | Description |
|-----------|-------------|
| **Infrastructure Overview** | High-level view of all hosts, active alerts |
| **Node Exporter Details** | Detailed CPU, memory, disk, network per host |
| **Nginx** | Connections, requests, error rates |
| **MySQL/MariaDB** | Connections, QPS, InnoDB metrics |
| **PHP-FPM** | Process pool, queue, slow requests |
| **Logs Explorer** | Centralized log viewer with filters |

## Alert Rules

Alert rules are also bundled with modules and automatically aggregated.

### System Alerts (node_exporter)
- Instance down
- High CPU (>80%, >95%)
- High memory usage (>80%, >95%)
- Disk space low (>80%, >90%)
- Disk fill prediction (24h)
- High load average
- Systemd service failed

### Service Alerts
- **Nginx**: Down, high connections, 4xx/5xx error rates
- **MySQL**: Down, connection saturation, slow queries, replication lag
- **PHP-FPM**: Down, max children reached, queue filling
- **Fail2ban**: Down, high ban rate, exporter errors

## Security

### Authentication
- **Grafana**: Username/password authentication
- **Prometheus/Loki/Alertmanager**: Protected via Nginx basic auth
- **Exporters**: Only accessible from observability VPS IP (firewall)

### SSL/TLS
- Automatic Let's Encrypt certificates via Certbot
- Auto-renewal enabled

## Ports Reference

### Observability VPS
| Port | Service | Access |
|------|---------|--------|
| 80 | HTTP (redirect to HTTPS) | Public |
| 443 | HTTPS (Grafana/APIs) | Public |
| 3000 | Grafana (internal) | Localhost |
| 9090 | Prometheus (internal) | Localhost |
| 3100 | Loki (internal) | Localhost |
| 9093 | Alertmanager (internal) | Localhost |

### Monitored Hosts
| Port | Exporter | Access |
|------|----------|--------|
| 9100 | node_exporter | From Observability VPS |
| 9113 | nginx_exporter | From Observability VPS |
| 9104 | mysqld_exporter | From Observability VPS |
| 9253 | phpfpm_exporter | From Observability VPS |
| 9191 | fail2ban_exporter | From Observability VPS |

## Troubleshooting

### Check service status
```bash
systemctl status prometheus loki grafana-server alertmanager nginx
```

### View logs
```bash
journalctl -u prometheus -f
journalctl -u loki -f
journalctl -u grafana-server -f
```

### Check module status on host
```bash
./scripts/module-manager.sh status
```

### Test Prometheus targets
```bash
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {instance: .labels.instance, health: .health}'
```

### Validate module manifests
```bash
./scripts/module-manager.sh validate
```

### Test Alertmanager
```bash
curl -X POST http://localhost:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{"labels":{"alertname":"TestAlert","severity":"warning"},"annotations":{"summary":"Test alert"}}]'
```

## Creating Custom Modules

1. Create a directory under `modules/_custom/`:

```bash
mkdir -p modules/_custom/my_exporter
```

2. Create the module manifest `module.yaml`:

```yaml
module:
  name: my_exporter
  display_name: My Custom Exporter
  version: "1.0.0"
  description: Description of what it monitors
  category: custom

detection:
  commands:
    - "which my_service"
  systemd_services:
    - my_service
  files:
    - "/etc/my_service/config"
  confidence: 80

exporter:
  binary_name: my_exporter
  port: 9999
  download_url_template: "https://example.com/releases/v${VERSION}/my_exporter-${VERSION}.linux-${ARCH}.tar.gz"
  flags:
    - "--web.listen-address=:9999"

prometheus:
  job_name: my_exporter
  scrape_interval: 15s

host_config:
  required: []
  optional:
    custom_setting:
      type: string
      default: "value"
```

3. Create `install.sh`, `uninstall.sh`, `dashboard.json`, and `alerts.yml`

4. Validate the module:
```bash
./scripts/module-manager.sh validate my_exporter
```

## Maintenance

### Update retention
Edit `config/global.yaml` and restart services:
```bash
systemctl restart prometheus loki
```

### Regenerate all configs
```bash
./scripts/module-manager.sh generate-config
systemctl reload prometheus
systemctl restart grafana-server
```

### Renew SSL certificate
```bash
certbot renew
systemctl reload nginx
```

### Backup Grafana
```bash
cp -r /var/lib/grafana /backup/grafana-$(date +%Y%m%d)
```

## License

MIT
