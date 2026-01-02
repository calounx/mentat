@component('mail::message')
# You're Invited to {{ $organization_name }}

Hello {{ $invitee_email }},

{{ $inviter_name }} has invited you to join **{{ $organization_name }}** on CHOM as a **{{ $role }}**.

CHOM is a powerful cPanel Hosting Operations Manager that helps teams manage and automate their hosting infrastructure.

@component('mail::button', ['url' => $accept_url])
Accept Invitation
@endcomponent

**Invitation Details:**
- Organization: {{ $organization_name }}
- Your Role: {{ $role }}
- Invited By: {{ $inviter_name }}
- Expires: {{ $expires_at }}

If you don't have a CHOM account yet, you'll be able to create one when you accept this invitation. Just click the button above and follow the signup process.

**Having trouble?** If you can't click the button above, copy and paste this URL into your browser:
{{ $accept_url }}

@component('mail::subcopy')
This invitation will expire on {{ $expires_at }}. If you believe you received this email in error or didn't request it, please ignore this message.
@endcomponent
@endcomponent
