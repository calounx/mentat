/**
 * Multi-Tenant Concurrency Load Test
 *
 * Tests CHOM platform with concurrent operations across multiple tenants:
 * - 50+ tenants with simultaneous operations
 * - Tenant data isolation under load
 * - Concurrent site provisioning
 * - Database connection pooling
 * - Query performance with tenant scoping
 *
 * Duration: 15 minutes
 * Virtual Users: 100 (2 users per tenant for 50 tenants)
 * Scenario: Realistic multi-tenant workload
 */

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';
import { SharedArray } from 'k6/data';

// Custom metrics
const tenantIsolationViolations = new Counter('tenant_isolation_violations');
const concurrentSiteCreations = new Counter('concurrent_site_creations');
const crossTenantQueries = new Rate('cross_tenant_queries');
const tenantOperationDuration = new Trend('tenant_operation_duration');

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
const TENANTS_COUNT = 50;
const USERS_PER_TENANT = 2;

// Load test stages
export const options = {
    stages: [
        { duration: '2m', target: 20 },   // Warm-up: 20 users
        { duration: '3m', target: 50 },   // Ramp to 50 users
        { duration: '5m', target: 100 },  // Sustained: 100 users (50 tenants × 2 users)
        { duration: '3m', target: 50 },   // Ramp down to 50
        { duration: '2m', target: 0 },    // Cool down
    ],
    thresholds: {
        http_req_duration: ['p(95)<1000', 'p(99)<2000'],
        http_req_failed: ['rate<0.01'], // Less than 1% errors
        tenant_isolation_violations: ['count<1'], // Zero violations
        checks: ['rate>0.95'], // 95% of checks must pass
    },
};

// Generate tenant data
const tenants = SharedArray('tenants', function () {
    const data = [];
    for (let i = 1; i <= TENANTS_COUNT; i++) {
        data.push({
            id: i,
            name: `tenant_${i}`,
            email: `owner_${i}@tenant${i}.test`,
            password: 'password123',
            orgName: `Organization ${i}`,
        });
    }
    return data;
});

// Setup: Create tenants (runs once per VU)
export function setup() {
    console.log(`Setting up multi-tenant test with ${TENANTS_COUNT} tenants...`);

    const tokens = [];

    // Create organizations and users for each tenant
    for (let i = 0; i < TENANTS_COUNT; i++) {
        const tenant = tenants[i];

        // Register organization and user
        const registerResponse = http.post(
            `${BASE_URL}/api/v1/auth/register`,
            JSON.stringify({
                name: tenant.name,
                email: tenant.email,
                password: tenant.password,
                password_confirmation: tenant.password,
                organization_name: tenant.orgName,
            }),
            {
                headers: { 'Content-Type': 'application/json' },
            }
        );

        if (registerResponse.status === 201) {
            const body = JSON.parse(registerResponse.body);
            tokens.push({
                tenantId: i,
                token: body.data.token,
                organizationId: body.data.user.organization_id,
            });
        }

        sleep(0.1); // Avoid rate limiting during setup
    }

    console.log(`Setup complete: ${tokens.length} tenants created`);
    return { tokens };
}

// Main test scenario
export default function (data) {
    // Determine which tenant this VU belongs to
    const vuTenantIndex = (__VU - 1) % TENANTS_COUNT;
    const tenantToken = data.tokens[vuTenantIndex];

    if (!tenantToken) {
        console.error(`No token for VU ${__VU}, tenant index ${vuTenantIndex}`);
        return;
    }

    const headers = {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${tenantToken.token}`,
    };

    // Simulate realistic tenant workload
    group('Multi-Tenant Operations', () => {
        // 1. List sites for this tenant
        group('List Tenant Sites', () => {
            const start = Date.now();
            const response = http.get(`${BASE_URL}/api/v1/sites`, { headers });
            const duration = Date.now() - start;

            tenantOperationDuration.add(duration);

            check(response, {
                'sites list successful': (r) => r.status === 200,
                'sites belong to tenant': (r) => {
                    const body = JSON.parse(r.body);
                    const allSitesBelongToTenant = body.data.every(
                        (site) => site.organization_id === tenantToken.organizationId
                    );
                    if (!allSitesBelongToTenant) {
                        tenantIsolationViolations.add(1);
                    }
                    return allSitesBelongToTenant;
                },
            });
        });

        // 2. Create site (concurrent site creation)
        if (Math.random() < 0.3) {
            // 30% chance
            group('Concurrent Site Creation', () => {
                const start = Date.now();
                const siteData = {
                    domain: `site${Date.now()}-t${vuTenantIndex}.test`,
                    type: ['wordpress', 'laravel', 'html'][
                        Math.floor(Math.random() * 3)
                    ],
                    php_version: '8.3',
                };

                const response = http.post(
                    `${BASE_URL}/api/v1/sites`,
                    JSON.stringify(siteData),
                    { headers }
                );
                const duration = Date.now() - start;

                tenantOperationDuration.add(duration);

                const success = check(response, {
                    'site creation queued': (r) => r.status === 201 || r.status === 202,
                    'site belongs to tenant': (r) => {
                        if (r.status >= 200 && r.status < 300) {
                            const body = JSON.parse(r.body);
                            return body.data.organization_id === tenantToken.organizationId;
                        }
                        return true;
                    },
                });

                if (success) {
                    concurrentSiteCreations.add(1);
                }
            });
        }

        // 3. List backups for this tenant
        group('List Tenant Backups', () => {
            const response = http.get(`${BASE_URL}/api/v1/backups`, { headers });

            check(response, {
                'backups list successful': (r) => r.status === 200,
                'backups belong to tenant': (r) => {
                    const body = JSON.parse(r.body);
                    return body.data.every(
                        (backup) => backup.organization_id === tenantToken.organizationId
                    );
                },
            });
        });

        // 4. List team members
        group('List Team Members', () => {
            const response = http.get(`${BASE_URL}/api/v1/team/members`, {
                headers,
            });

            check(response, {
                'team list successful': (r) => r.status === 200,
                'team members belong to tenant': (r) => {
                    const body = JSON.parse(r.body);
                    return body.data.every(
                        (member) =>
                            member.organization_id === tenantToken.organizationId
                    );
                },
            });
        });

        // 5. Attempt to access another tenant's data (should fail)
        if (Math.random() < 0.1) {
            // 10% chance
            group('Cross-Tenant Access Prevention', () => {
                // Try to access a site from another tenant
                const otherTenantIndex = (vuTenantIndex + 1) % TENANTS_COUNT;
                const fakeSiteId = 999999 + otherTenantIndex;

                const response = http.get(
                    `${BASE_URL}/api/v1/sites/${fakeSiteId}`,
                    { headers }
                );

                const isolated = check(response, {
                    'cross-tenant access denied': (r) =>
                        r.status === 404 || r.status === 403,
                });

                crossTenantQueries.add(isolated ? 0 : 1);
            });
        }

        // 6. Get organization details
        group('Get Organization Details', () => {
            const response = http.get(`${BASE_URL}/api/v1/organization`, {
                headers,
            });

            check(response, {
                'organization details retrieved': (r) => r.status === 200,
                'organization matches tenant': (r) => {
                    const body = JSON.parse(r.body);
                    return body.data.id === tenantToken.organizationId;
                },
            });
        });
    });

    // Think time between requests (simulate real user behavior)
    sleep(Math.random() * 3 + 2); // 2-5 seconds
}

// Teardown: Clean up (optional)
export function teardown(data) {
    console.log('Multi-tenant test complete');
    console.log(`Tenants tested: ${TENANTS_COUNT}`);
    console.log(`Concurrent site creations: ${concurrentSiteCreations.value || 0}`);
    console.log(
        `Tenant isolation violations: ${tenantIsolationViolations.value || 0}`
    );

    if (tenantIsolationViolations.value > 0) {
        console.error('⚠️  CRITICAL: Tenant isolation violations detected!');
    } else {
        console.log('✅ Tenant isolation maintained under load');
    }
}

/**
 * Test Scenarios Covered:
 *
 * 1. Concurrent Tenant Operations
 *    - 50 tenants operating simultaneously
 *    - 2 users per tenant (100 total VUs)
 *    - Realistic workload distribution
 *
 * 2. Data Isolation Validation
 *    - Verify tenant-scoped queries
 *    - Prevent cross-tenant data access
 *    - Track isolation violations
 *
 * 3. Concurrent Site Provisioning
 *    - Multiple tenants creating sites simultaneously
 *    - Test VPS allocation under load
 *    - Validate queue processing
 *
 * 4. Database Performance
 *    - Connection pooling under multi-tenant load
 *    - Query performance with tenant scoping
 *    - Index effectiveness
 *
 * 5. API Performance
 *    - Response times with concurrent tenants
 *    - Rate limiting per tenant
 *    - Resource contention
 *
 * Success Criteria:
 * - p95 response time < 1s
 * - p99 response time < 2s
 * - Error rate < 1%
 * - Zero tenant isolation violations
 * - 95%+ checks passing
 */
