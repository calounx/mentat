<?php

declare(strict_types=1);

namespace App\Livewire;

use App\Models\Site;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Livewire\Component;
use Symfony\Component\HttpKernel\Exception\HttpException;

/**
 * CacheManager Livewire Component
 *
 * Provides cache management functionality for sites including:
 * - Clear cache by type (all, opcache, redis, file)
 * - View cache statistics
 * - Track cache clearing operations
 *
 * @package App\Livewire
 */
class CacheManager extends Component
{
    /**
     * Site ID
     *
     * @var string
     */
    public string $siteId;

    /**
     * Cache statistics (size, hit rate, keys count)
     *
     * @var array
     */
    public array $cacheStats = [];

    /**
     * Processing state
     *
     * @var bool
     */
    public bool $processing = false;

    /**
     * Show confirmation modal
     *
     * @var bool
     */
    public bool $showConfirmModal = false;

    /**
     * Type of cache to clear (for confirmation)
     *
     * @var string|null
     */
    public ?string $clearType = null;

    /**
     * Error message
     *
     * @var string|null
     */
    public ?string $errorMessage = null;

    /**
     * Success message
     *
     * @var string|null
     */
    public ?string $successMessage = null;

    /**
     * Last cleared timestamp
     *
     * @var string|null
     */
    public ?string $lastCleared = null;

    /**
     * Mount the component
     *
     * @param Site $site
     * @return void
     * @throws HttpException
     */
    public function mount(Site $site): void
    {
        // Verify tenant access
        $user = auth()->user();
        if (!$user) {
            throw new HttpException(401, 'Unauthenticated.');
        }

        $tenant = $user->currentTenant ?? $user->tenant ?? null;
        if (!$tenant) {
            throw new HttpException(403, 'No active tenant found.');
        }

        if ($site->tenant_id !== $tenant->id) {
            throw new HttpException(403, 'You do not have access to this site.');
        }

        $this->siteId = $site->id;
        $this->refreshStats();
    }

    /**
     * Refresh cache statistics
     *
     * @return void
     */
    public function refreshStats(): void
    {
        try {
            $response = Http::withToken($this->getApiToken())
                ->get(config('app.api_url') . "/api/v1/sites/{$this->siteId}/cache/stats");

            if ($response->successful()) {
                $data = $response->json('data');
                $this->cacheStats = $data['stats'] ?? [];
                $this->lastCleared = $data['last_cleared'] ?? null;
            }
        } catch (\Exception $e) {
            Log::error('Failed to load cache stats', [
                'site_id' => $this->siteId,
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * Prompt for cache clear confirmation
     *
     * @param string $type
     * @return void
     */
    public function promptClearCache(string $type): void
    {
        // Only show confirmation for 'all' type
        if ($type === 'all') {
            $this->clearType = $type;
            $this->showConfirmModal = true;
        } else {
            $this->clearCache($type);
        }
    }

    /**
     * Clear cache by type
     *
     * @param string $type
     * @return void
     */
    public function clearCache(string $type): void
    {
        $this->resetMessages();
        $this->processing = true;
        $this->showConfirmModal = false;

        try {
            $response = Http::withToken($this->getApiToken())
                ->post(config('app.api_url') . "/api/v1/sites/{$this->siteId}/cache/clear", [
                    'type' => $type,
                ]);

            if ($response->successful()) {
                $this->successMessage = match($type) {
                    'all' => 'All cache cleared successfully.',
                    'opcache' => 'OPcache cleared successfully.',
                    'redis' => 'Redis cache cleared successfully.',
                    'file' => 'File cache cleared successfully.',
                    default => 'Cache cleared successfully.',
                };
                $this->refreshStats();
            } else {
                $this->errorMessage = $response->json('message') ?? 'Failed to clear cache.';
            }
        } catch (\Exception $e) {
            Log::error('Cache clear failed', [
                'site_id' => $this->siteId,
                'type' => $type,
                'error' => $e->getMessage(),
            ]);
            $this->errorMessage = 'An error occurred while clearing the cache.';
        } finally {
            $this->processing = false;
            $this->clearType = null;
        }
    }

    /**
     * Cancel clear cache confirmation
     *
     * @return void
     */
    public function cancelClearCache(): void
    {
        $this->showConfirmModal = false;
        $this->clearType = null;
    }

    /**
     * Get API token for authenticated requests
     *
     * @return string
     */
    protected function getApiToken(): string
    {
        return auth()->user()->api_token ?? session('api_token') ?? '';
    }

    /**
     * Reset messages
     *
     * @return void
     */
    protected function resetMessages(): void
    {
        $this->errorMessage = null;
        $this->successMessage = null;
    }

    /**
     * Render the component
     *
     * @return \Illuminate\View\View
     */
    public function render()
    {
        return view('livewire.cache-manager');
    }
}
