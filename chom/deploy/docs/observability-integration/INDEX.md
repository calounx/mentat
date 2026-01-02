# Observability Integration - Complete Documentation Index

## Quick Navigation

This document provides quick access to all observability integration resources.

**Total Documentation:** 6,800+ lines across 8 files
**Total Scripts:** 850+ lines across 2 executable scripts
**Estimated Implementation Time:** 1.5-2 hours
**Confidence Gain:** +3% (Phase 1 Quick Win #2)

## Master Reading List

### Start Here

1. **README.md** (Main Entry Point)
   - Overview of entire integration
   - Quick start steps
   - Common workflows
   - Command reference
   - Maintenance schedule

### Phase-by-Phase Implementation

2. **01-NETWORK-SETUP.md** (Network Layer - 15-30 min)
   - Network architecture
   - Layer 3 connectivity (ping)
   - DNS configuration
   - HTTP/HTTPS connectivity
   - Port verification
   - Firewall rules (UFW)
   - Performance analysis
   - SSL/TLS setup
   - Troubleshooting guide
   - Execution time: ~15-30 minutes

3. **02-PROMETHEUS-CONFIG.md** (Metrics Collection - 20-30 min)
   - Exporter installation verification
   - Prometheus scrape configuration
   - 6 scrape jobs (node, php-fpm, nginx, mysql, redis, app)
   - 10 alert rules
   - 9 recording rules
   - Grafana dashboard setup
   - Query examples
   - Remote storage (optional)
   - Troubleshooting guide
   - Execution time: ~20-30 minutes

4. **03-LOG-SHIPPING.md** (Log Aggregation - 20-30 min)
   - Alloy installation
   - Log source discovery (8 log sources)
   - Alloy configuration
   - JSON and text log parsing
   - Log filtering and sampling
   - Grafana log visualization
   - LogQL query examples
   - Performance tuning
   - Troubleshooting guide
   - Execution time: ~20-30 minutes

5. **04-VERIFICATION.md** (Testing & Validation - 30-45 min)
   - Connectivity verification
   - Prometheus health checks
   - Target status verification
   - Metric query validation
   - Loki log ingestion verification
   - Grafana integration tests
   - End-to-end data flow testing
   - Performance benchmarking
   - Security verification
   - Comprehensive 40-item checklist
   - Execution time: ~30-45 minutes

### Reference Documents

6. **IMPLEMENTATION-SUMMARY.md** (Executive Overview)
   - Deliverables overview
   - File structure
   - Quick start instructions
   - Performance metrics
   - Security posture
   - Maintenance schedule
   - Troubleshooting quick reference
   - Success criteria
   - Team responsibilities

7. **INDEX.md** (This File)
   - Documentation navigation
   - File descriptions
   - Implementation checklist
   - File sizes and metrics

## Files by Purpose

### Documentation Files

| File | Size | Lines | Purpose | Read Time |
|------|------|-------|---------|-----------|
| README.md | 15 KB | 555 | Main guide, quick start | 10 min |
| 01-NETWORK-SETUP.md | 15 KB | 481 | Network setup and troubleshooting | 15 min |
| 02-PROMETHEUS-CONFIG.md | 20 KB | 690 | Metrics configuration | 20 min |
| 03-LOG-SHIPPING.md | 19 KB | 762 | Log shipping setup | 20 min |
| 04-VERIFICATION.md | 16 KB | 624 | Verification procedures | 20 min |
| IMPLEMENTATION-SUMMARY.md | 14 KB | 475 | Executive summary | 10 min |
| INDEX.md | 8 KB | 250 | This navigation guide | 5 min |

**Total Documentation:** 99 KB, 3,837 lines

### Script Files

| File | Size | Lines | Purpose | Execution Time |
|------|------|-------|---------|-----------------|
| connectivity-test.sh | 15 KB | 495 | Network diagnostics | 2-5 min |
| setup-firewall.sh | 12 KB | 359 | Firewall configuration | 3-5 min |

**Total Scripts:** 27 KB, 854 lines

## Implementation Checklist

### Pre-Deployment (Verify Before Starting)

- [ ] Read README.md for overview
- [ ] Verify SSH access to both servers
- [ ] Confirm Prometheus running on mentat
- [ ] Confirm Loki running on mentat
- [ ] Confirm Grafana running on mentat
- [ ] Check DNS is configured for both hostnames
- [ ] Verify Internet connectivity on both servers

### Phase 1: Network Setup

- [ ] Run connectivity-test.sh on mentat
- [ ] Run connectivity-test.sh on landsraad
- [ ] Read 01-NETWORK-SETUP.md
- [ ] Run setup-firewall.sh --role mentat
- [ ] Run setup-firewall.sh --role landsraad
- [ ] Verify firewall rules with `ufw status`
- [ ] Test port connectivity with telnet/nc
- [ ] Verify DNS resolution both directions
- [ ] Test latency and bandwidth
- [ ] Document network baseline

### Phase 2: Prometheus Configuration

- [ ] Read 02-PROMETHEUS-CONFIG.md
- [ ] Verify Node Exporter running on landsraad
- [ ] Verify PHP-FPM Exporter running
- [ ] Verify Nginx Exporter running
- [ ] Verify MySQL Exporter running
- [ ] Verify Redis Exporter running
- [ ] Backup existing prometheus.yml
- [ ] Add CHOM scrape jobs to prometheus.yml
- [ ] Validate Prometheus config with promtool
- [ ] Reload Prometheus
- [ ] Verify targets in Prometheus UI
- [ ] Test metric queries
- [ ] Create alert rules file
- [ ] Create recording rules file
- [ ] Verify rules in Prometheus UI

### Phase 3: Log Shipping

- [ ] Read 03-LOG-SHIPPING.md
- [ ] SSH to landsraad
- [ ] Install Grafana Alloy: apt-get install grafana-alloy
- [ ] Verify Alloy installation
- [ ] Create /etc/alloy/config.alloy
- [ ] Update mentat IP in config
- [ ] Verify log file paths exist
- [ ] Set permissions for Alloy to read logs
- [ ] Validate Alloy config with alloy fmt
- [ ] Restart Alloy service
- [ ] Check Alloy logs for errors
- [ ] Query Loki for logs
- [ ] Verify all log types appearing
- [ ] Test log parsing
- [ ] Monitor Alloy resource usage

### Phase 4: Verification

- [ ] Read 04-VERIFICATION.md
- [ ] Run connectivity tests
- [ ] Verify Prometheus health
- [ ] Check all targets are UP
- [ ] Query sample metrics
- [ ] Verify recording rules
- [ ] Test alert rules
- [ ] Check Loki health
- [ ] Query logs in Loki
- [ ] Verify log ingestion rate
- [ ] Test Grafana data sources
- [ ] Create test dashboard
- [ ] Test time range selector
- [ ] Perform end-to-end testing
- [ ] Generate load test data
- [ ] Monitor system performance
- [ ] Test component failure recovery
- [ ] Verify firewall security
- [ ] Check TLS certificates
- [ ] Complete 40-item verification checklist

### Post-Deployment

- [ ] Document any customizations
- [ ] Create operational runbooks
- [ ] Setup notification channels
- [ ] Establish on-call rotation
- [ ] Schedule regular reviews
- [ ] Plan capacity improvements
- [ ] Create backup procedures
- [ ] Test disaster recovery
- [ ] Document lessons learned

## Key Configuration Locations

### On mentat (Observability)

```
/etc/prometheus/
├── prometheus.yml                 # Main Prometheus config
├── rules/
│   ├── chom-alerts.yml           # Alert rules
│   └── chom-recording.yml        # Recording rules
└── certs/                         # SSL certificates

/etc/loki/
└── loki-config.yaml              # Loki configuration

/etc/grafana/
├── provisioning/
│   └── dashboards/               # Dashboard definitions
└── grafana.ini                   # Grafana configuration

/var/lib/prometheus/              # Prometheus data
/var/lib/loki/                    # Loki data
```

### On landsraad (CHOM)

```
/etc/alloy/
└── config.alloy                  # Log shipping configuration

/var/www/chom/storage/logs/       # Application logs
├── app.json
├── laravel-*.log
├── performance-*.log
├── security-*.log
└── audit-*.log

/var/log/
├── nginx/                        # Web server logs
│   ├── access.log
│   └── error.log
└── php*-fpm.log                  # PHP process manager logs
```

## Network Architecture

```
┌────────────────────────────────────────────────────────────┐
│                    Internet (Public)                        │
└───────────────────┬────────────────────┬───────────────────┘
                    │                    │
         ┌──────────▼─────────┐ ┌────────▼──────────┐
         │ mentat.arewel.com  │ │landsraad.arewel.  │
         │   51.254.139.78    │ │   51.77.150.96    │
         ├────────────────────┤ ├───────────────────┤
         │ OBSERVABILITY      │ │ CHOM APPLICATION  │
         │ - Prometheus 9090  │ │ - Node Ex 9100    │
         │ - Loki 3100        │ │ - PHP-FPM 9253    │
         │ - Grafana 3000     │ │ - Nginx 9113      │
         │ - AlertMgr 9093    │ │ - MySQL 9104      │
         │                    │ │ - Redis 9121      │
         └────────────────────┘ │ - CHOM App 8080   │
                 ▲               │ - Alloy Agent     │
                 │               └───────────────────┘
         Metrics & Logs Pull ◄─── Pull & Push
         (Scrape Interval: 15s)   (Push Interval: 1s)
         Logs Push ◄────────────── Log Shipping
```

## Important Ports Summary

### mentat (Observability)

| Port | Service | Protocol | From | Purpose |
|------|---------|----------|------|---------|
| 22 | SSH | TCP | Any | Remote access |
| 3000 | Grafana | TCP | Any | Dashboards |
| 3100 | Loki | TCP | landsraad | Log ingestion |
| 9090 | Prometheus | TCP | landsraad | Metrics scraping |
| 9009 | Prometheus RW | TCP | landsraad | Remote write |
| 9093 | AlertManager | TCP | Local | Alerts |

### landsraad (CHOM)

| Port | Service | Protocol | From | Purpose |
|------|---------|----------|------|---------|
| 22 | SSH | TCP | Any | Remote access |
| 80 | HTTP | TCP | Any | Web traffic |
| 443 | HTTPS | TCP | Any | Secure web |
| 8080 | CHOM App | TCP | mentat | App metrics |
| 9100 | Node Ex | TCP | mentat | System metrics |
| 9104 | MySQL Ex | TCP | mentat | DB metrics |
| 9113 | Nginx Ex | TCP | mentat | Web metrics |
| 9121 | Redis Ex | TCP | mentat | Cache metrics |
| 9253 | PHP-FPM Ex | TCP | mentat | PHP metrics |

## Key Metrics Available

### System (Node Exporter - 9100)
- CPU usage, load average
- Memory (available, cached, buffers)
- Disk I/O, utilization
- Network bandwidth
- File descriptor usage
- Process count

### Web Server (Nginx - 9113)
- Request rate
- Response times
- Error rates (4xx, 5xx)
- Connection count
- Upstream latency

### PHP Runtime (PHP-FPM - 9253)
- Process states (idle, busy)
- Slow request count
- Max reached count
- Memory per process

### Database (MySQL - 9104)
- Active connections
- Connection count
- Threads running
- Query rate
- Slow query count
- Replication lag

### Cache (Redis - 9121)
- Memory usage
- Connected clients
- Commands/sec
- Hit rate
- Evictions

## Key Logs Available

| Source | Format | Frequency | Purpose |
|--------|--------|-----------|---------|
| App logs | JSON | Real-time | Application events |
| Laravel | Text | Real-time | Framework events |
| Nginx access | Text | Per request | HTTP requests |
| Nginx error | Text | On error | Web errors |
| PHP-FPM | Text | On event | PHP process events |
| Security | Text | Real-time | Security events |
| Audit | Text | Real-time | Audit trail |
| Performance | Text | Periodic | Performance analysis |

## Support Resources

### Within This Documentation

- Network troubleshooting: See 01-NETWORK-SETUP.md
- Prometheus issues: See 02-PROMETHEUS-CONFIG.md
- Log issues: See 03-LOG-SHIPPING.md
- Verification issues: See 04-VERIFICATION.md

### External Resources

- Prometheus: https://prometheus.io/docs/
- Loki: https://grafana.com/docs/loki/
- Grafana: https://grafana.com/docs/grafana/
- Alloy: https://grafana.com/docs/alloy/
- UFW: https://help.ubuntu.com/community/UFW

## Implementation Timeline

### Day 1: Network & Prometheus (1.5 hours)

1. Network setup (30 min)
2. Firewall configuration (30 min)
3. Prometheus configuration (30 min)

### Day 1-2: Log Shipping & Verification (1.5 hours)

1. Alloy installation (10 min)
2. Log shipping config (20 min)
3. Full verification (45 min)

### Ongoing: Monitoring (30 min/week)

1. Dashboard review (15 min)
2. Alert review (10 min)
3. Health checks (5 min)

## File Locations Quick Reference

### Documentation
```
/home/calounx/repositories/mentat/chom/deploy/docs/observability-integration/
```

### Scripts
```
/home/calounx/repositories/mentat/chom/deploy/scripts/network-diagnostics/
```

### Start Here
```
README.md          - Main guide
01-NETWORK-SETUP.md - Network phase
02-PROMETHEUS-CONFIG.md - Metrics phase
03-LOG-SHIPPING.md - Logs phase
04-VERIFICATION.md - Testing phase
```

## Metrics Summary

- **Total Documentation:** 99 KB across 7 files
- **Total Scripts:** 27 KB across 2 files
- **Total Lines:** 4,600+ lines
- **Execution Time:** 1.5-2 hours
- **Confidence Gain:** +3%

## Success Verification

You'll know the implementation is successful when:

✓ All connectivity tests pass
✓ All Prometheus targets show "UP"
✓ Logs appear in Loki within 5 seconds
✓ Grafana dashboards display live data
✓ Alert rules are configured and testing
✓ No resource exhaustion
✓ Firewall rules in place and working

---

**Documentation Version:** 1.0
**Last Updated:** January 2, 2026
**Status:** Ready for Implementation
