/**
 * k6 Scenario: Ramp-Up Test
 *
 * Gradually increases load from 10 to 100 users over 15 minutes to:
 * - Identify performance degradation points
 * - Monitor resource utilization scaling
 * - Validate auto-scaling triggers
 * - Establish baseline capacity
 *
 * Traffic Pattern: 10 → 50 → 100 users
 * Duration: 15 minutes
 * Target: Validate smooth scaling without errors
 */

import http from 'k6/http';
import { sleep, check, group } from 'k6';
import { getApiUrl, getHeaders } from '../k6.config.js';
import {
  generateTestUser,
  generateSiteConfig,
  extractToken,
  extractId,
  checkResponse,
  userThinkTime,
} from '../utils/helpers.js';

export const options = {
  scenarios: {
    ramp_up_test: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 10 },   // Warm-up to 10 users
        { duration: '3m', target: 10 },   // Sustain 10 users
        { duration: '2m', target: 50 },   // Ramp to 50 users
        { duration: '3m', target: 50 },   // Sustain 50 users
        { duration: '2m', target: 100 },  // Ramp to 100 users
        { duration: '3m', target: 100 },  // Sustain 100 users
      ],
      gracefulRampDown: '2m',
    },
  },
  thresholds: {
    'http_req_duration': ['p(95) < 500', 'p(99) < 1000'],
    'http_req_failed': ['rate < 0.001'],
    'http_reqs': ['rate > 100'],
    'checks': ['rate > 0.999'],
  },
  tags: {
    test: 'ramp-up',
    scenario: 'capacity-validation',
  },
};

export function setup() {
  console.log('='.repeat(80));
  console.log('RAMP-UP TEST - Capacity Validation');
  console.log('='.repeat(80));
  console.log('Pattern: 10 → 50 → 100 concurrent users');
  console.log('Duration: 15 minutes + 2min ramp-down');
  console.log('Objective: Validate scaling capability and identify bottlenecks');
  console.log('='.repeat(80));

  return { startTime: new Date().toISOString() };
}

export default function () {
  // Realistic user workflow mixing different operations
  const user = generateTestUser();
  let token = null;
  let siteId = null;

  // 1. Authentication
  group('Auth Flow', () => {
    const registerResponse = http.post(
      getApiUrl('/auth/register'),
      JSON.stringify(user),
      { headers: getHeaders() }
    );

    if (checkResponse(registerResponse, 201, 'Register')) {
      token = extractToken(registerResponse);
    }

    userThinkTime(1, 3);
  });

  if (!token) {
    console.error('Authentication failed, skipping rest of workflow');
    return;
  }

  // 2. Site Management (70% of users create sites)
  if (Math.random() < 0.7) {
    group('Site Creation', () => {
      const siteConfig = generateSiteConfig();

      const createResponse = http.post(
        getApiUrl('/sites'),
        JSON.stringify(siteConfig),
        { headers: getHeaders(token) }
      );

      if (checkResponse(createResponse, 201, 'Create Site')) {
        siteId = extractId(createResponse);
      }

      userThinkTime(2, 5);
    });
  }

  // 3. Browse Sites (90% of users)
  if (Math.random() < 0.9) {
    group('Browse Sites', () => {
      const listResponse = http.get(
        getApiUrl('/sites'),
        { headers: getHeaders(token) }
      );

      checkResponse(listResponse, 200, 'List Sites');

      userThinkTime(1, 3);
    });
  }

  // 4. View Site Details (60% of users)
  if (siteId && Math.random() < 0.6) {
    group('Site Details', () => {
      const showResponse = http.get(
        getApiUrl(`/sites/${siteId}`),
        { headers: getHeaders(token) }
      );

      checkResponse(showResponse, 200, 'Get Site');

      userThinkTime(2, 4);
    });
  }

  // 5. Create Backup (40% of users)
  if (siteId && Math.random() < 0.4) {
    group('Create Backup', () => {
      const backupConfig = {
        type: 'full',
        description: 'Automated backup during load test',
      };

      const backupResponse = http.post(
        getApiUrl(`/sites/${siteId}/backups`),
        JSON.stringify(backupConfig),
        { headers: getHeaders(token) }
      );

      check(backupResponse, {
        'Backup: status is 201 or 202': (r) => r.status === 201 || r.status === 202,
      });

      userThinkTime(2, 5);
    });
  }

  // 6. View Profile (30% of users)
  if (Math.random() < 0.3) {
    group('View Profile', () => {
      const meResponse = http.get(
        getApiUrl('/auth/me'),
        { headers: getHeaders(token) }
      );

      checkResponse(meResponse, 200, 'Get Profile');

      userThinkTime(1, 2);
    });
  }

  // 7. Logout (50% of users explicitly logout)
  if (Math.random() < 0.5) {
    group('Logout', () => {
      const logoutResponse = http.post(
        getApiUrl('/auth/logout'),
        null,
        { headers: getHeaders(token) }
      );

      checkResponse(logoutResponse, 200, 'Logout');
    });
  }

  sleep(1);
}

export function teardown(data) {
  console.log('='.repeat(80));
  console.log('RAMP-UP TEST COMPLETED');
  console.log(`Started: ${data.startTime}`);
  console.log(`Ended: ${new Date().toISOString()}`);
  console.log('='.repeat(80));
  console.log('');
  console.log('Next Steps:');
  console.log('1. Review metrics for performance degradation patterns');
  console.log('2. Identify resource bottlenecks (CPU, memory, database)');
  console.log('3. Check for error rate increases at scale');
  console.log('4. Validate auto-scaling triggers activated correctly');
  console.log('='.repeat(80));
}

export function handleSummary(data) {
  return {
    'results/ramp-up-test-results.json': JSON.stringify(data, null, 2),
  };
}
