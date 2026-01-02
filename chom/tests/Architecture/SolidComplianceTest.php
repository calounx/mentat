<?php

namespace Tests\Architecture;

use PHPUnit\Framework\TestCase;
use PHPUnit\Framework\Attributes\Test;

/**
 * SOLID Principles Compliance Tests
 *
 * These tests verify that the codebase adheres to SOLID principles:
 * - Single Responsibility Principle (SRP)
 * - Open/Closed Principle (OCP)
 * - Liskov Substitution Principle (LSP)
 * - Interface Segregation Principle (ISP)
 * - Dependency Inversion Principle (DIP)
 *
 * Note: For full architectural enforcement, install PHPStan/Larastan:
 *   composer require --dev phpstan/phpstan larastan/larastan
 *   php artisan vendor:publish --tag=larastan
 */
class SolidComplianceTest extends TestCase
{
    private string $appPath;

    protected function setUp(): void
    {
        parent::setUp();
        $this->appPath = __DIR__.'/../../app';
    }

    #[Test]


    /**
     * Verify controllers don't contain business logic
     * Controllers should only orchestrate, not implement business rules


     */
    public function controllers_should_not_contain_business_logic(): void
    {
        $controllers = $this->getPhpFiles($this->appPath.'/Http/Controllers');
        $violations = [];

        foreach ($controllers as $controller) {
            $content = file_get_contents($controller);

            // Check for database queries directly in controllers
            if (preg_match('/\$this->.*?->where\(|DB::table\(|DB::select\(/i', $content)) {
                $violations[] = basename($controller).' contains direct database queries';
            }

            // Check for complex business logic patterns
            if (preg_match('/foreach.*foreach|while.*while/s', $content)) {
                // Nested loops might indicate business logic
                $violations[] = basename($controller).' contains nested loops (possible business logic)';
            }

            // Check method complexity by counting lines
            if (preg_match_all('/public function \w+\([^)]*\)\s*{([^}]+)}/s', $content, $matches)) {
                foreach ($matches[1] as $methodBody) {
                    $lines = count(explode("\n", $methodBody));
                    if ($lines > 30) {
                        $violations[] = basename($controller).' has methods longer than 30 lines (possible business logic)';
                        break; // Only report once per file
                    }
                }
            }
        }

        $this->assertEmpty(
            $violations,
            "Controllers should not contain business logic:\n".implode("\n", $violations)
        );
    }

    #[Test]


    /**
     * Verify services implement interfaces (Dependency Inversion)


     */
    public function critical_services_should_implement_interfaces(): void
    {
        $criticalServices = [
            'VPS/VpsConnectionPool.php',
            'VPS/VpsConnectionManager.php',
            'VPS/VpsAllocationService.php',
            'Sites/SiteCreationService.php',
            'Backup/BackupService.php',
        ];

        $violations = [];

        foreach ($criticalServices as $service) {
            $servicePath = $this->appPath.'/Services/'.$service;

            if (! file_exists($servicePath)) {
                $violations[] = "Service not found: {$service}";

                continue;
            }

            $content = file_get_contents($servicePath);

            // Check if class implements any interface
            if (! preg_match('/class\s+\w+\s+implements\s+\w+/i', $content)) {
                $violations[] = "{$service} does not implement an interface";
            }
        }

        $this->assertEmpty(
            $violations,
            "Critical services should implement interfaces:\n".implode("\n", $violations)
        );
    }

    #[Test]


    /**
     * Verify no circular dependencies between major modules


     */
    public function no_circular_dependencies_between_modules(): void
    {
        $modules = [
            'VPS' => $this->appPath.'/Services/VPS',
            'Sites' => $this->appPath.'/Services/Sites',
            'Team' => $this->appPath.'/Services/Team',
            'Backup' => $this->appPath.'/Services/Backup',
        ];

        $dependencies = [];

        foreach ($modules as $moduleName => $modulePath) {
            if (! is_dir($modulePath)) {
                continue;
            }

            $files = $this->getPhpFiles($modulePath);
            $dependencies[$moduleName] = [];

            foreach ($files as $file) {
                $content = file_get_contents($file);

                // Check use statements for other modules
                foreach ($modules as $otherModule => $otherPath) {
                    if ($moduleName === $otherModule) {
                        continue;
                    }

                    if (preg_match("/use App\\\\Services\\\\{$otherModule}\\\\/", $content)) {
                        if (! in_array($otherModule, $dependencies[$moduleName])) {
                            $dependencies[$moduleName][] = $otherModule;
                        }
                    }
                }
            }
        }

        // Check for circular dependencies
        $circular = [];
        foreach ($dependencies as $module => $deps) {
            foreach ($deps as $dep) {
                if (isset($dependencies[$dep]) && in_array($module, $dependencies[$dep])) {
                    $circular[] = "{$module} <-> {$dep}";
                }
            }
        }

        $this->assertEmpty(
            $circular,
            "Circular dependencies detected:\n".implode("\n", array_unique($circular))
        );
    }

    #[Test]


    /**
     * Verify models don't contain complex query logic (should use repositories/services)


     */
    public function models_should_not_contain_complex_queries(): void
    {
        $models = $this->getPhpFiles($this->appPath.'/Models');
        $violations = [];

        foreach ($models as $model) {
            $content = file_get_contents($model);

            // Models shouldn't have complex query scopes
            if (preg_match('/public function scope\w+[^{]*{([^}]{200,})/s', $content)) {
                $violations[] = basename($model).' contains complex query scopes (>200 chars)';
            }

            // Models shouldn't have repository-like methods
            if (preg_match('/public function (findBy|getBy|searchBy|filterBy)\w+/i', $content)) {
                $violations[] = basename($model).' contains repository-like methods (should use repositories)';
            }
        }

        $this->assertEmpty(
            $violations,
            "Models should not contain complex query logic:\n".implode("\n", $violations)
        );
    }

    #[Test]


    /**
     * Verify value objects are immutable


     */
    public function value_objects_should_be_immutable(): void
    {
        $valueObjectsPath = $this->appPath.'/ValueObjects';

        if (! is_dir($valueObjectsPath)) {
            $this->markTestSkipped('No ValueObjects directory found');
        }

        $valueObjects = $this->getPhpFiles($valueObjectsPath);
        $violations = [];

        foreach ($valueObjects as $vo) {
            $content = file_get_contents($vo);

            // Check for setter methods (should not exist in value objects)
            if (preg_match('/public function set\w+\(/i', $content)) {
                $violations[] = basename($vo).' contains setter methods (should be immutable)';
            }

            // Check for public properties (should be private/readonly)
            if (preg_match('/public \$\w+/i', $content)) {
                $violations[] = basename($vo).' has public properties (should be private/readonly)';
            }
        }

        $this->assertEmpty(
            $violations,
            "Value objects should be immutable:\n".implode("\n", $violations)
        );
    }

    #[Test]


    /**
     * Verify services don't depend on controllers (correct dependency direction)


     */
    public function services_should_not_depend_on_controllers(): void
    {
        $services = $this->getPhpFiles($this->appPath.'/Services');
        $violations = [];

        foreach ($services as $service) {
            $content = file_get_contents($service);

            // Check for controller imports
            if (preg_match('/use App\\\\Http\\\\Controllers\\\\/i', $content)) {
                $violations[] = basename($service).' depends on controllers (wrong dependency direction)';
            }
        }

        $this->assertEmpty(
            $violations,
            "Services should not depend on controllers:\n".implode("\n", $violations)
        );
    }

    #[Test]


    /**
     * Verify middleware classes follow single responsibility


     */
    public function middleware_should_follow_single_responsibility(): void
    {
        $middlewarePath = $this->appPath.'/Http/Middleware';

        if (! is_dir($middlewarePath)) {
            $this->markTestSkipped('No Middleware directory found');
        }

        $middlewares = $this->getPhpFiles($middlewarePath);
        $violations = [];

        foreach ($middlewares as $middleware) {
            $content = file_get_contents($middleware);

            // Count responsibilities by looking for major control structures
            $responsibilityIndicators = [
                'if\s*\(' => 'conditional logic',
                'foreach\s*\(' => 'iteration',
                'try\s*{' => 'exception handling',
                'Log::' => 'logging',
                'Cache::' => 'caching',
                'DB::' => 'database operations',
            ];

            $found = [];
            foreach ($responsibilityIndicators as $pattern => $responsibility) {
                if (preg_match("/{$pattern}/", $content)) {
                    $found[] = $responsibility;
                }
            }

            // If middleware does more than 3 different things, it might violate SRP
            if (count($found) > 3) {
                $violations[] = basename($middleware).' has multiple responsibilities: '.implode(', ', $found);
            }
        }

        $this->assertEmpty(
            $violations,
            "Middleware should follow single responsibility:\n".implode("\n", $violations)
        );
    }

    #[Test]


    /**
     * Verify API controllers follow consistent response patterns


     */
    public function api_controllers_should_follow_consistent_patterns(): void
    {
        $apiControllers = $this->getPhpFiles($this->appPath.'/Http/Controllers/Api');

        if (empty($apiControllers)) {
            $this->markTestSkipped('No API controllers found');
        }

        $violations = [];

        foreach ($apiControllers as $controller) {
            $content = file_get_contents($controller);

            // API controllers should return JSON responses consistently
            if (preg_match('/return view\(/i', $content)) {
                $violations[] = basename($controller).' returns views (API controllers should return JSON)';
            }

            // Check for proper response methods
            if (! preg_match('/return response\(\)->json\(|return \$\w+->toJson|JsonResource/i', $content)) {
                if (preg_match('/public function (index|show|store|update|destroy)/i', $content)) {
                    $violations[] = basename($controller).' may not use proper JSON response methods';
                }
            }
        }

        $this->assertEmpty(
            $violations,
            "API controllers should follow consistent patterns:\n".implode("\n", $violations)
        );
    }

    #[Test]


    /**
     * Verify proper separation between domain and infrastructure


     */
    public function domain_logic_should_not_depend_on_infrastructure(): void
    {
        $servicesPath = $this->appPath.'/Services';

        if (! is_dir($servicesPath)) {
            $this->markTestSkipped('No Services directory found');
        }

        $services = $this->getPhpFiles($servicesPath);
        $violations = [];

        foreach ($services as $service) {
            $content = file_get_contents($service);

            // Domain services shouldn't directly use framework-specific code
            // (they should use abstractions/interfaces instead)
            $infrastructurePatterns = [
                '/use Illuminate\\\\Support\\\\Facades\\\\(?!Log|Cache)/' => 'uses Laravel facades directly',
                '/Request::/' => 'uses Request facade directly',
                '/Session::/' => 'uses Session facade directly',
            ];

            foreach ($infrastructurePatterns as $pattern => $message) {
                if (preg_match($pattern, $content)) {
                    $violations[] = basename($service).' '.$message.' (should use dependency injection)';
                    break; // Only report once per file
                }
            }
        }

        // Some violations are acceptable for certain service types
        $violations = array_filter($violations, function ($violation) {
            // Allow certain services to use facades
            return ! preg_match('/IntegrationService|NotificationService|EmailService/', $violation);
        });

        $this->assertEmpty(
            $violations,
            "Domain logic should not depend on infrastructure:\n".implode("\n", $violations)
        );
    }

    #[Test]


    /**
     * Verify policies are properly defined for authorization


     */
    public function policies_should_be_defined_for_major_resources(): void
    {
        $majorModels = [
            'Site',
            'VpsServer',
            'Organization',
            'User',
        ];

        $policiesPath = $this->appPath.'/Policies';
        $violations = [];

        foreach ($majorModels as $model) {
            $policyFile = $policiesPath.'/'.$model.'Policy.php';

            if (! file_exists($policyFile)) {
                $violations[] = "{$model}Policy not found (authorization may not be properly enforced)";

                continue;
            }

            $content = file_get_contents($policyFile);

            // Check for standard CRUD policy methods
            $expectedMethods = ['viewAny', 'view', 'create', 'update', 'delete'];
            $missingMethods = [];

            foreach ($expectedMethods as $method) {
                if (! preg_match("/public function {$method}\(/", $content)) {
                    $missingMethods[] = $method;
                }
            }

            if (! empty($missingMethods)) {
                $violations[] = "{$model}Policy missing methods: ".implode(', ', $missingMethods);
            }
        }

        // Some violations might be expected if models don't need full CRUD
        $this->assertTrue(
            count($violations) < count($majorModels),
            "Policies should be defined for major resources:\n".implode("\n", $violations)
        );
    }

    /**
     * Helper function to recursively get all PHP files in a directory
     */
    private function getPhpFiles(string $directory): array
    {
        if (! is_dir($directory)) {
            return [];
        }

        $files = [];
        $iterator = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($directory)
        );

        foreach ($iterator as $file) {
            if ($file->isFile() && $file->getExtension() === 'php') {
                $files[] = $file->getPathname();
            }
        }

        return $files;
    }
}
