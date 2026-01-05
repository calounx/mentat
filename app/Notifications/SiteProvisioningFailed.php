<?php

namespace App\Notifications;

use App\Models\Site;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class SiteProvisioningFailed extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(
        public Site $site,
        public string $failureReason,
        public array $healingAttempts = []
    ) {}

    public function via(object $notifiable): array
    {
        return ['mail', 'database'];
    }

    public function toMail(object $notifiable): MailMessage
    {
        $message = (new MailMessage)
            ->error()
            ->subject("Site Provisioning Failed: {$this->site->domain}")
            ->greeting('Site Provisioning Failed')
            ->line("The site **{$this->site->domain}** failed to provision after all retry attempts.")
            ->line("**Tenant:** " . ($this->site->tenant->name ?? 'Unknown'))
            ->line("**VPS:** " . ($this->site->vpsServer->hostname ?? 'Unknown'))
            ->line("**Site Type:** " . ucfirst($this->site->site_type))
            ->line("**Failure Reason:** {$this->failureReason}");

        if (!empty($this->healingAttempts)) {
            $message->line('---')
                ->line('**Self-Healing Actions Attempted:**');

            foreach ($this->healingAttempts as $attempt) {
                $status = $attempt['success'] ? 'Success' : 'Failed';
                $message->line("- [{$status}] {$attempt['action']}: {$attempt['result']}");
            }
        }

        $message->action('View in Admin Panel', url('/admin/sites'))
            ->line('Please investigate and take manual action if needed.');

        return $message;
    }

    public function toArray(object $notifiable): array
    {
        return [
            'type' => 'site_provisioning_failed',
            'site_id' => $this->site->id,
            'domain' => $this->site->domain,
            'tenant_id' => $this->site->tenant_id,
            'vps_id' => $this->site->vps_id,
            'failure_reason' => $this->failureReason,
            'healing_attempts' => $this->healingAttempts,
        ];
    }
}
