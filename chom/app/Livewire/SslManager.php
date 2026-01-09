<?php

declare(strict_types=1);

namespace App\Livewire;

use App\Models\Site;
use App\Models\Tenant;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Livewire\Component;

/**
 * SSL Manager Component
 *
 * Manages SSL certificates for sites through the CHOM API.
 * Provides real-time status updates and operations like issue, renew, and auto-renewal configuration.
 */
class SslManager extends Component
{
    public string $siteId;
    public ?array $sslStatus = null;
    public bool $processing = false;
    public int $renewalDays = 30;
    public bool $autoRenewEnabled = false;
    public ?string $errorMessage = null;
    public ?string $successMessage = null;

    protected $listeners = ['refreshStatus'];

    /**
     * Initialize component with site validation
     *
     * @param Site $site
     * @return void
     */
    public function mount(Site $site): void
    {
        // Verify tenant access
        $tenant = $this->getTenant();

        if ($site->tenant_id !== $tenant->id) {
            abort(403, 'You do not have access to this site.');
        }

        $this->siteId = $site->id;
        $this->refreshStatus();
    }

    /**
     * Get current tenant from authenticated user
     *
     * @return Tenant
     */
    protected function getTenant(): Tenant
    {
        $user = auth()->user();

        if (!$user || !$user->current_tenant_id) {
            abort(401, 'No tenant context available.');
        }

        $tenant = Tenant::find($user->current_tenant_id);

        if (!$tenant) {
            abort(401, 'Invalid tenant context.');
        }

        return $tenant;
    }

    /**
     * Refresh SSL status from API
     *
     * @return void
     */
    public function refreshStatus(): void
    {
        try {
            $response = Http::withToken($this->getApiToken())
                ->get(config('app.url') . "/api/v1/sites/{$this->siteId}/ssl/status");

            if ($response->successful()) {
                $this->sslStatus = $response->json('data');
                $this->autoRenewEnabled = $this->sslStatus['auto_renew_enabled'] ?? false;
                $this->errorMessage = null;
            } else {
                $this->handleApiError($response);
            }
        } catch (\Exception $e) {
            Log::error('Failed to fetch SSL status', [
                'site_id' => $this->siteId,
                'error' => $e->getMessage(),
            ]);
            $this->errorMessage = 'Failed to fetch SSL status. Please try again.';
        }
    }

    /**
     * Issue new SSL certificate
     *
     * @return void
     */
    public function issueSSL(): void
    {
        $this->processing = true;
        $this->errorMessage = null;
        $this->successMessage = null;

        try {
            $response = Http::withToken($this->getApiToken())
                ->post(config('app.url') . "/api/v1/sites/{$this->siteId}/ssl/issue");

            if ($response->successful()) {
                $this->successMessage = 'SSL certificate is being issued. This may take a few minutes.';
                $this->dispatch('ssl-issued');

                // Refresh status after a delay
                $this->dispatch('refresh-status-delayed', ['delay' => 5000]);
            } else {
                $this->handleApiError($response);
            }
        } catch (\Exception $e) {
            Log::error('Failed to issue SSL certificate', [
                'site_id' => $this->siteId,
                'error' => $e->getMessage(),
            ]);
            $this->errorMessage = 'Failed to issue SSL certificate. Please try again.';
        } finally {
            $this->processing = false;
        }
    }

    /**
     * Renew existing SSL certificate
     *
     * @return void
     */
    public function renewSSL(): void
    {
        $this->processing = true;
        $this->errorMessage = null;
        $this->successMessage = null;

        try {
            $response = Http::withToken($this->getApiToken())
                ->post(config('app.url') . "/api/v1/sites/{$this->siteId}/ssl/renew");

            if ($response->successful()) {
                $this->successMessage = 'SSL certificate is being renewed. This may take a few minutes.';
                $this->dispatch('ssl-renewed');

                // Refresh status after a delay
                $this->dispatch('refresh-status-delayed', ['delay' => 5000]);
            } else {
                $this->handleApiError($response);
            }
        } catch (\Exception $e) {
            Log::error('Failed to renew SSL certificate', [
                'site_id' => $this->siteId,
                'error' => $e->getMessage(),
            ]);
            $this->errorMessage = 'Failed to renew SSL certificate. Please try again.';
        } finally {
            $this->processing = false;
        }
    }

    /**
     * Toggle auto-renewal setting
     *
     * @return void
     */
    public function toggleAutoRenew(): void
    {
        $this->processing = true;
        $this->errorMessage = null;

        try {
            $response = Http::withToken($this->getApiToken())
                ->patch(config('app.url') . "/api/v1/sites/{$this->siteId}/ssl/auto-renew", [
                    'enabled' => !$this->autoRenewEnabled,
                    'renewal_days' => $this->renewalDays,
                ]);

            if ($response->successful()) {
                $this->autoRenewEnabled = !$this->autoRenewEnabled;
                $this->successMessage = $this->autoRenewEnabled
                    ? 'Auto-renewal enabled successfully.'
                    : 'Auto-renewal disabled successfully.';
                $this->dispatch('auto-renew-toggled');
            } else {
                $this->handleApiError($response);
            }
        } catch (\Exception $e) {
            Log::error('Failed to toggle auto-renewal', [
                'site_id' => $this->siteId,
                'error' => $e->getMessage(),
            ]);
            $this->errorMessage = 'Failed to update auto-renewal setting. Please try again.';
        } finally {
            $this->processing = false;
        }
    }

    /**
     * Get SSL status badge color
     *
     * @return string
     */
    public function getStatusColor(): string
    {
        if (!$this->sslStatus || !isset($this->sslStatus['status'])) {
            return 'gray';
        }

        return match($this->sslStatus['status']) {
            'valid' => 'green',
            'expiring_soon' => 'yellow',
            'expired' => 'red',
            default => 'gray',
        };
    }

    /**
     * Get SSL status text
     *
     * @return string
     */
    public function getStatusText(): string
    {
        if (!$this->sslStatus || !isset($this->sslStatus['status'])) {
            return 'No Certificate';
        }

        return match($this->sslStatus['status']) {
            'valid' => 'Valid',
            'expiring_soon' => 'Expiring Soon',
            'expired' => 'Expired',
            default => 'Unknown',
        };
    }

    /**
     * Check if certificate exists
     *
     * @return bool
     */
    public function hasCertificate(): bool
    {
        return $this->sslStatus !== null
            && isset($this->sslStatus['domain'])
            && $this->sslStatus['status'] !== 'none';
    }

    /**
     * Check if certificate can be renewed
     *
     * @return bool
     */
    public function canRenew(): bool
    {
        return $this->hasCertificate()
            && in_array($this->sslStatus['status'] ?? '', ['valid', 'expiring_soon', 'expired']);
    }

    /**
     * Get API token for authenticated user
     *
     * @return string
     */
    protected function getApiToken(): string
    {
        $user = auth()->user();

        // Get or create a personal access token
        $token = $user->tokens()->where('name', 'livewire-api-token')->first();

        if (!$token) {
            $token = $user->createToken('livewire-api-token');
        }

        return $token->plainTextToken ?? $token->accessToken ?? '';
    }

    /**
     * Handle API error response
     *
     * @param \Illuminate\Http\Client\Response $response
     * @return void
     */
    protected function handleApiError($response): void
    {
        $errorData = $response->json();
        $this->errorMessage = $errorData['message'] ?? 'An error occurred. Please try again.';

        Log::warning('SSL Manager API error', [
            'site_id' => $this->siteId,
            'status' => $response->status(),
            'error' => $errorData,
        ]);
    }

    /**
     * Render the component
     *
     * @return \Illuminate\View\View
     */
    public function render()
    {
        return view('livewire.ssl-manager');
    }
}
