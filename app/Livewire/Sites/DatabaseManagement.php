<?php

namespace App\Livewire\Sites;

use App\Models\Site;
use App\Models\Tenant;
use App\Services\Integration\VPSManagerBridge;
use Illuminate\Foundation\Auth\Access\AuthorizesRequests;
use Illuminate\Support\Facades\Log;
use Livewire\Component;

class DatabaseManagement extends Component
{
    use AuthorizesRequests;

    public ?string $siteId = null;
    public ?Site $site = null;

    public bool $isExporting = false;
    public bool $isOptimizing = false;
    public ?string $error = null;
    public ?string $exportResult = null;
    public ?string $optimizeResult = null;

    public bool $showExportConfirm = false;
    public bool $showOptimizeConfirm = false;

    protected $listeners = ['refreshDatabaseManagement' => '$refresh'];

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

    public function confirmExport(): void
    {
        $this->showExportConfirm = true;
    }

    public function cancelExport(): void
    {
        $this->showExportConfirm = false;
    }

    public function exportDatabase(): void
    {
        $this->showExportConfirm = false;

        if (!$this->site || !$this->site->vpsServer) {
            $this->error = 'Site or VPS server not available.';
            return;
        }

        // Authorization check
        $this->authorize('update', $this->site);

        $this->isExporting = true;
        $this->error = null;
        $this->exportResult = null;

        try {
            $bridge = app(VPSManagerBridge::class);
            $result = $bridge->exportDatabase($this->site->vpsServer, $this->site->domain);

            if ($result['success']) {
                $exportPath = $result['data']['path'] ?? $result['data']['file'] ?? null;
                $exportSize = $result['data']['size'] ?? null;

                if ($exportPath) {
                    $this->exportResult = "Database exported successfully to: {$exportPath}";
                    if ($exportSize) {
                        $this->exportResult .= " (Size: {$exportSize})";
                    }
                } else {
                    $this->exportResult = 'Database exported successfully.';
                }

                session()->flash('success', 'Database export completed.');

                Log::info('Database exported', [
                    'site_id' => $this->siteId,
                    'domain' => $this->site->domain,
                    'path' => $exportPath,
                ]);
            } else {
                $this->error = 'Database export failed. ' . ($result['output'] ?? 'Please try again.');
            }
        } catch (\Exception $e) {
            Log::error('Database export error', [
                'site_id' => $this->siteId,
                'error' => $e->getMessage(),
            ]);
            $this->error = 'Database export failed: ' . $e->getMessage();
        }

        $this->isExporting = false;
    }

    public function confirmOptimize(): void
    {
        $this->showOptimizeConfirm = true;
    }

    public function cancelOptimize(): void
    {
        $this->showOptimizeConfirm = false;
    }

    public function optimizeDatabase(): void
    {
        $this->showOptimizeConfirm = false;

        if (!$this->site || !$this->site->vpsServer) {
            $this->error = 'Site or VPS server not available.';
            return;
        }

        // Authorization check
        $this->authorize('update', $this->site);

        $this->isOptimizing = true;
        $this->error = null;
        $this->optimizeResult = null;

        try {
            $bridge = app(VPSManagerBridge::class);
            $result = $bridge->optimizeDatabase($this->site->vpsServer, $this->site->domain);

            if ($result['success']) {
                $tablesOptimized = $result['data']['tables_optimized'] ?? null;
                $spaceSaved = $result['data']['space_saved'] ?? null;

                $this->optimizeResult = 'Database optimization completed successfully.';
                if ($tablesOptimized) {
                    $this->optimizeResult .= " Tables optimized: {$tablesOptimized}.";
                }
                if ($spaceSaved) {
                    $this->optimizeResult .= " Space saved: {$spaceSaved}.";
                }

                session()->flash('success', 'Database optimization completed.');

                Log::info('Database optimized', [
                    'site_id' => $this->siteId,
                    'domain' => $this->site->domain,
                    'tables_optimized' => $tablesOptimized,
                    'space_saved' => $spaceSaved,
                ]);
            } else {
                $this->error = 'Database optimization failed. ' . ($result['output'] ?? 'Please try again.');
            }
        } catch (\Exception $e) {
            Log::error('Database optimize error', [
                'site_id' => $this->siteId,
                'error' => $e->getMessage(),
            ]);
            $this->error = 'Database optimization failed: ' . $e->getMessage();
        }

        $this->isOptimizing = false;
    }

    public function clearMessages(): void
    {
        $this->error = null;
        $this->exportResult = null;
        $this->optimizeResult = null;
    }

    private function getTenant(): ?Tenant
    {
        return auth()->user()?->currentTenant();
    }

    public function render()
    {
        return view('livewire.sites.database-management')
            ->layout('layouts.app', ['title' => $this->site ? "Database: {$this->site->domain}" : 'Database Management']);
    }
}
