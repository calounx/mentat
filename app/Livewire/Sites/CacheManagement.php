<?php

namespace App\Livewire\Sites;

use App\Models\Site;
use App\Models\Tenant;
use App\Services\Integration\VPSManagerBridge;
use Illuminate\Foundation\Auth\Access\AuthorizesRequests;
use Illuminate\Support\Facades\Log;
use Livewire\Component;

class CacheManagement extends Component
{
    use AuthorizesRequests;

    public ?string $siteId = null;
    public ?Site $site = null;

    public bool $isClearing = false;
    public ?string $error = null;
    public ?string $successMessage = null;

    public bool $showClearConfirm = false;

    protected $listeners = ['refreshCacheManagement' => '$refresh'];

    public function mount(string $siteId): void
    {
        $this->siteId = $siteId;
        $this->loadSite();
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

    public function confirmClearCache(): void
    {
        $this->showClearConfirm = true;
    }

    public function cancelClearCache(): void
    {
        $this->showClearConfirm = false;
    }

    public function clearCache(): void
    {
        $this->showClearConfirm = false;

        if (!$this->site || !$this->site->vpsServer) {
            $this->error = 'Site or VPS server not available.';
            return;
        }

        // Authorization check
        $this->authorize('update', $this->site);

        $this->isClearing = true;
        $this->error = null;
        $this->successMessage = null;

        try {
            $bridge = app(VPSManagerBridge::class);
            $result = $bridge->clearCache($this->site->vpsServer, $this->site->domain);

            if ($result['success']) {
                $cacheTypes = $result['data']['cleared'] ?? [];
                $message = 'Cache cleared successfully.';

                if (!empty($cacheTypes)) {
                    if (is_array($cacheTypes)) {
                        $message .= ' Cleared: ' . implode(', ', $cacheTypes) . '.';
                    } else {
                        $message .= " {$cacheTypes}";
                    }
                }

                $this->successMessage = $message;
                session()->flash('success', 'Cache cleared successfully.');

                Log::info('Cache cleared', [
                    'site_id' => $this->siteId,
                    'domain' => $this->site->domain,
                    'cleared' => $cacheTypes,
                ]);
            } else {
                $this->error = 'Failed to clear cache. ' . ($result['output'] ?? 'Please try again.');
            }
        } catch (\Exception $e) {
            Log::error('Cache clear error', [
                'site_id' => $this->siteId,
                'error' => $e->getMessage(),
            ]);
            $this->error = 'Failed to clear cache: ' . $e->getMessage();
        }

        $this->isClearing = false;
    }

    public function clearMessages(): void
    {
        $this->error = null;
        $this->successMessage = null;
    }

    private function getTenant(): ?Tenant
    {
        return auth()->user()?->currentTenant();
    }

    public function render()
    {
        return view('livewire.sites.cache-management')
            ->layout('layouts.app', ['title' => $this->site ? "Cache: {$this->site->domain}" : 'Cache Management']);
    }
}
