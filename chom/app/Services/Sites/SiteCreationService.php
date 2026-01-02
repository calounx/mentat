<?php

namespace App\Services\Sites;

use App\Exceptions\QuotaExceededException;
use App\Jobs\ProvisionSiteJob;
use App\Models\Site;
use App\Models\Tenant;
use App\Services\VPS\VpsAllocationService;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Site Creation Service
 *
 * Handles all business logic related to creating new sites.
 * Orchestrates quota checking, VPS allocation, and site provisioning.
 */
class SiteCreationService
{
    /**
     * Create a new site creation service instance.
     */
    public function __construct(
        protected SiteQuotaService $quotaService,
        protected VpsAllocationService $vpsAllocationService
    ) {}

    /**
     * Create a new site for the tenant.
     *
     * This method:
     * 1. Validates quota limits
     * 2. Allocates appropriate VPS server
     * 3. Creates site database record
     * 4. Dispatches async provisioning job
     *
     * @param  Tenant  $tenant  The tenant creating the site
     * @param  array<string, mixed>  $data  Site creation data
     *
     * @throws QuotaExceededException If tenant has exceeded site quota
     * @throws \RuntimeException If no VPS server is available
     */
    public function createSite(Tenant $tenant, array $data): Site
    {
        // Step 1: Check quota
        $this->quotaService->ensureCanCreateSite($tenant);

        // Step 2: Sanitize and prepare data
        $siteData = $this->prepareSiteData($tenant, $data);

        // Step 3: Create site in transaction
        $site = DB::transaction(function () use ($tenant, $siteData) {
            // Find available VPS
            $vps = $this->vpsAllocationService->findAvailableVps($tenant);

            if (! $vps) {
                throw new \RuntimeException(
                    'No available VPS server found. Please contact support.'
                );
            }

            // Create site record
            $site = Site::create([
                'tenant_id' => $tenant->id,
                'vps_id' => $vps->id,
                'domain' => $siteData['domain'],
                'site_type' => $siteData['site_type'],
                'php_version' => $siteData['php_version'],
                'ssl_enabled' => $siteData['ssl_enabled'],
                'status' => 'creating',
                'settings' => $siteData['settings'] ?? [],
            ]);

            Log::info('Site created', [
                'site_id' => $site->id,
                'tenant_id' => $tenant->id,
                'domain' => $site->domain,
                'vps_id' => $vps->id,
            ]);

            return $site;
        });

        // Emit SiteCreated event (triggers cache update, audit log, metrics)
        \App\Events\Site\SiteCreated::dispatch($site, $tenant);

        // Step 4: Dispatch async provisioning job
        ProvisionSiteJob::dispatch($site);

        Log::info('Site provisioning job dispatched', [
            'site_id' => $site->id,
            'domain' => $site->domain,
        ]);

        return $site;
    }

    /**
     * Prepare and sanitize site data.
     *
     * @param  Tenant  $tenant  The tenant
     * @param  array<string, mixed>  $data  Raw site data
     * @return array<string, mixed> Sanitized site data
     */
    protected function prepareSiteData(Tenant $tenant, array $data): array
    {
        return [
            'domain' => strtolower(trim($data['domain'])),
            'site_type' => $data['site_type'] ?? 'wordpress',
            'php_version' => $data['php_version'] ?? '8.2',
            'ssl_enabled' => $data['ssl_enabled'] ?? true,
            'settings' => $data['settings'] ?? [],
        ];
    }

    /**
     * Validate site creation data.
     *
     * This is an additional layer of validation beyond form requests.
     * Useful for programmatic site creation.
     *
     * @param  Tenant  $tenant  The tenant
     * @param  array<string, mixed>  $data  Site data
     * @return array{valid: bool, errors: array<string, string>}
     */
    public function validateSiteData(Tenant $tenant, array $data): array
    {
        $errors = [];

        // Validate domain
        if (empty($data['domain'])) {
            $errors['domain'] = 'Domain is required';
        } elseif (! $this->isValidDomain($data['domain'])) {
            $errors['domain'] = 'Invalid domain format';
        } elseif ($this->domainExistsForTenant($tenant, $data['domain'])) {
            $errors['domain'] = 'Domain already exists for this tenant';
        }

        // Validate site type
        $validTypes = ['wordpress', 'html', 'laravel'];
        if (isset($data['site_type']) && ! in_array($data['site_type'], $validTypes)) {
            $errors['site_type'] = 'Invalid site type';
        }

        // Validate PHP version
        $validPhpVersions = ['8.2', '8.4'];
        if (isset($data['php_version']) && ! in_array($data['php_version'], $validPhpVersions)) {
            $errors['php_version'] = 'Invalid PHP version';
        }

        return [
            'valid' => empty($errors),
            'errors' => $errors,
        ];
    }

    /**
     * Check if domain format is valid.
     *
     * @param  string  $domain  The domain to validate
     */
    protected function isValidDomain(string $domain): bool
    {
        $pattern = '/^[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+$/i';

        return (bool) preg_match($pattern, $domain);
    }

    /**
     * Check if domain already exists for tenant.
     *
     * @param  Tenant  $tenant  The tenant
     * @param  string  $domain  The domain to check
     */
    protected function domainExistsForTenant(Tenant $tenant, string $domain): bool
    {
        return $tenant->sites()
            ->where('domain', strtolower($domain))
            ->exists();
    }

    /**
     * Get site creation status and recommendations.
     *
     * Useful for showing users whether they can create sites
     * and what's blocking them if they can't.
     *
     * @param  Tenant  $tenant  The tenant
     * @return array{can_create: bool, quota_info: array, vps_available: bool, blockers: array<string>}
     */
    public function getCreationStatus(Tenant $tenant): array
    {
        $quotaInfo = $this->quotaService->getQuotaInfo($tenant);
        $vpsAvailable = $this->vpsAllocationService->getAvailableSharedVpsCount() > 0;

        $blockers = [];

        if (! $quotaInfo['can_create']) {
            $blockers[] = 'Site quota limit reached';
        }

        if (! $vpsAvailable) {
            $blockers[] = 'No VPS servers available';
        }

        if (! $tenant->isActive()) {
            $blockers[] = 'Tenant is not active';
        }

        return [
            'can_create' => empty($blockers),
            'quota_info' => $quotaInfo,
            'vps_available' => $vpsAvailable,
            'blockers' => $blockers,
        ];
    }
}
