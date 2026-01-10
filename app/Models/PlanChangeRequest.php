<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Facades\DB;

class PlanChangeRequest extends Model
{
    use HasUuids;

    public $timestamps = false;

    protected $fillable = [
        'tenant_id',
        'user_id',
        'current_tier',
        'requested_tier',
        'reason',
        'status',
        'requested_at',
        'reviewed_at',
        'reviewed_by',
        'reviewer_notes',
    ];

    protected $casts = [
        'requested_at' => 'datetime',
        'reviewed_at' => 'datetime',
    ];

    /**
     * Check if request is pending.
     */
    public function isPending(): bool
    {
        return $this->status === 'pending';
    }

    /**
     * Approve this plan change request and apply the change.
     */
    public function approve(User $reviewer, ?string $notes = null): void
    {
        DB::transaction(function () use ($reviewer, $notes) {
            $this->update([
                'status' => 'approved',
                'reviewed_at' => now(),
                'reviewed_by' => $reviewer->id,
                'reviewer_notes' => $notes,
            ]);

            // Apply the plan change to the tenant
            $this->tenant->update(['tier' => $this->requested_tier]);
        });
    }

    /**
     * Reject this plan change request.
     */
    public function reject(User $reviewer, string $reason): void
    {
        $this->update([
            'status' => 'rejected',
            'reviewed_at' => now(),
            'reviewed_by' => $reviewer->id,
            'reviewer_notes' => $reason,
        ]);
    }

    /**
     * Get the tenant this request belongs to.
     */
    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    /**
     * Get the user who made this request.
     */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /**
     * Get the user who reviewed this request.
     */
    public function reviewer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'reviewed_by');
    }
}
