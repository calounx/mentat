/**
 * k6 Scenario: Sustained Load Test
 *
 * Maintains constant load of 100 users for 10 minutes to:
 * - Validate steady-state performance
 * - Monitor resource stability
 * - Detect memory leaks
 * - Verify consistent response times
 *
 * Traffic Pattern: 100 users (constant)
 * Duration: 10 minutes
 * Target: Stable performance with no degradation
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
  parseJsonResponse,
} from '../utils/helpers.js';

export const options = {
  scenarios: {
    sustained_load: {
      executor: 'constant-vus',
      vus: 100,
      duration: '10m',
    },
  },
  thresholds: {
    'http_req_duration': ['p(95) < 500', 'p(99) < 1000', 'avg < 300'],
    'http_req_failed': ['rate < 0.001'],
    'http_reqs': ['rate > 100'],
    'checks': ['rate > 0.999'],
    // Monitor for performance degradation over time
    'http_req_duration{percentile:95}': ['p(95) < 500'],
  },
  tags: {
    test: 'sustained-load',
    scenario: 'steady-state-validation',
  },
};

export function setup() {
  console.log('='.repeat(80));
  console.log('SUSTAINED LOAD TEST - Steady State Performance');
  console.log('='.repeat(80));
  console.log('Pattern: 100 concurrent users (constant)');
  console.log('Duration: 10 minutes');
  console.log('Objective: Validate stable performance and detect resource leaks');
  console.log('='.repeat(80));

  return {
    startTime: new Date().toISOString(),
    testDuration: 10 * 60, // 10 minutes in seconds
  };
}

export default function () {
  const user = generateTestUser();
  let token = null;
  const createdResources = {
    sites: [],
    backups: [],
  };

  // Full user workflow
  group('Complete User Session', () => {
    // Register
    group('Registration', () => {
      const registerResponse = http.post(
        getApiUrl('/auth/register'),
        JSON.stringify(user),
        { headers: getHeaders() }
      );

      if (checkResponse(registerResponse, 201, 'Register')) {
        token = extractToken(registerResponse);
      }

      userThinkTime(1, 2);
    });

    if (!token) return;

    // Create multiple sites
    group('Site Creation', () => {
      const numSites = Math.floor(Math.random() * 3) + 1; // 1-3 sites

      for (let i = 0; i < numSites; i++) {
        const siteConfig = generateSiteConfig();

        const createResponse = http.post(
          getApiUrl('/sites'),
          JSON.stringify(siteConfig),
          { headers: getHeaders(token) }
        );

        if (checkResponse(createResponse, 201, `Create Site ${i + 1}`)) {
          const siteId = extractId(createResponse);
          if (siteId) {
            createdResources.sites.push(siteId);
          }
        }

        userThinkTime(1, 3);
      }
    });

    // List and view sites
    group('Site Management', () => {
      // List all sites
      const listResponse = http.get(
        getApiUrl('/sites'),
        { headers: getHeaders(token) }
      );

      checkResponse(listResponse, 200, 'List Sites');

      userThinkTime(1, 2);

      // View each created site
      createdResources.sites.forEach((siteId, index) => {
        const showResponse = http.get(
          getApiUrl(`/sites/${siteId}`),
          { headers: getHeaders(token) }
        );

        checkResponse(showResponse, 200, `View Site ${index + 1}`);

        userThinkTime(1, 2);
      });
    });

    // Backup operations
    if (createdResources.sites.length > 0) {
      group('Backup Operations', () => {
        const siteId = createdResources.sites[0];

        // Create backup
        const backupConfig = {
          type: 'full',
          description: 'Sustained load test backup',
        };

        const createBackupResponse = http.post(
          getApiUrl(`/sites/${siteId}/backups`),
          JSON.stringify(backupConfig),
          { headers: getHeaders(token) }
        );

        const backupCreated = check(createBackupResponse, {
          'Create Backup: status is 201 or 202': (r) => r.status === 201 || r.status === 202,
        });

        if (backupCreated) {
          const backupId = extractId(createBackupResponse);
          if (backupId) {
            createdResources.backups.push(backupId);
          }
        }

        userThinkTime(2, 4);

        // List backups
        const listBackupsResponse = http.get(
          getApiUrl(`/sites/${siteId}/backups`),
          { headers: getHeaders(token) }
        );

        checkResponse(listBackupsResponse, 200, 'List Backups');

        userThinkTime(1, 2);
      });
    }

    // Update site configuration
    if (createdResources.sites.length > 0) {
      group('Site Updates', () => {
        const siteId = createdResources.sites[0];

        const updateData = {
          php_version: '8.4',
        };

        const updateResponse = http.patch(
          getApiUrl(`/sites/${siteId}`),
          JSON.stringify(updateData),
          { headers: getHeaders(token) }
        );

        checkResponse(updateResponse, 200, 'Update Site');

        userThinkTime(1, 3);
      });
    }

    // Profile operations
    group('User Profile', () => {
      const meResponse = http.get(
        getApiUrl('/auth/me'),
        { headers: getHeaders(token) }
      );

      checkResponse(meResponse, 200, 'Get Profile');

      userThinkTime(1, 2);

      // Refresh token
      const refreshResponse = http.post(
        getApiUrl('/auth/refresh'),
        null,
        { headers: getHeaders(token) }
      );

      if (checkResponse(refreshResponse, 200, 'Refresh Token')) {
        const newToken = extractToken(refreshResponse);
        if (newToken) {
          token = newToken;
        }
      }

      userThinkTime(1, 2);
    });

    // Cleanup - delete some resources
    group('Resource Cleanup', () => {
      // Delete backups
      createdResources.backups.forEach((backupId) => {
        http.del(
          getApiUrl(`/backups/${backupId}`),
          null,
          { headers: getHeaders(token) }
        );

        sleep(0.5);
      });

      // Delete sites (50% chance)
      if (Math.random() < 0.5) {
        createdResources.sites.forEach((siteId) => {
          http.del(
            getApiUrl(`/sites/${siteId}`),
            null,
            { headers: getHeaders(token) }
          );

          sleep(0.5);
        });
      }
    });

    // Logout
    group('Logout', () => {
      http.post(
        getApiUrl('/auth/logout'),
        null,
        { headers: getHeaders(token) }
      );
    });
  });

  sleep(1);
}

export function teardown(data) {
  const endTime = new Date();
  const startTime = new Date(data.startTime);
  const durationMinutes = (endTime - startTime) / 1000 / 60;

  console.log('='.repeat(80));
  console.log('SUSTAINED LOAD TEST COMPLETED');
  console.log('='.repeat(80));
  console.log(`Started: ${data.startTime}`);
  console.log(`Ended: ${endTime.toISOString()}`);
  console.log(`Actual Duration: ${durationMinutes.toFixed(2)} minutes`);
  console.log('='.repeat(80));
  console.log('');
  console.log('Analysis Checklist:');
  console.log('[ ] Response times remained stable throughout test');
  console.log('[ ] No memory leaks detected (check server metrics)');
  console.log('[ ] Error rate stayed below 0.1%');
  console.log('[ ] Database connection pool stable');
  console.log('[ ] No performance degradation over time');
  console.log('[ ] Resource utilization within acceptable limits');
  console.log('='.repeat(80));
}

export function handleSummary(data) {
  return {
    'results/sustained-load-test-results.json': JSON.stringify(data, null, 2),
  };
}
