"""
CHOM API Test Suite - Utility Functions

This module provides utility functions for API testing.
"""

import time
import random
import string
from typing import Dict, Any, Optional, List
from datetime import datetime, timedelta


def generate_random_email(prefix: str = "test") -> str:
    """
    Generate a unique random email address.

    Args:
        prefix: Email prefix (default: "test")

    Returns:
        str: Random email address

    Example:
        >>> email = generate_random_email("user")
        >>> print(email)
        user_1640995200123_abc@chom.local
    """
    timestamp = int(time.time() * 1000)
    random_suffix = ''.join(random.choices(string.ascii_lowercase, k=3))
    return f"{prefix}_{timestamp}_{random_suffix}@chom.local"


def generate_random_domain(prefix: str = "test") -> str:
    """
    Generate a unique random domain name.

    Args:
        prefix: Domain prefix (default: "test")

    Returns:
        str: Random domain name

    Example:
        >>> domain = generate_random_domain("site")
        >>> print(domain)
        site-1640995200123-abc.example.com
    """
    timestamp = int(time.time() * 1000)
    random_suffix = ''.join(random.choices(string.ascii_lowercase, k=3))
    return f"{prefix}-{timestamp}-{random_suffix}.example.com"


def generate_random_string(length: int = 10, include_numbers: bool = True) -> str:
    """
    Generate a random alphanumeric string.

    Args:
        length: Length of the string
        include_numbers: Include numbers in the string

    Returns:
        str: Random string

    Example:
        >>> s = generate_random_string(8)
        >>> len(s)
        8
    """
    chars = string.ascii_letters
    if include_numbers:
        chars += string.digits

    return ''.join(random.choices(chars, k=length))


def wait_for_condition(
    condition_func: callable,
    timeout: int = 30,
    interval: float = 1.0,
    error_message: str = "Timeout waiting for condition"
) -> bool:
    """
    Wait for a condition to become true.

    Args:
        condition_func: Function that returns True when condition is met
        timeout: Maximum time to wait in seconds
        interval: Check interval in seconds
        error_message: Error message if timeout occurs

    Returns:
        bool: True if condition met, False if timeout

    Example:
        >>> def is_ready():
        ...     return check_api_status() == "ready"
        >>> wait_for_condition(is_ready, timeout=60)
    """
    start_time = time.time()

    while time.time() - start_time < timeout:
        if condition_func():
            return True
        time.sleep(interval)

    raise TimeoutError(error_message)


def assert_valid_uuid(value: str) -> None:
    """
    Assert that a string is a valid UUID.

    Args:
        value: String to validate

    Raises:
        AssertionError: If not a valid UUID
    """
    import uuid
    try:
        uuid.UUID(value)
    except ValueError:
        raise AssertionError(f"Invalid UUID: {value}")


def assert_valid_iso8601(value: str) -> None:
    """
    Assert that a string is a valid ISO 8601 datetime.

    Args:
        value: String to validate

    Raises:
        AssertionError: If not a valid ISO 8601 datetime
    """
    try:
        datetime.fromisoformat(value.replace('Z', '+00:00'))
    except ValueError:
        raise AssertionError(f"Invalid ISO 8601 datetime: {value}")


def assert_valid_email(value: str) -> None:
    """
    Assert that a string is a valid email address.

    Args:
        value: String to validate

    Raises:
        AssertionError: If not a valid email
    """
    import re
    email_pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'

    if not re.match(email_pattern, value):
        raise AssertionError(f"Invalid email: {value}")


def assert_valid_url(value: str, require_https: bool = False) -> None:
    """
    Assert that a string is a valid URL.

    Args:
        value: String to validate
        require_https: Require HTTPS scheme

    Raises:
        AssertionError: If not a valid URL
    """
    import re

    if require_https:
        url_pattern = r'^https://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'
    else:
        url_pattern = r'^https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'

    if not re.match(url_pattern, value):
        raise AssertionError(f"Invalid URL: {value}")


def parse_pagination(response_data: Dict[str, Any]) -> Dict[str, int]:
    """
    Extract pagination information from API response.

    Args:
        response_data: API response data

    Returns:
        dict: Pagination info with current_page, per_page, total, total_pages

    Example:
        >>> data = {"meta": {"pagination": {"current_page": 1, "total": 50}}}
        >>> info = parse_pagination(data)
        >>> print(info["current_page"])
        1
    """
    meta = response_data.get("meta", {})
    pagination = meta.get("pagination", {})

    return {
        "current_page": pagination.get("current_page", 1),
        "per_page": pagination.get("per_page", 20),
        "total": pagination.get("total", 0),
        "total_pages": pagination.get("total_pages", 0),
    }


def calculate_response_stats(durations: List[float]) -> Dict[str, float]:
    """
    Calculate statistics for response time durations.

    Args:
        durations: List of response times in milliseconds

    Returns:
        dict: Statistics including min, max, avg, p50, p95, p99

    Example:
        >>> durations = [100, 150, 200, 250, 300]
        >>> stats = calculate_response_stats(durations)
        >>> print(f"Average: {stats['avg']:.2f}ms")
    """
    if not durations:
        return {
            "min": 0,
            "max": 0,
            "avg": 0,
            "p50": 0,
            "p95": 0,
            "p99": 0,
        }

    sorted_durations = sorted(durations)
    count = len(sorted_durations)

    return {
        "min": sorted_durations[0],
        "max": sorted_durations[-1],
        "avg": sum(sorted_durations) / count,
        "p50": sorted_durations[int(count * 0.50)],
        "p95": sorted_durations[int(count * 0.95)],
        "p99": sorted_durations[int(count * 0.99)],
    }


def format_bytes(bytes_value: int) -> str:
    """
    Format bytes into human-readable string.

    Args:
        bytes_value: Number of bytes

    Returns:
        str: Formatted string (e.g., "1.5 MB")

    Example:
        >>> format_bytes(1536000)
        '1.46 MB'
    """
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_value < 1024.0:
            return f"{bytes_value:.2f} {unit}"
        bytes_value /= 1024.0

    return f"{bytes_value:.2f} PB"


def format_duration(seconds: float) -> str:
    """
    Format duration into human-readable string.

    Args:
        seconds: Duration in seconds

    Returns:
        str: Formatted string (e.g., "2m 30s")

    Example:
        >>> format_duration(150)
        '2m 30s'
    """
    if seconds < 60:
        return f"{seconds:.1f}s"

    minutes = int(seconds // 60)
    remaining_seconds = seconds % 60

    if minutes < 60:
        return f"{minutes}m {remaining_seconds:.0f}s"

    hours = int(minutes // 60)
    remaining_minutes = minutes % 60

    return f"{hours}h {remaining_minutes}m"


class ResponseTimer:
    """
    Context manager for timing API responses.

    Example:
        >>> with ResponseTimer() as timer:
        ...     response = make_api_call()
        >>> print(f"Request took {timer.duration_ms:.2f}ms")
    """

    def __init__(self):
        self.start_time: Optional[float] = None
        self.end_time: Optional[float] = None
        self.duration_ms: float = 0

    def __enter__(self):
        self.start_time = time.time()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.end_time = time.time()
        self.duration_ms = (self.end_time - self.start_time) * 1000


class TestDataFactory:
    """
    Factory for generating test data.

    Example:
        >>> factory = TestDataFactory()
        >>> user_data = factory.create_user_data()
        >>> site_data = factory.create_site_data()
    """

    @staticmethod
    def create_user_data(
        name: Optional[str] = None,
        email: Optional[str] = None,
        password: str = "SecurePassword123!@#"
    ) -> Dict[str, str]:
        """Create test user data."""
        return {
            "name": name or f"Test User {generate_random_string(4)}",
            "email": email or generate_random_email("user"),
            "password": password,
            "password_confirmation": password,
        }

    @staticmethod
    def create_organization_data(name: Optional[str] = None) -> Dict[str, str]:
        """Create test organization data."""
        return {
            "organization_name": name or f"Test Org {generate_random_string(4)}",
        }

    @staticmethod
    def create_site_data(
        domain: Optional[str] = None,
        site_type: str = "wordpress",
        php_version: str = "8.2"
    ) -> Dict[str, Any]:
        """Create test site data."""
        return {
            "domain": domain or generate_random_domain("site"),
            "site_type": site_type,
            "php_version": php_version,
            "ssl_enabled": True,
        }

    @staticmethod
    def create_backup_data(
        site_id: str,
        backup_type: str = "full",
        retention_days: int = 30
    ) -> Dict[str, Any]:
        """Create test backup data."""
        return {
            "site_id": site_id,
            "backup_type": backup_type,
            "retention_days": retention_days,
        }


def print_test_summary(
    total_tests: int,
    passed: int,
    failed: int,
    skipped: int,
    duration: float
) -> None:
    """
    Print formatted test summary.

    Args:
        total_tests: Total number of tests
        passed: Number of passed tests
        failed: Number of failed tests
        skipped: Number of skipped tests
        duration: Total duration in seconds
    """
    print("\n" + "="*70)
    print("TEST SUMMARY")
    print("="*70)
    print(f"Total Tests: {total_tests}")
    print(f"Passed: {passed} ({passed/total_tests*100:.1f}%)")
    print(f"Failed: {failed} ({failed/total_tests*100:.1f}%)")
    print(f"Skipped: {skipped} ({skipped/total_tests*100:.1f}%)")
    print(f"Duration: {format_duration(duration)}")
    print("="*70 + "\n")
