<?php

namespace App\Livewire\Backups;

use App\Jobs\CreateBackupJob;
use App\Jobs\RestoreBackupJob;
use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\Tenant;
use Illuminate\Foundation\Auth\Access\AuthorizesRequests;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Gate;
use Livewire\Component;
use Livewire\WithPagination;
use Illuminate\Support\Facades\Log;

class BackupList extends Component
{
    use WithPagination, AuthorizesRequests;

    public ?string $siteFilter = '';
    public ?string $typeFilter = '';

    public ?string $creatingBackupForSite = null;
    public string $backupType = 'full';

    public ?string $restoringBackupId = null;
    public ?string $deletingBackupId = null;

    // Backup status modal
    public bool $showBackupStatusModal = false;
    public ?string $viewingBackupStatusId = null;
    public $viewingBackupData = null;

    // Cache key for total backup size
    private const TOTAL_SIZE_CACHE_TTL = 300; // 5 minutes

    protected $queryString = [
        'siteFilter' => ['except' => ''],
        'typeFilter' => ['except' => ''],
    ];

    public function updatingSiteFilter(): void
    {
        $this->resetPage();
    }

    public function updatingTypeFilter(): void
    {
        $this->resetPage();
    }

    public function showCreateModal(string $siteId): void
    {
        $this->creatingBackupForSite = $siteId;
        $this->backupType = 'full';
    }

    public function closeCreateModal(): void
    {
        $this->creatingBackupForSite = null;
    }

    public function createBackup(): void
    {
        if (!$this->creatingBackupForSite) {
            return;
        }

        $tenant = $this->getTenant();
        $site = $tenant->sites()->with('vpsServer')->find($this->creatingBackupForSite);

        if (!$site || !$site->vpsServer) {
            session()->flash('error', 'Site or server not found.');
            $this->closeCreateModal();
            return;
        }

        // Authorization check - verify user can create backups for this site
        $response = Gate::inspect('create', [SiteBackup::class, $site]);
        if ($response->denied()) {
            session()->flash('error', $response->message() ?: 'You do not have permission to create backups.');
            $this->closeCreateModal();
            return;
        }

        try {
            // Dispatch async job to create backup
            CreateBackupJob::dispatch(
                $site,
                $this->backupType,
                $tenant->tierLimits?->backup_retention_days ?? 7
            );

            session()->flash('success', "Backup is being created for {$site->domain}");
        } catch (\Exception $e) {
            Log::error('Backup creation dispatch failed', ['site' => $site->domain, 'error' => $e->getMessage()]);
            session()->flash('error', 'Failed to start backup: ' . $e->getMessage());
        }

        $this->closeCreateModal();
    }

    public function confirmRestore(string $backupId): void
    {
        $this->restoringBackupId = $backupId;
    }

    public function cancelRestore(): void
    {
        $this->restoringBackupId = null;
    }

    public function restoreBackup(): void
    {
        if (!$this->restoringBackupId) {
            return;
        }

        $tenant = $this->getTenant();
        $backup = SiteBackup::whereHas('site', fn($q) => $q->where('tenant_id', $tenant->id))
            ->with('site.vpsServer')
            ->find($this->restoringBackupId);

        if (!$backup || !$backup->site->vpsServer) {
            session()->flash('error', 'Backup not found.');
            $this->cancelRestore();
            return;
        }

        // Authorization check - restore is a destructive operation requiring admin
        $this->authorize('restore', $backup);

        try {
            // Dispatch async job to restore backup
            RestoreBackupJob::dispatch($backup);

            session()->flash('success', "Backup restore started for {$backup->site->domain}");
        } catch (\Exception $e) {
            Log::error('Backup restore dispatch failed', ['backup' => $backup->id, 'error' => $e->getMessage()]);
            session()->flash('error', 'Failed to start restore: ' . $e->getMessage());
        }

        $this->cancelRestore();
    }

    public function confirmDelete(string $backupId): void
    {
        $this->deletingBackupId = $backupId;
    }

    public function cancelDelete(): void
    {
        $this->deletingBackupId = null;
    }

    public function viewBackupStatus(string $backupId): void
    {
        $tenant = $this->getTenant();
        $this->viewingBackupStatusId = $backupId;
        $this->viewingBackupData = SiteBackup::whereHas('site', fn($q) => $q->where('tenant_id', $tenant->id))
            ->with(['site', 'user'])
            ->find($backupId);
        $this->showBackupStatusModal = true;
    }

    public function closeBackupStatusModal(): void
    {
        $this->showBackupStatusModal = false;
        $this->viewingBackupStatusId = null;
        $this->viewingBackupData = null;
    }

    public function deleteBackup(): void
    {
        if (!$this->deletingBackupId) {
            return;
        }

        $tenant = $this->getTenant();

        if (!$tenant) {
            session()->flash('error', 'Tenant not found.');
            $this->cancelDelete();
            return;
        }

        try {
            $backup = SiteBackup::whereHas('site', fn($q) => $q->where('tenant_id', $tenant->id))
                ->find($this->deletingBackupId);

            if (!$backup) {
                session()->flash('error', 'Backup not found.');
                $this->cancelDelete();
                return;
            }

            // Authorization check - delete requires admin permissions
            $this->authorize('delete', $backup);

            $backup->delete();

            // Invalidate cache since backup size changed
            $this->invalidateTotalSizeCache($tenant->id);

            session()->flash('success', 'Backup deleted.');
        } catch (\Exception $e) {
            Log::error('Failed to delete backup', [
                'backup_id' => $this->deletingBackupId,
                'error' => $e->getMessage(),
            ]);
            session()->flash('error', 'Failed to delete backup.');
        }

        $this->cancelDelete();
    }

    private function getTenant(): ?Tenant
    {
        $user = auth()->user();

        return $user?->currentTenant();
    }

    /**
     * Get cached total backup size for tenant.
     * Cache is invalidated when backups are created or deleted.
     */
    private function getCachedTotalSize(string $tenantId): int
    {
        $cacheKey = "tenant_{$tenantId}_backup_total_size";

        return Cache::remember($cacheKey, self::TOTAL_SIZE_CACHE_TTL, function () use ($tenantId) {
            return (int) DB::table('site_backups')
                ->join('sites', 'site_backups.site_id', '=', 'sites.id')
                ->where('sites.tenant_id', $tenantId)
                ->sum('site_backups.size_bytes');
        });
    }

    /**
     * Invalidate the total size cache for tenant.
     */
    private function invalidateTotalSizeCache(string $tenantId): void
    {
        Cache::forget("tenant_{$tenantId}_backup_total_size");
    }

    public function render()
    {
        try {
            $tenant = $this->getTenant();

            if (!$tenant) {
                return view('livewire.backups.backup-list', [
                    'backups' => collect(),
                    'sites' => collect(),
                    'totalSize' => 0,
                ])->layout('layouts.app', ['title' => 'Backups']);
            }

            // Get site IDs for tenant using a subquery instead of whereHas for better performance
            $tenantSiteIds = DB::table('sites')
                ->where('tenant_id', $tenant->id)
                ->pluck('id');

            // Fetch sites for filter dropdown
            $sites = $tenant->sites()->orderBy('domain')->get(['id', 'domain']);

            // Build optimized backup query using whereIn instead of whereHas
            $query = SiteBackup::whereIn('site_id', $tenantSiteIds)
                ->with('site:id,domain')
                ->orderBy('created_at', 'desc');

            if ($this->siteFilter) {
                $query->where('site_id', $this->siteFilter);
            }

            if ($this->typeFilter) {
                $query->where('backup_type', $this->typeFilter);
            }

            $backups = $query->paginate(15);

            // Get cached total backup size
            $totalSize = $this->getCachedTotalSize($tenant->id);

            return view('livewire.backups.backup-list', [
                'backups' => $backups,
                'sites' => $sites,
                'totalSize' => $totalSize,
            ])->layout('layouts.app', ['title' => 'Backups']);
        } catch (\Exception $e) {
            Log::error('Failed to load backup list', [
                'error' => $e->getMessage(),
            ]);

            return view('livewire.backups.backup-list', [
                'backups' => collect(),
                'sites' => collect(),
                'totalSize' => 0,
                'error' => 'Failed to load backups. Please try again.',
            ])->layout('layouts.app', ['title' => 'Backups']);
        }
    }
}
