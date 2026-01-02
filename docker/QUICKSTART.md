# CHOM Docker Test Environment - Quick Start Guide

Get your CHOM test environment running in under 5 minutes!

## Prerequisites

- Docker 20.10+ installed and running
- Docker Compose 2.0+ installed
- At least 8GB RAM available
- At least 20GB free disk space
- CHOM Laravel application in `../chom/` directory

## Quick Start (3 Commands)

```bash
# 1. Navigate to docker directory
cd /home/calounx/repositories/mentat/docker

# 2. Run automated setup
./scripts/setup.sh

# 3. Access your environment
# Application:  http://localhost:8000
# Grafana:      http://localhost:3000 (admin/admin)
# Prometheus:   http://localhost:9090
```

That's it! The setup script will:
- Validate prerequisites
- Create configuration files
- Build Docker images (10-15 minutes first time)
- Start all services
- Run health checks
- Display access URLs

## Alternative: Manual Setup

```bash
# 1. Create environment file
cp .env.example .env

# 2. Build images
docker-compose build

# 3. Start services
docker-compose up -d

# 4. Check status
docker-compose ps

# 5. View logs
docker-compose logs -f
```

## Using Makefile (Recommended)

```bash
# View all available commands
make help

# Start environment
make up

# Check health
make health

# View logs
make logs

# Stop environment
make down
```

## Validation

After starting, validate everything is working:

```bash
./scripts/validate.sh
```

This runs 13 automated tests to ensure all components are operational.

## Common Commands

```bash
# View service status
make ps
# or
docker-compose ps

# View logs from all services
make logs
# or
docker-compose logs -f

# View logs from specific service
make logs-web
# or
docker-compose logs -f web

# Restart services
make restart
# or
docker-compose restart

# Run Laravel commands
docker-compose exec web php /var/www/chom/artisan migrate
docker-compose exec web php /var/www/chom/artisan tinker

# Access MySQL
docker-compose exec web mysql -u root -proot chom

# Access Redis
docker-compose exec web redis-cli

# Shell access
docker-compose exec web bash
```

## Access URLs

### Main Services
- **Application:** http://localhost:8000
- **Grafana:** http://localhost:3000 (admin/admin)
- **Prometheus:** http://localhost:9090
- **Alertmanager:** http://localhost:9093

### Metrics Endpoints
- **Node Exporter (Web):** http://localhost:9101/metrics
- **Nginx Exporter:** http://localhost:9113/metrics
- **MySQL Exporter:** http://localhost:9104/metrics
- **PHP-FPM Exporter:** http://localhost:9253/metrics

## Troubleshooting

### Services not starting?

```bash
# Check logs
docker-compose logs

# Check resource usage
docker stats

# Restart specific service
docker-compose restart web
```

### Application not accessible?

```bash
# Check Nginx logs
docker-compose logs web | grep nginx

# Verify health
curl http://localhost:8000/health
```

### Database issues?

```bash
# Check MySQL status
docker-compose exec web mysqladmin ping -h localhost

# View MySQL logs
docker-compose logs web | grep mysql
```

### Reset everything?

```bash
# Stop and remove all data (WARNING: destructive!)
docker-compose down -v

# Start fresh
docker-compose up -d
```

## Next Steps

1. **Explore Grafana** - http://localhost:3000
   - View pre-configured datasources
   - Explore metrics in Prometheus
   - Query logs in Loki
   - View traces in Tempo

2. **Check Prometheus** - http://localhost:9090
   - Navigate to Status > Targets
   - Verify all exporters are "UP"
   - Try example queries (see README.md)

3. **Test the Application** - http://localhost:8000
   - Access your Laravel application
   - Check logs with `make logs-web`
   - Run migrations with `docker-compose exec web php artisan migrate`

4. **Read Full Documentation** - See README.md for:
   - Detailed architecture overview
   - Advanced configuration
   - Performance tuning
   - Complete troubleshooting guide

## Need Help?

- Check `docker-compose logs` for errors
- Run `./scripts/validate.sh` to diagnose issues
- See README.md for detailed documentation
- Check container health with `docker-compose ps`

---

**Tip:** Use `make help` to see all available shortcuts!
