"""
CHOM API Test Suite - Pytest Configuration and Fixtures

This module provides shared fixtures and configuration for all API tests.
"""

import os
import time
from typing import Dict, Any, Optional, Generator
from dataclasses import dataclass

import pytest
import requests
from dotenv import load_dotenv

# Load test environment variables
load_dotenv(".env.testing")

# ============================================================================
# Configuration
# ============================================================================

API_BASE_URL = os.getenv("API_BASE_URL", "http://localhost:8000/api/v1")
API_TIMEOUT = int(os.getenv("API_TIMEOUT", "30"))
TEST_USER_EMAIL = os.getenv("TEST_USER_EMAIL", "test@chom.local")
TEST_USER_PASSWORD = os.getenv("TEST_USER_PASSWORD", "Test123!@#Password")
TEST_USER_NAME = os.getenv("TEST_USER_NAME", "Test User")
TEST_ORG_NAME = os.getenv("TEST_ORG_NAME", "Test Organization")


# ============================================================================
# Data Classes
# ============================================================================

@dataclass
class AuthCredentials:
    """Authentication credentials for test users."""
    email: str
    password: str
    name: str
    token: Optional[str] = None
    user_id: Optional[str] = None
    org_id: Optional[str] = None


@dataclass
class APIResponse:
    """Wrapper for API responses with common assertions."""
    status_code: int
    data: Dict[str, Any]
    headers: Dict[str, str]
    duration_ms: float

    @property
    def success(self) -> bool:
        """Check if response indicates success."""
        return self.data.get("success", False)

    @property
    def error(self) -> Optional[Dict[str, Any]]:
        """Get error details if present."""
        return self.data.get("error")

    def assert_success(self) -> "APIResponse":
        """Assert response was successful."""
        assert self.success, f"API call failed: {self.error}"
        return self

    def assert_status(self, expected: int) -> "APIResponse":
        """Assert specific status code."""
        assert self.status_code == expected, \
            f"Expected status {expected}, got {self.status_code}"
        return self

    def assert_has_field(self, *fields: str) -> "APIResponse":
        """Assert response data contains specified fields."""
        response_data = self.data.get("data", {})
        for field in fields:
            assert field in response_data, f"Missing field: {field}"
        return self


# ============================================================================
# Core Fixtures
# ============================================================================

@pytest.fixture(scope="session")
def api_base_url() -> str:
    """Get API base URL."""
    return API_BASE_URL


@pytest.fixture(scope="function")
def api_client() -> requests.Session:
    """
    Create a fresh requests session for each test.

    Provides clean state for each test with proper timeout configuration.
    """
    session = requests.Session()
    session.timeout = API_TIMEOUT
    return session


@pytest.fixture(scope="function")
def api_headers() -> Dict[str, str]:
    """Get default API headers."""
    return {
        "Content-Type": "application/json",
        "Accept": "application/json",
    }


# ============================================================================
# Authentication Fixtures
# ============================================================================

@pytest.fixture(scope="function")
def test_credentials() -> AuthCredentials:
    """Get test user credentials."""
    return AuthCredentials(
        email=TEST_USER_EMAIL,
        password=TEST_USER_PASSWORD,
        name=TEST_USER_NAME,
    )


@pytest.fixture(scope="function")
def registered_user(
    api_client: requests.Session,
    api_base_url: str,
    test_credentials: AuthCredentials
) -> Generator[AuthCredentials, None, None]:
    """
    Register a new test user and provide credentials.

    Automatically cleans up the user after the test.
    """
    # Generate unique email for this test
    timestamp = int(time.time() * 1000)
    unique_email = f"test_{timestamp}@chom.local"

    creds = AuthCredentials(
        email=unique_email,
        password=test_credentials.password,
        name=test_credentials.name,
    )

    # Register user
    response = api_client.post(
        f"{api_base_url}/auth/register",
        json={
            "name": creds.name,
            "email": creds.email,
            "password": creds.password,
            "password_confirmation": creds.password,
            "organization_name": f"{TEST_ORG_NAME} {timestamp}",
        }
    )

    if response.status_code == 201:
        data = response.json().get("data", {})
        creds.token = data.get("token")
        creds.user_id = data.get("user", {}).get("id")
        creds.org_id = data.get("organization", {}).get("id")

    yield creds

    # Cleanup: Delete user (if cleanup is enabled)
    cleanup_enabled = os.getenv("CLEANUP_AFTER_TESTS", "true").lower() == "true"
    if cleanup_enabled and creds.token:
        try:
            # Logout and revoke token
            api_client.post(
                f"{api_base_url}/auth/logout",
                headers={"Authorization": f"Bearer {creds.token}"}
            )
        except Exception:
            pass  # Ignore cleanup errors


@pytest.fixture(scope="function")
def auth_token(registered_user: AuthCredentials) -> str:
    """
    Get authentication token for a registered user.

    This is the most commonly used fixture for authenticated requests.
    """
    assert registered_user.token, "User registration failed"
    return registered_user.token


@pytest.fixture(scope="function")
def auth_headers(auth_token: str, api_headers: Dict[str, str]) -> Dict[str, str]:
    """Get headers with authentication token."""
    headers = api_headers.copy()
    headers["Authorization"] = f"Bearer {auth_token}"
    return headers


# ============================================================================
# Helper Fixtures
# ============================================================================

@pytest.fixture(scope="function")
def make_request(
    api_client: requests.Session,
    api_base_url: str,
    api_headers: Dict[str, str]
):
    """
    Factory fixture for making API requests with automatic timing.

    Example:
        response = make_request("GET", "/sites", auth_token=token)
        response.assert_success().assert_status(200)
    """
    def _make_request(
        method: str,
        endpoint: str,
        auth_token: Optional[str] = None,
        **kwargs
    ) -> APIResponse:
        """Make an API request and return wrapped response."""
        # Prepare headers
        headers = api_headers.copy()
        if auth_token:
            headers["Authorization"] = f"Bearer {auth_token}"

        # Merge with custom headers
        if "headers" in kwargs:
            headers.update(kwargs.pop("headers"))

        # Build full URL
        url = f"{api_base_url}{endpoint}"

        # Time the request
        start_time = time.time()
        response = api_client.request(
            method=method.upper(),
            url=url,
            headers=headers,
            timeout=API_TIMEOUT,
            **kwargs
        )
        duration_ms = (time.time() - start_time) * 1000

        # Parse JSON response
        try:
            data = response.json()
        except ValueError:
            data = {}

        return APIResponse(
            status_code=response.status_code,
            data=data,
            headers=dict(response.headers),
            duration_ms=duration_ms,
        )

    return _make_request


# ============================================================================
# Resource Creation Fixtures
# ============================================================================

@pytest.fixture(scope="function")
def created_site(
    make_request,
    auth_token: str
) -> Generator[Dict[str, Any], None, None]:
    """
    Create a test site and provide its data.

    Automatically cleans up the site after the test.
    """
    # Create unique domain
    timestamp = int(time.time() * 1000)
    domain = f"test-{timestamp}.example.com"

    # Create site
    response = make_request(
        "POST",
        "/sites",
        auth_token=auth_token,
        json={
            "domain": domain,
            "site_type": "wordpress",
            "php_version": "8.2",
            "ssl_enabled": True,
        }
    )

    assert response.status_code in [201, 202], \
        f"Site creation failed: {response.data}"

    site_data = response.data.get("data", {})
    site_id = site_data.get("id")

    yield site_data

    # Cleanup: Delete site
    cleanup_enabled = os.getenv("CLEANUP_AFTER_TESTS", "true").lower() == "true"
    if cleanup_enabled and site_id:
        try:
            make_request(
                "DELETE",
                f"/sites/{site_id}",
                auth_token=auth_token
            )
        except Exception:
            pass  # Ignore cleanup errors


# ============================================================================
# Performance Tracking
# ============================================================================

@pytest.fixture(scope="function")
def track_performance():
    """Track and report API performance metrics."""
    metrics = []

    def _track(endpoint: str, duration_ms: float):
        metrics.append({"endpoint": endpoint, "duration_ms": duration_ms})

    yield _track

    # Report slow endpoints after test
    threshold = float(os.getenv("PERF_THRESHOLD_P95", "500"))
    slow_requests = [m for m in metrics if m["duration_ms"] > threshold]

    if slow_requests:
        print(f"\nSlow API calls (>{threshold}ms):")
        for metric in slow_requests:
            print(f"  {metric['endpoint']}: {metric['duration_ms']:.2f}ms")


# ============================================================================
# Pytest Hooks
# ============================================================================

def pytest_configure(config):
    """Configure pytest environment."""
    # Create reports directory
    os.makedirs("reports", exist_ok=True)
    os.makedirs("htmlcov", exist_ok=True)


def pytest_collection_modifyitems(config, items):
    """Modify test collection to add markers."""
    for item in items:
        # Add markers based on file path
        if "test_auth" in str(item.fspath):
            item.add_marker(pytest.mark.auth)
        elif "test_sites" in str(item.fspath):
            item.add_marker(pytest.mark.sites)
        elif "test_backups" in str(item.fspath):
            item.add_marker(pytest.mark.backups)
        elif "test_team" in str(item.fspath):
            item.add_marker(pytest.mark.team)
        elif "test_health" in str(item.fspath):
            item.add_marker(pytest.mark.health)
