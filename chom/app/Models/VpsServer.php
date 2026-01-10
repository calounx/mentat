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
        'provider',
        'provider_id',
        'region',
        'spec_cpu',
        'spec_memory_mb',
        'spec_disk_gb',
        'status',
        'allocation_type',
        'vpsmanager_version',
        'observability_configured',
        'ssh_key_id',
        'ssh_user',
        'ssh_port',
        'last_health_check_at',
        'health_status',
        'health_error',
    ];

    protected $casts = [
        'spec_cpu' => 'integer',
        'spec_memory_mb' => 'integer',
        'spec_disk_gb' => 'integer',
        'ssh_port' => 'integer',
        'observability_configured' => 'boolean',
        'last_health_check_at' => 'datetime',
    ];

    /**
     * Get the sites on this VPS server.
     */
    public function sites(): HasMany
    {
        return $this->hasMany(Site::class, 'vps_id');
    }
}
