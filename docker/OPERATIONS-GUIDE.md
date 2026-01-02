# CHOM Docker Environment - Operations Guide

Complete guide for daily operations and maintenance of the CHOM Docker test environment.

## Table of Contents

- [Quick Reference](#quick-reference)
- [Starting & Stopping](#starting--stopping)
- [Monitoring](#monitoring)
- [Logs](#logs)
- [Database Operations](#database-operations)
- [Backup & Restore](#backup--restore)
- [Troubleshooting](#troubleshooting)
- [Maintenance](#maintenance)

---

## Quick Reference

### Essential Commands

```bash
# Start environment
./scripts/setup.sh           # First time setup
make up                       # Start all services
docker compose up -d          # Start all services (alternative)

# Stop environment
make down                     # Stop all services
docker compose down           # Stop all services (alternative)

# View status
make ps                       # Container status
make health                   # Health check all services
./scripts/quick-test.sh       # Quick validation

# View logs
make logs                     # All logs
make logs-web                 # Web application logs
make logs-obs                 # Observability logs
docker compose logs -f web    # Follow web logs

# Monitoring
./scripts/monitor.sh          # Real-time monitoring
make metrics                  # View metrics endpoints

# Backup
./scripts/backup.sh           # Create backup

# Cleanup
./scripts/cleanup.sh          # Remove everything (WARNING!)
```

---

## Starting & Stopping

### First Time Setup

```bash
cd /home/calounx/repositories/mentat/docker

# Automated setup (recommended)
./scripts/setup.sh

# Manual setup
cp .env.example .env
docker compose build
docker compose up -d
```

### Starting Services

```bash
# Start all services
docker compose up -d

# Start specific service
docker compose up -d web
docker compose up -d observability

# Start with build
docker compose up -d --build

# Start and view logs
docker compose up
```

### Stopping Services

```bash
# Stop all services (preserves data)
docker compose stop

# Stop and remove containers (preserves volumes)
docker compose down

# Stop and remove everything including volumes (DANGER!)
docker compose down -v
```

### Restarting Services

```bash
# Restart all services
docker compose restart

# Restart specific service
docker compose restart web
docker compose restart observability

# Rebuild and restart
docker compose up -d --build
```

---

## Monitoring

### Real-Time Monitoring

```bash
# Live resource monitoring (updates every 5s)
./scripts/monitor.sh

# One-time stats
./scripts/monitor.sh --once

# Docker stats
docker stats chom-web chom-observability
```

### Service Health

```bash
# Comprehensive health check
./scripts/validate.sh

# Quick health check
./scripts/quick-test.sh

# Check specific service
docker compose exec web php artisan health:check
docker compose exec web supervisorctl status
```

### Accessing Services

```bash
# Open in browser
make grafana              # Open Grafana
make prometheus           # Open Prometheus

# Manual access
open http://localhost:8000    # Application
open http://localhost:3000    # Grafana (admin/admin)
open http://localhost:9090    # Prometheus
open http://localhost:9093    # Alertmanager
```

---

## Logs

### Viewing Logs

```bash
# All services
docker compose logs

# Follow all logs
docker compose logs -f

# Specific service
docker compose logs web
docker compose logs observability

# Last 100 lines
docker compose logs --tail=100

# Since specific time
docker compose logs --since 1h
docker compose logs --since 2023-01-01T10:00:00
```

### Application Logs

```bash
# Laravel logs
docker compose exec web tail -f storage/logs/laravel.log

# Nginx logs
docker compose exec web tail -f /var/log/nginx/access.log
docker compose exec web tail -f /var/log/nginx/error.log

# PHP-FPM logs
docker compose exec web tail -f /var/log/php-fpm/error.log

# MySQL logs
docker compose exec web tail -f /var/log/mysql/error.log

# Queue worker logs
docker compose exec web supervisorctl tail -f laravel-queue-worker:*
```

### Observability Logs

```bash
# Prometheus logs
docker compose exec observability supervisorctl tail -f prometheus

# Grafana logs
docker compose exec observability supervisorctl tail -f grafana

# Loki logs
docker compose exec observability supervisorctl tail -f loki
```

### Log Queries (Loki)

```bash
# Query logs via Loki API
curl -G -s http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={job="laravel"}' | jq

# Or use Grafana Explore:
# http://localhost:3000/explore
```

---

## Database Operations

### Accessing MySQL

```bash
# MySQL CLI
docker compose exec web mysql -u chom -psecret chom

# Run SQL file
docker compose exec -T web mysql -u chom -psecret chom < backup.sql

# Dump database
docker compose exec web mysqldump -u chom -psecret chom > backup.sql

# Import database
docker compose exec -T web mysql -u chom -psecret chom < backup.sql
```

### Laravel Migrations

```bash
# Run migrations
docker compose exec web php artisan migrate

# Rollback migrations
docker compose exec web php artisan migrate:rollback

# Fresh migrations (WARNING: drops all tables)
docker compose exec web php artisan migrate:fresh

# Seed database
docker compose exec web php artisan db:seed
```

### Redis Operations

```bash
# Redis CLI
docker compose exec web redis-cli

# Monitor Redis
docker compose exec web redis-cli monitor

# Flush cache
docker compose exec web redis-cli FLUSHALL
docker compose exec web php artisan cache:clear

# Check Redis memory
docker compose exec web redis-cli INFO memory
```

---

## Backup & Restore

### Creating Backups

```bash
# Automated backup (all volumes)
./scripts/backup.sh

# Manual MySQL backup
docker compose exec web mysqldump -u chom -psecret chom > mysql_backup.sql

# Manual volume backup
docker run --rm \
  -v docker_mysql-data:/data \
  -v $(pwd):/backup \
  debian:12-slim \
  tar czf /backup/mysql-data.tar.gz -C /data .
```

### Restoring Backups

```bash
# Restore MySQL
docker compose exec -T web mysql -u chom -psecret chom < mysql_backup.sql

# Restore volume
docker run --rm \
  -v docker_mysql-data:/data \
  -v $(pwd):/backup \
  debian:12-slim \
  tar xzf /backup/mysql-data.tar.gz -C /data
```

---

## Troubleshooting

### Service Not Starting

```bash
# Check logs
docker compose logs servicename

# Check container status
docker compose ps

# Inspect container
docker inspect chom-web

# Restart service
docker compose restart servicename

# Rebuild service
docker compose up -d --build servicename
```

### Permission Issues

```bash
# Fix Laravel storage permissions
docker compose exec web chmod -R 775 storage bootstrap/cache
docker compose exec web chown -R www-data:www-data storage bootstrap/cache
```

### Port Conflicts

```bash
# Check what's using the port
lsof -i :8000
lsof -i :3000

# Change ports in .env or docker-compose.yml
# Example: Change 8000 to 8001
ports:
  - "8001:80"
```

### Database Connection Issues

```bash
# Test MySQL connection
docker compose exec web mysql -u chom -psecret -e "SELECT 1"

# Check MySQL is running
docker compose ps mysql

# Restart MySQL
docker compose restart web
```

### Memory/Resource Issues

```bash
# Check resource usage
docker stats

# Increase limits in .env
WEB_MEM_LIMIT=8g
OBSERVABILITY_MEM_LIMIT=8g

# Restart with new limits
docker compose down
docker compose up -d
```

---

## Maintenance

### Updating Images

```bash
# Pull latest images
docker compose pull

# Rebuild images
docker compose build --no-cache

# Update and restart
docker compose pull
docker compose up -d --build
```

### Cleaning Up

```bash
# Remove stopped containers
docker compose down

# Remove volumes (WARNING: deletes data)
docker compose down -v

# Complete cleanup
./scripts/cleanup.sh

# Docker system cleanup
docker system prune -a
```

### Optimizing Storage

```bash
# Check disk usage
docker system df

# Remove unused images
docker image prune -a

# Remove unused volumes
docker volume prune

# Remove unused networks
docker network prune
```

### Health Checks

```bash
# Run comprehensive validation
./scripts/validate.sh

# Check individual services
curl http://localhost:8000/health
curl http://localhost:9090/-/healthy
curl http://localhost:3100/ready
curl http://localhost:3000/api/health
```

---

## Advanced Operations

### Scaling Workers

```bash
# Edit docker-compose.yml to add more workers
# Then restart
docker compose up -d --scale queue-worker=4
```

### Accessing Shell

```bash
# Web container
docker compose exec web bash

# Observability container
docker compose exec observability bash

# Root shell
docker compose exec -u root web bash
```

### Running Commands

```bash
# Laravel Artisan
docker compose exec web php artisan {command}

# Composer
docker compose exec web composer {command}

# NPM
docker compose exec web npm {command}

# Supervisor
docker compose exec web supervisorctl {command}
```

### Network Troubleshooting

```bash
# Inspect networks
docker network ls
docker network inspect docker_monitoring-net

# Test connectivity
docker compose exec web ping observability
docker compose exec observability ping web
```

---

## Scheduled Maintenance

### Daily

- Check service health: `./scripts/quick-test.sh`
- Review logs for errors: `make logs`
- Check resource usage: `./scripts/monitor.sh --once`

### Weekly

- Create backup: `./scripts/backup.sh`
- Check disk space: `docker system df`
- Review Grafana dashboards

### Monthly

- Update Docker images: `docker compose pull && docker compose up -d`
- Prune unused resources: `docker system prune`
- Review and rotate logs

---

## Support

For issues or questions:
1. Check logs: `docker compose logs`
2. Run validation: `./scripts/validate.sh`
3. Review documentation: `README.md`
4. Check troubleshooting section above

---

**Last Updated:** 2026-01-01
