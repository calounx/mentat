/**
 * k6 Scenario: Spike Test
 *
 * Sudden traffic spike from 100 to 200 users to:
 * - Test system resilience under sudden load
 * - Validate auto-scaling response time
 * - Detect rate limiting effectiveness
 * - Monitor recovery after spike
 *
 * Traffic Pattern: 100 → 200 (spike) → 100
 * Duration: 5 minutes
 * Target: System remains stable during and after spike
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
    spike_test: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: 100 },   // Establish baseline
        { duration: '30s', target: 200 },  // Sudden spike to 200 users
        { duration: '3m', target: 200 },   // Maintain spike
        { duration: '30s', target: 100 },  // Return to baseline
        { duration: '1m', target: 100 },   // Monitor recovery
        { duration: '30s', target: 0 },    // Ramp down
      ],
    },
  },
  thresholds: {
    // Allow slightly higher latency during spike
    'http_req_duration': ['p(95) < 800', 'p(99) < 1500'],
    'http_req_failed': ['rate < 0.005'], // Allow 0.5% errors during spike
    'http_reqs': ['rate > 80'], // Expect higher throughput during spike
    'checks': ['rate > 0.995'], // 99.5% success rate minimum
  },
  tags: {
    test: 'spike-test',
    scenario: 'resilience-validation',
  },
};

export function setup() {
  console.log('='.repeat(80));
  console.log('SPIKE TEST - Resilience Under Sudden Load');
  console.log('='.repeat(80));
  console.log('Pattern: 100 → 200 → 100 users (sudden spike)');
  console.log('Duration: 6.5 minutes');
  console.log('Objective: Validate system stability during traffic spikes');
  console.log('='.repeat(80));

  return { startTime: new Date().toISOString() };
}

export default function () {
  // Aggressive user behavior during spike (shorter think times)
  const user = generateTestUser();
  let token = null;

  // Quick authentication
  group('Fast Auth', () => {
    const registerResponse = http.post(
      getApiUrl('/auth/register'),
      JSON.stringify(user),
      { headers: getHeaders() }
    );

    if (checkResponse(registerResponse, 201, 'Register')) {
      token = extractToken(registerResponse);
    } else {
      // During spike, might hit rate limits
      console.warn('Registration failed, possibly rate limited');
      return;
    }

    sleep(0.5); // Shorter think time during spike
  });

  if (!token) return;

  // Rapid site creation
  group('Rapid Site Creation', () => {
    const siteConfig = generateSiteConfig();

    const createResponse = http.post(
      getApiUrl('/sites'),
      JSON.stringify(siteConfig),
      { headers: getHeaders(token) }
    );

    checkResponse(createResponse, 201, 'Create Site');

    sleep(0.5);
  });

  // Frequent listing (cache test)
  group('Frequent Listing', () => {
    for (let i = 0; i < 3; i++) {
      const listResponse = http.get(
        getApiUrl('/sites'),
        { headers: getHeaders(token) }
      );

      checkResponse(listResponse, 200, 'List Sites');

      sleep(0.3);
    }
  });

  // Test multiple concurrent requests
  group('Concurrent Requests', () => {
    const requests = [
      {
        method: 'GET',
        url: getApiUrl('/sites'),
        params: { headers: getHeaders(token) },
      },
      {
        method: 'GET',
        url: getApiUrl('/auth/me'),
        params: { headers: getHeaders(token) },
      },
      {
        method: 'GET',
        url: getApiUrl('/backups'),
        params: { headers: getHeaders(token) },
      },
    ];

    const responses = http.batch(requests);

    responses.forEach((response, index) => {
      check(response, {
        [`Concurrent ${index + 1}: successful`]: (r) => r.status === 200,
      });
    });

    sleep(1);
  });

  // Logout
  group('Quick Logout', () => {
    http.post(
      getApiUrl('/auth/logout'),
      null,
      { headers: getHeaders(token) }
    );
  });

  sleep(0.5);
}

export function teardown(data) {
  console.log('='.repeat(80));
  console.log('SPIKE TEST COMPLETED');
  console.log('='.repeat(80));
  console.log(`Started: ${data.startTime}`);
  console.log(`Ended: ${new Date().toISOString()}`);
  console.log('='.repeat(80));
  console.log('');
  console.log('Analysis Points:');
  console.log('1. Response Time During Spike:');
  console.log('   - Did p95/p99 stay within acceptable limits?');
  console.log('   - How quickly did response times recover?');
  console.log('');
  console.log('2. Error Rate:');
  console.log('   - Were there any 5xx errors?');
  console.log('   - Did rate limiting activate appropriately?');
  console.log('   - Were errors gracefully handled?');
  console.log('');
  console.log('3. Auto-Scaling:');
  console.log('   - Did auto-scaling trigger during spike?');
  console.log('   - How long to scale up?');
  console.log('   - Proper scale-down after spike?');
  console.log('');
  console.log('4. Resource Utilization:');
  console.log('   - CPU spikes during load?');
  console.log('   - Memory pressure?');
  console.log('   - Database connection saturation?');
  console.log('='.repeat(80));
}

export function handleSummary(data) {
  return {
    'results/spike-test-results.json': JSON.stringify(data, null, 2),
  };
}
