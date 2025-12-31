<?php

namespace App\Providers;

use Illuminate\Foundation\Support\Providers\EventServiceProvider as ServiceProvider;

/**
 * Event Service Provider
 *
 * Registers all event listeners for the CHOM platform using explicit registration.
 *
 * Design Decision: Explicit Registration vs Auto-Discovery
 * - Better IDE support (autocomplete, navigation, refactoring)
 * - Clear event→listener mapping in one place
 * - Slightly better performance (no directory scanning)
 * - Easier debugging and understanding of event flow
 *
 * @package App\Providers
 */
class EventServiceProvider extends ServiceProvider
{
    /**
     * The event to listener mappings for the application.
     *
     * Format: EventClass::class => [ListenerClass::class, AnotherListenerClass::class]
     *
     * Listener method naming:
     * - Use '@handleEventName' syntax for specific event handlers
     * - Without @method, Laravel calls handle() by default
     *
     * @var array<class-string, array<int, class-string|string>>
     */
    protected $listen = [
        // Site Events
        \App\Events\Site\SiteCreated::class => [
            \App\Listeners\UpdateTenantMetrics::class . '@handleSiteCreated',
            \App\Listeners\RecordAuditLog::class,
            \App\Listeners\RecordMetrics::class . '@handleSiteCreated',
        ],

        \App\Events\Site\SiteProvisioned::class => [
            \App\Listeners\RecordAuditLog::class,
            \App\Listeners\SendNotification::class . '@handleSiteProvisioned',
            \App\Listeners\RecordMetrics::class . '@handleSiteProvisioned',
        ],

        \App\Events\Site\SiteProvisioningFailed::class => [
            \App\Listeners\RecordAuditLog::class,
            \App\Listeners\SendNotification::class . '@handleSiteProvisioningFailed',
            \App\Listeners\RecordMetrics::class . '@handleSiteProvisioningFailed',
        ],

        \App\Events\Site\SiteDeleted::class => [
            \App\Listeners\UpdateTenantMetrics::class . '@handleSiteDeleted',
            \App\Listeners\RecordAuditLog::class,
            \App\Listeners\RecordMetrics::class . '@handleSiteDeleted',
        ],

        // Backup Events
        \App\Events\Backup\BackupCreated::class => [
            \App\Listeners\RecordAuditLog::class,
        ],

        \App\Events\Backup\BackupCompleted::class => [
            \App\Listeners\RecordAuditLog::class,
            \App\Listeners\SendNotification::class . '@handleBackupCompleted',
            \App\Listeners\RecordMetrics::class . '@handleBackupCompleted',
        ],

        \App\Events\Backup\BackupFailed::class => [
            \App\Listeners\RecordAuditLog::class,
            \App\Listeners\SendNotification::class . '@handleBackupFailed',
            \App\Listeners\RecordMetrics::class . '@handleBackupFailed',
        ],

        // Future Events:
        // - Team Events (TeamMemberRoleChanged, TeamMemberRemoved, OwnershipTransferred)
        // - SSL Events (SslCertificateRequested, SslCertificateIssued, SslCertificateExpiring)
        // - Security Events (VpsCredentialsRotated, ApiTokenRotated)
        // - Quota Events (SiteQuotaExceeded, StorageQuotaExceeded)
    ];

    /**
     * Register any events for your application.
     */
    public function boot(): void
    {
        parent::boot();
    }

    /**
     * Determine if events and listeners should be automatically discovered.
     *
     * We use explicit registration for better control and IDE support.
     *
     * @return bool
     */
    public function shouldDiscoverEvents(): bool
    {
        return false;
    }
}
