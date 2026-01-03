<?php

declare(strict_types=1);

namespace Tests\Unit\Services;

use App\Services\SecretsManagerService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class SecretsManagerServiceTest extends TestCase
{
    use RefreshDatabase;

    private SecretsManagerService $service;

    protected function setUp(): void
    {
        parent::setUp();

        $this->service = new SecretsManagerService();
        Storage::fake('secrets');
    }

    public function test_encrypts_secret_correctly(): void
    {
        $plaintext = 'my-secret-password';

        $encrypted = $this->service->encrypt($plaintext);

        $this->assertNotEquals($plaintext, $encrypted);
        $this->assertIsString($encrypted);
        $this->assertGreaterThan(strlen($plaintext), strlen($encrypted));
    }

    public function test_decrypts_secret_correctly(): void
    {
        $plaintext = 'my-secret-password';

        $encrypted = $this->service->encrypt($plaintext);
        $decrypted = $this->service->decrypt($encrypted);

        $this->assertEquals($plaintext, $decrypted);
    }

    public function test_throws_exception_on_decrypt_invalid_data(): void
    {
        $this->expectException(\Illuminate\Contracts\Encryption\DecryptException::class);

        $this->service->decrypt('invalid-encrypted-data');
    }

    public function test_stores_secret_securely(): void
    {
        $key = 'api_key';
        $value = 'secret-api-key-12345';

        $this->service->store($key, $value);

        $retrieved = $this->service->retrieve($key);

        $this->assertEquals($value, $retrieved);
    }

    public function test_retrieves_nonexistent_secret_returns_null(): void
    {
        $result = $this->service->retrieve('nonexistent-key');

        $this->assertNull($result);
    }

    public function test_deletes_secret(): void
    {
        $key = 'temp_secret';
        $value = 'temporary-value';

        $this->service->store($key, $value);
        $this->assertNotNull($this->service->retrieve($key));

        $this->service->delete($key);

        $this->assertNull($this->service->retrieve($key));
    }

    public function test_updates_existing_secret(): void
    {
        $key = 'database_password';
        $oldValue = 'old-password';
        $newValue = 'new-password';

        $this->service->store($key, $oldValue);
        $this->assertEquals($oldValue, $this->service->retrieve($key));

        $this->service->store($key, $newValue);

        $this->assertEquals($newValue, $this->service->retrieve($key));
        $this->assertNotEquals($oldValue, $this->service->retrieve($key));
    }

    public function test_rotates_encryption_key(): void
    {
        $key = 'rotation_test';
        $value = 'test-value';

        // Store with current key
        $this->service->store($key, $value);

        // Rotate key
        $oldKey = config('app.key');
        $newKey = 'base64:' . base64_encode(random_bytes(32));

        $this->service->rotateKey($oldKey, $newKey);

        // Should still be able to retrieve
        $retrieved = $this->service->retrieve($key);
        $this->assertEquals($value, $retrieved);
    }

    public function test_lists_all_secret_keys(): void
    {
        $secrets = [
            'api_key_1' => 'value1',
            'api_key_2' => 'value2',
            'database_password' => 'value3',
        ];

        foreach ($secrets as $key => $value) {
            $this->service->store($key, $value);
        }

        $keys = $this->service->listKeys();

        $this->assertIsArray($keys);
        $this->assertCount(3, $keys);
        $this->assertContains('api_key_1', $keys);
        $this->assertContains('api_key_2', $keys);
        $this->assertContains('database_password', $keys);
    }

    public function test_checks_if_secret_exists(): void
    {
        $key = 'existence_test';

        $this->assertFalse($this->service->exists($key));

        $this->service->store($key, 'value');

        $this->assertTrue($this->service->exists($key));
    }

    public function test_stores_secret_with_expiration(): void
    {
        $key = 'expiring_secret';
        $value = 'temporary-value';
        $ttl = 2; // 2 seconds

        $this->service->storeWithExpiration($key, $value, $ttl);

        // Should exist immediately
        $this->assertEquals($value, $this->service->retrieve($key));

        // Wait for expiration
        sleep(3);

        // Should be gone
        $this->assertNull($this->service->retrieve($key));
    }

    public function test_encrypts_with_additional_context(): void
    {
        $value = 'sensitive-data';
        $context = ['user_id' => '123', 'action' => 'payment'];

        $encrypted = $this->service->encryptWithContext($value, $context);

        $this->assertNotEquals($value, $encrypted);
        $this->assertIsString($encrypted);
    }

    public function test_decrypts_with_matching_context(): void
    {
        $value = 'sensitive-data';
        $context = ['user_id' => '123', 'action' => 'payment'];

        $encrypted = $this->service->encryptWithContext($value, $context);
        $decrypted = $this->service->decryptWithContext($encrypted, $context);

        $this->assertEquals($value, $decrypted);
    }

    public function test_fails_to_decrypt_with_wrong_context(): void
    {
        $value = 'sensitive-data';
        $context1 = ['user_id' => '123'];
        $context2 = ['user_id' => '456'];

        $encrypted = $this->service->encryptWithContext($value, $context1);

        $this->expectException(\RuntimeException::class);

        $this->service->decryptWithContext($encrypted, $context2);
    }

    public function test_generates_strong_random_secret(): void
    {
        $length = 32;

        $secret = $this->service->generateRandomSecret($length);

        $this->assertIsString($secret);
        $this->assertEquals($length, strlen($secret));
        $this->assertMatchesRegularExpression('/^[a-zA-Z0-9+\/=]+$/', $secret);
    }

    public function test_validates_secret_strength(): void
    {
        $weakSecret = 'password123';
        $strongSecret = 'P@ssw0rd!2023#SecureKey$RandomStr1ng';

        $this->assertFalse($this->service->isSecretStrong($weakSecret));
        $this->assertTrue($this->service->isSecretStrong($strongSecret));
    }

    public function test_stores_secret_with_metadata(): void
    {
        $key = 'api_credential';
        $value = 'secret-value';
        $metadata = [
            'created_by' => 'admin',
            'purpose' => 'third-party-integration',
            'expires_at' => now()->addDays(30)->toIso8601String(),
        ];

        $this->service->storeWithMetadata($key, $value, $metadata);

        $retrieved = $this->service->retrieveWithMetadata($key);

        $this->assertEquals($value, $retrieved['value']);
        $this->assertEquals($metadata, $retrieved['metadata']);
    }

    public function test_exports_secrets_securely(): void
    {
        $secrets = [
            'key1' => 'value1',
            'key2' => 'value2',
        ];

        foreach ($secrets as $key => $value) {
            $this->service->store($key, $value);
        }

        $exportPassword = 'secure-export-password';
        $exportData = $this->service->exportSecrets(['key1', 'key2'], $exportPassword);

        $this->assertIsString($exportData);
        $this->assertNotEmpty($exportData);

        // Export should be encrypted
        $this->assertStringNotContainsString('value1', $exportData);
        $this->assertStringNotContainsString('value2', $exportData);
    }

    public function test_imports_secrets_securely(): void
    {
        $originalSecrets = [
            'import_key1' => 'import_value1',
            'import_key2' => 'import_value2',
        ];

        foreach ($originalSecrets as $key => $value) {
            $this->service->store($key, $value);
        }

        $exportPassword = 'import-test-password';
        $exportData = $this->service->exportSecrets(['import_key1', 'import_key2'], $exportPassword);

        // Clear secrets
        $this->service->delete('import_key1');
        $this->service->delete('import_key2');

        // Import
        $this->service->importSecrets($exportData, $exportPassword);

        // Verify imported
        $this->assertEquals('import_value1', $this->service->retrieve('import_key1'));
        $this->assertEquals('import_value2', $this->service->retrieve('import_key2'));
    }

    public function test_tracks_secret_access(): void
    {
        $key = 'tracked_secret';
        $value = 'tracked-value';

        $this->service->store($key, $value);

        // Access secret multiple times
        $this->service->retrieve($key);
        $this->service->retrieve($key);
        $this->service->retrieve($key);

        $accessCount = $this->service->getAccessCount($key);

        $this->assertEquals(3, $accessCount);
    }

    public function test_logs_secret_modifications(): void
    {
        $key = 'audit_test';

        $this->service->store($key, 'value1');
        $this->service->store($key, 'value2');
        $this->service->delete($key);

        $auditLog = $this->service->getAuditLog($key);

        $this->assertCount(3, $auditLog);
        $this->assertEquals('created', $auditLog[0]['action']);
        $this->assertEquals('updated', $auditLog[1]['action']);
        $this->assertEquals('deleted', $auditLog[2]['action']);
    }

    public function test_prevents_access_to_deleted_secrets(): void
    {
        $key = 'deleted_secret';
        $value = 'secret-value';

        $this->service->store($key, $value);
        $this->service->delete($key);

        $result = $this->service->retrieve($key);

        $this->assertNull($result);
    }

    public function test_handles_concurrent_secret_access(): void
    {
        $key = 'concurrent_test';
        $value = 'concurrent-value';

        $this->service->store($key, $value);

        $startTime = microtime(true);

        // Simulate 100 concurrent reads
        for ($i = 0; $i < 100; $i++) {
            $result = $this->service->retrieve($key);
            $this->assertEquals($value, $result);
        }

        $endTime = microtime(true);
        $duration = ($endTime - $startTime) * 1000;

        // 100 reads should complete in under 200ms
        $this->assertLessThan(200, $duration);
    }

    public function test_validates_secret_key_format(): void
    {
        $validKeys = [
            'api_key',
            'database-password',
            'oauth2.client.secret',
            'encryption_key_2023',
        ];

        $invalidKeys = [
            '',
            'key with spaces',
            'key@invalid',
            '../../../etc/passwd',
        ];

        foreach ($validKeys as $key) {
            $this->assertTrue($this->service->isValidKeyFormat($key));
        }

        foreach ($invalidKeys as $key) {
            $this->assertFalse($this->service->isValidKeyFormat($key));
        }
    }

    public function test_performance_encryption_decryption(): void
    {
        $data = str_repeat('a', 1000); // 1KB of data

        $startTime = microtime(true);

        for ($i = 0; $i < 100; $i++) {
            $encrypted = $this->service->encrypt($data);
            $decrypted = $this->service->decrypt($encrypted);
        }

        $endTime = microtime(true);
        $duration = ($endTime - $startTime) * 1000;

        // 100 encrypt/decrypt cycles should complete in under 500ms
        $this->assertLessThan(500, $duration);
    }
}
