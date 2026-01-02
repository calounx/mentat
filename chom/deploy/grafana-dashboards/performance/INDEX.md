# CHOM Performance Dashboards - Complete Index

## Quick Navigation

### For Immediate Setup
Start here: [QUICK-START.md](./QUICK-START.md)

### For Complete Information
Main guide: [README.md](./README.md)

### For Troubleshooting
Problem solving: [PERFORMANCE-TROUBLESHOOTING-GUIDE.md](./PERFORMANCE-TROUBLESHOOTING-GUIDE.md)

### For Project Overview
Summary: [DELIVERABLES.md](./DELIVERABLES.md)

---

## Dashboard Files

### 1. Application Performance Monitoring (APM)
**File**: [1-apm-dashboard.json](./1-apm-dashboard.json)

**Import to Grafana**: `http://localhost:3000/dashboard/import`

**Monitors**:
- Endpoint response times
- Cache performance
- Queue processing
- PHP-FPM utilization
- OPcache efficiency
- Session handling

**Use When**:
- Investigating slow API endpoints
- Optimizing cache strategy
- Troubleshooting queue delays
- Scaling PHP-FPM workers

---

### 2. Database Performance
**File**: [2-database-performance-dashboard.json](./2-database-performance-dashboard.json)

**Import to Grafana**: `http://localhost:3000/dashboard/import`

**Monitors**:
- Query latency
- Deadlocks
- Connection pools
- Index usage
- Buffer pool efficiency
- Replication lag

**Use When**:
- Identifying slow queries
- Resolving deadlocks
- Optimizing indexes
- Tuning database configuration

---

### 3. Frontend Performance & Core Web Vitals
**File**: [3-frontend-performance-dashboard.json](./3-frontend-performance-dashboard.json)

**Import to Grafana**: `http://localhost:3000/dashboard/import`

**Monitors**:
- Core Web Vitals (LCP, FID, CLS)
- Page load times
- JavaScript execution
- Asset loading
- Real User Monitoring (RUM)
- Geographic performance

**Use When**:
- Optimizing Core Web Vitals
- Improving page load speed
- Reducing JavaScript bloat
- Analyzing user experience by region

---

## Documentation Files

### QUICK-START.md
**Purpose**: Get running in 5 minutes

**Contains**:
- Prerequisites checklist
- 5-minute setup instructions
- First-time usage guide
- Common issues with quick fixes
- Emergency response procedures

**Read This If**:
- You're setting up for the first time
- You need a quick reference
- You're responding to an emergency

---

### README.md
**Purpose**: Complete implementation guide

**Contains**:
- Detailed installation instructions
- Dashboard feature descriptions
- Performance budget explanations
- Monitoring workflow
- Metric collection implementation
- Best practices

**Read This If**:
- You're doing a production deployment
- You need to understand architecture
- You're implementing custom metrics
- You want to establish best practices

---

### PERFORMANCE-TROUBLESHOOTING-GUIDE.md
**Purpose**: Comprehensive problem-solving guide

**Contains**:
- Application performance troubleshooting
- Database optimization techniques
- Frontend performance fixes
- 50+ code examples
- Before/after comparisons
- Performance testing methodology

**Read This If**:
- You're experiencing performance issues
- You need to optimize specific areas
- You want to learn optimization techniques
- You're implementing performance fixes

---

### DELIVERABLES.md
**Purpose**: Project summary and specifications

**Contains**:
- Executive summary
- Technical specifications
- Implementation checklist
- Success metrics
- Support information

**Read This If**:
- You need project overview
- You're planning implementation
- You want to understand scope
- You need to report on deliverables

---

## Common Use Cases

### I need to...

#### Set up dashboards for the first time
1. Read: [QUICK-START.md](./QUICK-START.md)
2. Import: All 3 JSON dashboard files
3. Verify: Dashboard displays data

#### Investigate slow API responses
1. Open: APM Dashboard
2. Check: "Slowest Endpoints (Top 10)" panel
3. Follow: [PERFORMANCE-TROUBLESHOOTING-GUIDE.md](./PERFORMANCE-TROUBLESHOOTING-GUIDE.md) - "Slow Endpoint Response Times"

#### Fix database deadlocks
1. Open: Database Performance Dashboard
2. Check: "Deadlock Detection" panel
3. Follow: [PERFORMANCE-TROUBLESHOOTING-GUIDE.md](./PERFORMANCE-TROUBLESHOOTING-GUIDE.md) - "Deadlock Resolution"

#### Improve Core Web Vitals
1. Open: Frontend Performance Dashboard
2. Check: "Core Web Vitals (p75)" panel
3. Follow: [PERFORMANCE-TROUBLESHOOTING-GUIDE.md](./PERFORMANCE-TROUBLESHOOTING-GUIDE.md) - "Core Web Vitals Optimization"

#### Optimize cache performance
1. Open: APM Dashboard
2. Check: "Cache Hit/Miss Ratios by Type" panel
3. Follow: [PERFORMANCE-TROUBLESHOOTING-GUIDE.md](./PERFORMANCE-TROUBLESHOOTING-GUIDE.md) - "High Cache Miss Rate"

#### Monitor database query performance
1. Open: Database Performance Dashboard
2. Check: "Query Latency Distribution" and "Slowest Queries by Table"
3. Follow: [PERFORMANCE-TROUBLESHOOTING-GUIDE.md](./PERFORMANCE-TROUBLESHOOTING-GUIDE.md) - "Slow Query Detection"

---

## Performance Budget Quick Reference

### Application (APM)
| Metric | Good | Warning | Critical |
|--------|------|---------|----------|
| Response Time (p95) | < 300ms | 500-1000ms | > 1000ms |
| Cache Hit Rate | > 95% | 75-90% | < 75% |
| Queue Processing | < 3s | 5-10s | > 10s |
| PHP-FPM Utilization | < 70% | 80-90% | > 90% |
| OPcache Hit Rate | > 97% | 90-95% | < 90% |

### Database
| Metric | Good | Warning | Critical |
|--------|------|---------|----------|
| Query Latency (p95) | < 50ms | 100-500ms | > 500ms |
| Deadlock Rate | 0/hour | 1-5/hour | > 5/hour |
| Connection Pool | < 60% | 75-90% | > 90% |
| Buffer Pool Hit | > 99.5% | 95-99% | < 95% |
| Index Efficiency | > 98% | 90-95% | < 90% |

### Frontend
| Metric | Good | Warning | Poor |
|--------|------|---------|------|
| LCP (p75) | < 2.0s | 2.5-4s | > 4s |
| FID (p75) | < 50ms | 100-300ms | > 300ms |
| CLS (p75) | < 0.05 | 0.1-0.25 | > 0.25 |
| TTFB (p75) | < 400ms | 600-1500ms | > 1500ms |
| Page Load | < 2s | 3-5s | > 5s |

---

## File Locations

All files are located at:
```
/home/calounx/repositories/mentat/chom/deploy/grafana-dashboards/performance/
```

### Dashboard JSON Files
```
1-apm-dashboard.json                          (42KB)
2-database-performance-dashboard.json         (45KB)
3-frontend-performance-dashboard.json         (49KB)
```

### Documentation Files
```
DELIVERABLES.md                               (14KB)
INDEX.md                                      (this file)
PERFORMANCE-TROUBLESHOOTING-GUIDE.md          (26KB)
QUICK-START.md                                (12KB)
README.md                                     (22KB)
```

---

## Related CHOM Documentation

- Load Testing Guide: `/home/calounx/repositories/mentat/chom/tests/load/LOAD-TESTING-GUIDE.md`
- Observability Integration: `/home/calounx/repositories/mentat/chom/deploy/docs/observability-integration/`
- E2E Testing: `/home/calounx/repositories/mentat/chom/docs/E2E-TESTING.md`

---

## Support

- Documentation Issues: Create GitHub issue
- Performance Questions: devops@chom.example.com
- Emergency Support: Contact on-call engineer

---

**Last Updated**: 2026-01-02
**Version**: 1.0.0
