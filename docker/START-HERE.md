# 🚀 CHOM Docker Environment - START HERE

Welcome to the CHOM Docker Test Environment! This document will get you up and running in minutes.

## ⚡ Quick Start (3 Steps)

### 1. Navigate to Docker Directory

```bash
cd /home/calounx/repositories/mentat/docker
```

### 2. Run Setup

```bash
./scripts/setup.sh
```

This automated script will:
- ✅ Create `.env` configuration file
- ✅ Pull required Docker images
- ✅ Build custom images
- ✅ Start all services
- ✅ Run health checks
- ✅ Display access URLs

**Estimated time:** 5-10 minutes (depending on internet speed)

### 3. Access Your Environment

Once setup completes, access these URLs:

- **🌐 Application:** http://localhost:8000
- **📊 Grafana:** http://localhost:3000 (admin/admin)
- **📈 Prometheus:** http://localhost:9090
- **🔔 Alertmanager:** http://localhost:9093

---

## 🎯 What You Get

### Two Debian 12 Hosts

#### Host 1: Observability Stack
Complete monitoring platform with:
- Prometheus (metrics)
- Loki (logs)
- Tempo (traces)
- Grafana (dashboards)
- Alertmanager (alerts)
- 6 exporters

#### Host 2: Web Application
Full LAMP stack with:
- Nginx
- PHP 8.2-FPM
- MySQL 8.0
- Redis 7+
- Laravel CHOM
- Queue workers
- Scheduler

---

## 📚 Essential Commands

### Daily Operations

```bash
# Start services
make up                    # or: docker compose up -d

# Stop services
make down                  # or: docker compose down

# View status
make ps                    # Container status
make health                # Health checks

# View logs
make logs                  # All logs
make logs-web              # Web application
make logs-obs              # Observability

# Quick test
./scripts/quick-test.sh    # Fast validation
```

### Monitoring

```bash
# Real-time monitoring
./scripts/monitor.sh

# Access Grafana
make grafana              # or: open http://localhost:3000

# View metrics
make metrics              # List all metrics endpoints
```

### Database

```bash
# MySQL access
make mysql                # or: docker compose exec web mysql -u chom -psecret chom

# Run migrations
make migrate              # or: docker compose exec web php artisan migrate

# Backup database
./scripts/backup.sh
```

### Troubleshooting

```bash
# Validate setup
./scripts/validate.sh     # 13 comprehensive tests

# View logs
docker compose logs web
docker compose logs observability

# Restart services
docker compose restart
```

---

## 📖 Documentation

Choose your reading level:

### Getting Started
- **START-HERE.md** ⬅️ You are here
- **QUICKSTART.md** - 5-minute guide
- **DEPLOYMENT-COMPLETE.md** - Detailed setup guide

### Daily Operations
- **OPERATIONS-GUIDE.md** - Complete operations manual
- **Makefile** - `make help` for all commands
- **README.md** - Full documentation (650+ lines)

### Technical Details
- **DEPLOYMENT-SUMMARY.md** - Architecture overview
- `docker-compose.yml` - Service definitions
- `observability/` - Observability configs
- `web/` - Web application configs

---

## 🔧 Common Tasks

### View Application Logs

```bash
# Laravel logs
docker compose exec web tail -f storage/logs/laravel.log

# Nginx access logs
docker compose logs -f web | grep nginx

# All web services
make logs-web
```

### Run Artisan Commands

```bash
# Interactive
make artisan

# Specific command
docker compose exec web php artisan migrate
docker compose exec web php artisan queue:work
docker compose exec web php artisan cache:clear
```

### Access Container Shell

```bash
# Web container
docker compose exec web bash

# Observability container
docker compose exec observability bash

# Root access
docker compose exec -u root web bash
```

### Reset Everything

```bash
# Stop and remove (keeps volumes)
docker compose down

# Remove everything including data (DANGER!)
./scripts/cleanup.sh
```

---

## 📊 Available Services

### Application Services (Host 2)

| Service | Internal Port | External Port | Description |
|---------|--------------|---------------|-------------|
| Nginx | 80 | 8000 | Web server |
| PHP-FPM | 9000 | - | PHP runtime |
| MySQL | 3306 | 3306 | Database |
| Redis | 6379 | 6379 | Cache/Queue |

### Observability Services (Host 1)

| Service | Internal Port | External Port | Description |
|---------|--------------|---------------|-------------|
| Prometheus | 9090 | 9090 | Metrics DB |
| Grafana | 3000 | 3000 | Dashboards |
| Loki | 3100 | 3100 | Log aggregation |
| Tempo | 3200 | 3200 | Distributed tracing |
| Alertmanager | 9093 | 9093 | Alert routing |

### Metrics Exporters

| Exporter | Port | Metrics |
|----------|------|---------|
| Node (Web) | 9101 | System metrics |
| Node (Obs) | 9100 | System metrics |
| Nginx | 9113 | Web server metrics |
| MySQL | 9104 | Database metrics |
| PHP-FPM | 9253 | PHP metrics |

---

## 🎓 Learning Path

### Beginner
1. ✅ Run `./scripts/setup.sh`
2. ✅ Access http://localhost:8000
3. ✅ Open Grafana at http://localhost:3000
4. ✅ Run `./scripts/quick-test.sh`

### Intermediate
1. ✅ Review `OPERATIONS-GUIDE.md`
2. ✅ Explore Grafana dashboards
3. ✅ Query Prometheus metrics
4. ✅ Run `./scripts/validate.sh`

### Advanced
1. ✅ Customize configurations
2. ✅ Create custom dashboards
3. ✅ Set up alert rules
4. ✅ Review `DEPLOYMENT-SUMMARY.md`

---

## ⚠️ Troubleshooting

### Services Not Starting

```bash
# Check status
docker compose ps

# View errors
docker compose logs

# Restart
docker compose restart
```

### Port Already in Use

Edit `.env` and change ports:
```bash
# Change 8000 to 8001
# Edit docker-compose.yml ports section
ports:
  - "8001:80"
```

### Permission Denied

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Or run with bash
bash scripts/setup.sh
```

### Cannot Connect to Database

```bash
# Check MySQL is running
docker compose ps mysql

# Test connection
docker compose exec web mysql -u chom -psecret -e "SELECT 1"

# Restart services
docker compose restart
```

---

## 🆘 Getting Help

1. **Check Logs:**
   ```bash
   docker compose logs web
   docker compose logs observability
   ```

2. **Run Validation:**
   ```bash
   ./scripts/validate.sh
   ```

3. **Read Documentation:**
   - OPERATIONS-GUIDE.md (comprehensive guide)
   - README.md (full documentation)

4. **Check Container Status:**
   ```bash
   docker compose ps
   docker stats
   ```

---

## 📦 What's Included

- ✅ **27 configuration files**
- ✅ **2 Debian 12 hosts** (containerized)
- ✅ **18+ managed services**
- ✅ **6 metrics exporters**
- ✅ **25+ alert rules**
- ✅ **7 helper scripts**
- ✅ **1,500+ lines of documentation**
- ✅ **Production-grade setup**

---

## 🎯 Next Steps

Now that you're set up:

1. **Explore the Application**
   - Open http://localhost:8000
   - Register a new account
   - Test CHOM features

2. **Explore Monitoring**
   - Open Grafana: http://localhost:3000
   - Default login: admin/admin
   - Browse pre-configured dashboards

3. **Learn Operations**
   - Read OPERATIONS-GUIDE.md
   - Try `make help` for all commands
   - Experiment with monitoring

4. **Customize**
   - Edit configurations in `observability/` and `web/`
   - Create custom dashboards
   - Add alert rules

---

## 🚀 Ready to Start?

```bash
cd /home/calounx/repositories/mentat/docker
./scripts/setup.sh
```

**Welcome to CHOM!** 🎉

---

*For detailed documentation, see README.md or OPERATIONS-GUIDE.md*

**Last Updated:** 2026-01-01
