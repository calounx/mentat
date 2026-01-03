<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\ResourceCollection;

class SiteCollection extends ResourceCollection
{
    /**
     * The resource that this resource collects.
     *
     * @var string
     */
    public $collects = SiteResource::class;

    /**
     * Transform the resource collection into an array.
     *
     * @return array<int|string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'data' => $this->collection,
            'meta' => [
                'total' => $this->collection->count(),
                'filters_applied' => $this->getAppliedFilters($request),
            ],
        ];
    }

    /**
     * Get the additional data that should be returned with the resource array.
     *
     * @return array<string, mixed>
     */
    public function with(Request $request): array
    {
        return [
            'version' => '1.0',
            'links' => [
                'self' => $request->url(),
                'docs' => url('/api/docs/sites'),
            ],
            'summary' => $this->getSummary(),
        ];
    }

    /**
     * Get applied filters from request.
     *
     * @param Request $request
     * @return array<string, mixed>
     */
    protected function getAppliedFilters(Request $request): array
    {
        $filters = [];

        if ($request->has('status')) {
            $filters['status'] = $request->query('status');
        }

        if ($request->has('vps_server_id')) {
            $filters['vps_server_id'] = $request->query('vps_server_id');
        }

        if ($request->has('search')) {
            $filters['search'] = $request->query('search');
        }

        return $filters;
    }

    /**
     * Get collection summary statistics.
     *
     * @return array<string, mixed>
     */
    protected function getSummary(): array
    {
        $statusCounts = $this->collection
            ->groupBy('status')
            ->map(fn($group) => $group->count());

        return [
            'total_sites' => $this->collection->count(),
            'active_sites' => $statusCounts['active'] ?? 0,
            'inactive_sites' => $statusCounts['inactive'] ?? 0,
            'pending_sites' => $statusCounts['pending'] ?? 0,
        ];
    }
}
