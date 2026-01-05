<?php

declare(strict_types=1);

namespace App\Livewire\Profile;

use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\Rules\Password;
use Livewire\Component;

class ProfileSettings extends Component
{
    public ?string $success = null;
    public ?string $error = null;

    // Profile fields
    public string $name = '';
    public string $email = '';

    // Password change fields
    public string $current_password = '';
    public string $new_password = '';
    public string $new_password_confirmation = '';

    public function mount(): void
    {
        $user = auth()->user();
        $this->name = $user->name;
        $this->email = $user->email;
    }

    public function updateProfile(): void
    {
        $this->validate([
            'name' => 'required|string|max:255',
            'email' => 'required|email|unique:users,email,' . auth()->id(),
        ]);

        try {
            $user = auth()->user();
            $user->update([
                'name' => $this->name,
                'email' => $this->email,
            ]);

            $this->success = 'Profile updated successfully.';
            $this->error = null;

            Log::info('User profile updated', [
                'user_id' => $user->id,
            ]);
        } catch (\Exception $e) {
            Log::error('Profile update error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to update profile: ' . $e->getMessage();
        }
    }

    public function updatePassword(): void
    {
        $this->validate([
            'current_password' => 'required',
            'new_password' => ['required', 'confirmed', Password::min(8)->mixedCase()->numbers()],
        ]);

        try {
            $user = auth()->user();

            // Verify current password
            if (!Hash::check($this->current_password, $user->password)) {
                $this->addError('current_password', 'The current password is incorrect.');
                return;
            }

            // Update password
            $user->update([
                'password' => Hash::make($this->new_password),
            ]);

            // Clear password fields
            $this->reset(['current_password', 'new_password', 'new_password_confirmation']);

            $this->success = 'Password updated successfully.';
            $this->error = null;

            Log::info('User password changed', [
                'user_id' => $user->id,
            ]);
        } catch (\Exception $e) {
            Log::error('Password update error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to update password: ' . $e->getMessage();
        }
    }

    public function render()
    {
        return view('livewire.profile.profile-settings')
            ->layout('layouts.app', ['title' => 'Profile Settings']);
    }
}
