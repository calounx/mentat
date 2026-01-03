<?php

declare(strict_types=1);

namespace Tests\Unit\Rules;

use App\Rules\NoSqlInjectionRule;
use Tests\TestCase;

class NoSqlInjectionRuleTest extends TestCase
{
    private NoSqlInjectionRule $rule;

    protected function setUp(): void
    {
        parent::setUp();
        $this->rule = new NoSqlInjectionRule();
    }

    public function test_accepts_safe_input(): void
    {
        $safeInputs = [
            'normal text',
            'user@example.com',
            'Product Name 123',
            'Description with spaces',
            'Text with-dashes',
            'Text_with_underscores',
        ];

        foreach ($safeInputs as $input) {
            $this->assertTrue(
                $this->rule->passes('field', $input),
                "Failed to accept safe input: {$input}"
            );
        }
    }

    public function test_rejects_sql_union_attacks(): void
    {
        $sqlInjections = [
            "1' UNION SELECT * FROM users--",
            "1' UNION ALL SELECT null, username, password FROM users--",
            "admin' UNION SELECT 1,2,3--",
            "' UNION SELECT table_name FROM information_schema.tables--",
        ];

        foreach ($sqlInjections as $injection) {
            $this->assertFalse(
                $this->rule->passes('field', $injection),
                "Failed to reject SQL injection: {$injection}"
            );
        }
    }

    public function test_rejects_sql_comment_attacks(): void
    {
        $sqlComments = [
            "admin'--",
            "admin'#",
            "admin'/*",
            "1' OR '1'='1'--",
            "1' OR 1=1--",
        ];

        foreach ($sqlComments as $comment) {
            $this->assertFalse($this->rule->passes('field', $comment));
        }
    }

    public function test_rejects_sql_drop_statements(): void
    {
        $dropStatements = [
            "'; DROP TABLE users;--",
            "1'; DROP DATABASE mydb;--",
            "admin'; DROP TABLE sessions;--",
            "test' DROP TABLE--",
        ];

        foreach ($dropStatements as $statement) {
            $this->assertFalse($this->rule->passes('field', $statement));
        }
    }

    public function test_rejects_sql_delete_statements(): void
    {
        $deleteStatements = [
            "'; DELETE FROM users WHERE 1=1;--",
            "admin'; DELETE FROM users;--",
            "1' OR 1=1; DELETE FROM sessions--",
        ];

        foreach ($deleteStatements as $statement) {
            $this->assertFalse($this->rule->passes('field', $statement));
        }
    }

    public function test_rejects_sql_update_statements(): void
    {
        $updateStatements = [
            "'; UPDATE users SET password='hacked' WHERE 1=1;--",
            "admin'; UPDATE users SET role='admin';--",
        ];

        foreach ($updateStatements as $statement) {
            $this->assertFalse($this->rule->passes('field', $statement));
        }
    }

    public function test_rejects_sql_insert_statements(): void
    {
        $insertStatements = [
            "'; INSERT INTO users (username, password) VALUES ('hacker', 'pass');--",
            "admin'; INSERT INTO sessions VALUES (1,2,3);--",
        ];

        foreach ($insertStatements as $statement) {
            $this->assertFalse($this->rule->passes('field', $statement));
        }
    }

    public function test_rejects_boolean_based_attacks(): void
    {
        $booleanAttacks = [
            "1' OR '1'='1",
            "1' OR 1=1",
            "admin' OR 'a'='a",
            "' OR '1'='1'--",
            "' OR 1=1--",
            "1' AND '1'='1",
        ];

        foreach ($booleanAttacks as $attack) {
            $this->assertFalse($this->rule->passes('field', $attack));
        }
    }

    public function test_rejects_time_based_blind_sql_injection(): void
    {
        $timeBasedAttacks = [
            "1' AND SLEEP(5)--",
            "admin' WAITFOR DELAY '00:00:05'--",
            "1'; SELECT SLEEP(5);--",
            "' OR IF(1=1, SLEEP(5), 0)--",
        ];

        foreach ($timeBasedAttacks as $attack) {
            $this->assertFalse($this->rule->passes('field', $attack));
        }
    }

    public function test_rejects_stacked_queries(): void
    {
        $stackedQueries = [
            "admin'; SELECT * FROM users;--",
            "1'; SELECT password FROM users WHERE id=1;--",
            "test'; EXEC sp_executesql;--",
        ];

        foreach ($stackedQueries as $query) {
            $this->assertFalse($this->rule->passes('field', $query));
        }
    }

    public function test_rejects_hex_encoded_attacks(): void
    {
        $hexAttacks = [
            "0x61646D696E",
            "CHAR(97,100,109,105,110)",
            "0x' UNION SELECT--",
        ];

        foreach ($hexAttacks as $attack) {
            $this->assertFalse($this->rule->passes('field', $attack));
        }
    }

    public function test_rejects_information_schema_queries(): void
    {
        $schemaQueries = [
            "' UNION SELECT * FROM information_schema.tables--",
            "' UNION SELECT column_name FROM information_schema.columns--",
            "1' AND (SELECT * FROM information_schema.tables)--",
        ];

        foreach ($schemaQueries as $query) {
            $this->assertFalse($this->rule->passes('field', $query));
        }
    }

    public function test_rejects_mysql_functions(): void
    {
        $mysqlFunctions = [
            "CONCAT('a','b')",
            "SUBSTRING(password,1,1)",
            "ASCII(SUBSTRING(password,1,1))",
            "BENCHMARK(10000,MD5('test'))",
        ];

        foreach ($mysqlFunctions as $function) {
            $this->assertFalse($this->rule->passes('field', $function));
        }
    }

    public function test_rejects_error_based_attacks(): void
    {
        $errorAttacks = [
            "' AND 1=CONVERT(int, (SELECT @@version))--",
            "' AND extractvalue(1,concat(0x7e,(SELECT @@version)))--",
        ];

        foreach ($errorAttacks as $attack) {
            $this->assertFalse($this->rule->passes('field', $attack));
        }
    }

    public function test_accepts_legitimate_sql_like_text(): void
    {
        // Text that looks like SQL but is actually legitimate user input
        $legitimateInputs = [
            "How to use SELECT in Excel",
            "My email is admin@example.com",
            "The password should be strong",
        ];

        foreach ($legitimateInputs as $input) {
            $this->assertTrue(
                $this->rule->passes('field', $input),
                "Failed to accept legitimate input: {$input}"
            );
        }
    }

    public function test_handles_case_insensitive_attacks(): void
    {
        $caseVariations = [
            "1' UnIoN SeLeCt * FrOm users--",
            "AdMiN' oR '1'='1",
            "1'; dRoP tAbLe users;--",
        ];

        foreach ($caseVariations as $variation) {
            $this->assertFalse($this->rule->passes('field', $variation));
        }
    }

    public function test_rejects_obfuscated_attacks(): void
    {
        $obfuscatedAttacks = [
            "1'/**/UNION/**/SELECT",
            "admin'||'1'='1",
            "1'/*comment*/OR/*comment*/'1'='1",
        ];

        foreach ($obfuscatedAttacks as $attack) {
            $this->assertFalse($this->rule->passes('field', $attack));
        }
    }

    public function test_handles_null_byte_attacks(): void
    {
        $nullByteAttacks = [
            "admin\x00' OR 1=1--",
            "test\0' UNION SELECT--",
        ];

        foreach ($nullByteAttacks as $attack) {
            $this->assertFalse($this->rule->passes('field', $attack));
        }
    }

    public function test_returns_descriptive_error_message(): void
    {
        $this->rule->passes('field', "1' OR 1=1--");

        $message = $this->rule->message();

        $this->assertIsString($message);
        $this->assertStringContainsString('SQL', $message);
        $this->assertStringContainsString('injection', strtolower($message));
    }

    public function test_handles_empty_string(): void
    {
        $this->assertTrue($this->rule->passes('field', ''));
    }

    public function test_handles_null_value(): void
    {
        $this->assertTrue($this->rule->passes('field', null));
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

    public function test_rejects_postgres_specific_attacks(): void
    {
        $postgresAttacks = [
            "'; SELECT pg_sleep(10);--",
            "' AND 1=1; COPY users TO '/tmp/output';--",
            "admin'; SELECT version();--",
        ];

        foreach ($postgresAttacks as $attack) {
            $this->assertFalse($this->rule->passes('field', $attack));
        }
    }

    public function test_rejects_oracle_specific_attacks(): void
    {
        $oracleAttacks = [
            "' UNION SELECT NULL FROM DUAL--",
            "admin' AND DBMS_PIPE.RECEIVE_MESSAGE('a',10)=1--",
        ];

        foreach ($oracleAttacks as $attack) {
            $this->assertFalse($this->rule->passes('field', $attack));
        }
    }

    public function test_rejects_mssql_specific_attacks(): void
    {
        $mssqlAttacks = [
            "'; EXEC xp_cmdshell 'dir';--",
            "admin'; EXEC sp_executesql;--",
            "1' WAITFOR DELAY '00:00:10'--",
        ];

        foreach ($mssqlAttacks as $attack) {
            $this->assertFalse($this->rule->passes('field', $attack));
        }
    }

    public function test_accepts_urls_with_query_parameters(): void
    {
        $urls = [
            'https://example.com?param=value',
            'https://api.example.com?user=john&sort=asc',
        ];

        foreach ($urls as $url) {
            $this->assertTrue(
                $this->rule->passes('field', $url),
                "Should accept URL: {$url}"
            );
        }
    }

    public function test_accepts_json_strings(): void
    {
        $jsonStrings = [
            '{"name": "John", "age": 30}',
            '{"query": "SELECT * FROM table"}',
        ];

        foreach ($jsonStrings as $json) {
            $this->assertTrue(
                $this->rule->passes('field', $json),
                "Should accept JSON: {$json}"
            );
        }
    }

    public function test_performance_with_large_input(): void
    {
        $largeInput = str_repeat('a', 10000);

        $startTime = microtime(true);

        $this->rule->passes('field', $largeInput);

        $endTime = microtime(true);
        $duration = ($endTime - $startTime) * 1000;

        // Validation should complete in under 10ms even for large input
        $this->assertLessThan(10, $duration);
    }

    public function test_performance_with_many_validations(): void
    {
        $inputs = array_merge(
            array_fill(0, 50, 'safe input'),
            array_fill(0, 50, "1' OR 1=1--")
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
