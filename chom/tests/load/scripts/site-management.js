/**
 * k6 Load Test: Site Management (CRUD Operations)
 *
 * Tests comprehensive site management operations:
 * - Create sites (WordPress, Laravel, Static)
 * - List sites with pagination
 * - Get site details
 * - Update site configuration
 * - Enable/disable sites
 * - Issue SSL certificates
 * - Delete sites
 *
 * Performance Targets:
 * - p95 response time < 500ms for site operations
 * - Error rate < 0.1%
 * - Support 100+ concurrent site operations
 */

import http from 'k6/http';
import { sleep, check, group } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';
import { getApiUrl, getHeaders } from '../k6.config.js';
import {
  generateTestUser,
  generateSiteConfig,
  extractToken,
  extractId,
  checkResponse,
  userThinkTime,
  customMetrics,
  parseJsonResponse,
} from '../utils/helpers.js';

// Custom metrics for site management
const siteMetrics = {
  createDuration: new Trend('site_create_duration'),
  listDuration: new Trend('site_list_duration'),
  showDuration: new Trend('site_show_duration'),
  updateDuration: new Trend('site_update_duration'),
  deleteDuration: new Trend('site_delete_duration'),
  sslDuration: new Trend('site_ssl_duration'),
  totalSitesCreated: new Counter('sites_created_total'),
  totalSitesDeleted: new Counter('sites_deleted_total'),
  siteOperationErrors: new Counter('site_operation_errors'),
};

// Test configuration
export const options = {
  stages: [
    { duration: '1m', target: 20 },   // Warm-up
    { duration: '3m', target: 50 },   // Ramp up
    { duration: '5m', target: 100 },  // Peak load
    { duration: '3m', target: 100 },  // Sustained load
    { duration: '2m', target: 50 },   // Ramp down
    { duration: '1m', target: 0 },    // Cool down
  ],
  thresholds: {
    'http_req_duration{endpoint:sites}': ['p(95) < 500', 'p(99) < 1000'],
    'http_req_failed{endpoint:sites}': ['rate < 0.001'],
    'site_create_duration': ['p(95) < 600'],
    'site_list_duration': ['p(95) < 300'],
    'site_show_duration': ['p(95) < 250'],
    'checks': ['rate > 0.999'],
  },
  tags: {
    test: 'site-management',
    endpoint: 'sites',
  },
};

/**
 * Setup - authenticate user
 */
export function setup() {
  console.log('='.repeat(60));
  console.log('Starting Site Management Load Test');
  console.log('='.repeat(60));

  // Create test user and authenticate
  const user = generateTestUser();

  const registerResponse = http.post(
    getApiUrl('/auth/register'),
    JSON.stringify(user),
    { headers: getHeaders() }
  );

  if (registerResponse.status !== 201) {
    throw new Error(`Failed to create test user: ${registerResponse.status}`);
  }

  const token = extractToken(registerResponse);

  if (!token) {
    throw new Error('Failed to extract auth token');
  }

  console.log('Test user authenticated successfully');
  console.log('='.repeat(60));

  return { token, user };
}

/**
 * Main test scenario
 */
export default function (data) {
  const { token } = data;
  const createdSites = [];

  // Test: Create WordPress site
  group('Create WordPress Site', () => {
    const siteConfig = generateSiteConfig();
    siteConfig.type = 'wordpress'; // Force WordPress type

    const startTime = Date.now();

    const createResponse = http.post(
      getApiUrl('/sites'),
      JSON.stringify(siteConfig),
      {
        headers: getHeaders(token),
        tags: { endpoint: 'sites', operation: 'create', site_type: 'wordpress' },
      }
    );

    siteMetrics.createDuration.add(Date.now() - startTime);

    const isSuccess = checkResponse(createResponse, 201, 'Create WordPress Site', {
      endpoint: 'sites',
      operation: 'create',
    });

    if (isSuccess) {
      const siteId = extractId(createResponse);

      if (siteId) {
        createdSites.push(siteId);
        siteMetrics.totalSitesCreated.add(1);

        check(createResponse, {
          'WordPress Site: has domain': (r) => {
            const data = parseJsonResponse(r);
            return data && (data.domain || data.data?.domain);
          },
          'WordPress Site: has type': (r) => {
            const data = parseJsonResponse(r);
            return data && (data.type === 'wordpress' || data.data?.type === 'wordpress');
          },
        });
      }
    } else {
      siteMetrics.siteOperationErrors.add(1);
    }

    userThinkTime(2, 4);
  });

  // Test: Create Laravel site
  group('Create Laravel Site', () => {
    const siteConfig = generateSiteConfig();
    siteConfig.type = 'laravel';

    const startTime = Date.now();

    const createResponse = http.post(
      getApiUrl('/sites'),
      JSON.stringify(siteConfig),
      {
        headers: getHeaders(token),
        tags: { endpoint: 'sites', operation: 'create', site_type: 'laravel' },
      }
    );

    siteMetrics.createDuration.add(Date.now() - startTime);

    if (checkResponse(createResponse, 201, 'Create Laravel Site')) {
      const siteId = extractId(createResponse);
      if (siteId) {
        createdSites.push(siteId);
        siteMetrics.totalSitesCreated.add(1);
      }
    } else {
      siteMetrics.siteOperationErrors.add(1);
    }

    userThinkTime(2, 4);
  });

  // Test: List all sites
  group('List Sites', () => {
    const startTime = Date.now();

    const listResponse = http.get(
      getApiUrl('/sites'),
      {
        headers: getHeaders(token),
        tags: { endpoint: 'sites', operation: 'list' },
      }
    );

    siteMetrics.listDuration.add(Date.now() - startTime);

    checkResponse(listResponse, 200, 'List Sites', {
      endpoint: 'sites',
      operation: 'list',
    });

    check(listResponse, {
      'List Sites: has data array': (r) => {
        const data = parseJsonResponse(r);
        return data && (Array.isArray(data.data) || Array.isArray(data));
      },
    });

    userThinkTime(1, 3);
  });

  // Test: Get site details for each created site
  if (createdSites.length > 0) {
    group('Get Site Details', () => {
      createdSites.forEach((siteId, index) => {
        const startTime = Date.now();

        const showResponse = http.get(
          getApiUrl(`/sites/${siteId}`),
          {
            headers: getHeaders(token),
            tags: { endpoint: 'sites', operation: 'show' },
          }
        );

        siteMetrics.showDuration.add(Date.now() - startTime);

        checkResponse(showResponse, 200, `Get Site Details (${index + 1})`, {
          endpoint: 'sites',
          operation: 'show',
        });

        if (index < createdSites.length - 1) {
          userThinkTime(1, 2);
        }
      });
    });
  }

  // Test: Update site configuration
  if (createdSites.length > 0) {
    group('Update Site', () => {
      const siteId = createdSites[0];

      const updateData = {
        php_version: '8.4',
      };

      const startTime = Date.now();

      const updateResponse = http.patch(
        getApiUrl(`/sites/${siteId}`),
        JSON.stringify(updateData),
        {
          headers: getHeaders(token),
          tags: { endpoint: 'sites', operation: 'update' },
        }
      );

      siteMetrics.updateDuration.add(Date.now() - startTime);

      checkResponse(updateResponse, 200, 'Update Site', {
        endpoint: 'sites',
        operation: 'update',
      });

      userThinkTime(2, 4);
    });
  }

  // Test: Enable/Disable site
  if (createdSites.length > 0) {
    group('Enable/Disable Site', () => {
      const siteId = createdSites[0];

      // Disable site
      const disableResponse = http.post(
        getApiUrl(`/sites/${siteId}/disable`),
        null,
        {
          headers: getHeaders(token),
          tags: { endpoint: 'sites', operation: 'disable' },
        }
      );

      checkResponse(disableResponse, 200, 'Disable Site');

      userThinkTime(1, 2);

      // Enable site
      const enableResponse = http.post(
        getApiUrl(`/sites/${siteId}/enable`),
        null,
        {
          headers: getHeaders(token),
          tags: { endpoint: 'sites', operation: 'enable' },
        }
      );

      checkResponse(enableResponse, 200, 'Enable Site');

      userThinkTime(2, 3);
    });
  }

  // Test: Issue SSL certificate
  if (createdSites.length > 0) {
    group('Issue SSL Certificate', () => {
      const siteId = createdSites[0];

      const startTime = Date.now();

      const sslResponse = http.post(
        getApiUrl(`/sites/${siteId}/ssl`),
        null,
        {
          headers: getHeaders(token),
          tags: { endpoint: 'sites', operation: 'ssl' },
        }
      );

      siteMetrics.sslDuration.add(Date.now() - startTime);

      // SSL issuance might take longer or be async, accept 200 or 202
      const isSuccess = check(sslResponse, {
        'SSL: status is 200 or 202': (r) => r.status === 200 || r.status === 202,
      });

      if (!isSuccess) {
        siteMetrics.siteOperationErrors.add(1);
      }

      userThinkTime(2, 4);
    });
  }

  // Test: Delete sites (cleanup)
  group('Delete Sites', () => {
    createdSites.forEach((siteId, index) => {
      const startTime = Date.now();

      const deleteResponse = http.del(
        getApiUrl(`/sites/${siteId}`),
        null,
        {
          headers: getHeaders(token),
          tags: { endpoint: 'sites', operation: 'delete' },
        }
      );

      siteMetrics.deleteDuration.add(Date.now() - startTime);

      // Accept 200, 202 (accepted), or 204 (no content)
      const isSuccess = check(deleteResponse, {
        'Delete: status is 200, 202, or 204': (r) =>
          r.status === 200 || r.status === 202 || r.status === 204,
      });

      if (isSuccess) {
        siteMetrics.totalSitesDeleted.add(1);
      } else {
        siteMetrics.siteOperationErrors.add(1);
      }

      if (index < createdSites.length - 1) {
        sleep(1);
      }
    });
  });

  // Simulate end of user session
  sleep(1);
}

/**
 * Teardown function
 */
export function teardown(data) {
  console.log('='.repeat(60));
  console.log('Site Management Load Test Complete');
  console.log('='.repeat(60));
}

/**
 * Handle test summary
 */
export function handleSummary(data) {
  return {
    'results/site-management-summary.json': JSON.stringify(data, null, 2),
  };
}
