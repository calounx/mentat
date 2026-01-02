#!/usr/bin/env python3
"""
Prometheus Exporter Metrics Validator

Validates exporter metrics format, health, and integration with Prometheus.
Provides comprehensive checks for metric quality, cardinality, and staleness.

Exit Codes:
    0: All checks passed (healthy)
    1: Warnings detected (non-critical issues)
    2: Critical errors detected (failures)
"""

import argparse
import json
import logging
import re
import sys
import time
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple
from urllib.parse import urljoin, urlparse

try:
    import requests
    from requests.adapters import HTTPAdapter
    from requests.packages.urllib3.util.retry import Retry
except ImportError:
    print("Error: requests library is required. Install with: pip install requests", file=sys.stderr)
    sys.exit(2)


# ANSI color codes
class Colors:
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    MAGENTA = '\033[95m'
    CYAN = '\033[96m'
    BOLD = '\033[1m'
    RESET = '\033[0m'


class Severity(Enum):
    """Issue severity levels."""
    INFO = "INFO"
    WARNING = "WARNING"
    CRITICAL = "CRITICAL"


class MetricType(Enum):
    """Prometheus metric types."""
    COUNTER = "counter"
    GAUGE = "gauge"
    HISTOGRAM = "histogram"
    SUMMARY = "summary"
    UNTYPED = "untyped"


@dataclass
class ValidationIssue:
    """Represents a validation issue."""
    severity: Severity
    category: str
    message: str
    metric_name: Optional[str] = None
    details: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            "severity": self.severity.value,
            "category": self.category,
            "message": self.message,
            "metric_name": self.metric_name,
            "details": self.details
        }


@dataclass
class MetricInfo:
    """Information about a parsed metric."""
    name: str
    metric_type: MetricType
    help_text: str
    samples: List[Dict[str, Any]] = field(default_factory=list)
    label_names: Set[str] = field(default_factory=set)


@dataclass
class ValidationResult:
    """Results of validation checks."""
    endpoint: str
    timestamp: datetime
    duration_ms: float
    total_metrics: int
    total_samples: int
    issues: List[ValidationIssue] = field(default_factory=list)
    metrics_info: List[MetricInfo] = field(default_factory=list)

    @property
    def has_critical(self) -> bool:
        """Check if result has critical issues."""
        return any(issue.severity == Severity.CRITICAL for issue in self.issues)

    @property
    def has_warnings(self) -> bool:
        """Check if result has warnings."""
        return any(issue.severity == Severity.WARNING for issue in self.issues)

    @property
    def exit_code(self) -> int:
        """Determine appropriate exit code."""
        if self.has_critical:
            return 2
        elif self.has_warnings:
            return 1
        return 0

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            "endpoint": self.endpoint,
            "timestamp": self.timestamp.isoformat(),
            "duration_ms": self.duration_ms,
            "total_metrics": self.total_metrics,
            "total_samples": self.total_samples,
            "issues": [issue.to_dict() for issue in self.issues],
            "exit_code": self.exit_code
        }


class PrometheusMetricParser:
    """Parser for Prometheus text format metrics."""

    # Prometheus metric name validation regex
    METRIC_NAME_RE = re.compile(r'^[a-zA-Z_:][a-zA-Z0-9_:]*$')
    LABEL_NAME_RE = re.compile(r'^[a-zA-Z_][a-zA-Z0-9_]*$')

    def __init__(self):
        self.logger = logging.getLogger(__name__)

    def parse(self, content: str) -> Tuple[List[MetricInfo], List[ValidationIssue]]:
        """
        Parse Prometheus metrics from text format.

        Args:
            content: Raw metrics content

        Returns:
            Tuple of (metrics_info, parsing_issues)
        """
        metrics: Dict[str, MetricInfo] = {}
        issues: List[ValidationIssue] = []

        current_metric_name: Optional[str] = None
        current_type: Optional[MetricType] = None
        current_help: Optional[str] = None

        lines = content.strip().split('\n')

        for line_num, line in enumerate(lines, 1):
            line = line.strip()

            # Skip empty lines and comments (except TYPE and HELP)
            if not line or (line.startswith('#') and not line.startswith('# TYPE') and not line.startswith('# HELP')):
                continue

            try:
                # Parse TYPE directive
                if line.startswith('# TYPE'):
                    parts = line.split(None, 3)
                    if len(parts) >= 4:
                        metric_name = parts[2]
                        type_str = parts[3].lower()

                        try:
                            current_type = MetricType(type_str)
                        except ValueError:
                            current_type = MetricType.UNTYPED
                            issues.append(ValidationIssue(
                                severity=Severity.WARNING,
                                category="parsing",
                                message=f"Unknown metric type '{type_str}' at line {line_num}",
                                metric_name=metric_name
                            ))

                        current_metric_name = metric_name

                # Parse HELP directive
                elif line.startswith('# HELP'):
                    parts = line.split(None, 3)
                    if len(parts) >= 4:
                        metric_name = parts[2]
                        help_text = parts[3]
                        current_help = help_text
                        current_metric_name = metric_name

                # Parse metric sample
                elif not line.startswith('#'):
                    sample = self._parse_sample(line, line_num)
                    if sample:
                        base_name = self._get_base_metric_name(sample['name'])

                        # Initialize metric info if needed
                        if base_name not in metrics:
                            metrics[base_name] = MetricInfo(
                                name=base_name,
                                metric_type=current_type or MetricType.UNTYPED,
                                help_text=current_help or ""
                            )

                        # Add sample and extract label names
                        metrics[base_name].samples.append(sample)
                        metrics[base_name].label_names.update(sample['labels'].keys())

            except Exception as e:
                issues.append(ValidationIssue(
                    severity=Severity.WARNING,
                    category="parsing",
                    message=f"Failed to parse line {line_num}: {str(e)}",
                    details={"line": line}
                ))

        return list(metrics.values()), issues

    def _parse_sample(self, line: str, line_num: int) -> Optional[Dict[str, Any]]:
        """Parse a single metric sample line."""
        try:
            # Split metric name/labels from value and timestamp
            parts = line.split(None, 2)
            if len(parts) < 2:
                return None

            metric_part = parts[0]
            value = float(parts[1])
            timestamp = int(parts[2]) if len(parts) > 2 else None

            # Parse metric name and labels
            if '{' in metric_part:
                name, labels_str = metric_part.split('{', 1)
                labels_str = labels_str.rstrip('}')
                labels = self._parse_labels(labels_str)
            else:
                name = metric_part
                labels = {}

            return {
                'name': name,
                'labels': labels,
                'value': value,
                'timestamp': timestamp
            }
        except Exception as e:
            logging.debug(f"Failed to parse sample at line {line_num}: {e}")
            return None

    def _parse_labels(self, labels_str: str) -> Dict[str, str]:
        """Parse label key-value pairs."""
        labels = {}

        # Simple label parsing (handles quoted values)
        pattern = r'(\w+)="([^"]*)"'
        for match in re.finditer(pattern, labels_str):
            key, value = match.groups()
            labels[key] = value

        return labels

    def _get_base_metric_name(self, name: str) -> str:
        """
        Get base metric name by removing common suffixes.

        For histograms and summaries, multiple related metrics exist:
        - histogram: _bucket, _count, _sum
        - summary: _count, _sum, quantiles
        """
        suffixes = ['_bucket', '_count', '_sum', '_total']
        for suffix in suffixes:
            if name.endswith(suffix):
                return name[:-len(suffix)]
        return name

    def validate_metric_name(self, name: str) -> Optional[str]:
        """
        Validate metric name follows Prometheus conventions.

        Returns:
            Error message if invalid, None if valid
        """
        if not self.METRIC_NAME_RE.match(name):
            return f"Invalid metric name format: {name}"

        # Check for common naming issues
        if name.startswith('_'):
            return f"Metric name should not start with underscore: {name}"

        # Recommend unit suffixes
        known_units = ['seconds', 'bytes', 'ratio', 'percent', 'total']
        has_unit = any(name.endswith(f'_{unit}') for unit in known_units)

        # This is just a recommendation, not an error
        if not has_unit and not name.endswith('_info'):
            logging.debug(f"Metric {name} may benefit from a unit suffix")

        return None

    def validate_label_name(self, name: str) -> Optional[str]:
        """Validate label name follows Prometheus conventions."""
        if not self.LABEL_NAME_RE.match(name):
            return f"Invalid label name format: {name}"

        if name.startswith('_'):
            return f"Label name should not start with underscore: {name}"

        # Reserved label names
        if name.startswith('__'):
            return f"Label name uses reserved prefix '__': {name}"

        return None


class ExporterValidator:
    """Main validator for Prometheus exporters."""

    def __init__(self,
                 timeout: int = 10,
                 max_cardinality: int = 1000,
                 staleness_threshold: int = 300):
        """
        Initialize validator.

        Args:
            timeout: HTTP request timeout in seconds
            max_cardinality: Maximum allowed label cardinality per metric
            staleness_threshold: Maximum metric age in seconds
        """
        self.timeout = timeout
        self.max_cardinality = max_cardinality
        self.staleness_threshold = staleness_threshold
        self.logger = logging.getLogger(__name__)
        self.parser = PrometheusMetricParser()

        # Setup requests session with retries
        self.session = requests.Session()
        retry_strategy = Retry(
            total=3,
            backoff_factor=1,
            status_forcelist=[429, 500, 502, 503, 504],
        )
        adapter = HTTPAdapter(max_retries=retry_strategy)
        self.session.mount("http://", adapter)
        self.session.mount("https://", adapter)

    def validate_endpoint(self, endpoint: str) -> ValidationResult:
        """
        Validate a single exporter endpoint.

        Args:
            endpoint: URL of the exporter metrics endpoint

        Returns:
            ValidationResult with all findings
        """
        start_time = time.time()
        result = ValidationResult(
            endpoint=endpoint,
            timestamp=datetime.now(),
            duration_ms=0,
            total_metrics=0,
            total_samples=0
        )

        try:
            # Fetch metrics
            self.logger.info(f"Fetching metrics from {endpoint}")
            response = self.session.get(endpoint, timeout=self.timeout)

            # Check HTTP status
            if response.status_code != 200:
                result.issues.append(ValidationIssue(
                    severity=Severity.CRITICAL,
                    category="http",
                    message=f"HTTP {response.status_code}: {response.reason}",
                    details={"status_code": response.status_code}
                ))
                return result

            # Check Content-Type
            content_type = response.headers.get('Content-Type', '')
            if 'text/plain' not in content_type and 'text/html' not in content_type:
                result.issues.append(ValidationIssue(
                    severity=Severity.WARNING,
                    category="http",
                    message=f"Unexpected Content-Type: {content_type}",
                    details={"content_type": content_type}
                ))

            # Parse metrics
            metrics_info, parse_issues = self.parser.parse(response.text)
            result.issues.extend(parse_issues)
            result.metrics_info = metrics_info
            result.total_metrics = len(metrics_info)
            result.total_samples = sum(len(m.samples) for m in metrics_info)

            # Run validation checks
            self._check_duplicate_metrics(metrics_info, result)
            self._check_metric_naming(metrics_info, result)
            self._check_label_cardinality(metrics_info, result)
            self._check_metric_staleness(metrics_info, result)
            self._check_metric_types(metrics_info, result)

        except requests.exceptions.Timeout:
            result.issues.append(ValidationIssue(
                severity=Severity.CRITICAL,
                category="connectivity",
                message=f"Request timeout after {self.timeout}s",
                details={"timeout": self.timeout}
            ))
        except requests.exceptions.ConnectionError as e:
            result.issues.append(ValidationIssue(
                severity=Severity.CRITICAL,
                category="connectivity",
                message=f"Connection failed: {str(e)}",
                details={"error": str(e)}
            ))
        except Exception as e:
            result.issues.append(ValidationIssue(
                severity=Severity.CRITICAL,
                category="error",
                message=f"Unexpected error: {str(e)}",
                details={"error": str(e)}
            ))
        finally:
            result.duration_ms = (time.time() - start_time) * 1000

        return result

    def _check_duplicate_metrics(self, metrics: List[MetricInfo], result: ValidationResult) -> None:
        """Check for duplicate metric definitions."""
        seen_names = set()
        for metric in metrics:
            if metric.name in seen_names:
                result.issues.append(ValidationIssue(
                    severity=Severity.CRITICAL,
                    category="validation",
                    message="Duplicate metric name",
                    metric_name=metric.name
                ))
            seen_names.add(metric.name)

    def _check_metric_naming(self, metrics: List[MetricInfo], result: ValidationResult) -> None:
        """Validate metric naming conventions."""
        for metric in metrics:
            # Check metric name format
            error = self.parser.validate_metric_name(metric.name)
            if error:
                result.issues.append(ValidationIssue(
                    severity=Severity.WARNING,
                    category="naming",
                    message=error,
                    metric_name=metric.name
                ))

            # Check label names
            for label_name in metric.label_names:
                error = self.parser.validate_label_name(label_name)
                if error:
                    result.issues.append(ValidationIssue(
                        severity=Severity.WARNING,
                        category="naming",
                        message=error,
                        metric_name=metric.name,
                        details={"label": label_name}
                    ))

    def _check_label_cardinality(self, metrics: List[MetricInfo], result: ValidationResult) -> None:
        """Check for high cardinality metrics."""
        for metric in metrics:
            cardinality = len(metric.samples)

            if cardinality > self.max_cardinality:
                result.issues.append(ValidationIssue(
                    severity=Severity.CRITICAL,
                    category="cardinality",
                    message=f"High cardinality detected: {cardinality} unique label sets",
                    metric_name=metric.name,
                    details={
                        "cardinality": cardinality,
                        "threshold": self.max_cardinality
                    }
                ))
            elif cardinality > self.max_cardinality * 0.7:
                result.issues.append(ValidationIssue(
                    severity=Severity.WARNING,
                    category="cardinality",
                    message=f"Approaching high cardinality: {cardinality} unique label sets",
                    metric_name=metric.name,
                    details={
                        "cardinality": cardinality,
                        "threshold": self.max_cardinality
                    }
                ))

    def _check_metric_staleness(self, metrics: List[MetricInfo], result: ValidationResult) -> None:
        """Check for stale metrics based on timestamp."""
        current_time = time.time() * 1000  # Convert to milliseconds

        for metric in metrics:
            for sample in metric.samples:
                if sample['timestamp']:
                    age_ms = current_time - sample['timestamp']
                    age_seconds = age_ms / 1000

                    if age_seconds > self.staleness_threshold:
                        result.issues.append(ValidationIssue(
                            severity=Severity.WARNING,
                            category="staleness",
                            message=f"Metric appears stale (age: {age_seconds:.0f}s)",
                            metric_name=metric.name,
                            details={
                                "age_seconds": age_seconds,
                                "threshold": self.staleness_threshold
                            }
                        ))
                        break  # Only report once per metric

    def _check_metric_types(self, metrics: List[MetricInfo], result: ValidationResult) -> None:
        """Validate metric type consistency."""
        for metric in metrics:
            # Check if type is defined
            if metric.metric_type == MetricType.UNTYPED:
                result.issues.append(ValidationIssue(
                    severity=Severity.INFO,
                    category="type",
                    message="Metric type not specified",
                    metric_name=metric.name
                ))

            # Check counter naming convention
            if metric.metric_type == MetricType.COUNTER:
                if not metric.name.endswith('_total'):
                    result.issues.append(ValidationIssue(
                        severity=Severity.WARNING,
                        category="naming",
                        message="Counter metric should end with '_total'",
                        metric_name=metric.name
                    ))

    def validate_prometheus_scraping(self,
                                     prometheus_url: str,
                                     target_job: Optional[str] = None) -> ValidationResult:
        """
        Validate that Prometheus is successfully scraping targets.

        Args:
            prometheus_url: Base URL of Prometheus server
            target_job: Optional job name to filter targets

        Returns:
            ValidationResult with Prometheus integration checks
        """
        result = ValidationResult(
            endpoint=prometheus_url,
            timestamp=datetime.now(),
            duration_ms=0,
            total_metrics=0,
            total_samples=0
        )

        start_time = time.time()

        try:
            # Query targets API
            targets_url = urljoin(prometheus_url, '/api/v1/targets')
            response = self.session.get(targets_url, timeout=self.timeout)

            if response.status_code != 200:
                result.issues.append(ValidationIssue(
                    severity=Severity.CRITICAL,
                    category="prometheus",
                    message=f"Failed to query Prometheus API: HTTP {response.status_code}",
                    details={"status_code": response.status_code}
                ))
                return result

            data = response.json()

            if data.get('status') != 'success':
                result.issues.append(ValidationIssue(
                    severity=Severity.CRITICAL,
                    category="prometheus",
                    message="Prometheus API returned error",
                    details={"response": data}
                ))
                return result

            active_targets = data.get('data', {}).get('activeTargets', [])

            # Filter by job if specified
            if target_job:
                active_targets = [t for t in active_targets if t.get('labels', {}).get('job') == target_job]

            # Check target health
            for target in active_targets:
                health = target.get('health', 'unknown')
                job = target.get('labels', {}).get('job', 'unknown')
                instance = target.get('labels', {}).get('instance', 'unknown')

                if health != 'up':
                    result.issues.append(ValidationIssue(
                        severity=Severity.CRITICAL,
                        category="prometheus",
                        message=f"Target down: {job}/{instance}",
                        details={
                            "job": job,
                            "instance": instance,
                            "health": health,
                            "last_error": target.get('lastError', '')
                        }
                    ))

                # Check scrape duration
                scrape_duration = target.get('lastScrapeDuration', 0)
                if scrape_duration > 10:  # More than 10 seconds
                    result.issues.append(ValidationIssue(
                        severity=Severity.WARNING,
                        category="performance",
                        message=f"Slow scrape: {job}/{instance} ({scrape_duration:.2f}s)",
                        details={
                            "job": job,
                            "instance": instance,
                            "duration": scrape_duration
                        }
                    ))

            result.total_metrics = len(active_targets)

        except Exception as e:
            result.issues.append(ValidationIssue(
                severity=Severity.CRITICAL,
                category="error",
                message=f"Failed to validate Prometheus scraping: {str(e)}",
                details={"error": str(e)}
            ))
        finally:
            result.duration_ms = (time.time() - start_time) * 1000

        return result


class OutputFormatter:
    """Format validation results for different output types."""

    @staticmethod
    def print_human_readable(results: List[ValidationResult], verbose: bool = False) -> None:
        """Print results in human-readable format."""
        print(f"\n{Colors.BOLD}{'='*80}{Colors.RESET}")
        print(f"{Colors.BOLD}Prometheus Exporter Validation Report{Colors.RESET}")
        print(f"{Colors.BOLD}{'='*80}{Colors.RESET}\n")

        for result in results:
            # Header
            print(f"{Colors.CYAN}{Colors.BOLD}Endpoint:{Colors.RESET} {result.endpoint}")
            print(f"{Colors.CYAN}Timestamp:{Colors.RESET} {result.timestamp.strftime('%Y-%m-%d %H:%M:%S')}")
            print(f"{Colors.CYAN}Duration:{Colors.RESET} {result.duration_ms:.2f}ms")
            print(f"{Colors.CYAN}Metrics:{Colors.RESET} {result.total_metrics}")
            print(f"{Colors.CYAN}Samples:{Colors.RESET} {result.total_samples}\n")

            # Issues summary
            critical_count = sum(1 for i in result.issues if i.severity == Severity.CRITICAL)
            warning_count = sum(1 for i in result.issues if i.severity == Severity.WARNING)
            info_count = sum(1 for i in result.issues if i.severity == Severity.INFO)

            if not result.issues:
                print(f"{Colors.GREEN}{Colors.BOLD}✓ All checks passed!{Colors.RESET}\n")
            else:
                print(f"{Colors.BOLD}Issues Found:{Colors.RESET}")
                if critical_count > 0:
                    print(f"  {Colors.RED}● Critical: {critical_count}{Colors.RESET}")
                if warning_count > 0:
                    print(f"  {Colors.YELLOW}● Warnings: {warning_count}{Colors.RESET}")
                if info_count > 0:
                    print(f"  {Colors.BLUE}● Info: {info_count}{Colors.RESET}")
                print()

                # Group issues by category
                issues_by_category = defaultdict(list)
                for issue in result.issues:
                    issues_by_category[issue.category].append(issue)

                # Print issues
                for category, issues in sorted(issues_by_category.items()):
                    print(f"{Colors.BOLD}{category.upper()}:{Colors.RESET}")
                    for issue in issues:
                        color = {
                            Severity.CRITICAL: Colors.RED,
                            Severity.WARNING: Colors.YELLOW,
                            Severity.INFO: Colors.BLUE
                        }[issue.severity]

                        symbol = {
                            Severity.CRITICAL: "✗",
                            Severity.WARNING: "⚠",
                            Severity.INFO: "ℹ"
                        }[issue.severity]

                        metric_info = f" [{issue.metric_name}]" if issue.metric_name else ""
                        print(f"  {color}{symbol} {issue.message}{metric_info}{Colors.RESET}")

                        if verbose and issue.details:
                            for key, value in issue.details.items():
                                print(f"    {Colors.CYAN}{key}:{Colors.RESET} {value}")
                    print()

            print(f"{Colors.BOLD}{'-'*80}{Colors.RESET}\n")

    @staticmethod
    def print_json(results: List[ValidationResult]) -> None:
        """Print results in JSON format."""
        output = {
            "validation_time": datetime.now().isoformat(),
            "results": [result.to_dict() for result in results],
            "summary": {
                "total_endpoints": len(results),
                "passed": sum(1 for r in results if not r.has_critical and not r.has_warnings),
                "warnings": sum(1 for r in results if r.has_warnings and not r.has_critical),
                "failed": sum(1 for r in results if r.has_critical)
            }
        }
        print(json.dumps(output, indent=2))

    @staticmethod
    def print_summary(results: List[ValidationResult]) -> None:
        """Print brief summary."""
        total = len(results)
        passed = sum(1 for r in results if not r.has_critical and not r.has_warnings)
        warnings = sum(1 for r in results if r.has_warnings and not r.has_critical)
        failed = sum(1 for r in results if r.has_critical)

        print(f"\n{Colors.BOLD}Summary:{Colors.RESET}")
        print(f"  Total endpoints: {total}")
        print(f"  {Colors.GREEN}Passed: {passed}{Colors.RESET}")
        print(f"  {Colors.YELLOW}Warnings: {warnings}{Colors.RESET}")
        print(f"  {Colors.RED}Failed: {failed}{Colors.RESET}\n")


def setup_logging(verbose: bool, quiet: bool) -> None:
    """Configure logging."""
    if quiet:
        level = logging.ERROR
    elif verbose:
        level = logging.DEBUG
    else:
        level = logging.INFO

    logging.basicConfig(
        level=level,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Validate Prometheus exporter metrics and health",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Validate single exporter
  %(prog)s --endpoint http://localhost:9100/metrics

  # Validate with Prometheus integration
  %(prog)s --endpoint http://localhost:9100/metrics \\
           --prometheus http://prometheus.example.com:9090 \\
           --job node_exporter

  # Scan all exporters on a host
  %(prog)s --scan-host localhost --prometheus http://prometheus:9090

  # JSON output for automation
  %(prog)s --endpoint http://localhost:9100/metrics --json

  # CI/CD integration (exit on warnings)
  %(prog)s --endpoint http://localhost:9100/metrics --exit-on-warning

Exit Codes:
  0 - All checks passed
  1 - Warnings detected
  2 - Critical errors detected
        """
    )

    # Input options
    input_group = parser.add_mutually_exclusive_group(required=True)
    input_group.add_argument(
        '--endpoint',
        type=str,
        help='Single exporter endpoint URL'
    )
    input_group.add_argument(
        '--scan-host',
        type=str,
        help='Scan common exporter ports on host'
    )
    input_group.add_argument(
        '--endpoints-file',
        type=Path,
        help='File containing list of endpoints (one per line)'
    )

    # Prometheus integration
    parser.add_argument(
        '--prometheus',
        type=str,
        help='Prometheus server URL for integration checks'
    )
    parser.add_argument(
        '--job',
        type=str,
        help='Prometheus job name to filter targets'
    )

    # Validation thresholds
    parser.add_argument(
        '--max-cardinality',
        type=int,
        default=1000,
        help='Maximum allowed label cardinality (default: 1000)'
    )
    parser.add_argument(
        '--staleness-threshold',
        type=int,
        default=300,
        help='Maximum metric age in seconds (default: 300)'
    )
    parser.add_argument(
        '--timeout',
        type=int,
        default=10,
        help='HTTP request timeout in seconds (default: 10)'
    )

    # Output options
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )
    parser.add_argument(
        '--summary-only',
        action='store_true',
        help='Only print summary, not detailed results'
    )
    parser.add_argument(
        '--verbose',
        '-v',
        action='store_true',
        help='Enable verbose output'
    )
    parser.add_argument(
        '--quiet',
        '-q',
        action='store_true',
        help='Suppress non-error output'
    )

    # Behavior options
    parser.add_argument(
        '--exit-on-warning',
        action='store_true',
        help='Exit with code 1 on warnings (stricter CI/CD mode)'
    )

    return parser.parse_args()


def scan_common_ports(host: str) -> List[str]:
    """
    Scan common exporter ports on a host.

    Args:
        host: Hostname or IP to scan

    Returns:
        List of discovered endpoints
    """
    common_ports = {
        9100: 'node_exporter',
        9090: 'prometheus',
        9093: 'alertmanager',
        9091: 'pushgateway',
        9104: 'mysqld_exporter',
        9187: 'postgres_exporter',
        9216: 'mongodb_exporter',
        9308: 'kafka_exporter',
        9117: 'apache_exporter',
        9113: 'nginx_exporter',
    }

    endpoints = []

    for port, name in common_ports.items():
        url = f"http://{host}:{port}/metrics"
        try:
            response = requests.get(url, timeout=2)
            if response.status_code == 200:
                endpoints.append(url)
                logging.info(f"Found {name} at {url}")
        except requests.exceptions.RequestException:
            pass

    return endpoints


def main() -> int:
    """Main entry point."""
    args = parse_args()
    setup_logging(args.verbose, args.quiet)

    # Initialize validator
    validator = ExporterValidator(
        timeout=args.timeout,
        max_cardinality=args.max_cardinality,
        staleness_threshold=args.staleness_threshold
    )

    # Collect endpoints to validate
    endpoints = []

    if args.endpoint:
        endpoints.append(args.endpoint)
    elif args.scan_host:
        endpoints = scan_common_ports(args.scan_host)
        if not endpoints:
            logging.error(f"No exporters found on {args.scan_host}")
            return 2
    elif args.endpoints_file:
        try:
            with open(args.endpoints_file, 'r') as f:
                endpoints = [line.strip() for line in f if line.strip() and not line.startswith('#')]
        except Exception as e:
            logging.error(f"Failed to read endpoints file: {e}")
            return 2

    # Validate endpoints
    results = []

    for endpoint in endpoints:
        result = validator.validate_endpoint(endpoint)
        results.append(result)

    # Validate Prometheus integration if requested
    if args.prometheus:
        prom_result = validator.validate_prometheus_scraping(
            args.prometheus,
            args.job
        )
        results.append(prom_result)

    # Output results
    if args.json:
        OutputFormatter.print_json(results)
    elif args.summary_only:
        OutputFormatter.print_summary(results)
    else:
        OutputFormatter.print_human_readable(results, args.verbose)
        if not args.quiet:
            OutputFormatter.print_summary(results)

    # Determine exit code
    max_exit_code = max(r.exit_code for r in results) if results else 0

    # Apply stricter exit logic if requested
    if args.exit_on_warning and any(r.has_warnings for r in results):
        max_exit_code = max(max_exit_code, 1)

    return max_exit_code


if __name__ == '__main__':
    sys.exit(main())
