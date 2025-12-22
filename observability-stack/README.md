# Observability Stack for Debian 13

A complete, production-ready observability stack without Docker. Monitors multiple web hosts running WordPress (via WordOps or similar).

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
└────────┼──────────────┼─────────────────────────────────────────┘
         │ scrape       │ push (promtail)
┌────────┴──────────────┴────────────────────────────────────────┐
│               MONITORED HOSTS                                   │
│  node_exporter │ nginx_exporter │ mysqld_exporter │ promtail   │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Configure `config/global.yaml`

Edit the configuration file with your settings:

```yaml
network:
  observability_vps_ip: "YOUR_VPS_IP"
  grafana_domain: "mentat.arewel.com"
  letsencrypt_email: "admin@arewel.com"

monitored_hosts:
  - name: "webserver-01"
    ip: "10.0.0.10"
    # ...

smtp:
  host: "smtp-relay.brevo.com"
  port: 587
  username: "your-brevo-email"
  password: "your-brevo-smtp-key"
  # ...

slack:
  webhook_url: "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
  # ...
```

### 2. Run Setup on Observability VPS

```bash
# Copy the entire observability-stack directory to your VPS
scp -r observability-stack root@YOUR_VPS_IP:/opt/

# SSH into the VPS
ssh root@YOUR_VPS_IP

# Run the setup script
cd /opt/observability-stack
./scripts/setup-observability.sh
```

### 3. Run Setup on Each Monitored Host

```bash
# Download and run the agent script
curl -sSL https://raw.githubusercontent.com/YOUR_REPO/setup-monitored-host.sh | \
  bash -s -- OBSERVABILITY_IP LOKI_URL LOKI_USER LOKI_PASS

# Or copy and run manually:
scp scripts/setup-monitored-host.sh root@MONITORED_HOST:/tmp/
ssh root@MONITORED_HOST '/tmp/setup-monitored-host.sh 10.0.0.5 https://mentat.arewel.com loki YOUR_PASSWORD'
```

## Directory Structure

```
observability-stack/
├── config/
│   └── global.yaml              # Main configuration file
├── prometheus/
│   ├── prometheus.yml.template  # Prometheus config template
│   └── rules/
│       ├── node_alerts.yml      # System alert rules
│       └── service_alerts.yml   # Service-specific alerts
├── loki/
│   └── loki-config.yaml         # Loki configuration
├── alertmanager/
│   ├── alertmanager.yml.template
│   └── templates/
│       └── email.tmpl           # Email notification template
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   └── datasources.yaml
│   │   └── dashboards/
│   │       └── dashboards.yaml
│   └── dashboards/
│       ├── overview.json        # Infrastructure overview
│       ├── node-exporter.json   # System metrics
│       ├── nginx.json           # Nginx metrics
│       ├── mysql.json           # MySQL/MariaDB metrics
│       ├── phpfpm.json          # PHP-FPM metrics
│       └── logs.json            # Log explorer
├── nginx/
│   └── observability.conf.template
├── scripts/
│   ├── setup-observability.sh   # Main setup script
│   └── setup-monitored-host.sh  # Agent setup script
└── README.md
```

## Pre-configured Dashboards

| Dashboard | Description |
|-----------|-------------|
| **Infrastructure Overview** | High-level view of all hosts, active alerts |
| **Node Exporter Details** | Detailed CPU, memory, disk, network per host |
| **Nginx** | Connections, requests, error rates |
| **MySQL/MariaDB** | Connections, QPS, InnoDB metrics |
| **PHP-FPM** | Process pool, queue, slow requests |
| **Logs Explorer** | Centralized log viewer with filters |

## Alert Rules

### System Alerts
- Instance down
- High CPU (>80%, >95%)
- High memory usage (>80%, >95%)
- Disk space low (>80%, >90%)
- Disk fill prediction (24h)
- High load average
- Systemd service failed

### Service Alerts
- Nginx down, high connections, 4xx/5xx error rates
- MySQL down, connection saturation, slow queries, replication lag
- PHP-FPM down, max children reached, queue filling

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

## Adding New Monitored Hosts

1. Add host to `config/global.yaml`:
```yaml
monitored_hosts:
  - name: "new-webserver"
    ip: "10.0.0.20"
    description: "New production server"
    exporters:
      - node_exporter
      - nginx_exporter
      - mysqld_exporter
      - phpfpm_exporter
```

2. Run agent setup on the new host:
```bash
./setup-monitored-host.sh OBSERVABILITY_IP LOKI_URL LOKI_USER LOKI_PASS
```

3. Regenerate Prometheus config and reload:
```bash
# On observability VPS
cd /opt/observability-stack
./scripts/setup-observability.sh  # Will update configs

# Or manually reload Prometheus
curl -X POST http://localhost:9090/-/reload
```

## Troubleshooting

### Check service status
```bash
systemctl status prometheus
systemctl status loki
systemctl status grafana-server
systemctl status alertmanager
systemctl status nginx
```

### View logs
```bash
journalctl -u prometheus -f
journalctl -u loki -f
journalctl -u grafana-server -f
```

### Test Prometheus targets
```bash
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {instance: .labels.instance, health: .health}'
```

### Test Alertmanager
```bash
# Send test alert
curl -X POST http://localhost:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{"labels":{"alertname":"TestAlert","severity":"warning"},"annotations":{"summary":"Test alert"}}]'
```

## Maintenance

### Update retention
Edit `config/global.yaml`:
```yaml
retention:
  metrics_days: 30
  logs_days: 14
```

Then restart services:
```bash
systemctl restart prometheus
systemctl restart loki
```

### Renew SSL certificate
```bash
certbot renew
systemctl reload nginx
```

### Backup Grafana
```bash
# Dashboards and settings
cp -r /var/lib/grafana /backup/grafana-$(date +%Y%m%d)
```

## License

MIT
