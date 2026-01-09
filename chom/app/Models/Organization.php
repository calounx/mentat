<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Organization Model
 *
 * Represents a top-level organization that contains tenants and users.
 *
 * @property string $id
 * @property string $name
 * @property string|null $domain
 * @property array|null $settings
 */
class Organization extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'name',
        'domain',
        'settings',
    ];

    protected $casts = [
        'settings' => 'array',
    ];

    /**
     * Get the tenants for this organization.
     */
    public function tenants(): HasMany
    {
        return $this->hasMany(Tenant::class);
    }

    /**
     * Get the users for this organization.
     */
    public function users(): HasMany
    {
        return $this->hasMany(User::class);
    }
}
