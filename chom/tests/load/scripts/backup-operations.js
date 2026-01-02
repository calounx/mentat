/**
 * k6 Load Test: Backup Operations
 *
 * Tests comprehensive backup lifecycle:
 * - Create backups (full, database, files)
 * - List backups with filtering
 * - Get backup details
 * - Download backups
 * - Restore from backups
 * - Delete backups
 *
 * Performance Targets:
 * - p95 response time < 800ms for backup operations
 * - Error rate < 0.1%
 * - Support 50+ concurrent backup operations
 */

import http from 'k6/http';
import { sleep, check, group } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';
import { getApiUrl, getHeaders } from '../k6.config.js';
import {
  generateTestUser,
  generateSiteConfig,
  generateBackupConfig,
  extractToken,
  extractId,
  checkResponse,
  userThinkTime,
  parseJsonResponse,
} from '../utils/helpers.js';

// Custom metrics for backup operations
const backupMetrics = {
  createDuration: new Trend('backup_create_duration'),
  listDuration: new Trend('backup_list_duration'),
  showDuration: new Trend('backup_show_duration'),
  downloadDuration: new Trend('backup_download_duration'),
  restoreDuration: new Trend('backup_restore_duration'),
  deleteDuration: new Trend('backup_delete_duration'),
  totalBackupsCreated: new Counter('backups_created_total'),
  totalBackupsRestored: new Counter('backups_restored_total'),
  totalBackupsDeleted: new Counter('backups_deleted_total'),
  backupErrors: new Counter('backup_errors_total'),
};

// Test configuration
export const options = {
  stages: [
    { duration: '1m', target: 10 },   // Warm-up
    { duration: '2m', target: 25 },   // Ramp up
    { duration: '4m', target: 50 },   // Peak load
    { duration: '3m', target: 50 },   // Sustained load
    { duration: '2m', target: 25 },   // Ramp down
    { duration: '1m', target: 0 },    // Cool down
  ],
  thresholds: {
    'http_req_duration{endpoint:backups}': ['p(95) < 800', 'p(99) < 1500'],
    'http_req_failed{endpoint:backups}': ['rate < 0.001'],
    'backup_create_duration': ['p(95) < 1000'],
    'backup_list_duration': ['p(95) < 400'],
    'backup_download_duration': ['p(95) < 2000'],
    'checks': ['rate > 0.999'],
  },
  tags: {
    test: 'backup-operations',
    endpoint: 'backups',
  },
};

/**
 * Setup - authenticate and create test sites
 */
export function setup() {
  console.log('='.repeat(60));
  console.log('Starting Backup Operations Load Test');
  console.log('='.repeat(60));

  // Create test user
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

  console.log('Test user authenticated');

  // Create a test site for backup operations
  const siteConfig = generateSiteConfig();

  const siteResponse = http.post(
    getApiUrl('/sites'),
    JSON.stringify(siteConfig),
    { headers: getHeaders(token) }
  );

  if (siteResponse.status !== 201) {
    throw new Error(`Failed to create test site: ${siteResponse.status}`);
  }

  const siteId = extractId(siteResponse);

  if (!siteId) {
    throw new Error('Failed to extract site ID');
  }

  console.log(`Test site created: ${siteId}`);
  console.log('='.repeat(60));

  return { token, siteId, user };
}

/**
 * Main test scenario
 */
export default function (data) {
  const { token, siteId } = data;
  const createdBackups = [];

  // Test: Create full backup
  group('Create Full Backup', () => {
    const backupConfig = generateBackupConfig();
    backupConfig.type = 'full';

    const startTime = Date.now();

    const createResponse = http.post(
      getApiUrl(`/sites/${siteId}/backups`),
      JSON.stringify(backupConfig),
      {
        headers: getHeaders(token),
        tags: { endpoint: 'backups', operation: 'create', backup_type: 'full' },
      }
    );

    backupMetrics.createDuration.add(Date.now() - startTime);

    // Accept 201 (created) or 202 (accepted for async processing)
    const isSuccess = check(createResponse, {
      'Create Full Backup: status is 201 or 202': (r) => r.status === 201 || r.status === 202,
    });

    if (isSuccess) {
      const backupId = extractId(createResponse);

      if (backupId) {
        createdBackups.push(backupId);
        backupMetrics.totalBackupsCreated.add(1);

        check(createResponse, {
          'Full Backup: has backup ID': (r) => backupId !== null,
          'Full Backup: has type': (r) => {
            const data = parseJsonResponse(r);
            return data && (data.type === 'full' || data.data?.type === 'full');
          },
        });
      }
    } else {
      backupMetrics.backupErrors.add(1);
      console.error(`Failed to create full backup: ${createResponse.status}`);
    }

    userThinkTime(3, 6);
  });

  // Test: Create database backup
  group('Create Database Backup', () => {
    const backupConfig = generateBackupConfig();
    backupConfig.type = 'database';

    const startTime = Date.now();

    const createResponse = http.post(
      getApiUrl(`/sites/${siteId}/backups`),
      JSON.stringify(backupConfig),
      {
        headers: getHeaders(token),
        tags: { endpoint: 'backups', operation: 'create', backup_type: 'database' },
      }
    );

    backupMetrics.createDuration.add(Date.now() - startTime);

    const isSuccess = check(createResponse, {
      'Create DB Backup: status is 201 or 202': (r) => r.status === 201 || r.status === 202,
    });

    if (isSuccess) {
      const backupId = extractId(createResponse);
      if (backupId) {
        createdBackups.push(backupId);
        backupMetrics.totalBackupsCreated.add(1);
      }
    } else {
      backupMetrics.backupErrors.add(1);
    }

    userThinkTime(2, 4);
  });

  // Test: Create files backup
  group('Create Files Backup', () => {
    const backupConfig = generateBackupConfig();
    backupConfig.type = 'files';

    const startTime = Date.now();

    const createResponse = http.post(
      getApiUrl(`/sites/${siteId}/backups`),
      JSON.stringify(backupConfig),
      {
        headers: getHeaders(token),
        tags: { endpoint: 'backups', operation: 'create', backup_type: 'files' },
      }
    );

    backupMetrics.createDuration.add(Date.now() - startTime);

    const isSuccess = check(createResponse, {
      'Create Files Backup: status is 201 or 202': (r) => r.status === 201 || r.status === 202,
    });

    if (isSuccess) {
      const backupId = extractId(createResponse);
      if (backupId) {
        createdBackups.push(backupId);
        backupMetrics.totalBackupsCreated.add(1);
      }
    } else {
      backupMetrics.backupErrors.add(1);
    }

    userThinkTime(2, 4);
  });

  // Test: List all backups
  group('List All Backups', () => {
    const startTime = Date.now();

    const listResponse = http.get(
      getApiUrl('/backups'),
      {
        headers: getHeaders(token),
        tags: { endpoint: 'backups', operation: 'list' },
      }
    );

    backupMetrics.listDuration.add(Date.now() - startTime);

    checkResponse(listResponse, 200, 'List All Backups', {
      endpoint: 'backups',
      operation: 'list',
    });

    check(listResponse, {
      'List Backups: has data array': (r) => {
        const data = parseJsonResponse(r);
        return data && (Array.isArray(data.data) || Array.isArray(data));
      },
    });

    userThinkTime(1, 3);
  });

  // Test: List backups for specific site
  group('List Site Backups', () => {
    const startTime = Date.now();

    const listResponse = http.get(
      getApiUrl(`/sites/${siteId}/backups`),
      {
        headers: getHeaders(token),
        tags: { endpoint: 'backups', operation: 'list', context: 'site' },
      }
    );

    backupMetrics.listDuration.add(Date.now() - startTime);

    checkResponse(listResponse, 200, 'List Site Backups');

    userThinkTime(1, 2);
  });

  // Test: Get backup details
  if (createdBackups.length > 0) {
    group('Get Backup Details', () => {
      createdBackups.forEach((backupId, index) => {
        const startTime = Date.now();

        const showResponse = http.get(
          getApiUrl(`/backups/${backupId}`),
          {
            headers: getHeaders(token),
            tags: { endpoint: 'backups', operation: 'show' },
          }
        );

        backupMetrics.showDuration.add(Date.now() - startTime);

        checkResponse(showResponse, 200, `Get Backup Details (${index + 1})`);

        if (index < createdBackups.length - 1) {
          userThinkTime(1, 2);
        }
      });
    });
  }

  // Test: Download backup
  if (createdBackups.length > 0) {
    group('Download Backup', () => {
      const backupId = createdBackups[0];

      const startTime = Date.now();

      const downloadResponse = http.get(
        getApiUrl(`/backups/${backupId}/download`),
        {
          headers: getHeaders(token),
          tags: { endpoint: 'backups', operation: 'download' },
        }
      );

      backupMetrics.downloadDuration.add(Date.now() - startTime);

      // Accept 200 (download) or 302 (redirect to download URL)
      check(downloadResponse, {
        'Download Backup: status is 200 or 302': (r) => r.status === 200 || r.status === 302,
      });

      userThinkTime(3, 6);
    });
  }

  // Test: Restore from backup
  if (createdBackups.length > 0) {
    group('Restore Backup', () => {
      const backupId = createdBackups[0];

      const startTime = Date.now();

      const restoreResponse = http.post(
        getApiUrl(`/backups/${backupId}/restore`),
        null,
        {
          headers: getHeaders(token),
          tags: { endpoint: 'backups', operation: 'restore' },
        }
      );

      backupMetrics.restoreDuration.add(Date.now() - startTime);

      // Accept 200 (completed) or 202 (accepted for async processing)
      const isSuccess = check(restoreResponse, {
        'Restore Backup: status is 200 or 202': (r) => r.status === 200 || r.status === 202,
      });

      if (isSuccess) {
        backupMetrics.totalBackupsRestored.add(1);
      } else {
        backupMetrics.backupErrors.add(1);
      }

      userThinkTime(4, 8);
    });
  }

  // Test: Delete backups (cleanup)
  group('Delete Backups', () => {
    createdBackups.forEach((backupId, index) => {
      const startTime = Date.now();

      const deleteResponse = http.del(
        getApiUrl(`/backups/${backupId}`),
        null,
        {
          headers: getHeaders(token),
          tags: { endpoint: 'backups', operation: 'delete' },
        }
      );

      backupMetrics.deleteDuration.add(Date.now() - startTime);

      // Accept 200, 202, or 204
      const isSuccess = check(deleteResponse, {
        'Delete Backup: status is 200, 202, or 204': (r) =>
          r.status === 200 || r.status === 202 || r.status === 204,
      });

      if (isSuccess) {
        backupMetrics.totalBackupsDeleted.add(1);
      } else {
        backupMetrics.backupErrors.add(1);
      }

      if (index < createdBackups.length - 1) {
        sleep(1);
      }
    });
  });

  // Simulate end of user session
  sleep(1);
}

/**
 * Teardown - cleanup test site
 */
export function teardown(data) {
  const { token, siteId } = data;

  console.log('='.repeat(60));
  console.log('Cleaning up test resources...');

  // Delete test site
  const deleteResponse = http.del(
    getApiUrl(`/sites/${siteId}`),
    null,
    { headers: getHeaders(token) }
  );

  if (deleteResponse.status === 200 || deleteResponse.status === 204) {
    console.log(`Test site deleted: ${siteId}`);
  } else {
    console.warn(`Failed to delete test site: ${deleteResponse.status}`);
  }

  console.log('Backup Operations Load Test Complete');
  console.log('='.repeat(60));
}

/**
 * Handle test summary
 */
export function handleSummary(data) {
  return {
    'results/backup-operations-summary.json': JSON.stringify(data, null, 2),
  };
}
