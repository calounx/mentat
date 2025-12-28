# Observability Stack - Roadmap & Missing Features

> Generated from comprehensive architecture review - December 2025

## Executive Summary

The observability-stack is a **production-grade, self-hosted monitoring platform** covering 80% of typical observability use cases. This roadmap outlines the missing 20% and prioritizes enhancements based on impact and effort.

**Current Capabilities:**
- ✅ 10 production exporters (Node, Nginx, MySQL, PHP-FPM, Fail2ban, etc.)
- ✅ 60+ pre-built alert rules across 8 domains
- ✅ 11 pre-configured dashboards
- ✅ Advanced SLO/SLI framework (Google SRE model)
- ✅ Three-pillar observability (Metrics → Prometheus, Logs → Loki, Traces → Tempo)
- ✅ Automated deployment and phased upgrades
- ✅ Module-based architecture for extensibility

---

## Tier 1: Critical Missing Features (High Impact, High Priority)

### 1.1 PostgreSQL Exporter
**Impact:** High - PostgreSQL is the most popular open-source database
**Effort:** Low (1-2 days)
**Dependencies:** None

**Details:**
- Add postgres_exporter module
- Monitor: connections, transactions, cache hit ratios, replication lag
- Pre-built dashboard: PostgreSQL Overview
- Alert rules: connection pool saturation, slow queries, replication issues
- Auto-detection: Check for postgresql service

**Implementation:**
```bash
modules/_core/postgres_exporter/
├── module.yaml
├── dashboards/postgres-overview.json
├── alerts/postgres-alerts.yaml
└── README.md
```

### 1.2 Redis Exporter
**Impact:** High - Redis is critical for caching/sessions
**Effort:** Low (1-2 days)
**Dependencies:** None

**Details:**
- Add redis_exporter module
- Monitor: memory usage, keyspace hits/misses, connected clients, evictions
- Dashboard: Redis Overview
- Alerts: memory saturation, eviction rates, connection limits
- Auto-detection: Check for redis service

### 1.3 Synthetic Monitoring (Blackbox Exporter)
**Impact:** Critical - Uptime monitoring from external perspective
**Effort:** Medium (3-5 days)
**Dependencies:** None

**Details:**
- Add blackbox_exporter module
- Probes: HTTP/HTTPS, TCP, ICMP, DNS
- Monitor: uptime, response time, SSL expiration, DNS resolution
- Dashboard: Uptime Overview with SLA tracking
- Alerts: service down, high latency, SSL expiring
- Config: HTTP probes for critical endpoints
- Integration with SLO framework (availability SLOs)

**Use Cases:**
- External uptime checks (website, API availability)
- SSL certificate monitoring
- DNS resolution checks
- Network connectivity validation

### 1.4 PagerDuty Integration (Pre-configured)
**Impact:** High - Critical for production incident management
**Effort:** Low (1 day)
**Dependencies:** None

**Details:**
- Pre-configured Alertmanager routes for PagerDuty
- Template with integration key placeholders
- Severity mapping (critical → high urgency, warning → low urgency)
- Auto-create incidents
- Documentation: Step-by-step setup guide
- Test notification script

### 1.5 Slack/Discord Integration (Pre-configured)
**Impact:** Medium - Team collaboration notifications
**Effort:** Low (1-2 days)
**Dependencies:** None

**Details:**
- Pre-configured Alertmanager templates for:
  - Slack (webhook integration)
  - Discord (webhook integration)
  - Microsoft Teams (webhook integration)
- Formatted notifications with context and runbook links
- Alert grouping and deduplication
- Color-coded severity (red=critical, yellow=warning)
- Documentation with webhook setup steps

---

## Tier 2: Important Enhancements (High Impact, Medium Priority)

### 2.1 Docker/Container Monitoring (cAdvisor)
**Impact:** High - Containers are ubiquitous
**Effort:** Medium (3-4 days)
**Dependencies:** Docker installed

**Details:**
- Add cadvisor module (Google's Container Advisor)
- Monitor: container CPU, memory, network, disk I/O
- Per-container resource usage
- Container restart tracking
- Dashboard: Docker Overview
- Alerts: container OOM, high CPU, frequent restarts
- Auto-detection: Check for docker service

### 2.2 Log Anomaly Detection (Loki-based)
**Impact:** Medium - Proactive issue detection
**Effort:** High (1-2 weeks)
**Dependencies:** Python, ML libraries

**Details:**
- Implement log pattern analysis
- Detect unusual log volume spikes
- Identify new error patterns
- Alert on anomalies
- Integration with Loki queries
- Dashboard: Log Anomaly Trends

**Approach:**
- Option A: Use LogCLI + simple statistical analysis
- Option B: Integrate with Grafana ML plugin
- Option C: Custom Python script analyzing Loki metrics

### 2.3 Elasticsearch Exporter
**Impact:** Medium - For Elasticsearch users
**Effort:** Medium (3 days)
**Dependencies:** Elasticsearch cluster

**Details:**
- Add elasticsearch_exporter module
- Monitor: cluster health, node stats, indices, JVM heap
- Dashboard: Elasticsearch Overview
- Alerts: cluster red, low disk, high JVM pressure
- Auto-detection: Check for elasticsearch service

### 2.4 Kafka Exporter
**Impact:** Medium - For event streaming platforms
**Effort:** Medium (3-4 days)
**Dependencies:** Kafka cluster

**Details:**
- Add kafka_exporter module
- Monitor: broker metrics, topic lag, consumer groups
- Dashboard: Kafka Overview
- Alerts: high lag, under-replicated partitions, broker down
- Auto-detection: Check for kafka service

### 2.5 HAProxy Exporter
**Impact:** Medium - Load balancer monitoring
**Effort:** Low (2 days)
**Dependencies:** HAProxy

**Details:**
- Add haproxy_exporter module
- Monitor: backend health, request rates, response times, session limits
- Dashboard: HAProxy Overview
- Alerts: backend down, high error rates, session limit
- Auto-detection: Check for haproxy service

### 2.6 MongoDB Exporter
**Impact:** Medium - NoSQL database monitoring
**Effort:** Medium (3 days)
**Dependencies:** MongoDB

**Details:**
- Add mongodb_exporter module
- Monitor: operations, connections, replication lag, oplog window
- Dashboard: MongoDB Overview
- Alerts: replication lag, connection pool, oplog exhaustion
- Auto-detection: Check for mongod service

---

## Tier 3: Nice-to-Have Features (Medium Impact, Lower Priority)

### 3.1 Runbook Automation
**Impact:** Medium - Reduces MTTR
**Effort:** High (2-3 weeks)
**Dependencies:** Webhook infrastructure

**Details:**
- Automated remediation scripts
- Webhook-triggered actions
- Example runbooks:
  - Restart service on failure
  - Clear disk space (log rotation)
  - Flush cache on high memory
- Safety mechanisms (rate limiting, approval gates)
- Audit logging of automated actions

### 3.2 Service Dependency Dashboard
**Impact:** Medium - Visualize architecture
**Effort:** Medium (1 week)
**Dependencies:** Tempo service graph

**Details:**
- Enhanced service graph dashboard
- Real-time dependency visualization
- Error propagation tracking
- Latency breakdown by service
- Integration with Tempo service graphs

### 3.3 Cost Tracking Dashboard
**Impact:** Low-Medium - Resource optimization
**Effort:** Medium (1 week)
**Dependencies:** Resource usage metrics

**Details:**
- Estimate infrastructure costs
- Storage growth trends
- Metric cardinality costs
- Log volume trends
- Recommendations for optimization

### 3.4 Kubernetes Monitoring Integration
**Impact:** High (for K8s users) - Critical for container orchestration
**Effort:** High (2-3 weeks)
**Dependencies:** Kubernetes cluster

**Details:**
- kube-state-metrics deployment
- kubelet metrics collection
- cAdvisor integration (per-pod metrics)
- Dashboards: K8s cluster, nodes, pods, deployments
- Alerts: pod crashes, node pressure, deployment failures
- Documentation: Kubernetes deployment guide

**Note:** Designed for bare-metal/VPS, not Kubernetes-native. This would be a major architectural shift.

### 3.5 Application Performance Monitoring (APM) Guide
**Impact:** Medium - Code-level insights
**Effort:** Medium (1-2 weeks)
**Dependencies:** Application instrumentation

**Details:**
- Documentation for instrumenting applications
- OpenTelemetry SDK examples (Go, Python, Node.js, PHP)
- Auto-instrumentation guides
- Trace context propagation
- Dashboard templates for APM
- Example: Instrument Laravel app for CHOM

**Approach:**
- Document manual instrumentation (not automatic agent)
- Provide code snippets for common frameworks
- Link to OpenTelemetry documentation

### 3.6 Apache Exporter
**Impact:** Low - For Apache users (Nginx preferred)
**Effort:** Low (2 days)
**Dependencies:** Apache

**Details:**
- Add apache_exporter module
- Monitor: requests, traffic, worker status
- Dashboard: Apache Overview
- Alerts: high error rates, worker saturation
- Auto-detection: Check for apache2/httpd service

### 3.7 RabbitMQ Exporter
**Impact:** Low-Medium - Message queue monitoring
**Effort:** Medium (3 days)
**Dependencies:** RabbitMQ

**Details:**
- Add rabbitmq_exporter module
- Monitor: queue depth, message rates, connections, channels
- Dashboard: RabbitMQ Overview
- Alerts: queue buildup, connection limits, node down
- Auto-detection: Check for rabbitmq service

### 3.8 Memcached Exporter
**Impact:** Low - Caching monitoring
**Effort:** Low (1-2 days)
**Dependencies:** Memcached

**Details:**
- Add memcached_exporter module
- Monitor: cache hit/miss ratio, evictions, connections
- Dashboard: Memcached Overview
- Alerts: low hit rate, high evictions
- Auto-detection: Check for memcached service

---

## Tier 4: Advanced/Enterprise Features (Lower Priority)

### 4.1 Multi-Region High Availability
**Impact:** High (for enterprise) - Production resilience
**Effort:** Very High (4-6 weeks)
**Dependencies:** Multiple VPS/regions

**Details:**
- Active-active Prometheus federation
- Loki multi-tenancy and replication
- Grafana HA setup
- Automated failover
- Cross-region querying
- DR testing procedures

**Scope:** Major architectural change, potentially out-of-scope for VPS-focused design

### 4.2 RBAC & Audit Logging
**Impact:** High (for compliance) - Security & compliance
**Effort:** High (3-4 weeks)
**Dependencies:** Reverse proxy or Grafana Enterprise

**Details:**
- Implement RBAC layer (via OAuth proxy or Grafana Enterprise)
- Audit logging for configuration changes
- User access tracking
- Compliance reporting dashboard
- Integration with LDAP/SSO

### 4.3 Real User Monitoring (RUM)
**Impact:** Medium - UX insights
**Effort:** Very High (6-8 weeks)
**Dependencies:** Frontend instrumentation

**Details:**
- JavaScript SDK for browser monitoring
- Core Web Vitals tracking (LCP, FID, CLS)
- User session tracking
- Error tracking (frontend exceptions)
- Dashboard: RUM Overview
- Integration with Grafana Faro (Grafana's RUM solution)

**Approach:**
- Document Grafana Faro integration
- Provide example instrumentation for Laravel/Vue
- Not a custom implementation

### 4.4 Anomaly Detection (ML-based)
**Impact:** Medium - Proactive detection
**Effort:** Very High (8-12 weeks)
**Dependencies:** ML infrastructure

**Details:**
- Machine learning model for metric anomaly detection
- Seasonal pattern recognition
- Baseline establishment
- Alerting on deviations
- Integration with Prometheus metrics

**Approach:**
- Option A: Integrate Grafana ML plugin (SaaS)
- Option B: Use Facebook Prophet for forecasting
- Option C: Custom model (TensorFlow/PyTorch)

**Note:** Complex to implement, may require external service

---

## Priority Implementation Plan

### Phase 1: Quick Wins (Q1 2025) - 2-3 weeks
**Focus:** Low-hanging fruit with high impact

1. **PostgreSQL Exporter** (2 days)
2. **Redis Exporter** (2 days)
3. **PagerDuty Integration** (1 day)
4. **Slack/Discord Integration** (2 days)
5. **Apache Exporter** (1 day)
6. **Memcached Exporter** (1 day)

**Deliverables:**
- 6 new modules
- Pre-configured integrations
- Documentation updates

### Phase 2: Critical Infrastructure (Q2 2025) - 4-6 weeks
**Focus:** Essential production capabilities

1. **Blackbox Exporter (Synthetic Monitoring)** (5 days)
2. **Docker/cAdvisor** (4 days)
3. **HAProxy Exporter** (2 days)
4. **Elasticsearch Exporter** (3 days)
5. **MongoDB Exporter** (3 days)
6. **Kafka Exporter** (4 days)

**Deliverables:**
- 6 infrastructure modules
- Uptime monitoring capability
- Container monitoring

### Phase 3: Enhancements (Q3 2025) - 6-8 weeks
**Focus:** Advanced features and automation

1. **Log Anomaly Detection** (2 weeks)
2. **Service Dependency Dashboard** (1 week)
3. **Runbook Automation Framework** (3 weeks)
4. **Cost Tracking Dashboard** (1 week)
5. **APM Instrumentation Guide** (1 week)

**Deliverables:**
- Anomaly detection
- Automation framework
- Cost optimization tools

### Phase 4: Enterprise & Advanced (Q4 2025) - TBD
**Focus:** Enterprise readiness (if needed)

1. **Kubernetes Integration** (3 weeks)
2. **RBAC & Audit Logging** (4 weeks)
3. **RUM (Grafana Faro integration)** (2 weeks)
4. **Multi-Region HA** (6 weeks)

**Deliverables:**
- K8s support
- Enterprise security
- Global deployment capability

---

## Migration Timeline

### Urgent: Promtail → Alloy Migration
**Deadline:** Q4 2025 (before EOL March 2, 2026)
**Effort:** Medium (2 weeks)
**Priority:** High

**Tasks:**
1. Document Alloy configuration for log shipping
2. Create migration guide from Promtail
3. Update all host configurations
4. Test log ingestion via Alloy
5. Deprecate Promtail module
6. Update documentation

---

## Community Contributions Welcome

The following features are ideal for community contributions:

**Easy (Good First Issues):**
- Apache Exporter
- Memcached Exporter
- Additional dashboard customizations
- Alert rule fine-tuning
- Documentation improvements

**Medium:**
- PostgreSQL Exporter
- Redis Exporter
- MongoDB Exporter
- Elasticsearch Exporter

**Advanced:**
- Kubernetes integration
- Anomaly detection
- Runbook automation

---

## Feature Request Process

1. **Submit Issue:** Open GitHub issue with feature request template
2. **Discussion:** Community discussion and prioritization
3. **Design:** Architecture and implementation plan
4. **Implementation:** Code, tests, documentation
5. **Review:** Code review and testing
6. **Merge:** Integration into main branch
7. **Release:** Included in next version

---

## Metrics for Success

### Coverage Goals
- **Exporters:** 20+ modules (currently 10)
- **Dashboards:** 20+ pre-built (currently 11)
- **Alert Rules:** 100+ rules (currently 60+)
- **SLOs:** 15+ services (currently 8)

### Quality Goals
- Test coverage: 95%+ (currently ~94%)
- Documentation: 100% coverage
- Security: Zero high/critical vulnerabilities
- Performance: <2% overhead on monitored systems

---

## Conclusion

This roadmap balances practical enhancements with maintaining the stack's core strengths:
- ✅ Self-hosted and open-source
- ✅ VPS-optimized (no Docker/K8s required)
- ✅ Production-ready out-of-the-box
- ✅ Modular and extensible

**Next Steps:**
1. Community feedback on priorities
2. Assign ownership for Phase 1 features
3. Create GitHub milestones
4. Begin implementation Q1 2025

---

**Questions or suggestions?** Open an issue: https://github.com/calounx/mentat/issues
