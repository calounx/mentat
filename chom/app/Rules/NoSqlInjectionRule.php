<?php

declare(strict_types=1);

namespace App\Rules;

use Closure;
use Illuminate\Contracts\Validation\ValidationRule;
use Illuminate\Support\Facades\Config;

/**
 * SQL Injection Prevention Rule
 *
 * Detects and blocks SQL injection patterns in user input.
 *
 * Patterns detected:
 * - UNION-based injection
 * - Boolean-based blind injection
 * - Time-based blind injection
 * - Stacked queries
 * - Comment-based injection
 *
 * OWASP Reference: A03:2021 – Injection
 * Protection: Defense in depth against SQL injection
 *
 * Note: This is a defense-in-depth measure. Primary protection
 * should be parameterized queries/prepared statements.
 *
 * @package App\Rules
 */
class NoSqlInjectionRule implements ValidationRule
{
    /**
     * Strict mode (more aggressive pattern matching).
     */
    protected bool $strictMode;

    /**
     * SQL injection patterns to detect.
     */
    protected array $patterns;

    /**
     * Create a new rule instance.
     *
     * @param bool $strictMode Enable strict mode
     */
    public function __construct(bool $strictMode = true)
    {
        $this->strictMode = $strictMode;
        $this->patterns = Config::get('security.validation.sql_injection_patterns', []);

        // Fallback patterns if config not available
        if (empty($this->patterns)) {
            $this->patterns = $this->getDefaultPatterns();
        }
    }

    /**
     * Run the validation rule.
     *
     * @param string $attribute Attribute name
     * @param mixed $value Value to validate
     * @param Closure $fail Failure callback
     * @return void
     */
    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        if (!is_string($value)) {
            return;
        }

        // Check against all patterns
        foreach ($this->patterns as $pattern) {
            if (preg_match($pattern, $value)) {
                $fail("The {$attribute} contains potentially malicious content.");
                return;
            }
        }

        // Additional strict checks
        if ($this->strictMode) {
            if ($this->hasStrictViolation($value)) {
                $fail("The {$attribute} contains potentially malicious content.");
                return;
            }
        }
    }

    /**
     * Get default SQL injection patterns.
     *
     * @return array Regex patterns
     */
    protected function getDefaultPatterns(): array
    {
        return [
            // UNION-based injection
            '/(\bunion\b.*\bselect\b)/i',

            // SELECT statements
            '/(\bselect\b.*\bfrom\b)/i',

            // INSERT statements
            '/(\binsert\b.*\binto\b)/i',

            // UPDATE statements
            '/(\bupdate\b.*\bset\b)/i',

            // DELETE statements
            '/(\bdelete\b.*\bfrom\b)/i',

            // DROP statements
            '/(\bdrop\b.*\b(table|database|column)\b)/i',

            // ALTER statements
            '/(\balter\b.*\btable\b)/i',

            // EXEC/EXECUTE statements
            '/(\bexec(ute)?\b.*\()/i',

            // SQL comments
            '/(--|\#|\/\*|\*\/)/i',

            // String concatenation in SQL context
            '/(\|\||concat\()/i',

            // Time-based blind injection
            '/(\bsleep\(|\bwaitfor\b|\bbenchmark\()/i',

            // Boolean-based patterns
            '/(\b(and|or)\b\s+\d+\s*=\s*\d+)/i',

            // Stacked queries
            '/;\s*(select|insert|update|delete|drop|alter)/i',

            // Information schema access
            '/(\binformation_schema\b)/i',

            // System table access
            '/(\b(sys|mysql|pg_)\w+\b)/i',

            // Hex encoding injection
            '/(0x[0-9a-f]+)/i',

            // Char function
            '/(\bchar\()/i',
        ];
    }

    /**
     * Check for strict mode violations.
     *
     * Additional checks in strict mode:
     * - Multiple SQL keywords
     * - Suspicious character combinations
     * - Encoding attempts
     *
     * @param string $value Input value
     * @return bool True if violation detected
     */
    protected function hasStrictViolation(string $value): bool
    {
        $lower = strtolower($value);

        // Count SQL keywords
        $keywords = [
            'select', 'insert', 'update', 'delete', 'drop',
            'union', 'where', 'from', 'into', 'table',
        ];

        $keywordCount = 0;

        foreach ($keywords as $keyword) {
            if (str_contains($lower, $keyword)) {
                $keywordCount++;
            }
        }

        // Multiple SQL keywords = suspicious
        if ($keywordCount >= 2) {
            return true;
        }

        // Check for suspicious character sequences
        $suspiciousSequences = [
            '\' or \'',
            '" or "',
            '\' and \'',
            '" and "',
            '1=1',
            '1=0',
            '\' or 1=1',
            '" or 1=1',
        ];

        foreach ($suspiciousSequences as $sequence) {
            if (str_contains($lower, $sequence)) {
                return true;
            }
        }

        // Check for percent encoding of SQL keywords
        if (preg_match('/%[0-9a-f]{2}/i', $value)) {
            $decoded = urldecode($value);

            // Check if decoding reveals SQL keywords
            foreach ($keywords as $keyword) {
                if (str_contains(strtolower($decoded), $keyword)) {
                    return true;
                }
            }
        }

        return false;
    }
}
