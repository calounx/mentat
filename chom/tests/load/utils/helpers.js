/**
 * k6 Load Testing Helper Utilities for CHOM
 *
 * Common utilities for generating test data, handling responses,
 * and managing test state.
 */

import { sleep, check, group } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';
import { randomString, randomIntBetween, randomItem } from 'k6/experimental/rand';

// Custom metrics
export const customMetrics = {
  authDuration: new Trend('auth_duration', true),
  siteDuration: new Trend('site_duration', true),
  backupDuration: new Trend('backup_duration', true),
  errorRate: new Rate('error_rate'),
  successRate: new Rate('success_rate'),
  apiCalls: new Counter('api_calls_total'),
};

/**
 * Generate random email address
 */
export function generateEmail(prefix = 'loadtest') {
  const timestamp = Date.now();
  const random = randomString(8, 'abcdefghijklmnopqrstuvwxyz0123456789');
  return `${prefix}_${timestamp}_${random}@example.com`;
}

/**
 * Generate random organization name
 */
export function generateOrgName() {
  const prefixes = ['Acme', 'Global', 'Tech', 'Cloud', 'Digital', 'Smart', 'Pro'];
  const suffixes = ['Corp', 'Inc', 'Solutions', 'Systems', 'Labs', 'Group'];
  const prefix = randomItem(prefixes);
  const suffix = randomItem(suffixes);
  return `${prefix} ${suffix} ${randomString(4, '0123456789')}`;
}

/**
 * Generate random domain name
 */
export function generateDomain() {
  const prefix = randomString(8, 'abcdefghijklmnopqrstuvwxyz');
  const tlds = ['com', 'net', 'org', 'io', 'dev'];
  const tld = randomItem(tlds);
  return `${prefix}-loadtest.${tld}`;
}

/**
 * Generate secure password
 */
export function generatePassword(length = 16) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*';
  return randomString(length, chars);
}

/**
 * Generate random site configuration
 */
export function generateSiteConfig() {
  const types = ['wordpress', 'laravel', 'static'];
  const phpVersions = ['8.2', '8.4'];

  return {
    domain: generateDomain(),
    type: randomItem(types),
    php_version: randomItem(phpVersions),
    auto_ssl: true,
  };
}

/**
 * Generate random backup configuration
 */
export function generateBackupConfig() {
  const types = ['full', 'database', 'files'];

  return {
    type: randomItem(types),
    description: `Load test backup - ${new Date().toISOString()}`,
  };
}

/**
 * Check HTTP response with detailed validation
 */
export function checkResponse(response, expectedStatus, checkName, tags = {}) {
  const checks = {};

  // Status check
  checks[`${checkName}: status is ${expectedStatus}`] = response.status === expectedStatus;

  // Response time check
  checks[`${checkName}: response time < 2000ms`] = response.timings.duration < 2000;

  // Valid JSON check (if applicable)
  if (response.headers['Content-Type']?.includes('application/json')) {
    try {
      JSON.parse(response.body);
      checks[`${checkName}: valid JSON response`] = true;
    } catch (e) {
      checks[`${checkName}: valid JSON response`] = false;
    }
  }

  const result = check(response, checks, tags);

  // Update custom metrics
  if (result) {
    customMetrics.successRate.add(1);
  } else {
    customMetrics.errorRate.add(1);
  }

  customMetrics.apiCalls.add(1);

  return result;
}

/**
 * Parse JSON response safely
 */
export function parseJsonResponse(response) {
  try {
    return JSON.parse(response.body);
  } catch (e) {
    console.error(`Failed to parse JSON response: ${e.message}`);
    console.error(`Response body: ${response.body}`);
    return null;
  }
}

/**
 * Extract token from response
 */
export function extractToken(response) {
  const data = parseJsonResponse(response);

  if (!data) {
    return null;
  }

  // Try different possible token locations
  return data.token || data.access_token || data.data?.token || data.data?.access_token;
}

/**
 * Extract ID from response
 */
export function extractId(response) {
  const data = parseJsonResponse(response);

  if (!data) {
    return null;
  }

  return data.id || data.data?.id;
}

/**
 * Simulate realistic user think time
 */
export function userThinkTime(min = 1, max = 5) {
  const duration = randomIntBetween(min, max);
  sleep(duration);
}

/**
 * Handle rate limiting with exponential backoff
 */
export function handleRateLimit(response, retries = 3) {
  if (response.status === 429) {
    const retryAfter = parseInt(response.headers['Retry-After'] || '60', 10);

    if (retries > 0) {
      console.log(`Rate limited. Waiting ${retryAfter}s before retry...`);
      sleep(retryAfter);
      return true; // Should retry
    }

    console.error('Rate limit exceeded, no retries left');
    return false;
  }

  return false; // No rate limit
}

/**
 * Generate test user with credentials
 */
export function generateTestUser() {
  return {
    name: generateOrgName(),
    email: generateEmail(),
    password: generatePassword(),
  };
}

/**
 * Log test execution summary
 */
export function logTestSummary(scenario, metrics) {
  console.log('='.repeat(60));
  console.log(`Test Scenario: ${scenario}`);
  console.log('='.repeat(60));
  console.log(`Total API Calls: ${metrics.apiCalls}`);
  console.log(`Success Rate: ${(metrics.successRate * 100).toFixed(2)}%`);
  console.log(`Error Rate: ${(metrics.errorRate * 100).toFixed(2)}%`);
  console.log(`Avg Response Time: ${metrics.avgDuration.toFixed(2)}ms`);
  console.log('='.repeat(60));
}

/**
 * Create pagination parameters
 */
export function getPaginationParams(page = 1, perPage = 20) {
  return {
    page,
    per_page: perPage,
  };
}

/**
 * Build query string from object
 */
export function buildQueryString(params) {
  return Object.entries(params)
    .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`)
    .join('&');
}

/**
 * Measure operation duration
 */
export function measureDuration(fn, metricName) {
  const start = Date.now();
  const result = fn();
  const duration = Date.now() - start;

  if (customMetrics[metricName]) {
    customMetrics[metricName].add(duration);
  }

  return { result, duration };
}

/**
 * Validate response structure
 */
export function validateResponseStructure(response, requiredFields = []) {
  const data = parseJsonResponse(response);

  if (!data) {
    return false;
  }

  const checks = {};
  requiredFields.forEach(field => {
    const fieldPath = field.split('.');
    let value = data;

    for (const part of fieldPath) {
      value = value?.[part];
    }

    checks[`has field: ${field}`] = value !== undefined;
  });

  return check(data, checks);
}

/**
 * Generate random integer within range
 */
export function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

/**
 * Format bytes to human-readable string
 */
export function formatBytes(bytes) {
  const sizes = ['Bytes', 'KB', 'MB', 'GB'];
  if (bytes === 0) return '0 Bytes';
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return `${Math.round(bytes / Math.pow(1024, i) * 100) / 100} ${sizes[i]}`;
}

/**
 * Validate email format
 */
export function isValidEmail(email) {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}

/**
 * Create HTTP headers with auth token
 */
export function createAuthHeaders(token) {
  return {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Authorization': `Bearer ${token}`,
    'X-Load-Test': 'k6',
  };
}

/**
 * Create basic HTTP headers
 */
export function createHeaders() {
  return {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'X-Load-Test': 'k6',
  };
}

export default {
  customMetrics,
  generateEmail,
  generateOrgName,
  generateDomain,
  generatePassword,
  generateSiteConfig,
  generateBackupConfig,
  checkResponse,
  parseJsonResponse,
  extractToken,
  extractId,
  userThinkTime,
  handleRateLimit,
  generateTestUser,
  logTestSummary,
  getPaginationParams,
  buildQueryString,
  measureDuration,
  validateResponseStructure,
  randomInt,
  formatBytes,
  isValidEmail,
  createAuthHeaders,
  createHeaders,
};
