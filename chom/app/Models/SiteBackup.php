<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SiteBackup extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'site_id',
        'filename',
        'backup_type',
        'status',
        'storage_path',
        'size_bytes',
        'size_mb',
        'checksum',
        'retention_days',
        'expires_at',
        'completed_at',
        'error_message',
    ];

    protected $casts = [
        'expires_at' => 'datetime',
        'completed_at' => 'datetime',
    ];

    protected $hidden = [
        'storage_path',
        'checksum',
    ];

    public function site(): BelongsTo
    {
        return $this->belongsTo(Site::class);
    }

    public function isExpired(): bool
    {
        return $this->expires_at && $this->expires_at->isPast();
    }

    public function getSizeFormatted(): string
    {
        $bytes = $this->size_bytes;
        if ($bytes >= 1073741824) {
            return round($bytes / 1073741824, 2).' GB';
        }
        if ($bytes >= 1048576) {
            return round($bytes / 1048576, 2).' MB';
        }

        return round($bytes / 1024, 2).' KB';
    }
}
