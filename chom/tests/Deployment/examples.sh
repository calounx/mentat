#!/bin/bash

# Deployment Test Suite - Usage Examples
# This script demonstrates various ways to run the deployment test suite

echo "========================================="
echo "Deployment Test Suite - Usage Examples"
echo "========================================="
echo ""

# Example 1: Quick smoke test before deployment
echo "Example 1: Quick Smoke Test (30 seconds)"
echo "Command: ./tests/Deployment/run-deployment-tests.sh --smoke-only"
echo ""

# Example 2: Full integration test suite
echo "Example 2: Full Integration Tests (5-10 minutes)"
echo "Command: ./tests/Deployment/run-deployment-tests.sh --integration-only"
echo ""

# Example 3: All tests with coverage
echo "Example 3: Complete Test Suite with Coverage (20-45 minutes)"
echo "Command: ./tests/Deployment/run-deployment-tests.sh --all --coverage"
echo ""

# Example 4: Load tests
echo "Example 4: Performance/Load Tests (5-15 minutes)"
echo "Command: ./tests/Deployment/run-deployment-tests.sh --load --verbose"
echo ""

# Example 5: Chaos tests
echo "Example 5: Failure Scenario Tests (10-20 minutes)"
echo "Command: ./tests/Deployment/run-deployment-tests.sh --chaos"
echo ""

# Example 6: Using PHPUnit directly
echo "Example 6: Run Specific Test Suite with PHPUnit"
echo "Command: vendor/bin/phpunit --testsuite DeploymentSmoke"
echo ""

# Example 7: Run specific test file
echo "Example 7: Run Specific Test File"
echo "Command: vendor/bin/phpunit tests/Deployment/Smoke/CriticalPathTest.php"
echo ""

# Example 8: Run tests by group
echo "Example 8: Run Tests by Group"
echo "Command: vendor/bin/phpunit --group smoke"
echo "Command: vendor/bin/phpunit --group integration"
echo "Command: vendor/bin/phpunit --group load"
echo "Command: vendor/bin/phpunit --group chaos"
echo ""

# Example 9: Run specific test method
echo "Example 9: Run Specific Test Method"
echo "Command: vendor/bin/phpunit --filter test_database_is_accessible"
echo ""

# Example 10: Exclude slow tests
echo "Example 10: Run Fast Tests Only"
echo "Command: vendor/bin/phpunit --exclude-group slow tests/Deployment/"
echo ""

echo "========================================="
echo "Pre-Deployment Workflow Example"
echo "========================================="
echo ""
echo "# Step 1: Run smoke tests (quick validation)"
echo "./tests/Deployment/run-deployment-tests.sh --smoke-only"
echo ""
echo "# Step 2: Run integration tests (comprehensive)"
echo "./tests/Deployment/run-deployment-tests.sh --integration-only"
echo ""
echo "# Step 3: Review test results"
echo "cat storage/test-reports/*/summary.txt"
echo ""
echo "# Step 4: Proceed with deployment if tests pass"
echo "./chom/scripts/deploy-production.sh"
echo ""

echo "========================================="
echo "Post-Deployment Workflow Example"
echo "========================================="
echo ""
echo "# Step 1: Run smoke tests immediately"
echo "./tests/Deployment/run-deployment-tests.sh --smoke-only"
echo ""
echo "# Step 2: Run health checks"
echo "./chom/scripts/health-check.sh"
echo ""
echo "# Step 3: Monitor application for 5-10 minutes"
echo "tail -f storage/logs/laravel.log"
echo ""

echo "========================================="
echo "Troubleshooting Examples"
echo "========================================="
echo ""
echo "# View latest test results"
echo "cat storage/test-reports/*/summary.txt | tail -20"
echo ""
echo "# Run tests with verbose output"
echo "./tests/Deployment/run-deployment-tests.sh --smoke-only --verbose"
echo ""
echo "# Run PHPUnit with debug mode"
echo "vendor/bin/phpunit --verbose --debug tests/Deployment/Smoke/"
echo ""
echo "# Check test environment"
echo "php artisan db:show"
echo "redis-cli ping"
echo ""

echo "========================================="
echo "CI/CD Examples"
echo "========================================="
echo ""
echo "# Manual GitHub Actions trigger:"
echo "1. Go to GitHub Actions tab"
echo "2. Select 'Deployment Tests' workflow"
echo "3. Click 'Run workflow'"
echo "4. Select test suite (smoke/integration/all/load/chaos)"
echo "5. Click 'Run workflow'"
echo ""

echo "========================================="
echo "Performance Testing Examples"
echo "========================================="
echo ""
echo "# Run load tests and generate report"
echo "./tests/Deployment/run-deployment-tests.sh --load --verbose > load-test-results.txt"
echo ""
echo "# Extract performance metrics"
echo "grep -E '(avg|ms|seconds)' storage/test-reports/*/load.log"
echo ""

echo "========================================="
echo "For more information, see:"
echo "  - tests/Deployment/README.md"
echo "  - tests/Deployment/QUICK-REFERENCE.md"
echo "  - tests/Deployment/PERFORMANCE-BENCHMARKS.md"
echo "========================================="
