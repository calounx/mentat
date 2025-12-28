<?php

namespace App\Livewire\Sites;

use App\Jobs\ProvisionSiteJob;
use App\Models\Site;
use App\Models\VpsServer;
use Illuminate\Foundation\Auth\Access\AuthorizesRequests;
use Illuminate\Support\Facades\DB;
use Livewire\Component;

class SiteCreate extends Component
{
    use AuthorizesRequests;

    public string $domain = '';
    public string $siteType = 'wordpress';
    public string $phpVersion = '8.2';
    public bool $sslEnabled = true;

    public bool $isCreating = false;
    public ?string $error = null;

    protected $rules = [
        'domain' => 'required|regex:/^[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+$/i|max:253',
        'siteType' => 'required|in:wordpress,html',
        'phpVersion' => 'required|in:8.2,8.4',
        'sslEnabled' => 'boolean',
    ];

    protected $messages = [
        'domain.required' => 'Please enter a domain name.',
        'domain.regex' => 'Please enter a valid domain name (e.g., example.com).',
    ];

    public function updatedDomain(): void
    {
        $this->domain = strtolower(trim($this->domain));
    }

    public function create(): void
    {
        // Authorization check - only users with site management permissions can create
        $this->authorize('create', Site::class);

        $this->validate();

        $tenant = auth()->user()->currentTenant();

        // Check quota
        if (!$tenant->canCreateSite()) {
            $this->error = 'You have reached your plan\'s site limit. Please upgrade to create more sites.';
            return;
        }

        // Check if domain already exists
        if ($tenant->sites()->where('domain', $this->domain)->exists()) {
            $this->error = 'This domain is already configured for your account.';
            return;
        }

        $this->isCreating = true;
        $this->error = null;

        try {
            $site = DB::transaction(function () use ($tenant) {
                // Find available VPS
                $vps = $this->findAvailableVps($tenant);

                if (!$vps) {
                    throw new \RuntimeException('No available server found. Please contact support.');
                }

                // Create site record
                $site = Site::create([
                    'tenant_id' => $tenant->id,
                    'vps_id' => $vps->id,
                    'domain' => $this->domain,
                    'site_type' => $this->siteType,
                    'php_version' => $this->phpVersion,
                    'ssl_enabled' => $this->sslEnabled,
                    'status' => 'creating',
                ]);

                return $site;
            });

            // Dispatch async job to provision the site
            ProvisionSiteJob::dispatch($site);

            session()->flash('success', "Site {$this->domain} is being created.");
            $this->redirect(route('sites.index'));

        } catch (\Exception $e) {
            $this->error = $e->getMessage();
            $this->isCreating = false;
        }
    }

    private function findAvailableVps($tenant): ?VpsServer
    {
        // Check existing allocation first
        $allocation = $tenant->vpsAllocations()->with('vpsServer')->first();

        if ($allocation && $allocation->vpsServer?->isAvailable()) {
            return $allocation->vpsServer;
        }

        // Find shared VPS with capacity
        return VpsServer::active()
            ->shared()
            ->healthy()
            ->orderByRaw('(SELECT COUNT(*) FROM sites WHERE vps_id = vps_servers.id) ASC')
            ->first();
    }

    public function render()
    {
        $tenant = auth()->user()->currentTenant();
        $canCreate = $tenant?->canCreateSite() ?? false;
        $siteCount = $tenant?->getSiteCount() ?? 0;
        $maxSites = $tenant?->getMaxSites() ?? 0;

        return view('livewire.sites.site-create', [
            'canCreate' => $canCreate,
            'siteCount' => $siteCount,
            'maxSites' => $maxSites,
        ])->layout('layouts.app', ['title' => 'Create Site']);
    }
}
