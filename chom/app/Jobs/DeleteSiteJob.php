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
use Illuminate\Support\Facades\Storage;

class DeleteSiteJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 3;
    public int $timeout = 600;

    public function __construct(
        public readonly Site $site
    ) {
    }

    public function handle(): void
    {
        try {
            Log::info('Deleting site', [
                'site_id' => $this->site->id,
                'domain' => $this->site->domain,
            ]);

            // Delete all backups
            foreach ($this->site->backups as $backup) {
                if ($backup->storage_path && Storage::disk('backups')->exists($backup->storage_path)) {
                    Storage::disk('backups')->delete($backup->storage_path);
                }
                $backup->delete();
            }

            // Soft delete the site
            $this->site->delete();

            Log::info('Site deleted successfully', [
                'site_id' => $this->site->id,
            ]);
        } catch (\Exception $e) {
            Log::error('Site deletion failed', [
                'site_id' => $this->site->id,
                'error' => $e->getMessage(),
            ]);

            $this->site->update(['status' => 'active']);
            throw $e;
        }
    }
}
