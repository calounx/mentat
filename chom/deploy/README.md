# CHOM Infrastructure Deployment

Deploy the CHOM SaaS platform infrastructure to vanilla Debian 13 VPS servers.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Control Plane                          │
│               (Laravel Application)                     │
└───────────────────────────┬─────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────┐
│   OVH VPS 1      │ │   OVH VPS 2      │ │  Additional  │
│ (Observability)  │ │  (VPSManager)    │ │   VPS...     │
│                  │ │                  │ │              │
│ - Prometheus     │ │ - Nginx          │ │ - WordPress  │
│ - Loki           │ │ - PHP-FPM        │ │   Sites      │
│ - Grafana        │ │ - MariaDB        │ │              │
│ - Alertmanager   │ │ - Redis          │ │              │
└──────────────────┘ └──────────────────┘ └──────────────┘
```

## Prerequisites

1. **Two OVH VPS servers** with Debian 13 installed
   - VPS 1 (Observability): Minimum 2GB RAM, 1 vCPU, 20GB disk
   - VPS 2 (VPSManager): Minimum 4GB RAM, 2 vCPU, 80GB disk

2. **Local machine requirements:**
   - SSH access to both VPS servers
   - `yq` installed: `sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod +x /usr/local/bin/yq`

## Quick Start

### 1. Configure Inventory

Edit `configs/inventory.yaml` with your VPS details:

```yaml
observability:
  ip: 1.2.3.4  # VPS 1 IP address
  hostname: obs.yourdomain.com

vpsmanager:
  ip: 5.6.7.8  # VPS 2 IP address
  hostname: wp.yourdomain.com
```

### 2. Generate SSH Key

```bash
./deploy.sh
# First run generates SSH key and shows public key
```

### 3. Add SSH Key to VPS Servers

Copy the public key shown and add it to both VPS servers:

```bash
# On each VPS as root:
mkdir -p ~/.ssh
echo "your-public-key-here" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### 4. Deploy

```bash
# Deploy everything
./deploy.sh all

# Or deploy individually
./deploy.sh observability
./deploy.sh vpsmanager
```

## Post-Deployment

### Observability Stack (VPS 1)

After deployment, you'll receive:
- **Grafana URL**: `http://<VPS1-IP>:80`
- **Grafana credentials**: Shown in deployment output

Credentials are also saved to `/root/.observability-credentials` on the VPS.

### VPSManager (VPS 2)

After deployment, you'll receive:
- **Dashboard URL**: `http://<VPS2-IP>:8080`
- **Dashboard password**: Shown in deployment output
- **MySQL root password**: Shown in deployment output

Credentials are saved to `/root/.vpsmanager-credentials` on the VPS.

## Connecting VPSManager to Observability

The VPSManager VPS automatically installs Node Exporter. To add it to Prometheus:

1. SSH to the Observability VPS
2. Edit `/etc/observability/prometheus/prometheus.yml`
3. Add under `scrape_configs`:

```yaml
  - job_name: 'vpsmanager'
    static_configs:
      - targets: ['<VPS2-IP>:9100']
        labels:
          role: vpsmanager
          tenant_id: internal
```

4. Reload Prometheus: `curl -X POST http://localhost:9090/-/reload`

## Directory Structure

```
deploy/
├── deploy.sh              # Main deployment script
├── configs/
│   └── inventory.yaml     # VPS configuration
├── scripts/
│   ├── setup-observability-vps.sh  # Observability setup
│   └── setup-vpsmanager-vps.sh     # VPSManager setup
├── keys/
│   └── chom_deploy_key    # SSH key (generated)
└── README.md
```

## Troubleshooting

### SSH Connection Failed

```bash
# Test SSH connection manually
ssh -i keys/chom_deploy_key root@<VPS-IP>
```

### Service Not Starting

```bash
# Check service status
systemctl status <service-name>

# View logs
journalctl -u <service-name> -f
```

### Firewall Issues

```bash
# List firewall rules
ufw status verbose

# Allow additional port
ufw allow <port>/tcp
```

## Security Notes

1. **Change default passwords** after deployment
2. **Enable SSL** with Let's Encrypt:
   ```bash
   certbot --nginx -d grafana.yourdomain.com
   ```
3. **Restrict Prometheus/Loki** to internal access only
4. **Regular backups** of `/var/lib/observability` and `/var/www`

## Ports Reference

| Port | Service | VPS |
|------|---------|-----|
| 22 | SSH | Both |
| 80 | HTTP/Grafana | Observability |
| 443 | HTTPS | Both |
| 3100 | Loki | Observability |
| 8080 | VPSManager Dashboard | VPSManager |
| 9090 | Prometheus | Observability |
| 9093 | Alertmanager | Observability |
| 9100 | Node Exporter | Both |
