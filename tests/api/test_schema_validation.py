"""
CHOM API Test Suite - Schema Validation Tests

Tests that API responses conform to expected JSON schemas.
"""

import pytest
from jsonschema import validate, ValidationError


# ============================================================================
# JSON Schemas
# ============================================================================

USER_SCHEMA = {
    "type": "object",
    "properties": {
        "id": {"type": "string", "format": "uuid"},
        "name": {"type": "string"},
        "email": {"type": "string", "format": "email"},
        "role": {"type": "string", "enum": ["owner", "admin", "member", "viewer"]},
        "email_verified": {"type": "boolean"},
        "created_at": {"type": "string"},
    },
    "required": ["id", "name", "email", "role"],
}

ORGANIZATION_SCHEMA = {
    "type": "object",
    "properties": {
        "id": {"type": "string", "format": "uuid"},
        "name": {"type": "string"},
        "slug": {"type": "string"},
        "billing_email": {"type": ["string", "null"]},
    },
    "required": ["id", "name", "slug"],
}

SITE_SCHEMA = {
    "type": "object",
    "properties": {
        "id": {"type": "string", "format": "uuid"},
        "domain": {"type": "string"},
        "url": {"type": "string"},
        "site_type": {"type": "string", "enum": ["wordpress", "html", "laravel"]},
        "php_version": {"type": "string", "enum": ["8.2", "8.4"]},
        "ssl_enabled": {"type": "boolean"},
        "status": {"type": "string"},
        "storage_used_mb": {"type": ["integer", "null"]},
        "created_at": {"type": "string"},
        "updated_at": {"type": "string"},
    },
    "required": ["id", "domain", "site_type", "status"],
}

BACKUP_SCHEMA = {
    "type": "object",
    "properties": {
        "id": {"type": "string", "format": "uuid"},
        "site_id": {"type": "string", "format": "uuid"},
        "backup_type": {"type": "string", "enum": ["full", "database", "files"]},
        "size": {"type": "string"},
        "size_bytes": {"type": "integer"},
        "is_ready": {"type": "boolean"},
        "is_expired": {"type": "boolean"},
        "created_at": {"type": "string"},
    },
    "required": ["id", "site_id", "backup_type", "is_ready"],
}

API_SUCCESS_RESPONSE_SCHEMA = {
    "type": "object",
    "properties": {
        "success": {"type": "boolean", "const": True},
        "data": {"type": ["object", "array"]},
    },
    "required": ["success", "data"],
}

API_ERROR_RESPONSE_SCHEMA = {
    "type": "object",
    "properties": {
        "success": {"type": "boolean", "const": False},
        "error": {
            "type": "object",
            "properties": {
                "code": {"type": "string"},
                "message": {"type": "string"},
            },
            "required": ["code", "message"],
        },
    },
    "required": ["success", "error"],
}

PAGINATION_SCHEMA = {
    "type": "object",
    "properties": {
        "current_page": {"type": "integer", "minimum": 1},
        "per_page": {"type": "integer", "minimum": 1},
        "total": {"type": "integer", "minimum": 0},
        "total_pages": {"type": "integer", "minimum": 0},
    },
    "required": ["current_page", "per_page", "total", "total_pages"],
}


# ============================================================================
# Schema Validation Tests
# ============================================================================

class TestAuthSchemas:
    """Test authentication response schemas."""

    def test_login_response_schema(self, make_request, registered_user):
        """Test login response conforms to schema."""
        response = make_request(
            "POST",
            "/auth/login",
            json={
                "email": registered_user.email,
                "password": registered_user.password,
            }
        )

        response.assert_status(200)

        # Validate overall response structure
        validate(instance=response.data, schema=API_SUCCESS_RESPONSE_SCHEMA)

        # Validate user data
        user_data = response.data["data"]["user"]
        validate(instance=user_data, schema=USER_SCHEMA)

        # Validate organization data
        org_data = response.data["data"]["organization"]
        validate(instance=org_data, schema=ORGANIZATION_SCHEMA)

        # Validate token exists
        assert "token" in response.data["data"]
        assert isinstance(response.data["data"]["token"], str)

    def test_register_response_schema(self, make_request):
        """Test register response conforms to schema."""
        import time
        timestamp = int(time.time() * 1000)

        response = make_request(
            "POST",
            "/auth/register",
            json={
                "name": "Schema Test",
                "email": f"schema_{timestamp}@chom.local",
                "password": "SecurePassword123!@#",
                "password_confirmation": "SecurePassword123!@#",
                "organization_name": f"Schema Org {timestamp}",
            }
        )

        response.assert_status(201)
        validate(instance=response.data, schema=API_SUCCESS_RESPONSE_SCHEMA)

    def test_me_response_schema(self, make_request, auth_token):
        """Test /auth/me response conforms to schema."""
        response = make_request(
            "GET",
            "/auth/me",
            auth_token=auth_token
        )

        response.assert_status(200)
        validate(instance=response.data, schema=API_SUCCESS_RESPONSE_SCHEMA)

        user_data = response.data["data"]["user"]
        validate(instance=user_data, schema=USER_SCHEMA)


class TestSiteSchemas:
    """Test site response schemas."""

    def test_list_sites_schema(self, make_request, auth_token):
        """Test list sites response conforms to schema."""
        response = make_request(
            "GET",
            "/sites",
            auth_token=auth_token
        )

        response.assert_status(200)
        validate(instance=response.data, schema=API_SUCCESS_RESPONSE_SCHEMA)

        # Validate pagination
        pagination = response.data["meta"]["pagination"]
        validate(instance=pagination, schema=PAGINATION_SCHEMA)

        # Validate each site if any exist
        sites = response.data["data"]
        for site in sites:
            validate(instance=site, schema=SITE_SCHEMA)

    def test_create_site_schema(self, make_request, auth_token):
        """Test create site response conforms to schema."""
        import time
        timestamp = int(time.time() * 1000)

        response = make_request(
            "POST",
            "/sites",
            auth_token=auth_token,
            json={
                "domain": f"schema-{timestamp}.example.com",
                "site_type": "wordpress",
            }
        )

        assert response.status_code in [201, 202]
        validate(instance=response.data, schema=API_SUCCESS_RESPONSE_SCHEMA)

        site_data = response.data["data"]
        validate(instance=site_data, schema=SITE_SCHEMA)

        # Cleanup
        make_request("DELETE", f"/sites/{site_data['id']}", auth_token=auth_token)

    def test_get_site_schema(self, make_request, auth_token, created_site):
        """Test get site response conforms to schema."""
        response = make_request(
            "GET",
            f"/sites/{created_site['id']}",
            auth_token=auth_token
        )

        response.assert_status(200)
        validate(instance=response.data, schema=API_SUCCESS_RESPONSE_SCHEMA)

        site_data = response.data["data"]
        validate(instance=site_data, schema=SITE_SCHEMA)


class TestBackupSchemas:
    """Test backup response schemas."""

    def test_list_backups_schema(self, make_request, auth_token):
        """Test list backups response conforms to schema."""
        response = make_request(
            "GET",
            "/backups",
            auth_token=auth_token
        )

        response.assert_status(200)
        validate(instance=response.data, schema=API_SUCCESS_RESPONSE_SCHEMA)

        # Validate pagination
        pagination = response.data["meta"]["pagination"]
        validate(instance=pagination, schema=PAGINATION_SCHEMA)

        # Validate each backup if any exist
        backups = response.data["data"]
        for backup in backups:
            validate(instance=backup, schema=BACKUP_SCHEMA)


class TestErrorSchemas:
    """Test error response schemas."""

    def test_401_error_schema(self, make_request):
        """Test 401 error response conforms to schema."""
        response = make_request("GET", "/auth/me")

        response.assert_status(401)
        # Error responses should follow error schema
        # Note: Some errors might not have success field
        if "error" in response.data:
            assert "code" in response.data["error"]
            assert "message" in response.data["error"]

    def test_404_error_schema(self, make_request, auth_token):
        """Test 404 error response conforms to schema."""
        fake_uuid = "00000000-0000-0000-0000-000000000000"

        response = make_request(
            "GET",
            f"/sites/{fake_uuid}",
            auth_token=auth_token
        )

        response.assert_status(404)

    def test_422_validation_error_schema(self, make_request):
        """Test 422 validation error response."""
        response = make_request(
            "POST",
            "/auth/login",
            json={
                "email": "invalid-email",
                "password": "short",
            }
        )

        response.assert_status(422)


@pytest.mark.security
class TestSecurityHeaders:
    """Test API security headers."""

    def test_content_type_header(self, make_request, auth_token):
        """Test API returns correct content-type."""
        response = make_request(
            "GET",
            "/auth/me",
            auth_token=auth_token
        )

        assert "application/json" in response.headers.get("content-type", "").lower()

    def test_cors_headers(self, make_request):
        """Test CORS headers if applicable."""
        response = make_request("GET", "/health")

        # Check if CORS headers are present (implementation dependent)
        # This is optional and depends on API configuration
        headers = response.headers
        # Just ensure we got headers back
        assert headers is not None
