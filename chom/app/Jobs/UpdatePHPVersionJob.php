<?php

declare(strict_types=1);

namespace App\Jobs;

use App\Models\Site;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;

class UpdatePHPVersionJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 3;
    public int $timeout = 300;

    public function __construct(
        public readonly Site $site,
        public readonly string $version
    ) {
    }

    public function handle(): void
    {
        try {
            Log::info('Updating PHP version', [
                'site_id' => $this->site->id,
                'version' => $this->version,
            ]);

            // Update PHP version in database
            $this->site->update([
                'php_version' => $this->version,
                'status' => 'active',
            ]);

            Log::info('PHP version updated successfully', [
                'site_id' => $this->site->id,
                'version' => $this->version,
            ]);
        } catch (\Exception $e) {
            Log::error('PHP version update failed', [
                'site_id' => $this->site->id,
                'version' => $this->version,
                'error' => $e->getMessage(),
            ]);

            $this->site->update(['status' => 'active']);
            throw $e;
        }
    }
}
