# CHOM Architecture Summary

Quick reference guide to the CHOM platform architecture. For detailed diagrams and explanations, see [docs/diagrams/](./diagrams/).

## System Overview

CHOM is a multi-tenant SaaS platform for WordPress/Laravel hosting with integrated observability, built on Laravel 12 with a security-first approach.

```
Key Metrics:
- Architecture Layers: 5 (Client, Frontend, Service, Integration, Data)
- Security Layers: 4 (Edge, Authentication, Authorization, Data)
- Middleware Stack: 12 middleware components
- Database Tables: 13 core tables
- Multi-tenancy: Organization → Tenant → Sites
- Tech Stack: Laravel 12, PHP 8.2+, Livewire 3, Redis, PostgreSQL/MySQL
```

## Architecture Diagrams

All diagrams use Mermaid syntax and are viewable directly in GitHub or any Markdown viewer with Mermaid support.

### 1. System Architecture
📄 [01-system-architecture.md](./diagrams/01-system-architecture.md)

**Purpose**: Complete system design showing all components and their interactions

**Key Components**:
- Laravel Control Plane (Frontend, Services, Integration layers)
- Managed VPS Fleet (LEMP stack on each VPS)
- Observability Stack (Prometheus, Loki, Grafana)
- External Services (Stripe, SMTP, S3, DNS)

**Use Cases**:
- Understanding overall architecture
- Identifying component dependencies
- Planning new feature integration
- System design reviews

### 2. Security Architecture
📄 [02-security-architecture.md](./diagrams/02-security-architecture.md)

**Purpose**: Comprehensive security implementation across all layers

**Key Features**:
- **Edge Security**: TLS 1.3, CORS, CSRF, Rate Limiting (5-60 req/min)
- **Authentication**: Sanctum tokens with 60min expiry and auto-rotation
- **2FA**: TOTP with 7-day grace period, required for Owner/Admin
- **Authorization**: RBAC (Owner/Admin/Member/Viewer) + Policies + Gates
- **Tenant Isolation**: Global scopes ensure data segregation
- **Encryption**: AES-256-CBC for secrets, SSH keys, 2FA codes
- **Audit**: Tamper-evident logs with SHA-256 hash chain

**OWASP Top 10 Coverage**: All 10 categories addressed

**Use Cases**:
- Security audits and compliance reviews
- Threat modeling and risk assessment
- Implementing new security features
- Incident response planning

### 3. Request Flow
📄 [03-request-flow.md](./diagrams/03-request-flow.md)

**Purpose**: Detailed request lifecycle from client to response

**Flow Stages**:
1. **Reception** (10-20ms): Nginx → PHP-FPM
2. **Bootstrap** (5-15ms): Laravel kernel → Router
3. **Middleware** (20-50ms): 12 middleware layers
4. **Authorization** (10-30ms): Validation → Policies → Gates
5. **Service Layer** (30-100ms): Business logic execution
6. **Database** (20-80ms): Query with caching
7. **Response** (10-20ms): Transform → JSON

**Performance**:
- Cold Start: 250-400ms
- Warm (Cached): 80-150ms
- Database Queries: 2-8 (cold), 0-2 (cached)

**Use Cases**:
- Performance optimization
- Debugging request issues
- Understanding middleware order
- Identifying bottlenecks

### 4. Deployment Architecture
📄 [04-deployment-architecture.md](./diagrams/04-deployment-architecture.md)

**Purpose**: Infrastructure deployment and operations

**Infrastructure**:
- **Control Plane**: Single server running Laravel app
- **VPS Fleet**: Multiple managed servers (shared/dedicated)
- **Observability**: Dedicated monitoring server

**Workflows**:
1. **Control Plane Deployment**: Git pull → Composer → Migrations → Cache (3-5min)
2. **VPS Provisioning**: API → Bootstrap → LEMP Stack → Monitoring (5-10min)
3. **Site Deployment**: Queue → SSH → Configure → SSL → Deploy (2-5min)
4. **Backups**: Scheduled → Dump → Tar → S3 Upload (daily)

**Scaling**:
- Horizontal: Add more VPS servers to fleet
- Vertical: Upgrade server resources
- Auto-scale: Trigger at 70% capacity

**Use Cases**:
- Infrastructure planning
- Deployment automation
- Disaster recovery
- Scaling strategy

### 5. Database Schema
📄 [05-database-schema.md](./diagrams/05-database-schema.md)

**Purpose**: Complete database design and relationships

**Core Tables**:
- `organizations`: Billing entities (Stripe customers)
- `users`: Team members with RBAC roles
- `tenants`: Isolation units (cached aggregates)
- `sites`: Customer sites (tenant-scoped)
- `vps_servers`: Managed infrastructure (encrypted SSH keys)
- `vps_allocations`: Resource tracking
- `site_backups`: Backup metadata
- `audit_logs`: Hash-chained audit trail

**Multi-Tenancy**:
```
Organization (1) → Tenants (N) → Sites (N)
```

**Security Features**:
- Encrypted fields: 2FA secrets, SSH keys, backup codes
- Tenant isolation: Global scopes on all queries
- Audit integrity: SHA-256 hash chain
- Soft deletes: Recovery within retention period

**Performance**:
- 45+ strategic indexes
- Cached aggregates (site count, storage usage)
- Connection pooling
- Query optimization

**Use Cases**:
- Database design and modeling
- Query optimization
- Data migration planning
- Schema evolution

## Architecture Principles

### 1. Security-First
Every layer implements security controls:
- Input validation at edge
- Authentication via Sanctum
- Authorization via policies
- Encryption at rest and in transit
- Audit all actions

### 2. Multi-Tenancy
Three-level hierarchy with automatic isolation:
```php
// Global scope automatically applied
Site::all(); // WHERE tenant_id = '{current_tenant_id}'
```

### 3. Performance-Optimized
- Redis caching (sessions, queries, API responses)
- Background jobs for long operations
- Connection pooling (SSH, Redis, DB)
- Cached aggregates to avoid expensive queries

### 4. Observability-Driven
Every component is monitored:
- Metrics: Prometheus scrapes all VPS
- Logs: Promtail ships to Loki
- Dashboards: Grafana per tenant
- Alerts: AlertManager routing

### 5. Scalable Design
- Stateless application layer
- Queue-based job processing
- Auto-allocation of VPS resources
- Horizontal scaling of VPS fleet

## Technology Stack

### Backend Layer
| Component | Technology | Version |
|-----------|------------|---------|
| Framework | Laravel | 12.x |
| Language | PHP | 8.2+ |
| Auth | Sanctum | 4.2 |
| Billing | Cashier | 16.1 |
| SSH | phpseclib | 3.0 |

### Frontend Layer
| Component | Technology | Version |
|-----------|------------|---------|
| UI | Livewire | 3.x |
| JS | Alpine.js | 3.x |
| CSS | Tailwind | 4.x |
| Build | Vite | 7.x |

### Data Layer
| Component | Technology | Version |
|-----------|------------|---------|
| Database | PostgreSQL/MySQL | 13+/8.0+ |
| Cache | Redis | 7.x |
| Queue | Redis Queue | - |
| Storage | S3/Local | - |

### Infrastructure
| Component | Technology | Version |
|-----------|------------|---------|
| Web Server | Nginx | Latest |
| App Server | PHP-FPM | 8.2 |
| OS | Ubuntu | 24.04 LTS |
| Container | Docker | Optional |

### Observability
| Component | Technology | Version |
|-----------|------------|---------|
| Metrics | Prometheus | Latest |
| Logs | Loki | Latest |
| Visualization | Grafana | Latest |
| Alerting | AlertManager | Latest |

## Key Architecture Patterns

### 1. Service Layer Pattern
Encapsulate business logic in dedicated service classes:
```php
class SiteService {
    public function createSite(array $data): Site {
        DB::beginTransaction();
        try {
            $site = $this->repository->create($data);
            $vps = $this->vpsService->allocate($site);
            DeploySiteJob::dispatch($site);
            DB::commit();
            return $site;
        } catch (Exception $e) {
            DB::rollBack();
            throw $e;
        }
    }
}
```

### 2. Repository Pattern
Abstract data access logic:
```php
class SiteRepository {
    public function findByTenant(Tenant $tenant): Collection {
        $cacheKey = "sites:tenant:{$tenant->id}";
        return Cache::remember($cacheKey, 300, function () use ($tenant) {
            return Site::where('tenant_id', $tenant->id)->get();
        });
    }
}
```

### 3. Global Scope Pattern
Automatic tenant filtering:
```php
protected static function booted(): void {
    static::addGlobalScope('tenant', function ($builder) {
        if (auth()->check() && auth()->user()->currentTenant()) {
            $builder->where('tenant_id', auth()->user()->currentTenant()->id);
        }
    });
}
```

### 4. Middleware Pipeline Pattern
Sequential request processing:
```
Request → TLS → CORS → CSRF → RateLimit → Auth → Tenant → 2FA → Controller
```

### 5. Job Queue Pattern
Async processing for long operations:
```php
DeploySiteJob::dispatch($site)
    ->onQueue('deployments')
    ->delay(now()->addSeconds(5));
```

## Critical Data Flows

### Site Deployment Flow
```
User Request
  → API Endpoint (validated)
  → SiteController (authorized)
  → SiteService (business logic)
  → Database (create record)
  → Queue (dispatch job)
  ← Response (202 Accepted)

Background Job
  → VPS Bridge (SSH connection)
  → VPS Manager CLI (remote commands)
  → Configure Nginx, PHP, MySQL
  → Deploy application files
  → Issue SSL certificate
  → Update site status
```

### Authentication Flow
```
Login Request
  → Validate credentials
  → Check 2FA required?
    Yes → Send to 2FA verification
    No → Issue token
  → Token stored in Redis
  → Response with Bearer token

Subsequent Requests
  → Extract Bearer token
  → Validate token (Sanctum)
  → Load user
  → Check 2FA verified (if required)
  → Load tenant context
  → Process request
```

### Backup Flow
```
Scheduler (2 AM daily)
  → Queue BackupSiteJob for each site
  → Job connects via SSH
  → Dump MySQL database (gzip)
  → Tar application files (gzip)
  → Upload to S3
  → Create backup record
  → Prune old backups (retention policy)
  → Send email report (if failures)
```

## Security Highlights

### Defense in Depth
```
Layer 1: Edge Security
  - TLS 1.3 encryption
  - CORS validation
  - CSRF protection
  - Rate limiting

Layer 2: Authentication
  - Sanctum token auth
  - 60-minute token expiry
  - Automatic token rotation
  - 2FA for privileged roles

Layer 3: Authorization
  - RBAC (4 roles)
  - Policy-based access control
  - Feature gates
  - Tenant isolation

Layer 4: Data Security
  - Encryption at rest (AES-256)
  - Encryption in transit (TLS)
  - SSH key rotation (90 days)
  - Audit logging (tamper-evident)
```

### Compliance Ready
- **GDPR**: Data export, deletion, audit trails
- **SOC 2**: Access controls, encryption, monitoring
- **PCI DSS**: Stripe handles card data (Level 1)
- **HIPAA**: Encryption, audit logs (if needed)

## Performance Benchmarks

### Request Latency
| Scenario | Cold Start | Warm (Cached) |
|----------|-----------|---------------|
| Simple GET | 250-400ms | 80-150ms |
| Authenticated API | 300-450ms | 100-180ms |
| Database Query | 50-120ms | 2-5ms |
| Site Deployment | 2-5 minutes | N/A |
| Backup | 1-3 minutes | N/A |

### Capacity
| Resource | Shared VPS | Dedicated VPS |
|----------|-----------|---------------|
| Sites per VPS | 10-50 | 1 |
| Memory per Site | 256 MB | Unlimited |
| CPU Allocation | Shared | Dedicated |
| Storage | Shared | Dedicated |

### Scalability
- **VPS Fleet**: Unlimited (auto-provision)
- **Sites per Tenant**: Tier-dependent (5/25/unlimited)
- **Concurrent Requests**: 100-500 (per control plane instance)
- **Background Jobs**: 4-8 workers (configurable)

## Monitoring & Observability

### Metrics Collected
- Request duration and throughput
- Database query performance
- Cache hit rates
- Queue depth and processing time
- VPS resource utilization (CPU, memory, disk)
- Site response times

### Logs Aggregated
- Application logs (Laravel)
- Web server logs (Nginx access/error)
- Database logs (slow queries)
- System logs (syslog)
- Security events (audit logs)

### Dashboards Available
- **Fleet Overview**: All VPS health and capacity
- **Per-VPS**: Resource usage, site count, alerts
- **Per-Site**: Traffic, performance, errors
- **Per-Tenant**: Usage, limits, billing

### Alert Rules
- VPS unhealthy or offline
- Disk space > 80%
- Memory usage > 90%
- SSL expiring < 14 days
- Backup failures
- Security events (failed logins, 2FA changes)

## Deployment Strategy

### Continuous Deployment
```
Git Push (main branch)
  → GitHub Actions
  → Run tests
  → Deploy script
  → Health check
  → Rollback on failure
```

### Zero-Downtime Deployment
1. Pull new code
2. Install dependencies
3. Run migrations (background)
4. Build assets
5. Reload PHP-FPM (graceful)
6. Clear caches
7. Restart queue workers (graceful)

### Rollback Procedure
1. Restore previous deployment
2. Rollback database migrations
3. Restart services
4. Verify health checks
5. Alert administrators

## Future Enhancements

### Planned Improvements
- [ ] Multi-region support (geo-distribution)
- [ ] Advanced caching (Varnish/CloudFlare)
- [ ] Kubernetes deployment option
- [ ] GraphQL API alongside REST
- [ ] WebSocket support for real-time updates
- [ ] Advanced RBAC (custom roles)
- [ ] Multi-tenancy at database level (schema per tenant)
- [ ] Enhanced backup (incremental, point-in-time)

### Scalability Roadmap
- [ ] Control plane horizontal scaling (load balancer)
- [ ] Database read replicas
- [ ] Redis cluster for distributed cache
- [ ] CDN integration for static assets
- [ ] Edge computing for low-latency regions

## Quick Links

- **Diagrams**: [docs/diagrams/](./diagrams/)
- **API Documentation**: [docs/api.md](./api.md)
- **Security Policy**: [SECURITY-IMPLEMENTATION.md](../SECURITY-IMPLEMENTATION.md)
- **Deployment Guide**: [deploy/README.md](../deploy/README.md)
- **Development Setup**: [DEVELOPMENT.md](../DEVELOPMENT.md)
- **Testing Guide**: [TESTING.md](../TESTING.md)

## Contributing to Architecture

When proposing architecture changes:
1. **Create ADR**: Document decision rationale
2. **Update Diagrams**: Reflect changes visually
3. **Update Documentation**: Keep docs in sync
4. **Add Tests**: Verify architectural constraints
5. **Review**: Get team approval before implementation

## Architecture Reviews

Regular architecture reviews ensure:
- Alignment with business goals
- Security best practices
- Performance requirements
- Scalability needs
- Technical debt management

**Review Schedule**: Quarterly or before major releases

---

**Document Version**: 1.0.0
**Last Updated**: 2025-12-30
**Maintained By**: CHOM Architecture Team
