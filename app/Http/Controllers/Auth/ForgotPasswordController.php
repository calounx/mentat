<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Password;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Validation\ValidationException;

class ForgotPasswordController extends Controller
{
    /**
     * Display the forgot password form.
     */
    public function showLinkRequestForm()
    {
        return view('auth.forgot-password');
    }

    /**
     * Send a reset link to the given user.
     */
    public function sendResetLinkEmail(Request $request)
    {
        $request->validate([
            'email' => ['required', 'email'],
        ]);

        // Rate limiting: 3 requests per 60 minutes
        $throttleKey = 'password-reset:' . $request->ip();

        if (RateLimiter::tooManyAttempts($throttleKey, 3)) {
            $seconds = RateLimiter::availableIn($throttleKey);
            $minutes = ceil($seconds / 60);

            throw ValidationException::withMessages([
                'email' => ["Too many password reset attempts. Please try again in {$minutes} minutes."],
            ]);
        }

        // We will send the password reset link to this user. Once we have attempted
        // to send the link, we will examine the response then see the message we
        // need to show to the user. Finally, we'll send out a proper response.
        $status = Password::sendResetLink(
            $request->only('email')
        );

        if ($status === Password::RESET_LINK_SENT) {
            // Increment rate limiter on successful attempt
            RateLimiter::hit($throttleKey, 3600); // 60 minutes in seconds

            return back()->with('status', __($status));
        }

        // For security, always show the same message even if email doesn't exist
        // This prevents email enumeration attacks
        return back()->with('status', 'We have emailed your password reset link if that email exists in our system.');
    }

    /**
     * Clear the rate limiter for testing purposes.
     * This method should only be used in testing/development.
     */
    public function clearRateLimiter(Request $request)
    {
        if (app()->environment('production')) {
            abort(404);
        }

        $throttleKey = 'password-reset:' . $request->ip();
        RateLimiter::clear($throttleKey);

        return response()->json(['message' => 'Rate limiter cleared']);
    }
}
