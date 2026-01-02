<?php

namespace App\Http\Resources\V1;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Team Member API Resource
 *
 * Transforms User model into consistent JSON API response format for team management.
 */
class TeamMemberResource extends JsonResource
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
            'email' => $this->email,
            'role' => $this->role,
            'email_verified' => !is_null($this->email_verified_at),
            'email_verified_at' => $this->email_verified_at?->toIso8601String(),
            'two_factor_enabled' => $this->two_factor_enabled,
            'created_at' => $this->created_at->toIso8601String(),
            'updated_at' => $this->updated_at->toIso8601String(),

            // Include organization info when loaded
            'organization' => $this->when($this->relationLoaded('organization'), function () {
                return [
                    'id' => $this->organization->id,
                    'name' => $this->organization->name,
                    'slug' => $this->organization->slug,
                ];
            }),

            // Include permissions/capabilities for the member
            'permissions' => [
                'can_manage_sites' => $this->canManageSites(),
                'can_manage_team' => $this->isAdmin(),
                'is_owner' => $this->isOwner(),
                'is_admin' => $this->isAdmin(),
                'is_viewer' => $this->isViewer(),
            ],

            // Include operations count for detailed view
            'operations_count' => $this->when(
                $request->routeIs('team.show') && $this->relationLoaded('operations'),
                fn() => $this->operations->count()
            ),
        ];
    }

    /**
     * Get additional data that should be returned with the resource array.
     *
     * @return array<string, mixed>
     */
    public function with(Request $request): array
    {
        return [
            'success' => true,
        ];
    }
}
