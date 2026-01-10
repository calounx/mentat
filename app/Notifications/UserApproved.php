<?php

namespace App\Notifications;

use App\Models\Organization;
use App\Models\User;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class UserApproved extends Notification
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
        return (new MailMessage)
            ->subject('Your CHOM Account Has Been Approved!')
            ->greeting("Hello {$this->user->first_name}!")
            ->line('Great news! Your CHOM account has been approved.')
            ->line("**Organization:** {$this->organization->name}")
            ->line('You can now log in and select your plan to get started.')
            ->action('Login to CHOM', url('/login'))
            ->line('After logging in, you will be prompted to select a plan before you can create sites.')
            ->line('Thank you for choosing CHOM!');
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
            'organization_id' => $this->organization->id,
            'organization_name' => $this->organization->name,
        ];
    }
}
