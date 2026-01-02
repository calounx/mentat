<?php

namespace App\Http\Resources\V1;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\ResourceCollection;

/**
 * Team Invitation Collection Resource
 *
 * Handles collection of team invitations with pagination metadata.
 */
class TeamInvitationCollection extends ResourceCollection
{
    /**
     * The resource that this resource collects.
     *
     * @var string
     */
    public $collects = TeamInvitationResource::class;

    /**
     * Transform the resource collection into an array.
     *
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'data' => $this->collection,
            'meta' => [
                'pagination' => [
                    'total' => $this->total(),
                    'count' => $this->count(),
                    'per_page' => $this->perPage(),
                    'current_page' => $this->currentPage(),
                    'total_pages' => $this->lastPage(),
                    'has_more_pages' => $this->hasMorePages(),
                ],
                'summary' => [
                    'total_pending' => $this->collection->where('status.is_pending', true)->count(),
                    'total_expired' => $this->collection->where('status.is_expired', true)->count(),
                ],
            ],
        ];
    }

    /**
     * Get additional data that should be returned with the resource collection.
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
