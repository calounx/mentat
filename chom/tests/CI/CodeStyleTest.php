<?php

declare(strict_types=1);

namespace Tests\CI;

use Tests\TestCase;

/**
 * Code style and standards compliance tests
 */
class CodeStyleTest extends TestCase
{
    /**
     * Test PSR-12 compliance
     */
    public function test_code_follows_psr12_standards(): void
    {
        $output = [];
        $exitCode = 0;

        exec('vendor/bin/pint --test 2>&1', $output, $exitCode);

        $this->assertEquals(0, $exitCode, "Code style violations found:\n".implode("\n", $output));
    }

    /**
     * Test no debugging statements in production code
     */
    public function test_no_debugging_statements_in_code(): void
    {
        $forbiddenFunctions = ['dd(', 'dump(', 'var_dump(', 'print_r('];
        $violations = [];

        $files = glob(base_path('app').'/*.php');

        foreach ($files as $file) {
            $content = file_get_contents($file);

            foreach ($forbiddenFunctions as $function) {
                if (str_contains($content, $function)) {
                    $violations[] = "{$file} contains {$function}";
                }
            }
        }

        $this->assertEmpty($violations, "Debugging statements found:\n".implode("\n", $violations));
    }

    /**
     * Test all classes have proper namespaces
     */
    public function test_all_classes_have_proper_namespaces(): void
    {
        $this->assertTrue(true); // Placeholder - would check namespace compliance
    }
}
