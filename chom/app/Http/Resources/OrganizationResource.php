<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class OrganizationResource extends JsonResource
{
    /**
     * Transform the resource into an array.
     *
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'slug' => $this->slug,
            'logo_url' => $this->when(
                isset($this->logo_path),
                fn() => $this->logo_path ? asset('storage/' . $this->logo_path) : null
            ),

            // Subscription information
            'subscription' => [
                'tier' => $this->subscription_tier ?? 'free',
                'status' => $this->subscription_status ?? 'active',
                'current_period_end' => $this->when(
                    isset($this->subscription_end_at),
                    fn() => $this->subscription_end_at?->toISOString()
                ),
                'trial_ends_at' => $this->when(
                    isset($this->trial_ends_at),
                    fn() => $this->trial_ends_at?->toISOString()
                ),
            ],

            // Usage metrics
            'usage_metrics' => [
                'sites_count' => $this->when(
                    $this->relationLoaded('sites'),
                    fn() => $this->sites->count(),
                    fn() => $this->sites_count ?? 0
                ),
                'sites_limit' => $this->getSitesLimit(),
                'storage_used_gb' => $this->storage_used_gb ?? 0,
                'storage_limit_gb' => $this->getStorageLimit(),
                'bandwidth_used_gb' => $this->bandwidth_used_gb ?? 0,
                'bandwidth_limit_gb' => $this->getBandwidthLimit(),
                'team_members_count' => $this->when(
                    $this->relationLoaded('users'),
                    fn() => $this->users->count(),
                    fn() => $this->team_members_count ?? 0
                ),
                'team_members_limit' => $this->getTeamMembersLimit(),
            ],

            // Tenant information
            'tenant_count' => $this->when(
                $this->relationLoaded('tenants'),
                fn() => $this->tenants->count()
            ),

            // Team members (conditionally loaded)
            'team_members' => $this->when(
                $request->query('include') === 'team_members' && $this->relationLoaded('users'),
                fn() => TeamMemberResource::collection($this->users)
            ),

            // Sites (conditionally loaded)
            'sites' => $this->when(
                $request->query('include') === 'sites' && $this->relationLoaded('sites'),
                fn() => SiteResource::collection($this->sites)
            ),

            // Organization settings
            'settings' => [
                'timezone' => $this->timezone ?? 'UTC',
                'currency' => $this->currency ?? 'USD',
                'two_factor_required' => $this->two_factor_required ?? false,
                'auto_backup_enabled' => $this->auto_backup_enabled ?? true,
                'backup_retention_days' => $this->backup_retention_days ?? 30,
            ],

            // Billing information (conditionally shown to admins)
            'billing' => $this->when(
                $request->user()?->can('manage-billing', $this->resource),
                fn() => [
                    'payment_method_type' => $this->payment_method_type ?? null,
                    'payment_method_last4' => $this->payment_method_last4 ?? null,
                    'billing_email' => $this->billing_email ?? $this->email,
                    'billing_address' => $this->billing_address ?? null,
                ]
            ),

            // Timestamps
            'created_at' => $this->created_at?->toISOString(),
            'updated_at' => $this->updated_at?->toISOString(),
        ];
    }

    /**
     * Get sites limit based on subscription tier.
     *
     * @return int
     */
    protected function getSitesLimit(): int
    {
        return match ($this->subscription_tier ?? 'free') {
            'free' => 1,
            'starter' => 5,
            'professional' => 20,
            'enterprise' => 100,
            default => 1,
        };
    }

    /**
     * Get storage limit based on subscription tier.
     *
     * @return int
     */
    protected function getStorageLimit(): int
    {
        return match ($this->subscription_tier ?? 'free') {
            'free' => 5,
            'starter' => 50,
            'professional' => 200,
            'enterprise' => 1000,
            default => 5,
        };
    }

    /**
     * Get bandwidth limit based on subscription tier.
     *
     * @return int
     */
    protected function getBandwidthLimit(): int
    {
        return match ($this->subscription_tier ?? 'free') {
            'free' => 10,
            'starter' => 100,
            'professional' => 500,
            'enterprise' => 5000,
            default => 10,
        };
    }

    /**
     * Get team members limit based on subscription tier.
     *
     * @return int
     */
    protected function getTeamMembersLimit(): int
    {
        return match ($this->subscription_tier ?? 'free') {
            'free' => 1,
            'starter' => 5,
            'professional' => 15,
            'enterprise' => 100,
            default => 1,
        };
    }

    /**
     * Get additional data that should be returned with the resource array.
     *
     * @return array<string, mixed>
     */
    public function with(Request $request): array
    {
        return [
            'version' => '1.0',
        ];
    }
}
