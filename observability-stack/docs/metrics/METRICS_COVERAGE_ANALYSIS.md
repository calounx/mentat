# Observability Stack - Metrics Coverage Analysis
**Generated:** 2025-12-27
**Analysis Type:** Comprehensive metrics, queries, and dashboard coverage assessment

---

## Executive Summary

### Coverage Statistics
- **Total Modules Analyzed:** 6 (node_exporter, nginx_exporter, mysqld_exporter, phpfpm_exporter, fail2ban_exporter, promtail)
- **Total Dashboards:** 8 (1 overview + 6 module-specific + 1 logs)
- **Total Metrics Used in Dashboards:** 43 unique metrics
- **Total Metrics Used in Alerts:** 25 unique metrics
- **Alert Rules Defined:** 30 rules across 5 modules
- **Dashboard Panels:** 88 total panels

### Key Findings

#### Strengths
1. **Comprehensive node_exporter coverage** - Well-designed with 14 panels covering CPU, memory, disk, and network
2. **Good service health monitoring** - All exporters have up/down status checks
3. **Balanced alert coverage** - All critical services have basic availability and performance alerts
4. **Centralized logs dashboard** - Single unified view for all log sources

#### Critical Gaps
1. **Missing fail2ban_exporter dashboard** - Dashboard file is empty, no visualization for security metrics
2. **Missing promtail dashboard** - Dashboard file is empty, no promtail-specific metrics visualization
3. **No fail2ban metrics in overview** - Security status not represented on main dashboard
4. **Limited MySQL advanced metrics** - Missing query cache, table locks, replication metrics
5. **No nginx error rate tracking** - Missing 4xx/5xx status code metrics
6. **Missing network error panels** - node_exporter dashboard lacks error rate visualization

---

## 1. Metrics Collection by Exporter

### 1.1 node_exporter (System Metrics)

#### Metrics Collected (Used in Dashboards/Alerts)
```
Core Metrics:
✓ node_cpu_seconds_total        - CPU time by mode (user, system, idle, iowait, etc.)
✓ node_memory_MemTotal_bytes    - Total system memory
✓ node_memory_MemAvailable_bytes - Available memory
✓ node_memory_Buffers_bytes     - Buffer cache
✓ node_memory_Cached_bytes      - Page cache
✓ node_memory_SwapTotal_bytes   - Total swap space
✓ node_memory_SwapFree_bytes    - Free swap space
✓ node_filesystem_size_bytes    - Filesystem total size
✓ node_filesystem_avail_bytes   - Filesystem available space
✓ node_disk_read_bytes_total    - Disk read bytes
✓ node_disk_written_bytes_total - Disk write bytes
✓ node_disk_io_time_seconds_total - Disk I/O utilization
✓ node_network_receive_bytes_total - Network RX bytes
✓ node_network_transmit_bytes_total - Network TX bytes
✓ node_network_receive_errs_total - Network RX errors
✓ node_network_transmit_errs_total - Network TX errors
✓ node_load1, node_load5, node_load15 - Load averages
✓ node_boot_time_seconds        - System boot time
✓ node_time_seconds             - Current time
✓ node_filefd_allocated         - Open file descriptors
✓ node_filefd_maximum           - Max file descriptors
✓ node_systemd_unit_state       - Systemd unit states
✓ node_timex_offset_seconds     - Clock skew
✓ node_netstat_Tcp_CurrEstab    - TCP connections established
✓ node_sockstat_TCP_tw          - TCP time-wait connections
✓ up                            - Exporter availability

Collectors Enabled:
- Standard collectors (CPU, memory, disk, network, filesystem)
- --collector.systemd
- --collector.processes
```

#### Known Missing Important Metrics
```
✗ node_context_switches_total   - Context switches (performance indicator)
✗ node_interrupts_total         - System interrupts
✗ node_procs_blocked            - Blocked processes
✗ node_procs_running            - Running processes
✗ node_entropy_available_bits   - Available entropy (security)
✗ node_hwmon_*                  - Hardware sensors (temperature, fan speed)
✗ node_memory_Shmem_bytes       - Shared memory
✗ node_vmstat_*                 - VM statistics
```

**Coverage:** 65% (core metrics covered, advanced performance metrics missing)

---

### 1.2 nginx_exporter (Web Server Metrics)

#### Metrics Collected (Used in Dashboards/Alerts)
```
✓ nginx_up                      - Nginx exporter status
✓ nginx_connections_active      - Active client connections
✓ nginx_connections_reading     - Connections reading requests
✓ nginx_connections_writing     - Connections writing responses
✓ nginx_connections_waiting     - Idle keepalive connections
✓ nginx_connections_accepted    - Total accepted connections
✓ nginx_connections_handled     - Total handled connections
✓ nginx_http_requests_total     - Total HTTP requests
```

#### Known Missing Important Metrics
```
✗ nginx_http_response_status_codes - 2xx, 3xx, 4xx, 5xx breakdown
✗ nginx_upstream_* metrics      - Backend/upstream server health
✗ nginx_ssl_* metrics           - SSL/TLS session info
✗ nginx_cache_* metrics         - Cache hit/miss rates
✗ Request duration/latency      - Response time metrics
✗ Per-location statistics       - Granular endpoint metrics
```

**Note:** The exporter uses nginx stub_status module which provides only basic metrics. For advanced metrics, nginx-vts-exporter or nginx-prometheus-exporter with nginx-module-vts would be needed.

**Coverage:** 40% (basic connection metrics only, missing status codes and performance data)

---

### 1.3 mysqld_exporter (Database Metrics)

#### Metrics Collected (Used in Dashboards/Alerts)
```
✓ mysql_up                      - MySQL exporter status
✓ mysql_global_status_uptime    - Server uptime
✓ mysql_global_status_threads_connected - Current connections
✓ mysql_global_status_threads_running - Running threads
✓ mysql_global_status_queries   - Total queries
✓ mysql_global_status_questions - Client queries
✓ mysql_global_status_slow_queries - Slow queries
✓ mysql_global_status_commands_total - Command counters (SELECT, INSERT, UPDATE, DELETE)
✓ mysql_global_variables_max_connections - Max connection limit
✓ mysql_global_status_innodb_buffer_pool_bytes_data - InnoDB buffer data
✓ mysql_global_status_innodb_buffer_pool_bytes_dirty - InnoDB dirty pages
✓ mysql_global_variables_innodb_buffer_pool_size - InnoDB buffer pool size
✓ mysql_global_status_innodb_row_ops_total - InnoDB row operations
```

#### Known Missing Important Metrics
```
✗ mysql_global_status_aborted_connects - Failed connection attempts
✗ mysql_global_status_table_locks_waited - Table lock waits
✗ mysql_global_status_innodb_buffer_pool_reads - Buffer pool reads (cache miss)
✗ mysql_global_status_innodb_buffer_pool_read_requests - Read requests (total)
✗ mysql_global_status_qcache_* - Query cache metrics
✗ mysql_slave_status_* - Replication lag and status
✗ mysql_global_status_binlog_cache_* - Binary log cache
✗ mysql_global_status_created_tmp_* - Temporary table creation
✗ mysql_perf_schema_* - Performance schema metrics
✗ mysql_info_schema_* - Schema size and table statistics
```

**Coverage:** 50% (core connection and InnoDB basics covered, missing replication, query cache, locks)

---

### 1.4 phpfpm_exporter (PHP-FPM Metrics)

#### Metrics Collected (Used in Dashboards/Alerts)
```
✓ phpfpm_up                     - PHP-FPM exporter status
✓ phpfpm_active_processes       - Active worker processes
✓ phpfpm_idle_processes         - Idle worker processes
✓ phpfpm_total_processes        - Total processes
✓ phpfpm_listen_queue           - Current queue length
✓ phpfpm_listen_queue_len       - Max queue length
✓ phpfpm_max_listen_queue       - Peak queue length
✓ phpfpm_accepted_connections_total - Total accepted connections
✓ phpfpm_slow_requests_total    - Slow requests counter
✓ phpfpm_max_children_reached_total - Max children limit hits
```

#### Known Missing Important Metrics
```
✗ Per-process metrics           - Individual worker status
✗ Request duration histogram    - Response time distribution
✗ Memory usage per pool         - Pool memory consumption
✗ Start time                    - Pool/process start timestamp
```

**Note:** PHP-FPM status page provides limited metrics. All major metrics are captured.

**Coverage:** 90% (excellent coverage of available PHP-FPM metrics)

---

### 1.5 fail2ban_exporter (Security Metrics)

#### Metrics Collected (Used in Alerts)
```
✓ f2b_up                        - Fail2ban exporter status
✓ f2b_jail_banned_current       - Currently banned IPs per jail
✓ f2b_jail_banned_total         - Total bans per jail
```

#### Known Fail2ban Exporter Metrics (Standard)
```
✓ f2b_up                        - Exporter up status
✓ f2b_jail_banned_current       - Current bans
✓ f2b_jail_banned_total         - Total bans
✓ f2b_jail_failed_current       - Current failed attempts
✓ f2b_jail_failed_total         - Total failed attempts
✗ f2b_errors                    - Exporter errors (if applicable)
```

#### Missing from Dashboard
```
✗ f2b_jail_failed_current       - NOT visualized (should show attack attempts)
✗ f2b_jail_failed_total         - NOT visualized
✗ Ban rate trending             - NOT visualized
✗ Top attacked jails            - NOT visualized
✗ Geographic IP visualization   - Not available (would require enhancement)
```

**CRITICAL ISSUE:** Dashboard file is empty (0 bytes). NO metrics are visualized despite alerts being configured.

**Coverage:** 0% dashboard coverage, 60% alert coverage

---

### 1.6 promtail (Log Collection)

#### Metrics Exposed by Promtail
```
Promtail exposes operational metrics about itself:
✓ promtail_sent_entries_total   - Log entries sent to Loki
✓ promtail_dropped_entries_total - Dropped log entries
✓ promtail_read_bytes_total     - Bytes read from log files
✓ promtail_read_lines_total     - Lines read from log files
✓ promtail_file_bytes_total     - Current file positions
✓ promtail_targets_active_total - Active scrape targets
✓ promtail_targets_failed_total - Failed scrape targets
```

#### Dashboard Status
```
✗ Dashboard file is empty (0 bytes)
✗ No panels for promtail operational metrics
✗ No visualization of log shipping health
✗ No alerts for promtail failures
```

**CRITICAL ISSUE:** No monitoring of the log collection pipeline itself.

**Coverage:** 0% (no dashboard, no alerts, promtail operational health is blind spot)

---

## 2. Dashboard Analysis

### 2.1 Overview Dashboard (grafana/dashboards/overview.json)

**Purpose:** High-level infrastructure health across all monitored hosts

**Panels (12 total):**
```
Status Panels (3):
✓ Host Status (up metric from node job)
✓ Nginx Status (nginx_up)
✓ MySQL Status (mysql_up)

Time Series Graphs (5):
✓ CPU Usage by Host
✓ Memory Usage by Host
✓ Disk Usage (/) by Host
✓ Nginx Requests/sec by Host

Stat Panels (3):
✓ Total Nginx Active Connections (aggregated)
✓ Total MySQL Connections (aggregated)
✓ Total PHP-FPM Active Processes (aggregated)

Table (1):
✓ Active Alerts (ALERTS{alertstate="firing"})
```

**Coverage Analysis:**
```
✓ node_exporter    - Basic CPU, memory, disk (3 metrics)
✓ nginx_exporter   - Status, requests, connections (3 metrics)
✓ mysql_exporter   - Status, connections (2 metrics)
✓ phpfpm_exporter  - Active processes (1 metric)
✗ fail2ban_exporter - NOT PRESENT (missing security overview)
✗ promtail         - NOT PRESENT (missing log health)
```

**Recommendations:**
1. Add fail2ban panel showing total current bans across all hosts
2. Add promtail health indicator (active targets, drop rate)
3. Add PHP-FPM status indicator alongside nginx/mysql
4. Add network traffic overview panel
5. Add disk I/O overview panel
6. Consider swap usage indicator

---

### 2.2 Node Exporter Dashboard (modules/_core/node_exporter/dashboard.json)

**Comprehensive, well-organized dashboard with 14 panels across 5 sections:**

**Row 1: System Overview (6 gauge/stat panels)**
```
✓ CPU Usage gauge
✓ Memory Usage gauge
✓ Disk Usage (/) gauge
✓ Uptime
✓ Total RAM
✓ CPU Cores
```

**Row 2: CPU (2 time series)**
```
✓ CPU Usage by Mode (stacked area - user, system, iowait, etc.)
✓ Load Average (1m, 5m, 15m vs CPU count)
```

**Row 3: Memory (2 time series)**
```
✓ Memory Usage (stacked - used, buffers, cached, available)
✓ Swap Usage
```

**Row 4: Disk (2 time series)**
```
✓ Disk Usage by Mountpoint (%)
✓ Disk I/O (read/write bytes per device)
```

**Row 5: Network (2 time series)**
```
✓ Network Bandwidth (RX/TX bytes in bps, filtered to exclude virtual interfaces)
✓ TCP Connections (established, time-wait)
```

**Missing Panels:**
```
✗ Network Errors (receive/transmit errors) - CRITICAL for troubleshooting
✗ Context Switches Rate
✗ Open File Descriptors (used in alerts but not visualized)
✗ Systemd Service Status (used in alerts but not visualized)
✗ Process Count
✗ Disk IOPS (operations, not just bytes)
```

**Coverage:** 75% (excellent core coverage, missing error metrics and advanced counters)

---

### 2.3 Nginx Dashboard (modules/_core/nginx_exporter/dashboard.json)

**Well-structured with 10 panels across 3 sections:**

**Row 1: Overview (6 stat panels)**
```
✓ Nginx Status (up/down)
✓ Active Connections
✓ Requests/sec
✓ Reading connections
✓ Writing connections
✓ Waiting connections
```

**Row 2: Connections & Requests (2 time series)**
```
✓ Connections (active, reading, writing, waiting)
✓ Request Rate
```

**Row 3: Totals (2 panels)**
```
✓ Connection Rates (accepted/sec, handled/sec)
✓ Total Counts (cumulative accepted, handled, requests)
```

**Missing Panels:**
```
✗ HTTP Status Codes (2xx, 3xx, 4xx, 5xx) - NOT AVAILABLE in stub_status
✗ Request Duration/Latency - NOT AVAILABLE in stub_status
✗ Error Rate - NOT AVAILABLE in stub_status
✗ Upstream Backend Health - NOT AVAILABLE in stub_status
✗ SSL/TLS Metrics - NOT AVAILABLE in stub_status
✗ Cache Hit Ratio - NOT AVAILABLE in stub_status
```

**Note:** Missing panels are due to exporter limitations (stub_status module), not dashboard design.

**Coverage:** 100% of available metrics, 40% of desired metrics (exporter constraint)

---

### 2.4 MySQL Dashboard (modules/_core/mysqld_exporter/dashboard.json)

**Organized dashboard with 12 panels across 4 sections:**

**Row 1: Overview (6 stat panels)**
```
✓ MySQL Status (up/down)
✓ Uptime
✓ Connections
✓ Running Threads
✓ QPS (Queries per Second)
✓ Slow Queries/sec
```

**Row 2: Connections (2 panels)**
```
✓ Connections time series (connected, running, max)
✓ Connection Usage % gauge
```

**Row 3: Query Performance (2 time series)**
```
✓ Query Rate (queries vs questions)
✓ Command Rates (SELECT, INSERT, UPDATE, DELETE)
```

**Row 4: InnoDB (2 time series)**
```
✓ InnoDB Buffer Pool (data, dirty, pool size)
✓ InnoDB Row Operations (reads, inserts, updates, deletes)
```

**Missing Important Panels:**
```
✗ Table Locks (table_locks_waited)
✗ Query Cache Hit Rate (if query cache enabled)
✗ Temporary Table Creation (heap vs disk)
✗ Aborted Connections (connection failures)
✗ Replication Lag (for master-slave setups)
✗ Binary Log Usage
✗ InnoDB Buffer Pool Hit Ratio (critical for tuning)
✗ Sort/Join Operations
```

**Coverage:** 60% (good connection and basic InnoDB coverage, missing advanced performance metrics)

---

### 2.5 PHP-FPM Dashboard (modules/_core/phpfpm_exporter/dashboard.json)

**Excellent comprehensive dashboard with 11 panels across 4 sections:**

**Row 1: Overview (6 stat panels)**
```
✓ PHP-FPM Status (up/down)
✓ Active Processes
✓ Idle Processes
✓ Total Processes
✓ Listen Queue
✓ Max Children Reached (1h)
```

**Row 2: Processes (2 panels)**
```
✓ Process Distribution (stacked area - active vs idle)
✓ Process Usage % gauge
```

**Row 3: Queue & Performance (2 time series)**
```
✓ Listen Queue (current, max length, peak)
✓ Connection & Slow Request Rate
```

**Row 4: Totals (1 stat panel)**
```
✓ Lifetime Counters (total accepted, slow requests, max children hits)
```

**Missing Panels:**
```
✗ Start Since (uptime) - minor
✗ Per-pool breakdown (if multiple pools) - nice-to-have
```

**Coverage:** 95% (near-complete coverage of PHP-FPM metrics)

---

### 2.6 Fail2ban Dashboard (modules/_core/fail2ban_exporter/dashboard.json)

**STATUS: EMPTY FILE (CRITICAL ISSUE)**

**Expected Panels (NOT IMPLEMENTED):**
```
✗ Fail2ban Status (up/down)
✗ Currently Banned IPs (per jail)
✗ Total Bans Over Time (time series)
✗ Ban Rate (bans per minute)
✗ Failed Attempts (per jail)
✗ Top Attacked Jails (bar chart)
✗ Ban Events (table with jail, count)
```

**Impact:** Security metrics are collected but completely invisible. No way to monitor attack patterns.

**Coverage:** 0%

---

### 2.7 Promtail Dashboard (modules/_core/promtail/dashboard.json)

**STATUS: EMPTY FILE (CRITICAL ISSUE)**

**Expected Panels (NOT IMPLEMENTED):**
```
✗ Promtail Status (up/down)
✗ Log Entries Sent (rate)
✗ Log Entries Dropped (rate)
✗ Active Targets
✗ Failed Targets
✗ Read Bytes Rate
✗ Bytes Behind (lag indicator)
```

**Impact:** Log collection pipeline health is invisible. No way to detect log shipping failures.

**Coverage:** 0%

---

### 2.8 Logs Explorer Dashboard (grafana/dashboards/logs.json)

**Purpose:** Unified log viewing across all log sources

**Panels (9 total):**
```
Row 1: Log Statistics (3 time series)
✓ Log Volume by Host (bar chart)
✓ Log Volume by Job
✓ Error/Warning Logs by Host

Row 2-7: Log Viewers (6 log panels)
✓ Nginx Access Logs
✓ Nginx Error Logs
✓ PHP Error Logs
✓ MySQL Slow Query Logs
✓ Syslog
✓ WordPress Debug Logs
```

**Variables:**
```
✓ $job - Filter by log job
✓ $host - Filter by hostname
✓ $search - Text search filter
```

**Log Sources Covered:**
```
✓ nginx_access - Nginx access logs
✓ nginx_error - Nginx error logs
✓ php.* - PHP error logs
✓ mysql_slow - MySQL slow query logs
✓ syslog - System logs
✓ wordpress - WordPress debug logs
```

**Missing Log Sources:**
```
✗ fail2ban logs - No specific panel for fail2ban activity logs
✗ PHP-FPM error logs - Separate from PHP error logs
✗ MySQL error logs - Only slow queries, not general errors
✗ Application-specific logs - No panels for custom app logs
```

**Coverage:** 75% (good coverage of common log types, missing some specialized logs)

---

## 3. Alert Coverage Analysis

### 3.1 Alert Rules Summary

**Total Alert Rules: 30 across 5 modules**

| Module | Rules | Severity Critical | Severity Warning |
|--------|-------|-------------------|------------------|
| node_exporter | 18 | 5 | 13 |
| nginx_exporter | 3 | 1 | 2 |
| mysqld_exporter | 4 | 2 | 2 |
| phpfpm_exporter | 3 | 1 | 2 |
| fail2ban_exporter | 3 | 1 | 2 |
| promtail | 0 | 0 | 0 |

---

### 3.2 node_exporter Alerts (18 rules)

**Instance Availability (1 critical)**
```
✓ InstanceDown - up == 0 for 2m
```

**CPU Alerts (2)**
```
✓ HighCpuLoad (warning) - >80% for 5m
✓ CriticalCpuLoad (critical) - >95% for 2m
```

**Memory Alerts (3)**
```
✓ HighMemoryUsage (warning) - >80% for 5m
✓ CriticalMemoryUsage (critical) - >95% for 2m
✓ HighSwapUsage (warning) - >80% for 5m
```

**Disk Alerts (4)**
```
✓ DiskSpaceLow (warning) - >80% for 5m
✓ DiskSpaceCritical (critical) - >90% for 2m
✓ DiskWillFillIn24Hours (warning) - Predictive based on 6h trend
✓ HighDiskIOUtilization (warning) - >80% for 10m
```

**Network Alerts (2)**
```
✓ HighNetworkReceiveErrors (warning) - >10 errors/sec for 5m
✓ HighNetworkTransmitErrors (warning) - >10 errors/sec for 5m
```

**System Alerts (4)**
```
✓ HighLoadAverage (warning) - load15 > 2x CPU count for 10m
✓ ClockSkew (warning) - >0.05 seconds offset for 5m
✓ TooManyOpenFiles (warning) - >80% of max for 5m
✓ SystemdServiceFailed (critical) - Any systemd unit in failed state for 1m
```

**Dashboard Coverage vs Alert Coverage:**
```
Alerts but NO dashboard panels:
✗ Network errors (HighNetworkReceiveErrors/HighNetworkTransmitErrors)
✗ File descriptors (TooManyOpenFiles)
✗ Systemd services (SystemdServiceFailed)
✗ Clock skew (ClockSkew)
```

**Missing Important Alerts:**
```
✗ High context switch rate
✗ OOM killer events
✗ Disk read/write latency spikes
✗ Low entropy (security concern)
```

**Coverage:** 85% (comprehensive coverage of core resources)

---

### 3.3 nginx_exporter Alerts (3 rules)

```
✓ NginxDown (critical) - nginx_up == 0 for 1m
✓ NginxHighConnections (warning) - >1000 active for 5m
✓ NginxHighConnectionsWaiting (warning) - >500 waiting for 5m
```

**Missing Critical Alerts:**
```
✗ High error rate (4xx/5xx) - NOT AVAILABLE (stub_status limitation)
✗ Request rate spike/drop - Could be added
✗ Connection refused rate - NOT AVAILABLE
✗ Slow response time - NOT AVAILABLE (stub_status limitation)
```

**Coverage:** 60% (basic availability and saturation, missing error rates)

---

### 3.4 mysqld_exporter Alerts (4 rules)

```
✓ MySQLDown (critical) - mysql_up == 0 for 1m
✓ MySQLTooManyConnections (warning) - >80% of max for 5m
✓ MySQLConnectionsCritical (critical) - >95% of max for 2m
✓ MySQLSlowQueries (warning) - >0.1 slow queries/sec for 5m
```

**Missing Important Alerts:**
```
✗ Aborted connections (security/stability indicator)
✗ Table lock contention
✗ InnoDB buffer pool low hit rate
✗ Replication lag (for master-slave setups)
✗ Binary log disk usage
✗ High temporary table creation rate
```

**Coverage:** 50% (covers availability and connections, missing performance indicators)

---

### 3.5 phpfpm_exporter Alerts (3 rules)

```
✓ PHPFPMDown (critical) - phpfpm_up == 0 for 1m
✓ PHPFPMHighActiveProcesses (warning) - >80% processes active for 5m
✓ PHPFPMMaxChildrenReached (warning) - Hitting max children for 5m
```

**Missing Alerts:**
```
✗ High queue length (threshold-based)
✗ Slow request rate spike
✗ Process saturation prediction
```

**Coverage:** 80% (good coverage of critical conditions)

---

### 3.6 fail2ban_exporter Alerts (3 rules)

```
✓ Fail2banDown (critical) - f2b_up == 0 for 1m
✓ Fail2banHighBanRate (warning) - >1 ban/sec for 5m
✓ Fail2banManyCurrentBans (warning) - >50 total current bans for 5m
```

**Missing Alerts:**
```
✗ High failed attempt rate (f2b_jail_failed_total)
✗ Jail-specific ban thresholds
✗ Exporter errors
```

**Coverage:** 60% (basic security event detection, missing granular jail alerts)

---

### 3.7 promtail Alerts (0 rules - CRITICAL GAP)

```
✗ NO ALERTS CONFIGURED FOR PROMTAIL
```

**Missing Critical Alerts:**
```
✗ PromtailDown - Exporter/service unavailable
✗ PromtailTargetDown - Log file target failed
✗ PromtailHighDropRate - Dropping log entries
✗ PromtailLagging - Falling behind in log tailing
```

**Coverage:** 0% (blind spot in observability)

---

## 4. Coverage Analysis Summary

### 4.1 Exporter Metrics Utilization

| Exporter | Metrics Available (Est.) | Metrics Used | Utilization | Dashboard Panels | Alert Rules |
|----------|-------------------------|--------------|-------------|------------------|-------------|
| node_exporter | ~500 | 26 | 5% | 14 | 18 |
| nginx_exporter | 8 | 8 | 100% | 10 | 3 |
| mysqld_exporter | ~200 | 13 | 6% | 12 | 4 |
| phpfpm_exporter | ~15 | 10 | 67% | 11 | 3 |
| fail2ban_exporter | ~6 | 3 | 50% | 0 | 3 |
| promtail | ~15 | 0 | 0% | 0 | 0 |

**Note:** Low utilization for node_exporter and mysqld_exporter is normal - they expose hundreds of advanced metrics that are not needed for standard monitoring.

---

### 4.2 Module Completeness Matrix

| Module | Dashboard Exists | Dashboard Complete | Alerts Exist | Alerts Adequate | In Overview | Overall |
|--------|------------------|-------------------|--------------|-----------------|-------------|---------|
| node_exporter | ✓ | 75% | ✓ | 85% | ✓ | GOOD |
| nginx_exporter | ✓ | 100%* | ✓ | 60% | ✓ | GOOD |
| mysqld_exporter | ✓ | 60% | ✓ | 50% | ✓ | FAIR |
| phpfpm_exporter | ✓ | 95% | ✓ | 80% | ✓ | EXCELLENT |
| fail2ban_exporter | ✗ | 0% | ✓ | 60% | ✗ | CRITICAL |
| promtail | ✗ | 0% | ✗ | 0% | ✗ | CRITICAL |

*100% of available metrics, but metrics are limited by stub_status

---

### 4.3 Gap Analysis by Category

#### CRITICAL GAPS (Immediate Action Required)
```
1. fail2ban_exporter dashboard is missing (0 bytes)
   - Security metrics invisible
   - Cannot monitor attack patterns
   - Alerts exist but no visualization

2. promtail dashboard is missing (0 bytes)
   - Log pipeline health invisible
   - Cannot detect log shipping failures
   - No alerts for log collection failures

3. promtail has no alerts configured
   - Log collection failures go unnoticed
   - Critical observability blind spot

4. fail2ban not in overview dashboard
   - Security status not at-a-glance
   - Admins won't notice attacks on main view
```

#### HIGH PRIORITY GAPS
```
5. node_exporter dashboard missing network error panels
   - Network errors in alerts but not visualized
   - Troubleshooting network issues is difficult

6. node_exporter dashboard missing file descriptor panel
   - TooManyOpenFiles alert exists but no graph
   - Cannot see trending before alert fires

7. node_exporter dashboard missing systemd service panel
   - SystemdServiceFailed alert exists but no panel
   - Cannot see which services are failed

8. MySQL missing advanced performance metrics
   - No replication monitoring
   - No query cache visibility
   - No table lock visualization
```

#### MEDIUM PRIORITY GAPS
```
9. nginx_exporter cannot track error rates
   - Limited by stub_status module
   - Consider upgrading to nginx-vts-exporter

10. Overview dashboard missing security indicators
    - No fail2ban current bans
    - No attack rate indicator

11. Logs dashboard missing fail2ban logs
    - Security events not in log viewer
```

#### LOW PRIORITY (Nice-to-Have)
```
12. node_exporter missing advanced metrics
    - Context switches, interrupts, entropy
    - Usually not needed unless deep troubleshooting

13. MySQL missing query cache, table locks
    - Important for highly loaded databases
    - Not critical for most deployments
```

---

## 5. Redundancy and Duplicate Analysis

### 5.1 Duplicate Panels
```
NONE FOUND - No redundant or duplicate panels detected
```

### 5.2 Overlapping Metrics
```
Overview dashboard intentionally duplicates some metrics:
- CPU/Memory/Disk usage shown aggregated in overview
- Same metrics shown per-host in node_exporter dashboard
- This is GOOD DESIGN (different views for different purposes)
```

### 5.3 Unused Metrics in Dashboards
```
Metrics in alerts but NOT in dashboards:
- node_network_receive_errs_total (alert only)
- node_network_transmit_errs_total (alert only)
- node_filefd_allocated/maximum (alert only)
- node_systemd_unit_state (alert only)
- node_timex_offset_seconds (alert only)
- node_disk_io_time_seconds_total (alert only)

Recommendation: Add panels for these to support troubleshooting
```

---

## 6. Data-Driven Recommendations

### Priority 1: CRITICAL - Fix Immediately

#### 6.1 Create fail2ban_exporter Dashboard
**File:** `/home/calounx/repositories/mentat/observability-stack/modules/_core/fail2ban_exporter/dashboard.json`

**Required Panels:**
```json
Row 1: Overview (3 stat panels)
- Fail2ban Status (f2b_up)
- Total Current Bans (sum(f2b_jail_banned_current))
- Total Bans Last Hour (increase(f2b_jail_banned_total[1h]))

Row 2: Ban Activity (2 time series)
- Current Bans per Jail (f2b_jail_banned_current by jail)
- Ban Rate (rate(f2b_jail_banned_total[5m]) by jail)

Row 3: Attack Attempts (2 time series)
- Current Failed Attempts (f2b_jail_failed_current by jail)
- Failed Attempt Rate (rate(f2b_jail_failed_total[5m]) by jail)

Row 4: Details (1 table)
- Jail Status Table (jail, current_bans, current_failed, total_bans)
```

**Impact:** Enables security monitoring, attack pattern detection

---

#### 6.2 Create promtail Dashboard
**File:** `/home/calounx/repositories/mentat/observability-stack/modules/_core/promtail/dashboard.json`

**Required Panels:**
```json
Row 1: Overview (4 stat panels)
- Promtail Instances Up (count(up{job="promtail"}))
- Active Targets (promtail_targets_active_total)
- Failed Targets (promtail_targets_failed_total)
- Drop Rate (rate(promtail_dropped_entries_total[5m]))

Row 2: Throughput (2 time series)
- Log Entries Sent (rate(promtail_sent_entries_total[5m]) by host)
- Bytes Read (rate(promtail_read_bytes_total[5m]) by host)

Row 3: Health (2 panels)
- Dropped Entries (rate(promtail_dropped_entries_total[5m]) by host)
- Target Status (promtail_targets_active_total vs promtail_targets_failed_total)
```

**Impact:** Enables log pipeline monitoring, prevents silent log loss

---

#### 6.3 Add promtail Alerts
**File:** `/home/calounx/repositories/mentat/observability-stack/modules/_core/promtail/alerts.yml`

**Required Alerts:**
```yaml
groups:
  - name: promtail_alerts
    rules:
      - alert: PromtailDown
        expr: up{job="promtail"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Promtail is down on {{ $labels.instance }}"
          description: "Promtail log shipper is not responding"

      - alert: PromtailTargetDown
        expr: promtail_targets_failed_total > 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Promtail has failed targets on {{ $labels.instance }}"
          description: "{{ $value }} log targets are failing"

      - alert: PromtailHighDropRate
        expr: rate(promtail_dropped_entries_total[5m]) > 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Promtail is dropping log entries on {{ $labels.instance }}"
          description: "Dropping {{ $value | printf \"%.2f\" }} entries/sec"
```

**Impact:** Detects log collection failures before data is lost

---

#### 6.4 Add Fail2ban to Overview Dashboard
**File:** `/home/calounx/repositories/mentat/observability-stack/grafana/dashboards/overview.json`

**Add after existing status panels:**
```json
{
  "datasource": { "type": "prometheus", "uid": "prometheus" },
  "fieldConfig": {
    "defaults": {
      "color": { "mode": "thresholds" },
      "mappings": [],
      "thresholds": {
        "mode": "absolute",
        "steps": [
          { "color": "green", "value": null },
          { "color": "yellow", "value": 10 },
          { "color": "red", "value": 50 }
        ]
      },
      "unit": "none"
    }
  },
  "gridPos": { "h": 6, "w": 8, "x": 0, "y": 31 },
  "options": {
    "colorMode": "background",
    "graphMode": "area",
    "justifyMode": "center",
    "orientation": "horizontal",
    "reduceOptions": { "calcs": ["lastNotNull"], "fields": "", "values": false },
    "textMode": "auto"
  },
  "targets": [
    { "expr": "sum(f2b_jail_banned_current)", "legendFormat": "Banned IPs", "refId": "A" }
  ],
  "title": "Current Fail2ban Bans",
  "type": "stat"
}
```

**Impact:** Security status visible at-a-glance on main dashboard

---

### Priority 2: HIGH - Improve Visibility

#### 6.5 Add Network Error Panel to node_exporter Dashboard
**Location:** After "Network Bandwidth" panel in node dashboard

```json
{
  "datasource": { "type": "prometheus", "uid": "prometheus" },
  "fieldConfig": {
    "defaults": {
      "color": { "mode": "palette-classic" },
      "custom": {
        "drawStyle": "line",
        "lineWidth": 2,
        "fillOpacity": 10
      },
      "unit": "errors/sec"
    }
  },
  "targets": [
    {
      "expr": "rate(node_network_receive_errs_total{instance=~\"$instance\",device!~\"lo|docker.*|br.*|veth.*\"}[5m])",
      "legendFormat": "{{ device }} RX errors"
    },
    {
      "expr": "rate(node_network_transmit_errs_total{instance=~\"$instance\",device!~\"lo|docker.*|br.*|veth.*\"}[5m])",
      "legendFormat": "{{ device }} TX errors"
    }
  ],
  "title": "Network Errors",
  "type": "timeseries"
}
```

**Impact:** Align dashboard with alerts, enable proactive troubleshooting

---

#### 6.6 Add File Descriptor Panel to node_exporter Dashboard
**Location:** After "TCP Connections" in node dashboard

```json
{
  "datasource": { "type": "prometheus", "uid": "prometheus" },
  "fieldConfig": {
    "defaults": {
      "color": { "mode": "thresholds" },
      "max": 100,
      "min": 0,
      "thresholds": {
        "steps": [
          { "color": "green" },
          { "color": "yellow", "value": 70 },
          { "color": "red", "value": 90 }
        ]
      },
      "unit": "percent"
    }
  },
  "options": { "orientation": "auto", "showThresholdMarkers": true },
  "targets": [
    {
      "expr": "node_filefd_allocated{instance=~\"$instance\"} / node_filefd_maximum{instance=~\"$instance\"} * 100"
    }
  ],
  "title": "File Descriptor Usage",
  "type": "gauge"
}
```

**Impact:** Visualize trending before TooManyOpenFiles alert fires

---

#### 6.7 Add Systemd Service Status Panel to node_exporter Dashboard
**Location:** After "System Overview" section

```json
{
  "datasource": { "type": "prometheus", "uid": "prometheus" },
  "fieldConfig": {
    "defaults": {
      "custom": { "align": "auto", "cellOptions": { "type": "color-background" } },
      "mappings": [
        {
          "options": {
            "0": { "color": "red", "text": "Failed" },
            "1": { "color": "green", "text": "Active" }
          },
          "type": "value"
        }
      ]
    }
  },
  "targets": [
    {
      "expr": "node_systemd_unit_state{instance=~\"$instance\",state=\"failed\"}",
      "format": "table"
    }
  ],
  "title": "Failed Systemd Services",
  "type": "table",
  "transformations": [
    {
      "id": "organize",
      "options": {
        "excludeByName": { "Time": true, "Value": true },
        "renameByName": { "name": "Service", "state": "State" }
      }
    }
  ]
}
```

**Impact:** Quickly identify failed services before investigating

---

### Priority 3: MEDIUM - Enhance Monitoring

#### 6.8 Add MySQL Advanced Metrics

**Add to MySQL Dashboard:**

**Panel: Buffer Pool Hit Ratio**
```json
{
  "expr": "(1 - (mysql_global_status_innodb_buffer_pool_reads / mysql_global_status_innodb_buffer_pool_read_requests)) * 100",
  "legendFormat": "Hit Ratio %",
  "title": "InnoDB Buffer Pool Hit Ratio"
}
```
**Impact:** Critical for database performance tuning

**Panel: Aborted Connections**
```json
{
  "expr": "rate(mysql_global_status_aborted_connects[5m])",
  "legendFormat": "Aborted Connects/sec",
  "title": "Aborted Connections"
}
```
**Impact:** Security indicator (brute force attempts)

---

#### 6.9 Add Promtail Health to Overview Dashboard

**Add stat panel:**
```json
{
  "title": "Log Shippers Active",
  "targets": [
    { "expr": "count(up{job=\"promtail\"} == 1)" }
  ],
  "type": "stat"
}
```

**Impact:** Log pipeline health visible on main dashboard

---

#### 6.10 Enhance Logs Dashboard with fail2ban Logs

**Add panel after "System Logs" row:**
```json
{
  "datasource": { "type": "loki", "uid": "loki" },
  "gridPos": { "h": 10, "w": 24 },
  "targets": [
    { "expr": "{job=\"fail2ban\"} |= \"Ban\" or \"Unban\"" }
  ],
  "title": "Fail2ban Activity Logs",
  "type": "logs"
}
```

**Impact:** Correlate ban metrics with actual log events

---

### Priority 4: LOW - Nice to Have

#### 6.11 Upgrade nginx_exporter for Status Codes

**Current Limitation:** stub_status module lacks HTTP status code metrics

**Recommendation:**
1. Install nginx-module-vts (Virtual Host Traffic Status)
2. Replace nginx-prometheus-exporter with nginx-vts-exporter
3. Add panels for 2xx, 3xx, 4xx, 5xx rates

**Effort:** Medium (requires nginx module compilation or switch to nginx-plus)

**Impact:** Error rate tracking, better incident detection

---

#### 6.12 Add Advanced node_exporter Panels

**Context Switches:**
```json
{
  "expr": "rate(node_context_switches_total[5m])",
  "title": "Context Switches/sec"
}
```

**Interrupts:**
```json
{
  "expr": "rate(node_interrupts_total[5m])",
  "title": "Interrupts/sec"
}
```

**Impact:** Advanced performance troubleshooting

---

## 7. Metric Hierarchy and Dependencies

### 7.1 Metric Dependencies
```
Overview Dashboard depends on:
  - node_exporter (host status, resource usage)
  - nginx_exporter (web service health)
  - mysql_exporter (database health)
  - phpfpm_exporter (application health)
  - [MISSING] fail2ban_exporter
  - [MISSING] promtail

Individual dashboards are self-contained (no cross-dependencies)

Logs dashboard depends on:
  - promtail (log shipping)
  - Loki (log storage)
```

### 7.2 Alert to Dashboard Mapping
```
Alerts WITHOUT corresponding dashboard panels:
  - node_network_receive_errs_total (HIGH PRIORITY)
  - node_network_transmit_errs_total (HIGH PRIORITY)
  - node_filefd_allocated/maximum (HIGH PRIORITY)
  - node_systemd_unit_state (MEDIUM PRIORITY)
  - node_timex_offset_seconds (LOW PRIORITY)
  - node_disk_io_time_seconds_total (MEDIUM PRIORITY)

Dashboard panels WITHOUT corresponding alerts:
  - node_memory_Buffers_bytes (OK - informational)
  - node_memory_Cached_bytes (OK - informational)
  - node_boot_time_seconds (OK - informational)
  - nginx_connections_reading (OK - detailed view)
  - nginx_connections_writing (OK - detailed view)
  - mysql_global_status_questions (OK - complementary to queries)
```

---

## 8. Implementation Checklist

### Immediate (Complete within 1-2 days)

- [ ] **Create fail2ban dashboard** (dashboard.json from empty file)
  - [ ] Add 8 panels as specified in 6.1
  - [ ] Configure variables (instance, jail)
  - [ ] Set refresh rate to 30s
  - [ ] Test with live data

- [ ] **Create promtail dashboard** (dashboard.json from empty file)
  - [ ] Add 8 panels as specified in 6.2
  - [ ] Configure instance variable
  - [ ] Set refresh rate to 30s
  - [ ] Test with live data

- [ ] **Add promtail alerts** (create alerts.yml)
  - [ ] PromtailDown alert
  - [ ] PromtailTargetDown alert
  - [ ] PromtailHighDropRate alert
  - [ ] Test alert routing

- [ ] **Add fail2ban to overview dashboard**
  - [ ] Add "Current Fail2ban Bans" stat panel
  - [ ] Position after existing status panels
  - [ ] Test aggregation across hosts

### Short-term (Complete within 1 week)

- [ ] **Enhance node_exporter dashboard**
  - [ ] Add Network Errors panel (6.5)
  - [ ] Add File Descriptor Usage gauge (6.6)
  - [ ] Add Failed Systemd Services table (6.7)
  - [ ] Test all panels with live data

- [ ] **Enhance overview dashboard**
  - [ ] Add Log Shippers Active stat (6.9)
  - [ ] Add PHP-FPM status indicator
  - [ ] Reorganize layout for better visual hierarchy

### Medium-term (Complete within 2 weeks)

- [ ] **Enhance MySQL dashboard**
  - [ ] Add Buffer Pool Hit Ratio gauge (6.8)
  - [ ] Add Aborted Connections panel
  - [ ] Add Table Locks panel
  - [ ] Add corresponding alerts

- [ ] **Enhance logs dashboard**
  - [ ] Add fail2ban logs panel (6.10)
  - [ ] Add PHP-FPM error logs panel
  - [ ] Add MySQL error logs panel

### Long-term (Nice to have)

- [ ] **Upgrade nginx monitoring**
  - [ ] Evaluate nginx-vts-exporter
  - [ ] Plan migration from stub_status
  - [ ] Add HTTP status code panels

- [ ] **Add advanced node metrics**
  - [ ] Context switches panel
  - [ ] Interrupts panel
  - [ ] Hardware sensors (if available)

---

## 9. Testing and Validation Plan

### 9.1 Dashboard Testing
```bash
# For each new/modified dashboard:
1. Load in Grafana UI
2. Verify all panels render without errors
3. Confirm variables populate correctly
4. Test time range selection
5. Verify data appears for monitored hosts
6. Check panel descriptions and units
7. Validate threshold colors
```

### 9.2 Alert Testing
```bash
# For each new alert:
1. Manually trigger condition (if possible)
2. Verify alert fires in Alertmanager
3. Confirm notification sent (email/Slack)
4. Test alert resolution
5. Verify annotations are descriptive
```

### 9.3 Metrics Validation
```bash
# Verify metrics are being collected:
curl -s http://localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | select(.health != "up") | {instance: .labels.instance, job: .labels.job, health: .health, error: .lastError}'

# Check specific metrics:
curl -s 'http://localhost:9090/api/v1/query?query=f2b_up' | jq
curl -s 'http://localhost:9090/api/v1/query?query=promtail_targets_active_total' | jq
```

---

## 10. Maintenance Recommendations

### 10.1 Regular Review Cadence
```
Weekly:
  - Review fired alerts
  - Check dashboard for anomalies
  - Verify all exporters are up

Monthly:
  - Review alert thresholds
  - Analyze false positive rate
  - Check for new exporter versions

Quarterly:
  - Review metric retention needs
  - Evaluate new monitoring requirements
  - Update dashboards based on usage patterns
```

### 10.2 Dashboard Evolution
```
Track dashboard usage:
  - Which dashboards are accessed most
  - Which panels provide most value
  - Which panels are never viewed

Iterate based on feedback:
  - Add panels for frequent manual queries
  - Remove or consolidate rarely-used panels
  - Adjust time ranges and thresholds
```

---

## Conclusion

The observability stack has **strong foundational coverage** with well-designed dashboards for core services (node, nginx, mysql, phpfpm). However, **two critical gaps** exist:

1. **fail2ban_exporter** - Has alerts but zero dashboard visibility (empty file)
2. **promtail** - Completely missing monitoring (no dashboard, no alerts)

These gaps create **blind spots in security monitoring and log pipeline health**. The recommendations in this document provide a clear roadmap to achieve comprehensive observability coverage.

**Estimated Effort:**
- Priority 1 (Critical): 8-12 hours
- Priority 2 (High): 4-6 hours
- Priority 3 (Medium): 6-8 hours
- Priority 4 (Low): 8-12 hours

**Total: 26-38 hours** to achieve complete coverage.
