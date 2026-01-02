/**
 * k6 Load Testing Configuration for CHOM
 *
 * This configuration file defines performance baselines, thresholds, and
 * shared settings for all k6 load tests.
 *
 * Performance Targets (Phase 3 - 99% Confidence):
 * - Response Time: p95 < 500ms, p99 < 1000ms
 * - Throughput: > 100 req/s
 * - Error Rate: < 0.1%
 * - Concurrent Users: 100+
 */

export const config = {
  // Base URL configuration
  baseURL: __ENV.BASE_URL || 'http://localhost:8000',
  apiVersion: 'v1',

  // Performance thresholds (enforced across all tests)
  thresholds: {
    // HTTP request duration
    http_req_duration: [
      'p(95) < 500',    // 95% of requests must complete below 500ms
      'p(99) < 1000',   // 99% of requests must complete below 1000ms
      'p(50) < 200',    // 50% of requests must complete below 200ms (median)
    ],

    // HTTP request failure rate
    http_req_failed: [
      'rate < 0.001',   // Error rate must be below 0.1%
    ],

    // Request rate (throughput)
    http_reqs: [
      'rate > 100',     // Must handle more than 100 requests per second
    ],

    // Specific endpoint thresholds
    'http_req_duration{endpoint:auth}': ['p(95) < 300'],
    'http_req_duration{endpoint:sites}': ['p(95) < 500'],
    'http_req_duration{endpoint:backups}': ['p(95) < 800'],

    // Check success rates
    checks: [
      'rate > 0.999',   // 99.9% of checks must pass
    ],
  },

  // Test data configuration
  testData: {
    // User pool size for realistic testing
    userPoolSize: 1000,

    // Number of sites per user
    sitesPerUser: 5,

    // Backup retention for testing
    backupsPerSite: 10,

    // Think time ranges (in seconds)
    thinkTime: {
      min: 1,
      max: 5,
    },
  },

  // Rate limiting configuration (matches CHOM API)
  rateLimits: {
    auth: 5,          // 5 requests per minute
    api: 60,          // 60 requests per minute
    sensitive: 10,    // 10 requests per minute
    twoFactor: 5,     // 5 requests per minute
  },

  // Scenario configurations
  scenarios: {
    // Warm-up scenario
    warmup: {
      executor: 'constant-vus',
      vus: 10,
      duration: '2m',
    },

    // Ramp-up test: 10 → 50 → 100 users over 15 minutes
    rampUp: {
      executor: 'ramping-vus',
      startVUs: 10,
      stages: [
        { duration: '5m', target: 50 },   // Ramp to 50 users
        { duration: '5m', target: 100 },  // Ramp to 100 users
        { duration: '5m', target: 100 },  // Hold at 100 users
      ],
      gracefulRampDown: '1m',
    },

    // Sustained load: 100 users for 10 minutes
    sustained: {
      executor: 'constant-vus',
      vus: 100,
      duration: '10m',
    },

    // Spike test: 100 → 200 users for 5 minutes
    spike: {
      executor: 'ramping-vus',
      startVUs: 100,
      stages: [
        { duration: '1m', target: 100 },   // Baseline
        { duration: '30s', target: 200 },  // Spike to 200
        { duration: '3m', target: 200 },   // Hold spike
        { duration: '30s', target: 100 },  // Return to baseline
      ],
      gracefulRampDown: '1m',
    },

    // Soak test: 50 users for 1 hour
    soak: {
      executor: 'constant-vus',
      vus: 50,
      duration: '60m',
    },

    // Stress test: Find breaking point
    stress: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 50 },
        { duration: '2m', target: 100 },
        { duration: '2m', target: 200 },
        { duration: '2m', target: 300 },
        { duration: '2m', target: 400 },
        { duration: '2m', target: 500 },
        { duration: '5m', target: 500 },  // Hold at max
        { duration: '2m', target: 0 },    // Ramp down
      ],
      gracefulRampDown: '1m',
    },
  },

  // Output configuration
  output: {
    influxdb: __ENV.K6_INFLUXDB_URL || null,
    json: __ENV.K6_JSON_OUTPUT || 'results/results.json',
    csv: __ENV.K6_CSV_OUTPUT || 'results/results.csv',
  },

  // Tags for grouping metrics
  tags: {
    project: 'chom',
    environment: __ENV.APP_ENV || 'test',
    version: __ENV.APP_VERSION || '1.0.0',
  },
};

/**
 * Get API URL for endpoint
 */
export function getApiUrl(endpoint) {
  return `${config.baseURL}/api/${config.apiVersion}${endpoint}`;
}

/**
 * Get common HTTP headers
 */
export function getHeaders(token = null) {
  const headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'X-Load-Test': 'k6',
  };

  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  return headers;
}

/**
 * Random sleep with think time
 */
export function thinkTime() {
  const { min, max } = config.testData.thinkTime;
  return Math.random() * (max - min) + min;
}

export default config;
