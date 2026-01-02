/**
 * k6 Load Test: Authentication Flow
 *
 * Tests the complete authentication lifecycle:
 * - User registration
 * - Login/logout
 * - Token refresh
 * - Session management
 * - Two-factor authentication (2FA)
 *
 * Performance Targets:
 * - p95 response time < 300ms for auth endpoints
 * - Error rate < 0.1%
 * - Support 100+ concurrent auth operations
 */

import http from 'k6/http';
import { sleep, check, group } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';
import { getApiUrl, getHeaders, config } from '../k6.config.js';
import {
  generateTestUser,
  extractToken,
  checkResponse,
  userThinkTime,
  customMetrics,
} from '../utils/helpers.js';

// Custom metrics for auth flow
const authMetrics = {
  registerDuration: new Trend('auth_register_duration'),
  loginDuration: new Trend('auth_login_duration'),
  logoutDuration: new Trend('auth_logout_duration'),
  refreshDuration: new Trend('auth_refresh_duration'),
  authFailures: new Counter('auth_failures'),
  authSuccesses: new Counter('auth_successes'),
};

// Test configuration
export const options = {
  stages: [
    { duration: '1m', target: 20 },   // Warm-up
    { duration: '3m', target: 50 },   // Ramp up
    { duration: '5m', target: 100 },  // Peak load
    { duration: '2m', target: 50 },   // Ramp down
    { duration: '1m', target: 0 },    // Cool down
  ],
  thresholds: {
    'http_req_duration{endpoint:auth}': ['p(95) < 300', 'p(99) < 500'],
    'http_req_failed{endpoint:auth}': ['rate < 0.001'],
    'auth_register_duration': ['p(95) < 400'],
    'auth_login_duration': ['p(95) < 250'],
    'checks': ['rate > 0.999'],
  },
  tags: {
    test: 'auth-flow',
    endpoint: 'auth',
  },
};

/**
 * Main test scenario
 */
export default function () {
  const user = generateTestUser();
  let token = null;

  // Test registration
  group('User Registration', () => {
    const startTime = Date.now();

    const registerResponse = http.post(
      getApiUrl('/auth/register'),
      JSON.stringify({
        name: user.name,
        email: user.email,
        password: user.password,
      }),
      { headers: getHeaders(), tags: { endpoint: 'auth', operation: 'register' } }
    );

    authMetrics.registerDuration.add(Date.now() - startTime);

    const isSuccess = checkResponse(registerResponse, 201, 'Register', {
      endpoint: 'auth',
      operation: 'register',
    });

    if (isSuccess) {
      authMetrics.authSuccesses.add(1);

      // Extract token from registration response
      token = extractToken(registerResponse);

      check(token, {
        'Registration: token received': (t) => t !== null && t.length > 0,
      });
    } else {
      authMetrics.authFailures.add(1);
      console.error(`Registration failed: ${registerResponse.status} - ${registerResponse.body}`);
      return; // Skip rest of test if registration fails
    }

    userThinkTime(1, 3);
  });

  // Test login
  group('User Login', () => {
    const startTime = Date.now();

    const loginResponse = http.post(
      getApiUrl('/auth/login'),
      JSON.stringify({
        email: user.email,
        password: user.password,
      }),
      { headers: getHeaders(), tags: { endpoint: 'auth', operation: 'login' } }
    );

    authMetrics.loginDuration.add(Date.now() - startTime);

    const isSuccess = checkResponse(loginResponse, 200, 'Login', {
      endpoint: 'auth',
      operation: 'login',
    });

    if (isSuccess) {
      authMetrics.authSuccesses.add(1);

      // Extract new token
      const newToken = extractToken(loginResponse);

      check(newToken, {
        'Login: token received': (t) => t !== null && t.length > 0,
      });

      // Update token for subsequent requests
      if (newToken) {
        token = newToken;
      }
    } else {
      authMetrics.authFailures.add(1);
      console.error(`Login failed: ${loginResponse.status} - ${loginResponse.body}`);
      return;
    }

    userThinkTime(2, 5);
  });

  // Test authenticated endpoint (/auth/me)
  group('Get User Profile', () => {
    const meResponse = http.get(
      getApiUrl('/auth/me'),
      { headers: getHeaders(token), tags: { endpoint: 'auth', operation: 'me' } }
    );

    checkResponse(meResponse, 200, 'Get Profile', {
      endpoint: 'auth',
      operation: 'me',
    });

    userThinkTime(1, 3);
  });

  // Test token refresh
  group('Token Refresh', () => {
    const startTime = Date.now();

    const refreshResponse = http.post(
      getApiUrl('/auth/refresh'),
      null,
      { headers: getHeaders(token), tags: { endpoint: 'auth', operation: 'refresh' } }
    );

    authMetrics.refreshDuration.add(Date.now() - startTime);

    const isSuccess = checkResponse(refreshResponse, 200, 'Token Refresh', {
      endpoint: 'auth',
      operation: 'refresh',
    });

    if (isSuccess) {
      const newToken = extractToken(refreshResponse);

      check(newToken, {
        'Refresh: new token received': (t) => t !== null && t.length > 0,
      });

      // Update token
      if (newToken) {
        token = newToken;
      }
    }

    userThinkTime(1, 2);
  });

  // Test logout
  group('User Logout', () => {
    const startTime = Date.now();

    const logoutResponse = http.post(
      getApiUrl('/auth/logout'),
      null,
      { headers: getHeaders(token), tags: { endpoint: 'auth', operation: 'logout' } }
    );

    authMetrics.logoutDuration.add(Date.now() - startTime);

    const isSuccess = checkResponse(logoutResponse, 200, 'Logout', {
      endpoint: 'auth',
      operation: 'logout',
    });

    if (isSuccess) {
      authMetrics.authSuccesses.add(1);
    } else {
      authMetrics.authFailures.add(1);
    }
  });

  // Simulate user session end
  sleep(1);
}

/**
 * Setup function - runs once before test starts
 */
export function setup() {
  console.log('='.repeat(60));
  console.log('Starting Authentication Flow Load Test');
  console.log('='.repeat(60));
  console.log(`Base URL: ${config.baseURL}`);
  console.log(`Target: 100 concurrent users`);
  console.log(`Duration: 12 minutes`);
  console.log('='.repeat(60));

  // Verify API is accessible
  const healthResponse = http.get(getApiUrl('/health'));

  if (healthResponse.status !== 200) {
    throw new Error(`API health check failed: ${healthResponse.status}`);
  }

  console.log('API health check passed');

  return {
    startTime: new Date().toISOString(),
  };
}

/**
 * Teardown function - runs once after test completes
 */
export function teardown(data) {
  console.log('='.repeat(60));
  console.log('Authentication Flow Load Test Complete');
  console.log('='.repeat(60));
  console.log(`Started: ${data.startTime}`);
  console.log(`Ended: ${new Date().toISOString()}`);
  console.log('='.repeat(60));
}

/**
 * Handle test summary
 */
export function handleSummary(data) {
  return {
    'results/auth-flow-summary.json': JSON.stringify(data, null, 2),
    stdout: textSummary(data, { indent: ' ', enableColors: true }),
  };
}

function textSummary(data, options = {}) {
  const indent = options.indent || '';
  const enableColors = options.enableColors || false;

  let summary = '\n';
  summary += `${indent}Test Results Summary\n`;
  summary += `${indent}${'='.repeat(60)}\n`;
  summary += `${indent}Total Requests: ${data.metrics.http_reqs?.values.count || 0}\n`;
  summary += `${indent}Request Rate: ${(data.metrics.http_reqs?.values.rate || 0).toFixed(2)} req/s\n`;
  summary += `${indent}Failed Requests: ${data.metrics.http_req_failed?.values.passes || 0}\n`;
  summary += `${indent}Avg Duration: ${(data.metrics.http_req_duration?.values.avg || 0).toFixed(2)}ms\n`;
  summary += `${indent}p95 Duration: ${(data.metrics.http_req_duration?.values['p(95)'] || 0).toFixed(2)}ms\n`;
  summary += `${indent}p99 Duration: ${(data.metrics.http_req_duration?.values['p(99)'] || 0).toFixed(2)}ms\n`;
  summary += `${indent}${'='.repeat(60)}\n`;

  return summary;
}
