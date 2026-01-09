# CHOM Documentation

**Version 2.2.0** - Cloud Hosting & Observability Manager

A multi-tenant SaaS platform for WordPress hosting management with integrated observability and automated infrastructure management.

---

## Quick Links

| Section | Description |
|---------|-------------|
| [Getting Started](#getting-started) | Installation, setup, and quick start guides |
| [Architecture](#architecture) | System design, multi-tenancy, and technical architecture |
| [Development](#development) | Testing, contribution guidelines, and development workflow |
| [Deployment](#deployment) | Production deployment procedures and automation |
| [Operations](#operations) | Monitoring, observability, health checks, and maintenance |
| [API Reference](#api-reference) | REST API endpoints and authentication |
| [VPSManager](#vpsmanager) | Server management CLI and infrastructure automation |
| [Archive](#archive) | Historical documentation and phase reports |

---

## Getting Started

New to CHOM? Start here:

- **Installation Guide** - Set up CHOM locally or in production
- **Quick Start Tutorial** - Create your first site in 5 minutes
- **Configuration Guide** - Environment variables and settings
- **First Deployment** - Deploy your application to production

---

## Architecture

Understand how CHOM works:

- **[Multi-Tenancy Security](architecture/multi-tenancy.md)** - Organization isolation and security boundaries
- **System Overview** - High-level architecture and component interactions
- **Database Schema** - Models, relationships, and data structure
- **Security Model** - Authentication, authorization, and tenant isolation
- **Storage Architecture** - File storage, backups, and CHOM-STORAGE design

Related files:
- [CHOM-STORAGE Architecture](CHOM-STORAGE-ARCHITECTURE.md)
- [POC Operational Plan](POC-OPERATIONAL-PLAN.md)

---

## Development

Contributing to CHOM:

- **[Testing Guide](development/testing.md)** - Unit tests, feature tests, and test coverage
- **Code Style** - PHP/Laravel conventions and best practices
- **Development Workflow** - Git flow, branches, and pull requests
- **Adding Features** - How to extend CHOM functionality
- **Debugging** - Common issues and troubleshooting

---

## Deployment

Deploy CHOM to production:

- **Production Deployment** - Step-by-step production deployment guide
- **Observability Stack** - Prometheus, Loki, and Grafana setup
- **VPSManager Installation** - Server management infrastructure
- **Secrets Management** - Secure credential handling
- **SSL Certificates** - HTTPS setup and Let's Encrypt integration
- **Backup & Recovery** - Data protection and disaster recovery

---

## Operations

Keep CHOM running smoothly:

- **[Observability](operations/observability.md)** - Metrics, logs, and distributed tracing
- **[Health Checks](operations/health-checks.md)** - System health monitoring and alerts
- **[Self-Healing](operations/self-healing.md)** - Automated recovery and fault tolerance
- **Monitoring Dashboards** - Grafana dashboards and alerting rules
- **Performance Tuning** - Optimization and scaling strategies
- **Incident Response** - Troubleshooting and emergency procedures

---

## API Reference

REST API documentation:

- **Authentication** - Sanctum token-based auth
- **Organizations & Tenants** - Multi-tenancy API endpoints
- **Sites Management** - Create, update, delete sites
- **Backups** - Backup creation, restoration, and management
- **VPS Servers** - Fleet management and health monitoring
- **Webhooks** - Stripe billing webhooks and event handlers

---

## VPSManager

Server management CLI:

- **Installation** - Set up VPSManager on target servers
- **Site Management** - Create, configure, and delete sites
- **User Isolation** - Per-site system users and security
- **Database Management** - MySQL/MariaDB provisioning
- **SSL Management** - Certificate generation and renewal
- **Nginx Configuration** - Web server setup and optimization

---

## Archive

Historical documentation and implementation reports:

- Phase 0 Reports - Initial deployment and setup
- Phase 1 & 2 Reports - Multi-tenancy implementation
- Phase 3 Reports - Observability and monitoring
- Migration Guides - Upgrade procedures and breaking changes
- Legacy Documentation - Superseded by current docs

See [archive/](archive/) directory for all historical documents.

---

## Version History

| Version | Date | Highlights |
|---------|------|------------|
| **2.2.0** | 2026-01-10 | System Health & Self-Healing, VPSManager UI, Enhanced Observability |
| **2.1.0** | 2026-01-09 | Multi-tenancy security, Loki multi-tenancy, Password reset |
| **2.0.0** | 2026-01-06 | PoC operational architecture, CHOM-STORAGE design |
| **1.0.0** | 2025-12-xx | Initial release with core functionality |

---

## Support & Resources

- **Issue Tracker** - GitHub Issues
- **Discussions** - GitHub Discussions
- **Email** - support@chom.io
- **Documentation** - This site

---

## Contributing

We welcome contributions! See [Development](#development) section for guidelines.

---

## License

MIT License - see [LICENSE](../LICENSE) for details.
