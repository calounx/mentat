@component('mail::message')
# Reset Your Password

Hello {{ $user_name }},

We received a request to reset your CHOM password. Click the button below to create a new password.

@component('mail::button', ['url' => $reset_url])
Reset Password
@endcomponent

**This link will expire in {{ $expires_in_minutes }} minutes.**

If you didn't request a password reset, you can safely ignore this email. Your account remains secure.

**Didn't recognize this request?** If you believe someone else is trying to access your account, please [contact our support team]({{ $app_url }}/support) immediately.

**Having trouble?** If you can't click the button above, copy and paste this URL into your browser:
{{ $reset_url }}

@component('mail::subcopy')
For security reasons, this password reset link will only work once. If you need to reset your password again, please visit [{{ $app_url }}]({{ $app_url }}) and use the "Forgot Password" option.
@endcomponent
@endcomponent
