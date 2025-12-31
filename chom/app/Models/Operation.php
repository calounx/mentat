<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Operation extends Model
{
    use HasFactory, HasUuids;

    /**
     * Boot the model and register global scopes for tenant isolation.
     */
    protected static function booted(): void
    {
        // Apply tenant scope automatically to all queries
        static::addGlobalScope('tenant', function ($builder) {
            if (auth()->check() && auth()->user()->currentTenant()) {
                $builder->where('tenant_id', auth()->user()->currentTenant()->id);
            }
        });
    }

    protected $fillable = [
        'tenant_id',
        'user_id',
        'operation_type',
        'target_type',
        'target_id',
        'status',
        'input_data',
        'output_data',
        'error_message',
        'started_at',
        'completed_at',
    ];

    protected function casts(): array
    {
        return [
            'input_data' => 'array',
            'output_data' => 'array',
            'started_at' => 'datetime',
            'completed_at' => 'datetime',
        ];
    }

    /**
     * Get the tenant this operation belongs to.
     */
    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    /**
     * Get the user who initiated this operation.
     */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /**
     * Check if the operation is pending.
     */
    public function isPending(): bool
    {
        return $this->status === 'pending';
    }

    /**
     * Check if the operation is running.
     */
    public function isRunning(): bool
    {
        return $this->status === 'running';
    }

    /**
     * Check if the operation is completed.
     */
    public function isCompleted(): bool
    {
        return $this->status === 'completed';
    }

    /**
     * Check if the operation has failed.
     */
    public function isFailed(): bool
    {
        return $this->status === 'failed';
    }

    /**
     * Check if the operation was cancelled.
     */
    public function isCancelled(): bool
    {
        return $this->status === 'cancelled';
    }

    /**
     * Check if the operation is still in progress.
     */
    public function isInProgress(): bool
    {
        return in_array($this->status, ['pending', 'running']);
    }

    /**
     * Check if the operation has finished (regardless of outcome).
     */
    public function isFinished(): bool
    {
        return in_array($this->status, ['completed', 'failed', 'cancelled']);
    }

    /**
     * Mark the operation as running.
     */
    public function markAsRunning(): self
    {
        $this->update([
            'status' => 'running',
            'started_at' => now(),
        ]);

        return $this;
    }

    /**
     * Mark the operation as completed.
     */
    public function markAsCompleted(?array $outputData = null): self
    {
        $this->update([
            'status' => 'completed',
            'output_data' => $outputData,
            'completed_at' => now(),
        ]);

        return $this;
    }

    /**
     * Mark the operation as failed.
     */
    public function markAsFailed(string $errorMessage, ?array $outputData = null): self
    {
        $this->update([
            'status' => 'failed',
            'error_message' => $errorMessage,
            'output_data' => $outputData,
            'completed_at' => now(),
        ]);

        return $this;
    }

    /**
     * Mark the operation as cancelled.
     */
    public function markAsCancelled(): self
    {
        $this->update([
            'status' => 'cancelled',
            'completed_at' => now(),
        ]);

        return $this;
    }

    /**
     * Get the duration of the operation in seconds.
     */
    public function getDurationInSeconds(): ?int
    {
        if (!$this->started_at) {
            return null;
        }

        $endTime = $this->completed_at ?? now();
        return $this->started_at->diffInSeconds($endTime);
    }

    /**
     * Scope to filter by operation type.
     */
    public function scopeOfType($query, string $operationType)
    {
        return $query->where('operation_type', $operationType);
    }

    /**
     * Scope to filter by status.
     */
    public function scopeWithStatus($query, string $status)
    {
        return $query->where('status', $status);
    }

    /**
     * Scope to get pending operations.
     */
    public function scopePending($query)
    {
        return $query->where('status', 'pending');
    }

    /**
     * Scope to get running operations.
     */
    public function scopeRunning($query)
    {
        return $query->where('status', 'running');
    }

    /**
     * Scope to get failed operations.
     */
    public function scopeFailed($query)
    {
        return $query->where('status', 'failed');
    }

    /**
     * Scope to filter by target.
     */
    public function scopeForTarget($query, string $targetType, string $targetId)
    {
        return $query->where('target_type', $targetType)
            ->where('target_id', $targetId);
    }
}
