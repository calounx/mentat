<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Site Model
 *
 * Represents a hosted website (WordPress, Laravel, or HTML site).
 *
 * @property string $id
 * @property string $tenant_id
 * @property string $vps_id
 * @property string $domain
 * @property string $site_type
 * @property string $php_version
 * @property bool $ssl_enabled
 * @property \Carbon\Carbon|null $ssl_expires_at
 * @property string $status
 * @property string|null $document_root
 * @property string|null $db_name
 * @property string|null $db_user
 * @property int $storage_used_mb
 * @property array|null $settings
 */
class Site extends Model
{
    use HasFactory, HasUuids, SoftDeletes;

    protected $fillable = [
        'tenant_id',
        'vps_id',
        'domain',
        'site_type',
        'php_version',
        'ssl_enabled',
        'ssl_expires_at',
        'status',
        'document_root',
        'db_name',
        'db_user',
        'storage_used_mb',
        'settings',
    ];

    protected $casts = [
        'ssl_enabled' => 'boolean',
        'ssl_expires_at' => 'datetime',
        'storage_used_mb' => 'integer',
        'settings' => 'array',
    ];

    /**
     * Get the tenant that owns the site.
     */
    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    /**
     * Get the VPS server hosting this site.
     */
    public function vpsServer(): BelongsTo
    {
        return $this->belongsTo(VpsServer::class, 'vps_id');
    }

    /**
     * Get the backups for this site.
     */
    public function backups(): HasMany
    {
        return $this->hasMany(SiteBackup::class);
    }

    /**
     * Get the SSL certificate for this site.
     */
    public function sslCertificate(): BelongsTo
    {
        return $this->belongsTo(SslCertificate::class);
    }
}
