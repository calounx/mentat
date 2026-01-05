<?php

declare(strict_types=1);

namespace App\Livewire\Admin;

use App\Models\VpsServer;
use App\Services\Integration\VPSManagerBridge;
use Illuminate\Support\Facades\Log;
use Livewire\Component;
use Livewire\WithPagination;

class VpsManagement extends Component
{
    use WithPagination;

    // Filters
    public string $search = '';
    public string $statusFilter = '';
    public string $healthFilter = '';
    public string $providerFilter = '';

    // Selected VPS for actions
    public ?string $selectedVpsId = null;
    public array $vpsHealthData = [];
    public bool $showHealthModal = false;
    public bool $isLoadingHealth = false;

    // Form for add/edit
    public bool $showForm = false;
    public bool $isEditing = false;
    public array $formData = [
        'hostname' => '',
        'ip_address' => '',
        'provider' => 'custom',
        'region' => '',
        'spec_cpu' => 2,
        'spec_memory_mb' => 2048,
        'spec_disk_gb' => 40,
        'allocation_type' => 'shared',
    ];

    public ?string $error = null;
    public ?string $success = null;

    protected $queryString = [
        'search' => ['except' => ''],
        'statusFilter' => ['except' => ''],
        'healthFilter' => ['except' => ''],
        'providerFilter' => ['except' => ''],
    ];

    protected $rules = [
        'formData.hostname' => 'required|string|max:255',
        'formData.ip_address' => 'required|ip',
        'formData.provider' => 'required|string|in:hetzner,digitalocean,vultr,linode,custom',
        'formData.region' => 'nullable|string|max:50',
        'formData.spec_cpu' => 'required|integer|min:1|max:128',
        'formData.spec_memory_mb' => 'required|integer|min:512|max:524288',
        'formData.spec_disk_gb' => 'required|integer|min:10|max:10000',
        'formData.allocation_type' => 'required|in:shared,dedicated',
    ];

    public function updatingSearch(): void
    {
        $this->resetPage();
    }

    public function updatingStatusFilter(): void
    {
        $this->resetPage();
    }

    public function updatingHealthFilter(): void
    {
        $this->resetPage();
    }

    public function updatingProviderFilter(): void
    {
        $this->resetPage();
    }

    public function openAddForm(): void
    {
        $this->isEditing = false;
        $this->formData = [
            'hostname' => '',
            'ip_address' => '',
            'provider' => 'custom',
            'region' => '',
            'spec_cpu' => 2,
            'spec_memory_mb' => 2048,
            'spec_disk_gb' => 40,
            'allocation_type' => 'shared',
        ];
        $this->showForm = true;
        $this->error = null;
    }

    public function openEditForm(string $vpsId): void
    {
        $vps = VpsServer::findOrFail($vpsId);
        $this->isEditing = true;
        $this->selectedVpsId = $vpsId;
        $this->formData = [
            'hostname' => $vps->hostname,
            'ip_address' => $vps->ip_address,
            'provider' => $vps->provider,
            'region' => $vps->region ?? '',
            'spec_cpu' => $vps->spec_cpu,
            'spec_memory_mb' => $vps->spec_memory_mb,
            'spec_disk_gb' => $vps->spec_disk_gb,
            'allocation_type' => $vps->allocation_type,
        ];
        $this->showForm = true;
        $this->error = null;
    }

    public function closeForm(): void
    {
        $this->showForm = false;
        $this->selectedVpsId = null;
        $this->error = null;
    }

    public function saveVps(): void
    {
        $this->validate();
        $this->error = null;

        try {
            if ($this->isEditing && $this->selectedVpsId) {
                $vps = VpsServer::findOrFail($this->selectedVpsId);
                $vps->update($this->formData);
                $this->success = "VPS '{$vps->hostname}' updated successfully.";
            } else {
                // Check for duplicate hostname
                if (VpsServer::where('hostname', $this->formData['hostname'])->exists()) {
                    $this->error = 'A VPS with this hostname already exists.';
                    return;
                }

                $vps = VpsServer::create(array_merge($this->formData, [
                    'status' => 'provisioning',
                    'health_status' => 'unknown',
                ]));
                $this->success = "VPS '{$vps->hostname}' created successfully.";
            }

            $this->closeForm();
        } catch (\Exception $e) {
            Log::error('VPS save error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to save VPS: ' . $e->getMessage();
        }
    }

    public function viewHealth(string $vpsId): void
    {
        $this->selectedVpsId = $vpsId;
        $this->vpsHealthData = [];
        $this->showHealthModal = true;
        $this->isLoadingHealth = true;

        // Fetch health data
        $this->fetchHealthData();
    }

    public function fetchHealthData(): void
    {
        if (!$this->selectedVpsId) {
            return;
        }

        try {
            $vps = VpsServer::findOrFail($this->selectedVpsId);
            $bridge = app(VPSManagerBridge::class);

            $healthResult = $bridge->healthCheck($vps);
            $dashboardResult = $bridge->getDashboard($vps);

            $this->vpsHealthData = [
                'vps' => $vps,
                'health' => $healthResult['success'] ? $healthResult['data'] : null,
                'dashboard' => $dashboardResult['success'] ? $dashboardResult['data'] : null,
                'error' => (!$healthResult['success'] && !$dashboardResult['success'])
                    ? 'Failed to connect to VPS'
                    : null,
            ];
        } catch (\Exception $e) {
            Log::error('VPS health fetch error', [
                'vps_id' => $this->selectedVpsId,
                'error' => $e->getMessage(),
            ]);
            $this->vpsHealthData = [
                'error' => 'Failed to fetch health data: ' . $e->getMessage(),
            ];
        }

        $this->isLoadingHealth = false;
    }

    public function closeHealthModal(): void
    {
        $this->showHealthModal = false;
        $this->selectedVpsId = null;
        $this->vpsHealthData = [];
    }

    public function updateStatus(string $vpsId, string $status): void
    {
        try {
            $vps = VpsServer::findOrFail($vpsId);
            $vps->update(['status' => $status]);
            $this->success = "VPS '{$vps->hostname}' status updated to {$status}.";
        } catch (\Exception $e) {
            Log::error('VPS status update error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to update status: ' . $e->getMessage();
        }
    }

    public function testConnection(string $vpsId): void
    {
        try {
            $vps = VpsServer::findOrFail($vpsId);
            $bridge = app(VPSManagerBridge::class);

            if ($bridge->testConnection($vps)) {
                $this->success = "Connection to '{$vps->hostname}' successful!";
                $vps->update(['health_status' => 'healthy', 'last_health_check_at' => now()]);
            } else {
                $this->error = "Connection to '{$vps->hostname}' failed.";
                $vps->update(['health_status' => 'unhealthy', 'last_health_check_at' => now()]);
            }
        } catch (\Exception $e) {
            Log::error('VPS connection test error', ['error' => $e->getMessage()]);
            $this->error = 'Connection test failed: ' . $e->getMessage();
        }
    }

    public function deleteVps(string $vpsId): void
    {
        try {
            $vps = VpsServer::findOrFail($vpsId);

            // Check if VPS has sites
            if ($vps->sites()->count() > 0) {
                $this->error = "Cannot delete VPS '{$vps->hostname}' because it has {$vps->sites()->count()} active site(s).";
                return;
            }

            $hostname = $vps->hostname;
            $vps->delete();
            $this->success = "VPS '{$hostname}' deleted successfully.";
        } catch (\Exception $e) {
            Log::error('VPS delete error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to delete VPS: ' . $e->getMessage();
        }
    }

    public function render()
    {
        $query = VpsServer::query()
            ->withCount('sites');

        if ($this->search) {
            $query->where(function ($q) {
                $q->where('hostname', 'like', "%{$this->search}%")
                    ->orWhere('ip_address', 'like', "%{$this->search}%");
            });
        }

        if ($this->statusFilter) {
            $query->where('status', $this->statusFilter);
        }

        if ($this->healthFilter) {
            $query->where('health_status', $this->healthFilter);
        }

        if ($this->providerFilter) {
            $query->where('provider', $this->providerFilter);
        }

        $vpsServers = $query->orderBy('hostname')->paginate(15);

        // Get unique providers for filter dropdown
        $providers = VpsServer::distinct()->pluck('provider')->filter()->sort()->values();

        return view('livewire.admin.vps-management', [
            'vpsServers' => $vpsServers,
            'providers' => $providers,
        ])->layout('layouts.admin', ['title' => 'VPS Management']);
    }
}
