<?php

declare(strict_types=1);

namespace App\Livewire\Admin;

use App\Models\TierLimit;
use Illuminate\Support\Facades\Log;
use Livewire\Component;

class PlanManagement extends Component
{
    public ?string $success = null;
    public ?string $error = null;

    // Edit modal
    public bool $showEditModal = false;
    public ?string $editingTier = null;
    public array $editForm = [
        'name' => '',
        'description' => '',
        'max_sites' => 0,
        'max_storage_gb' => 0,
        'max_bandwidth_gb' => 0,
        'backup_retention_days' => 7,
        'support_level' => 'community',
        'dedicated_ip' => false,
        'staging_environments' => false,
        'white_label' => false,
        'api_rate_limit_per_hour' => 1000,
        'price_monthly_cents' => 0,
        'start_date' => null,
        'end_date' => null,
        'is_active' => true,
        'unlimited_sites' => false,
        'unlimited_storage' => false,
        'unlimited_bandwidth' => false,
        'unlimited_api_rate' => false,
    ];

    // Create modal
    public bool $showCreateModal = false;
    public array $createForm = [
        'tier' => '',
        'name' => '',
        'description' => '',
        'max_sites' => 5,
        'max_storage_gb' => 10,
        'max_bandwidth_gb' => 100,
        'backup_retention_days' => 7,
        'support_level' => 'community',
        'dedicated_ip' => false,
        'staging_environments' => false,
        'white_label' => false,
        'api_rate_limit_per_hour' => 1000,
        'price_monthly_cents' => 2900,
        'start_date' => null,
        'end_date' => null,
        'is_active' => true,
        'unlimited_sites' => false,
        'unlimited_storage' => false,
        'unlimited_bandwidth' => false,
        'unlimited_api_rate' => false,
    ];

    protected function rules(): array
    {
        return [
            'editForm.name' => 'required|string|max:100',
            'editForm.description' => 'nullable|string|max:500',
            'editForm.max_sites' => 'required|integer|min:-1',
            'editForm.max_storage_gb' => 'required|integer|min:-1',
            'editForm.max_bandwidth_gb' => 'required|integer|min:-1',
            'editForm.backup_retention_days' => 'required|integer|min:1|max:365',
            'editForm.support_level' => 'required|in:community,standard,priority,dedicated',
            'editForm.dedicated_ip' => 'boolean',
            'editForm.staging_environments' => 'boolean',
            'editForm.white_label' => 'boolean',
            'editForm.api_rate_limit_per_hour' => 'required|integer|min:-1',
            'editForm.price_monthly_cents' => 'required|integer|min:0',
            'editForm.start_date' => 'nullable|date',
            'editForm.end_date' => 'nullable|date|after_or_equal:editForm.start_date',
            'editForm.is_active' => 'boolean',
        ];
    }

    public function openEditModal(string $tier): void
    {
        $plan = TierLimit::find($tier);

        if (!$plan) {
            $this->error = 'Plan not found.';
            return;
        }

        $this->editingTier = $tier;
        $this->editForm = [
            'name' => $plan->name,
            'description' => $plan->description ?? '',
            'max_sites' => $plan->max_sites === -1 ? 0 : $plan->max_sites,
            'max_storage_gb' => $plan->max_storage_gb === -1 ? 0 : $plan->max_storage_gb,
            'max_bandwidth_gb' => $plan->max_bandwidth_gb === -1 ? 0 : $plan->max_bandwidth_gb,
            'backup_retention_days' => $plan->backup_retention_days,
            'support_level' => $plan->support_level,
            'dedicated_ip' => $plan->dedicated_ip,
            'staging_environments' => $plan->staging_environments,
            'white_label' => $plan->white_label,
            'api_rate_limit_per_hour' => $plan->api_rate_limit_per_hour === -1 ? 0 : $plan->api_rate_limit_per_hour,
            'price_monthly_cents' => $plan->price_monthly_cents,
            'start_date' => $plan->start_date?->format('Y-m-d'),
            'end_date' => $plan->end_date?->format('Y-m-d'),
            'is_active' => $plan->is_active ?? true,
            'unlimited_sites' => $plan->max_sites === -1,
            'unlimited_storage' => $plan->max_storage_gb === -1,
            'unlimited_bandwidth' => $plan->max_bandwidth_gb === -1,
            'unlimited_api_rate' => $plan->api_rate_limit_per_hour === -1,
        ];
        $this->showEditModal = true;
    }

    public function closeEditModal(): void
    {
        $this->showEditModal = false;
        $this->editingTier = null;
        $this->resetValidation();
    }

    public function savePlan(): void
    {
        $this->validate();

        try {
            $plan = TierLimit::find($this->editingTier);

            if (!$plan) {
                $this->error = 'Plan not found.';
                return;
            }

            $plan->update([
                'name' => $this->editForm['name'],
                'description' => $this->editForm['description'] ?: null,
                'max_sites' => $this->editForm['unlimited_sites'] ? -1 : $this->editForm['max_sites'],
                'max_storage_gb' => $this->editForm['unlimited_storage'] ? -1 : $this->editForm['max_storage_gb'],
                'max_bandwidth_gb' => $this->editForm['unlimited_bandwidth'] ? -1 : $this->editForm['max_bandwidth_gb'],
                'backup_retention_days' => $this->editForm['backup_retention_days'],
                'support_level' => $this->editForm['support_level'],
                'dedicated_ip' => $this->editForm['dedicated_ip'],
                'staging_environments' => $this->editForm['staging_environments'],
                'white_label' => $this->editForm['white_label'],
                'api_rate_limit_per_hour' => $this->editForm['unlimited_api_rate'] ? -1 : $this->editForm['api_rate_limit_per_hour'],
                'price_monthly_cents' => $this->editForm['price_monthly_cents'],
                'start_date' => $this->editForm['start_date'] ?: null,
                'end_date' => $this->editForm['end_date'] ?: null,
                'is_active' => $this->editForm['is_active'],
            ]);

            $this->success = "Plan '{$plan->name}' updated successfully.";
            $this->closeEditModal();

            Log::info('Plan updated', [
                'tier' => $this->editingTier,
                'updated_by' => auth()->id(),
            ]);
        } catch (\Exception $e) {
            Log::error('Plan update error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to update plan: ' . $e->getMessage();
        }
    }

    public function openCreateModal(): void
    {
        $this->createForm = [
            'tier' => '',
            'name' => '',
            'max_sites' => 5,
            'max_storage_gb' => 10,
            'max_bandwidth_gb' => 100,
            'backup_retention_days' => 7,
            'support_level' => 'community',
            'dedicated_ip' => false,
            'staging_environments' => false,
            'white_label' => false,
            'api_rate_limit_per_hour' => 1000,
            'price_monthly_cents' => 2900,
            'unlimited_sites' => false,
            'unlimited_storage' => false,
            'unlimited_bandwidth' => false,
            'unlimited_api_rate' => false,
        ];
        $this->showCreateModal = true;
    }

    public function closeCreateModal(): void
    {
        $this->showCreateModal = false;
        $this->resetValidation();
    }

    public function createPlan(): void
    {
        $this->validate([
            'createForm.tier' => 'required|string|max:50|unique:tier_limits,tier',
            'createForm.name' => 'required|string|max:100',
            'createForm.description' => 'nullable|string|max:500',
            'createForm.max_sites' => 'required|integer|min:-1',
            'createForm.max_storage_gb' => 'required|integer|min:-1',
            'createForm.max_bandwidth_gb' => 'required|integer|min:-1',
            'createForm.backup_retention_days' => 'required|integer|min:1|max:365',
            'createForm.support_level' => 'required|in:community,standard,priority,dedicated',
            'createForm.price_monthly_cents' => 'required|integer|min:0',
            'createForm.start_date' => 'nullable|date',
            'createForm.end_date' => 'nullable|date|after_or_equal:createForm.start_date',
            'createForm.is_active' => 'boolean',
        ]);

        try {
            $plan = TierLimit::create([
                'tier' => strtolower($this->createForm['tier']),
                'name' => $this->createForm['name'],
                'description' => $this->createForm['description'] ?: null,
                'max_sites' => $this->createForm['unlimited_sites'] ? -1 : $this->createForm['max_sites'],
                'max_storage_gb' => $this->createForm['unlimited_storage'] ? -1 : $this->createForm['max_storage_gb'],
                'max_bandwidth_gb' => $this->createForm['unlimited_bandwidth'] ? -1 : $this->createForm['max_bandwidth_gb'],
                'backup_retention_days' => $this->createForm['backup_retention_days'],
                'support_level' => $this->createForm['support_level'],
                'dedicated_ip' => $this->createForm['dedicated_ip'],
                'staging_environments' => $this->createForm['staging_environments'],
                'white_label' => $this->createForm['white_label'],
                'api_rate_limit_per_hour' => $this->createForm['unlimited_api_rate'] ? -1 : $this->createForm['api_rate_limit_per_hour'],
                'price_monthly_cents' => $this->createForm['price_monthly_cents'],
                'start_date' => $this->createForm['start_date'] ?: null,
                'end_date' => $this->createForm['end_date'] ?: null,
                'is_active' => $this->createForm['is_active'],
            ]);

            $this->success = "Plan '{$plan->name}' created successfully.";
            $this->closeCreateModal();

            Log::info('Plan created', [
                'tier' => $plan->tier,
                'created_by' => auth()->id(),
            ]);
        } catch (\Exception $e) {
            Log::error('Plan creation error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to create plan: ' . $e->getMessage();
        }
    }

    public function deletePlan(string $tier): void
    {
        try {
            $plan = TierLimit::find($tier);

            if (!$plan) {
                $this->error = 'Plan not found.';
                return;
            }

            // Check if any tenants are using this plan
            $tenantCount = $plan->tenants()->count();
            if ($tenantCount > 0) {
                $this->error = "Cannot delete plan '{$plan->name}' because {$tenantCount} tenant(s) are using it.";
                return;
            }

            $name = $plan->name;
            $plan->delete();

            $this->success = "Plan '{$name}' deleted successfully.";

            Log::info('Plan deleted', [
                'tier' => $tier,
                'deleted_by' => auth()->id(),
            ]);
        } catch (\Exception $e) {
            Log::error('Plan deletion error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to delete plan: ' . $e->getMessage();
        }
    }

    public function render()
    {
        $plans = TierLimit::withCount('tenants')
            ->orderByRaw("CASE tier WHEN 'starter' THEN 1 WHEN 'pro' THEN 2 WHEN 'enterprise' THEN 3 ELSE 4 END")
            ->get();

        return view('livewire.admin.plan-management', [
            'plans' => $plans,
        ])->layout('layouts.admin', ['title' => 'Plan Management']);
    }
}
