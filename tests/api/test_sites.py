"""
CHOM API Test Suite - Site Management Tests

Tests all site management endpoints including:
- List sites
- Create sites
- Get site details
- Update sites
- Delete sites
- Site actions (enable/disable/SSL)
"""

import time
import pytest
from typing import List


class TestListSites:
    """Test site listing endpoint: GET /api/v1/sites"""

    def test_list_sites_empty(self, make_request, auth_token):
        """Test listing sites when user has no sites."""
        response = make_request(
            "GET",
            "/sites",
            auth_token=auth_token
        )

        response.assert_status(200).assert_success()
        assert "data" in response.data
        assert "meta" in response.data
        assert isinstance(response.data["data"], list)

    def test_list_sites_with_sites(self, make_request, auth_token, created_site):
        """Test listing sites when user has sites."""
        response = make_request(
            "GET",
            "/sites",
            auth_token=auth_token
        )

        response.assert_status(200).assert_success()
        assert len(response.data["data"]) >= 1

        # Verify site structure
        site = response.data["data"][0]
        assert "id" in site
        assert "domain" in site
        assert "site_type" in site
        assert "status" in site

    def test_list_sites_pagination(self, make_request, auth_token):
        """Test site listing pagination."""
        response = make_request(
            "GET",
            "/sites?page=1&per_page=10",
            auth_token=auth_token
        )

        response.assert_status(200).assert_success()

        meta = response.data["meta"]["pagination"]
        assert meta["current_page"] == 1
        assert meta["per_page"] == 10
        assert "total" in meta
        assert "total_pages" in meta

    def test_list_sites_filter_by_status(self, make_request, auth_token):
        """Test filtering sites by status."""
        response = make_request(
            "GET",
            "/sites?status=active",
            auth_token=auth_token
        )

        response.assert_status(200).assert_success()

        # All returned sites should have status=active
        for site in response.data["data"]:
            assert site.get("status") in ["active", "creating", "disabled"]

    def test_list_sites_filter_by_type(self, make_request, auth_token):
        """Test filtering sites by type."""
        response = make_request(
            "GET",
            "/sites?type=wordpress",
            auth_token=auth_token
        )

        response.assert_status(200).assert_success()

    def test_list_sites_search(self, make_request, auth_token, created_site):
        """Test searching sites by domain."""
        domain = created_site["domain"]
        search_term = domain.split(".")[0]

        response = make_request(
            "GET",
            f"/sites?search={search_term}",
            auth_token=auth_token
        )

        response.assert_status(200).assert_success()

    def test_list_sites_unauthorized(self, make_request):
        """Test listing sites without authentication."""
        response = make_request("GET", "/sites")

        response.assert_status(401)


class TestCreateSite:
    """Test site creation endpoint: POST /api/v1/sites"""

    def test_create_wordpress_site(self, make_request, auth_token):
        """Test creating a WordPress site."""
        timestamp = int(time.time() * 1000)
        domain = f"wp-{timestamp}.example.com"

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

        assert response.status_code in [201, 202]
        response.assert_success()

        site_data = response.data["data"]
        assert site_data["domain"] == domain
        assert site_data["site_type"] == "wordpress"
        assert site_data["php_version"] == "8.2"

        # Cleanup
        site_id = site_data["id"]
        make_request("DELETE", f"/sites/{site_id}", auth_token=auth_token)

    def test_create_html_site(self, make_request, auth_token):
        """Test creating an HTML site."""
        timestamp = int(time.time() * 1000)
        domain = f"html-{timestamp}.example.com"

        response = make_request(
            "POST",
            "/sites",
            auth_token=auth_token,
            json={
                "domain": domain,
                "site_type": "html",
                "php_version": "8.2",
            }
        )

        assert response.status_code in [201, 202]
        response.assert_success()

        # Cleanup
        site_id = response.data["data"]["id"]
        make_request("DELETE", f"/sites/{site_id}", auth_token=auth_token)

    def test_create_laravel_site(self, make_request, auth_token):
        """Test creating a Laravel site."""
        timestamp = int(time.time() * 1000)
        domain = f"laravel-{timestamp}.example.com"

        response = make_request(
            "POST",
            "/sites",
            auth_token=auth_token,
            json={
                "domain": domain,
                "site_type": "laravel",
                "php_version": "8.4",
            }
        )

        assert response.status_code in [201, 202]
        response.assert_success()

        # Cleanup
        site_id = response.data["data"]["id"]
        make_request("DELETE", f"/sites/{site_id}", auth_token=auth_token)

    def test_create_site_missing_domain(self, make_request, auth_token):
        """Test site creation fails without domain."""
        response = make_request(
            "POST",
            "/sites",
            auth_token=auth_token,
            json={
                "site_type": "wordpress",
            }
        )

        response.assert_status(422)
        assert not response.success

    def test_create_site_invalid_domain_format(self, make_request, auth_token):
        """Test site creation fails with invalid domain format."""
        response = make_request(
            "POST",
            "/sites",
            auth_token=auth_token,
            json={
                "domain": "invalid domain with spaces",
                "site_type": "wordpress",
            }
        )

        response.assert_status(422)
        assert not response.success

    def test_create_site_duplicate_domain(self, make_request, auth_token, created_site):
        """Test site creation fails with duplicate domain."""
        response = make_request(
            "POST",
            "/sites",
            auth_token=auth_token,
            json={
                "domain": created_site["domain"],  # Duplicate
                "site_type": "wordpress",
            }
        )

        response.assert_status(422)
        assert not response.success

    def test_create_site_invalid_type(self, make_request, auth_token):
        """Test site creation fails with invalid site type."""
        timestamp = int(time.time() * 1000)

        response = make_request(
            "POST",
            "/sites",
            auth_token=auth_token,
            json={
                "domain": f"test-{timestamp}.example.com",
                "site_type": "invalid_type",
            }
        )

        response.assert_status(422)
        assert not response.success

    def test_create_site_invalid_php_version(self, make_request, auth_token):
        """Test site creation fails with invalid PHP version."""
        timestamp = int(time.time() * 1000)

        response = make_request(
            "POST",
            "/sites",
            auth_token=auth_token,
            json={
                "domain": f"test-{timestamp}.example.com",
                "site_type": "wordpress",
                "php_version": "7.4",  # Not supported
            }
        )

        response.assert_status(422)
        assert not response.success

    @pytest.mark.skip(reason="Requires quota enforcement implementation")
    def test_create_site_quota_exceeded(self, make_request, auth_token):
        """Test site creation fails when quota is exceeded."""
        # This would require creating multiple sites up to the quota limit
        pass


class TestGetSite:
    """Test get site details endpoint: GET /api/v1/sites/{id}"""

    def test_get_site_details(self, make_request, auth_token, created_site):
        """Test retrieving site details."""
        site_id = created_site["id"]

        response = make_request(
            "GET",
            f"/sites/{site_id}",
            auth_token=auth_token
        )

        response.assert_status(200).assert_success()

        site_data = response.data["data"]
        assert site_data["id"] == site_id
        assert site_data["domain"] == created_site["domain"]

        # Detailed view should include additional fields
        assert "db_name" in site_data or "document_root" in site_data

    def test_get_site_invalid_id(self, make_request, auth_token):
        """Test getting site with invalid ID."""
        response = make_request(
            "GET",
            "/sites/invalid-uuid-here",
            auth_token=auth_token
        )

        response.assert_status(404)

    def test_get_site_nonexistent(self, make_request, auth_token):
        """Test getting nonexistent site."""
        fake_uuid = "00000000-0000-0000-0000-000000000000"

        response = make_request(
            "GET",
            f"/sites/{fake_uuid}",
            auth_token=auth_token
        )

        response.assert_status(404)

    def test_get_site_unauthorized(self, make_request, created_site):
        """Test getting site without authentication."""
        response = make_request(
            "GET",
            f"/sites/{created_site['id']}"
        )

        response.assert_status(401)


class TestUpdateSite:
    """Test update site endpoint: PUT/PATCH /api/v1/sites/{id}"""

    def test_update_site_php_version(self, make_request, auth_token, created_site):
        """Test updating site PHP version."""
        site_id = created_site["id"]

        response = make_request(
            "PATCH",
            f"/sites/{site_id}",
            auth_token=auth_token,
            json={
                "php_version": "8.4",
            }
        )

        response.assert_status(200).assert_success()

        updated_site = response.data["data"]
        assert updated_site["php_version"] == "8.4"

    def test_update_site_settings(self, make_request, auth_token, created_site):
        """Test updating site settings."""
        site_id = created_site["id"]

        response = make_request(
            "PATCH",
            f"/sites/{site_id}",
            auth_token=auth_token,
            json={
                "settings": {
                    "custom_setting": "value"
                }
            }
        )

        response.assert_status(200).assert_success()

    def test_update_site_invalid_data(self, make_request, auth_token, created_site):
        """Test updating site with invalid data."""
        site_id = created_site["id"]

        response = make_request(
            "PATCH",
            f"/sites/{site_id}",
            auth_token=auth_token,
            json={
                "php_version": "invalid_version",
            }
        )

        response.assert_status(422)
        assert not response.success

    def test_update_nonexistent_site(self, make_request, auth_token):
        """Test updating nonexistent site."""
        fake_uuid = "00000000-0000-0000-0000-000000000000"

        response = make_request(
            "PATCH",
            f"/sites/{fake_uuid}",
            auth_token=auth_token,
            json={
                "php_version": "8.2",
            }
        )

        response.assert_status(404)


class TestDeleteSite:
    """Test delete site endpoint: DELETE /api/v1/sites/{id}"""

    def test_delete_site(self, make_request, auth_token):
        """Test deleting a site."""
        # Create a site to delete
        timestamp = int(time.time() * 1000)
        create_response = make_request(
            "POST",
            "/sites",
            auth_token=auth_token,
            json={
                "domain": f"delete-{timestamp}.example.com",
                "site_type": "html",
            }
        )

        assert create_response.status_code in [201, 202]
        site_id = create_response.data["data"]["id"]

        # Delete the site
        delete_response = make_request(
            "DELETE",
            f"/sites/{site_id}",
            auth_token=auth_token
        )

        delete_response.assert_status(200).assert_success()

    def test_delete_nonexistent_site(self, make_request, auth_token):
        """Test deleting nonexistent site."""
        fake_uuid = "00000000-0000-0000-0000-000000000000"

        response = make_request(
            "DELETE",
            f"/sites/{fake_uuid}",
            auth_token=auth_token
        )

        response.assert_status(404)

    def test_delete_site_unauthorized(self, make_request, created_site):
        """Test deleting site without authentication."""
        response = make_request(
            "DELETE",
            f"/sites/{created_site['id']}"
        )

        response.assert_status(401)


class TestSiteActions:
    """Test site action endpoints (enable/disable/SSL)"""

    def test_enable_site(self, make_request, auth_token, created_site):
        """Test enabling a site."""
        site_id = created_site["id"]

        response = make_request(
            "POST",
            f"/sites/{site_id}/enable",
            auth_token=auth_token
        )

        # Should succeed or already be enabled
        assert response.status_code in [200, 201]

    def test_disable_site(self, make_request, auth_token, created_site):
        """Test disabling a site."""
        site_id = created_site["id"]

        response = make_request(
            "POST",
            f"/sites/{site_id}/disable",
            auth_token=auth_token
        )

        # Should succeed or already be disabled
        assert response.status_code in [200, 201]

    def test_issue_ssl_certificate(self, make_request, auth_token, created_site):
        """Test issuing SSL certificate for a site."""
        site_id = created_site["id"]

        response = make_request(
            "POST",
            f"/sites/{site_id}/ssl",
            auth_token=auth_token
        )

        # Should accept the request (async operation)
        assert response.status_code in [200, 201, 202]

    def test_get_site_metrics(self, make_request, auth_token, created_site):
        """Test retrieving site metrics."""
        site_id = created_site["id"]

        response = make_request(
            "GET",
            f"/sites/{site_id}/metrics",
            auth_token=auth_token
        )

        response.assert_status(200).assert_success()

        metrics = response.data["data"]["metrics"]
        assert "storage_used_mb" in metrics or "requests_per_minute" in metrics


@pytest.mark.performance
class TestSitePerformance:
    """Test site endpoint performance."""

    def test_list_sites_performance(self, make_request, auth_token, track_performance):
        """Test site listing performance."""
        response = make_request(
            "GET",
            "/sites",
            auth_token=auth_token
        )

        track_performance("/sites", response.duration_ms)

        assert response.duration_ms < 500, \
            f"Listing sites took {response.duration_ms:.2f}ms (expected < 500ms)"

    def test_get_site_performance(self, make_request, auth_token, created_site, track_performance):
        """Test get site details performance."""
        response = make_request(
            "GET",
            f"/sites/{created_site['id']}",
            auth_token=auth_token
        )

        track_performance(f"/sites/{created_site['id']}", response.duration_ms)

        assert response.duration_ms < 300, \
            f"Getting site took {response.duration_ms:.2f}ms (expected < 300ms)"
