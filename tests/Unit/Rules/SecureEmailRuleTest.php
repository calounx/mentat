<?php

declare(strict_types=1);

namespace Tests\Unit\Rules;

use App\Rules\SecureEmailRule;
use Tests\TestCase;

class SecureEmailRuleTest extends TestCase
{
    private SecureEmailRule $rule;

    protected function setUp(): void
    {
        parent::setUp();
        $this->rule = new SecureEmailRule();
    }

    public function test_accepts_valid_email_addresses(): void
    {
        $validEmails = [
            'user@example.com',
            'john.doe@example.com',
            'user+tag@example.com',
            'user_name@example.com',
            'user123@example.com',
            'user@subdomain.example.com',
            'user@example.co.uk',
            'first.last@example.io',
        ];

        foreach ($validEmails as $email) {
            $this->assertTrue(
                $this->rule->passes('email', $email),
                "Failed to accept valid email: {$email}"
            );
        }
    }

    public function test_rejects_invalid_email_format(): void
    {
        $invalidEmails = [
            'invalid',
            '@example.com',
            'user@',
            'user @example.com',
            'user@example',
            'user..name@example.com',
            'user@.example.com',
            'user@example..com',
            '.user@example.com',
            'user.@example.com',
        ];

        foreach ($invalidEmails as $email) {
            $this->assertFalse(
                $this->rule->passes('email', $email),
                "Failed to reject invalid email: {$email}"
            );
        }
    }

    public function test_rejects_disposable_email_domains(): void
    {
        $disposableEmails = [
            'user@10minutemail.com',
            'user@tempmail.com',
            'user@guerrillamail.com',
            'user@mailinator.com',
            'user@throwaway.email',
            'user@temp-mail.org',
            'user@fakeinbox.com',
            'user@maildrop.cc',
        ];

        foreach ($disposableEmails as $email) {
            $this->assertFalse(
                $this->rule->passes('email', $email),
                "Failed to reject disposable email: {$email}"
            );
        }
    }

    public function test_rejects_role_based_email_addresses(): void
    {
        $roleEmails = [
            'admin@example.com',
            'noreply@example.com',
            'support@example.com',
            'info@example.com',
            'sales@example.com',
            'postmaster@example.com',
            'webmaster@example.com',
            'abuse@example.com',
        ];

        $rule = new SecureEmailRule(['reject_role_emails' => true]);

        foreach ($roleEmails as $email) {
            $this->assertFalse(
                $rule->passes('email', $email),
                "Failed to reject role-based email: {$email}"
            );
        }
    }

    public function test_accepts_role_emails_when_not_configured_to_reject(): void
    {
        $rule = new SecureEmailRule(['reject_role_emails' => false]);

        $this->assertTrue($rule->passes('email', 'admin@example.com'));
        $this->assertTrue($rule->passes('email', 'support@example.com'));
    }

    public function test_rejects_emails_with_suspicious_patterns(): void
    {
        $suspiciousEmails = [
            'test+spam@example.com',
            'test+abuse@example.com',
            'test+fraud@example.com',
            'test.test.test.test.test@example.com', // Too many dots
        ];

        $rule = new SecureEmailRule(['check_suspicious_patterns' => true]);

        foreach ($suspiciousEmails as $email) {
            $this->assertFalse(
                $rule->passes('email', $email),
                "Failed to reject suspicious email: {$email}"
            );
        }
    }

    public function test_validates_mx_records_for_domain(): void
    {
        $rule = new SecureEmailRule(['verify_mx_records' => true]);

        // Gmail has valid MX records
        $this->assertTrue($rule->passes('email', 'user@gmail.com'));

        // Fake domain should not have MX records
        $this->assertFalse($rule->passes('email', 'user@thisdomaindoesnotexist12345.com'));
    }

    public function test_rejects_emails_exceeding_max_length(): void
    {
        // Email addresses should not exceed 254 characters
        $longLocal = str_repeat('a', 250);
        $longEmail = $longLocal . '@example.com';

        $this->assertFalse($this->rule->passes('email', $longEmail));
    }

    public function test_rejects_local_part_exceeding_64_characters(): void
    {
        $longLocal = str_repeat('a', 65);
        $email = $longLocal . '@example.com';

        $this->assertFalse($this->rule->passes('email', $email));
    }

    public function test_rejects_special_characters_in_local_part(): void
    {
        $invalidEmails = [
            'user<script>@example.com',
            'user"test@example.com',
            'user\\test@example.com',
            'user,name@example.com',
            'user:name@example.com',
            'user;name@example.com',
        ];

        foreach ($invalidEmails as $email) {
            $this->assertFalse($this->rule->passes('email', $email));
        }
    }

    public function test_accepts_plus_addressing(): void
    {
        $rule = new SecureEmailRule(['allow_plus_addressing' => true]);

        $plusEmails = [
            'user+newsletters@example.com',
            'user+receipts@example.com',
            'john+shopping@example.com',
        ];

        foreach ($plusEmails as $email) {
            $this->assertTrue($rule->passes('email', $email));
        }
    }

    public function test_rejects_plus_addressing_when_disabled(): void
    {
        $rule = new SecureEmailRule(['allow_plus_addressing' => false]);

        $this->assertFalse($rule->passes('email', 'user+tag@example.com'));
    }

    public function test_rejects_typosquatting_domains(): void
    {
        $typosquattingEmails = [
            'user@gmai1.com', // gmail with 1 instead of l
            'user@gmial.com',
            'user@yahooo.com',
            'user@outloook.com',
        ];

        $rule = new SecureEmailRule(['check_typosquatting' => true]);

        foreach ($typosquattingEmails as $email) {
            $this->assertFalse(
                $rule->passes('email', $email),
                "Failed to reject typosquatting email: {$email}"
            );
        }
    }

    public function test_rejects_numeric_only_local_part(): void
    {
        $this->assertFalse($this->rule->passes('email', '123456@example.com'));
    }

    public function test_rejects_emails_with_consecutive_dots(): void
    {
        $invalidEmails = [
            'user..name@example.com',
            'user...name@example.com',
            'user@example..com',
        ];

        foreach ($invalidEmails as $email) {
            $this->assertFalse($this->rule->passes('email', $email));
        }
    }

    public function test_rejects_emails_starting_or_ending_with_dot(): void
    {
        $invalidEmails = [
            '.user@example.com',
            'user.@example.com',
            'user@.example.com',
            'user@example.com.',
        ];

        foreach ($invalidEmails as $email) {
            $this->assertFalse($this->rule->passes('email', $email));
        }
    }

    public function test_handles_internationalized_email_addresses(): void
    {
        $idnEmails = [
            'user@münchen.de',
            'user@españa.es',
        ];

        foreach ($idnEmails as $email) {
            $this->assertTrue(
                $this->rule->passes('email', $email),
                "Should accept internationalized email: {$email}"
            );
        }
    }

    public function test_rejects_known_spam_domains(): void
    {
        $spamEmails = [
            'user@spam.com',
            'user@viagra-test-123.com',
        ];

        $rule = new SecureEmailRule(['check_spam_domains' => true]);

        foreach ($spamEmails as $email) {
            $this->assertFalse(
                $rule->passes('email', $email),
                "Failed to reject spam domain: {$email}"
            );
        }
    }

    public function test_validates_against_custom_blacklist(): void
    {
        $blacklist = ['blocked.com', 'banned.com'];
        $rule = new SecureEmailRule(['domain_blacklist' => $blacklist]);

        $this->assertFalse($rule->passes('email', 'user@blocked.com'));
        $this->assertFalse($rule->passes('email', 'user@banned.com'));
        $this->assertTrue($rule->passes('email', 'user@allowed.com'));
    }

    public function test_validates_against_custom_whitelist(): void
    {
        $whitelist = ['allowed.com', 'trusted.com'];
        $rule = new SecureEmailRule(['domain_whitelist' => $whitelist, 'enforce_whitelist' => true]);

        $this->assertTrue($rule->passes('email', 'user@allowed.com'));
        $this->assertTrue($rule->passes('email', 'user@trusted.com'));
        $this->assertFalse($rule->passes('email', 'user@other.com'));
    }

    public function test_returns_descriptive_error_message(): void
    {
        $this->rule->passes('email', 'user@mailinator.com');

        $message = $this->rule->message();

        $this->assertIsString($message);
        $this->assertNotEmpty($message);
    }

    public function test_handles_null_value(): void
    {
        $this->assertFalse($this->rule->passes('email', null));
    }

    public function test_handles_empty_string(): void
    {
        $this->assertFalse($this->rule->passes('email', ''));
    }

    public function test_handles_numeric_value(): void
    {
        $this->assertFalse($this->rule->passes('email', 12345));
    }

    public function test_handles_array_value(): void
    {
        $this->assertFalse($this->rule->passes('email', ['user@example.com']));
    }

    public function test_case_insensitive_validation(): void
    {
        $this->assertTrue($rule->passes('email', 'User@Example.COM'));
        $this->assertTrue($this->rule->passes('email', 'USER@EXAMPLE.COM'));
    }

    public function test_rejects_emails_with_unicode_characters_in_local_part(): void
    {
        $invalidEmails = [
            'user™@example.com',
            'user©@example.com',
            'user®@example.com',
        ];

        foreach ($invalidEmails as $email) {
            $this->assertFalse($this->rule->passes('email', $email));
        }
    }

    public function test_detects_free_email_providers(): void
    {
        $freeEmails = [
            'user@gmail.com',
            'user@yahoo.com',
            'user@hotmail.com',
            'user@outlook.com',
        ];

        $rule = new SecureEmailRule(['reject_free_providers' => true]);

        foreach ($freeEmails as $email) {
            $this->assertFalse(
                $rule->passes('email', $email),
                "Failed to reject free email provider: {$email}"
            );
        }
    }

    public function test_accepts_business_email_addresses(): void
    {
        $businessEmails = [
            'employee@company.com',
            'john.doe@acme-corp.com',
            'admin@business-domain.io',
        ];

        $rule = new SecureEmailRule(['reject_free_providers' => true]);

        foreach ($businessEmails as $email) {
            $this->assertTrue(
                $rule->passes('email', $email),
                "Should accept business email: {$email}"
            );
        }
    }

    public function test_performance_with_mx_lookup(): void
    {
        $rule = new SecureEmailRule(['verify_mx_records' => true]);

        $startTime = microtime(true);

        $rule->passes('email', 'user@gmail.com');

        $endTime = microtime(true);
        $duration = ($endTime - $startTime) * 1000;

        // MX lookup should complete in under 500ms
        $this->assertLessThan(500, $duration);
    }

    public function test_performance_with_many_validations(): void
    {
        $emails = array_merge(
            array_fill(0, 50, 'valid@example.com'),
            array_fill(0, 50, 'invalid@mailinator.com')
        );

        $startTime = microtime(true);

        foreach ($emails as $email) {
            $this->rule->passes('email', $email);
        }

        $endTime = microtime(true);
        $duration = ($endTime - $startTime) * 1000;

        // 100 validations should complete in under 100ms
        $this->assertLessThan(100, $duration);
    }
}
