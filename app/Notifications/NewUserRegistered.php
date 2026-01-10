<?php

namespace App\Notifications;

use App\Models\Organization;
use App\Models\User;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class NewUserRegistered extends Notification
{
    use Queueable;

    /**
     * Create a new notification instance.
     */
    public function __construct(
        public User $user,
        public Organization $organization
    ) {
    }

    /**
     * Get the notification's delivery channels.
     *
     * @return array<int, string>
     */
    public function via(object $notifiable): array
    {
        return ['mail'];
    }

    /**
     * Get the mail representation of the notification.
     */
    public function toMail(object $notifiable): MailMessage
    {
        $ficfictiveLabel = $this->organization->isFictive() ? ' (Fictive)' : '';

        return (new MailMessage)
            ->subject('New User Pending Approval - CHOM')
            ->greeting('New Registration')
            ->line('A new user has registered and is pending approval.')
            ->line("**Username:** {$this->user->username}")
            ->line("**Name:** {$this->user->fullName()}")
            ->line("**Email:** {$this->user->email}")
            ->line("**Organization:** {$this->organization->name}{$ficfictiveLabel}")
            ->line("**Registered:** {$this->user->created_at->diffForHumans()}")
            ->action('Review in Admin Panel', url('/admin/pending-approvals'))
            ->line('Please review this application and approve or reject it.');
    }

    /**
     * Get the array representation of the notification.
     *
     * @return array<string, mixed>
     */
    public function toArray(object $notifiable): array
    {
        return [
            'user_id' => $this->user->id,
            'username' => $this->user->username,
            'name' => $this->user->fullName(),
            'email' => $this->user->email,
            'organization_id' => $this->organization->id,
            'organization_name' => $this->organization->name,
            'is_fictive' => $this->organization->isFictive(),
        ];
    }
}
