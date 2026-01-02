# Email Configuration Guide

This guide walks you through setting up email services for CHOM to enable team invitations, password resets, and system notifications.

## Table of Contents

1. [Overview](#overview)
2. [Development Setup](#development-setup)
3. [Production Setup](#production-setup)
4. [Service Comparison](#service-comparison)
5. [Testing Email Delivery](#testing-email-delivery)
6. [Troubleshooting](#troubleshooting)

---

## Overview

CHOM supports multiple email services:

- **SendGrid** (Recommended) - 100 emails/day free tier, unlimited for 3 months
- **Mailgun** - 5,000 emails/month free tier
- **AWS SES** - 62,000 emails/month (free tier, first 12 months)
- **Postmark** - Premium option, 100 free emails for 30 days
- **SMTP** - Generic SMTP server
- **Log** - Development only, emails logged to `storage/logs/laravel.log`

### Email Use Cases in CHOM

1. **Team Invitations** - Invite team members to organizations
2. **Password Resets** - Send password reset links
3. **Notifications** - Site provisioning, backup completion alerts
4. **System Alerts** - Operations team notifications

---

## Development Setup

### Option 1: Log Emails (Simplest for Development)

Emails are logged instead of sent. Perfect for local development.

```bash
# In .env
MAIL_MAILER=log
```

View logged emails in `storage/logs/laravel.log`:

```bash
tail -f storage/logs/laravel.log
```

**Pros:**
- No external service needed
- No rate limits
- Fast iteration

**Cons:**
- Emails not actually sent
- Can't test real email delivery

### Option 2: MailHog (Realistic Testing)

MailHog is a local SMTP server with a web UI. Perfect for testing email content.

#### Setup MailHog

**Docker (Recommended):**

```bash
# In docker-compose.yml, it's already configured
docker-compose up -d mailhog

# Access MailHog UI at http://localhost:8025
```

**Manual Installation:**

```bash
# Download from https://github.com/mailhog/MailHog/releases
# Or install via Homebrew (macOS):
brew install mailhog

# Start MailHog
mailhog
```

#### Configure CHOM for MailHog

```bash
# In .env
MAIL_MAILER=smtp
MAIL_HOST=mailhog          # Use 'mailhog' in Docker, '127.0.0.1' if installed locally
MAIL_PORT=1025             # MailHog SMTP port
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=null
MAIL_FROM_ADDRESS="noreply@chom.local"
MAIL_FROM_NAME="CHOM"
```

#### Using MailHog

1. Send an email from the app (e.g., invite a team member)
2. Visit http://localhost:8025
3. Click "Latest" to see the email
4. Inspect the email content, headers, and HTML rendering

**Pros:**
- Realistic SMTP testing
- Can inspect email content
- Web UI for easy viewing

**Cons:**
- Requires Docker or manual installation
- Emails not actually delivered

### Option 3: Mailtrap (Cloud Sandbox)

Mailtrap provides a free cloud sandbox for testing emails.

#### Setup Mailtrap

1. Sign up at https://mailtrap.io/
2. Create a new inbox
3. Get SMTP credentials from "Integrations" > "Nodemailer"

#### Configure CHOM for Mailtrap

```bash
# In .env
MAIL_MAILER=smtp
MAIL_HOST=smtp.mailtrap.io
MAIL_PORT=465              # or 587 with encryption tls
MAIL_USERNAME=your_username
MAIL_PASSWORD=your_password
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS="noreply@example.com"
MAIL_FROM_NAME="CHOM"
```

**Pros:**
- Free cloud service
- No local setup needed
- Good for testing with team

**Cons:**
- Requires signup
- Rate limited on free tier

---

## Production Setup

### Recommendation: SendGrid

SendGrid is the recommended service for production because:

- Generous free tier (100 emails/day, unlimited for 3 months)
- Excellent deliverability
- Built-in SMTP relay and Web API
- Detailed bounce/complaint tracking
- Easy setup
- Affordable scaling

#### Setup SendGrid

##### Step 1: Create SendGrid Account

1. Sign up at https://sendgrid.com
2. Verify your email address
3. Complete the account setup

##### Step 2: Create API Key

1. Log in to SendGrid Dashboard
2. Navigate to **Settings > API Keys**
3. Click **Create API Key**
4. Give it a name (e.g., "CHOM Production")
5. Select **Full Access** (or customize permissions)
6. Copy the API key (you won't see it again!)

##### Step 3: Configure Environment

```bash
# In .env or your environment variables
MAIL_MAILER=sendgrid
SENDGRID_API_KEY=SG.your_api_key_here
MAIL_FROM_ADDRESS="noreply@yourdomain.com"
MAIL_FROM_NAME="CHOM"
```

##### Step 4: Verify Sender Domain (Recommended)

For best deliverability, verify your domain:

1. In SendGrid Dashboard, go to **Settings > Sender Authentication**
2. Click **Authenticate Your Domain**
3. Follow the DNS setup instructions
4. Add the provided DNS records to your domain
5. Wait for DNS propagation (usually 5-30 minutes)

This prevents emails from being flagged as spam.

##### Step 5: Test Configuration

```bash
php artisan tinker

# Send a test email
Mail::to('test@example.com')->send(new \App\Mail\TeamInvitationMail(...));
```

**SendGrid Pricing:**
- Free: 100 emails/day (unlimited for first 3 months)
- Pro: $30/month (unlimited emails, advanced features)

**API Documentation:**
https://docs.sendgrid.com/for-developers/sending-email/quickstart-php

---

### Alternative: Mailgun

Mailgun is another excellent option:

#### Step 1: Create Mailgun Account

1. Sign up at https://mailgun.com
2. Verify your email

#### Step 2: Get Credentials

1. In Mailgun Dashboard, go to **API > API Keys**
2. Copy your API Key
3. Note your domain (e.g., `sandbox12345.mailgun.org`)

#### Step 3: Configure Environment

```bash
# In .env
MAIL_MAILER=mailgun
MAILGUN_DOMAIN=sandbox12345.mailgun.org
MAILGUN_SECRET=key-xxxxxxxxxxxxxxxxxxxx
MAILGUN_ENDPOINT=api.mailgun.net          # api.eu.mailgun.net for EU region
MAIL_FROM_ADDRESS="noreply@yourdomain.com"
MAIL_FROM_NAME="CHOM"
```

#### Step 4: Verify Domain (Production)

For production, verify your custom domain:

1. In Mailgun Dashboard, go to **Sending > Domains**
2. Add your domain
3. Follow DNS setup instructions
4. Add the DNS records to your domain
5. Verify the domain

**Mailgun Pricing:**
- Free: 5,000 emails/month (with sandbox domain)
- Pro: $35/month for custom domain

**API Documentation:**
https://documentation.mailgun.com/en/latest/

---

### Alternative: AWS SES

If you're already using AWS:

#### Configuration

```bash
# In .env
MAIL_MAILER=ses
AWS_DEFAULT_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_SES_REGION=us-east-1
MAIL_FROM_ADDRESS="noreply@yourdomain.com"
MAIL_FROM_NAME="CHOM"
```

**Steps:**
1. Create IAM user with SES permissions
2. Get access key and secret
3. Verify sender email in AWS SES console
4. Request production access (remove sandbox restrictions)

**AWS SES Pricing:**
- Free: 62,000 emails/month (first 12 months)
- After: $0.10 per 1,000 emails

---

## Service Comparison

| Feature | SendGrid | Mailgun | AWS SES | Postmark |
|---------|----------|---------|---------|----------|
| Free Tier | 100/day (unlimited 3mo) | 5,000/month | 62,000/month* | 100 (30 days) |
| Setup Time | 5 minutes | 10 minutes | 15 minutes | 5 minutes |
| Deliverability | Excellent | Excellent | Very Good | Excellent |
| Support | Good | Excellent | AWS | Excellent |
| Webhook Support | Yes | Yes | Yes | Yes |
| SMTP Support | Yes | Yes | Yes | Yes |
| Web API | Yes | Yes | Yes | Yes |
| Price (Starter) | $30/month | $35/month | $0.10/1K | $15/month |
| Best For | General Use | Developers | AWS Users | Premium SLA |

*AWS free tier is for first 12 months only

---

## Testing Email Delivery

### 1. Unit Tests

Test email sending with Laravel's Mail fake:

```php
namespace Tests\Feature;

use Illuminate\Support\Facades\Mail;
use App\Mail\TeamInvitationMail;
use Tests\TestCase;

class EmailTest extends TestCase
{
    public function test_team_invitation_email_is_sent()
    {
        Mail::fake();

        // Trigger email sending
        $this->postJson('/api/v1/team/invite', [
            'email' => 'user@example.com',
            'role' => 'member',
        ]);

        // Assert email was sent
        Mail::assertSent(TeamInvitationMail::class);
    }

    public function test_password_reset_email_contains_reset_link()
    {
        Mail::fake();

        // Trigger password reset
        $this->postJson('/api/v1/auth/forgot-password', [
            'email' => 'user@example.com',
        ]);

        Mail::assertSent(PasswordResetMail::class, function ($mail) {
            return str_contains($mail->render(), 'reset');
        });
    }
}
```

Run tests:

```bash
php artisan test

# Or specific test file:
php artisan test tests/Feature/EmailTest.php
```

### 2. Manual Testing

#### Send Test Email via Artisan

```bash
php artisan tinker

# Test team invitation
use App\Models\{User, Organization, TeamInvitation};
use App\Mail\TeamInvitationMail;
use Illuminate\Support\Facades\Mail;

$org = Organization::first();
$user = User::first();
$invitation = TeamInvitation::factory()->create();

Mail::to('test@example.com')->send(
    new TeamInvitationMail($invitation, $org, $user, 'https://...')
);
```

#### Send Actual API Request

```bash
# Invite a team member (triggers email)
curl -X POST http://localhost:8000/api/v1/team/invite \
  -H "Authorization: Bearer your_token" \
  -H "Content-Type: application/json" \
  -d '{"email":"newmember@example.com","role":"member"}'
```

Then check:
- MailHog UI: http://localhost:8025
- Mailtrap UI: https://mailtrap.io
- SendGrid Dashboard: https://app.sendgrid.com
- Logs: `tail -f storage/logs/laravel.log`

### 3. Integration Testing

Test the complete flow:

```bash
# 1. Start queue worker
php artisan queue:work

# 2. In another terminal, trigger an invitation
php artisan tinker

# This will queue the email
Mail::queue(new TeamInvitationMail(...));

# Check your email service dashboard
```

### 4. Email Deliverability Checklist

Before going to production:

- [ ] DKIM record added to DNS
- [ ] SPF record added to DNS
- [ ] DMARC policy configured
- [ ] Domain verified in email service
- [ ] Test email received in inbox (not spam)
- [ ] Unsubscribe link included in bulk emails
- [ ] Reply-to address configured
- [ ] Email templates tested on mobile/desktop

---

## Troubleshooting

### Email Not Sending

#### Check Configuration

```bash
php artisan tinker

# Check which mailer is active
echo config('mail.default');  # Should show your mailer name

# Check specific mailer config
echo config('mail.mailers.sendgrid');
```

#### Check Queue Worker

If using queued emails:

```bash
# Ensure queue worker is running
ps aux | grep queue:work

# If not running, start it:
php artisan queue:work

# Or for development:
php artisan queue:work --sleep=3
```

#### Check Logs

```bash
# View recent logs
tail -100 storage/logs/laravel.log

# Filter for mail errors
grep -i "mail\|email" storage/logs/laravel.log | tail -50
```

### API Key Issues

#### Invalid SendGrid API Key

Error: `401 Unauthorized`

Solution:
1. Verify API key in SendGrid Dashboard
2. Check for typos in `.env`
3. Ensure API key starts with `SG.`
4. Verify API key hasn't been revoked

#### Invalid Mailgun Credentials

Error: `401 Unauthorized` or `422 Unprocessable Entity`

Solution:
1. Check domain is in Mailgun account
2. Verify API key in Dashboard
3. Check endpoint (api.mailgun.net vs api.eu.mailgun.net)
4. Ensure domain hasn't expired

### Emails Going to Spam

#### Check SPF/DKIM/DMARC

Most likely cause: Sender domain not authenticated.

**Solution:**
1. Verify domain in your email service (SendGrid, Mailgun, etc.)
2. Add SPF record: `v=spf1 include:sendgrid.net ~all`
3. Enable DKIM in service dashboard
4. Add DMARC policy: `v=DMARC1; p=none`

#### Check Email Content

Common spam triggers:
- Excessive links
- Attachments
- Suspicious sender name
- All caps subject
- Too many images

**Solution:** Review email templates in `resources/views/emails/`

### Rate Limiting

Error: `429 Too Many Requests`

Solution:
1. Check rate limits in email service dashboard
2. Implement email queuing properly
3. Use Laravel queue system with workers
4. Consider upgrade plan if exceeding limits

### DNS Issues

Cannot verify domain:

```bash
# Check your DNS records
nslookup example.com

# Verify SPF record
nslookup -type=TXT example.com | grep spf

# Verify DKIM records (example: selector1)
nslookup selector1._domainkey.example.com
```

Ensure all DNS records are propagated (may take 24-48 hours).

### Testing in Development

If emails aren't appearing in MailHog:

1. Restart MailHog:
   ```bash
   docker-compose restart mailhog
   ```

2. Check Laravel is configured correctly:
   ```php
   MAIL_HOST=mailhog  # Must match Docker service name
   MAIL_PORT=1025
   ```

3. Check queue is running (if using Mail::queue):
   ```bash
   php artisan queue:work
   ```

---

## Common Patterns

### Send Email Immediately

```php
Mail::send(new TeamInvitationMail(...));
```

### Queue Email for Later

```php
Mail::queue(new TeamInvitationMail(...));
```

### Send with Custom Headers

```php
Mail::to($recipient)
    ->withSymfonyMessage(function ($message) {
        $message->getHeaders()->addTextHeader('X-Custom', 'value');
    })
    ->send(new TeamInvitationMail(...));
```

### Handle Email Failures

```php
try {
    Mail::send(new TeamInvitationMail(...));
} catch (\Exception $e) {
    Log::error('Email send failed: ' . $e->getMessage());
    // Optionally: notify user or retry later
}
```

---

## Environment Variables Summary

```bash
# Required for all mailers
MAIL_FROM_ADDRESS=noreply@example.com
MAIL_FROM_NAME=CHOM

# Select mailer
MAIL_MAILER=sendgrid  # or mailgun, ses, postmark, smtp, log

# SendGrid
SENDGRID_API_KEY=SG.xxxx

# Mailgun
MAILGUN_DOMAIN=sandboxxx.mailgun.org
MAILGUN_SECRET=key-xxxx
MAILGUN_ENDPOINT=api.mailgun.net

# AWS SES
AWS_DEFAULT_REGION=us-east-1
AWS_ACCESS_KEY_ID=xxxx
AWS_SECRET_ACCESS_KEY=xxxx

# Generic SMTP
MAIL_SCHEME=tls
MAIL_HOST=smtp.example.com
MAIL_PORT=587
MAIL_USERNAME=user@example.com
MAIL_PASSWORD=password
MAIL_ENCRYPTION=tls
```

---

## Next Steps

1. **Choose a service** - SendGrid recommended for most use cases
2. **Create account** - Sign up and get API credentials
3. **Configure .env** - Add credentials to environment
4. **Test locally** - Use MailHog or Log driver first
5. **Deploy to production** - Update production environment variables
6. **Monitor** - Use service dashboard to track delivery

For questions or issues, refer to:
- SendGrid Docs: https://docs.sendgrid.com
- Mailgun Docs: https://documentation.mailgun.com
- Laravel Mail: https://laravel.com/docs/mail
