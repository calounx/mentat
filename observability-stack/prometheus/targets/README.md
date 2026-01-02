# Prometheus Target Files

This directory contains file-based service discovery targets for Prometheus.

## Usage

1. Copy the `.yaml.example` files to `.yaml` files:
   ```bash
   cd /etc/prometheus/targets
   cp vpsmanager-node.yaml.example vpsmanager-node.yaml
   cp vpsmanager-nginx.yaml.example vpsmanager-nginx.yaml
   cp vpsmanager-mysql.yaml.example vpsmanager-mysql.yaml
   cp vpsmanager-phpfpm.yaml.example vpsmanager-phpfpm.yaml
   ```

2. Edit each file to add your VPS server targets

3. Prometheus will automatically reload targets every 30 seconds

## Job Naming Convention

VPSManager targets use the following job name pattern:
- `vpsmanager-node` - Node Exporter (system metrics)
- `vpsmanager-nginx` - Nginx Exporter (web server metrics)
- `vpsmanager-mysql` - MySQL/MariaDB Exporter (database metrics)
- `vpsmanager-phpfpm` - PHP-FPM Exporter (PHP process metrics)
- `vpsmanager-fail2ban` - Fail2ban Exporter (security metrics)

## Required Labels

Each target should include:
- `host` - Hostname of the VPS
- `env` - Environment (test, staging, production)
- `role` - Server role (vps, observability)
- `app` - Application name (vpsmanager)

## Dynamic Target Management

The CHOM application can dynamically manage these files when provisioning
or deprovisioning VPS servers. See the VPSManager integration documentation.
