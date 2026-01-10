<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class RejectedEmail extends Model
{
    use HasUuids;

    public $timestamps = false;

    protected $fillable = [
        'email',
        'user_id',
        'rejection_reason',
        'rejected_at',
        'rejected_by',
        'attempts',
    ];

    protected $casts = [
        'rejected_at' => 'datetime',
        'attempts' => 'integer',
    ];

    /**
     * Check if an email address has been rejected.
     */
    public static function isRejected(string $email): bool
    {
        return self::where('email', $email)->exists();
    }

    /**
     * Track a rejected email address.
     */
    public static function trackRejection(
        string $email,
        ?string $userId,
        string $reason,
        string $rejectedBy
    ): void {
        $existing = self::where('email', $email)->first();

        if ($existing) {
            $existing->increment('attempts');
        } else {
            self::create([
                'email' => $email,
                'user_id' => $userId,
                'rejection_reason' => $reason,
                'rejected_at' => now(),
                'rejected_by' => $rejectedBy,
                'attempts' => 1,
            ]);
        }
    }

    /**
     * Get the user associated with this rejected email.
     */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /**
     * Get the user who rejected this email.
     */
    public function rejector(): BelongsTo
    {
        return $this->belongsTo(User::class, 'rejected_by');
    }
}
