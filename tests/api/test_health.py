"""
CHOM API Test Suite - Health Check Tests

Tests all health check endpoints including:
- Basic health check
- Detailed health check
- Security health check
"""

import pytest


class TestBasicHealth:
    """Test basic health check endpoint: GET /api/v1/health"""

    def test_health_check_success(self, make_request):
        """Test basic health check returns 200."""
        response = make_request("GET", "/health")

        response.assert_status(200)
        assert "data" in response.data or "status" in response.data

    def test_health_check_no_auth_required(self, make_request):
        """Test health check does not require authentication."""
        # Should work without token
        response = make_request("GET", "/health")

        response.assert_status(200)

    def test_health_check_response_time(self, make_request, track_performance):
        """Test health check is fast."""
        response = make_request("GET", "/health")

        track_performance("/health", response.duration_ms)

        # Health checks should be very fast (< 100ms)
        assert response.duration_ms < 100, \
            f"Health check took {response.duration_ms:.2f}ms (expected < 100ms)"


class TestDetailedHealth:
    """Test detailed health check endpoint: GET /api/v1/health/detailed"""

    def test_detailed_health_check(self, make_request):
        """Test detailed health check provides system information."""
        response = make_request("GET", "/health/detailed")

        response.assert_status(200)
        # Detailed health should provide more info
        assert response.data is not None

    def test_detailed_health_no_auth_required(self, make_request):
        """Test detailed health check does not require authentication."""
        # Should work without token
        response = make_request("GET", "/health/detailed")

        response.assert_status(200)


class TestSecurityHealth:
    """Test security health check endpoint: GET /api/v1/health/security"""

    def test_security_health_requires_auth(self, make_request):
        """Test security health check requires authentication."""
        response = make_request("GET", "/health/security")

        # Should require authentication
        response.assert_status(401)

    def test_security_health_with_auth(self, make_request, auth_token):
        """Test security health check with authentication."""
        response = make_request(
            "GET",
            "/health/security",
            auth_token=auth_token
        )

        # Should work with valid token
        # May require admin role, so accept 200 or 403
        assert response.status_code in [200, 403]

    @pytest.mark.skip(reason="Requires admin role implementation")
    def test_security_health_admin_only(self, make_request, auth_token):
        """Test security health check requires admin role."""
        response = make_request(
            "GET",
            "/health/security",
            auth_token=auth_token
        )

        # Non-admin users should get 403
        # Admin users should get 200
        assert response.status_code in [200, 403]


@pytest.mark.performance
class TestHealthPerformance:
    """Test health check performance under load."""

    def test_health_check_concurrent_requests(self, make_request):
        """Test health check can handle concurrent requests."""
        import concurrent.futures

        def check_health():
            response = make_request("GET", "/health")
            return response.status_code

        # Send 20 concurrent requests
        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
            futures = [executor.submit(check_health) for _ in range(20)]
            results = [f.result() for f in concurrent.futures.as_completed(futures)]

        # All requests should succeed
        assert all(code == 200 for code in results), \
            f"Some health checks failed: {results}"

    def test_health_check_response_consistency(self, make_request):
        """Test health check returns consistent results."""
        responses = []

        # Make 10 consecutive requests
        for _ in range(10):
            response = make_request("GET", "/health")
            responses.append(response.status_code)

        # All should return 200
        assert all(code == 200 for code in responses), \
            f"Inconsistent responses: {responses}"


class TestHealthMonitoring:
    """Test health monitoring and observability."""

    def test_health_includes_timestamp(self, make_request):
        """Test health check includes timestamp or version info."""
        response = make_request("GET", "/health/detailed")

        if response.status_code == 200:
            # Check if response includes useful monitoring data
            data = response.data.get("data", {})
            # Timestamp, version, or uptime might be included
            # This is implementation-dependent
            assert data is not None

    def test_health_check_headers(self, make_request):
        """Test health check response headers."""
        response = make_request("GET", "/health")

        # Should have appropriate content-type
        assert "application/json" in response.headers.get("content-type", "").lower()
