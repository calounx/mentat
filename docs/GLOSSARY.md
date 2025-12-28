# Glossary

Quick reference for technical terms used in the Mentat documentation.

---

## A

### age
A modern file encryption tool that uses ChaCha20-Poly1305 for secure encryption. Used in the observability stack for encrypting secrets at rest. Simpler and faster than GPG while maintaining strong security.
- Official documentation: https://age-encryption.org/

### Alert Rules
Conditions defined in Prometheus that trigger notifications when metrics cross specified thresholds. The observability stack includes pre-configured alert rules for CPU, memory, disk, network, database, and application metrics.

### Alertmanager
A component of the Prometheus ecosystem that handles alert routing, grouping, and delivery. Routes alerts to various receivers like email, Slack, or PagerDuty based on severity and labels.
- Port: 9093
- Documentation: https://prometheus.io/docs/alerting/latest/alertmanager/

### Alloy
An OpenTelemetry collector that receives, processes, and exports telemetry data (metrics, logs, traces). Part of the Grafana stack, it provides a unified pipeline for observability data.
- Port: 12345
- Documentation: https://grafana.com/docs/alloy/

### Alpine.js
A lightweight JavaScript framework for adding interactivity to web pages with minimal overhead. Used in CHOM's frontend alongside Livewire for reactive components.
- Documentation: https://alpinejs.dev/

### API (Application Programming Interface)
A set of defined methods for communication between software components. CHOM exposes a REST API for programmatic access to site management, backups, and observability features.

### Audit Logs
Records of all significant actions taken within a system. CHOM maintains audit logs for tracking team member activities, configuration changes, and security events.

---

## B

### Backup Retention
Policies defining how long backups are kept before deletion. CHOM supports configurable retention with options for hourly, daily, weekly, and monthly backup schedules.

### BATS (Bash Automated Testing System)
A testing framework for Bash scripts. Used extensively in the observability stack to test installation scripts, configuration generators, and upgrade procedures.
- Documentation: https://github.com/bats-core/bats-core

### Blackbox Exporter
A Prometheus exporter for synthetic monitoring via HTTP/HTTPS probes, SSL certificate checks, and uptime monitoring. Useful for external endpoint monitoring.

### Blade Templates
Laravel's templating engine for building views. CHOM uses Blade for server-side rendering of HTML with embedded PHP logic and layouts.

### Bootstrap Installer
A self-contained script that downloads and installs the observability stack on a fresh server. Provides an interactive wizard for selecting roles (Observability VPS, VPSManager, or Monitored Host).
- Location: `observability-stack/deploy/bootstrap.sh`

### Brevo
An email service provider (formerly Sendinblue) used by Alertmanager for sending alert notifications. Requires an API key configured in the secrets management system.

### Burn Rate
The rate at which an error budget is consumed. Used in SLO-based alerting to detect when errors are occurring faster than acceptable, triggering alerts before the entire budget is exhausted.

---

## C

### Cardinality
The number of unique time series in a metrics database. High cardinality (too many unique label combinations) can cause performance issues in Prometheus. Best practice is to limit labels to low-cardinality values.

### Cashier
Laravel's official package for Stripe billing integration. CHOM uses Cashier for subscription management, invoicing, and webhook handling.
- Documentation: https://laravel.com/docs/11.x/billing

### Certbot
A tool for obtaining free SSL/TLS certificates from Let's Encrypt. Automatically renews certificates before expiration and integrates with Nginx for HTTPS configuration.
- Documentation: https://certbot.eff.org/

### CHOM (Cloud Hosting & Observability Manager)
A multi-tenant SaaS platform for WordPress hosting management with integrated observability. Provides site provisioning, VPS fleet management, backups, and Stripe billing.

### Composer
The dependency manager for PHP. Used in CHOM to install Laravel packages and manage project dependencies defined in composer.json.
- Documentation: https://getcomposer.org/

### CORS (Cross-Origin Resource Sharing)
A security mechanism that controls which domains can access API endpoints. CHOM configures CORS to allow authorized cross-origin requests while blocking unauthorized access.

### CSRF (Cross-Site Request Forgery)
An attack where unauthorized commands are submitted from a user the application trusts. Laravel provides CSRF protection for all web routes via token validation.

---

## D

### Dashboard
A visual display of metrics and data in Grafana. The observability stack includes pre-built dashboards for system metrics, databases, web servers, and application performance.

### Debian
A Linux distribution known for stability and security. The observability stack is designed for Debian 13 (Trixie) with support for Ubuntu 22.04+.

### Defense in Depth
A security strategy using multiple layers of protection. The secrets management system employs file permissions, disk encryption, secret encryption, and systemd credentials for comprehensive security.

### Deployment Wizard
An interactive script that guides users through deployment decisions for both the observability stack and CHOM. Recommends appropriate configurations based on use case.
- Location: `deployment-wizard.sh`

### Distributed Tracing
Tracking requests as they flow through distributed systems. Tempo provides distributed tracing capabilities for understanding request paths, latencies, and dependencies.

---

## E

### Eloquent
Laravel's ORM (Object-Relational Mapping) for database interactions. CHOM uses Eloquent models for sites, backups, users, organizations, and VPS servers.

### Error Budget
The allowed amount of downtime or errors within an SLO period. For example, a 99.9% SLA allows 0.1% downtime (43.2 minutes per month). Error budget tracking helps balance reliability and feature velocity.

### Exporter
A program that collects metrics from a service and exposes them in Prometheus format. Examples include node_exporter (system metrics), nginx_exporter (web server), and mysqld_exporter (database).

---

## F

### Fail2ban
An intrusion prevention tool that monitors logs and bans IPs with suspicious activity. The fail2ban_exporter provides metrics on banned IPs and jail status.

### Fail2ban Exporter
A Prometheus exporter for monitoring Fail2ban jail status, banned IP counts, and ban/unban events. Useful for security monitoring and threat detection.

---

## G

### Git Subtree
A Git feature for managing monorepos by embedding one repository inside another. The Mentat monorepo uses this approach to combine the observability stack and CHOM.

### GPG (GNU Privacy Guard)
An encryption tool supporting public-key cryptography. Can be used in the secrets management system as an alternative to age for encrypting sensitive data.

### Grafana
An open-source visualization and analytics platform. Displays dashboards with metrics from Prometheus, logs from Loki, and traces from Tempo.
- Port: 3000
- Documentation: https://grafana.com/docs/grafana/latest/

---

## H

### htpasswd
A utility for creating password files with HTTP basic authentication credentials. Used to protect Prometheus and Loki endpoints with username/password authentication.

### HTTP Basic Auth
A simple authentication method using username and password sent in HTTP headers. The observability stack uses this to protect Prometheus and Loki from unauthorized access.

---

## I

### Idempotency
The property of operations that can be run multiple times with the same result. Installation and upgrade scripts are idempotent - running them repeatedly produces the same final state.

---

## J

### journalctl
A command for querying systemd logs. Used to view service logs, debug issues, and monitor system events.
- Example: `journalctl -u prometheus -f`

### jq
A command-line JSON processor. Used extensively in scripts for parsing API responses, configuration files, and structured data.
- Documentation: https://jqlang.github.io/jq/

---

## L

### Label (in Loki context)
Metadata attached to log streams for filtering and querying. Examples include job name, hostname, and severity level. Keep label cardinality low to maintain performance.

### Laravel
A PHP web framework for building modern web applications. CHOM is built on Laravel 12 and uses its features for routing, authentication, database access, and job queues.
- Documentation: https://laravel.com/docs/

### LEMP Stack
A web server stack consisting of Linux, Nginx (Engine-X), MySQL/MariaDB, and PHP. The VPSManager role installs a complete LEMP stack with monitoring.

### Let's Encrypt
A free, automated certificate authority providing SSL/TLS certificates. Certbot uses Let's Encrypt to obtain and renew certificates automatically.
- Documentation: https://letsencrypt.org/

### Livewire
A Laravel framework for building reactive interfaces without writing JavaScript. CHOM uses Livewire 3 for interactive dashboards and forms.
- Documentation: https://livewire.laravel.com/

### Loki
A log aggregation system designed for efficiency and cost-effectiveness. Stores logs with indexed labels and full-text search capabilities.
- Port: 3100
- Documentation: https://grafana.com/docs/loki/latest/

### LUKS (Linux Unified Key Setup)
A disk encryption specification for Linux. Recommended for encrypting disks containing sensitive data like secrets and backups.

---

## M

### Metrics
Numerical measurements collected over time. The observability stack collects metrics for CPU, memory, disk, network, database queries, HTTP requests, and more.

### Module
A self-contained component in the observability stack that can be independently installed. Modules include exporters (node_exporter, nginx_exporter), data stores (Prometheus, Loki), and collectors (Alloy).

### Monorepo
A repository containing multiple related projects. The Mentat monorepo includes both the observability stack and CHOM.

### Multi-tenant Architecture
A software architecture where a single instance serves multiple customers (tenants) with data isolation. CHOM uses multi-tenancy to serve multiple organizations from one deployment.

### Multi-window Alerting
An SLO alerting technique using multiple time windows to detect both fast-burning (immediate issues) and slow-burning (degrading performance) problems.

### MySQL Exporter (mysqld_exporter)
A Prometheus exporter for MySQL and MariaDB metrics including connections, queries, replication lag, and InnoDB statistics.

---

## N

### Nginx
A high-performance web server and reverse proxy. Used in the LEMP stack and as a reverse proxy for Grafana with SSL termination.
- Documentation: https://nginx.org/en/docs/

### Nginx Exporter
A Prometheus exporter for Nginx metrics including active connections, requests per second, and response codes.

### Node Exporter
A Prometheus exporter for hardware and OS-level metrics including CPU, memory, disk I/O, network, and filesystem statistics.

---

## O

### Observability
The ability to understand system internal states by examining outputs (metrics, logs, traces). The observability stack provides comprehensive observability for infrastructure and applications.

### Observability Stack
A production-ready monitoring platform including Prometheus, Loki, Tempo, Grafana, and Alertmanager. Deployed on Debian/Ubuntu without Docker or Kubernetes.

### OpenTelemetry Protocol (OTLP)
A standard protocol for transmitting telemetry data. Alloy and Tempo use OTLP for receiving traces and metrics from instrumented applications.
- Documentation: https://opentelemetry.io/docs/specs/otlp/

### ORM (Object-Relational Mapping)
A programming technique for converting data between incompatible type systems. Laravel's Eloquent is an ORM for database access using PHP objects.

---

## P

### PagerDuty
An incident management platform for on-call scheduling and alert routing. The observability stack supports PagerDuty integration via Alertmanager.

### Phased Upgrade
A strategy for upgrading components in stages to minimize risk. The upgrade orchestrator uses three phases: exporters (low-risk), Prometheus (high-risk), and Loki/Promtail (medium-risk).

### PHP-FPM (FastCGI Process Manager)
A PHP implementation optimized for high-traffic websites. The phpfpm_exporter monitors pool status, queue length, and process counts.

### PHPUnit
The standard testing framework for PHP. CHOM uses PHPUnit for unit and feature tests.
- Documentation: https://phpunit.de/

### Prometheus
An open-source monitoring system with a time-series database. Collects metrics via scraping, evaluates alert rules, and stores data with configurable retention.
- Port: 9090
- Documentation: https://prometheus.io/docs/

### Promtail
A log shipping agent that forwards logs to Loki. Reads log files, adds labels, and sends structured log data over HTTP.

### PSR-12
PHP coding standard for consistent code style. CHOM follows PSR-12 using Laravel Pint for automatic formatting.
- Documentation: https://www.php-fig.org/psr/psr-12/

---

## Q

### Queue
A system for processing background jobs asynchronously. CHOM uses Laravel queues for site provisioning, backups, and SSL certificate issuance.

---

## R

### Recording Rules
Pre-computed queries in Prometheus that calculate and store expensive queries as new time series. Used in SLO monitoring to efficiently track error rates and request counts.

### Redis
An in-memory data store used for caching, session storage, and queue backends. Optional dependency for CHOM in production deployments.

### REST API
An architectural style for web services using HTTP methods (GET, POST, PUT, DELETE). CHOM provides a RESTful API for programmatic access authenticated with Laravel Sanctum tokens.

### Retention Policy
Rules defining how long data is kept before deletion. Prometheus retains metrics for 30 days by default, while Loki retention is configurable.

### Role-Based Access Control (RBAC)
A security model where permissions are assigned to roles (Owner, Admin, Member, Viewer) rather than individual users. CHOM implements RBAC for team collaboration.

### Rollback
Reverting to a previous version after a failed upgrade. The upgrade orchestrator maintains backups and state tracking to enable safe rollbacks.

---

## S

### Sanctum
Laravel's API authentication package using token-based authentication. CHOM uses Sanctum for securing API endpoints with personal access tokens.
- Documentation: https://laravel.com/docs/11.x/sanctum

### Scraping
Prometheus's method of collecting metrics by periodically fetching data from exporters' HTTP endpoints. Scrape intervals are typically 15-60 seconds.

### Service Level Agreement (SLA)
A commitment between service provider and customer defining expected uptime and performance. Example: "99.9% uptime" means no more than 43 minutes downtime per month.

### Service Level Indicator (SLI)
A quantitative measure of service performance. Examples include request latency, error rate, and availability. SLIs are measured to track SLO compliance.

### Service Level Objective (SLO)
An internal target for service performance. Example: "95% of requests complete in under 200ms." SLOs are more strict than SLAs to provide a buffer.

### ShellCheck
A static analysis tool for shell scripts that detects bugs, style issues, and potential problems. Used in CI/CD to ensure script quality.
- Documentation: https://www.shellcheck.net/

### SLI Recording Rules
Prometheus recording rules that calculate SLI metrics (error rates, latency percentiles) from raw metrics. Pre-computation improves dashboard and alerting performance.

### SSH (Secure Shell)
A protocol for secure remote access and command execution. CHOM uses SSH to manage VPS servers, deploy sites, and execute remote operations.

### SSL/TLS
Protocols for encrypting web traffic. The observability stack and CHOM use SSL certificates from Let's Encrypt for HTTPS connections.

### Stripe
A payment processing platform. CHOM integrates with Stripe for subscription billing, invoicing, and payment collection using Laravel Cashier.
- Documentation: https://stripe.com/docs

### systemd
The init system for Linux that manages services, logging, and system resources. All observability components run as systemd services for reliability and automatic restarts.

### systemd Credentials
A systemd feature for encrypting and isolating service credentials using TPM2 hardware security. Supported in Debian 13+ for enhanced secret security.

---

## T

### Tailwind CSS
A utility-first CSS framework for rapidly building custom user interfaces. CHOM uses Tailwind CSS 4 for responsive, modern design.
- Documentation: https://tailwindcss.com/

### Tempo
A distributed tracing backend from Grafana. Stores and queries traces to understand request flows through microservices and applications.
- Ports: 4317 (OTLP gRPC), 4318 (OTLP HTTP)
- Documentation: https://grafana.com/docs/tempo/latest/

### Time Series Database (TSDB)
A database optimized for time-stamped data. Prometheus uses a custom TSDB for efficient storage and querying of metrics over time.

### TPM2 (Trusted Platform Module 2.0)
A hardware security chip for storing encryption keys. systemd credentials can use TPM2 for hardware-backed secret encryption on supported systems.

---

## U

### UFW (Uncomplicated Firewall)
A user-friendly interface for managing iptables firewall rules. Used in the observability stack to restrict network access to monitoring ports.

### Uptime Monitoring
Tracking service availability over time. Blackbox Exporter provides uptime monitoring via HTTP probes, SSL checks, and synthetic transactions.

---

## V

### Vite
A modern frontend build tool with fast hot module replacement. CHOM uses Vite 7 for building and bundling JavaScript and CSS assets.
- Documentation: https://vitejs.dev/

### VPS (Virtual Private Server)
A virtual machine sold as a service by hosting providers. CHOM manages fleets of VPS servers from providers like DigitalOcean, Linode, and Vultr.

### VPSManager
A role in the deployment system that sets up a VPS with a complete LEMP stack, CHOM application, and observability exporters for managing WordPress sites.

---

## W

### WAL (Write-Ahead Log)
A logging mechanism where changes are written to a log before being applied to the database. Prometheus uses WAL for crash recovery and data durability.

### Webhook
An HTTP callback that delivers real-time data to other applications. CHOM receives Stripe webhooks for subscription events and sends webhooks for custom integrations.

### WordPress
A popular content management system. CHOM automates WordPress site deployment with one-click provisioning, SSL certificates, and automated backups.

---

## Y

### YAML (YAML Ain't Markup Language)
A human-readable data serialization format used for configuration files. The observability stack uses YAML for global configuration, module definitions, and alert rules.

---

## Additional Resources

- **Observability Stack Documentation**: `/home/calounx/repositories/mentat/observability-stack/README.md`
- **CHOM Documentation**: `/home/calounx/repositories/mentat/chom/README.md`
- **Security Guide**: `/home/calounx/repositories/mentat/SECURITY.md`
- **Contributing Guide**: `/home/calounx/repositories/mentat/CONTRIBUTING.md`
- **Secrets Management**: `/home/calounx/repositories/mentat/observability-stack/docs/SECRETS.md`
- **Upgrade Documentation**: `/home/calounx/repositories/mentat/observability-stack/docs/upgrade/`

---

**Last Updated**: 2025-12-28
**Version**: 1.0.0
