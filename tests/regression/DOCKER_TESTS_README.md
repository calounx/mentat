# Docker Environment Regression Test Suite

Comprehensive regression testing framework for all Docker test environments in the CHOM/Mentat project.

## Overview

This test suite validates three Docker environments:

1. **Main Test Environment** (`docker/docker-compose.yml`)
   - 2 containers: `chom_observability` + `chom_web`
   - Networks: observability-net (172.20.0.0/24), web-net (172.21.0.0/24), monitoring-net (172.22.0.0/24)
   - Services: Prometheus, Loki, Tempo, Grafana, Alertmanager, Nginx, PHP-FPM, MySQL, Redis

2. **VPS Simulation** (`docker/docker-compose.vps.yml`)
   - 3 containers: `mentat_tst`, `landsraad_tst`, `richese_tst`
   - Network: 10.10.100.0/24
   - Debian 13 with systemd support

3. **Development Environment** (`chom/docker-compose.yml`)
   - 10+ services: MySQL, Redis, MailHog, MinIO, Prometheus, Grafana, Loki, etc.
   - For local CHOM development

## Test Phases

### Phase 1: Environment Setup Tests
- Docker Compose syntax validation
- Port conflict detection
- Volume mount verification
- Network configuration validation
- Environment variable completeness
- Container startup tests
- Health check validation
- Resource limit verification

### Phase 2: Service-Level Tests
- **Observability Stack:**
  - Prometheus: Metrics collection, API endpoints
  - Loki: Log ingestion, query API
  - Grafana: UI accessibility, login, datasources
  - Tempo: OTLP endpoints (gRPC/HTTP)
  - Alertmanager: API health
  - Node Exporter: Metrics export

- **Web Stack:**
  - Nginx: HTTP/HTTPS endpoints
  - MySQL: Database connectivity, operations
  - Redis: Key-value operations
  - All exporters: Metrics format validation

- **VPS Simulation:**
  - systemd functionality
  - SSH accessibility
  - Inter-container networking

### Phase 3: Integration Tests
- Prometheus target scraping
- Metrics collection verification
- Grafana datasource connectivity
- Loki log ingestion and retrieval
- MySQL database operations
- Redis cache operations
- Application-to-database connectivity
- Metrics exporter integration

### Phase 4: Persistence Tests
- Prometheus data persistence across restarts
- Grafana dashboard persistence
- MySQL data persistence
- Redis data persistence (AOF/RDB)
- Loki log persistence
- Volume integrity checks
- Full stop/start cycle validation

## Quick Start

### Prerequisites

```bash
# Required tools
- Docker 20.10+
- Docker Compose v2.0+
- jq (JSON processor)
- curl
- mysql client (optional, for database tests)
- redis-cli (optional, for Redis tests)
```

### Run All Tests

```bash
./docker-environments-test.sh
```

### Run Specific Environment

```bash
# Main test environment only
./docker-environments-test.sh --main-only

# VPS simulation only
./docker-environments-test.sh --vps-only

# Development environment only
./docker-environments-test.sh --dev-only
```

### Quick Test (Skip Persistence)

```bash
./docker-environments-test.sh --skip-persistence
```

### Verbose Output

```bash
./docker-environments-test.sh -v
```

### Keep Environment Running (No Cleanup)

```bash
./docker-environments-test.sh --no-cleanup
```

## Usage Examples

```bash
# Full regression test with verbose output
VERBOSE=true ./docker-environments-test.sh

# Test main environment without cleanup (for debugging)
./docker-environments-test.sh --main-only --no-cleanup

# Quick validation of all environments
./docker-environments-test.sh --skip-persistence

# Test specific environment with custom report directory
./docker-environments-test.sh --vps-only --report-dir /tmp/test-reports
```

## Cleanup

### Clean All Environments

```bash
./cleanup.sh --all
```

### Clean Specific Environment

```bash
./cleanup.sh --main
./cleanup.sh --vps
./cleanup.sh --dev
```

### Full Cleanup (Including Volumes)

```bash
# WARNING: This deletes all data!
./cleanup.sh --all --volumes --force
```

### Prune Docker Resources

```bash
./cleanup.sh --all --prune
```

## Output and Reports

Test results are saved in `reports/` directory:

- **test-execution.log** - Detailed execution log
- **test-results.json** - Machine-readable test results
- **test-results.md** - Human-readable test report

### JSON Report Format

```json
{
  "test_suite": "Docker Environment Regression Tests",
  "timestamp": "2026-01-02T12:00:00+00:00",
  "duration": 180,
  "summary": {
    "total": 45,
    "passed": 42,
    "failed": 1,
    "warnings": 2
  },
  "results": {
    "Test Name": {
      "status": "PASS|FAIL|WARN",
      "duration": "5s"
    }
  }
}
```

## Exit Codes

- **0** - All tests passed
- **1** - Tests passed with warnings
- **2** - Test failures detected

## Directory Structure

```
tests/regression/
├── DOCKER_TESTS_README.md             # This file
├── docker-environments-test.sh        # Main test execution script
├── cleanup.sh                         # Cleanup utility
├── lib/                               # Test libraries
│   ├── test-utils.sh                  # Common utilities
│   ├── phase1-setup-tests.sh          # Environment setup tests
│   ├── phase2-service-tests.sh        # Service-level tests
│   ├── phase3-integration-tests.sh    # Integration tests
│   └── phase4-persistence-tests.sh    # Persistence tests
└── reports/                           # Test reports (generated)
    ├── test-execution.log
    ├── test-results.json
    └── test-results.md
```

## Continuous Integration

### GitHub Actions Example

```yaml
name: Docker Environment Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y jq mysql-client redis-tools
      - name: Run regression tests
        run: |
          cd tests/regression
          ./docker-environments-test.sh --skip-persistence
      - name: Upload test reports
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: test-reports
          path: tests/regression/reports/
```

## Troubleshooting

### Test Failures

1. **Check logs**: `cat reports/test-execution.log`
2. **Inspect containers**: `docker compose -f <file> ps`
3. **View container logs**: `docker logs <container_name>`
4. **Run with no cleanup**: `./docker-environments-test.sh --no-cleanup`
5. **Manually inspect**: `docker exec -it <container> bash`

### Port Conflicts

If ports are already in use:
```bash
# Stop conflicting services
./cleanup.sh --all

# Or check what's using the port
sudo netstat -tulpn | grep <port>
```

### Volume Issues

If volumes are corrupted:
```bash
# Remove all volumes (WARNING: deletes data)
./cleanup.sh --all --volumes --force
```

### Permission Issues

Ensure scripts are executable:
```bash
chmod +x docker-environments-test.sh cleanup.sh lib/*.sh
```

## Performance Benchmarks

Typical execution times (on modern hardware):

- **Phase 1 (Setup)**: 30-60s per environment
- **Phase 2 (Services)**: 60-90s per environment
- **Phase 3 (Integration)**: 30-45s per environment
- **Phase 4 (Persistence)**: 90-120s per environment

**Total**: ~5-8 minutes for all environments (full test suite)
**Quick Test** (skip persistence): ~3-4 minutes

## Contributing

When adding new tests:

1. Add test functions to appropriate phase library
2. Follow existing naming conventions (`test_<name>`)
3. Use `start_test` and `end_test` for tracking
4. Use assertion helpers (`assert_true`, `assert_equals`, etc.)
5. Handle errors gracefully (tests should not fail entire suite)
6. Add documentation to this README

## License

Part of the CHOM/Mentat project. See main project LICENSE file.
