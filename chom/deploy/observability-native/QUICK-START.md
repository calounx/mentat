# Quick Start Guide - Native Observability Stack

## 5-Minute Installation

For experienced administrators who want to get up and running quickly.

### Prerequisites

- Debian 11+ (root access)
- 4GB RAM, 20GB disk
- Internet connection

### One-Command Installation

```bash
cd /home/calounx/repositories/mentat/chom/deploy/observability-native
sudo bash install-all.sh
```

That's it! The script will:
1. Check system requirements
2. Install all components (Prometheus, Grafana, Loki, Promtail, AlertManager, Node Exporter)
3. Configure services
4. Start everything
5. Run health checks

Installation time: 15-20 minutes

### Access Services

After installation completes:

```bash
# Grafana (dashboards)
http://mentat.arewel.com:3000
Username: admin
Password: changeme

# Prometheus (metrics)
http://mentat.arewel.com:9090

# AlertManager (alerts)
http://mentat.arewel.com:9093
```

### First Steps After Installation

```bash
# 1. CHANGE GRAFANA PASSWORD IMMEDIATELY
sudo grafana-cli admin reset-admin-password YOUR_SECURE_PASSWORD

# 2. Check all services are running
sudo bash manage-services.sh status

# 3. View health status
sudo bash manage-services.sh health

# 4. Check service summary
cat /root/observability-stack-info.txt
```

### Deploy to Application Server

```bash
# On application server (landsraad.arewel.com)
# Copy scripts
scp mentat.arewel.com:/home/calounx/repositories/mentat/chom/deploy/observability-native/install-promtail.sh .
scp mentat.arewel.com:/home/calounx/repositories/mentat/chom/deploy/observability-native/install-node-exporter.sh .

# Install
sudo bash install-promtail.sh
sudo bash install-node-exporter.sh

# Verify
systemctl status promtail node_exporter
```

### Verify Everything Works

```bash
# Check Prometheus targets (all should be "up")
curl http://localhost:9090/api/v1/targets | grep '"health":"up"'

# Check logs are being collected
curl -G http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={job="chom"}' | grep -q stream

# Send test alert
curl -X POST http://localhost:9093/api/v2/alerts -H "Content-Type: application/json" -d '[{
  "labels": {"alertname": "TestAlert", "severity": "info"},
  "annotations": {"summary": "Test", "description": "Test alert"}
}]'
```

### Common Commands

```bash
# Service management
sudo bash manage-services.sh          # Interactive menu
sudo bash manage-services.sh status   # Show status
sudo bash manage-services.sh restart  # Restart all
sudo bash manage-services.sh logs prometheus 100  # View logs

# Individual services
sudo systemctl status prometheus
sudo systemctl restart grafana-server
sudo journalctl -u loki -f

# Health checks
sudo bash manage-services.sh health
sudo bash manage-services.sh ports
sudo bash manage-services.sh disk
```

### Troubleshooting

**Service won't start?**
```bash
sudo journalctl -u <service-name> -n 50
sudo systemctl status <service-name>
```

**Can't access web interface?**
```bash
sudo bash manage-services.sh ports
sudo ufw status
```

**No metrics/logs?**
```bash
# Check targets
curl http://localhost:9090/api/v1/targets

# Check network
curl http://app-server:9100/metrics
```

### Next Steps

1. Read DEPLOYMENT-GUIDE.md for detailed configuration
2. Import Grafana dashboards
3. Configure AlertManager email notifications
4. Set up backup automation
5. Review security settings

### Uninstall

```bash
sudo bash uninstall-all.sh
```

### Help

- Full documentation: README.md
- Deployment guide: DEPLOYMENT-GUIDE.md
- Implementation details: IMPLEMENTATION-SUMMARY.md
- Service management: `sudo bash manage-services.sh --help`

---

**Quick Reference**

| Service | Port | Config | Data |
|---------|------|--------|------|
| Prometheus | 9090 | /etc/prometheus | /var/lib/prometheus |
| Grafana | 3000 | /etc/grafana | /var/lib/grafana |
| Loki | 3100 | /etc/loki | /var/lib/loki |
| Promtail | 9080 | /etc/promtail | /var/lib/promtail |
| AlertManager | 9093 | /etc/alertmanager | /var/lib/alertmanager |
| Node Exporter | 9100 | - | - |

**Service Control**
```bash
systemctl start|stop|restart|status <service>
journalctl -u <service> -f
```

**Files**
- Summary: /root/observability-stack-info.txt
- Credentials: /root/grafana-credentials.txt
- Install log: /var/log/observability-install.log
