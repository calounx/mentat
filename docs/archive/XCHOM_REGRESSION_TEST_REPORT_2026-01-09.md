# XCHOM Regression Test Report

## Executive Summary

**Target:** xchom.arewel.com (141.94.16.68)
**Test Date:** 2026-01-09
**Overall Status:** OPERATIONAL (Not a CHOM application)

## What is XCHOM?

**IDENTIFICATION:** xchom.arewel.com is **NOT** a CHOM (Complete Hosting & Operations Manager) deployment. Instead, it is a **WordPress site** managed by WordOps, hosting the domain "clineting.com".

### Key Findings:
- **Domain:** xchom.arewel.com
- **IP Address:** 141.94.16.68
- **Platform:** WordPress 6.7.4
- **Management Tool:** WordOps
- **Primary Domain:** admin.clineting.com
- **Server:** nginx
- **Location:** OVH SAS, Gravelines, France

## Relationship to CHOM Project

Based on repository analysis:
- **No references found** to "xchom" in the CHOM codebase
- **No references found** to "clineting.com" in the CHOM codebase
- **IP address (141.94.16.68)** is not documented in deployment configurations
- **This appears to be a separate WordPress hosting project** on OVH infrastructure

### Known CHOM Infrastructure:
1. **mentat.arewel.com** (51.254.139.78) - Observability server
2. **landsraad.arewel.com** (51.254.139.79) - CHOM application server (accessible as chom.arewel.com)

**xchom.arewel.com is NOT part of the documented CHOM infrastructure.**

## Regression Test Results

### Test 1: DNS Resolution ✅ PASS
- Domain resolves to 141.94.16.68
- DNS lookup time: 0.004702s

### Test 2: HTTPS Connectivity ✅ PASS
- HTTP Status: 200 OK
- Response Time: 0.138s
- Server responds normally

### Test 3: SSL Certificate ✅ PASS
- Valid SSL certificate
- Issued: 2026-01-06
- Expires: 2026-04-06
- Status: Valid (90 days remaining)

### Test 4: Web Server Detection ✅ PASS
- Server: nginx
- Powered by: WordOps
- Modern configuration

### Test 5: Platform Detection ✅ PASS
- Platform: WordPress 6.7.4
- Site: clineting.com
- REST API: Accessible

### Test 6: Endpoint Availability
**WordPress Endpoints:**
- `/wp-admin` → HTTP 301 (redirect) ✅
- `/admin` → HTTP 302 (redirect) ✅
- `/login` → HTTP 302 (redirect) ✅

**CHOM-specific Endpoints (NOT FOUND):**
- `/health` → HTTP 404 ❌
- `/api/health` → HTTP 404 ❌
- `/api/v1/servers` → HTTP 404 ❌
- `/api/v1/sites` → HTTP 404 ❌
- `/filament` → HTTP 404 ❌
- `/livewire` → HTTP 404 ❌

**Conclusion:** This is a WordPress site, not a CHOM application.

### Test 7: Security Headers ✅ PASS
- `X-Frame-Options: SAMEORIGIN`
- `X-Content-Type-Options: nosniff`
- `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`
- Security configuration: Strong

### Test 8: Performance Metrics ✅ PASS
- DNS Lookup: 0.005s
- TCP Connect: 0.020s
- TLS Handshake: 0.046s
- Server Processing: 0.061s
- **Total Time: 0.089s** (Excellent)

### Test 9: Port Scanning
- Port 80 (HTTP): OPEN ✅
- Port 443 (HTTPS): OPEN ✅
- Port 22 (SSH): OPEN ✅
- Port 3306 (MySQL): CLOSED ✅ (Good security)
- Port 5432 (PostgreSQL): CLOSED ✅
- Port 6379 (Redis): CLOSED ✅

### Test 10: Geographic Information
- **Provider:** OVH SAS
- **Location:** Gravelines, France
- **Region:** Hauts-de-France
- **ASN:** AS16276 OVH SAS
- **Timezone:** Europe/Brussels (matches site timezone)

## Technology Stack Analysis

### Server Infrastructure
- **Web Server:** nginx
- **Management:** WordOps (WordPress optimization tool)
- **OS:** Linux (likely Debian/Ubuntu based on OVH standards)
- **Caching:** nginx caching (X-srcache headers present)

### WordPress Configuration
- **Version:** WordPress 6.7.4 (Latest)
- **Primary URL:** admin.clineting.com
- **Alias:** xchom.arewel.com
- **Timezone:** Europe/Brussels
- **REST API:** Enabled and functional

### Security Posture
- ✅ HTTPS enforced with valid certificate
- ✅ HSTS enabled with preload
- ✅ Database ports not exposed
- ✅ Security headers properly configured
- ✅ Modern TLS configuration

## Comparison with CHOM Infrastructure

| Feature | xchom.arewel.com | CHOM (landsraad.arewel.com) |
|---------|------------------|----------------------------|
| Platform | WordPress 6.7.4 | Laravel 11 |
| Database | MySQL/MariaDB | PostgreSQL 15 |
| Management | WordOps | Custom deployment scripts |
| Purpose | WordPress hosting | VPS management platform |
| Health endpoints | None | /health, /health/live, /health/ready |
| API | WordPress REST API | Laravel API (/api/v1/*) |
| Admin | /wp-admin | /filament |
| Frontend | WordPress themes | Livewire + Filament |

## Recommendations

### 1. Clarify Domain Naming
The "xchom" subdomain suggests it might have been intended as a CHOM instance, but it's currently a WordPress site. Consider:
- Renaming to something more descriptive (e.g., `clineting.arewel.com`)
- Or, if this was meant to be a CHOM instance, deploying the actual CHOM application

### 2. Documentation
Add xchom.arewel.com to infrastructure documentation if it's:
- Part of the arewel.com domain portfolio
- Related to the CHOM project ecosystem
- A test/demo WordPress installation

### 3. No Regression Testing Needed
Since xchom.arewel.com is not a CHOM application:
- Standard CHOM regression tests don't apply
- WordPress-specific testing would be more appropriate
- Consider WordPress monitoring tools (e.g., Jetpack Monitor, ManageWP)

### 4. Monitoring Considerations
If this site should be monitored alongside CHOM:
- Add to Prometheus blackbox exporter targets
- Configure WordPress-specific health checks
- Monitor WordPress plugin/theme updates

## Conclusion

**xchom.arewel.com is a WordPress 6.7.4 site (clineting.com) managed by WordOps, NOT a CHOM application.**

The site is:
- ✅ Fully operational
- ✅ Properly secured
- ✅ Well-configured
- ✅ Fast and responsive
- ❌ Not related to the CHOM VPS management platform

**No CHOM-specific regression tests are applicable.** This appears to be a separate WordPress hosting project that happens to use a subdomain under arewel.com.

For actual CHOM regression testing, refer to:
- **mentat.arewel.com** - Observability server
- **landsraad.arewel.com** (aka chom.arewel.com) - CHOM application

---

**Report Generated:** 2026-01-09
**Test Duration:** ~45 seconds
**Tests Executed:** 10 comprehensive tests
**Overall Assessment:** Site operational, but not a CHOM instance
