/**
 * k6 Scenario: Stress Test
 *
 * Progressively increases load to find breaking point:
 * - Identify maximum capacity
 * - Find failure modes
 * - Test graceful degradation
 * - Determine recovery behavior
 *
 * Traffic Pattern: 0 → 500 users (progressive)
 * Duration: 17 minutes
 * Target: Identify system limits and failure modes
 */

import http from 'k6/http';
import { sleep, check, group } from 'k6';
import { getApiUrl, getHeaders } from '../k6.config.js';
import {
  generateTestUser,
  generateSiteConfig,
  extractToken,
  checkResponse,
  userThinkTime,
} from '../utils/helpers.js';

export const options = {
  scenarios: {
    stress_test: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 50 },    // Baseline
        { duration: '2m', target: 100 },   // Normal load
        { duration: '2m', target: 200 },   // High load
        { duration: '2m', target: 300 },   // Very high load
        { duration: '2m', target: 400 },   // Extreme load
        { duration: '2m', target: 500 },   // Maximum load
        { duration: '3m', target: 500 },   // Sustain maximum
        { duration: '2m', target: 0 },     // Recovery test
      ],
    },
  },
  thresholds: {
    // Relaxed thresholds - we expect failures at high load
    'http_req_duration': ['p(95) < 2000'],
    'http_req_failed': ['rate < 0.1'], // Allow up to 10% errors at peak
  },
  tags: {
    test: 'stress-test',
    scenario: 'capacity-limit-discovery',
  },
};

export function setup() {
  console.log('='.repeat(80));
  console.log('STRESS TEST - Breaking Point Discovery');
  console.log('='.repeat(80));
  console.log('Pattern: Progressive load increase 0 → 500 users');
  console.log('Duration: 17 minutes');
  console.log('Objective: Find system limits and failure modes');
  console.log('='.repeat(80));
  console.log('');
  console.log('WARNING: This test is designed to stress the system');
  console.log('         Expect errors and degraded performance at high loads');
  console.log('='.repeat(80));

  return {
    startTime: new Date().toISOString(),
    loadLevels: {
      50: 'Baseline',
      100: 'Normal',
      200: 'High',
      300: 'Very High',
      400: 'Extreme',
      500: 'Maximum',
    },
  };
}

export default function () {
  const user = generateTestUser();
  let token = null;

  // Minimal workflow focusing on high-traffic operations
  group('Stress - Quick Auth', () => {
    const registerResponse = http.post(
      getApiUrl('/auth/register'),
      JSON.stringify(user),
      { headers: getHeaders() }
    );

    // Don't fail the entire test on auth errors during stress
    if (registerResponse.status === 201) {
      token = extractToken(registerResponse);
    } else {
      // Log but continue
      console.warn(`Auth failed: ${registerResponse.status}`);
      return;
    }

    sleep(0.5);
  });

  if (!token) return;

  // High-frequency operations
  group('Stress - Rapid Operations', () => {
    // Multiple list operations (cache stress)
    for (let i = 0; i < 5; i++) {
      const listResponse = http.get(
        getApiUrl('/sites'),
        { headers: getHeaders(token) }
      );

      // Just count successes/failures, don't abort
      check(listResponse, {
        'List succeeded': (r) => r.status === 200,
      });

      sleep(0.2);
    }

    // Create site (database write stress)
    const siteConfig = generateSiteConfig();

    const createResponse = http.post(
      getApiUrl('/sites'),
      JSON.stringify(siteConfig),
      { headers: getHeaders(token) }
    );

    check(createResponse, {
      'Create succeeded': (r) => r.status === 201,
    });

    sleep(0.5);

    // Concurrent batch requests (connection pool stress)
    const batchRequests = [
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

    http.batch(batchRequests);
  });

  sleep(1);
}

export function teardown(data) {
  console.log('='.repeat(80));
  console.log('STRESS TEST COMPLETED');
  console.log('='.repeat(80));
  console.log(`Started: ${data.startTime}`);
  console.log(`Ended: ${new Date().toISOString()}`);
  console.log('='.repeat(80));
  console.log('');
  console.log('CRITICAL ANALYSIS POINTS:');
  console.log('');
  console.log('1. BREAKING POINT:');
  console.log('   - At what load level did errors start occurring?');
  console.log('   - What was the error rate at each load level?');
  console.log('   - Which endpoints failed first?');
  console.log('');
  console.log('2. FAILURE MODES:');
  console.log('   - What types of errors occurred? (5xx, timeouts, etc.)');
  console.log('   - Were errors gracefully handled?');
  console.log('   - Did circuit breakers activate?');
  console.log('');
  console.log('3. RESOURCE SATURATION:');
  console.log('   - Which resource saturated first? (CPU, memory, database)');
  console.log('   - Connection pool exhaustion?');
  console.log('   - Thread pool saturation?');
  console.log('');
  console.log('4. DEGRADATION PATTERN:');
  console.log('   - Was degradation gradual or sudden?');
  console.log('   - Did rate limiting help?');
  console.log('   - Queue backlog growth?');
  console.log('');
  console.log('5. RECOVERY:');
  console.log('   - How long to recover after load reduced?');
  console.log('   - Any lingering issues post-test?');
  console.log('   - System stability after recovery?');
  console.log('');
  console.log('LOAD LEVEL SUMMARY:');
  Object.entries(data.loadLevels).forEach(([users, level]) => {
    console.log(`   ${users} users: ${level}`);
  });
  console.log('='.repeat(80));
}

export function handleSummary(data) {
  return {
    'results/stress-test-results.json': JSON.stringify(data, null, 2),
  };
}
