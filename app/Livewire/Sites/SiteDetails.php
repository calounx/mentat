<?php

namespace App\Livewire\Sites;

use App\Models\Site;
use App\Models\Tenant;
use App\Services\Integration\VPSManagerBridge;
use Illuminate\Foundation\Auth\Access\AuthorizesRequests;
use Illuminate\Support\Facades\Log;
use Livewire\Component;

class SiteDetails extends Component
{
    use AuthorizesRequests;

    public ?string $siteId = null;
    public ?Site $site = null;

    public array $siteInfo = [];
    public array $sslStatus = [];

    public bool $isLoading = false;
    public ?string $error = null;
    public ?string $lastUpdated = null;

    protected $listeners = ['refreshSiteDetails' => 'loadSiteData'];

    public function mount(string $siteId): void
    {
        $this->siteId = $siteId;
        $this->loadSite();
        $this->loadSiteData();
    }

    private function loadSite(): void
    {
        $tenant = $this->getTenant();

        if (!$tenant) {
            $this->error = 'Tenant not found.';
            return;
        }

        $this->site = $tenant->sites()
            ->with('vpsServer')
            ->find($this->siteId);

        if (!$this->site) {
            $this->error = 'Site not found.';
        }
    }

    public function loadSiteData(): void
    {
        if (!$this->site || !$this->site->vpsServer) {
            $this->error = 'Site or VPS server not available.';
            return;
        }

        $this->isLoading = true;
        $this->error = null;

        try {
            $bridge = app(VPSManagerBridge::class);

            // Fetch site info from VPS
            $siteInfoResult = $bridge->getSiteInfo($this->site->vpsServer, $this->site->domain);
            $sslStatusResult = $bridge->getSSLStatus($this->site->vpsServer, $this->site->domain);

            $this->siteInfo = $siteInfoResult['success'] ? ($siteInfoResult['data'] ?? []) : [];
            $this->sslStatus = $sslStatusResult['success'] ? ($sslStatusResult['data'] ?? []) : [];

            if (!$siteInfoResult['success'] && !$sslStatusResult['success']) {
                $this->error = 'Failed to fetch site data from VPS.';
            }

            $this->lastUpdated = now()->format('M d, Y H:i:s');

        } catch (\Exception $e) {
            Log::error('Site details fetch error', [
                'site_id' => $this->siteId,
                'error' => $e->getMessage(),
            ]);
            $this->error = 'Failed to fetch site data: ' . $e->getMessage();
        }

        $this->isLoading = false;
    }

    public function refresh(): void
    {
        $this->loadSiteData();
    }

    private function getTenant(): ?Tenant
    {
        return auth()->user()?->currentTenant();
    }

    public function render()
    {
        return view('livewire.sites.site-details')
            ->layout('layouts.app', ['title' => $this->site ? "Site: {$this->site->domain}" : 'Site Details']);
    }
}
