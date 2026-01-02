# Email Service Setup - Quick Start Guide

## Overview

The CHOM application now has production-ready email service support for team invitations and password resets. This guide will get you started in under 10 minutes.

## Quick Setup (Choose One Option)

### Option 1: Development (Simplest) - Log Driver

Email logs are written to `storage/logs/laravel.log` - perfect for local development.

```bash
# Already configured! Just run:
php artisan serve

# View emails in logs:
tail -f storage/logs/laravel.log
```

**Pros:** No setup needed, works immediately
**Cons:** Not real email delivery

---

### Option 2: Development (Realistic) - MailHog

MailHog provides a local SMTP server with a web UI for testing.

```bash
# Start MailHog via Docker
docker-compose up -d mailhog

# Access at http://localhost:8025
```

Then run:
```bash
./scripts/setup-email.sh
# Select option 3 (MailHog)
```

**Pros:** Realistic SMTP testing, visual inspection of emails
**Cons:** Requires Docker

---

### Option 3: Production - SendGrid (Recommended)

SendGrid is free for 100 emails/day (unlimited for first 3 months).

#### Step 1: Get API Key
1. Sign up at https://sendgrid.com
2. Go to Settings > API Keys
3. Create new API key
4. Copy the key (you won't see it again!)

#### Step 2: Configure CHOM
```bash
./scripts/setup-email.sh
# Select option 1 (SendGrid)
# Paste your API key when prompted
```

Or manually edit `.env`:
```bash
MAIL_MAILER=sendgrid
SENDGRID_API_KEY=SG.your_api_key_here
MAIL_FROM_ADDRESS=noreply@yourdomain.com
```

#### Step 3: Test It
```bash
php artisan tinker

# Test sending email
Mail::to('test@example.com')->send(
    new \App\Mail\TeamInvitationMail(...)
);
```

**Pros:** Production-ready, generous free tier, excellent deliverability
**Cons:** Requires signup and API key

---

### Option 4: Production - Mailgun

Mailgun offers 5,000 emails/month free.

#### Step 1: Get Credentials
1. Sign up at https://mailgun.com
2. Dashboard > API > API Keys (copy secret key)
3. Note your domain (e.g., `sandbox12345.mailgun.org`)

#### Step 2: Configure CHOM
```bash
./scripts/setup-email.sh
# Select option 2 (Mailgun)
# Enter domain and API key when prompted
```

Or manually edit `.env`:
```bash
MAIL_MAILER=mailgun
MAILGUN_DOMAIN=sandboxxx.mailgun.org
MAILGUN_SECRET=key-xxxx
MAILGUN_ENDPOINT=api.mailgun.net
```

---

## Test Email Functionality

### Run the Email Test Suite

```bash
php artisan test tests/Feature/Api/V1/EmailTest.php

# Expected: 20 tests passed
```

### Manual Test (API)

Invite a team member (this sends an email):

```bash
curl -X POST http://localhost:8000/api/v1/team/invite \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "newmember@example.com",
    "role": "member"
  }'
```

Check your email service:
- **Log:** `tail -f storage/logs/laravel.log`
- **MailHog:** http://localhost:8025
- **SendGrid:** https://app.sendgrid.com/email_activity
- **Mailgun:** https://app.mailgun.com/app/logs

---

## File Locations

### Email Classes
- `app/Mail/TeamInvitationMail.php` - Invitation emails
- `app/Mail/PasswordResetMail.php` - Password reset emails

### Email Templates
- `resources/views/emails/team-invitation.blade.php`
- `resources/views/emails/password-reset.blade.php`

### Documentation
- `docs/EMAIL_CONFIGURATION.md` - Comprehensive guide (680+ lines)
- `scripts/setup-email.sh` - Interactive setup script

### Tests
- `tests/Feature/Api/V1/EmailTest.php` - 20 email test cases

### Implementation
- `IMPLEMENTATION_SUMMARY.md` - Detailed changes summary

---

## Environment Variables

### Required
```bash
MAIL_MAILER=sendgrid          # or: mailgun, ses, postmark, smtp, log
MAIL_FROM_ADDRESS=noreply@yourdomain.com
MAIL_FROM_NAME=CHOM
```

### SendGrid
```bash
SENDGRID_API_KEY=SG.xxxxx
```

### Mailgun
```bash
MAILGUN_DOMAIN=sandbox123.mailgun.org
MAILGUN_SECRET=key-xxxx
MAILGUN_ENDPOINT=api.mailgun.net
```

### AWS SES
```bash
AWS_DEFAULT_REGION=us-east-1
AWS_SES_REGION=us-east-1
```

### SMTP (Generic)
```bash
MAIL_HOST=smtp.example.com
MAIL_PORT=587
MAIL_USERNAME=user@example.com
MAIL_PASSWORD=password
MAIL_ENCRYPTION=tls
```

---

## What Works Now

### Team Invitations
When you invite a team member via the API:
1. Invitation record created in database
2. Email sent to the invitee with acceptance link
3. Invitee can click link to accept and join team

### Password Reset
Password reset emails (ready to integrate):
1. Send reset email with secure token
2. User clicks link and resets password

### Logging
All email events logged with:
- Recipient email
- Organization name
- Inviter details
- Acceptance link
- Expiration time

---

## Troubleshooting

### Email Not Sending?

1. **Check configuration:**
   ```bash
   php artisan config:show mail
   ```

2. **Check queue worker (if using queued emails):**
   ```bash
   php artisan queue:work
   ```

3. **Check logs:**
   ```bash
   tail -f storage/logs/laravel.log
   ```

4. **Verify credentials:**
   - SendGrid: https://app.sendgrid.com/settings/api_keys
   - Mailgun: https://app.mailgun.com/app/account/security/api_keys

### API Key Issues?

- **Invalid SendGrid key:** Verify at https://app.sendgrid.com
- **Invalid Mailgun key:** Verify at https://app.mailgun.com
- **Key starts with `SG.`?** (SendGrid requirement)

### Emails Going to Spam?

Verify your domain:
1. SendGrid: Settings > Sender Authentication
2. Mailgun: Sending > Domains
3. Add SPF/DKIM records from service dashboard

---

## Next Steps

1. **Choose your service** (Development: Log or MailHog, Production: SendGrid or Mailgun)
2. **Run setup script** (`./scripts/setup-email.sh`)
3. **Test** (Run test suite or manual API test)
4. **Review documentation** (`docs/EMAIL_CONFIGURATION.md` for detailed guide)

---

## Key Features Implemented

- Production-ready email infrastructure
- Multiple service provider support
- Queued async email delivery
- Graceful error handling
- Comprehensive logging
- Mobile-responsive templates
- 20 unit tests
- Interactive setup script
- 680+ line documentation

---

## Support

For detailed information, see:
- **Setup Guide:** `/docs/EMAIL_CONFIGURATION.md`
- **Implementation:** `/IMPLEMENTATION_SUMMARY.md`
- **Tests:** `/tests/Feature/Api/V1/EmailTest.php`

Questions? Check the troubleshooting section in the comprehensive guide.

---

## Quick Reference

| Service | Setup Time | Free Tier | Best For |
|---------|-----------|-----------|----------|
| Log Driver | Instant | Unlimited* | Local dev |
| MailHog | 2 min | Unlimited* | Dev testing |
| SendGrid | 5 min | 100/day | Production |
| Mailgun | 5 min | 5,000/mo | Production |

*Only in development, not real delivery
