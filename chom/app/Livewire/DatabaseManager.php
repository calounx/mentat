<?php

declare(strict_types=1);

namespace App\Livewire;

use App\Models\Site;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Livewire\Component;
use Symfony\Component\HttpKernel\Exception\HttpException;

/**
 * DatabaseManager Livewire Component
 *
 * Provides database management functionality for sites including:
 * - Database exports (structure, data, full)
 * - Database optimization
 * - Export history tracking
 * - Download exports
 *
 * @package App\Livewire
 */
class DatabaseManager extends Component
{
    /**
     * Site ID
     *
     * @var string
     */
    public string $siteId;

    /**
     * Export history (recent exports)
     *
     * @var array
     */
    public array $exportHistory = [];

    /**
     * Optimization history
     *
     * @var array
     */
    public array $optimizationHistory = [];

    /**
     * Processing state
     *
     * @var bool
     */
    public bool $processing = false;

    /**
     * Export type (structure_only, data_only, full)
     *
     * @var string
     */
    public string $exportType = 'full';

    /**
     * Database information
     *
     * @var array|null
     */
    public ?array $databaseInfo = null;

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
        $this->loadDatabaseInfo();
        $this->loadHistory();
    }

    /**
     * Load database information
     *
     * @return void
     */
    public function loadDatabaseInfo(): void
    {
        try {
            $response = Http::withToken($this->getApiToken())
                ->get(config('app.api_url') . "/api/v1/sites/{$this->siteId}/database/info");

            if ($response->successful()) {
                $this->databaseInfo = $response->json('data');
            }
        } catch (\Exception $e) {
            Log::error('Failed to load database info', [
                'site_id' => $this->siteId,
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * Export database
     *
     * @return void
     */
    public function exportDatabase(): void
    {
        $this->resetMessages();
        $this->processing = true;

        try {
            $response = Http::withToken($this->getApiToken())
                ->post(config('app.api_url') . "/api/v1/sites/{$this->siteId}/database/export", [
                    'type' => $this->exportType,
                ]);

            if ($response->successful()) {
                $this->successMessage = 'Database export started successfully. You will be notified when it completes.';
                $this->loadHistory();
            } else {
                $this->errorMessage = $response->json('message') ?? 'Failed to export database.';
            }
        } catch (\Exception $e) {
            Log::error('Database export failed', [
                'site_id' => $this->siteId,
                'type' => $this->exportType,
                'error' => $e->getMessage(),
            ]);
            $this->errorMessage = 'An error occurred while exporting the database.';
        } finally {
            $this->processing = false;
        }
    }

    /**
     * Optimize database
     *
     * @return void
     */
    public function optimizeDatabase(): void
    {
        $this->resetMessages();
        $this->processing = true;

        try {
            $response = Http::withToken($this->getApiToken())
                ->post(config('app.api_url') . "/api/v1/sites/{$this->siteId}/database/optimize");

            if ($response->successful()) {
                $this->successMessage = 'Database optimization started successfully.';
                $this->loadHistory();
            } else {
                $this->errorMessage = $response->json('message') ?? 'Failed to optimize database.';
            }
        } catch (\Exception $e) {
            Log::error('Database optimization failed', [
                'site_id' => $this->siteId,
                'error' => $e->getMessage(),
            ]);
            $this->errorMessage = 'An error occurred while optimizing the database.';
        } finally {
            $this->processing = false;
        }
    }

    /**
     * Download export
     *
     * @param string $exportId
     * @return \Symfony\Component\HttpFoundation\StreamedResponse|void
     */
    public function downloadExport(string $exportId)
    {
        try {
            $response = Http::withToken($this->getApiToken())
                ->get(config('app.api_url') . "/api/v1/sites/{$this->siteId}/database/exports/{$exportId}/download");

            if ($response->successful()) {
                return response()->streamDownload(function () use ($response) {
                    echo $response->body();
                }, 'database-export-' . $exportId . '.sql.gz');
            } else {
                $this->errorMessage = 'Failed to download export.';
            }
        } catch (\Exception $e) {
            Log::error('Export download failed', [
                'site_id' => $this->siteId,
                'export_id' => $exportId,
                'error' => $e->getMessage(),
            ]);
            $this->errorMessage = 'An error occurred while downloading the export.';
        }
    }

    /**
     * Load history of operations
     *
     * @return void
     */
    public function loadHistory(): void
    {
        try {
            // Load export history
            $exportResponse = Http::withToken($this->getApiToken())
                ->get(config('app.api_url') . "/api/v1/sites/{$this->siteId}/database/exports", [
                    'limit' => 10,
                ]);

            if ($exportResponse->successful()) {
                $this->exportHistory = $exportResponse->json('data') ?? [];
            }

            // Load optimization history
            $optimizationResponse = Http::withToken($this->getApiToken())
                ->get(config('app.api_url') . "/api/v1/sites/{$this->siteId}/database/optimizations", [
                    'limit' => 10,
                ]);

            if ($optimizationResponse->successful()) {
                $this->optimizationHistory = $optimizationResponse->json('data') ?? [];
            }
        } catch (\Exception $e) {
            Log::error('Failed to load operation history', [
                'site_id' => $this->siteId,
                'error' => $e->getMessage(),
            ]);
        }
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
        return view('livewire.database-manager');
    }
}
