<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

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
            'avatar_url' => $this->when(
                isset($this->avatar_path),
                fn() => $this->avatar_path ? asset('storage/' . $this->avatar_path) : null
            ),

            // Team-specific role and permissions
            'role' => $this->when(
                $this->pivot && isset($this->pivot->role),
                fn() => $this->pivot->role
            ),

            'permissions' => $this->when(
                $this->relationLoaded('permissions'),
                fn() => $this->permissions->pluck('name')
            ),

            // Activity tracking
            'last_activity' => $this->when(
                isset($this->last_activity_at),
                fn() => [
                    'timestamp' => $this->last_activity_at?->toISOString(),
                    'relative' => $this->last_activity_at?->diffForHumans(),
                    'action' => $this->last_activity_type ?? null,
                ]
            ),

            // Team membership details
            'team_membership' => $this->when(
                $this->pivot,
                fn() => [
                    'joined_at' => $this->pivot->created_at?->toISOString() ?? null,
                    'invited_by' => $this->when(
                        isset($this->pivot->invited_by),
                        fn() => $this->pivot->invited_by
                    ),
                    'status' => $this->pivot->status ?? 'active',
                ]
            ),

            // Additional user metadata
            'meta' => [
                'is_online' => $this->isOnline(),
                'timezone' => $this->timezone ?? 'UTC',
                'two_factor_enabled' => $this->two_factor_enabled ?? false,
                'email_verified' => $this->email_verified_at !== null,
            ],

            // Timestamps
            'created_at' => $this->created_at?->toISOString(),
            'updated_at' => $this->updated_at?->toISOString(),
        ];
    }

    /**
     * Check if user is currently online (active within last 5 minutes).
     *
     * @return bool
     */
    protected function isOnline(): bool
    {
        if (!isset($this->last_activity_at)) {
            return false;
        }

        return $this->last_activity_at->diffInMinutes(now()) < 5;
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
