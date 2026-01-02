# CHOM Docker Test Environment

Production-like multi-host test environment for the CHOM Laravel SaaS platform, featuring a complete observability stack.

## Architecture Overview

This Docker environment simulates a production deployment with two separate hosts:

### Host 1: Observability Stack (chom-observability)
- **Prometheus** (v3.0.1) - Metrics collection and storage (15-day retention)
- **Loki** (v3.3.1) - Log aggregation and querying (31-day retention)
- **Tempo** (v2.6.1) - Distributed tracing
- **Grafana** (v11.4.0) - Unified visualization dashboard
- **Alertmanager** (v0.28.1) - Alert routing and management
- **Grafana Alloy** (v1.5.1) - OpenTelemetry collector for observability stack
- **Node Exporter** (v1.8.2) - System metrics

### Host 2: Web Application Stack (chom-web)
- **Nginx** - High-performance web server
- **PHP 8.2-FPM** - Laravel runtime with optimized configuration
- **MySQL 8.0** - Primary database
- **Redis 7+** - Cache, session store, and queue backend
- **Laravel CHOM** - Multi-tenant SaaS application
- **Queue Workers** - Background job processing (2 workers)
- **Scheduler** - Cron job management
- **Grafana Alloy** - Metrics and logs shipper to observability stack
- **Exporters** - Node, Nginx, MySQL, PHP-FPM metrics exporters

### Networking
- **observability-net** (172.20.0.0/24) - Internal observability network
- **web-net** (172.21.0.0/24) - Internal web application network
- **monitoring-net** (172.22.0.0/24) - Shared network for metrics/logs collection

## Quick Start

### Prerequisites
- Docker 20.10+ and Docker Compose 2.0+
- At least 8GB RAM available for Docker
- At least 20GB free disk space
- CHOM Laravel application in `../chom/` directory

### Installation

1. **Clone or navigate to the docker directory:**
   ```bash
   cd /home/calounx/repositories/mentat/docker
   ```

2. **Create environment file:**
   ```bash
   cp .env.example .env
   ```

3. **Edit .env file (optional):**
   ```bash
   nano .env
   # Adjust database credentials, passwords, etc.
   ```

4. **Start the environment:**
   ```bash
   docker-compose up -d
   ```

5. **View logs:**
   ```bash
   # All services
   docker-compose logs -f

   # Specific service
   docker-compose logs -f web
   docker-compose logs -f observability
   ```

6. **Check service health:**
   ```bash
   docker-compose ps
   ```

### First-Time Setup

When the containers start for the first time, the web application will:
1. Wait for MySQL and Redis to be ready
2. Install Composer dependencies (if `vendor/` doesn't exist)
3. Create `.env` file from `.env.example` (if missing)
4. Generate Laravel application key (if missing)
5. Run database migrations
6. Seed database with test data (in local/development mode)
7. Install NPM dependencies and build frontend assets
8. Cache Laravel configuration, routes, and views

This process takes approximately 2-5 minutes depending on your system.

## Access URLs

### Web Application
- **Application:** http://localhost:8000
- **Application (HTTPS):** https://localhost:8443

### Observability Stack
- **Grafana:** http://localhost:3000
  - Username: `admin`
  - Password: `admin`
- **Prometheus:** http://localhost:9090
- **Alertmanager:** http://localhost:9093
- **Loki:** http://localhost:3100

### Exporters (Metrics Endpoints)
- **Observability Node Exporter:** http://localhost:9100/metrics
- **Web Node Exporter:** http://localhost:9101/metrics
- **Nginx Exporter:** http://localhost:9113/metrics
- **MySQL Exporter:** http://localhost:9104/metrics
- **PHP-FPM Exporter:** http://localhost:9253/metrics

### Optional Services (uncomment in docker-compose.yml)
- **Redis Commander:** http://localhost:8081
- **Adminer:** http://localhost:8080
- **MailHog:** http://localhost:8025

## Service Management

### Start all services
```bash
docker-compose up -d
```

### Stop all services
```bash
docker-compose down
```

### Restart specific service
```bash
docker-compose restart web
docker-compose restart observability
```

### View service status
```bash
docker-compose ps
```

### View resource usage
```bash
docker stats
```

### Execute commands in containers
```bash
# Laravel artisan commands
docker-compose exec web php /var/www/chom/artisan migrate
docker-compose exec web php /var/www/chom/artisan tinker

# MySQL console
docker-compose exec web mysql -u root -proot chom

# Redis CLI
docker-compose exec web redis-cli

# Shell access
docker-compose exec web bash
docker-compose exec observability bash
```

## Monitoring & Observability

### Grafana Dashboards

Access Grafana at http://localhost:3000 with credentials `admin/admin`.

#### Pre-configured Datasources:
1. **Prometheus** - Application and infrastructure metrics
2. **Loki** - Centralized logs from all services
3. **Tempo** - Distributed tracing
4. **Alertmanager** - Alert management

#### Example Queries:

**Prometheus (Metrics):**
- CPU Usage: `rate(node_cpu_seconds_total{mode!="idle"}[5m])`
- Memory Usage: `node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100`
- Nginx Requests: `rate(nginx_http_requests_total[5m])`
- PHP-FPM Active Processes: `phpfpm_active_processes`
- MySQL Queries: `rate(mysql_global_status_queries[5m])`

**Loki (Logs):**
- All Nginx logs: `{job="nginx"}`
- Nginx errors: `{job="nginx-error"}`
- Laravel logs: `{job="laravel"}`
- PHP-FPM logs: `{job="php-fpm"}`
- MySQL slow queries: `{job="mysql"} |= "slow"`
- Error level logs: `{level="error"}`

### Prometheus Targets

Access Prometheus at http://localhost:9090 and navigate to Status > Targets to verify all exporters are healthy.

### Alertmanager

Access Alertmanager at http://localhost:9093 to view and manage alerts.

## Troubleshooting

### Services not starting

1. **Check logs:**
   ```bash
   docker-compose logs web
   docker-compose logs observability
   ```

2. **Check disk space:**
   ```bash
   df -h
   docker system df
   ```

3. **Check available memory:**
   ```bash
   free -h
   docker stats
   ```

### MySQL connection errors

1. **Wait for MySQL to initialize:**
   MySQL takes 30-60 seconds to initialize on first startup.

2. **Check MySQL logs:**
   ```bash
   docker-compose logs web | grep mysql
   ```

3. **Verify MySQL is running:**
   ```bash
   docker-compose exec web mysqladmin ping -h localhost
   ```

### Laravel application not accessible

1. **Check Nginx logs:**
   ```bash
   docker-compose exec web tail -f /var/log/nginx/chom-error.log
   ```

2. **Check PHP-FPM logs:**
   ```bash
   docker-compose exec web tail -f /var/log/php-fpm/error.log
   ```

3. **Verify application permissions:**
   ```bash
   docker-compose exec web ls -la /var/www/chom/storage
   ```

### Observability services not collecting data

1. **Check Alloy status:**
   ```bash
   # Web application Alloy
   docker-compose exec web curl http://localhost:12345/metrics

   # Observability Alloy
   docker-compose exec observability curl http://localhost:12345/metrics
   ```

2. **Verify network connectivity:**
   ```bash
   docker-compose exec web ping -c 3 chom-observability
   docker-compose exec observability ping -c 3 chom-web
   ```

3. **Check Prometheus targets:**
   Visit http://localhost:9090/targets and ensure all targets are "UP"

### High resource usage

1. **Reduce resource limits in docker-compose.yml:**
   ```yaml
   mem_limit: 2g
   cpus: 1.0
   ```

2. **Reduce number of queue workers:**
   Edit `web/supervisor/supervisord.conf` and change `numprocs=2` to `numprocs=1`

3. **Disable unused services:**
   Comment out services in `docker-compose.yml` that you don't need.

### Reset environment

**Warning: This will delete all data!**

```bash
# Stop and remove containers, networks, volumes
docker-compose down -v

# Remove all images (optional)
docker-compose down --rmi all

# Start fresh
docker-compose up -d
```

## Advanced Configuration

### Custom Nginx Configuration

Edit `web/nginx/chom.conf` to modify Laravel application nginx settings:
```bash
nano web/nginx/chom.conf
docker-compose restart web
```

### Custom PHP Configuration

Edit `web/php/php.ini` for PHP settings:
```bash
nano web/php/php.ini
docker-compose restart web
```

### Custom MySQL Configuration

Edit `web/mysql/my.cnf` for MySQL tuning:
```bash
nano web/mysql/my.cnf
docker-compose restart web
```

### Adding Prometheus Alert Rules

1. Create alert rules in `observability/prometheus/rules/`:
   ```bash
   mkdir -p observability/prometheus/rules
   nano observability/prometheus/rules/alerts.yml
   ```

2. Restart Prometheus:
   ```bash
   docker-compose restart observability
   ```

### Custom Grafana Dashboards

1. Place JSON dashboard files in `observability/grafana/dashboards/json/`
2. Dashboards will be auto-loaded by Grafana

### Scaling Queue Workers

Edit `web/supervisor/supervisord.conf` and change `numprocs`:
```ini
[program:laravel-queue-worker]
numprocs=4  # Increase from 2 to 4 workers
```

Then restart:
```bash
docker-compose restart web
```

## File Structure

```
docker/
├── docker-compose.yml              # Main orchestration file
├── .env.example                    # Environment variables template
├── README.md                       # This file
│
├── observability/                  # Observability stack
│   ├── Dockerfile                  # Observability host image
│   ├── supervisord.conf            # Service manager configuration
│   ├── prometheus/
│   │   └── prometheus.yml          # Prometheus configuration
│   ├── loki/
│   │   └── loki-config.yml         # Loki configuration
│   ├── tempo/
│   │   └── tempo-config.yml        # Tempo configuration
│   ├── alertmanager/
│   │   └── alertmanager.yml        # Alertmanager configuration
│   ├── grafana/
│   │   ├── grafana.ini             # Grafana configuration
│   │   ├── datasources/
│   │   │   └── datasources.yml     # Auto-provisioned datasources
│   │   └── dashboards/
│   │       ├── dashboards.yml      # Dashboard provider config
│   │       └── json/               # Dashboard JSON files
│   └── alloy/
│       └── config.alloy            # Alloy collector config
│
└── web/                            # Web application stack
    ├── Dockerfile                  # Web application host image
    ├── nginx/
    │   ├── nginx.conf              # Main nginx configuration
    │   └── chom.conf               # Laravel site configuration
    ├── php/
    │   ├── php-fpm.conf            # PHP-FPM pool configuration
    │   └── php.ini                 # PHP settings
    ├── mysql/
    │   └── my.cnf                  # MySQL configuration
    ├── supervisor/
    │   └── supervisord.conf        # Service manager configuration
    ├── alloy/
    │   └── config.alloy            # Alloy shipper configuration
    └── scripts/
        ├── init-app.sh             # Application initialization
        └── healthcheck.sh          # Health check script
```

## Performance Tuning

### For Development (Low Resources)
- Reduce `mem_limit` to `2g` for both services
- Reduce `cpus` to `1.0`
- Set `numprocs=1` for queue workers
- Disable unused exporters

### For Testing (Medium Resources)
- Use default configuration (4GB RAM per service)
- 2 CPUs per service
- 2 queue workers

### For Production-like Testing (High Resources)
- Increase `mem_limit` to `8g`
- Increase `cpus` to `4.0`
- Increase queue workers to `4-8`
- Enable all exporters and monitoring

## Security Considerations

### For Production Deployment

This is a **test environment**. For production, implement:

1. **Strong passwords** - Change all default passwords
2. **TLS/SSL** - Enable HTTPS with valid certificates
3. **Firewall rules** - Restrict access to management ports
4. **Security scanning** - Run vulnerability scans on images
5. **Secrets management** - Use Docker secrets or external vaults
6. **Network isolation** - Use separate networks with proper firewall rules
7. **Log rotation** - Configure log rotation to prevent disk filling
8. **Regular updates** - Keep all images and packages updated
9. **Backup strategy** - Implement regular backups of volumes
10. **Monitoring alerts** - Configure production alerting channels

## Support & Documentation

### Useful Commands

```bash
# View all container logs
docker-compose logs -f

# Check container health
docker-compose ps

# Rebuild images
docker-compose build --no-cache

# View resource usage
docker stats

# Clean up unused resources
docker system prune -a

# Export/backup database
docker-compose exec web mysqldump -u root -proot chom > backup.sql

# Import database
docker-compose exec -T web mysql -u root -proot chom < backup.sql
```

### Component Versions

- Debian: 12 (Bookworm)
- PHP: 8.2
- Nginx: Latest stable
- MySQL: 8.0
- Redis: 7+
- Node.js: 20
- Composer: 2.7.1
- Prometheus: 3.0.1
- Loki: 3.3.1
- Tempo: 2.6.1
- Grafana: 11.4.0
- Alertmanager: 0.28.1
- Grafana Alloy: 1.5.1
- Node Exporter: 1.8.2
- Nginx Exporter: 1.3.0
- MySQL Exporter: 0.16.0
- PHP-FPM Exporter: 2.2.0

### Resources

- [Docker Documentation](https://docs.docker.com/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Laravel Documentation](https://laravel.com/docs)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/)
- [Tempo Documentation](https://grafana.com/docs/tempo/)

## License

This Docker environment configuration is part of the CHOM project and follows the same license.

---

**Created:** 2025-01-01
**Version:** 1.0.0
**Maintainer:** CHOM Team
