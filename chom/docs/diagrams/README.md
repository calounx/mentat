# CHOM Architecture Diagrams

Comprehensive visual documentation of the CHOM platform architecture using Mermaid diagrams.

## Overview

This directory contains detailed architecture diagrams that provide insights into various aspects of the CHOM (Cloud Hosting & Observability Manager) platform. Each diagram focuses on a specific architectural concern and includes detailed explanations.

## Diagrams

### 1. System Architecture
**File:** [01-system-architecture.md](./01-system-architecture.md)

Shows the complete system architecture including:
- Laravel application structure (Frontend, Services, Integration, Data layers)
- Managed VPS fleet infrastructure
- Observability stack integration (Prometheus, Loki, Grafana)
- External service integrations (Stripe, SMTP, S3, DNS)
- Data flow between components
- Background job processing
- Queue management

**Best for:** Understanding overall system design and component interactions

### 2. Security Architecture
**File:** [02-security-architecture.md](./02-security-architecture.md)

Illustrates the comprehensive security implementation:
- Defense-in-depth strategy with multiple security layers
- Authentication flow (Sanctum token-based with rotation)
- Two-Factor Authentication (2FA) implementation
- Authorization layer (RBAC + Policies + Gates)
- Tenant isolation mechanisms
- Encryption at rest and in transit
- Audit logging with hash chain integrity
- OWASP Top 10 coverage

**Best for:** Security review, compliance audits, threat modeling

### 3. Request Flow
**File:** [03-request-flow.md](./03-request-flow.md)

Details the complete lifecycle of an HTTP request:
- Request entry through Nginx and PHP-FPM
- Laravel bootstrap and routing
- Middleware execution order (12 middleware layers)
- Authentication and authorization checks
- Service layer execution
- Repository and database access with caching
- Response construction and delivery
- Error handling flows
- Performance benchmarks

**Best for:** Performance optimization, debugging, understanding request processing

### 4. Deployment Architecture
**File:** [04-deployment-architecture.md](./04-deployment-architecture.md)

Covers infrastructure deployment and operations:
- Control plane server setup
- VPS fleet provisioning workflow
- Site deployment sequence
- Backup and restore procedures
- Monitoring agent installation
- Observability stack configuration
- Scaling strategies (horizontal and vertical)
- Disaster recovery planning

**Best for:** DevOps, infrastructure planning, deployment automation

### 5. Database Schema
**File:** [05-database-schema.md](./05-database-schema.md)

Comprehensive database design documentation:
- Entity-Relationship (ER) diagram with all tables
- Multi-tenancy implementation (Organization → Tenant → Sites)
- Tenant isolation via global scopes
- Foreign key relationships and constraints
- Encrypted fields (2FA secrets, SSH keys)
- Performance optimizations (cached aggregates, strategic indexes)
- Audit trail with hash chain integrity
- Security features in schema design

**Best for:** Database design, query optimization, data modeling

## How to Use These Diagrams

### Viewing Diagrams
All diagrams are written in Mermaid syntax and can be viewed in:
- **GitHub**: Native Mermaid rendering in markdown files
- **VS Code**: Install "Markdown Preview Mermaid Support" extension
- **Mermaid Live Editor**: Copy diagram code to https://mermaid.live/
- **Documentation Sites**: Rendered automatically in MkDocs, Docusaurus, etc.

### For Different Audiences

#### Developers
Start with:
1. **Request Flow** - Understand how requests are processed
2. **Database Schema** - Learn the data model
3. **System Architecture** - See how components interact

#### Security Reviewers
Focus on:
1. **Security Architecture** - Complete security implementation
2. **Request Flow** - Security middleware stack
3. **Database Schema** - Encryption and audit trails

#### DevOps Engineers
Review:
1. **Deployment Architecture** - Infrastructure and deployment
2. **System Architecture** - Component dependencies
3. **Request Flow** - Performance characteristics

#### Product Managers
Overview:
1. **System Architecture** - High-level system design
2. **Deployment Architecture** - Scaling capabilities
3. **Security Architecture** - Security features and compliance

## Architecture Principles

### 1. Multi-Tenancy
CHOM implements a hybrid multi-tenancy model:
```
Organization (Billing Entity)
  └── Tenant (Isolation Unit)
        └── Sites (Resources)
```

Key features:
- Global query scopes for automatic tenant filtering
- Tenant context middleware ensures isolation
- Cached aggregates for performance at scale

### 2. Security-First Design
- **Defense in Depth**: Multiple security layers (edge, auth, authz, data)
- **Zero Trust**: Verify at every layer
- **Least Privilege**: Role-based access control
- **Audit Everything**: Immutable audit logs with hash chain

### 3. Observability-Driven
- **Metrics**: Prometheus integration for all VPS and sites
- **Logs**: Centralized log aggregation via Loki
- **Traces**: Distributed tracing for debugging
- **Dashboards**: Pre-built Grafana dashboards per tenant

### 4. Performance Optimized
- **Caching**: Redis for sessions, queries, and API responses
- **Background Jobs**: Queue-based processing for long operations
- **Connection Pooling**: SSH connection reuse
- **Cached Aggregates**: Pre-calculated statistics

### 5. Scalability
- **Horizontal Scaling**: Add more VPS servers to fleet
- **Vertical Scaling**: Upgrade server resources
- **Auto-allocation**: Intelligent VPS selection
- **Load Distribution**: Balance sites across VPS fleet

## Technology Stack

### Backend
- **Framework**: Laravel 12
- **PHP**: 8.2+
- **Authentication**: Laravel Sanctum 4.2
- **Billing**: Laravel Cashier 16.1 (Stripe)
- **SSH**: phpseclib 3.0

### Frontend
- **UI Framework**: Livewire 3
- **JavaScript**: Alpine.js 3
- **CSS**: Tailwind CSS 4
- **Build Tool**: Vite 7

### Infrastructure
- **Web Server**: Nginx
- **App Server**: PHP-FPM
- **Database**: PostgreSQL / MySQL / SQLite
- **Cache**: Redis 7
- **Queue**: Redis-backed Laravel Queue

### Observability
- **Metrics**: Prometheus
- **Logs**: Loki
- **Visualization**: Grafana
- **Alerting**: AlertManager

## Architecture Decision Records (ADRs)

### ADR-001: Multi-Tenancy Model
**Decision**: Use Organization → Tenant → Sites hierarchy with global scopes

**Rationale**:
- Supports multiple tenants per organization (future use case)
- Global scopes provide automatic tenant isolation
- Cached aggregates enable performance at scale
- Clear separation between billing (org) and isolation (tenant)

### ADR-002: Sanctum Token Authentication
**Decision**: Use Laravel Sanctum with 60-minute expiration and automatic rotation

**Rationale**:
- Native Laravel integration
- Token rotation provides security without UX disruption
- Stateless authentication scales horizontally
- Grace period prevents race conditions

### ADR-003: VPS Management via SSH
**Decision**: Manage VPS fleet via SSH + VPS Manager CLI

**Rationale**:
- Provider-agnostic (works with any VPS provider)
- Full control over server configuration
- Connection pooling optimizes performance
- Encrypted key storage ensures security

### ADR-004: Observability Stack Integration
**Decision**: Integrate with Mentat observability platform (Prometheus, Loki, Grafana)

**Rationale**:
- Industry-standard tools
- Scalable time-series storage
- Rich query language (PromQL, LogQL)
- Tenant-specific dashboards and alerts

### ADR-005: Audit Log Hash Chain
**Decision**: Implement tamper-evident audit logs using hash chains

**Rationale**:
- Compliance requirements (SOC 2, GDPR)
- Detect unauthorized modifications
- Cryptographically verifiable integrity
- Minimal performance overhead

## Diagram Maintenance

### Updating Diagrams
When architecture changes:
1. Update the relevant Mermaid diagram
2. Update accompanying text explanations
3. Add changelog entry in this README
4. Review for consistency across all diagrams

### Diagram Standards
- Use consistent color schemes across diagrams
- Include legends where helpful
- Provide both visual and textual explanations
- Add examples and code snippets
- Keep diagrams focused (single responsibility)

## Changelog

### 2025-12-30
- Initial creation of all architecture diagrams
- Added comprehensive system architecture diagram
- Documented security architecture with OWASP coverage
- Created detailed request flow with middleware stack
- Added deployment architecture with provisioning workflows
- Documented complete database schema with relationships

## Related Documentation

- **API Documentation**: `/docs/api.md`
- **Security Policy**: `/SECURITY-IMPLEMENTATION.md`
- **Deployment Guide**: `/deploy/README.md`
- **Development Setup**: `/DEVELOPMENT.md`
- **Testing Guide**: `/TESTING.md`

## Contributing

When contributing architecture changes:
1. Update relevant diagrams first (design-driven)
2. Implement changes in code
3. Update documentation to reflect implementation
4. Add tests to verify architectural constraints
5. Update this README with ADRs if needed

## Questions?

For questions about architecture:
- Review the diagram most relevant to your concern
- Check related documentation
- Consult the CHOM development team
- File an issue if documentation is unclear

---

**Maintained by**: CHOM Architecture Team
**Last Updated**: 2025-12-30
**Version**: 1.0.0
