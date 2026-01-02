/**
 * k6 Scenario: Soak Test (Endurance Test)
 *
 * Maintains moderate load of 50 users for 1 hour to:
 * - Detect memory leaks
 * - Identify resource exhaustion
 * - Monitor database connection pools
 * - Verify log rotation and cleanup
 * - Test long-running session stability
 *
 * Traffic Pattern: 50 users (constant)
 * Duration: 60 minutes
 * Target: No performance degradation or resource leaks
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
    soak_test: {
      executor: 'constant-vus',
      vus: 50,
      duration: '60m',
    },
  },
  thresholds: {
    // Strict thresholds for long-term stability
    'http_req_duration': ['p(95) < 500', 'p(99) < 1000', 'avg < 250'],
    'http_req_failed': ['rate < 0.0005'], // Even stricter: < 0.05%
    'http_reqs': ['rate > 50'],
    'checks': ['rate > 0.9995'], // 99.95% success rate
  },
  tags: {
    test: 'soak-test',
    scenario: 'endurance-validation',
  },
};

export function setup() {
  console.log('='.repeat(80));
  console.log('SOAK TEST - Endurance & Memory Leak Detection');
  console.log('='.repeat(80));
  console.log('Pattern: 50 concurrent users (constant)');
  console.log('Duration: 60 minutes');
  console.log('Objective: Detect memory leaks and resource exhaustion');
  console.log('='.repeat(80));
  console.log('');
  console.log('MONITORING CHECKLIST:');
  console.log('[ ] Memory usage trend (should be stable)');
  console.log('[ ] Database connection pool (no leaks)');
  console.log('[ ] Response times (no degradation)');
  console.log('[ ] Disk usage (log rotation working)');
  console.log('[ ] Cache hit rate (should remain high)');
  console.log('='.repeat(80));

  return {
    startTime: new Date().toISOString(),
    checkpoints: [],
  };
}

// Realistic long-running user session
export default function () {
  const user = generateTestUser();
  let token = null;
  const session = {
    sites: [],
    backups: [],
    iterations: 0,
  };

  // Long-running authenticated session
  group('Long Session - Authentication', () => {
    const registerResponse = http.post(
      getApiUrl('/auth/register'),
      JSON.stringify(user),
      { headers: getHeaders() }
    );

    if (checkResponse(registerResponse, 201, 'Register')) {
      token = extractToken(registerResponse);
    }

    userThinkTime(2, 4);
  });

  if (!token) return;

  // Simulate realistic user activity over time
  const activityCycles = Math.floor(Math.random() * 3) + 2; // 2-4 activity cycles

  for (let cycle = 0; cycle < activityCycles; cycle++) {
    session.iterations++;

    // Site management activities
    group(`Activity Cycle ${cycle + 1} - Site Management`, () => {
      // Create site (occasional)
      if (Math.random() < 0.3 || session.sites.length === 0) {
        const siteConfig = generateSiteConfig();

        const createResponse = http.post(
          getApiUrl('/sites'),
          JSON.stringify(siteConfig),
          { headers: getHeaders(token) }
        );

        if (checkResponse(createResponse, 201, 'Create Site')) {
          const siteId = extractId(createResponse);
          if (siteId) {
            session.sites.push(siteId);
          }
        }

        userThinkTime(3, 6);
      }

      // List sites (frequent)
      const listResponse = http.get(
        getApiUrl('/sites'),
        { headers: getHeaders(token) }
      );

      checkResponse(listResponse, 200, 'List Sites');

      userThinkTime(2, 4);

      // View site details (if sites exist)
      if (session.sites.length > 0) {
        const randomSiteId = session.sites[Math.floor(Math.random() * session.sites.length)];

        const showResponse = http.get(
          getApiUrl(`/sites/${randomSiteId}`),
          { headers: getHeaders(token) }
        );

        checkResponse(showResponse, 200, 'View Site');

        userThinkTime(2, 5);
      }
    });

    // Backup activities
    if (session.sites.length > 0) {
      group(`Activity Cycle ${cycle + 1} - Backup Operations`, () => {
        const siteId = session.sites[Math.floor(Math.random() * session.sites.length)];

        // Create backup (occasional)
        if (Math.random() < 0.4) {
          const backupConfig = {
            type: ['full', 'database', 'files'][Math.floor(Math.random() * 3)],
            description: `Soak test backup - cycle ${cycle + 1}`,
          };

          const createBackupResponse = http.post(
            getApiUrl(`/sites/${siteId}/backups`),
            JSON.stringify(backupConfig),
            { headers: getHeaders(token) }
          );

          const created = check(createBackupResponse, {
            'Create Backup: success': (r) => r.status === 201 || r.status === 202,
          });

          if (created) {
            const backupId = extractId(createBackupResponse);
            if (backupId) {
              session.backups.push({ id: backupId, siteId });
            }
          }

          userThinkTime(4, 8);
        }

        // List backups (frequent)
        const listBackupsResponse = http.get(
          getApiUrl(`/sites/${siteId}/backups`),
          { headers: getHeaders(token) }
        );

        checkResponse(listBackupsResponse, 200, 'List Backups');

        userThinkTime(2, 4);
      });
    }

    // Profile and session management
    group(`Activity Cycle ${cycle + 1} - Session Management`, () => {
      // View profile
      const meResponse = http.get(
        getApiUrl('/auth/me'),
        { headers: getHeaders(token) }
      );

      checkResponse(meResponse, 200, 'Get Profile');

      userThinkTime(2, 3);

      // Refresh token (every few cycles)
      if (cycle % 2 === 0) {
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
      }
    });

    // Cleanup old resources (simulate real usage patterns)
    if (session.backups.length > 5) {
      group(`Activity Cycle ${cycle + 1} - Cleanup`, () => {
        const oldBackup = session.backups.shift();

        http.del(
          getApiUrl(`/backups/${oldBackup.id}`),
          null,
          { headers: getHeaders(token) }
        );

        userThinkTime(1, 2);
      });
    }

    // Longer break between activity cycles
    userThinkTime(5, 10);
  }

  // Final cleanup and logout
  group('Session End - Cleanup', () => {
    // Delete some backups
    session.backups.forEach((backup) => {
      http.del(
        getApiUrl(`/backups/${backup.id}`),
        null,
        { headers: getHeaders(token) }
      );
      sleep(0.5);
    });

    // Optionally delete sites (30% chance)
    if (Math.random() < 0.3) {
      session.sites.forEach((siteId) => {
        http.del(
          getApiUrl(`/sites/${siteId}`),
          null,
          { headers: getHeaders(token) }
        );
        sleep(0.5);
      });
    }

    // Logout
    http.post(
      getApiUrl('/auth/logout'),
      null,
      { headers: getHeaders(token) }
    );
  });

  sleep(2);
}

export function teardown(data) {
  const endTime = new Date();
  const startTime = new Date(data.startTime);
  const durationMinutes = (endTime - startTime) / 1000 / 60;

  console.log('='.repeat(80));
  console.log('SOAK TEST COMPLETED');
  console.log('='.repeat(80));
  console.log(`Started: ${data.startTime}`);
  console.log(`Ended: ${endTime.toISOString()}`);
  console.log(`Total Duration: ${durationMinutes.toFixed(2)} minutes`);
  console.log('='.repeat(80));
  console.log('');
  console.log('POST-TEST ANALYSIS CHECKLIST:');
  console.log('');
  console.log('1. MEMORY ANALYSIS:');
  console.log('   [ ] Plot memory usage over 60 minutes');
  console.log('   [ ] Verify no upward trend (memory leak indicator)');
  console.log('   [ ] Check for sawtooth pattern (healthy GC)');
  console.log('');
  console.log('2. RESPONSE TIME ANALYSIS:');
  console.log('   [ ] Compare p95 at start vs end (should be similar)');
  console.log('   [ ] Plot response time trend (should be flat)');
  console.log('   [ ] Identify any degradation points');
  console.log('');
  console.log('3. RESOURCE UTILIZATION:');
  console.log('   [ ] Database connection pool stable');
  console.log('   [ ] No file descriptor leaks');
  console.log('   [ ] Cache hit rate maintained');
  console.log('   [ ] Queue backlog remained low');
  console.log('');
  console.log('4. ERROR ANALYSIS:');
  console.log('   [ ] Total error count < 0.05%');
  console.log('   [ ] No error rate increase over time');
  console.log('   [ ] Review error logs for patterns');
  console.log('');
  console.log('5. APPLICATION HEALTH:');
  console.log('   [ ] Log rotation working correctly');
  console.log('   [ ] No deadlocks or race conditions');
  console.log('   [ ] Session cleanup functioning');
  console.log('   [ ] Background jobs processing normally');
  console.log('='.repeat(80));
}

export function handleSummary(data) {
  const summary = {
    testInfo: {
      type: 'soak-test',
      duration: '60 minutes',
      vus: 50,
      completedAt: new Date().toISOString(),
    },
    metrics: data.metrics,
  };

  return {
    'results/soak-test-results.json': JSON.stringify(summary, null, 2),
    'results/soak-test-summary.txt': createTextSummary(data),
  };
}

function createTextSummary(data) {
  let text = '\n';
  text += '='.repeat(80) + '\n';
  text += 'SOAK TEST SUMMARY\n';
  text += '='.repeat(80) + '\n\n';

  const metrics = data.metrics;

  text += 'REQUEST STATISTICS:\n';
  text += `  Total Requests: ${metrics.http_reqs?.values.count || 0}\n`;
  text += `  Request Rate: ${(metrics.http_reqs?.values.rate || 0).toFixed(2)} req/s\n`;
  text += `  Failed Requests: ${metrics.http_req_failed?.values.passes || 0}\n`;
  text += `  Error Rate: ${((metrics.http_req_failed?.values.rate || 0) * 100).toFixed(4)}%\n\n`;

  text += 'RESPONSE TIMES:\n';
  text += `  Average: ${(metrics.http_req_duration?.values.avg || 0).toFixed(2)}ms\n`;
  text += `  Median (p50): ${(metrics.http_req_duration?.values.med || 0).toFixed(2)}ms\n`;
  text += `  p95: ${(metrics.http_req_duration?.values['p(95)'] || 0).toFixed(2)}ms\n`;
  text += `  p99: ${(metrics.http_req_duration?.values['p(99)'] || 0).toFixed(2)}ms\n`;
  text += `  Max: ${(metrics.http_req_duration?.values.max || 0).toFixed(2)}ms\n\n`;

  text += 'THRESHOLDS:\n';
  Object.entries(data.root_group.checks || {}).forEach(([name, value]) => {
    const status = value.passes === value.fails ? '✓' : '✗';
    text += `  ${status} ${name}\n`;
  });

  text += '\n' + '='.repeat(80) + '\n';

  return text;
}
