<?php

declare(strict_types=1);

namespace App\Rules;

use Closure;
use Illuminate\Contracts\Validation\ValidationRule;
use Illuminate\Support\Facades\Config;

/**
 * XSS Prevention Validation Rule
 *
 * Detects and blocks cross-site scripting (XSS) patterns in user input.
 *
 * Patterns detected:
 * - Script tags and JavaScript protocols
 * - Event handlers (onclick, onload, etc.)
 * - Object/embed/iframe tags
 * - Data URIs with executable content
 * - Encoded XSS attempts
 *
 * OWASP Reference: A03:2021 – Injection
 * Protection: Defense in depth against XSS attacks
 *
 * Note: This is a defense-in-depth measure. Primary protection
 * should be output encoding and Content Security Policy.
 *
 * @package App\Rules
 */
class NoXssRule implements ValidationRule
{
    /**
     * Strict mode (more aggressive pattern matching).
     */
    protected bool $strictMode;

    /**
     * Allow certain HTML tags (whitelist mode).
     */
    protected bool $allowHtml;

    /**
     * Allowed HTML tags if allowHtml is true.
     */
    protected array $allowedTags;

    /**
     * XSS patterns to detect.
     */
    protected array $patterns;

    /**
     * Create a new rule instance.
     *
     * @param bool $strictMode Enable strict mode
     * @param bool $allowHtml Allow whitelisted HTML tags
     * @param array $allowedTags Whitelisted tags if allowHtml is true
     */
    public function __construct(
        bool $strictMode = true,
        bool $allowHtml = false,
        array $allowedTags = ['p', 'br', 'strong', 'em']
    ) {
        $this->strictMode = $strictMode;
        $this->allowHtml = $allowHtml;
        $this->allowedTags = $allowedTags;
        $this->patterns = Config::get('security.validation.xss_patterns', []);

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

        // Check for dangerous patterns
        foreach ($this->patterns as $pattern) {
            if (preg_match($pattern, $value)) {
                $fail("The {$attribute} contains potentially malicious content.");
                return;
            }
        }

        // Check for event handlers
        if ($this->hasEventHandlers($value)) {
            $fail("The {$attribute} contains potentially malicious content.");
            return;
        }

        // Check for encoded XSS
        if ($this->hasEncodedXss($value)) {
            $fail("The {$attribute} contains potentially malicious content.");
            return;
        }

        // Check HTML tags if not allowed
        if (!$this->allowHtml && $this->hasHtmlTags($value)) {
            $fail("The {$attribute} cannot contain HTML tags.");
            return;
        }

        // Check for disallowed HTML tags
        if ($this->allowHtml && $this->hasDisallowedTags($value)) {
            $fail("The {$attribute} contains disallowed HTML tags.");
            return;
        }

        // Strict mode checks
        if ($this->strictMode && $this->hasStrictViolation($value)) {
            $fail("The {$attribute} contains potentially malicious content.");
            return;
        }
    }

    /**
     * Get default XSS patterns.
     *
     * @return array Regex patterns
     */
    protected function getDefaultPatterns(): array
    {
        return [
            // Script tags
            '/<script[^>]*>.*?<\/script>/is',
            '/<script/i',

            // JavaScript protocol
            '/javascript:/i',
            '/vbscript:/i',

            // Data URIs with scripts
            '/data:text\/html/i',

            // Object/embed/iframe tags
            '/<(object|embed|applet)[^>]*>/i',
            '/<iframe[^>]*>/i',

            // Style with expressions (IE)
            '/<style[^>]*>.*?expression\s*\(/is',

            // Import statements
            '/@import/i',

            // Link with javascript
            '/<link[^>]*href\s*=\s*["\']?\s*javascript:/i',

            // Meta refresh to javascript
            '/<meta[^>]*http-equiv\s*=\s*["\']?refresh[^>]*content\s*=\s*["\']?\d+;\s*url\s*=\s*javascript:/i',

            // Base tag manipulation
            '/<base[^>]*>/i',

            // Form with action to javascript
            '/<form[^>]*action\s*=\s*["\']?\s*javascript:/i',

            // Input with form action
            '/<input[^>]*formaction\s*=\s*["\']?\s*javascript:/i',

            // Eval function
            '/eval\s*\(/i',

            // Document.write
            '/document\s*\.\s*write/i',

            // Window.location
            '/window\s*\.\s*location/i',

            // Document.cookie
            '/document\s*\.\s*cookie/i',
        ];
    }

    /**
     * Check for event handler attributes.
     *
     * Event handlers like onclick, onload, onerror, etc.
     *
     * @param string $value Input value
     * @return bool True if event handlers found
     */
    protected function hasEventHandlers(string $value): bool
    {
        // Pattern for on* attributes
        $pattern = '/\bon\w+\s*=/i';

        return (bool) preg_match($pattern, $value);
    }

    /**
     * Check for encoded XSS attempts.
     *
     * Detects URL encoding, HTML entity encoding, and Unicode encoding.
     *
     * @param string $value Input value
     * @return bool True if encoded XSS detected
     */
    protected function hasEncodedXss(string $value): bool
    {
        // Decode URL encoding
        $decoded = urldecode($value);

        // Check if decoding reveals XSS patterns
        if ($decoded !== $value) {
            foreach ($this->patterns as $pattern) {
                if (preg_match($pattern, $decoded)) {
                    return true;
                }
            }
        }

        // Decode HTML entities
        $htmlDecoded = html_entity_decode($value, ENT_QUOTES | ENT_HTML5, 'UTF-8');

        // Check if HTML decoding reveals XSS patterns
        if ($htmlDecoded !== $value) {
            foreach ($this->patterns as $pattern) {
                if (preg_match($pattern, $htmlDecoded)) {
                    return true;
                }
            }
        }

        // Check for Unicode escaping (\u0061 = 'a')
        if (preg_match('/\\\\u[0-9a-f]{4}/i', $value)) {
            $unicodeDecoded = json_decode('"' . $value . '"');

            if ($unicodeDecoded) {
                foreach ($this->patterns as $pattern) {
                    if (preg_match($pattern, $unicodeDecoded)) {
                        return true;
                    }
                }
            }
        }

        return false;
    }

    /**
     * Check if value contains any HTML tags.
     *
     * @param string $value Input value
     * @return bool True if HTML tags found
     */
    protected function hasHtmlTags(string $value): bool
    {
        return $value !== strip_tags($value);
    }

    /**
     * Check for disallowed HTML tags.
     *
     * @param string $value Input value
     * @return bool True if disallowed tags found
     */
    protected function hasDisallowedTags(string $value): bool
    {
        // Strip allowed tags
        $allowedTagsString = '<' . implode('><', $this->allowedTags) . '>';
        $stripped = strip_tags($value, $allowedTagsString);

        // If stripping all tags except allowed changes value, disallowed tags exist
        return strip_tags($value) !== strip_tags($stripped);
    }

    /**
     * Check for strict mode violations.
     *
     * Additional checks in strict mode:
     * - Suspicious character combinations
     * - Nested encoding
     * - Mixed case evasion
     *
     * @param string $value Input value
     * @return bool True if violation detected
     */
    protected function hasStrictViolation(string $value): bool
    {
        // Check for mixed case evasion (e.g., <ScRiPt>)
        $lower = strtolower($value);

        $suspiciousKeywords = [
            'script',
            'javascript',
            'onerror',
            'onload',
            'onclick',
            'eval',
            'alert',
        ];

        foreach ($suspiciousKeywords as $keyword) {
            if (str_contains($lower, $keyword)) {
                return true;
            }
        }

        // Check for null bytes
        if (str_contains($value, "\0")) {
            return true;
        }

        // Check for excessive special characters (possible obfuscation)
        $specialChars = preg_match_all('/[<>"\'\(\)\[\]\{\};]/', $value);

        if ($specialChars > strlen($value) / 4) {
            return true;
        }

        return false;
    }
}
