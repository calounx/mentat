<?php

namespace Tests\Deployment\Helpers;

use Illuminate\Support\Facades\Process;

/**
 * Helper class to create mock deployment environments for testing
 */
class MockEnvironment
{
    private string $basePath;
    private array $config = [];

    public function __construct(string $basePath = null)
    {
        $this->basePath = $basePath ?? sys_get_temp_dir() . '/deployment_test_' . uniqid();
    }

    /**
     * Create a mock deployment environment
     */
    public function create(): self
    {
        if (!is_dir($this->basePath)) {
            mkdir($this->basePath, 0755, true);
        }

        // Create necessary directories
        mkdir("{$this->basePath}/storage/app/backups", 0755, true);
        mkdir("{$this->basePath}/storage/logs", 0755, true);
        mkdir("{$this->basePath}/bootstrap/cache", 0755, true);

        return $this;
    }

    /**
     * Set environment variable
     */
    public function setEnv(string $key, string $value): self
    {
        $this->config[$key] = $value;
        return $this;
    }

    /**
     * Create .env file
     */
    public function createEnvFile(): self
    {
        $content = [];
        foreach ($this->config as $key => $value) {
            $content[] = "{$key}={$value}";
        }

        file_put_contents("{$this->basePath}/.env", implode("\n", $content));

        return $this;
    }

    /**
     * Simulate low disk space
     */
    public function simulateLowDiskSpace(): self
    {
        // This is a marker - actual implementation would depend on testing environment
        $this->config['_SIMULATE_LOW_DISK'] = 'true';
        return $this;
    }

    /**
     * Simulate network failure
     */
    public function simulateNetworkFailure(): self
    {
        $this->config['_SIMULATE_NETWORK_FAILURE'] = 'true';
        return $this;
    }

    /**
     * Simulate database unavailable
     */
    public function simulateDatabaseDown(): self
    {
        $this->config['DB_HOST'] = 'invalid-host-' . uniqid();
        return $this;
    }

    /**
     * Get the base path
     */
    public function getBasePath(): string
    {
        return $this->basePath;
    }

    /**
     * Clean up the mock environment
     */
    public function cleanup(): void
    {
        if (is_dir($this->basePath)) {
            Process::run("rm -rf {$this->basePath}");
        }
    }

    /**
     * Create a Git repository in the mock environment
     */
    public function initGitRepo(): self
    {
        Process::run("cd {$this->basePath} && git init");
        Process::run("cd {$this->basePath} && git config user.email 'test@example.com'");
        Process::run("cd {$this->basePath} && git config user.name 'Test User'");

        // Create initial commit
        file_put_contents("{$this->basePath}/README.md", "# Test Repository\n");
        Process::run("cd {$this->basePath} && git add . && git commit -m 'Initial commit'");

        return $this;
    }

    /**
     * Create a new commit
     */
    public function createCommit(string $message = 'Test commit'): self
    {
        file_put_contents(
            "{$this->basePath}/test_" . time() . ".txt",
            "Test file content\n"
        );
        Process::run("cd {$this->basePath} && git add . && git commit -m '{$message}'");

        return $this;
    }
}
