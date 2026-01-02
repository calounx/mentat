<?php

declare(strict_types=1);

namespace Database\Factories;

use App\Models\AuditLog;
use App\Models\Organization;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * AuditLog Factory
 *
 * Generates realistic audit log test data for security testing and monitoring.
 *
 * Design Pattern: Factory Pattern
 * - Encapsulates audit log generation logic
 * - Provides fluent state methods for different action types
 * - Ensures valid audit trail data for testing compliance requirements
 *
 * Security Features:
 * - Generates tamper-proof hash chain (handled by model boot method)
 * - Includes IP address and user agent tracking
 * - Supports severity classification (low, medium, high, critical)
 * - Provides realistic metadata for different resource types
 *
 * States:
 * - created(): Resource creation audit log
 * - updated(): Resource update audit log
 * - deleted(): Resource deletion audit log
 * - viewed(): Resource access audit log
 * - exported(): Data export audit log
 *
 * OWASP Reference: A09:2021 – Security Logging and Monitoring Failures
 *
 * @extends \Illuminate\Database\Eloquent\Factories\Factory<\App\Models\AuditLog>
 */
class AuditLogFactory extends Factory
{
    protected $model = AuditLog::class;

    /**
     * Define the model's default state.
     *
     * Generates realistic audit log data with:
     * - Security-relevant actions with proper severity classification
     * - Resource type and ID for polymorphic tracking
     * - IP address and user agent information
     * - Contextual metadata for the audited action
     *
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        $resourceTypes = ['Site', 'User', 'VpsServer', 'Backup', 'Organization', 'Subscription', 'Invoice'];
        $resourceType = fake()->randomElement($resourceTypes);

        $actions = [
            'authentication.success',
            'authentication.failed',
            'user.created',
            'user.updated',
            'user.deleted',
            'site.created',
            'site.updated',
            'site.deleted',
            'backup.created',
            'backup.restored',
            'vps.provisioned',
            'vps.deleted',
            'invoice.paid',
            'subscription.created',
            'permission.changed',
        ];

        $action = fake()->randomElement($actions);

        return [
            'organization_id' => Organization::factory(),
            'user_id' => User::factory(),
            'action' => $action,
            'severity' => $this->determineSeverity($action),
            'resource_type' => $resourceType,
            'resource_id' => fake()->uuid(),
            'ip_address' => fake()->ipv4(),
            'user_agent' => fake()->userAgent(),
            'metadata' => $this->generateMetadata($action, $resourceType),
            // Note: 'hash' is automatically calculated by the model's boot method
        ];
    }

    /**
     * Determine severity level based on action type.
     *
     * Security Classification:
     * - critical: Security breaches, privilege escalations
     * - high: Authentication failures, access denials
     * - medium: Standard CRUD operations
     * - low: Read-only operations
     *
     * @param  string  $action
     * @return string
     */
    protected function determineSeverity(string $action): string
    {
        $criticalActions = [
            'security.breach.detected',
            'authentication.brute_force',
            'authorization.escalation_attempt',
        ];

        $highActions = [
            'authentication.failed',
            'authorization.denied',
            'user.deleted',
            'vps.deleted',
        ];

        $lowActions = [
            'user.viewed',
            'site.viewed',
            'dashboard.viewed',
        ];

        if (in_array($action, $criticalActions)) {
            return 'critical';
        }

        if (in_array($action, $highActions)) {
            return 'high';
        }

        if (in_array($action, $lowActions)) {
            return 'low';
        }

        return 'medium';
    }

    /**
     * Generate contextual metadata for the action.
     *
     * Provides realistic before/after state for different resource types.
     *
     * @param  string  $action
     * @param  string  $resourceType
     * @return array<string, mixed>
     */
    protected function generateMetadata(string $action, string $resourceType): array
    {
        $metadata = [
            'action_timestamp' => now()->toIso8601String(),
            'request_id' => fake()->uuid(),
        ];

        // Add context based on action type
        if (str_contains($action, 'created')) {
            $metadata['changes'] = [
                'new_values' => $this->generateResourceData($resourceType),
            ];
        } elseif (str_contains($action, 'updated')) {
            $metadata['changes'] = [
                'old_values' => $this->generateResourceData($resourceType),
                'new_values' => $this->generateResourceData($resourceType),
            ];
        } elseif (str_contains($action, 'deleted')) {
            $metadata['changes'] = [
                'old_values' => $this->generateResourceData($resourceType),
            ];
        }

        return $metadata;
    }

    /**
     * Generate sample resource data for metadata.
     *
     * @param  string  $resourceType
     * @return array<string, mixed>
     */
    protected function generateResourceData(string $resourceType): array
    {
        return match ($resourceType) {
            'Site' => [
                'domain' => fake()->domainName(),
                'status' => fake()->randomElement(['active', 'disabled']),
                'php_version' => fake()->randomElement(['8.2', '8.4']),
            ],
            'User' => [
                'name' => fake()->name(),
                'email' => fake()->email(),
                'role' => fake()->randomElement(['owner', 'admin', 'member', 'viewer']),
            ],
            'VpsServer' => [
                'name' => fake()->word().'-vps',
                'status' => fake()->randomElement(['active', 'provisioning', 'error']),
                'ip_address' => fake()->ipv4(),
            ],
            'Backup' => [
                'size_mb' => fake()->numberBetween(100, 10000),
                'status' => fake()->randomElement(['completed', 'failed']),
            ],
            default => [
                'id' => fake()->uuid(),
                'updated_at' => now()->toIso8601String(),
            ],
        };
    }

    /**
     * State: Resource creation audit log.
     *
     * @return static
     */
    public function created(): static
    {
        return $this->state(function (array $attributes) {
            $resourceType = $attributes['resource_type'] ?? 'Site';

            return [
                'action' => strtolower($resourceType).'.created',
                'severity' => 'medium',
                'metadata' => array_merge(
                    $attributes['metadata'] ?? [],
                    [
                        'changes' => [
                            'new_values' => $this->generateResourceData($resourceType),
                        ],
                    ]
                ),
            ];
        });
    }

    /**
     * State: Resource update audit log.
     *
     * @return static
     */
    public function updated(): static
    {
        return $this->state(function (array $attributes) {
            $resourceType = $attributes['resource_type'] ?? 'Site';

            return [
                'action' => strtolower($resourceType).'.updated',
                'severity' => 'medium',
                'metadata' => array_merge(
                    $attributes['metadata'] ?? [],
                    [
                        'changes' => [
                            'old_values' => $this->generateResourceData($resourceType),
                            'new_values' => $this->generateResourceData($resourceType),
                        ],
                    ]
                ),
            ];
        });
    }

    /**
     * State: Resource deletion audit log.
     *
     * @return static
     */
    public function deleted(): static
    {
        return $this->state(function (array $attributes) {
            $resourceType = $attributes['resource_type'] ?? 'Site';

            return [
                'action' => strtolower($resourceType).'.deleted',
                'severity' => 'high',
                'metadata' => array_merge(
                    $attributes['metadata'] ?? [],
                    [
                        'changes' => [
                            'old_values' => $this->generateResourceData($resourceType),
                        ],
                    ]
                ),
            ];
        });
    }

    /**
     * State: Resource view/access audit log.
     *
     * @return static
     */
    public function viewed(): static
    {
        return $this->state(function (array $attributes) {
            $resourceType = $attributes['resource_type'] ?? 'Site';

            return [
                'action' => strtolower($resourceType).'.viewed',
                'severity' => 'low',
                'metadata' => array_merge(
                    $attributes['metadata'] ?? [],
                    ['access_type' => 'read']
                ),
            ];
        });
    }

    /**
     * State: Data export audit log.
     *
     * @return static
     */
    public function exported(): static
    {
        return $this->state(function (array $attributes) {
            return [
                'action' => 'data.exported',
                'severity' => 'medium',
                'metadata' => array_merge(
                    $attributes['metadata'] ?? [],
                    [
                        'export_format' => fake()->randomElement(['csv', 'json', 'pdf']),
                        'record_count' => fake()->numberBetween(1, 1000),
                    ]
                ),
            ];
        });
    }

    /**
     * State: Authentication failure audit log.
     *
     * Security: High severity for failed login attempts.
     *
     * @return static
     */
    public function authenticationFailed(): static
    {
        return $this->state(fn (array $attributes) => [
            'action' => 'authentication.failed',
            'severity' => 'high',
            'metadata' => [
                'email' => fake()->email(),
                'reason' => fake()->randomElement(['invalid_password', 'user_not_found', '2fa_failed']),
                'attempt_count' => fake()->numberBetween(1, 5),
            ],
        ]);
    }

    /**
     * State: Authentication success audit log.
     *
     * @return static
     */
    public function authenticationSuccess(): static
    {
        return $this->state(fn (array $attributes) => [
            'action' => 'authentication.success',
            'severity' => 'medium',
            'metadata' => [
                'method' => fake()->randomElement(['password', '2fa', 'sso']),
                'session_id' => fake()->uuid(),
            ],
        ]);
    }

    /**
     * Set specific severity level.
     *
     * @param  string  $severity
     * @return static
     */
    public function withSeverity(string $severity): static
    {
        return $this->state(fn (array $attributes) => [
            'severity' => $severity,
        ]);
    }

    /**
     * Set specific action.
     *
     * @param  string  $action
     * @return static
     */
    public function withAction(string $action): static
    {
        return $this->state(fn (array $attributes) => [
            'action' => $action,
            'severity' => $this->determineSeverity($action),
        ]);
    }

    /**
     * Set specific resource type and ID.
     *
     * @param  string  $resourceType
     * @param  string  $resourceId
     * @return static
     */
    public function forResource(string $resourceType, string $resourceId): static
    {
        return $this->state(fn (array $attributes) => [
            'resource_type' => $resourceType,
            'resource_id' => $resourceId,
        ]);
    }
}
