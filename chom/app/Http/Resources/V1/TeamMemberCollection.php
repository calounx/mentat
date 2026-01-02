<?php

namespace App\Http\Resources\V1;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\ResourceCollection;

/**
 * Team Member Collection Resource
 *
 * Handles collection of team members with pagination metadata.
 */
class TeamMemberCollection extends ResourceCollection
{
    /**
     * The resource that this resource collects.
     *
     * @var string
     */
    public $collects = TeamMemberResource::class;

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
                    'total_members' => $this->total(),
                    'roles' => $this->getRoleSummary(),
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

    /**
     * Get role distribution summary.
     *
     * @return array<string, int>
     */
    protected function getRoleSummary(): array
    {
        return [
            'owners' => $this->collection->where('role', 'owner')->count(),
            'admins' => $this->collection->where('role', 'admin')->count(),
            'members' => $this->collection->where('role', 'member')->count(),
            'viewers' => $this->collection->where('role', 'viewer')->count(),
        ];
    }
}
