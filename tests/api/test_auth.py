"""
CHOM API Test Suite - Authentication Tests

Tests all authentication endpoints including:
- Registration
- Login
- Logout
- Token refresh
- User profile retrieval
"""

import time
import pytest
from conftest import APIResponse


class TestRegistration:
    """Test user registration endpoint: POST /api/v1/auth/register"""

    def test_register_success(self, make_request):
        """Test successful user registration with valid data."""
        timestamp = int(time.time() * 1000)

        response = make_request(
            "POST",
            "/auth/register",
            json={
                "name": "Test User",
                "email": f"newuser_{timestamp}@chom.local",
                "password": "SecurePassword123!@#",
                "password_confirmation": "SecurePassword123!@#",
                "organization_name": f"Test Org {timestamp}",
            }
        )

        response.assert_status(201).assert_success()
        response.assert_has_field("user", "organization", "tenant", "token")

        user_data = response.data["data"]["user"]
        assert user_data["email"] == f"newuser_{timestamp}@chom.local"
        assert user_data["name"] == "Test User"
        assert user_data["role"] == "owner"

    def test_register_duplicate_email(self, make_request, registered_user):
        """Test registration fails with duplicate email."""
        response = make_request(
            "POST",
            "/auth/register",
            json={
                "name": "Another User",
                "email": registered_user.email,  # Duplicate
                "password": "SecurePassword123!@#",
                "password_confirmation": "SecurePassword123!@#",
                "organization_name": "Another Org",
            }
        )

        response.assert_status(422)
        assert not response.success

    def test_register_invalid_email_format(self, make_request):
        """Test registration fails with invalid email format."""
        response = make_request(
            "POST",
            "/auth/register",
            json={
                "name": "Test User",
                "email": "invalid-email",
                "password": "SecurePassword123!@#",
                "password_confirmation": "SecurePassword123!@#",
                "organization_name": "Test Org",
            }
        )

        response.assert_status(422)
        assert not response.success

    def test_register_missing_required_fields(self, make_request):
        """Test registration fails with missing required fields."""
        response = make_request(
            "POST",
            "/auth/register",
            json={
                "name": "Test User",
                # Missing email, password, organization_name
            }
        )

        response.assert_status(422)
        assert not response.success

    def test_register_password_too_short(self, make_request):
        """Test registration fails with password that's too short."""
        timestamp = int(time.time() * 1000)

        response = make_request(
            "POST",
            "/auth/register",
            json={
                "name": "Test User",
                "email": f"test_{timestamp}@chom.local",
                "password": "123",  # Too short
                "password_confirmation": "123",
                "organization_name": "Test Org",
            }
        )

        response.assert_status(422)
        assert not response.success

    def test_register_password_mismatch(self, make_request):
        """Test registration fails when passwords don't match."""
        timestamp = int(time.time() * 1000)

        response = make_request(
            "POST",
            "/auth/register",
            json={
                "name": "Test User",
                "email": f"test_{timestamp}@chom.local",
                "password": "SecurePassword123!@#",
                "password_confirmation": "DifferentPassword123!@#",
                "organization_name": "Test Org",
            }
        )

        response.assert_status(422)
        assert not response.success


class TestLogin:
    """Test user login endpoint: POST /api/v1/auth/login"""

    def test_login_success(self, make_request, registered_user):
        """Test successful login with valid credentials."""
        response = make_request(
            "POST",
            "/auth/login",
            json={
                "email": registered_user.email,
                "password": registered_user.password,
            }
        )

        response.assert_status(200).assert_success()
        response.assert_has_field("user", "organization", "token")

        assert response.data["data"]["user"]["email"] == registered_user.email
        assert "token" in response.data["data"]

    def test_login_invalid_credentials(self, make_request, registered_user):
        """Test login fails with invalid credentials."""
        response = make_request(
            "POST",
            "/auth/login",
            json={
                "email": registered_user.email,
                "password": "WrongPassword123!@#",
            }
        )

        response.assert_status(401)
        assert not response.success
        assert response.error["code"] == "INVALID_CREDENTIALS"

    def test_login_nonexistent_user(self, make_request):
        """Test login fails with nonexistent user."""
        response = make_request(
            "POST",
            "/auth/login",
            json={
                "email": "nonexistent@chom.local",
                "password": "SomePassword123!@#",
            }
        )

        response.assert_status(401)
        assert not response.success

    def test_login_missing_credentials(self, make_request):
        """Test login fails with missing credentials."""
        response = make_request(
            "POST",
            "/auth/login",
            json={}
        )

        response.assert_status(422)
        assert not response.success

    def test_login_missing_password(self, make_request, registered_user):
        """Test login fails with missing password."""
        response = make_request(
            "POST",
            "/auth/login",
            json={
                "email": registered_user.email,
            }
        )

        response.assert_status(422)
        assert not response.success

    @pytest.mark.rate_limit
    def test_login_rate_limiting(self, make_request, api_base_url, api_client):
        """Test rate limiting on login endpoint."""
        # The auth endpoint has rate limit: 5 req/min
        rate_limit = 5
        responses = []

        for i in range(rate_limit + 2):
            response = api_client.post(
                f"{api_base_url}/auth/login",
                json={
                    "email": f"test_{i}@chom.local",
                    "password": "password",
                }
            )
            responses.append(response.status_code)
            time.sleep(0.1)  # Small delay between requests

        # At least one request should be rate limited (429)
        assert 429 in responses, \
            f"Expected rate limiting (429) but got: {responses}"


class TestAuthenticatedEndpoints:
    """Test authenticated endpoints: /auth/me, /auth/logout, /auth/refresh"""

    def test_get_current_user(self, make_request, auth_token, registered_user):
        """Test retrieving current authenticated user."""
        response = make_request(
            "GET",
            "/auth/me",
            auth_token=auth_token
        )

        response.assert_status(200).assert_success()
        response.assert_has_field("user", "organization")

        assert response.data["data"]["user"]["email"] == registered_user.email

    def test_get_current_user_without_token(self, make_request):
        """Test /auth/me fails without authentication token."""
        response = make_request("GET", "/auth/me")

        response.assert_status(401)

    def test_get_current_user_with_invalid_token(self, make_request):
        """Test /auth/me fails with invalid token."""
        response = make_request(
            "GET",
            "/auth/me",
            auth_token="invalid-token-here"
        )

        response.assert_status(401)

    def test_logout_success(self, make_request, registered_user):
        """Test successful logout."""
        response = make_request(
            "POST",
            "/auth/logout",
            auth_token=registered_user.token
        )

        response.assert_status(200).assert_success()

        # Verify token is revoked by trying to use it
        me_response = make_request(
            "GET",
            "/auth/me",
            auth_token=registered_user.token
        )

        me_response.assert_status(401)

    def test_logout_without_token(self, make_request):
        """Test logout fails without authentication token."""
        response = make_request("POST", "/auth/logout")

        response.assert_status(401)

    def test_refresh_token(self, make_request, auth_token):
        """Test token refresh."""
        response = make_request(
            "POST",
            "/auth/refresh",
            auth_token=auth_token
        )

        response.assert_status(200).assert_success()
        response.assert_has_field("token")

        new_token = response.data["data"]["token"]
        assert new_token != auth_token

        # Verify new token works
        me_response = make_request(
            "GET",
            "/auth/me",
            auth_token=new_token
        )

        me_response.assert_status(200).assert_success()

    def test_refresh_token_without_auth(self, make_request):
        """Test token refresh fails without authentication."""
        response = make_request("POST", "/auth/refresh")

        response.assert_status(401)


class TestTokenSecurity:
    """Test token security and validation."""

    def test_token_format(self, registered_user):
        """Test token has expected format."""
        token = registered_user.token
        assert token is not None
        assert len(token) > 20  # Sanctum tokens are quite long
        assert "|" in token  # Sanctum tokens contain pipe separator

    def test_multiple_tokens_per_user(self, make_request, registered_user):
        """Test user can have multiple active tokens."""
        # Login again to get another token
        response = make_request(
            "POST",
            "/auth/login",
            json={
                "email": registered_user.email,
                "password": registered_user.password,
            }
        )

        response.assert_status(200).assert_success()
        second_token = response.data["data"]["token"]

        # Both tokens should work
        for token in [registered_user.token, second_token]:
            me_response = make_request(
                "GET",
                "/auth/me",
                auth_token=token
            )
            me_response.assert_status(200)

    def test_token_isolation(self, make_request, registered_user):
        """Test tokens are isolated between users."""
        # Create another user
        timestamp = int(time.time() * 1000)
        response = make_request(
            "POST",
            "/auth/register",
            json={
                "name": "Another User",
                "email": f"another_{timestamp}@chom.local",
                "password": "SecurePassword123!@#",
                "password_confirmation": "SecurePassword123!@#",
                "organization_name": f"Another Org {timestamp}",
            }
        )

        response.assert_status(201)
        other_token = response.data["data"]["token"]

        # Each user's token should only work for them
        user1_response = make_request(
            "GET",
            "/auth/me",
            auth_token=registered_user.token
        )
        user1_response.assert_status(200)
        user1_email = user1_response.data["data"]["user"]["email"]

        user2_response = make_request(
            "GET",
            "/auth/me",
            auth_token=other_token
        )
        user2_response.assert_status(200)
        user2_email = user2_response.data["data"]["user"]["email"]

        assert user1_email != user2_email


@pytest.mark.performance
class TestAuthPerformance:
    """Test authentication endpoint performance."""

    def test_login_performance(self, make_request, registered_user, track_performance):
        """Test login response time is acceptable."""
        response = make_request(
            "POST",
            "/auth/login",
            json={
                "email": registered_user.email,
                "password": registered_user.password,
            }
        )

        track_performance("/auth/login", response.duration_ms)

        # Login should be fast (< 500ms)
        assert response.duration_ms < 500, \
            f"Login took {response.duration_ms:.2f}ms (expected < 500ms)"

    def test_me_endpoint_performance(self, make_request, auth_token, track_performance):
        """Test /auth/me response time is acceptable."""
        response = make_request(
            "GET",
            "/auth/me",
            auth_token=auth_token
        )

        track_performance("/auth/me", response.duration_ms)

        # Simple GET should be very fast (< 200ms)
        assert response.duration_ms < 200, \
            f"/auth/me took {response.duration_ms:.2f}ms (expected < 200ms)"
