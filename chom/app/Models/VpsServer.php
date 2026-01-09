<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * VPS Server Model
 *
 * @property string $id
 * @property string $hostname
 * @property string $ip_address
 * @property string $status
 * @property int $site_count
 */
class VpsServer extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'hostname',
        'ip_address',
        'status',
        'site_count',
    ];

    protected $casts = [
        'site_count' => 'integer',
    ];

    /**
     * Get the sites on this VPS server.
     */
    public function sites(): HasMany
    {
        return $this->hasMany(Site::class, 'vps_id');
    }
}
