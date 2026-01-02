# Exporter Auto-Discovery - Quick Start Guide

5-minute guide to get started with the exporter auto-discovery system.

## Installation

```bash
cd /home/calounx/repositories/mentat/scripts/observability

# Ensure scripts are executable
chmod +x detect-exporters.sh
chmod +x install-exporter.sh
chmod +x generate-prometheus-config.sh
```

## Basic Usage

### 1. Scan Your System (30 seconds)

```bash
./detect-exporters.sh
```

**What it does:**
- Scans for running services (nginx, mysql, redis, etc.)
- Checks which exporters are installed
- Validates Prometheus configuration
- Shows what's missing

### 2. Install Missing Exporters (2 minutes)

```bash
# Preview what would be installed
./detect-exporters.sh --install --dry-run

# Actually install (requires sudo)
sudo ./detect-exporters.sh --install
```

### 3. Update Prometheus Config (1 minute)

```bash
# Generate configuration
./generate-prometheus-config.sh --host $(hostname)
```

### 4. Verify Everything Works (30 seconds)

```bash
# Check all exporters
./detect-exporters.sh --format json | jq '.summary'
```

## Quick Reference

### Exporter Ports

| Exporter | Port | Service |
|----------|------|---------|
| node_exporter | 9100 | System |
| nginx_exporter | 9113 | Nginx |
| mysqld_exporter | 9104 | MySQL |
| postgres_exporter | 9187 | PostgreSQL |
| redis_exporter | 9121 | Redis |
| phpfpm_exporter | 9253 | PHP-FPM |

See full documentation in docs/EXPORTER_AUTO_DISCOVERY.md
