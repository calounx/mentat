<?php

namespace App\Http\Resources\V1;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Team Invitation API Resource
 *
 * Transforms TeamInvitation model into consistent JSON API response format.
 */
class TeamInvitationResource extends JsonResource
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
            'email' => $this->email,
            'role' => $this->role,
            'token' => $this->when(
                // Only show token in response when creating invitation
                $request->routeIs('team.invite'),
                $this->token
            ),
            'expires_at' => $this->expires_at->toIso8601String(),
            'accepted_at' => $this->accepted_at?->toIso8601String(),
            'created_at' => $this->created_at->toIso8601String(),

            // Include inviter information when loaded
            'invited_by' => $this->when($this->relationLoaded('inviter'), function () {
                return [
                    'id' => $this->inviter->id,
                    'name' => $this->inviter->name,
                    'email' => $this->inviter->email,
                ];
            }),

            // Status flags
            'status' => [
                'is_pending' => $this->isValid(),
                'is_expired' => $this->isExpired(),
                'is_accepted' => !is_null($this->accepted_at),
            ],

            // Time until expiration (in human readable format)
            'expires_in_human' => $this->expires_at->diffForHumans(),
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
