# CHOM Test Environment Setup

## Overview

This guide describes how to set up a two-node test environment for the CHOM SaaS platform on Debian 13 (Trixie):

| Node | Role | Components |
|------|------|------------|
| **mentat_tst** | Observability + Application | Prometheus, Grafana, Loki, Tempo, Alertmanager + CHOM Laravel app |
| **landsraad_tst** | Managed VPS Target | PHP, Nginx, MariaDB, Redis, Node Exporter (provisioned by CHOM) |

## Architecture

```
                    +-------------------------+
                    |      mentat_tst         |
                    |     (10.10.100.10)      |
                    +-------------------------+
                    |  Docker Containers:     |
                    |  - chom_observability   |
                    |  - chom_web             |
                    +-------------------------+
                              |
                              | Scrape metrics
                              | Ship logs
                              v
                    +-------------------------+
                    |    landsraad_tst        |
                    |     (10.10.100.20)      |
                    +-------------------------+
                    |  Native Services:       |
                    |  - Nginx + PHP-FPM      |
                    |  - MariaDB + Redis      |
                    |  - Node Exporter        |
                    |  - Promtail             |
                    +-------------------------+
```

## Prerequisites

### mentat_tst (Docker Host)
- Debian 13 (Trixie)
- Docker 24.0+
- Docker Compose 2.20+
- 4GB RAM minimum
- 20GB disk space

### landsraad_tst (VPS Target)
- Debian 13 (Trixie)
- SSH access with sudo
- 2GB RAM minimum
- 10GB disk space

## Quick Start

### 1. Set Up mentat_tst (Local Docker)

```bash
# Clone the repository (if not already done)
cd /home/calounx/repositories/mentat

# Navigate to docker directory
cd docker

# Create environment file
cp .env.test .env

# Generate a proper APP_KEY
NEW_KEY=$(openssl rand -base64 32)
sed -i "s|APP_KEY=.*|APP_KEY=base64:${NEW_KEY}|" .env

# Build and start containers
make build
make up

# Wait for services to start
make health

# Initialize Laravel
make migrate
```

### 2. Set Up landsraad_tst (Remote VPS)

```bash
# From mentat_tst, copy the setup script
scp chom/deploy/scripts/setup-vpsmanager-vps.sh deploy@10.10.100.20:/tmp/
scp chom/deploy/lib/deploy-common.sh deploy@10.10.100.20:/tmp/

# SSH to landsraad_tst and run setup
ssh deploy@10.10.100.20
sudo mkdir -p /opt/chom/deploy/lib
sudo mv /tmp/deploy-common.sh /opt/chom/deploy/lib/
sudo mv /tmp/setup-vpsmanager-vps.sh /opt/chom/deploy/scripts/
cd /opt/chom/deploy/scripts
sudo OBSERVABILITY_IP=10.10.100.10 bash setup-vpsmanager-vps.sh
```

### 3. Verify Setup

```bash
# On mentat_tst
cd docker
make health

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'
```

## Access URLs

### mentat_tst (via Docker)

| Service | URL | Credentials |
|---------|-----|-------------|
| CHOM Application | http://localhost:8000 | - |
| Grafana | http://localhost:3000 | admin / admin |
| Prometheus | http://localhost:9090 | - |
| Loki | http://localhost:3100 | - |
| Alertmanager | http://localhost:9093 | - |
| Tempo | http://localhost:3200 | - |

### landsraad_tst (Native)

| Service | URL | Notes |
|---------|-----|-------|
| VPSManager Dashboard | http://10.10.100.20:8080 | Password in /root/.vpsmanager-credentials |
| Node Exporter | http://10.10.100.20:9100 | Scraped by Prometheus |

## Container Names

All containers use the `chom_` prefix:
- `chom_observability` - Prometheus, Grafana, Loki, Tempo, Alertmanager
- `chom_web` - Nginx, PHP-FPM, MySQL, Redis, Laravel app

## Configuration Files

### Host Configurations

| File | Purpose |
|------|---------|
| `observability-stack/config/hosts/mentat_tst.yaml` | Observability host configuration |
| `observability-stack/config/hosts/landsraad_tst.yaml` | VPS target configuration |

### Docker Configuration

| File | Purpose |
|------|---------|
| `docker/.env` | Environment variables |
| `docker/docker-compose.yml` | Service definitions |
| `docker/observability/` | Observability stack configs |
| `docker/web/` | Web application configs |

## Common Operations

### Make Commands

```bash
# Start/Stop
make up              # Start all containers
make down            # Stop all containers
make restart         # Restart all containers

# Logs
make logs            # Tail all logs
make logs-web        # Tail web container logs
make logs-obs        # Tail observability logs

# Shell Access
make shell-web       # Shell into web container
make shell-obs       # Shell into observability container

# Database
make mysql           # MySQL console
make migrate         # Run migrations
make migrate-fresh   # Reset and migrate

# Testing
make test            # Run Laravel tests
make health          # Check service health
```

### Docker Commands

```bash
# View container status
docker ps --filter "name=chom_"

# View container logs
docker logs -f chom_web
docker logs -f chom_observability

# Execute commands in containers
docker exec -it chom_web bash
docker exec -it chom_observability sh
```

## Prometheus Scrape Targets

The observability stack scrapes metrics from:

### mentat_tst (localhost)
- `prometheus:9090` - Self-monitoring
- `grafana:3000` - Grafana metrics
- `loki:3100` - Loki metrics
- `alertmanager:9093` - Alertmanager metrics
- `tempo:3200` - Tempo metrics
- `node_exporter:9100` - System metrics

### chom_web Container
- `chom_web:9100` - Node exporter
- `chom_web:9113` - Nginx exporter
- `chom_web:9104` - MySQL exporter
- `chom_web:9253` - PHP-FPM exporter
- `chom_web:12345` - Alloy metrics

### landsraad_tst (10.10.100.20)
- `10.10.100.20:9100` - Node exporter
- `10.10.100.20:9113` - Nginx exporter
- `10.10.100.20:9104` - MySQL exporter
- `10.10.100.20:9253` - PHP-FPM exporter

## Troubleshooting

### Containers Won't Start

```bash
# Check container status
docker-compose ps

# View logs for specific service
docker-compose logs observability
docker-compose logs web

# Rebuild containers
make rebuild
```

### Network Connectivity Issues

```bash
# Test connectivity from web to observability
docker exec chom_web ping -c 3 chom_observability

# Check network configuration
docker network inspect docker_monitoring-net
```

### Database Connection Issues

```bash
# Check MySQL is running
docker exec chom_web mysqladmin ping -h 127.0.0.1

# View MySQL logs
docker exec chom_web tail -f /var/log/mysql/error.log
```

### Prometheus Targets Down

```bash
# Check target status
curl http://localhost:9090/api/v1/targets | jq

# Verify exporters are running
docker exec chom_web curl localhost:9100/metrics | head
docker exec chom_web curl localhost:9113/metrics | head
```

## Network Configuration

### Docker Networks

| Network | Subnet | Purpose |
|---------|--------|---------|
| observability-net | 172.20.0.0/24 | Observability internal |
| web-net | 172.21.0.0/24 | Web application internal |
| monitoring-net | 172.22.0.0/24 | Cross-container monitoring |

### Port Mappings

| Host Port | Container | Service |
|-----------|-----------|---------|
| 8000 | chom_web:80 | Nginx HTTP |
| 8443 | chom_web:443 | Nginx HTTPS |
| 3306 | chom_web:3306 | MySQL |
| 6379 | chom_web:6379 | Redis |
| 9090 | chom_observability:9090 | Prometheus |
| 3000 | chom_observability:3000 | Grafana |
| 3100 | chom_observability:3100 | Loki |
| 3200 | chom_observability:3200 | Tempo |
| 9093 | chom_observability:9093 | Alertmanager |

## Development Workflow

1. **Make code changes** in `chom/` directory
2. **Changes are auto-mounted** into the container
3. **Run tests**: `make test`
4. **Check application**: Visit http://localhost:8000
5. **View metrics**: Visit http://localhost:9090 (Prometheus) or http://localhost:3000 (Grafana)
6. **View logs**: Visit http://localhost:3000 and use Explore with Loki data source
