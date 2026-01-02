<?php

namespace App\Services\Sites;

use App\Contracts\VpsManagerInterface;
use App\Jobs\IssueSslCertificateJob;
use App\Models\Site;
use Illuminate\Support\Facades\Log;

/**
 * Site Management Service
 *
 * Handles site lifecycle operations like enabling, disabling,
 * SSL management, updates, and deletion.
 */
class SiteManagementService
{
    /**
     * Create a new site management service instance.
     */
    public function __construct(
        protected VpsManagerInterface $vpsManager
    ) {}

    /**
     * Enable a site.
     *
     * @param  Site  $site  The site to enable
     * @return array{success: bool, message: string}
     */
    public function enableSite(Site $site): array
    {
        if ($site->status === 'active') {
            return [
                'success' => true,
                'message' => 'Site is already enabled',
            ];
        }

        if (! $site->vpsServer) {
            return [
                'success' => false,
                'message' => 'Site has no associated VPS server',
            ];
        }

        try {
            $result = $this->vpsManager->enableSite($site->vpsServer, $site->domain);

            if ($result['success']) {
                $site->update(['status' => 'active']);

                Log::info('Site enabled', [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                ]);

                return [
                    'success' => true,
                    'message' => 'Site enabled successfully',
                ];
            }

            Log::warning('Failed to enable site on VPS', [
                'site_id' => $site->id,
                'domain' => $site->domain,
                'output' => $result['output'] ?? null,
            ]);

            return [
                'success' => false,
                'message' => 'Failed to enable site on VPS',
            ];

        } catch (\Exception $e) {
            Log::error('Site enable error', [
                'site_id' => $site->id,
                'error' => $e->getMessage(),
            ]);

            return [
                'success' => false,
                'message' => $e->getMessage(),
            ];
        }
    }

    /**
     * Disable a site.
     *
     * @param  Site  $site  The site to disable
     * @return array{success: bool, message: string}
     */
    public function disableSite(Site $site): array
    {
        if ($site->status === 'disabled') {
            return [
                'success' => true,
                'message' => 'Site is already disabled',
            ];
        }

        if (! $site->vpsServer) {
            return [
                'success' => false,
                'message' => 'Site has no associated VPS server',
            ];
        }

        try {
            $result = $this->vpsManager->disableSite($site->vpsServer, $site->domain);

            if ($result['success']) {
                $site->update(['status' => 'disabled']);

                Log::info('Site disabled', [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                ]);

                return [
                    'success' => true,
                    'message' => 'Site disabled successfully',
                ];
            }

            Log::warning('Failed to disable site on VPS', [
                'site_id' => $site->id,
                'domain' => $site->domain,
                'output' => $result['output'] ?? null,
            ]);

            return [
                'success' => false,
                'message' => 'Failed to disable site on VPS',
            ];

        } catch (\Exception $e) {
            Log::error('Site disable error', [
                'site_id' => $site->id,
                'error' => $e->getMessage(),
            ]);

            return [
                'success' => false,
                'message' => $e->getMessage(),
            ];
        }
    }

    /**
     * Update site settings.
     *
     * @param  Site  $site  The site to update
     * @param  array<string, mixed>  $data  Update data
     * @return Site Updated site
     */
    public function updateSite(Site $site, array $data): Site
    {
        $updateData = [];

        // Only allow specific fields to be updated
        $allowedFields = ['php_version', 'settings'];

        foreach ($allowedFields as $field) {
            if (array_key_exists($field, $data)) {
                $updateData[$field] = $data[$field];
            }
        }

        if (! empty($updateData)) {
            $site->update($updateData);

            Log::info('Site updated', [
                'site_id' => $site->id,
                'updated_fields' => array_keys($updateData),
            ]);
        }

        return $site->fresh();
    }

    /**
     * Delete a site.
     *
     * This performs both VPS cleanup and database soft delete.
     *
     * @param  Site  $site  The site to delete
     * @param  bool  $force  Force deletion even if VPS cleanup fails
     * @return array{success: bool, message: string}
     */
    public function deleteSite(Site $site, bool $force = false): array
    {
        try {
            // Attempt to delete from VPS if site is active
            if ($site->vpsServer && $site->status === 'active') {
                $result = $this->vpsManager->deleteSite(
                    $site->vpsServer,
                    $site->domain,
                    force: true
                );

                if (! $result['success'] && ! $force) {
                    Log::warning('VPS site deletion failed', [
                        'site_id' => $site->id,
                        'domain' => $site->domain,
                        'output' => $result['output'] ?? null,
                    ]);

                    return [
                        'success' => false,
                        'message' => 'Failed to delete site from VPS. Use force option to delete anyway.',
                    ];
                }
            }

            // Soft delete the site
            $site->delete();

            Log::info('Site deleted', [
                'site_id' => $site->id,
                'domain' => $site->domain,
            ]);

            return [
                'success' => true,
                'message' => 'Site deleted successfully',
            ];

        } catch (\Exception $e) {
            Log::error('Site deletion error', [
                'site_id' => $site->id,
                'error' => $e->getMessage(),
            ]);

            return [
                'success' => false,
                'message' => $e->getMessage(),
            ];
        }
    }

    /**
     * Issue SSL certificate for a site.
     *
     * @param  Site  $site  The site
     * @return array{success: bool, message: string}
     */
    public function issueSSL(Site $site): array
    {
        if (! $site->vpsServer) {
            return [
                'success' => false,
                'message' => 'Site has no associated VPS server',
            ];
        }

        try {
            // Dispatch async job for SSL certificate issuance
            IssueSslCertificateJob::dispatch($site);

            Log::info('SSL certificate issuance job dispatched', [
                'site_id' => $site->id,
                'domain' => $site->domain,
            ]);

            return [
                'success' => true,
                'message' => 'SSL certificate issuance started',
            ];

        } catch (\Exception $e) {
            Log::error('SSL certificate dispatch error', [
                'site_id' => $site->id,
                'error' => $e->getMessage(),
            ]);

            return [
                'success' => false,
                'message' => $e->getMessage(),
            ];
        }
    }

    /**
     * Get site health status.
     *
     * @param  Site  $site  The site
     * @return array{healthy: bool, issues: array<string>}
     */
    public function getSiteHealth(Site $site): array
    {
        $issues = [];

        // Check VPS availability
        if (! $site->vpsServer || ! $site->vpsServer->isAvailable()) {
            $issues[] = 'VPS server is not available';
        }

        // Check SSL expiration
        if ($site->ssl_enabled && $site->isSslExpired()) {
            $issues[] = 'SSL certificate has expired';
        } elseif ($site->ssl_enabled && $site->isSslExpiringSoon()) {
            $issues[] = 'SSL certificate expires soon';
        }

        // Check site status
        if ($site->status !== 'active') {
            $issues[] = 'Site is not active';
        }

        return [
            'healthy' => empty($issues),
            'issues' => $issues,
        ];
    }
}
