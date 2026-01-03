<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\ResourceCollection;

class BackupCollection extends ResourceCollection
{
    /**
     * The resource that this resource collects.
     *
     * @var string
     */
    public $collects = BackupResource::class;

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
                'total_size' => $this->getTotalSize(),
                'total_size_formatted' => $this->formatBytes($this->getTotalSize()),
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
                'docs' => url('/api/docs/backups'),
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

        if ($request->has('type')) {
            $filters['type'] = $request->query('type');
        }

        if ($request->has('site_id')) {
            $filters['site_id'] = $request->query('site_id');
        }

        if ($request->has('date_from')) {
            $filters['date_from'] = $request->query('date_from');
        }

        if ($request->has('date_to')) {
            $filters['date_to'] = $request->query('date_to');
        }

        return $filters;
    }

    /**
     * Get total size of all backups in collection.
     *
     * @return int
     */
    protected function getTotalSize(): int
    {
        return $this->collection->sum('size') ?? 0;
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

        $typeCounts = $this->collection
            ->groupBy('type')
            ->map(fn($group) => $group->count());

        return [
            'total_backups' => $this->collection->count(),
            'completed_backups' => $statusCounts['completed'] ?? 0,
            'pending_backups' => $statusCounts['pending'] ?? 0,
            'failed_backups' => $statusCounts['failed'] ?? 0,
            'by_type' => [
                'full' => $typeCounts['full'] ?? 0,
                'incremental' => $typeCounts['incremental'] ?? 0,
                'database' => $typeCounts['database'] ?? 0,
                'files' => $typeCounts['files'] ?? 0,
            ],
        ];
    }

    /**
     * Format bytes to human-readable format.
     *
     * @param int $bytes
     * @param int $precision
     * @return string
     */
    protected function formatBytes(int $bytes, int $precision = 2): string
    {
        $units = ['B', 'KB', 'MB', 'GB', 'TB'];

        for ($i = 0; $bytes > 1024 && $i < count($units) - 1; $i++) {
            $bytes /= 1024;
        }

        return round($bytes, $precision) . ' ' . $units[$i];
    }
}
