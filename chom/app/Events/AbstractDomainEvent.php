<?php

namespace App\Events;

use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

/**
 * Base class for all domain events in CHOM.
 *
 * Design Principles:
 * - SerializesModels: Allows events to be queued with Eloquent models
 * - Timestamp tracking: Every event knows when it occurred
 * - Actor tracking: Records who/what triggered the event (user ID or system)
 * - Metadata support: Provides structured event data for logging and auditing
 *
 * @package App\Events
 */
abstract class AbstractDomainEvent
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    /**
     * The timestamp when this event occurred.
     */
    public readonly \DateTimeInterface $occurredAt;

    /**
     * The ID of the actor who triggered this event (user ID or null for system).
     */
    public readonly ?string $actorId;

    /**
     * The type of actor ('user' or 'system').
     */
    public readonly string $actorType;

    /**
     * Create a new domain event instance.
     *
     * @param string|null $actorId The ID of the user/actor, or null for system events
     * @param string $actorType The type of actor ('user' or 'system')
     */
    public function __construct(
        ?string $actorId = null,
        string $actorType = 'user'
    ) {
        $this->occurredAt = now();
        $this->actorId = $actorId ?? auth()->id();
        $this->actorType = $actorType;
    }

    /**
     * Get event metadata for logging, auditing, and tracing.
     *
     * Child classes should override this and merge with parent metadata
     * to include event-specific data.
     *
     * @return array<string, mixed>
     */
    public function getMetadata(): array
    {
        return [
            'event' => static::class,
            'occurred_at' => $this->occurredAt->toIso8601String(),
            'actor_id' => $this->actorId,
            'actor_type' => $this->actorType,
        ];
    }

    /**
     * Get the human-readable event name.
     *
     * Returns the class basename (e.g., "SiteCreated" from "App\Events\Site\SiteCreated").
     *
     * @return string
     */
    public function getEventName(): string
    {
        return class_basename(static::class);
    }
}
