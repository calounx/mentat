<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

/**
 * SSL Certificate Model
 *
 * @property string $id
 * @property string $domain
 * @property \Carbon\Carbon|null $expires_at
 */
class SslCertificate extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'domain',
        'expires_at',
    ];

    protected $casts = [
        'expires_at' => 'datetime',
    ];
}
