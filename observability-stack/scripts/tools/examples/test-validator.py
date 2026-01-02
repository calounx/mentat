#!/usr/bin/env python3
"""
Test Suite for Exporter Validator

Provides unit tests and integration tests for validate-exporters.py.
Run with: python3 test-validator.py
"""

import sys
import unittest
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from threading import Thread
from time import sleep
from typing import Optional

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    from validate_exporters import (
        PrometheusMetricParser,
        ExporterValidator,
        ValidationResult,
        MetricType,
        Severity
    )
except ImportError:
    # Handle module name with hyphens
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "validate_exporters",
        Path(__file__).parent.parent / "validate-exporters.py"
    )
    validate_exporters = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(validate_exporters)

    PrometheusMetricParser = validate_exporters.PrometheusMetricParser
    ExporterValidator = validate_exporters.ExporterValidator
    ValidationResult = validate_exporters.ValidationResult
    MetricType = validate_exporters.MetricType
    Severity = validate_exporters.Severity


# Test HTTP Server for mock exporter
class MockExporterHandler(BaseHTTPRequestHandler):
    """Mock exporter HTTP handler."""

    response_body: Optional[str] = None
    response_code: int = 200
    response_headers: dict = {'Content-Type': 'text/plain; version=0.0.4'}

    def do_GET(self):
        """Handle GET requests."""
        if self.path == '/metrics':
            self.send_response(self.response_code)
            for key, value in self.response_headers.items():
                self.send_header(key, value)
            self.end_headers()

            body = self.response_body or self.get_default_metrics()
            self.wfile.write(body.encode())
        else:
            self.send_response(404)
            self.end_headers()

    def get_default_metrics(self) -> str:
        """Default metrics response."""
        return """# HELP test_counter_total A test counter
# TYPE test_counter_total counter
test_counter_total 42

# HELP test_gauge A test gauge
# TYPE test_gauge gauge
test_gauge{label="value"} 3.14

# HELP test_histogram_seconds Test histogram
# TYPE test_histogram_seconds histogram
test_histogram_seconds_bucket{le="0.1"} 10
test_histogram_seconds_bucket{le="0.5"} 25
test_histogram_seconds_bucket{le="1.0"} 40
test_histogram_seconds_bucket{le="+Inf"} 50
test_histogram_seconds_sum 42.5
test_histogram_seconds_count 50
"""

    def log_message(self, format, *args):
        """Suppress logging."""
        pass


class TestPrometheusMetricParser(unittest.TestCase):
    """Test cases for PrometheusMetricParser."""

    def setUp(self):
        """Set up test fixtures."""
        self.parser = PrometheusMetricParser()

    def test_parse_simple_counter(self):
        """Test parsing a simple counter metric."""
        content = """# HELP test_total A test counter
# TYPE test_total counter
test_total 42
"""
        metrics, issues = self.parser.parse(content)

        self.assertEqual(len(metrics), 1)
        self.assertEqual(metrics[0].name, 'test')
        self.assertEqual(metrics[0].metric_type, MetricType.COUNTER)
        self.assertEqual(metrics[0].help_text, 'A test counter')
        self.assertEqual(len(metrics[0].samples), 1)
        self.assertEqual(metrics[0].samples[0]['value'], 42)

    def test_parse_gauge_with_labels(self):
        """Test parsing gauge with labels."""
        content = """# HELP test_gauge A test gauge
# TYPE test_gauge gauge
test_gauge{label1="value1",label2="value2"} 3.14
"""
        metrics, issues = self.parser.parse(content)

        self.assertEqual(len(metrics), 1)
        self.assertEqual(metrics[0].metric_type, MetricType.GAUGE)
        self.assertEqual(len(metrics[0].samples), 1)
        self.assertIn('label1', metrics[0].samples[0]['labels'])
        self.assertIn('label2', metrics[0].samples[0]['labels'])
        self.assertEqual(metrics[0].samples[0]['labels']['label1'], 'value1')

    def test_parse_histogram(self):
        """Test parsing histogram metrics."""
        content = """# HELP test_seconds Test histogram
# TYPE test_seconds histogram
test_seconds_bucket{le="0.1"} 10
test_seconds_bucket{le="0.5"} 25
test_seconds_bucket{le="+Inf"} 50
test_seconds_sum 42.5
test_seconds_count 50
"""
        metrics, issues = self.parser.parse(content)

        self.assertEqual(len(metrics), 1)
        self.assertEqual(metrics[0].name, 'test_seconds')
        self.assertEqual(metrics[0].metric_type, MetricType.HISTOGRAM)
        # Should have bucket, sum, and count samples
        self.assertGreater(len(metrics[0].samples), 3)

    def test_validate_metric_name_valid(self):
        """Test valid metric name validation."""
        valid_names = [
            'test_metric',
            'test_metric_total',
            'test:metric',
            'TestMetric123',
            'test_metric_seconds'
        ]

        for name in valid_names:
            error = self.parser.validate_metric_name(name)
            self.assertIsNone(error, f"Valid name '{name}' should not have error")

    def test_validate_metric_name_invalid(self):
        """Test invalid metric name validation."""
        invalid_names = [
            '_test',  # Starts with underscore
            'test-metric',  # Contains hyphen
            '123test',  # Starts with number
            'test metric',  # Contains space
        ]

        for name in invalid_names:
            error = self.parser.validate_metric_name(name)
            self.assertIsNotNone(error, f"Invalid name '{name}' should have error")

    def test_validate_label_name(self):
        """Test label name validation."""
        # Valid labels
        self.assertIsNone(self.parser.validate_label_name('test_label'))
        self.assertIsNone(self.parser.validate_label_name('TestLabel'))

        # Invalid labels
        self.assertIsNotNone(self.parser.validate_label_name('__reserved'))
        self.assertIsNotNone(self.parser.validate_label_name('test-label'))
        self.assertIsNotNone(self.parser.validate_label_name('_starts_underscore'))

    def test_parse_with_comments(self):
        """Test parsing with comment lines."""
        content = """# This is a comment
# HELP test_total A counter
# TYPE test_total counter
test_total 42
# Another comment
"""
        metrics, issues = self.parser.parse(content)

        self.assertEqual(len(metrics), 1)
        self.assertEqual(len(issues), 0)

    def test_parse_invalid_syntax(self):
        """Test parsing with syntax errors."""
        content = """# HELP test_total A counter
# TYPE test_total counter
test_total invalid_value
"""
        metrics, issues = self.parser.parse(content)

        # Should handle gracefully
        self.assertIsInstance(metrics, list)
        # May have parsing issues
        self.assertGreaterEqual(len(issues), 0)


class TestExporterValidator(unittest.TestCase):
    """Test cases for ExporterValidator."""

    @classmethod
    def setUpClass(cls):
        """Start mock HTTP server."""
        cls.server_port = 18080
        cls.server = HTTPServer(('localhost', cls.server_port), MockExporterHandler)
        cls.server_thread = Thread(target=cls.server.serve_forever, daemon=True)
        cls.server_thread.start()
        sleep(0.1)  # Give server time to start

    @classmethod
    def tearDownClass(cls):
        """Stop mock HTTP server."""
        cls.server.shutdown()

    def setUp(self):
        """Set up test fixtures."""
        self.validator = ExporterValidator(timeout=5)
        self.endpoint = f'http://localhost:{self.server_port}/metrics'

    def test_validate_healthy_endpoint(self):
        """Test validation of healthy endpoint."""
        result = self.validator.validate_endpoint(self.endpoint)

        self.assertIsInstance(result, ValidationResult)
        self.assertEqual(result.endpoint, self.endpoint)
        self.assertGreater(result.total_metrics, 0)
        self.assertGreater(result.total_samples, 0)
        self.assertGreaterEqual(result.duration_ms, 0)

    def test_validate_endpoint_with_issues(self):
        """Test validation detecting issues."""
        # Create content with naming issues
        MockExporterHandler.response_body = """# HELP bad_counter Missing _total suffix
# TYPE bad_counter counter
bad_counter 42

# HELP _invalid_name Starts with underscore
# TYPE _invalid_name gauge
_invalid_name 1
"""

        result = self.validator.validate_endpoint(self.endpoint)

        # Should detect naming issues
        naming_issues = [i for i in result.issues if i.category == 'naming']
        self.assertGreater(len(naming_issues), 0)

        # Reset to default
        MockExporterHandler.response_body = None

    def test_validate_high_cardinality(self):
        """Test high cardinality detection."""
        # Create metric with many unique label combinations
        lines = ['# HELP test_total Test metric', '# TYPE test_total counter']
        for i in range(100):
            lines.append(f'test_total{{id="{i}"}} {i}')

        MockExporterHandler.response_body = '\n'.join(lines)

        # Use low cardinality threshold for testing
        validator = ExporterValidator(max_cardinality=50)
        result = validator.validate_endpoint(self.endpoint)

        # Should detect high cardinality
        cardinality_issues = [i for i in result.issues if i.category == 'cardinality']
        self.assertGreater(len(cardinality_issues), 0)

        # Reset
        MockExporterHandler.response_body = None

    def test_validate_connection_error(self):
        """Test handling of connection errors."""
        invalid_endpoint = 'http://localhost:19999/metrics'
        result = self.validator.validate_endpoint(invalid_endpoint)

        # Should have connectivity issue
        connectivity_issues = [i for i in result.issues if i.category == 'connectivity']
        self.assertGreater(len(connectivity_issues), 0)
        self.assertTrue(result.has_critical)

    def test_validate_http_error(self):
        """Test handling of HTTP errors."""
        # Configure mock to return 500 error
        original_code = MockExporterHandler.response_code
        MockExporterHandler.response_code = 500

        result = self.validator.validate_endpoint(self.endpoint)

        # Should have HTTP issue
        http_issues = [i for i in result.issues if i.category == 'http']
        self.assertGreater(len(http_issues), 0)
        self.assertTrue(result.has_critical)

        # Reset
        MockExporterHandler.response_code = original_code

    def test_exit_code_logic(self):
        """Test exit code determination."""
        result = ValidationResult(
            endpoint='test',
            timestamp=None,
            duration_ms=0,
            total_metrics=0,
            total_samples=0
        )

        # No issues = exit 0
        self.assertEqual(result.exit_code, 0)

        # Warning only = exit 1
        from validate_exporters import ValidationIssue
        result.issues.append(ValidationIssue(
            severity=Severity.WARNING,
            category='test',
            message='test warning'
        ))
        self.assertEqual(result.exit_code, 1)

        # Critical = exit 2
        result.issues.append(ValidationIssue(
            severity=Severity.CRITICAL,
            category='test',
            message='test critical'
        ))
        self.assertEqual(result.exit_code, 2)


class TestIntegration(unittest.TestCase):
    """Integration tests."""

    @classmethod
    def setUpClass(cls):
        """Start mock HTTP server."""
        cls.server_port = 18081
        cls.server = HTTPServer(('localhost', cls.server_port), MockExporterHandler)
        cls.server_thread = Thread(target=cls.server.serve_forever, daemon=True)
        cls.server_thread.start()
        sleep(0.1)

    @classmethod
    def tearDownClass(cls):
        """Stop mock HTTP server."""
        cls.server.shutdown()

    def test_end_to_end_validation(self):
        """Test complete validation workflow."""
        validator = ExporterValidator()
        endpoint = f'http://localhost:{self.server_port}/metrics'

        # Run validation
        result = validator.validate_endpoint(endpoint)

        # Verify result structure
        self.assertIsInstance(result, ValidationResult)
        self.assertEqual(result.endpoint, endpoint)
        self.assertGreater(result.duration_ms, 0)

        # Should have parsed metrics
        self.assertGreater(result.total_metrics, 0)
        self.assertGreater(result.total_samples, 0)

        # Should have metrics info
        self.assertGreater(len(result.metrics_info), 0)

        # Verify metric details
        for metric in result.metrics_info:
            self.assertIsNotNone(metric.name)
            self.assertIsInstance(metric.metric_type, MetricType)
            self.assertIsInstance(metric.samples, list)


def run_tests():
    """Run all tests."""
    # Create test suite
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()

    # Add test classes
    suite.addTests(loader.loadTestsFromTestCase(TestPrometheusMetricParser))
    suite.addTests(loader.loadTestsFromTestCase(TestExporterValidator))
    suite.addTests(loader.loadTestsFromTestCase(TestIntegration))

    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    # Return exit code
    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    sys.exit(run_tests())
