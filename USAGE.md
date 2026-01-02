# CHOM/Mentat Usage Guide

This guide covers the usage of the CHOM test environment, monitoring stack, and common operations.

## Table of Contents

1. [Test Environment Usage](#test-environment-usage)
2. [Monitoring and Observability](#monitoring-and-observability)
3. [Adding New Nodes](#adding-new-nodes)
4. [Running Tests](#running-tests)

---

## Test Environment Usage

The CHOM test environment simulates a 3-VPS infrastructure for regression testing:

| Container      | IP Address    | Role                                      |
|----------------|---------------|-------------------------------------------|
| mentat_tst     | 10.10.100.10  | Observability (Prometheus, Grafana, Loki) |
| landsraad_tst  | 10.10.100.20  | VPSManager/CHOM application (primary)     |
| richese_tst    | 10.10.100.30  | Hosting node (secondary web server)       |

### Starting and Stopping Containers

All container management is done via the `test-env.sh` script:

```bash
# Navigate to the docker directory
cd docker

# Start all VPS containers
./scripts/test-env.sh up

# Stop and remove containers
./scripts/test-env.sh down

# Reset to clean state (deletes all data and volumes)
./scripts/test-env.sh reset
```

### Checking Status

```bash
# Show status of all services
./scripts/test-env.sh status

# View container logs
./scripts/test-env.sh logs mentat_tst
./scripts/test-env.sh logs landsraad_tst
./scripts/test-env.sh logs richese_tst

# Open interactive shell in a container
./scripts/test-env.sh shell mentat_tst
./scripts/test-env.sh shell landsraad_tst
```

### Accessing Services

After starting containers, services are available at:

**Observability (mentat_tst - 10.10.100.10):**
- SSH: `ssh -p 2210 root@localhost`
- Grafana: http://localhost:3000 (admin/admin)
- Prometheus: http://localhost:9090
- Loki: http://localhost:3100
- Tempo: http://localhost:3200
- Alertmanager: http://localhost:9093
- Node Exporter: http://localhost:9110

**CHOM Application (landsraad_tst - 10.10.100.20):**
- SSH: `ssh -p 2220 root@localhost`
- Web Application: http://localhost:8000
- MySQL: `mysql -h localhost -P 3316 -u chom -psecret chom`
- Redis: `redis-cli -p 6389`

**Hosting Node (richese_tst - 10.10.100.30):**
- SSH: `ssh -p 2230 root@localhost`
- Web Application: http://localhost:8010
- MySQL: `mysql -h localhost -P 3326 -u richese -psecret richese`
- Redis: `redis-cli -p 6399`

### Running Deployments

Deploy the full stack to containers:

```bash
# Deploy everything (observability + vpsmanager)
./scripts/test-env.sh deploy

# Deploy only observability stack to mentat_tst
./scripts/test-env.sh deploy observability

# Deploy only vpsmanager stack to landsraad_tst
./scripts/test-env.sh deploy vpsmanager
```

Deployment scripts install and configure all required services:
- **Observability**: Prometheus, Grafana, Loki, Tempo, Alertmanager, Node Exporter
- **VPSManager**: Nginx, PHP-FPM, MariaDB, Redis, Laravel application, all exporters

### Database Access

Connect to MySQL from host:

```bash
# Connect to CHOM database on landsraad_tst
mysql -h localhost -P 3316 -u chom -psecret chom

# Connect as root
mysql -h localhost -P 3316 -u root -proot
```

Execute queries directly:

```bash
# Check migrations ran
mysql -h localhost -P 3316 -u chom -psecret chom -e "SHOW TABLES;"

# Check users
mysql -h localhost -P 3316 -u chom -psecret chom -e "SELECT id, email FROM users LIMIT 5;"
```

---

## Monitoring and Observability

### Grafana Dashboards

Access Grafana at http://localhost:3000 (default credentials: admin/admin).

Pre-configured dashboards include:
- **Node Exporter Full**: System metrics (CPU, memory, disk, network)
- **Nginx**: Request rates, response times, error rates
- **MySQL**: Query performance, connections, buffer pool
- **PHP-FPM**: Process states, request duration, memory

Import dashboards manually:
1. Go to Dashboards > Import
2. Enter dashboard ID from grafana.com or upload JSON
3. Select Prometheus as data source

### Prometheus Queries

Access Prometheus at http://localhost:9090.

**Common PromQL Queries:**

```promql
# Check all targets are up
up

# CPU usage percentage by host
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage percentage
100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))

# Disk usage percentage
100 - ((node_filesystem_avail_bytes{fstype!="tmpfs"} * 100) / node_filesystem_size_bytes)

# HTTP request rate
rate(nginx_http_requests_total[5m])

# PHP-FPM active processes
phpfpm_active_processes

# MySQL queries per second
rate(mysql_global_status_queries[5m])
```

**Checking Target Status:**

```bash
# Check targets via API
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Check specific metric
curl -s 'http://localhost:9090/api/v1/query?query=up' | jq '.data.result'
```

### Log Viewing with Loki

Access logs via Grafana's Explore feature or directly via API:

**Via Grafana:**
1. Go to Explore
2. Select Loki as data source
3. Build query using label selectors

**Common LogQL Queries:**

```logql
# All logs from landsraad_tst
{host="landsraad_tst"}

# Nginx access logs
{filename=~".*nginx.*access.*"}

# PHP-FPM logs
{filename=~".*php.*fpm.*"}

# Laravel application logs
{filename=~".*laravel.*"}

# Error logs only
{host="landsraad_tst"} |= "error"

# Nginx 500 errors
{filename=~".*nginx.*access.*"} |~ "\" 5[0-9]{2} "
```

**Via API:**

```bash
# Query logs from last hour
curl -sG 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={host="landsraad_tst"}' \
  --data-urlencode 'limit=100' | jq '.data.result[].values[]'
```

### Alertmanager Configuration

Access Alertmanager at http://localhost:9093.

**View Active Alerts:**

```bash
curl -s http://localhost:9093/api/v2/alerts | jq '.'
```

**Silence an Alert:**

```bash
# Create silence (replace values as needed)
curl -X POST http://localhost:9093/api/v2/silences \
  -H "Content-Type: application/json" \
  -d '{
    "matchers": [{"name": "alertname", "value": "HighCPU", "isRegex": false}],
    "startsAt": "2024-01-01T00:00:00Z",
    "endsAt": "2024-01-02T00:00:00Z",
    "createdBy": "admin",
    "comment": "Maintenance window"
  }'
```

---

## Adding New Nodes

To add a new VPS node to the test environment:

### 1. Create Host Configuration

Add a new service to `docker/docker-compose.vps.yml`:

```yaml
  newhost_tst:
    container_name: newhost_tst
    hostname: newhost-tst
    build:
      context: ./vps-base
      dockerfile: Dockerfile
    networks:
      vps-network:
        ipv4_address: 10.10.100.40  # Choose next available IP
    ports:
      # SSH
      - "2240:22"
      # HTTP/HTTPS
      - "8020:80"
      - "8463:443"
      # MySQL
      - "3336:3306"
      # Redis
      - "6409:6379"
      # Exporters
      - "9113:9100"   # Node Exporter
      - "9116:9113"   # Nginx Exporter
      - "9107:9104"   # MySQL Exporter
      - "9256:9253"   # PHP-FPM Exporter
    volumes:
      - ../observability-stack:/opt/observability-stack:ro
      - ./vps-base/scripts:/opt/scripts:ro
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
    tmpfs:
      - /run
      - /run/lock
    privileged: true
    cap_add:
      - SYS_ADMIN
    security_opt:
      - seccomp:unconfined
    environment:
      - TZ=UTC
      - DEPLOYMENT_ROLE=hosting
      - HOST_IP=10.10.100.40
      - HOST_NAME=newhost_tst
      - OBSERVABILITY_IP=10.10.100.10
      - DB_DATABASE=newhost
      - DB_USERNAME=newhost
      - DB_PASSWORD=secret
      - MYSQL_ROOT_PASSWORD=root
    restart: unless-stopped
    depends_on:
      mentat_tst:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "systemctl is-active multi-user.target || exit 0"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 15s
```

### 2. Update Prometheus Targets

Create target files in `/etc/prometheus/targets/` on mentat_tst:

```yaml
# /etc/prometheus/targets/newhost-node.yaml
- targets:
    - "10.10.100.40:9100"
  labels:
    host: "newhost_tst"
    env: "test"
    role: "vps"
    app: "newhost"
```

```yaml
# /etc/prometheus/targets/newhost-nginx.yaml
- targets:
    - "10.10.100.40:9113"
  labels:
    host: "newhost_tst"
    env: "test"
    role: "vps"
    app: "newhost"
```

Or use the deployment script which creates these automatically:

```bash
# Inside mentat_tst container
export HOSTING_NODE_2_IP="10.10.100.40"
export HOSTING_NODE_2_NAME="newhost_tst"
# Re-run deployment
bash /opt/scripts/deploy-observability.sh
```

### 3. Reload Prometheus

```bash
# Inside mentat_tst
kill -HUP $(pidof prometheus)
# Or
systemctl reload prometheus
```

---

## Running Tests

### Quick Regression Tests

```bash
# Run basic environment tests
./scripts/test-env.sh test
```

### Full Test Suite

```bash
cd docker/tests

# Run all tests
./run-all-tests.sh

# Run specific test suites
./run-all-tests.sh observability  # Prometheus, Loki, Grafana, Alertmanager, Tempo
./run-all-tests.sh chom           # Application and webserver tests
./run-all-tests.sh integration    # End-to-end metrics and logs flow
./run-all-tests.sh quick          # Fast smoke tests only
```

### Individual Test Scripts

```bash
# Observability tests
./tests/observability/test-prometheus.sh
./tests/observability/test-loki.sh
./tests/observability/test-grafana.sh
./tests/observability/test-alertmanager.sh
./tests/observability/test-tempo.sh

# CHOM application tests
./tests/chom/test-webserver.sh
./tests/chom/test-application.sh

# Integration tests
./tests/integration/test-metrics-flow.sh
./tests/integration/test-logs-flow.sh
```

### Test Environment Variables

Customize test behavior with environment variables:

```bash
# Override Prometheus host
PROMETHEUS_HOST=10.10.100.10 ./tests/observability/test-prometheus.sh

# Override web host and port
WEB_HOST=localhost WEB_PORT=8000 ./tests/chom/test-application.sh

# Increase timeout for slow connections
TIMEOUT=30 ./tests/observability/test-loki.sh
```

### Prerequisites for Tests

Tests require these tools on the host:
- `curl` - HTTP requests
- `jq` - JSON parsing
- `docker` - Container access
- `mysql-client` (optional) - Database tests
- `redis-cli` (optional) - Redis tests

```bash
# Install on Debian/Ubuntu
apt-get install curl jq docker.io mysql-client redis-tools
```

---

## Quick Reference

### Common Commands

```bash
# Start environment
cd docker && ./scripts/test-env.sh up

# Deploy all stacks
./scripts/test-env.sh deploy

# Run tests
./scripts/test-env.sh test

# View logs
./scripts/test-env.sh logs landsraad_tst

# Shell access
./scripts/test-env.sh shell mentat_tst

# Stop environment
./scripts/test-env.sh down

# Reset everything
./scripts/test-env.sh reset
```

### Service URLs

| Service      | URL                    | Credentials    |
|--------------|------------------------|----------------|
| Grafana      | http://localhost:3000  | admin/admin    |
| Prometheus   | http://localhost:9090  | -              |
| Loki         | http://localhost:3100  | -              |
| Alertmanager | http://localhost:9093  | -              |
| CHOM App     | http://localhost:8000  | -              |
| Hosting App  | http://localhost:8010  | -              |

### Health Check Endpoints

```bash
# Prometheus
curl http://localhost:9090/-/healthy

# Grafana
curl http://localhost:3000/api/health

# Loki
curl http://localhost:3100/ready

# Alertmanager
curl http://localhost:9093/-/healthy

# CHOM Application
curl http://localhost:8000/api/v1/health
```
