<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Site Backup Model
 *
 * @property string $id
 * @property string $site_id
 * @property string $backup_type
 * @property string $status
 * @property int|null $size_mb
 * @property string|null $file_path
 */
class SiteBackup extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'site_id',
        'backup_type',
        'status',
        'size_mb',
        'file_path',
    ];

    protected $casts = [
        'size_mb' => 'integer',
    ];

    /**
     * Get the site that owns this backup.
     */
    public function site(): BelongsTo
    {
        return $this->belongsTo(Site::class);
    }
}
